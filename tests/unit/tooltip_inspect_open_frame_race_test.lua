-- tests/unit/tooltip_inspect_open_frame_race_test.lua
-- Run: lua tests/unit/tooltip_inspect_open_frame_race_test.lua
--
-- Regression: hovering an inspectable player queues a tooltip NotifyInspect on
-- a C_Timer.After(0.05) delay. If the user opens InspectFrame inside that
-- window, AbandonForUserInspect (InspectFrame OnShow) clears queuedRequest and
-- cancels the timeout -- but a C_Timer.After closure cannot be cancelled, so
-- the queued callback still ran and fired NotifyInspect. That second inspect
-- request redirected the server off the inspected unit / flooded a duplicate
-- (Blizzard_InspectUI.lua:54: "the server drops the inspect data when flooded
-- with inspect requests"), blanking the open inspect pane's item levels and
-- gear tooltips a few seconds after it opened -- reported in instances, where
-- players hover a teammate then inspect them constantly.
--
-- Fix: the queued callback re-checks InspectFrame:IsShown() before NotifyInspect,
-- matching the guard QueueInspect already makes at queue time.

local function assertEq(a, b, msg)
    if a ~= b then
        error((msg or "assertion failed") .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")", 2)
    end
end

------------------------------------------------------------------------------
-- Minimal WoW environment
------------------------------------------------------------------------------
local timerQueue = {}
C_Timer = {
    After = function(_, callback) timerQueue[#timerQueue + 1] = callback end,
    NewTimer = function() return { Cancel = function() end } end,
}
local function flushTimers()
    local pending = timerQueue
    timerQueue = {}
    for _, cb in ipairs(pending) do cb() end
end

local _time = 1000
function GetTime() return _time end
function InCombatLockdown() return false end

-- Equipment slot id constants referenced at module load (COUNTED_SLOTS).
local _slotId = 0
for _, name in ipairs({
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WAIST", "LEGS", "FEET",
    "WRIST", "HAND", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2",
    "MAINHAND", "OFFHAND",
}) do
    _slotId = _slotId + 1
    _G["INVSLOT_" .. name] = _slotId
end

GameTooltip = { IsForbidden = function() return false end, GetUnit = function() return nil, nil end }

-- InspectFrame stub with controllable IsShown + OnShow hook wiring.
local inspectOnShow = {}
InspectFrame = {
    shown = false,
    unit = nil,
    IsShown = function(self) return self.shown end,
    HookScript = function(_, script, handler)
        if script == "OnShow" then inspectOnShow[#inspectOnShow + 1] = handler end
    end,
}
_G.InspectFrame = InspectFrame
local function fireInspectOnShow()
    for _, h in ipairs(inspectOnShow) do h() end
end

local eventFrames = {}
function CreateFrame()
    local f = { _events = {} }
    function f:RegisterEvent(e) self._events[e] = true end
    function f:SetScript(script, handler)
        if script == "OnEvent" then
            self.OnEvent = handler
            eventFrames[#eventFrames + 1] = self
        end
    end
    return f
end
-- Fire INSPECT_READY with an unsafe guid so the module's handler just finalizes
-- the active request (clears activeRequest) without caching -- lets the next
-- scenario re-queue the same unit from a clean slate.
local function clearActiveRequest()
    for _, f in ipairs(eventFrames) do
        if f._events["INSPECT_READY"] and f.OnEvent then f:OnEvent("INSPECT_READY", nil) end
    end
end

-- Unit world: "party1" is an inspectable player distinct from the player.
local UNIT_GUID = "Player-1-DEADBEEF"
function UnitExists(unit) return unit == "party1" end
function UnitGUID(unit) if unit == "party1" then return UNIT_GUID end return nil end
function UnitIsPlayer(unit) return unit == "party1" end
function UnitIsUnit(a, b) return a == b end

local canInspect = true
function CanInspect() return canInspect end

local notifyCalls = {}
function NotifyInspect(unit) notifyCalls[#notifyCalls + 1] = unit end
function ClearInspectPlayer() end

------------------------------------------------------------------------------
-- Load module under test
------------------------------------------------------------------------------
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        -- Real core/utils.lua helpers used by the module (secret-fold to
        -- nil / nil-compare); the harness never feeds a secret, so these
        -- behave as identity / plain == exactly like the shipped Helpers.
        SafeValue = function(value, fallback)
            if issecretvalue and issecretvalue(value) then return fallback end
            return value
        end,
        SafeCompare = function(a, b)
            if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then return nil end
            return a == b
        end,
        GetModuleDB = function(name)
            if name == "tooltip" then
                return { enabled = true, showPlayerItemLevel = true }
            end
            return nil
        end,
    },
    SafeCall = function(_policy, fn, ...)
        return pcall(fn, ...)
    end,
    SafeCallMethod = function(_policy, obj, name, ...)
        return pcall(function(...) return obj[name](obj, ...) end, ...)
    end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
}
assert(loadfile("modules/qol/tooltip_inspect.lua"))("QUI_QoL", ns)
local TooltipInspect = assert(ns.TooltipInspect, "module must export ns.TooltipInspect")

------------------------------------------------------------------------------
-- Negative control: no InspectFrame open -> queued timer DOES NotifyInspect.
-- Proves the queue path reaches NotifyInspect, so the guard is what stops it.
------------------------------------------------------------------------------
InspectFrame.shown = false
notifyCalls = {}
assertEq(TooltipInspect:QueueInspect("party1"), true, "QueueInspect should accept an inspectable unit")
flushTimers()
assertEq(#notifyCalls, 1, "control: queued tooltip request must NotifyInspect when no InspectFrame is open")
assertEq(notifyCalls[1], "party1", "control: NotifyInspect targets the hovered unit")
clearActiveRequest()  -- release module state so the next scenario can re-queue

------------------------------------------------------------------------------
-- Regression: user opens InspectFrame during the REQUEST_DELAY window.
-- The stale queued timer must NOT fire NotifyInspect.
------------------------------------------------------------------------------
InspectFrame.shown = false           -- not open when hovering
notifyCalls = {}
assertEq(TooltipInspect:QueueInspect("party1"), true, "QueueInspect should queue again after control finalized")

-- User opens InspectFrame before the 0.05s timer fires.
InspectFrame.shown = true
InspectFrame.unit = "party1"
fireInspectOnShow()                  -- AbandonForUserInspect: clears queue state

flushTimers()                        -- stale C_Timer.After closure runs now
assertEq(#notifyCalls, 0,
    "regression: queued tooltip NotifyInspect must be suppressed once InspectFrame is open " ..
    "(else it floods/redirects the server and blanks the inspect pane)")

print("PASS tooltip_inspect_open_frame_race_test")
