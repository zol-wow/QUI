-- tests/unit/bags_scan_guild_test.lua
-- Run: lua tests/unit/bags_scan_guild_test.lua
-- Guild bank scanner: legacy global APIs, whole-bank rescan unit, session
-- keyed by GUILDBANKFRAME_OPENED/CLOSED (guild data is server-resident and
-- only readable at the guild bank).
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- Guild identity: Store.GetCurrentGuildKey → "Test Guild-TestRealm"
local guildName = "Test Guild"
_G.GetGuildInfo = function() return guildName end

-- Legacy guild-bank API stubs ----------------------------------------------
local numTabs = 2
_G.GetNumGuildBankTabs = function() return numTabs end

local queried = {}
_G.QueryGuildBankTab = function(tab) queried[#queried + 1] = tab end

-- tab 1 viewable; tab 2 not (an officers tab this character can't see)
local tabInfo = {
    [1] = { name = "Materials", icon = 101, isViewable = true, canDeposit = true,
            numWithdrawals = 100, remainingWithdrawals = 25 },
    [2] = { name = "Officers", icon = 102, isViewable = false, canDeposit = false,
            numWithdrawals = 0, remainingWithdrawals = 0 },
}
_G.GetGuildBankTabInfo = function(tab)
    local t = tabInfo[tab]
    if not t then return nil end
    return t.name, t.icon, t.isViewable, t.canDeposit, t.numWithdrawals, t.remainingWithdrawals
end

local items = {
    [1] = {
        [1] = { texture = 134414, count = 5, locked = false, isFiltered = false, quality = 2,
                link = "|Hitem:6948::::::::70:::::|h[Hearthstone]|h" },
        [3] = { texture = 132599, count = 1, locked = false, isFiltered = false, quality = 3,
                link = "|Hbattlepet:1234:25:3:1547:325:244:0000|h[Cagey Pet]|h" },
    },
}
_G.GetGuildBankItemInfo = function(tab, slot)
    local e = items[tab] and items[tab][slot]
    if not e then return nil end
    return e.texture, e.count, e.locked, e.isFiltered, e.quality
end
_G.GetGuildBankItemLink = function(tab, slot)
    local e = items[tab] and items[tab][slot]
    return e and e.link or nil
end

_G.GetGuildBankMoney = function() return 5000000 end
-- Default: no tab is the "current" active tab (0 matches no real tab index).
-- Test 7 overrides this to exercise the current-tab exemption.
_G.GetCurrentGuildBankTab = function() return 0 end

local ns = loader.LoadAll(nil, "scan_guild.lua")
ns.Bags.RequestDrain = function() end
local Store, ScanGuild, Bus = ns.Bags.Store, ns.Bags.ScanGuild, ns.Bags.Bus

_G.QUI_StorageDB = nil
Store.Initialize()

local events = {}
Bus.Subscribe("GuildChanged", function(_, guildKey, changedTabs)
    events[#events + 1] = { guildKey = guildKey, tabs = changedTabs }
end)

local KEY = "Test Guild-TestRealm"

-- Test 1: opened pump queries each tab once + EnsureGuild created the record
ScanGuild.OnGuildBankOpened()
assert(#queried == 2 and queried[1] == 1 and queried[2] == 2, "pump must query each tab exactly once")
assert(Store.GetGuild(KEY) ~= nil, "OnGuildBankOpened must create the guild record")

-- Test 2: drain writes viewable tabs (meta + slots) + money + one GuildChanged
ScanGuild.MarkDirty()
assert(ScanGuild.Drain() == true, "dirty drain must write")
local rec = Store.GetGuild(KEY)
local tab1 = rec.tabs[1]
assert(tab1.size == 98, "guild tabs are 98 slots")
assert(tab1.name == "Materials" and tab1.icon == 101 and tab1.withdrawals == 25, "tab meta wrong")
local entry = tab1.slots[1]
assert(entry.itemID == 6948 and entry.count == 5 and entry.quality == 2
       and entry.icon == 134414 and entry.isBound == false
       and entry.link == "|Hitem:6948::::::::70:::::|h[Hearthstone]|h", "slot entry wrong")
assert(tab1.slots[2] == nil, "empty slots must be nil")
-- minimalism guard: ONLY the six persisted entry keys (scan_common parity)
local allowed = { itemID = true, count = true, link = true, quality = true, icon = true, isBound = true }
for slot, e in pairs(tab1.slots) do
    for k in pairs(e) do
        assert(allowed[k], "unexpected persisted key in slot " .. slot .. ": " .. tostring(k))
    end
end
assert(rec.money == 5000000, "guild money not captured on drain")
assert(#events == 1, "exactly one GuildChanged per drain")
assert(events[1].guildKey == KEY, "GuildChanged key wrong")
assert(#events[1].tabs == 1 and events[1].tabs[1] == 1, "changed list must hold only the written (viewable) tab")
assert(ScanGuild.Drain() == false, "clean drain must no-op")

-- Test 3: non-viewable tab retains the previously cached copy
rec.tabs[2] = { size = 98, slots = {}, name = "Officers (old)", icon = 99, withdrawals = 3 }
local stale = rec.tabs[2]
ScanGuild.MarkDirty()
assert(ScanGuild.Drain() == true, "drain should still write the viewable tab")
assert(rec.tabs[2] == stale and rec.tabs[2].name == "Officers (old)",
       "non-viewable tab must keep its cached copy untouched")
assert(#events == 2 and #events[2].tabs == 1 and events[2].tabs[1] == 1,
       "non-viewable tab must not appear in the changed list")

-- Test 4: battlepet link kept with itemID nil; item link parses itemID
local pet = rec.tabs[1].slots[3]
assert(pet ~= nil, "battlepet entry must be kept")
assert(pet.itemID == nil, "battlepet links carry no item: payload → itemID nil")
assert(pet.count == 1 and pet.quality == 3 and pet.icon == 132599
       and pet.link:find("battlepet", 1, true), "battlepet entry fields wrong")
assert(rec.tabs[1].slots[1].itemID == 6948, "item link must parse itemID")

-- Test 5: unguilded OnGuildBankOpened is a complete no-op
guildName = nil
local queriesBefore = #queried
ScanGuild.OnGuildBankOpened()
assert(#queried == queriesBefore, "unguilded open must not pump")
assert(#Store.ListGuilds() == 1, "unguilded open must not create a record")
ScanGuild.MarkDirty()
assert(ScanGuild.Drain() == false, "unguilded session drain must no-op")
assert(#events == 2, "unguilded drain must not publish")

-- Test 6: OnGuildBankClosed clears the session
guildName = "Test Guild"
ScanGuild.OnGuildBankOpened()
ScanGuild.MarkDirty()
ScanGuild.OnGuildBankClosed()
assert(ScanGuild.Drain() == false, "drain after close must no-op even when dirty")
assert(#events == 2, "closed-session drain must not publish")

-- Test 7: unstreamed all-empty read must not clobber a previously occupied tab
-- Setup: reopen a session so guildKey is live; make tab 2 viewable with prior cache.
do
    -- Make tab 2 viewable for this test block.
    tabInfo[2] = { name = "Officers", icon = 102, isViewable = true, canDeposit = true,
                   numWithdrawals = 0, remainingWithdrawals = 0 }

    -- Stub GetCurrentGuildBankTab: tab 1 is the active tab being viewed.
    _G.GetCurrentGuildBankTab = function() return 1 end

    -- Seed the guild record with an occupied tab 2 via a first drain (tab 2 has items).
    items[2] = {
        [5]  = { texture = 134414, count = 3, locked = false, isFiltered = false, quality = 1,
                 link = "|Hitem:6948::::::::70:::::|h[Hearthstone]|h" },
        [10] = { texture = 132599, count = 2, locked = false, isFiltered = false, quality = 2,
                 link = "|Hitem:12345::::::::70:::::|h[Widget]|h" },
    }
    guildName = "Test Guild"
    ScanGuild.OnGuildBankOpened()
    ScanGuild.MarkDirty()
    assert(ScanGuild.Drain() == true, "seed drain must write")
    local rec7 = Store.GetGuild(KEY)
    assert(rec7.tabs[2] ~= nil and rec7.tabs[2].slots[5] ~= nil,
           "precondition: tab 2 must be seeded with occupied slots")
    local seedTab2 = rec7.tabs[2]
    local eventsBeforeUnstream = #events

    -- Now simulate an unstreamed read: tab 2 returns nil for all slots (server
    -- hasn't streamed it yet), while tab 1 (current) returns its normal items.
    items[2] = {}  -- all-nil reads for tab 2 (unstreamed)

    ScanGuild.MarkDirty()
    assert(ScanGuild.Drain() == true, "drain must still write (tab 1 is current + written)")

    -- tab 2 must be untouched — the occupancy guard preserved the cache.
    assert(rec7.tabs[2] == seedTab2,
           "unstreamed tab 2: occupancy guard must keep the cached record")
    assert(rec7.tabs[2].slots[5] ~= nil,
           "unstreamed tab 2: cached occupied slots must survive")

    -- tab 2 must NOT appear in the GuildChanged changed list.
    local lastEv = events[#events]
    for _, t in ipairs(lastEv.tabs) do
        assert(t ~= 2, "unstreamed tab 2 must not appear in the GuildChanged changed list")
    end

    -- Sub-assert: current tab (tab 1) is exempt from the guard even when all-empty.
    -- Stub tab 1 to also return all-nil (genuine full-empty on the active tab).
    items[1] = {}  -- all-nil for tab 1 (current tab — must still overwrite)
    local oldTab1 = rec7.tabs[1]
    ScanGuild.MarkDirty()
    -- Tab 1 all-empty drain: either writes tab 1 with empty slots OR tab 2 unchanged.
    -- The key assertion is tab 1 WAS overwritten (current-tab exemption means we write it).
    ScanGuild.Drain()
    assert(rec7.tabs[1] ~= oldTab1 or (rec7.tabs[1] ~= nil),
           "current tab (tab 1) must be overwritten even when all-empty (current-tab exemption)")
    -- More precise: the record object itself must be a freshly built one.
    -- If the guard skipped tab 1, it would keep oldTab1; if it wrote it, it's a new table.
    -- We verify by checking the slots table was cleared (no slot 1 anymore).
    assert(rec7.tabs[1].slots[1] == nil,
           "current tab write must clear previously occupied slots (new empty record)")
    assert(rec7.tabs[1].slots[3] == nil,
           "current tab write must clear all old slots")

    -- Also verify tab 2 still untouched after the second drain.
    assert(rec7.tabs[2] == seedTab2,
           "tab 2 must remain cached after the second drain too")

    -- Restore items table for any follow-up.
    items[1] = {
        [1] = { texture = 134414, count = 5, locked = false, isFiltered = false, quality = 2,
                link = "|Hitem:6948::::::::70:::::|h[Hearthstone]|h" },
        [3] = { texture = 132599, count = 1, locked = false, isFiltered = false, quality = 3,
                link = "|Hbattlepet:1234:25:3:1547:325:244:0000|h[Cagey Pet]|h" },
    }
    items[2] = nil
    tabInfo[2] = { name = "Officers", icon = 102, isViewable = false, canDeposit = false,
                   numWithdrawals = 0, remainingWithdrawals = 0 }
end

print("OK: bags_scan_guild_test")
