-- tests/unit/bags_summaries_test.lua
-- Run: lua tests/unit/bags_summaries_test.lua
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_bags_data.lua")
local ns = loader.LoadAll() -- everything, incl. summaries' bus self-subscription
local Store, Summaries, Bus = ns.Bags.Store, ns.Bags.Summaries, ns.Bags.Bus

local function entry(itemID, count) return { itemID = itemID, count = count, quality = 1 } end

_G.QUI_StorageDB = nil
Store.Initialize()
QUI_StorageDB.characters["Main-TestRealm"] = {
    details = {},
    bags = { [0] = { size = 2, slots = { entry(111, 5), entry(111, 3) } } },
    bankTabs = { [6] = { size = 1, slots = { entry(111, 10) } } },
}
QUI_StorageDB.characters["Alt-TestRealm"] = {
    details = {},
    bags = { [0] = { size = 1, slots = { entry(111, 7) } } },
    bankTabs = {},
}
QUI_StorageDB.warband.tabs[12] = { size = 1, slots = { entry(111, 20) } }

-- Test 1: seeded owners produce per-owner, per-location counts
Summaries.SeedOwners()
local counts = Summaries.GetCounts(111)
assert(counts["Main-TestRealm"].bags == 8, "main bags count wrong")
assert(counts["Main-TestRealm"].bank == 10, "main bank count wrong")
assert(counts["Alt-TestRealm"].bags == 7, "alt bags count wrong")
assert(counts[Summaries.WARBAND_OWNER].warband == 20, "warband count wrong")

-- Test 2: unknown item → empty table
local none = Summaries.GetCounts(424242)
assert(type(none) == "table" and next(none) == nil, "unknown item should be empty")

-- Test 3: bus events invalidate lazily (rebuild happens on next query)
QUI_StorageDB.characters["Main-TestRealm"].bags[0].slots[1] = entry(111, 50)
counts = Summaries.GetCounts(111)
assert(counts["Main-TestRealm"].bags == 8, "index must serve cached counts until invalidated")
Bus.Publish("BagsChanged", "Main-TestRealm", { 0 })
counts = Summaries.GetCounts(111)
assert(counts["Main-TestRealm"].bags == 53, "BagsChanged invalidation missed")

QUI_StorageDB.warband.tabs[12].slots[1] = entry(111, 1)
Bus.Publish("WarbandChanged", { 12 })
counts = Summaries.GetCounts(111)
assert(counts[Summaries.WARBAND_OWNER].warband == 1, "WarbandChanged invalidation missed")

-- Test 3b: BankChanged invalidates; two containers merge into one location
QUI_StorageDB.characters["Main-TestRealm"].bankTabs[7] = { size = 1, slots = { entry(111, 5) } }
Bus.Publish("BankChanged", "Main-TestRealm", { 7 })
counts = Summaries.GetCounts(111)
assert(counts["Main-TestRealm"].bank == 15, "two bank tabs must merge into the bank location")

-- Test 4: deleted character disappears — invalidation arrives via the
-- store's own CharacterDeleted event, no manual Invalidate needed
Store.DeleteCharacter("Alt-TestRealm")
counts = Summaries.GetCounts(111)
assert(counts["Alt-TestRealm"] == nil, "deleted character still in counts")

-- Test 5: warband owner key can never collide with Name-Realm keys
assert(not Summaries.WARBAND_OWNER:find("-", 1, true), "WARBAND_OWNER must stay dash-less")

-- Test 6: GUILD_PREFIX exported and non-colliding
assert(type(Summaries.GUILD_PREFIX) == "string" and #Summaries.GUILD_PREFIX > 0,
    "Summaries.GUILD_PREFIX must be a non-empty string")
assert(Summaries.GUILD_PREFIX:sub(1, 1) == ":",
    "GUILD_PREFIX must start with ':' to avoid Name-Realm collision")

-- Test 7: guild tab counts under prefixed owner via GetCounts
do
    _G.QUI_StorageDB = nil
    Store.Initialize()
    local guildKey = "TestGuild-TestRealm"
    local ownerKey = Summaries.GUILD_PREFIX .. guildKey
    -- inject a guild record with a tab containing some items
    QUI_StorageDB.guilds[guildKey] = {
        tabs  = { [1] = { size = 98, slots = { entry(777, 4), entry(777, 6) } } },
        money = 0,
        details = {},
    }
    Summaries.SeedOwners()
    local counts = Summaries.GetCounts(777)
    assert(counts[ownerKey] ~= nil, "guild owner not in counts")
    assert(counts[ownerKey].guild == 10, "guild tab count wrong: expected 10, got " .. tostring(counts[ownerKey] and counts[ownerKey].guild))
end

-- Test 8: GuildChanged bus event invalidates the prefixed owner
do
    -- Use the guild record already in db from Test 7
    local guildKey = "TestGuild-TestRealm"
    local ownerKey = Summaries.GUILD_PREFIX .. guildKey
    -- Confirm cached
    local counts = Summaries.GetCounts(777)
    assert(counts[ownerKey].guild == 10, "precondition: should be 10 before change")
    -- Mutate the underlying db
    QUI_StorageDB.guilds[guildKey].tabs[1].slots[1] = entry(777, 100)
    -- Without invalidation, GetCounts still returns cached value
    counts = Summaries.GetCounts(777)
    assert(counts[ownerKey].guild == 10, "should be cached (not yet invalidated)")
    -- Publish GuildChanged → invalidation
    Bus.Publish("GuildChanged", guildKey, { 1 })
    counts = Summaries.GetCounts(777)
    assert(counts[ownerKey].guild == 106, "GuildChanged invalidation missed: expected 106, got " .. tostring(counts[ownerKey] and counts[ownerKey].guild))
end

-- Test 9: Store.DeleteGuild publishes GuildDeleted and drops owner from GetCounts
do
    local guildKey = "TestGuild-TestRealm"
    local ownerKey = Summaries.GUILD_PREFIX .. guildKey
    -- Confirm owner still present
    local counts = Summaries.GetCounts(777)
    assert(counts[ownerKey] ~= nil, "precondition: guild owner should be present")
    -- Delete through the store (publishes GuildDeleted)
    Store.DeleteGuild(guildKey)
    counts = Summaries.GetCounts(777)
    assert(counts[ownerKey] == nil, "deleted guild owner still in counts")
end

-- Test 10: phase-6 breadth locations — mail/equipped/auctions counts appear
-- under their locations (mail/auctions are list-as-slots; equipped is keyed
-- by invSlot). currencies is a flat ID→quantity map and must NEVER join the
-- item index (different ID space).
do
    QUI_StorageDB.characters["Breadth-TestRealm"] = {
        details = {},
        bags = { [0] = { size = 1, slots = { entry(888, 5) } } },
        bankTabs = {},
        mail = { size = 2, slots = {
            { itemID = 888, count = 2, quality = 1, daysLeft = 29 },
            { itemID = 888, count = 3, quality = 1, daysLeft = 12 },
        } },
        equipped = { size = 19, slots = { [16] = { itemID = 888, count = 1, quality = 4, isBound = true } } },
        currencies = { [888] = 12345 }, -- currencyID 888 ≠ itemID 888
        auctions = { size = 1, slots = { { itemID = 888, count = 12 } } },
    }
    Summaries.SeedOwners()
    local counts = Summaries.GetCounts(888)
    local owner = counts["Breadth-TestRealm"]
    assert(owner ~= nil, "breadth owner missing from counts")
    assert(owner.bags == 5, "bags location wrong")
    assert(owner.mail == 5, "mail location must sum attachment entries, got " .. tostring(owner.mail))
    assert(owner.equipped == 1, "equipped location wrong")
    assert(owner.auctions == 12, "auctions location wrong")
    assert(owner.currencies == nil, "currencies must not leak into item summaries")
end

-- Test 11: phase-1 records (placeholder {} without .slots) must not break
-- a rebuild; bus events MailChanged/EquippedChanged/AuctionsChanged
-- invalidate their owner
do
    QUI_StorageDB.characters["Old-TestRealm"] = {
        details = {},
        bags = {}, bankTabs = {},
        mail = {}, equipped = {}, currencies = {}, auctions = {},
    }
    Summaries.SeedOwners()
    assert(next(Summaries.GetCounts(999999)) == nil, "placeholder shapes must rebuild clean")

    local rec = QUI_StorageDB.characters["Breadth-TestRealm"]
    rec.mail.slots[3] = { itemID = 888, count = 10, quality = 1, daysLeft = 1 }
    local counts = Summaries.GetCounts(888)
    assert(counts["Breadth-TestRealm"].mail == 5, "should be cached until invalidated")
    Bus.Publish("MailChanged", "Breadth-TestRealm")
    counts = Summaries.GetCounts(888)
    assert(counts["Breadth-TestRealm"].mail == 15, "MailChanged invalidation missed")

    rec.equipped.slots[1] = { itemID = 888, count = 1, quality = 2, isBound = true }
    Bus.Publish("EquippedChanged", "Breadth-TestRealm")
    counts = Summaries.GetCounts(888)
    assert(counts["Breadth-TestRealm"].equipped == 2, "EquippedChanged invalidation missed")

    rec.auctions.slots[2] = { itemID = 888, count = 8 }
    Bus.Publish("AuctionsChanged", "Breadth-TestRealm")
    counts = Summaries.GetCounts(888)
    assert(counts["Breadth-TestRealm"].auctions == 20, "AuctionsChanged invalidation missed")
end

-- Test 12: synthetic re-dress pings (empty changed array) must NOT invalidate
-- the summaries index. Only real moves (non-empty changed) should trigger a
-- rebuild — lock/cooldown visual refreshes publish {} and must be cheap.
do
    _G.QUI_StorageDB = nil
    Store.Initialize()
    local charKey = "Ping-TestRealm"
    QUI_StorageDB.characters[charKey] = {
        details = {},
        bags = { [0] = { size = 1, slots = { entry(555, 7) } } },
        bankTabs = {},
    }
    Summaries.SeedOwners()
    local before = Summaries.GetCounts(555)
    assert(before[charKey] and before[charKey].bags == 7, "precondition: seeded count wrong")

    -- Mutate the store but publish a synthetic (empty) BagsChanged ping.
    QUI_StorageDB.characters[charKey].bags[0].slots[1] = entry(555, 99)
    Bus.Publish("BagsChanged", charKey, {}) -- empty changed = synthetic re-dress
    local afterPing = Summaries.GetCounts(555)
    assert(afterPing[charKey] and afterPing[charKey].bags == 7,
        "BagsChanged with {} must NOT invalidate (synthetic re-dress ping)")

    -- Now publish a real move (non-empty changed) and verify the rebuild fires.
    Bus.Publish("BagsChanged", charKey, { 0 })
    local afterReal = Summaries.GetCounts(555)
    assert(afterReal[charKey] and afterReal[charKey].bags == 99,
        "BagsChanged with non-empty changed must invalidate and rebuild")

    -- Same contract for WarbandChanged.
    QUI_StorageDB.warband.tabs[12] = { size = 1, slots = { entry(555, 10) } }
    Summaries.SeedOwners()
    local wbBefore = Summaries.GetCounts(555)
    assert(wbBefore[Summaries.WARBAND_OWNER] and wbBefore[Summaries.WARBAND_OWNER].warband == 10,
        "warband precondition wrong")
    QUI_StorageDB.warband.tabs[12].slots[1] = entry(555, 50)
    Bus.Publish("WarbandChanged", {}) -- synthetic re-dress
    local wbAfterPing = Summaries.GetCounts(555)
    assert(wbAfterPing[Summaries.WARBAND_OWNER].warband == 10,
        "WarbandChanged with {} must NOT invalidate (synthetic re-dress ping)")
    Bus.Publish("WarbandChanged", { 12 }) -- real move
    local wbAfterReal = Summaries.GetCounts(555)
    assert(wbAfterReal[Summaries.WARBAND_OWNER].warband == 50,
        "WarbandChanged with non-empty changed must invalidate and rebuild")
end

print("OK: bags_summaries_test")
