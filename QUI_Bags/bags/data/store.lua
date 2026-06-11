-- luacheck: globals QUI_StorageDB
---------------------------------------------------------------------------
-- Bags data layer: persistent store (QUI_StorageDB).
-- Dumb storage only: schema init/versioning and accessors. Scanners write
-- through the records returned here; content events are published by scanners.
-- The ONE exception: deletions are published by the store itself
-- (CharacterDeleted/GuildDeleted) — no scanner can observe them.
-- NEVER lives in the AceDB profile — profile import/export and
-- the shipped-defaults shadow must not see inventory data.
--
-- Slot entry shape (the ONLY persisted item record — keep minimal):
--   { itemID, count, link, quality, icon, isBound }
-- Phase-6 variations on that shape (same keys, two documented deltas):
--   mail entries swap isBound for daysLeft (bind state unknowable, expiry
--   matters); auction entries omit quality/isBound (OwnedAuctionInfo
--   carries neither — count-driven location).
-- Derived fields (class/subclass/ilvl/expansion) are session-cached in
-- item_info.lua and never persisted.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Store = {}
Bags.Store = Store

Store.SCHEMA_VERSION = 1

local db -- → QUI_StorageDB after Initialize()

local function NewCharacterRecord()
    return {
        details = {},
        bags = {},      -- [bagID 0..5]  = { size, slots = { [slot] = entry } }
        bankTabs = {},  -- [bagID 6..11] = { size, name, icon, depositFlags, slots }
        -- Phase-6 breadth records. All written wholesale by their scanner;
        -- {} is the pre-first-scan placeholder (summaries' .slots guard
        -- skips it). mail/auctions reuse { slots = ..., size = n } with a
        -- DENSE LIST as slots so IndexInto walks them unchanged.
        mail = {},      -- { size = n, slots = { entry+daysLeft list } } (mailbox sessions)
        equipped = {},  -- { size = 19, slots = { [invSlot] = entry } }
        currencies = {},-- { [currencyID] = quantity } — flat map, never joins item summaries
        auctions = {},  -- { size = n, slots = { entry list } } (AH sessions)
    }
end

function Store.Initialize()
    Store.readOnly = nil
    if type(QUI_StorageDB) ~= "table" then
        QUI_StorageDB = {}
    end
    db = QUI_StorageDB
    if db.version ~= nil and db.version > Store.SCHEMA_VERSION then
        -- Written by a newer QUI: leave untouched, read-only this session.
        Store.readOnly = true
        print("|cFFFF6666QUI:|r bags storage was written by a newer QUI version; cache is read-only this session.")
        return db
    end
    -- db.version < SCHEMA_VERSION: future migrations dispatch here (none for v1).
    db.version = Store.SCHEMA_VERSION
    db.characters = db.characters or {}
    db.guilds = db.guilds or {}
    db.warband = db.warband or { tabs = {}, money = 0 }
    return db
end

function Store.IsReady()
    return db ~= nil and not Store.readOnly
end

--- Initialize() ran this session (regardless of read-only). Distinct from
--- IsReady so a lazy-init caller doesn't re-run Initialize (and re-print
--- the read-only warning) every refresh of a newer-version cache.
function Store.IsInitialized()
    return db ~= nil
end

-- Cache keys use the NORMALIZED realm (no spaces/dashes/apostrophes — the
-- UnitFullName/GetNormalizedRealmName format) in EVERY path. Mixing in
-- GetRealmName()'s display name ("Aerie Peak" vs "AeriePeak") would fork
-- the same character into two records across sessions depending on which
-- API answered at login. Fallback chain: UnitFullName realm (normalized,
-- can be nil early) → GetNormalizedRealmName (PlayerScriptDocumentation;
-- post-login) → GetRealmName stripped by hand (degraded last resort, same
-- format). Display realm for UI lives in details.realm, never in keys.
local function NormalizedRealm()
    local _, realm = UnitFullName("player")
    if realm and realm ~= "" then return realm end
    if type(GetNormalizedRealmName) == "function" then
        realm = GetNormalizedRealmName()
        if realm and realm ~= "" then return realm end
    end
    realm = GetRealmName()
    return realm and realm:gsub("[%s%-']", "") or nil
end

function Store.GetCurrentCharacterKey()
    local name = UnitFullName("player")
    if not name then return nil end
    local realm = NormalizedRealm()
    if not realm or realm == "" then return nil end
    return name .. "-" .. realm
end

function Store.EnsureCurrentCharacter()
    if not Store.IsReady() then return nil end
    local key = Store.GetCurrentCharacterKey()
    if not key then return nil end
    local rec = db.characters[key]
    if not rec then
        rec = NewCharacterRecord()
        db.characters[key] = rec
    end
    local d = rec.details
    -- UnitClass/UnitRace: MayReturnNothing (guard; for "player" this fires at
    -- login when the unit is ready, so nil is unlikely but possible mid-session).
    local _, classFilename = UnitClass("player")
    if classFilename then d.class = classFilename end
    local _, englishRace = UnitRace("player")
    if englishRace then d.race = englishRace end
    local faction = UnitFactionGroup("player")
    if faction then d.faction = faction end
    -- Display realm (spaces kept) — UI-facing metadata only, never key
    -- material. GetRealmName is the display source; normalized fallback.
    d.realm = GetRealmName() or NormalizedRealm()
    d.guild = GetGuildInfo("player")
    d.money = GetMoney()
    d.lastSeen = time()
    return rec, key
end

function Store.GetCharacter(key)
    return db and db.characters and db.characters[key] or nil
end

function Store.GetCurrentCharacter()
    return Store.GetCharacter(Store.GetCurrentCharacterKey())
end

function Store.ListCharacters()
    local keys = {}
    if db and db.characters then
        for k in pairs(db.characters) do keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

function Store.DeleteCharacter(key)
    if not Store.IsReady() then return end
    if db and db.characters and db.characters[key] then
        db.characters[key] = nil
        Bags.Bus.Publish("CharacterDeleted", key)
    end
end

function Store.GetWarband()
    return db and db.warband or nil
end

function Store.GetGuild(key)
    return db and db.guilds and db.guilds[key] or nil
end

function Store.ListGuilds()
    local keys = {}
    if db and db.guilds then
        for k in pairs(db.guilds) do keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

function Store.DeleteGuild(key)
    if not Store.IsReady() then return end
    if db and db.guilds and db.guilds[key] then
        db.guilds[key] = nil
        Bags.Bus.Publish("GuildDeleted", key)
    end
end

--- Creates the guild record for `key` if absent; returns it (idempotent).
--- Returns nil when the store is not ready or key is nil.
function Store.EnsureGuild(key)
    if not Store.IsReady() then return nil end
    if not key then return nil end
    local rec = db.guilds[key]
    if not rec then
        rec = { tabs = {}, money = 0, details = {} }
        db.guilds[key] = rec
    end
    return rec
end

--- Returns the current character's guild key ("GuildName-Realm"), or nil when
--- unguilded. Uses the same realm-fallback as GetCurrentCharacterKey.
function Store.GetCurrentGuildKey()
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local realm = NormalizedRealm()
    if not realm or realm == "" then return nil end
    return guildName .. "-" .. realm
end
