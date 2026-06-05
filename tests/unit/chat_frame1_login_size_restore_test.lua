-- tests/unit/chat_frame1_login_size_restore_test.lua
-- Run: lua tests/unit/chat_frame1_login_size_restore_test.lua
--
-- Two runtime behaviors that must live on the main chat path (chat.lua), without
-- ever touching ChatFrame1's protected Edit Mode geometry:
--
--   1. SIZE RESTORE. QUI stores ChatFrame1's width/height in
--      profile.chat.frameSize when the user resizes it. Blizzard does not
--      persist a custom size on its preset Edit Mode layouts, so on login QUI
--      must re-apply the stored size with a PLAIN SetSize (SetSize is not one of
--      Blizzard's Edit-Mode-overridden setters, so it does not re-enter the
--      secure EditModeManager chain). It must never detach/reparent/SetPoint.
--
--   2. SELECTION SUPPRESSION. While Blizzard's Edit Mode is open, the chat
--      frame's blue selection box + resize handle are visual noise. chat.lua
--      hides them by zeroing the .Selection / .EditModeResizeButton overlay
--      alpha (never Hide(): Blizzard's magnetic-snap loop reads Selection:GetRect
--      which returns nil while hidden and errors). It touches only the child
--      overlays, never ChatFrame1's own secure Edit Mode state.

local function noop() end

local function readAll(path)
    local f = assert(io.open(path, "rb"), "failed to open " .. path)
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

-- The runtime path still must not reference the protected detach/sync helper.
local chatSrc = readAll("modules/chat/chat.lua")
assert(not chatSrc:find("DetachFromEditMode", 1, true),
    "runtime chat.lua must not reference the ChatFrame1 detach helper")
assert(not chatSrc:find("SyncToStored", 1, true),
    "runtime chat.lua must not reference the ChatFrame1 sync helper")

local settings = {
    enabled = true,
    timestamps = { enabled = false },
    urls = { enabled = false },
    modifiers = {},
    hyperlinks = { coordinates = false, friendlyURLs = false },
    frameSize = { w = 500, h = 300 },
}

local function createStateTable()
    local state = setmetatable({}, { __mode = "k" })
    return state, function(key)
        local value = state[key]
        if not value then
            value = {}
            state[key] = value
        end
        return value
    end
end

-- Record hooksecurefunc(table, "method", fn) so we can fire Blizzard hooks.
local hooks = {}
function hooksecurefunc(a, b, c)
    if type(a) == "table" then hooks[b] = c end
end

C_Timer = { After = function(_, callback) callback() end }
C_ChatInfo = {
    _locked = false,
    InChatMessagingLockdown = function()
        return C_ChatInfo._locked
    end,
}

function date() return "12:34" end
function geterrorhandler() return function(err) error(err, 2) end end
function InCombatLockdown() return false end

local eventFrame
local function makeFrame()
    local frame = { _scripts = {}, _shown = true }
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript(script, handler)
        self._scripts[script] = handler
        if script == "OnEvent" then
            eventFrame = self
            self.OnEvent = handler
        end
    end
    function frame:GetScript(script) return self._scripts[script] end
    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    return frame
end
function CreateFrame() return makeFrame() end

NUM_CHAT_WINDOWS = 1

local function makeOverlay()
    local o = { _alpha = 1, _mouse = true }
    function o:SetAlpha(a) self._alpha = a end
    function o:GetAlpha() return self._alpha end
    function o:EnableMouse(enable) self._mouse = enable end
    return o
end

ChatFrame1 = { _w = 200, _h = 100, Selection = makeOverlay(), EditModeResizeButton = makeOverlay() }
function ChatFrame1:SetSize(w, h) self._w, self._h = w, h end
function ChatFrame1:GetWidth() return self._w end
function ChatFrame1:GetHeight() return self._h end
DEFAULT_CHAT_FRAME = ChatFrame1

EditModeManagerFrame = {}
function EditModeManagerFrame:EnterEditMode() end
function EditModeManagerFrame:ExitEditMode() end

UIParent = makeFrame()

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function() return settings end
        end,
        CreateStateTable = createStateTable,
        IsSecretValue = function() return false end,
        HasSecretValue = function() return false end,
    },
    UIKit = {},
    QUI = {
        Chat = {
            Sounds = { Setup = noop },
            Skinning = { SkinAll = noop, StyleAllTabs = noop },
            Cleanup = {},
            EditBoxBasics = {},
            EditBoxHistory = { InitializeForFrame = noop },
            Copy = { SetupURLClick = noop },
        },
    },
}

assert(loadfile("modules/chat/chat.lua"))("QUI", ns)
assert(eventFrame and eventFrame.OnEvent, "chat module should install an event handler")

eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "QUI")
eventFrame.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")

-- 1. Stored size re-applied at login via plain SetSize.
assert(ChatFrame1:GetWidth() == 500 and ChatFrame1:GetHeight() == 300,
    "login must re-apply stored ChatFrame1 size via SetSize (got "
        .. tostring(ChatFrame1._w) .. "x" .. tostring(ChatFrame1._h) .. ")")

-- 2. Edit Mode enter zeroes the selection + resize-handle overlay alpha.
assert(type(hooks.EnterEditMode) == "function",
    "chat.lua must hook EditModeManagerFrame:EnterEditMode to suppress the chat selection overlay")
ChatFrame1.Selection:SetAlpha(1)
ChatFrame1.EditModeResizeButton:SetAlpha(1)
hooks.EnterEditMode(EditModeManagerFrame)
assert(ChatFrame1.Selection:GetAlpha() == 0,
    "Edit Mode enter must zero ChatFrame1.Selection alpha")
assert(ChatFrame1.EditModeResizeButton:GetAlpha() == 0,
    "Edit Mode enter must zero ChatFrame1.EditModeResizeButton alpha")
assert(ChatFrame1.EditModeResizeButton._mouse == false,
    "Edit Mode enter must disable mouse on the chat resize grip so a stray drag can't resize outside QUI")

print("OK: chat_frame1_login_size_restore_test")
