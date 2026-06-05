-- tests/unit/chat_frame1_editmode_detach_test.lua
-- Run: lua tests/unit/chat_frame1_editmode_detach_test.lua
--
-- Regression guard for the recurring chat taint:
--   "attempt to perform string conversion on a secret string value
--    (execution tainted by 'QUI')" at ChatFrameOverrides MessageFormatter,
--   firing when a public channel body (e.g. "4. LookingForGroup") is secret.
--
-- ROOT CAUSE: ChatFrame1 is an EditModeSystem frame. EditModeSystemMixin:
-- OnSystemLoad saves its real setters as *Base and REPLACES SetPoint/
-- ClearAllPoints/SetScale with overrides that re-enter EditModeManagerFrame
-- (SetPointOverride -> OnEditModeSystemAnchorChanged). Calling those from QUI's
-- (tainted) code taints the frame's secure layout chain, which then surfaces on
-- the frame's OWN chat-event dispatch and trips Blizzard's secret-string guard.
-- Reparenting the frame (detach) does NOT remove those per-instance overrides --
-- so FCF_SetWindowSize AND a plain-looking frame:SetPoint/frame:ClearAllPoints
-- are both taint vectors.
--
-- THE FIX (chat_frame1.lua): detach ChatFrame1 from the Edit Mode hierarchy once
-- (reparent to a plain container), and reposition it through the saved *Base
-- setters (Helpers.BaseSetPoint/BaseClearAllPoints) so positioning never
-- re-enters Edit Mode. SetSize is NOT overridden, so the size path stays plain.
-- QUI owns position post-detach. This test asserts:
--   * geometry is NEVER applied before detach,
--   * detach reparents ChatFrame1 + pulls its Edit Mode overlay widgets away,
--   * post-detach sizing uses plain SetSize and NEVER FCF_SetWindowSize,
--   * stored position round-trips through the *Base setters against UIParent and
--     NEVER through the Edit Mode SetPoint/ClearAllPoints overrides,
--   * SyncToStored is inert while chat is disabled.
-- It FAILS on the pre-fix source (FCF_SetWindowSize, or the overridden setters).

local function newWidget(name)
    local w = { _name = name, _children = {} }
    function w:SetParent(p) self._parent = p end
    function w:GetParent() return self._parent end
    function w:SetAllPoints() self._allPoints = true end
    function w:EnableMouse(v) self._mouse = v end
    function w:Hide() self._hidden = true end
    function w:Show() self._hidden = false end
    return w
end

-- Spy: must NEVER be called (post-detach sizing uses plain SetSize).
local fcfSetWindowSizeCalls = 0
FCF_SetWindowSize = function() fcfSetWindowSizeCalls = fcfSetWindowSizeCalls + 1 end

function InCombatLockdown() return false end

UIParent = newWidget("UIParent")

-- Mock ChatFrame1 with the methods the detach/sizing/position paths touch.
local chat = newWidget("ChatFrame1")
chat._width, chat._height = 400, 200
chat._setSizeCalls = 0
chat._baseClearPointsCalls = 0      -- taint-safe path (what QUI must use)
chat._baseSetPointArgs = nil
chat._overrideClearPointsCalls = 0  -- Edit Mode override (QUI must NEVER call it)
chat._overrideSetPointCalls = 0
function chat:SetSize(w, h) self._setSizeCalls = self._setSizeCalls + 1; self._width, self._height = w, h end
function chat:GetWidth() return self._width end
function chat:GetHeight() return self._height end
function chat:SetClampedToScreen(v) self._clamped = v end
-- Model the EditModeSystemMixin method swap: the real setters are saved as *Base;
-- SetPoint/ClearAllPoints are overrides that re-enter EditModeManagerFrame (the
-- taint vector). QUI must drive the *Base setters and never the overrides.
function chat:ClearAllPointsBase() self._baseClearPointsCalls = self._baseClearPointsCalls + 1 end
function chat:SetPointBase(point, rel, relPoint, x, y)
    self._baseSetPointArgs = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end
function chat:ClearAllPoints() self._overrideClearPointsCalls = self._overrideClearPointsCalls + 1 end
function chat:SetPoint() self._overrideSetPointCalls = self._overrideSetPointCalls + 1 end
-- Seed anchor read by PersistCurrentPosition on first detach.
function chat:GetPoint() return "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 12.6, 7.2 end
chat.Selection = newWidget("Selection")
chat.EditModeResizeButton = newWidget("EditModeResizeButton")

ChatFrame1 = chat

function CreateFrame(_type, name)
    return newWidget(name)
end

-- Profile DB the module reads/writes through Helpers.GetCore().
local chatDB = { enabled = true, frameSize = { w = 640, h = 320 } }
local core = { db = { profile = { chat = chatDB } } }

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        GetCore = function() return core end,
        -- Mirror the real core/utils.lua override-bypass helpers.
        BaseClearAllPoints = function(frame)
            if not frame then return end
            local fn = frame.ClearAllPointsBase or frame.ClearAllPoints
            if fn then fn(frame) end
        end,
        BaseSetPoint = function(frame, ...)
            if not frame then return end
            local fn = frame.SetPointBase or frame.SetPoint
            if fn then fn(frame, ...) end
        end,
    },
    QUI = {},
    -- No ns.Settings: the file's ProviderFeatures registration early-returns,
    -- but every detach/sizing/position function is defined before that guard.
}

assert(loadfile("modules/chat/settings/chat_frame1.lua"))("QUI", ns)

local Sizing = ns.QUI.ChatFrame1Sizing
assert(Sizing, "ChatFrame1Sizing namespace must be exported")

local function check(cond, msg)
    if not cond then
        print("FAIL: " .. msg)
        os.exit(1)
    end
end

-- Phase A: disabled -> SyncToStored is fully inert (no detach, no reparent).
chatDB.enabled = false
check(Sizing.SyncToStored() == false, "SyncToStored must return false while chat disabled")
check(Sizing.IsDetached() == false, "must NOT detach while chat disabled")
check(chat:GetParent() == nil, "ChatFrame1 must not be reparented while chat disabled")
chatDB.enabled = true

-- Phase B: before detach, geometry must NEVER be applied (the taint invariant).
check(Sizing.ApplyStoredSize() == false, "ApplyStoredSize must refuse before detach")
check(chat._setSizeCalls == 0, "no SetSize may happen before detach")
check(Sizing.ApplyStoredPosition() == false, "ApplyStoredPosition must refuse before detach")

-- Phase C: detach reparents ChatFrame1 + relocates its Edit Mode overlay widgets.
check(Sizing.DetachFromEditMode() == true, "DetachFromEditMode must succeed out of combat")
check(Sizing.IsDetached() == true, "IsDetached must be true after detach")
check(chat:GetParent() ~= nil and chat:GetParent()._name == "QUIChatFrame1Container",
    "ChatFrame1 must be reparented to the plain QUI container")
check(chat.Selection:GetParent() ~= nil and chat.Selection:GetParent() ~= UIParent,
    "Edit Mode Selection widget must be reparented off-screen")
check(chat.EditModeResizeButton:GetParent() ~= nil,
    "Edit Mode resize button must be reparented off-screen")
-- First detach seeds position from the live anchor (rounded).
check(chatDB.framePosition and chatDB.framePosition.point == "BOTTOMLEFT"
    and chatDB.framePosition.x == 13 and chatDB.framePosition.y == 7,
    "detach must seed rounded framePosition from the live anchor")

-- Phase D: post-detach sizing uses plain SetSize; FCF_SetWindowSize never runs.
check(Sizing.ApplyStoredSize() == true, "ApplyStoredSize must apply once detached")
check(chat._setSizeCalls == 1 and chat._width == 640 and chat._height == 320,
    "ApplyStoredSize must plain-SetSize to the stored dimensions")
check(fcfSetWindowSizeCalls == 0, "FCF_SetWindowSize must NEVER be called (it re-enters Edit Mode)")

-- Phase E: stored position re-applies via the *Base setters against UIParent --
-- NEVER the Edit Mode overrides (which would re-enter EditModeManagerFrame and
-- taint ChatFrame1's chat-event dispatch -> the secret-string crash).
chatDB.framePosition = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -5, y = -5 }
check(Sizing.ApplyStoredPosition() == true, "ApplyStoredPosition must apply once detached")
check(chat._baseClearPointsCalls >= 1, "ApplyStoredPosition must ClearAllPointsBase first (override-bypass)")
check(chat._baseSetPointArgs and chat._baseSetPointArgs.point == "TOPRIGHT"
    and chat._baseSetPointArgs.rel == UIParent and chat._baseSetPointArgs.x == -5,
    "ApplyStoredPosition must SetPointBase against UIParent with stored offsets")
check(chat._overrideClearPointsCalls == 0 and chat._overrideSetPointCalls == 0,
    "ApplyStoredPosition must NEVER call the Edit Mode SetPoint/ClearAllPoints overrides")

-- Phase F: StorePosition rounds offsets to integers.
Sizing.StorePosition("CENTER", "CENTER", 10.4, -20.6)
check(chatDB.framePosition.x == 10 and chatDB.framePosition.y == -21,
    "StorePosition must round offsets to integers")

-- Phase G: when the user anchors chat via the Frame Positioning panel, the
-- anchoring system owns position -> ApplyStoredPosition must stand down so the
-- two systems don't fight. (Size stays QUI-owned regardless.)
core.db.profile.frameAnchoring = { chatFrame1 = { point = "TOPLEFT", offsetX = 0, offsetY = 0 } }
check(Sizing.ApplyStoredPosition() == false, "ApplyStoredPosition must defer when chat is anchored via the panel")
core.db.profile.frameAnchoring = nil
check(Sizing.ApplyStoredPosition() == true, "ApplyStoredPosition resumes ownership once the anchor is cleared")

print("OK: chat_frame1_editmode_detach_test")
