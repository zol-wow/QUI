-- tests/unit/bags_everywhere_test.lua
-- Run: lua tests/unit/bags_everywhere_test.lua
-- The search-everywhere query core: Everywhere.Query(queryString, opts) —
-- pure aggregation over store accessors + Details.Build + Search.Compile.
-- Covers: aggregation across owners/locations (counts summed per itemID,
-- owners breakdown array), sort total-desc-then-name (pending names last),
-- limit + truncated overflow count, blank query → empty + .blank, pending
-- details included (matcher nil ≠ excluded), plain name queries.
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

local ns = loader.LoadAll()
local Store, Summaries = ns.Bags.Store, ns.Bags.Summaries

-- everywhere.lua sits outside the data layer: load compiler + details + it
for _, path in ipairs({
    "QUI_Bags/bags/search/compiler.lua",
    "QUI_Bags/bags/views/details.lua",
    "QUI_Bags/bags/search/everywhere.lua",
}) do
    local chunk = assert(loadfile(path))
    chunk("QUI", ns)
end
local Everywhere = ns.Bags.Everywhere
assert(Everywhere and type(Everywhere.Query) == "function", "Everywhere.Query must be exported")

-- Item universe. GetItemInfo resolves names for all but 103 (pending: the
-- client hasn't cached it yet) — auction entries also omit quality (store
-- contract), so 104 is quality-PENDING for quality queries.
local NAMES = {
    [101] = "Healing Potion",
    [102] = "Iron Sword",
    -- 103 deliberately absent → name pending
    [104] = "Apple",
    [105] = "Banana",
    [106] = "Zircon Blade",
}
_G.C_Item.GetItemInfo = function(itemID)
    local name = NAMES[itemID]
    if not name then return nil end
    return name, "link:" .. itemID, 1, 10, nil, nil, nil, 20,
        nil, nil, nil, nil, nil, nil, 9
end

local function e(itemID, count, quality, icon, link)
    return { itemID = itemID, count = count, quality = quality or 1,
             icon = icon or 111, link = link or ("l" .. itemID) }
end

_G.QUI_StorageDB = nil
Store.Initialize()
QUI_StorageDB.characters["Alta-TestRealm"] = {
    details = {},
    bags = {
        -- two slots of 101 in one location: counts must merge (3+2=5)
        [0] = { size = 2, slots = { e(101, 3), e(101, 2) } },
        [1] = { size = 2, slots = { e(105, 12), e(106, 3, 4, 666) } },
    },
    bankTabs = { [6] = { size = 1, slots = { e(101, 10) } } },
    mail = {}, currencies = {}, auctions = {},
    equipped = { size = 19, slots = {
        [16] = { itemID = 102, count = 1, quality = 4, isBound = true, icon = 222, link = "l102" },
    } },
}
QUI_StorageDB.characters["Brin-TestRealm"] = {
    details = {},
    bags = { [0] = { size = 1, slots = { { itemID = 103, count = 3, quality = 4, icon = 333 } } } },
    bankTabs = {},
    mail = { size = 1, slots = { { itemID = 101, count = 2, quality = 1, icon = 111, link = "l101", daysLeft = 10 } } },
    equipped = {}, currencies = {},
    -- auction entries omit quality/isBound (store contract)
    auctions = { size = 1, slots = { { itemID = 104, count = 12, icon = 444, link = "l104" } } },
}
QUI_StorageDB.warband.tabs[12] = { size = 1, slots = { e(101, 20) } }
QUI_StorageDB.guilds["Guildy-TestRealm"] = {
    tabs = { [1] = { size = 98, slots = { e(101, 7) } } },
    money = 0, details = {},
}

-- Test 1: blank/whitespace queries → empty result with .blank (a blank
-- query compiles to match-everything; "every item on the account" is not a
-- useful result set, so the core refuses instead of returning the world)
local res = Everywhere.Query("")
assert(#res == 0, "blank query must return no entries")
assert(res.blank == true, "blank query must set .blank")
assert(res.truncated == nil, "blank query must not set .truncated")
res = Everywhere.Query("   ")
assert(#res == 0 and res.blank == true, "whitespace query must behave as blank")
res = Everywhere.Query(nil)
assert(#res == 0 and res.blank == true, "nil query must behave as blank")

-- Test 2: aggregation across owners and locations — one itemID, five
-- placements (bags merged from two slots, bank, mail, warband, guild).
-- 103's name is pending, so name queries carry it as a maybe (nil ~= false)
-- — exactly like the window grids keep pending slots visible.
res = Everywhere.Query("potion")
assert(res.blank == nil, "non-blank query must not set .blank")
assert(#res == 2, "potion must match the potion + the pending-name item, got " .. #res)
assert(res[2].itemID == 103 and res[2].name == nil,
    "the pending-name item must ride along on name queries")
local item = res[1]
assert(item.itemID == 101, "wrong itemID")
assert(item.name == "Healing Potion", "name must come from item info")
assert(item.total == 44, "total must sum every placement (5+10+2+20+7), got " .. tostring(item.total))
assert(item.icon == 111, "icon must carry from a cache entry")
assert(item.quality == 1, "quality must carry from a cache entry")
assert(item.link == "l101", "link must carry from a cache entry (tooltip fallback)")
-- owners breakdown: count desc, then ownerKey, then location
assert(#item.owners == 5, "five owner/location placements expected, got " .. #item.owners)
local function ownerAt(i, ownerKey, location, count)
    local o = item.owners[i]
    assert(o.ownerKey == ownerKey and o.location == location and o.count == count,
        ("owners[%d] expected %s/%s/%d, got %s/%s/%s"):format(
            i, ownerKey, location, count,
            tostring(o.ownerKey), tostring(o.location), tostring(o.count)))
end
ownerAt(1, Summaries.WARBAND_OWNER, "warband", 20)
ownerAt(2, "Alta-TestRealm", "bank", 10)
ownerAt(3, Summaries.GUILD_PREFIX .. "Guildy-TestRealm", "guild", 7)
ownerAt(4, "Alta-TestRealm", "bags", 5)
ownerAt(5, "Brin-TestRealm", "mail", 2)

-- Test 3: name query reaches the equipped location (+ the pending-name
-- rider, which outranks it on total: 3 > 1)
res = Everywhere.Query("iron")
assert(#res == 2 and res[1].itemID == 103 and res[2].itemID == 102,
    "iron must match the sword + the pending-name rider, total-sorted")
local sword = res[2]
assert(sword.total == 1 and #sword.owners == 1, "one equipped copy expected")
assert(sword.owners[1].ownerKey == "Alta-TestRealm"
    and sword.owners[1].location == "equipped"
    and sword.owners[1].count == 1, "equipped owner entry wrong")
assert(sword.link == "l102", "first owner's link must be carried")

-- Test 4: pending details are INCLUDED (matcher nil ≠ false). "epic" hits:
-- 104 (quality pending: auction entries omit quality) total 12,
-- 106 (epic, named) total 3, 103 (epic, name pending) total 3, 102 total 1.
-- Sort: total desc; ties by name with nil (pending) LAST; itemID final.
res = Everywhere.Query("epic")
assert(#res == 4, "epic must include both pending-field items, got " .. #res)
assert(res[1].itemID == 104, "quality-pending item (highest total) must lead")
assert(res[2].itemID == 106 and res[2].name == "Zircon Blade",
    "named item must precede the pending-name item on a total tie")
assert(res[3].itemID == 103 and res[3].name == nil,
    "pending-name item must be included with name == nil")
assert(res[4].itemID == 102, "lowest total must come last")

-- Test 5: sort total desc, then name asc — "common" hits 101 (44, match),
-- 104 (12, quality pending → included), 105 (12, match): Apple < Banana.
res = Everywhere.Query("common")
assert(#res == 3, "common must match three items, got " .. #res)
assert(res[1].itemID == 101, "highest total must sort first")
assert(res[2].itemID == 104 and res[3].itemID == 105,
    "total ties must sort by name (Apple before Banana)")
assert(res.truncated == nil, "no overflow → .truncated must stay nil")

-- Test 6: explicit limit caps the array and reports the overflow count
res = Everywhere.Query("common", { limit = 2 })
assert(#res == 2, "limit=2 must cap the result array")
assert(res[1].itemID == 101 and res[2].itemID == 104,
    "the cap must keep the top-sorted entries")
assert(res.truncated == 1, "one dropped entry must be reported, got " .. tostring(res.truncated))

-- Test 7: limit larger than the result set → no truncation flag
res = Everywhere.Query("common", { limit = 50 })
assert(#res == 3 and res.truncated == nil, "an unexceeded limit must not set .truncated")

-- Test 8: no match → empty, no flags. A compound query whose AND collapses
-- to false for every item — including the pending ones (103 fails on
-- quality, 104 fails on name), so nothing rides along as a maybe.
res = Everywhere.Query("poor potion")
assert(#res == 0 and res.blank == nil and res.truncated == nil,
    "a non-matching query must return a plain empty result")

-- Test 9: default limit is 100 (fresh store with 105 distinct matches; all
-- names pending → total ties broken by itemID ascending)
_G.QUI_StorageDB = nil
Store.Initialize()
local slots = {}
for i = 1, 105 do slots[i] = { itemID = 1000 + i, count = 1, quality = 1, icon = 5 } end
QUI_StorageDB.characters["Bulk-TestRealm"] = {
    details = {},
    bags = { [0] = { size = 105, slots = slots } },
    bankTabs = {}, mail = {}, equipped = {}, currencies = {}, auctions = {},
}
res = Everywhere.Query("common")
assert(#res == 100, "default limit must be 100, got " .. #res)
assert(res.truncated == 5, "default-limit overflow must be 5, got " .. tostring(res.truncated))
assert(res[1].itemID == 1001 and res[100].itemID == 1100,
    "all-pending names must fall back to itemID-ascending ordering")

-- ── Pure window seams: owner labels + the one-line owners summary ────────
-- search_window creates frames only lazily (EnsureWindow); the recording
-- fake guards that staying true (the gate-test idiom).
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
ns.Helpers = { CreateDBGetter = function() return function() return {} end end }
local chunk = assert(loadfile("QUI_Bags/bags/views/search_window.lua"))
chunk("QUI", ns)
local SearchWindow = ns.Bags.SearchWindow
assert(type(SearchWindow.Toggle) == "function", "Toggle must be exported")
assert(type(SearchWindow.IsShown) == "function", "IsShown must be exported")

-- Test 10: owner labels — characters verbatim, warband friendly, guild
-- keys lose the registry prefix and gain brackets
assert(SearchWindow.OwnerLabel("Alta-TestRealm") == "Alta-TestRealm",
    "character keys must label verbatim")
assert(SearchWindow.OwnerLabel(Summaries.WARBAND_OWNER) == "Warband",
    "the warband owner must get the friendly label")
assert(SearchWindow.OwnerLabel(Summaries.GUILD_PREFIX .. "Guildy-TestRealm")
    == "<Guildy-TestRealm>", "guild keys must drop the prefix and gain brackets")

-- Test 11: owners line — per-owner sums (locations merged), largest first,
-- key-ascending ties, comma-joined
local line = SearchWindow.BuildOwnersLine({
    { ownerKey = "Alta-TestRealm", location = "bank", count = 10 },
    { ownerKey = Summaries.WARBAND_OWNER, location = "warband", count = 20 },
    { ownerKey = "Alta-TestRealm", location = "bags", count = 5 },
    { ownerKey = "Brin-TestRealm", location = "mail", count = 2 },
})
assert(line == "Warband: 20, Alta-TestRealm: 15, Brin-TestRealm: 2",
    "owners line wrong: " .. line)
assert(SearchWindow.BuildOwnersLine({}) == "", "no owners → empty line")
assert(SearchWindow.BuildOwnersLine(nil) == "", "nil owners → empty line")
local tie = SearchWindow.BuildOwnersLine({
    { ownerKey = "Brin-TestRealm", location = "bags", count = 3 },
    { ownerKey = "Alta-TestRealm", location = "bags", count = 3 },
})
assert(tie == "Alta-TestRealm: 3, Brin-TestRealm: 3",
    "owner-sum ties must order by key: " .. tie)

-- Test 12: ResolveTarget — pick the placement a result-row click navigates
-- to. Priority: current bags > current bank > warband > any guild >
-- other-char bags > other-char bank; mail/equipped/auctions are never
-- navigable (no window renders them). → { window, ownerKey?, guildKey?,
-- warband? } or nil; ownerKey nil means "current character's view".
local CUR = "Me-TestRealm"
local function owners(...) return { owners = { ... } } end
local function o(ownerKey, location) return { ownerKey = ownerKey, location = location, count = 1 } end

local t = Everywhere.ResolveTarget(owners(o("Alta-TestRealm", "bags"), o(CUR, "bags")), CUR)
assert(t and t.window == "bags" and t.ownerKey == nil,
    "current-char bags must win (ownerKey nil = current)")
t = Everywhere.ResolveTarget(owners(o("Alta-TestRealm", "bags"), o(CUR, "bank")), CUR)
assert(t and t.window == "bank" and t.ownerKey == nil,
    "current-char bank must beat other-char bags")
t = Everywhere.ResolveTarget(owners(o(Summaries.WARBAND_OWNER, "warband"), o("Alta-TestRealm", "bank")), CUR)
assert(t and t.window == "bank" and t.ownerKey == nil and t.warband == true,
    "warband routes to the bank window (current view)")
t = Everywhere.ResolveTarget(owners(o(Summaries.GUILD_PREFIX .. "Guildy-TestRealm", "guild")), CUR)
assert(t and t.window == "guild" and t.guildKey == "Guildy-TestRealm",
    "guild owner must strip the prefix into guildKey")
t = Everywhere.ResolveTarget(owners(o("Alta-TestRealm", "bank"), o("Alta-TestRealm", "bags")), CUR)
assert(t and t.window == "bags" and t.ownerKey == "Alta-TestRealm",
    "other-char bags beat other-char bank")
t = Everywhere.ResolveTarget(owners(o(CUR, "mail"), o(CUR, "equipped"), o(CUR, "auctions")), CUR)
assert(t == nil, "mail/equipped/auctions placements are not navigable")

print("OK: bags_everywhere_test")
