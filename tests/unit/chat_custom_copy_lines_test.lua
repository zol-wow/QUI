-- tests/unit/chat_custom_copy_lines_test.lua
-- Run: lua tests/unit/chat_custom_copy_lines_test.lua
-- Verifies Copy.GetCustomDisplayLines: store-sourced, CleanMessage-stripped,
-- secrets replaced with the protected placeholder, empty lines dropped.

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

-- copy.lua module-scope needs (stub minimally; extend ONLY if loadfile errors)
local function noopFrame()
    local f = {}
    local function noop() end
    return setmetatable(f, { __index = function() return noop end })
end
function _G.CreateFrame() return noopFrame() end
_G.UIParent = noopFrame()
function _G.hooksecurefunc() end
_G.StaticPopupDialogs = {}
_G.NUM_CHAT_WINDOWS = 10

local settings = { enabled = true, copyHistorySource = "live" }
local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    UIKit = setmetatable({}, { __index = function() return function() end end }),
    QUI = { Chat = { _internals = setmetatable({
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
        IsChatMessagingLockedDown = function() return false end,
        GetThemeColors = function() return { bg = {0,0,0,1}, text = {1,1,1,1}, textDim = {.7,.7,.7,1}, accent = {.2,.8,.6,1}, border = {1,1,1,.1} } end,
        GetAccent = function() return { .2, .8, .6, 1 } end,
    }, { __index = function() return function() end end }) } },
}

-- Real store feeds the copy source
assert(loadfile("QUI_Chat/chat/message_store.lua"))("QUI", ns)
assert(loadfile("QUI_Chat/chat/copy.lua"))("QUI", ns)
local Copy = ns.QUI.Chat.Copy
local Store = ns.QUI.Chat.MessageStore

Store.Append({ m = "|cff00ff00|Hplayer:Ann|h[Ann]|h|r: hello |TInterface\\icon:0|t", e = "CHAT_MSG_SAY" })
Store.Append({ m = secret, s = true, e = "CHAT_MSG_RAID_WARNING" })
Store.Append({ m = "plain", e = "CHAT_MSG_SAY" })
-- Baked base color (GMOTD green) wraps the line so the copy window renders it
-- like the chat display; inner |r terminators are substituted with the base
-- color (a bare |r would reset to the editbox color, not the line color).
Store.Append({ m = "Guild MOTD: Raid tonight", r = 0.25, g = 1, b = 0.25, e = "GUILD_MOTD", k = "GUILD" })
Store.Append({ m = "|cffff0000Bob|r says hi", r = 0.25, g = 1, b = 0.25, e = "CHAT_MSG_GUILD" })
Store.Append({ m = "kill |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t now", e = "CHAT_MSG_SAY" })
Store.Append({ m = "white", r = 1, g = 1, b = 1, e = "CHAT_MSG_SAY" })

local lines = Copy.GetCustomDisplayLines()
assert(#lines == 7, "seven lines, got " .. #lines)
assert(lines[1] == "|cff00ff00Ann|r: hello ",
    "texture/link markup stripped, color escapes kept, got " .. tostring(lines[1]))
assert(lines[2] == "??? (protected message)", "secret placeholder")
assert(lines[3] == "plain", "plain passthrough (no baked color -> no wrap)")
assert(lines[4] == "|cff40ff40Guild MOTD: Raid tonight|r",
    "baked base color wraps the line, got " .. tostring(lines[4]))
assert(lines[5] == "|cff40ff40|cffff0000Bob|cff40ff40 says hi|r",
    "inner |r substituted with the line base color, got " .. tostring(lines[5]))
assert(lines[6] == "kill {rt8} now", "raid icon converted before texture strip, got " .. tostring(lines[6]))
assert(lines[7] == "white", "white base color skips the wrap")

print("OK: chat_custom_copy_lines_test")
