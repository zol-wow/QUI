---------------------------------------------------------------------------
-- QUI Chat Module — Per-Channel Color Overrides
-- Stores user-chosen colors for built-in chat types (SAY/YELL/...) and
-- joined custom channels by NAME (not slot).
--
-- Storage: db.profile.chat.channelColors = { [key] = {r, g, b}, ... }
--   - Built-in keys: uppercase strings (SAY, RAID, WHISPER, ...).
--   - Custom keys: channel name as joined ("Trade", "LookingForGroup").
--
-- Colors are applied at RENDER TIME: this module is a pure data store plus a
-- `ColorFor(event, eventArgs)` resolver that the custom display's render
-- transform consults to override a line's r,g,b. It NEVER calls ChangeChatColor
-- or writes Blizzard's ChatTypeInfo table -- doing so taints chat dispatch and
-- poisons ChatHistory_GetAccessID (a secret-string crash on the first secret
-- chat payload). See chat_channel_colors_no_chattypeinfo_write_test.lua.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

-- Load-order guard: chat.lua must run first so ns.QUI.Chat exists for us to
-- attach ChannelColors and the color resolver onto.
assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: channel_colors.lua loaded before chat.lua. Check chat.xml — chat.lua must precede channel_colors.lua.")

local Helpers = ns.Helpers
local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

ns.QUI.Chat.ChannelColors = ns.QUI.Chat.ChannelColors or {}
local ChannelColors = ns.QUI.Chat.ChannelColors

-- Public list of editable built-in chat-type keys, in dropdown display order.
local BUILTIN_KEYS = {
    "SAY", "YELL", "EMOTE",
    "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    "GUILD", "OFFICER",
    "WHISPER", "WHISPER_INFORM",
    "BN_WHISPER", "BN_WHISPER_INFORM",
    "SYSTEM",
}
ChannelColors.BUILTIN_KEYS = BUILTIN_KEYS

-- Friendly display labels for the dropdown.
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
    WHISPER = "Whisper",
    WHISPER_INFORM = "Whisper (sent)",
    BN_WHISPER = "BN Whisper",
    BN_WHISPER_INFORM = "BN Whisper (sent)",
    SYSTEM = "System",
}
ChannelColors.BUILTIN_LABELS = BUILTIN_LABELS

-- Closed-set membership for fast O(1) discrimination of built-in chat-type
-- keys vs. arbitrary channel names. Built once at file load.
local BUILTIN_SET = {}
for i = 1, #BUILTIN_KEYS do BUILTIN_SET[BUILTIN_KEYS[i]] = true end

-- Built-in chat-type keys are a closed set defined above; channel names are
-- arbitrary user strings. Use literal membership rather than a regex so
-- channel names that happen to be all uppercase (e.g. "PVP", "EU", "LFG")
-- aren't misclassified as built-ins.
local function isBuiltinKey(key)
    if type(key) ~= "string" then return false end
    return BUILTIN_SET[key] == true
end

-- Walk GetChannelList() and return a name → "CHANNEL%d" map.
-- GetChannelList returns id1, name1, header1, id2, name2, header2, ...
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

-----------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------

-- Returns "CHANNEL%d" for a given joined channel name, or nil if the user
-- isn't currently in that channel.
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

-- Returns r, g, b for the currently effective color (override if set, else
-- Blizzard's live default read from ChatTypeInfo, else white). Reading
-- ChatTypeInfo is taint-safe -- only writing it poisons chat dispatch.
function ChannelColors.GetEffective(key)
    local store = getDB()
    local c = store and store[key]
    if c then return c[1], c[2], c[3] end

    -- For customs, the default lives under the CURRENT slot key.
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
    -- Only touch keys we manage: BUILTIN_KEYS + currently joined channels.
    -- Leaves orphan imported keys (e.g. MONSTER_SAY) untouched in SV.
    for i = 1, #BUILTIN_KEYS do
        store[BUILTIN_KEYS[i]] = nil
    end
    local nameToSlot = buildNameToSlotMap()
    for name in pairs(nameToSlot) do
        store[name] = nil
    end
end

-----------------------------------------------------------------------
-- Render-time color resolver (consumed by chat.lua)
-----------------------------------------------------------------------

-- Resolve the override color for one rendered chat line. Returns r, g, b for a
-- user override on this event's key, else nil (leave Blizzard's color). Never
-- mutates any Blizzard global -- this is the whole point of the render-time
-- approach. Secret-safe: returns nil on secret event / channel name.
function ChannelColors.ColorFor(event, eventArgs)
    if type(event) ~= "string" or event == "" then return nil end
    local store = getDB()
    if not store then return nil end

    local key
    if event == "CHAT_MSG_CHANNEL" then
        if type(eventArgs) ~= "table" then return nil end
        local name = eventArgs[9]  -- channel base name; matches the stored custom key
        if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
        key = name
    else
        key = event:match("^CHAT_MSG_(.+)$")  -- SAY / WHISPER / BN_WHISPER_INFORM / ...
        if not key then return nil end
    end

    local c = store[key]
    if c then return c[1], c[2], c[3] end
    return nil
end

-- Register the resolver for the QUI display's render path (display_layer's
-- RenderEntry re-resolves per render so live override edits recolor rebuilds;
-- capture also bakes the effective color via Format.ColorForTypeKey).
ns.QUI.Chat._lineColorResolver = ChannelColors.ColorFor
