-- tests/unit/chat_channel_colors_no_chattypeinfo_write_test.lua
-- Run: lua tests/unit/chat_channel_colors_no_chattypeinfo_write_test.lua
--
-- Regression guard: channel_colors.lua must NEVER call ChangeChatColor nor write
-- ChatTypeInfo. ChangeChatColor fires UPDATE_CHAT_COLOR whose Blizzard handler
-- writes ChatTypeInfo[strupper(key)].r/g/b; from addon code that taints chat and
-- poisons ChatHistory_GetAccessID (secret-string crash on RAID_WARNING/MONSTER_YELL).
-- FAILS on the pre-fix source (Set/apply call ChangeChatColor); PASSES once the
-- feature is render-time only.

local changeChatColorCalls = 0
local writes = {}
local function guardedTypeTable(name)
    return setmetatable({}, { __newindex = function(t, k, v)
        writes[#writes + 1] = name .. "." .. tostring(k)
        rawset(t, k, v)
    end })
end

ChatTypeInfo = {}
for _, t in ipairs({ "SAY", "YELL", "RAID", "RAID_WARNING", "GUILD", "WHISPER", "CHANNEL1" }) do
    ChatTypeInfo[t] = guardedTypeTable(t)
end

-- Mirror Blizzard's UPDATE_CHAT_COLOR handler so the test fails on any
-- ChangeChatColor call (same modeling the class_colors test does for
-- SetChatColorNameByClass).
function ChangeChatColor(key, r, g, b)
    changeChatColorCalls = changeChatColorCalls + 1
    local info = ChatTypeInfo[string.upper(key)]
    if info then info.r, info.g, info.b = r, g, b end
end

function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
end
function GetChannelList() return end

_G.QUI = { db = { profile = { chat = { channelColors = {} } } } }

local settings = { enabled = true }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = {
        _afterRefresh = {},
        _internals = {
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            IsChatMessagingLockedDown = function() return false end,
        },
    } },
}

assert(loadfile("modules/chat/channel_colors.lua"))("QUI", ns)
local CC = assert(ns.QUI.Chat.ChannelColors, "ChannelColors should load")

-- Drive every public mutation + any refresh hooks.
CC.Set("SAY", 1, 0, 0)
CC.Set("RAID_WARNING", 0, 1, 0)
CC.Clear("SAY")
CC.ClearAll()
for _, fn in ipairs(ns.QUI.Chat._afterRefresh) do fn() end

assert(changeChatColorCalls == 0,
    "channel_colors.lua must NOT call ChangeChatColor (taints ChatTypeInfo). Calls: " .. changeChatColorCalls)
assert(#writes == 0,
    "channel_colors.lua must NOT write ChatTypeInfo. Offending: "
        .. (next(writes) and table.concat(writes, ", ") or "(none)"))

print("OK: chat_channel_colors_no_chattypeinfo_write_test")
