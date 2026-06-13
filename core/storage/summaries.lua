---------------------------------------------------------------------------
-- Core storage: summaries index.
-- Per-owner inverted index: owner → itemID → location → count, rebuilt
-- lazily per dirty owner (owner count is small; GetCounts merges across
-- owners on demand). This is what tooltip counts and search-everywhere
-- query — nothing walks the full cache per lookup.
-- Self-subscribes to the bus (load after bus.lua/store.lua in bags.xml).
-- The module entry MUST call SeedOwners() once after Store.Initialize() or
-- offline characters never enter the index. First query after a seed pays
-- one full rebuild; lookups are O(owners) thereafter.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local Summaries = {}
Storage.Summaries = Summaries

-- Reserved owner key for the account-wide warband bank. A "-"-less key can
-- never collide with a real "Name-Realm" character key.
Summaries.WARBAND_OWNER = ":warband"

-- Prefix for guild owner keys. ":guild:" followed by the "GuildName-Realm"
-- store key. Can never collide with character keys (no leading colon) or
-- WARBAND_OWNER (different prefix).
Summaries.GUILD_PREFIX = ":guild:"

local perOwner = {} -- ownerKey → { itemID → { location → count } }
local dirty = {}    -- ownerKey → true

function Summaries.Invalidate(ownerKey)
    if ownerKey then dirty[ownerKey] = true end
end

function Summaries.InvalidateWarband()
    dirty[Summaries.WARBAND_OWNER] = true
end

--- Mark every known owner dirty (login seed; cheap — rebuilds are lazy).
function Summaries.SeedOwners()
    for _, key in ipairs(Storage.Store.ListCharacters()) do dirty[key] = true end
    dirty[Summaries.WARBAND_OWNER] = true
    for _, guildKey in ipairs(Storage.Store.ListGuilds()) do
        dirty[Summaries.GUILD_PREFIX .. guildKey] = true
    end
end

local function IndexInto(idx, location, container)
    if not container or not container.slots then return end
    for _, entry in pairs(container.slots) do
        if entry and entry.itemID then
            local byItem = idx[entry.itemID]
            if not byItem then byItem = {}; idx[entry.itemID] = byItem end
            byItem[location] = (byItem[location] or 0) + (entry.count or 1)
        end
    end
end

local function RebuildOwner(ownerKey)
    if ownerKey == Summaries.WARBAND_OWNER then
        local idx = {}
        local wb = Storage.Store.GetWarband()
        if wb then
            for _, tab in pairs(wb.tabs or {}) do IndexInto(idx, "warband", tab) end
        end
        perOwner[ownerKey] = idx
        return
    end
    -- Guild owner: ":guild:" .. guildKey
    local guildKey = ownerKey:match("^" .. Summaries.GUILD_PREFIX .. "(.+)$")
    if guildKey then
        local guild = Storage.Store.GetGuild(guildKey)
        if not guild then
            perOwner[ownerKey] = nil -- deleted guild drops out entirely
            return
        end
        local idx = {}
        for _, tab in pairs(guild.tabs or {}) do IndexInto(idx, "guild", tab) end
        perOwner[ownerKey] = idx
        return
    end
    local rec = Storage.Store.GetCharacter(ownerKey)
    if not rec then
        perOwner[ownerKey] = nil -- deleted/unknown owner drops out entirely
        return
    end
    local idx = {}
    for _, bag in pairs(rec.bags) do IndexInto(idx, "bags", bag) end
    for _, tab in pairs(rec.bankTabs) do IndexInto(idx, "bank", tab) end
    -- Phase-6 breadth records all reuse { slots = ..., size = n } (mail and
    -- auctions are list-as-slots) so IndexInto walks them unchanged; its
    -- .slots guard also skips phase-1 placeholder {} records. currencies is
    -- deliberately absent: a flat currencyID→quantity map in a different ID
    -- space than itemIDs.
    IndexInto(idx, "mail", rec.mail)
    IndexInto(idx, "equipped", rec.equipped)
    IndexInto(idx, "auctions", rec.auctions)
    perOwner[ownerKey] = idx
end

local function FlushDirty()
    for ownerKey in pairs(dirty) do
        RebuildOwner(ownerKey)
        dirty[ownerKey] = nil
    end
end

--- Lazily-rebuilt index for one owner. Flushes pending dirty owners first
--- (same path GetCounts uses) then returns perOwner[ownerKey] — nil for an
--- unknown/deleted owner. Internal; consumers use IterateOwnerItems.
local function IndexFor(ownerKey)
    FlushDirty()
    return perOwner[ownerKey]
end

--- Iterate one owner's (lazily rebuilt) index: fn(itemID, { location → count }).
--- ownerKey: a character key, Summaries.WARBAND_OWNER, or a GUILD_PREFIX key.
--- Unknown owner → no error, no iteration. Inner tables are internal index
--- state: READ-ONLY, do not retain across bag/bank events (rebuilds swap them).
function Summaries.IterateOwnerItems(ownerKey, fn)
    local idx = IndexFor(ownerKey)
    if not idx then return end
    for itemID, byLocation in pairs(idx) do
        fn(itemID, byLocation)
    end
end

--- → { [ownerKey] = { [location] = count } }; WARBAND_OWNER keys the warband.
--- Inner tables are internal index state: READ-ONLY, and do not retain them
--- across bag/bank events (rebuilds swap them wholesale).
function Summaries.GetCounts(itemID)
    FlushDirty()
    local out = {}
    for ownerKey, idx in pairs(perOwner) do
        local byItem = idx[itemID]
        if byItem then out[ownerKey] = byItem end
    end
    return out
end

-- Data-layer-internal wiring: scans invalidate their owner.
-- An empty changed array is a synthetic re-dress ping (lock/cooldown visual
-- refresh, not a real move): skip invalidation so tooltip counts stay stable.
Storage.Bus.Subscribe("BagsChanged", function(_, charKey, changed)
    if changed and #changed == 0 then return end -- synthetic re-dress ping
    Summaries.Invalidate(charKey)
end)
Storage.Bus.Subscribe("BankChanged", function(_, charKey, changed)
    if changed and #changed == 0 then return end -- synthetic re-dress ping
    Summaries.Invalidate(charKey)
end)
Storage.Bus.Subscribe("MailChanged", function(_, charKey) Summaries.Invalidate(charKey) end)
Storage.Bus.Subscribe("EquippedChanged", function(_, charKey) Summaries.Invalidate(charKey) end)
Storage.Bus.Subscribe("AuctionsChanged", function(_, charKey) Summaries.Invalidate(charKey) end)
-- CurrenciesChanged is NOT subscribed: currencies never join the item index.
Storage.Bus.Subscribe("WarbandChanged", function(_, changed)
    if changed and #changed == 0 then return end -- synthetic re-dress ping
    Summaries.InvalidateWarband()
end)
Storage.Bus.Subscribe("CharacterDeleted", function(_, charKey) Summaries.Invalidate(charKey) end)
Storage.Bus.Subscribe("GuildChanged", function(_, guildKey)
    Summaries.Invalidate(Summaries.GUILD_PREFIX .. guildKey)
end)
Storage.Bus.Subscribe("GuildDeleted", function(_, guildKey)
    Summaries.Invalidate(Summaries.GUILD_PREFIX .. guildKey)
end)
