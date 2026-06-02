-- tests/unit/chat_channel_colors_colorfor_test.lua
-- Run: lua tests/unit/chat_channel_colors_colorfor_test.lua
-- Verifies ChannelColors.ColorFor maps chat events -> stored override colors,
-- including all whisper types and custom channels by name, and is secret-safe.

function CreateFrame() local f = {}; function f:RegisterEvent() end; function f:SetScript() end; return f end
function GetChannelList() return end
ChatTypeInfo = {}

local secret = setmetatable({}, { __tostring = function() return "secret" end })
_G.QUI = { db = { profile = { chat = { channelColors = {
    SAY = { 0.1, 0.2, 0.3 },
    WHISPER = { 0.4, 0.5, 0.6 },
    BN_WHISPER_INFORM = { 0.7, 0.8, 0.9 },
    ["Trade"] = { 0.11, 0.22, 0.33 },
} } } } }

local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = { _afterRefresh = {}, _internals = {
        GetSettings = function() return { enabled = true } end,
        IsChatEnabled = function() return true end,
        IsChatMessagingLockedDown = function() return false end,
    } } },
}

assert(loadfile("modules/chat/channel_colors.lua"))("QUI", ns)
local CC = ns.QUI.Chat.ChannelColors

local function eq(label, got, want)
    assert(got == want, label .. ": expected " .. tostring(want) .. " got " .. tostring(got))
end

local r, g, b = CC.ColorFor("CHAT_MSG_SAY")
eq("SAY r", r, 0.1); eq("SAY g", g, 0.2); eq("SAY b", b, 0.3)

r = CC.ColorFor("CHAT_MSG_WHISPER"); eq("WHISPER r", r, 0.4)
r = CC.ColorFor("CHAT_MSG_BN_WHISPER_INFORM"); eq("BN inform r", r, 0.7)

r, g, b = CC.ColorFor("CHAT_MSG_CHANNEL", { [9] = "Trade" })
eq("channel r", r, 0.11); eq("channel b", b, 0.33)

assert(CC.ColorFor("CHAT_MSG_GUILD") == nil, "no override -> nil")
assert(CC.ColorFor("CHAT_MSG_CHANNEL", { [9] = "Trade", [10] = 0 }) ~= nil, "named channel resolves")
assert(CC.ColorFor("CHAT_MSG_CHANNEL", { [9] = secret }) == nil, "secret channel name -> nil")
assert(CC.ColorFor("CHAT_MSG_CHANNEL", { [9] = "Unknown" }) == nil, "unset channel -> nil")
assert(CC.ColorFor(secret) == nil, "secret event -> nil")
assert(CC.ColorFor("CHAT_MSG_CHANNEL", "notatable") == nil, "bad eventArgs -> nil")

-- And the resolver is registered for chat.lua to pull.
assert(ns.QUI.Chat._lineColorResolver == CC.ColorFor, "ColorFor must be registered as _lineColorResolver")

print("OK: chat_channel_colors_colorfor_test")
