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
-- SetFont models Blizzard's direct-font path: it records the raw triple and
-- drops any font object (the in-game collapse the durability hook fights).
function _G.ChatFrame2:SetFont(file, size, flags)
    self._rawFont = { file, size, flags }
    self._font = nil
end
function _G.ChatFrame2:GetFont()
    local rf = self._rawFont
    if rf then return rf[1], rf[2], rf[3] end
end
-- hooksecurefunc stub: post-hook on a table member.
function _G.hooksecurefunc(tbl, name, fn)
    local orig = tbl[name]
    tbl[name] = function(...)
        orig(...)
        fn(...)
    end
end

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

-- Stock font present before the first embed (Blizzard sets it at OnLoad);
-- RefreshFont snapshots it for the Deactivate hand-back.
_G.ChatFrame2:SetFont("Fonts\\STOCK.TTF", 12, "")

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

-- Blizzard clobber while the tab is open: ChatFrame2 keeps UPDATE_CHAT_WINDOWS
-- (neuter-exempt), and its handler re-asserts the saved per-window font via
-- SetFont (ChatFrameOverrides.lua:114-119). The durability hook must re-apply
-- the QUI font object immediately.
_G.ChatFrame2:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
assert(_G.ChatFrame2._font == fontSentinel2,
    "QUI font object re-applied after an outside SetFont while active")

-- Deactivate(1): host clears, SMF restored, ChatFrame2 parked off the container.
CL.Deactivate(1)
assert(CL.IsActiveWindow(1) == false, "inactive after deactivate")
assert(CL.GetHostParent() == nil, "no host after deactivate")
assert(_G.ChatFrame2:GetParent() ~= container, "ChatFrame2 parked off the container")
assert(smf._shown == true, "SMF restored after deactivate")
assert(_G.ChatFrame2._rawFont[1] == "Fonts\\STOCK.TTF" and _G.ChatFrame2._rawFont[2] == 12,
    "snapshotted stock font handed back on deactivate")
assert(_G.ChatFrame2._font == nil,
    "durability hook stays inert while the tab is inactive")

print("OK chat_combat_log_tab_test")
