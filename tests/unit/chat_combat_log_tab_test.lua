-- tests/unit/chat_combat_log_tab_test.lua
-- Run: lua tests/unit/chat_combat_log_tab_test.lua
-- Headless coverage of CombatLogTab's pure state surface. Frame reparenting
-- (real ChatFrame2) is validated in-game, not here; the stubs only verify the
-- activate/deactivate state machine and host-parent resolution.

-- Minimal frame stub.
local function F()
    local f = { _pts = {}, _shown = false, _parent = nil, scripts = {} }
    function f:SetParent(p) self._parent = p end
    function f:GetParent() return self._parent end
    function f:ClearAllPoints() self._pts = {} end
    function f:SetPoint(...) self._pts[#self._pts + 1] = { ... } end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:RegisterEvent() end
    function f:UnregisterAllEvents() end
    function f:GetName() return "ChatFrame2" end
    return f
end

_G.UIParent = F()
_G.CreateFrame = function() return F() end
_G.ChatFrame2 = F()
_G.CombatLogQuickButtonFrame_Custom = F()
_G.ChatFrame2.Background = F()
function _G.ChatFrame2:SetFontObject(fo) self._font = fo end

local container = F()
local smf = F()
local ns
ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return ns._settings end,
    } } },
}
ns._settings = { customDisplay = { combatLogTab = true } }
local fontSentinel = { _id = "QUI_ChatFont" }
ns.QUI.Chat._internals.chatFontObject = fontSentinel
ns.QUI.Chat.DisplayLayer = {
    GetContainer = function() return container end,
    GetMessageFrame = function() return smf end,
}
ns.QUI.Chat.TabManager = { ReapplyAll = function() end }
ns.QUI.Chat.Scrollbar = { SetShown = function() end }

assert(loadfile("QUI_Chat/chat/combat_log_tab.lua"))("QUI", ns)
local CL = ns.QUI.Chat.CombatLogTab

-- IsEnabled reads the setting.
assert(CL.IsEnabled() == true, "default enabled")
ns._settings.customDisplay.combatLogTab = false
assert(CL.IsEnabled() == false, "respects disabled")
ns._settings.customDisplay.combatLogTab = true

-- Inactive: no host.
assert(CL.GetHostParent() == nil, "no host before activate")
assert(CL.IsActiveWindow(1) == false, "window 1 inactive before activate")

-- Activate(1): host resolves, ChatFrame2 parented into the container, SMF hidden.
CL.Activate(1)
assert(CL.IsActiveWindow(1) == true, "window 1 active after activate")
assert(CL.GetHostParent() == container, "host should be the window container")
assert(_G.ChatFrame2:GetParent() == container, "ChatFrame2 reparented into container")
assert(_G.CombatLogQuickButtonFrame_Custom:GetParent() == container, "quick-bar reparented in")
assert(smf._shown == false, "SMF hidden while combat log active")
assert(_G.ChatFrame2._shown == true, "ChatFrame2 shown")
assert(_G.ChatFrame2._font == fontSentinel,
    "ChatFrame2 adopts the QUI chat font object on embed")

-- Live font change while the tab is open: RefreshFont re-applies the
-- (re-published) font object.
local fontSentinel2 = { _id = "QUI_ChatFont2" }
ns.QUI.Chat._internals.chatFontObject = fontSentinel2
CL.RefreshFont()
assert(_G.ChatFrame2._font == fontSentinel2,
    "RefreshFont re-applies the published font object while active")

-- Deactivate(1): host clears, SMF restored, ChatFrame2 parked off the container.
CL.Deactivate(1)
assert(CL.IsActiveWindow(1) == false, "inactive after deactivate")
assert(CL.GetHostParent() == nil, "no host after deactivate")
assert(_G.ChatFrame2:GetParent() ~= container, "ChatFrame2 parked off the container")
assert(smf._shown == true, "SMF restored after deactivate")

print("OK chat_combat_log_tab_test")
