local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local Summaries = {}
Storage.Summaries = Summaries

Summaries.WARBAND_OWNER = ":warband"

Summaries.GUILD_PREFIX = ":guild:"

local perOwner = {}
local dirty = {}

function Summaries.Invalidate(ownerKey)
    if ownerKey then dirty[ownerKey] = true end
end

function Summaries.InvalidateWarband()
    dirty[Summaries.WARBAND_OWNER] = true
end

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
    local guildKey = ownerKey:match("^" .. Summaries.GUILD_PREFIX .. "(.+)$")
    if guildKey then
        local guild = Storage.Store.GetGuild(guildKey)
        if not guild then
            perOwner[ownerKey] = nil
            return
        end
        local idx = {}
        for _, tab in pairs(guild.tabs or {}) do IndexInto(idx, "guild", tab) end
        perOwner[ownerKey] = idx
        return
    end
    local rec = Storage.Store.GetCharacter(ownerKey)
    if not rec then
        perOwner[ownerKey] = nil
        return
    end
    local idx = {}
    for _, bag in pairs(rec.bags) do IndexInto(idx, "bags", bag) end
    for _, tab in pairs(rec.bankTabs) do IndexInto(idx, "bank", tab) end
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

local function IndexFor(ownerKey)
    FlushDirty()
    return perOwner[ownerKey]
end

function Summaries.IterateOwnerItems(ownerKey, fn)
    local idx = IndexFor(ownerKey)
    if not idx then return end
    for itemID, byLocation in pairs(idx) do
        fn(itemID, byLocation)
    end
end

function Summaries.GetCounts(itemID)
    FlushDirty()
    local out = {}
    for ownerKey, idx in pairs(perOwner) do
        local byItem = idx[itemID]
        if byItem then out[ownerKey] = byItem end
    end
    return out
end

Storage.Bus.Subscribe("BagsChanged", function(_, charKey, changed)
    if changed and #changed == 0 then return end
    Summaries.Invalidate(charKey)
end)
Storage.Bus.Subscribe("BankChanged", function(_, charKey, changed)
    if changed and #changed == 0 then return end
    Summaries.Invalidate(charKey)
end)
Storage.Bus.Subscribe("MailChanged", function(_, charKey) Summaries.Invalidate(charKey) end)
Storage.Bus.Subscribe("EquippedChanged", function(_, charKey) Summaries.Invalidate(charKey) end)
Storage.Bus.Subscribe("AuctionsChanged", function(_, charKey) Summaries.Invalidate(charKey) end)
Storage.Bus.Subscribe("WarbandChanged", function(_, changed)
    if changed and #changed == 0 then return end
    Summaries.InvalidateWarband()
end)
Storage.Bus.Subscribe("CharacterDeleted", function(_, charKey) Summaries.Invalidate(charKey) end)
Storage.Bus.Subscribe("GuildChanged", function(_, guildKey)
    Summaries.Invalidate(Summaries.GUILD_PREFIX .. guildKey)
end)
Storage.Bus.Subscribe("GuildDeleted", function(_, guildKey)
    Summaries.Invalidate(Summaries.GUILD_PREFIX .. guildKey)
end)
