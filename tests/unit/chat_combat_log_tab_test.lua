-- tests/unit/chat_combat_log_tab_test.lua
-- Run: lua tests/unit/chat_combat_log_tab_test.lua
-- Headless coverage of CombatLogTab's pure state surface. Frame reparenting
-- (real ChatFrame2) is validated in-game, not here; the stubs only verify the
-- activate/deactivate state machine and host-parent resolution.

-- Minimal frame stub.
local function F()
    local f = { _pts = {}, _shown = false, _parent = nil, scripts = {}, _events = {} }
    function f:SetParent(p) self._parent = p end
    function f:GetParent() return self._parent end
    function f:ClearAllPoints() self._pts = {} end
    function f:SetPoint(...) self._pts[#self._pts + 1] = { ... } end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    function f:SetSize(w, h) self._size = { w, h } end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterAllEvents() self._events = {} end
    function f:GetName() return "ChatFrame2" end
    return f
end

_G.UIParent = F()
-- CreateFrame records every frame (the module's waiters/driver are internal,
-- tests locate them by shape) and emulates SecureHandlerBaseTemplate: Execute
-- models the module's snippet — Hide+Show cycle the referenced combat log.
local createdFrames = {}
_G.CreateFrame = function(_, _, _, template)
    local f = F()
    if template == "SecureHandlerBaseTemplate" then
        f._refs = {}
        function f:SetFrameRef(label, frame) self._refs[label] = frame end
        function f:Execute()
            self._executed = (self._executed or 0) + 1
            local cf = self._refs.quiCombatLog
            if cf then
                if cf:IsShown() then cf:Hide() end
                cf:Show()
            end
        end
    end
    createdFrames[#createdFrames + 1] = f
    return f
end
local function FindFrame(pred)
    for _, f in ipairs(createdFrames) do
        if pred(f) then return f end
    end
end
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
-- Justification models the in-game SetFontObject behavior: adopting a font
-- object pulls the SMF to the OBJECT's justification (the QUI font family
-- carries none -> CENTER), which is the centered-combat-log bug.
_G.ChatFrame2._justifyH = "LEFT"
function _G.ChatFrame2:GetJustifyH() return self._justifyH end
function _G.ChatFrame2:SetJustifyH(j) self._justifyH = j end
local realSetFontObject = _G.ChatFrame2.SetFontObject
function _G.ChatFrame2:SetFontObject(fo)
    realSetFontObject(self, fo)
    self._justifyH = "CENTER"
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
-- Regen-cycle/Prime guard: the module skips secure cycles when the Blizzard
-- takeover is no longer active (e.g. torn down mid-combat).
local suppressActive = true
ns.QUI.Chat.BlizzardSuppress = { IsActive = function() return suppressActive end }

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
assert(_G.ChatFrame2._justifyH == "LEFT",
    "justification re-asserted after SetFontObject (font family centers the SMF)")

-- Live font change while the tab is open: RefreshFont re-applies the
-- (re-published) font object.
local fontSentinel2 = { _id = "QUI_ChatFont2" }
ns.QUI.Chat._internals.chatFontObject = fontSentinel2
CL.RefreshFont()
assert(_G.ChatFrame2._font == fontSentinel2,
    "RefreshFont re-applies the published font object while active")
assert(_G.ChatFrame2._justifyH == "LEFT",
    "justification survives a live font refresh")

-- Blizzard clobber while the tab is open: ChatFrame2 keeps UPDATE_CHAT_WINDOWS
-- (neuter-exempt), and its handler re-asserts the saved per-window font via
-- SetFont (ChatFrameOverrides.lua:114-119). The durability hook must re-apply
-- the QUI font object immediately.
_G.ChatFrame2:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
assert(_G.ChatFrame2._font == fontSentinel2,
    "QUI font object re-applied after an outside SetFont while active")
assert(_G.ChatFrame2._justifyH == "LEFT",
    "justification re-asserted by the durability hook too")

-- Deactivate(1): host clears, SMF restored, ChatFrame2 parked off the container.
CL.Deactivate(1)
assert(CL.IsActiveWindow(1) == false, "inactive after deactivate")
assert(CL.GetHostParent() == nil, "no host after deactivate")
assert(_G.ChatFrame2:GetParent() ~= container, "ChatFrame2 parked off the container")
-- The park must be the SHOWN clipped anchor: parking on a hidden parent would
-- fire Blizzard_CombatLog's OnHide wrapper on QUI's tainted path and break the
-- combat-log filter pipeline (ClearEventFilters runs, AddEventFilter blocked).
assert(_G.ChatFrame2:GetParent() == CL.GetParkParent(),
    "ChatFrame2 parks on the module's park parent")
assert(CL.GetParkParent()._shown == true, "park parent is a SHOWN frame")
assert(smf._shown == true, "SMF restored after deactivate")
assert(_G.ChatFrame2._rawFont[1] == "Fonts\\STOCK.TTF" and _G.ChatFrame2._rawFont[2] == 12,
    "snapshotted stock font handed back on deactivate")
assert(_G.ChatFrame2._font == nil,
    "durability hook stays inert while the tab is inactive")

-- ===== In-combat activation =====
-- ChatFrame2 is unprotected (FloatingChatFrame.xml:676), so the embed must run
-- IMMEDIATELY during lockdown — the old defer-to-regen left the Combat tab
-- dead until the fight ended. Only the secure filter cycle (restricted frame
-- handles refuse unprotected frames in combat) waits for PLAYER_REGEN_ENABLED.
local driver = FindFrame(function(f) return f._refs ~= nil end)
assert(driver and driver._executed == 1,
    "secure driver cycled exactly once during the out-of-combat activation")

local inCombat = true
_G.InCombatLockdown = function() return inCombat end

CL.Activate(1)
assert(CL.IsActiveWindow(1) == true, "window 1 active from an in-combat activate")
assert(CL.GetHostParent() == container, "host resolves during lockdown")
assert(_G.ChatFrame2:GetParent() == container,
    "ChatFrame2 embedded immediately during lockdown (no regen wait)")
assert(_G.CombatLogQuickButtonFrame_Custom:GetParent() == container,
    "quick-bar embedded immediately during lockdown")
assert(smf._shown == false, "SMF hidden by the in-combat embed")
assert(_G.ChatFrame2._font == fontSentinel2, "font applied by the in-combat embed")
assert(driver._executed == 1,
    "secure cycle must NOT run in combat (restricted handles reject unprotected frames)")

-- The deferred cycle is armed for regen...
local waiter = FindFrame(function(f) return f._events.PLAYER_REGEN_ENABLED end)
assert(waiter, "a regen waiter is registered for the deferred filter cycle")
-- ...and fires it once combat drops.
inCombat = false
waiter.scripts.OnEvent(waiter)
assert(driver._executed == 2, "filter cycle re-fired at PLAYER_REGEN_ENABLED")
assert(_G.ChatFrame2._shown == true, "ChatFrame2 shown after the regen cycle")

-- Deactivated before combat drops: the regen waiter still cycles — a parked
-- cycle is harmless and doubles as the session's priming apply.
inCombat = true
CL.Activate(1)
CL.Deactivate(1)
assert(_G.ChatFrame2:GetParent() == CL.GetParkParent(),
    "in-combat deactivate parks ChatFrame2 (unprotected reparent is lockdown-legal)")
assert(smf._shown == true, "SMF restored by the in-combat deactivate")
inCombat = false
waiter = FindFrame(function(f) return f._events.PLAYER_REGEN_ENABLED end)
assert(waiter, "regen waiter re-armed by the second in-combat activate")
waiter.scripts.OnEvent(waiter)
assert(driver._executed == 3, "regen cycle runs even while the tab is parked")

-- Takeover torn down before combat drops: the regen waiter must SKIP (cycling
-- a re-docked stock ChatFrame2 would pop it visible over stock chat).
inCombat = true
CL.Activate(1)
suppressActive = false
inCombat = false
waiter = FindFrame(function(f) return f._events.PLAYER_REGEN_ENABLED end)
assert(waiter, "regen waiter armed by the third in-combat activate")
waiter.scripts.OnEvent(waiter)
assert(driver._executed == 3, "regen cycle skipped after takeover teardown")
suppressActive = true
CL.Deactivate(1)

-- ===== Priming =====
-- Prime drives the session's first filter apply at takeover time so a
-- mid-combat FIRST tab click finds filters applied and the frame shown.
ns._settings.customDisplay.combatLogTab = false
CL.Prime()
assert(driver._executed == 3, "Prime no-ops while the tab feature is off (and must not latch)")
ns._settings.customDisplay.combatLogTab = true
CL.Prime()
assert(driver._executed == 4, "Prime drives the first apply on the PARKED frame")
assert(_G.ChatFrame2._shown == true, "primed ChatFrame2 ends shown (the park's design state)")
CL.Prime()
assert(driver._executed == 4, "Prime latches: once per session")

-- ===== Mid-combat hidden fallback =====
-- A still-hidden ChatFrame2 mid-combat (combat-/reload session) is shown
-- INSECURELY rather than left blank; the queued regen cycle then re-fires
-- the wrapper securely to restore exact filtering.
inCombat = true
_G.ChatFrame2:Hide()
CL.Activate(1)
assert(_G.ChatFrame2._shown == true,
    "hidden ChatFrame2 shown insecurely mid-combat (never blank)")
assert(driver._executed == 4, "secure cycle still deferred while locked")
inCombat = false
waiter = FindFrame(function(f) return f._events.PLAYER_REGEN_ENABLED end)
assert(waiter, "regen waiter armed by the hidden-fallback activate")
waiter.scripts.OnEvent(waiter)
assert(driver._executed == 5, "secure re-apply heals the insecure show at regen")
CL.Deactivate(1)

print("OK chat_combat_log_tab_test")
