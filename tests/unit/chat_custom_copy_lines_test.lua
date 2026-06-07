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
assert(loadfile("modules/chat/message_store.lua"))("QUI", ns)
assert(loadfile("modules/chat/copy.lua"))("QUI", ns)
local Copy = ns.QUI.Chat.Copy
local Store = ns.QUI.Chat.MessageStore

Store.Append({ m = "|cff00ff00|Hplayer:Ann|h[Ann]|h|r: hello |TInterface\\icon:0|t", e = "CHAT_MSG_SAY" })
Store.Append({ m = secret, s = true, e = "CHAT_MSG_RAID_WARNING" })
Store.Append({ m = "plain", e = "CHAT_MSG_SAY" })

local lines = Copy.GetCustomDisplayLines()
assert(#lines == 3, "three lines, got " .. #lines)
assert(lines[1] == "Ann: hello ", "markup stripped, got " .. tostring(lines[1]))
assert(lines[2] == "??? (protected message)", "secret placeholder")
assert(lines[3] == "plain", "plain passthrough")

print("OK: chat_custom_copy_lines_test")
