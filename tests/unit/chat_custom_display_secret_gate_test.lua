-- tests/unit/chat_custom_display_secret_gate_test.lua
-- PHASE 1 SHIP GATE (design §6): a secret payload fired at the capture frame
-- must reach ScrollingMessageFrame:AddMessage BY IDENTITY with zero Lua
-- operators applied, through the real capture -> store -> display chain.
-- The sentinel explodes on ANY metamethod; reaching print("OK") proves
-- opacity end-to-end. Also proves: interleaved normal messages still render,
-- a rebuild (tab switch) re-passes matching secrets untouched, and the
-- enable/disable toggle round-trip replays the retained store.

local function explode() error("OPERATOR APPLIED TO SECRET", 2) end
local secret = setmetatable({}, {
    __tostring = explode, __concat = explode, __len = explode,
    __eq = explode, __lt = explode, __le = explode,
    __add = explode, __sub = explode, __mul = explode, __div = explode,
    __index = explode, __newindex = explode,
})

-- WoW mocks ------------------------------------------------------------------
local smfAdded = {}
local function makeFrame(ftype)
    local f = { ftype = ftype, shown = true }
    local function noop() end
    f.GetName = function(self) return self.name end
    f.SetSize = noop; f.SetHeight = noop; f.SetPoint = noop; f.ClearAllPoints = noop
    f.GetPoint = function() return "BOTTOMLEFT", nil, "BOTTOMLEFT", 35, 40 end
    f.GetWidth = function() return 430 end; f.GetHeight = function() return 190 end
    f.Show = function(s) s.shown = true end; f.Hide = function(s) s.shown = false end
    f.IsShown = function(s) return s.shown end
    f.SetMovable = noop; f.SetResizable = noop; f.SetResizeBounds = noop
    f.SetClampedToScreen = noop; f.EnableMouse = noop; f.RegisterForDrag = noop
    f.StartMoving = noop; f.StartSizing = noop; f.StopMovingOrSizing = noop
    f.SetFrameStrata = noop; f.SetFontObject = noop; f.SetJustifyH = noop
    f.SetFading = noop; f.SetMaxLines = noop; f.SetHyperlinksEnabled = noop
    f.ScrollUp = noop; f.ScrollDown = noop; f.ScrollToBottom = noop
    f.HookScript = function(s, k, v) s["_hook_" .. k] = v end
    f.EnableMouseWheel = noop
    f.Clear = function() smfAdded = {} end
    f.AddMessage = function(_, m, r, g, b) smfAdded[#smfAdded + 1] = { m = m, r = r, g = g, b = b } end
    f.RegisterEvent = noop; f.UnregisterAllEvents = noop
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    return f
end
local captureFrame
function _G.CreateFrame(ftype, name)
    local f = makeFrame(ftype)
    f.name = name
    if name then _G[name] = f end
    -- The capture frame is the first unnamed Frame; drag handles and resize
    -- grips also have name == nil but come later (display_layer loads after
    -- message_capture in chat.xml order).
    if not captureFrame and ftype == "Frame" and name == nil then captureFrame = f end
    return f
end
_G.UIParent = makeFrame("Frame")
_G.ChatFontNormal = {}
_G.ChatTypeGroupInverted = { CHAT_MSG_SAY = "SAY", CHAT_MSG_RAID_WARNING = "RAID_WARNING" }
_G.C_EventUtils = { IsEventValid = function() return true end }
-- ChatTypeInfo trapped against writes (render-time-color constraint enforcement)
_G.ChatTypeInfo = setmetatable({}, {
    __index = function(_, k)
        if k == "RAID_WARNING" then return { r = 1, g = 0.28, b = 0 } end
        return { r = 1, g = 1, b = 1 }
    end,
    __newindex = function() error("WRITE to ChatTypeInfo is forbidden") end,
})
function _G.Ambiguate(n) return n end
function _G.GetServerTime() return 99 end
_G.ChatFrame1 = { name = "ChatFrame1" }
_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1
_G.ChatFrameUtil = { ProcessMessageEventFilters = function(_, _, ...) return false, ... end }
function _G.hooksecurefunc() end
function _G.debugstack() return "" end

-- One window: secret-gate is a single-window discipline test.
-- windows[1] carries the legacy geometry fields display_layer reads from
-- the config entry; maxLines lives at customDisplay.maxLines.
local settings = { enabled = true,
    customDisplay = {
        maxLines = 500,
        windows = {
            { width = 430, height = 190,
              position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 35, y = 40 },
              tabs = {} },
        },
    } }
local ns = {
    Helpers = {
        IsSecretValue = function(v) return v == secret end,
        SetFrameBackdropColor = function() end,
        SetFrameBackdropBorderColor = function() end,
    },
    UIKit = { ApplyPixelBackdrop = function() end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

-- Load the REAL chain in chat.xml order.
-- TabManager must exist before display_layer so GetWindowsConfig resolves.
assert(loadfile("modules/chat/message_store.lua"))("QUI", ns)
assert(loadfile("modules/chat/message_format.lua"))("QUI", ns)
assert(loadfile("modules/chat/message_capture.lua"))("QUI", ns)
-- Stub TabManager so display_layer.EnsureCreated can read the window config.
-- The real tab_manager is loaded afterward and replaces this stub.
ns.QUI.Chat.TabManager = {
    GetWindowsConfig = function() return settings.customDisplay.windows end,
}
assert(loadfile("modules/chat/display_layer.lua"))("QUI", ns)
assert(loadfile("modules/chat/tab_manager.lua"))("QUI", ns)
assert(loadfile("modules/chat/display_fallback.lua"))("QUI", ns)

-- Real two-arg Rebuild is now in place; no shim needed (Task 3).

ns.QUI.Chat.DisplayFallback.Apply()
assert(captureFrame and captureFrame._OnEvent, "capture frame wired")

-- 1. Normal message renders
captureFrame._OnEvent(captureFrame, "CHAT_MSG_SAY", "before", "Ann")
assert(#smfAdded == 1, "normal message rendered")

-- 2. SECRET RAID_WARNING: identity pass-through, event-derived color
captureFrame._OnEvent(captureFrame, "CHAT_MSG_RAID_WARNING", secret, "Boss")
assert(#smfAdded == 2, "secret rendered")
assert(rawequal(smfAdded[2].m, secret), "SECRET reached AddMessage BY IDENTITY")
assert(smfAdded[2].r == 1 and smfAdded[2].g == 0.28 and smfAdded[2].b == 0,
    "secret line colored from EVENT, payload untouched")

-- 3. Next normal message still flows (no taint wedge)
captureFrame._OnEvent(captureFrame, "CHAT_MSG_SAY", "after", "Ann")
assert(#smfAdded == 3, "dispatch alive after secret")

-- 4. Tab-switch rebuild filters by event metadata and re-passes matching
-- secrets untouched.
ns.QUI.Chat.TabManager.SetActiveTab(1, { groups = { RAID_WARNING = true }, invert = false })
local secretSeen = false
for _, line in ipairs(smfAdded) do
    if rawequal(line.m, secret) then secretSeen = true end
end
assert(secretSeen, "secret survives matching filtered rebuild")
ns.QUI.Chat.TabManager.SetActiveTab(1, { groups = { SAY = true }, invert = false })
secretSeen = false
for _, line in ipairs(smfAdded) do
    if rawequal(line.m, secret) then secretSeen = true end
end
assert(not secretSeen, "secret blocked when its metadata does not match the active tab")

-- 5. Lossless toggle: disabling hides, store intact; re-enabling replays all
settings.enabled = false
ns.QUI.Chat.DisplayFallback.Apply()
assert(ns.QUI.Chat.MessageStore.Size() == 3, "store retained on toggle-off")
settings.enabled = true
ns.QUI.Chat.TabManager.SetActiveTab(1, nil)
ns.QUI.Chat.DisplayFallback.Apply()
assert(#smfAdded == 3, "full replay after toggle round-trip, got " .. #smfAdded)
local replaySecret = false
for _, line in ipairs(smfAdded) do
    if rawequal(line.m, secret) then replaySecret = true end
end
assert(replaySecret, "secret survives toggle-round-trip replay")

print("OK: chat_custom_display_secret_gate_test")
