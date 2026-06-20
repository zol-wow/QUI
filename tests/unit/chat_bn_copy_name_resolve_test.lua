-- tests/unit/chat_bn_copy_name_resolve_test.lua
-- Run: lua tests/unit/chat_bn_copy_name_resolve_test.lua
-- Regression: a BN friend-online toast stores the friend name as a |K kstring
-- inside the |HBNplayer link (chat SMF renders it; a copy EditBox cannot, so
-- the kstring strip would blank it to "???"). copy.CleanMessage must resolve
-- the account name from the bnID embedded in the link data and substitute
-- plain text BEFORE the kstring strip, so the copy window shows the friend's
-- name. Mirrors the real in-game shape: sender is a |K kstring, bnID present.

-- ---- format module deps ----
_G.C_BattleNet = { GetAccountInfoByID = function(id)
    if id == 77 then
        -- Real in-game shape (verified via debug dump): for BN friend toasts
        -- accountInfo.accountName comes back AS THE SAME |K kstring as the
        -- sender, so it is useless for the copy window. battleTag is the plain,
        -- reliable field; copy must key on it (truncated at '#').
        return { accountName = "|Kj33|k", battleTag = "Quazii#1234",
                 gameAccountInfo = { characterName = nil } }
    end
    return nil
end }
_G.ChatTypeInfo = setmetatable({}, { __index = function() return nil end,
    __newindex = function() error("no write") end })
_G.BN_INLINE_TOAST_FRIEND_ONLINE = "%s has come online."

local function explode() error("secret op", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode })
local secrets = { [secret] = true }

local settingsF = { modifiers = { classColors = { enabled = true },
    channelShorten = { enabled = true, preset = "letter" } } }
local nsF = {
    Helpers = { IsSecretValue = function(v) return secrets[v] == true end },
    QUI = { Chat = { _internals = { GetSettings = function() return settingsF end } } },
}
assert(loadfile("QUI_Chat/chat/message_format.lua"))("QUI", nsF)
local F = nsF.QUI.Chat.MessageFormat

-- Real in-game arg2 is a |K kstring; bnID (arg13) present.
local line = F.BuildEventLine("CHAT_MSG_BN_INLINE_TOAST_ALERT",
    { text = "FRIEND_ONLINE", sender = "|Kq1|k", bnID = 77, lineID = 99 })
print("formatted entry.m = " .. tostring(line))

-- ---- copy module deps ----
local function noopFrame()
    local f = {}; local function noop() end
    return setmetatable(f, { __index = function() return noop end })
end
function _G.CreateFrame() return noopFrame() end
_G.UIParent = noopFrame()
function _G.hooksecurefunc() end
_G.StaticPopupDialogs = {}
_G.NUM_CHAT_WINDOWS = 10

local settingsC = { enabled = true, copyHistorySource = "live" }
local nsC = {
    Helpers = { IsSecretValue = function(v) return secrets[v] == true end },
    UIKit = setmetatable({}, { __index = function() return function() end end }),
    QUI = { Chat = {
        _lineColorResolver = function() return nil end,
        _internals = setmetatable({
            GetSettings = function() return settingsC end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            IsChatMessagingLockedDown = function() return false end,
            GetThemeColors = function() return { bg={0,0,0,1}, text={1,1,1,1}, textDim={.7,.7,.7,1}, accent={.2,.8,.6,1}, border={1,1,1,.1} } end,
            GetAccent = function() return { .2, .8, .6, 1 } end,
        }, { __index = function() return function() end end }) } },
}
assert(loadfile("QUI_Chat/chat/message_store.lua"))("QUI", nsC)
assert(loadfile("QUI_Chat/chat/copy.lua"))("QUI", nsC)
local Store = nsC.QUI.Chat.MessageStore

Store.Append({ m = line, e = "CHAT_MSG_BN_INLINE_TOAST_ALERT", k = "BN_INLINE_TOAST_ALERT" })
local copyLines = nsC.QUI.Chat.Copy.GetCustomDisplayLines()
print("copy line = " .. tostring(copyLines[1]))

assert(not copyLines[1]:find("?"), "copy line should NOT contain ??? -- got: " .. tostring(copyLines[1]))
-- accountName is empty in the mock, so BNet display name = battleTag truncated
-- at '#' ("Quazii#1234" -> "Quazii"), matching BNet_GetBNetAccountName.
assert(copyLines[1]:find("[Quazii]", 1, true),
    "copy line should show the BNet account display name in brackets -- got: " .. tostring(copyLines[1]))
assert(not copyLines[1]:find("#"),
    "battleTag discriminator must be truncated -- got: " .. tostring(copyLines[1]))
print("OK: chat_bn_copy_name_resolve_test")
