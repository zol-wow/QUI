-- luacheck: globals QUI_StorageDB
local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue
local Storage = ns.Storage or {}; ns.Storage = Storage

local Store = {}
Storage.Store = Store

Store.SCHEMA_VERSION = 2

local db

local function NewCharacterRecord()
    return {
        details = {},
        bags = {},
        bankTabs = {},
        mail = {},
        equipped = {},
        currencies = {},
        auctions = {},
        professions = {},
        reputations = {},
        weeklies = {},
        lockouts = {},
    }
end

function Store.Initialize()
    Store.readOnly = nil
    if type(QUI_StorageDB) ~= "table" then
        QUI_StorageDB = {}
    end
    db = QUI_StorageDB
    if db.version ~= nil and db.version > Store.SCHEMA_VERSION then
        Store.readOnly = true
        print("|cFFFF6666QUI:|r character storage was written by a newer QUI version; cache is read-only this session.")
        return db
    end
    if (db.version or 0) < 2 then
        for _, rec in pairs(db.characters or {}) do
            if type(rec) == "table" then
                rec.professions = rec.professions or {}
                rec.reputations = rec.reputations or {}
                rec.weeklies = rec.weeklies or {}
                rec.lockouts = rec.lockouts or {}
            end
        end
    end
    db.version = Store.SCHEMA_VERSION
    db.characters = db.characters or {}
    db.guilds = db.guilds or {}
    db.warband = db.warband or { tabs = {}, money = 0 }
    db.factionNames = db.factionNames or {}
    db.factionGroups = db.factionGroups or {}
    return db
end

function Store.IsReady()
    return db ~= nil and not Store.readOnly
end

function Store.IsInitialized()
    return db ~= nil
end

local function NormalizedRealm()
    local _, realm = UnitFullName("player")
    if issecretvalue and issecretvalue(realm) then
        realm = nil -- @secret-policy: reject-secret-value (next realm source decides)
    end
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
    if issecretvalue and issecretvalue(name) then
        name = nil -- @secret-policy: reject-secret-value (store stays unkeyed this pass)
    end
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
    -- @secret-policy: collapse-only
    local _, classFilename = UnitClass("player")
    if issecretvalue and issecretvalue(classFilename) then classFilename = nil end
    if classFilename then d.class = classFilename end
    local _, englishRace = UnitRace("player")
    if issecretvalue and issecretvalue(englishRace) then englishRace = nil end -- @secret-policy: collapse-only
    if englishRace then d.race = englishRace end
    local faction = UnitFactionGroup("player")
    if faction then d.faction = faction end
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
        Storage.Bus.Publish("CharacterDeleted", key)
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
        Storage.Bus.Publish("GuildDeleted", key)
    end
end

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

function Store.GetCurrentGuildKey()
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local realm = NormalizedRealm()
    if not realm or realm == "" then return nil end
    return guildName .. "-" .. realm
end

function Store.GetFactionNames()
    return db and db.factionNames or nil
end

function Store.GetFactionGroups()
    return db and db.factionGroups or nil
end
