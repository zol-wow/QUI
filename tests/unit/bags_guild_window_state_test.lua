-- tests/unit/bags_guild_window_state_test.lua
-- Run: lua tests/unit/bags_guild_window_state_test.lua
-- Pure parts of the guild bank window: GuildWindow.BuildTabList(rec, opts)
-- — tab-strip assembly from the guild cache record. Guild tabs are keyed
-- 1..MAX_GUILDBANK_TABS on rec.tabs (sparse: non-viewable tabs may never
-- have been cached); ordering is ascending tab index. opts (live mode
-- only): liveViewable = {[tab]=bool} drops tabs the live API reports
-- non-viewable (absent keys default viewable — cached browse-anywhere keeps
-- the full list); canPurchase appends a { purchase = true } marker last.
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- SetScript-recording frame fake (the gate-test idiom). guild_window creates
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
local chunk = assert(loadfile("QUI_Bags/bags/views/guild_window.lua"))
chunk("QUI", ns)
local GuildWindow = ns.Bags.GuildWindow
assert(type(GuildWindow.BuildTabList) == "function", "BuildTabList must be exported")

-- Test 1: empty cache → empty list (nil record and empty tables alike)
assert(#GuildWindow.BuildTabList(nil, nil) == 0, "nil record must yield an empty list")
assert(#GuildWindow.BuildTabList({}, nil) == 0, "recordless cache must yield an empty list")
assert(#GuildWindow.BuildTabList({ tabs = {} }, nil) == 0,
    "empty tab table must yield an empty list")

-- Test 2: ordering from guild.tabs — ascending tab index, gaps skipped,
-- fields carried (scan_guild cache shape: {size, slots, name, icon,
-- withdrawals}). ≥2 real tabs prepend the synthetic All entry
-- ({ all = true }, no tab index) — selection sentinel is the string "all".
local rec = {
    tabs = {
        [3] = { size = 98, slots = {}, name = "Mats", icon = 333, withdrawals = 25 },
        [1] = { size = 98, slots = {}, name = "One",  icon = 111, withdrawals = -1 },
        -- 2, 4..8 never cached → skipped
    },
}
local list = GuildWindow.BuildTabList(rec, nil)
assert(#list == 3, "All + two tabs expected, got " .. #list)
assert(list[1].all == true and list[1].tab == nil and list[1].name == nil,
    "the synthetic All entry leads the list and carries no tab/name")
assert(list[2].tab == 1 and list[3].tab == 3, "tabs must be ordered by tab index")
assert(list[2].name == "One" and list[2].icon == 111, "tab name/icon must come from the cache")
assert(list[2].withdrawals == -1 and list[3].withdrawals == 25,
    "remainingWithdrawals must be carried (tooltip data)")
assert(not list[2].purchase and not list[3].purchase, "real tabs carry no purchase marker")

-- Test 3: single mid-range tab survives alone — and gets NO All entry
-- (one tab has nothing to unify)
list = GuildWindow.BuildTabList({ tabs = { [2] = { size = 98, slots = {}, name = "Solo" } } }, nil)
assert(#list == 1 and list[1].tab == 2 and list[1].name == "Solo" and not list[1].all,
    "a lone sparse tab must list by itself with no All entry")

-- Test 4: liveViewable filtering — false drops the tab; absent and true
-- keep. The All entry counts REAL tabs after the filter.
list = GuildWindow.BuildTabList(rec, { liveViewable = { [1] = false } })
assert(#list == 1 and list[1].tab == 3 and not list[1].all,
    "liveViewable[tab]=false must drop that tab (<2 real tabs → no All)")
list = GuildWindow.BuildTabList(rec, { liveViewable = { [1] = true } })
assert(#list == 3 and list[1].all == true, "liveViewable[tab]=true must keep the tab")
list = GuildWindow.BuildTabList(rec, { liveViewable = {} })
assert(#list == 3 and list[1].all == true, "absent liveViewable keys must default to viewable")
list = GuildWindow.BuildTabList(rec, { liveViewable = { [1] = false, [3] = false } })
assert(#list == 0, "filtering every tab must yield an empty list")

-- Test 5: canPurchase appends the marker AFTER the real tabs (and after
-- the All entry, which always leads)
list = GuildWindow.BuildTabList(rec, { canPurchase = true })
assert(#list == 4, "All + tabs + purchase marker expected, got " .. #list)
assert(list[1].all == true, "the All entry leads the list")
assert(list[4].purchase == true, "marker must come last")
assert(list[4].tab == nil, "purchase markers carry no tab index")
assert(list[2].tab == 1 and list[3].tab == 3, "real tabs must precede the marker")

-- Test 6: marker appears even when the guild has no cached tabs yet
-- (fresh guild at the vault: nothing purchased, the + must still render)
list = GuildWindow.BuildTabList({ tabs = {} }, { canPurchase = true })
assert(#list == 1 and list[1].purchase == true,
    "the purchase marker must not require existing tabs")

-- Test 7: no opts table → no purchase marker (cached mode); the All entry
-- still leads (cached browse gets the unified view too)
list = GuildWindow.BuildTabList(rec, nil)
for _, entry in ipairs(list) do
    assert(not entry.purchase, "cached mode (no opts) must produce no purchase markers")
end
list = GuildWindow.BuildTabList(rec, {})
assert(#list == 3, "empty opts must add no marker")
for _, entry in ipairs(list) do
    assert(not entry.purchase, "opts without canPurchase must produce no purchase markers")
end

-- Test 8: viewability filter + purchase marker compose — the marker is
-- appended after the FILTERED tab list
list = GuildWindow.BuildTabList(rec, { liveViewable = { [1] = false }, canPurchase = true })
assert(#list == 2 and list[1].tab == 3 and list[2].purchase == true,
    "marker must follow the filtered tabs")

-- Test 8b: All sentinel scaling — a full 8-tab guild leads with All and
-- keeps ascending order; filtering down to ONE viewable tab drops it
local full = { tabs = {} }
for tab = 1, 8 do full.tabs[tab] = { size = 98, slots = {}, name = "T" .. tab } end
list = GuildWindow.BuildTabList(full, nil)
assert(#list == 9 and list[1].all == true, "8 tabs → All + 8 entries")
for i = 2, 9 do
    assert(list[i].tab == i - 1, "real tabs keep ascending order after All")
end
list = GuildWindow.BuildTabList(full, { liveViewable = {
    [1] = false, [2] = false, [3] = false, [4] = false,
    [5] = false, [6] = false, [7] = false } })
assert(#list == 1 and list[1].tab == 8 and not list[1].all,
    "viewability filtering down to one real tab must drop the All entry")

-- Test 9: FindTabForItem — the search-focus tab autoselect (lowest tab
-- index containing the item; sparse slots; nil when absent/nil record)
local frec = {
    tabs = {
        [3] = { size = 98, slots = { [12] = { itemID = 777 } } },
        [1] = { size = 98, slots = { [5] = { itemID = 555 } } },
    },
}
assert(GuildWindow.FindTabForItem(frec, 777) == 3, "tab containing the item")
assert(GuildWindow.FindTabForItem(frec, 555) == 1, "lowest matching tab index")
assert(GuildWindow.FindTabForItem(frec, 999) == nil, "absent item → nil")
assert(GuildWindow.FindTabForItem(nil, 777) == nil, "nil record → nil")

print("OK: bags_guild_window_state_test")
