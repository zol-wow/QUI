local ADDON_NAME, ns = ...

assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: channel_colors.lua loaded before chat.lua. Check chat.xml — chat.lua must precede channel_colors.lua.")

local Helpers = ns.Helpers
local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

ns.QUI.Chat.ChannelColors = ns.QUI.Chat.ChannelColors or {}
local ChannelColors = ns.QUI.Chat.ChannelColors

local BUILTIN_KEYS = {
    "SAY", "YELL", "EMOTE",
    "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    "GUILD", "OFFICER", "GUILD_DISCORD",
    "WHISPER", "WHISPER_INFORM",
    "BN_WHISPER", "BN_WHISPER_INFORM",
    "SYSTEM",
}
ChannelColors.BUILTIN_KEYS = BUILTIN_KEYS

local BUILTIN_LABELS = {
    SAY = "Say",
    YELL = "Yell",
    EMOTE = "Emote",
    PARTY = "Party",
    PARTY_LEADER = "Party Leader",
    RAID = "Raid",
    RAID_LEADER = "Raid Leader",
    RAID_WARNING = "Raid Warning",
    INSTANCE_CHAT = "Instance",
    INSTANCE_CHAT_LEADER = "Instance Leader",
    GUILD = "Guild",
    OFFICER = "Officer",
    GUILD_DISCORD = "Guild Discord",
    WHISPER = "Whisper",
    WHISPER_INFORM = "Whisper (sent)",
    BN_WHISPER = "BN Whisper",
    BN_WHISPER_INFORM = "BN Whisper (sent)",
    SYSTEM = "System",
}
ChannelColors.BUILTIN_LABELS = BUILTIN_LABELS

local BUILTIN_SET = {}
for i = 1, #BUILTIN_KEYS do BUILTIN_SET[BUILTIN_KEYS[i]] = true end

local function isBuiltinKey(key)
    if type(key) ~= "string" then return false end
    return BUILTIN_SET[key] == true
end

local function buildNameToSlotMap()
    local map = {}
    if type(GetChannelList) ~= "function" then return map end
    local data = { GetChannelList() }
    for i = 1, #data, 3 do
        local slot, name, header = data[i], data[i + 1], data[i + 2]
        if slot and name and not header then
            map[name] = "CHANNEL" .. slot
        end
    end
    return map
end

local function getDB()
    local db = _G.QUI and _G.QUI.db and _G.QUI.db.profile and _G.QUI.db.profile.chat
    if not db then return nil end
    db.channelColors = db.channelColors or {}
    return db.channelColors
end

function ChannelColors.SlotForChannel(name)
    if type(name) ~= "string" or name == "" then return nil end
    return buildNameToSlotMap()[name]
end

function ChannelColors.IsBuiltin(key)
    return isBuiltinKey(key)
end

function ChannelColors.HasOverride(key)
    local store = getDB()
    return (store and store[key] ~= nil) or false
end

function ChannelColors.GetEffective(key)
    local store = getDB()
    local c = store and store[key]
    if c then return c[1], c[2], c[3] end

    local lookupKey = key
    if not isBuiltinKey(key) then
        lookupKey = ChannelColors.SlotForChannel(key)
    end
    local info = lookupKey and type(ChatTypeInfo) == "table" and ChatTypeInfo[lookupKey]
    if info and info.r then return info.r, info.g, info.b end
    return 1, 1, 1
end

function ChannelColors.Set(key, r, g, b)
    if type(key) ~= "string" or key == "" then return end
    local store = getDB()
    if not store then return end
    store[key] = { r, g, b }
end

function ChannelColors.Clear(key)
    if type(key) ~= "string" or key == "" then return end
    local store = getDB()
    if not store then return end
    store[key] = nil
end

function ChannelColors.ClearAll()
    local store = getDB()
    if not store then return end
    for key in pairs(store) do
        store[key] = nil
    end
end

function ChannelColors.ColorFor(event, eventArgs)
    if type(event) ~= "string" or event == "" then return nil end
    local store = getDB()
    if not store then return nil end

    local key
    if event == "CHAT_MSG_CHANNEL" then
        if type(eventArgs) ~= "table" then return nil end
        local name = eventArgs[9]
        if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
        key = name
    else
        key = event:match("^CHAT_MSG_(.+)$")
        if not key then return nil end
    end

    local c = store[key]
    if c then return c[1], c[2], c[3] end
    return nil
end

ns.QUI.Chat._lineColorResolver = ChannelColors.ColorFor
