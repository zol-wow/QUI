-- tests/unit/bags_bank_window_state_test.lua
-- Run: lua tests/unit/bags_bank_window_state_test.lua
-- Pure parts of the bank window: BankWindow.BuildTabList(rec, warband, opts)
-- — tab-strip assembly from the cache. Char tabs (bag IDs 6–11) sorted
-- first, warband tabs (12–16) sorted after, and a purchase marker per bank
-- type appended after that type's tabs when opts allows. Missing tab IDs
-- are skipped; an empty cache yields an empty list.
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- SetScript-recording frame fake (the gate-test idiom). bank_window creates
-- all frames lazily (EnsureWindow), so load time should never need one —
-- the fake guards against that ever changing silently.
_G.CreateFrame = function()
    local f = { _scripts = {} }
    function f.SetScript(self, which, fn) self._scripts[which] = fn end
    function f.GetScript(self, which) return self._scripts[which] end
    function f.SetSize() end
    function f.SetPoint() end
    function f.Hide() end
    function f.Show() end
    return f
end

local ns = loader.LoadAll()
ns.Helpers = { CreateDBGetter = function() return function() return {} end end }

assert(loadfile("QUI_Bags/bags/views/chassis.lua"))("QUI", ns)
local chunk = assert(loadfile("QUI_Bags/bags/views/bank_window.lua"))
chunk("QUI", ns)
local BankWindow = ns.Bags.BankWindow
assert(type(BankWindow.BuildTabList) == "function", "BuildTabList must be exported")

local CHAR = Enum.BankType.Character
local ACCOUNT = Enum.BankType.Account

-- Test 1: empty cache → empty list (nil records and empty tables alike)
assert(#BankWindow.BuildTabList(nil, nil, nil) == 0, "nil cache must yield an empty list")
assert(#BankWindow.BuildTabList({}, {}, nil) == 0, "recordless cache must yield an empty list")
assert(#BankWindow.BuildTabList({ bankTabs = {} }, { tabs = {} }, nil) == 0,
    "empty tab tables must yield an empty list")

-- Test 2: char tabs sorted by bag ID, missing IDs skipped, fields carried.
-- ≥2 real tabs of a type prepend that type's synthetic All entry
-- ({ all = true, bankType }, no bagID) before its tabs.
local rec = {
    bankTabs = {
        [8] = { size = 98, name = "Mats", icon = 222, depositFlags = 0, slots = {} },
        [6] = { size = 98, name = "One",  icon = 111, depositFlags = 0, slots = {} },
        -- 7, 9, 10, 11 not purchased → skipped
    },
}
local list = BankWindow.BuildTabList(rec, nil, nil)
assert(#list == 3, "All + two char tabs expected, got " .. #list)
assert(list[1].all == true and list[1].bankType == CHAR and list[1].bagID == nil,
    "the char All entry leads its type")
assert(list[2].bagID == 6 and list[3].bagID == 8, "char tabs must be sorted by bag ID")
assert(list[2].bankType == CHAR and list[3].bankType == CHAR, "char tabs carry BankType.Character")
assert(list[2].name == "One" and list[2].icon == 111, "tab name/icon must come from the cache")
assert(not list[2].purchase and not list[3].purchase, "real tabs carry no purchase marker")

-- Test 2b: a single tab of a type gets NO All entry (nothing to unify)
list = BankWindow.BuildTabList({ bankTabs = {
    [6] = { size = 98, name = "Solo", icon = 1, depositFlags = 0, slots = {} },
} }, nil, nil)
assert(#list == 1 and list[1].bagID == 6 and not list[1].all,
    "one tab → no All entry")

-- Test 3: warband tabs sorted, appended AFTER all char tabs (each type
-- leads with its own All entry)
local warband = {
    tabs = {
        [14] = { size = 98, name = "WB Two", icon = 444, depositFlags = 0, slots = {} },
        [12] = { size = 98, name = "WB One", icon = 333, depositFlags = 0, slots = {} },
    },
}
list = BankWindow.BuildTabList(rec, warband, nil)
assert(#list == 6, "AllC + char tabs + AllW + warband tabs expected, got " .. #list)
assert(list[2].bagID == 6 and list[3].bagID == 8, "char tabs first")
assert(list[4].all == true and list[4].bankType == ACCOUNT,
    "the warband All entry leads the warband tabs")
assert(list[5].bagID == 12 and list[6].bagID == 14, "warband tabs sorted after char tabs")
assert(list[5].bankType == ACCOUNT and list[6].bankType == ACCOUNT,
    "warband tabs carry BankType.Account")
assert(list[5].name == "WB One" and list[5].icon == 333, "warband name/icon from the cache")

-- Test 4: purchase markers appended after their own type's tabs
list = BankWindow.BuildTabList(rec, warband, { canPurchaseChar = true, canPurchaseWarband = true })
assert(#list == 8, "two purchase markers expected, got " .. #list)
assert(list[4].purchase == true and list[4].bankType == CHAR,
    "char purchase marker must follow the char tabs")
assert(list[4].bagID == nil, "purchase markers carry no bagID")
assert(list[6].bagID == 12 and list[7].bagID == 14, "warband tabs follow the char purchase marker")
assert(list[8].purchase == true and list[8].bankType == ACCOUNT,
    "warband purchase marker must come last")

-- Test 5: one-sided purchase opts
list = BankWindow.BuildTabList(rec, warband, { canPurchaseChar = true })
assert(#list == 7 and list[4].purchase and list[4].bankType == CHAR
    and list[7].bagID == 14, "char-only purchase marker")
list = BankWindow.BuildTabList(rec, warband, { canPurchaseWarband = true })
assert(#list == 7 and list[7].purchase and list[7].bankType == ACCOUNT
    and list[2].bagID == 6, "warband-only purchase marker")

-- Test 6: purchase markers appear even when that type has no tabs yet
-- (a fresh character: nothing purchased, but the + must still render)
list = BankWindow.BuildTabList({ bankTabs = {} }, { tabs = {} },
    { canPurchaseChar = true, canPurchaseWarband = true })
assert(#list == 2 and list[1].purchase and list[1].bankType == CHAR
    and list[2].purchase and list[2].bankType == ACCOUNT,
    "purchase markers must not require existing tabs")

-- Test 7: no opts table → no purchase markers (cached mode)
list = BankWindow.BuildTabList(rec, warband, nil)
for _, entry in ipairs(list) do
    assert(not entry.purchase, "cached mode (no opts) must produce no purchase markers")
end

-- Test 8: viewability gate (live mode, C_Bank.CanViewBank) — viewWarband =
-- false drops the warband tabs AND the warband purchase marker, char side
-- untouched; absent flags default to viewable (cached browse-anywhere and
-- the pure assertions above stay valid).
list = BankWindow.BuildTabList(rec, warband,
    { canPurchaseChar = true, canPurchaseWarband = true, viewWarband = false })
assert(#list == 4, "viewWarband=false must drop warband tabs + marker, got " .. #list)
assert(list[2].bagID == 6 and list[3].bagID == 8, "char tabs must survive viewWarband=false")
assert(list[4].purchase == true and list[4].bankType == CHAR,
    "the char purchase marker must survive viewWarband=false")
for _, entry in ipairs(list) do
    assert(entry.bankType == CHAR, "no warband entry may survive viewWarband=false")
end
-- symmetric: viewChar=false keeps only the warband side
list = BankWindow.BuildTabList(rec, warband,
    { canPurchaseChar = true, canPurchaseWarband = true, viewChar = false })
assert(#list == 4 and list[1].all == true and list[2].bagID == 12 and list[3].bagID == 14
    and list[4].purchase == true and list[4].bankType == ACCOUNT,
    "viewChar=false must drop char tabs + marker, keep warband")
-- absent view flags default to viewable (full list, markers included)
list = BankWindow.BuildTabList(rec, warband,
    { canPurchaseChar = true, canPurchaseWarband = true })
assert(#list == 8, "absent view flags must default to viewable")

-- Test 9: TabSettingsArgs — the UpdateBankTabSettings passthrough contract.
-- Doc: tabIcon is cstring (Nilable=false) while BankTabData.icon is fileID;
-- Blizzard passes the fileID through and falls back to QUESTION_MARK_ICON,
-- never 0 (0 renders a broken icon and is not a valid icon cstring).
_G.QUESTION_MARK_ICON = "QM_FALLBACK"
local name, icon, flags = BankWindow.TabSettingsArgs({ icon = 222, depositFlags = 5 }, "NewName")
assert(name == "NewName", "TabSettingsArgs must pass the new name through")
assert(icon == 222, "cached fileID must pass through (cstring coerces numbers)")
assert(flags == 5, "cached depositFlags must pass through")
name, icon, flags = BankWindow.TabSettingsArgs({}, "X")
assert(icon == "QM_FALLBACK", "missing icon must fall back to QUESTION_MARK_ICON, never 0")
assert(flags == 0, "missing depositFlags default to 0 (empty BagSlotFlags)")

-- Test 10: FindTabForItem — the search-focus tab autoselect. Char tabs win
-- over warband tabs; slots are sparse (pairs walk); nil when absent.
local frec = {
    bankTabs = {
        [7] = { size = 98, slots = { [4] = { itemID = 777, count = 1 } } },
        [6] = { size = 98, slots = {} },
    },
}
local fwb = {
    tabs = {
        [12] = { size = 98, slots = { [9] = { itemID = 777, count = 2 }, [2] = { itemID = 555 } } },
    },
}
assert(BankWindow.FindTabForItem(frec, fwb, 777) == 7,
    "char tab containing the item must win over the warband tab")
assert(BankWindow.FindTabForItem(frec, fwb, 555) == 12,
    "warband tabs are searched when no char tab has the item")
assert(BankWindow.FindTabForItem(frec, fwb, 999) == nil, "absent item → nil")
assert(BankWindow.FindTabForItem(nil, nil, 777) == nil, "nil records → nil")

-- Test 11: BuildTabList active bank-type filter. Character view keeps only
-- char tabs/marker; warband view keeps only warband tabs/marker.
list = BankWindow.BuildTabList(rec, warband,
    { canPurchaseChar = true, canPurchaseWarband = true, bankType = CHAR })
assert(#list == 4, "character-filtered list: All + char tabs + char purchase marker")
assert(list[1].all == true, "character-filtered list leads with its All entry")
for _, entry in ipairs(list) do
    assert(entry.bankType == CHAR, "character-filtered list must not include warband entries")
end
list = BankWindow.BuildTabList(rec, warband,
    { canPurchaseChar = true, canPurchaseWarband = true, bankType = ACCOUNT })
assert(#list == 4, "warband-filtered list: All + warband tabs + warband purchase marker")
assert(list[1].all == true, "warband-filtered list leads with its All entry")
for _, entry in ipairs(list) do
    assert(entry.bankType == ACCOUNT, "warband-filtered list must not include character entries")
end

-- Test 12: bank type helpers.
assert(BankWindow.BankTypeForBagID(6) == CHAR, "bag 6 is a character bank tab")
assert(BankWindow.BankTypeForBagID(11) == CHAR, "bag 11 is a character bank tab")
assert(BankWindow.BankTypeForBagID(12) == ACCOUNT, "bag 12 is a warband bank tab")
assert(BankWindow.BankTypeForBagID(16) == ACCOUNT, "bag 16 is a warband bank tab")
assert(BankWindow.BankTypeLabel(CHAR) == "Character Bank", "character label")
assert(BankWindow.BankTypeLabel(ACCOUNT) == "Warband Bank", "warband label")

-- Test 13: focus options choose account bank for warband hits.
assert(BankWindow.BankTypeForFocus({ warband = true }) == ACCOUNT,
    "warband search focus must activate Warband Bank")
assert(BankWindow.BankTypeForFocus({}) == CHAR,
    "plain bank search focus defaults to Character Bank")

print("OK: bags_bank_window_state_test")
