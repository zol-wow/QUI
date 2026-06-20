-- tests/unit/aura_events_nonroster_tooltip_scope_test.lua
-- Run: lua tests/unit/aura_events_nonroster_tooltip_scope_test.lua
--
-- Regression: mousing over a unit frame in a raid caused a significant FPS drop.
-- Root cause: core/aura_events.lua IsNonRosterEventInteresting let EVERY
-- non-roster UNIT_AURA token (nameplate1..40, mouseover, focus, boss, arena)
-- through whenever ANY GameTooltip was shown. In a raid/M+ the 40 enemy
-- nameplates ticking DoTs flood the dispatcher's queue/merge/fan-out the instant
-- a tooltip appears. The sole "all" subscriber (QoL tooltip mount line) only acts
-- on the unit the tooltip is showing and bails in combat, so all that work is
-- discarded. The predicate must scope the tooltip pass to the tooltip's own unit
-- (and drop everything but `target` in combat, where the subscriber bails).

local function noop() end

-- Controllable WoW environment ------------------------------------------------
local env = { inCombat = false, tooltipShown = false, tooltipUnit = nil }

function InCombatLockdown() return env.inCombat end
function wipe(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

GameTooltip = {
    IsShown = function() return env.tooltipShown end,
    GetUnit = function() return env.tooltipUnit and "SomeName" or nil, env.tooltipUnit end,
}

local createdFrames = {}
function CreateFrame()
    local f = {
        _onEvent = nil,
        _onUpdate = nil,
        _registeredGlobal = false,
        RegisterEvent = function(self, event)
            if event == "UNIT_AURA" then self._registeredGlobal = true end
        end,
        RegisterUnitEvent = noop,
        Show = noop,
        Hide = noop,
        SetScript = function(self, script, handler)
            if script == "OnEvent" then self._onEvent = handler
            elseif script == "OnUpdate" then self._onUpdate = handler end
        end,
    }
    createdFrames[#createdFrames + 1] = f
    return f
end

-- Load the live dispatcher with a fresh namespace --------------------------------
local ns = {}
assert(loadfile("core/aura_events.lua"))("QUI", ns)
local AuraEvents = ns.AuraEvents
assert(AuraEvents, "core/aura_events.lua must publish ns.AuraEvents")

-- Locate the global UNIT_AURA router frame and the coalescing frame.
local eventFrame, coalesceFrame
for _, f in ipairs(createdFrames) do
    if f._registeredGlobal and f._onEvent then eventFrame = f end
    if f._onUpdate then coalesceFrame = f end
end
assert(eventFrame, "could not find the global UNIT_AURA router frame")
assert(coalesceFrame, "could not find the coalescing frame")

-- Record every unit dispatched to "all" subscribers.
local seen = {}
AuraEvents:Subscribe("all", function(unit) seen[unit] = (seen[unit] or 0) + 1 end)

local function fire(unit) eventFrame._onEvent(eventFrame, "UNIT_AURA", unit, nil) end
local function drain()
    seen = {}
    coalesceFrame._onUpdate(coalesceFrame)
end

local function test(n, f) print(n); f(); print("  ok") end

test("OOC tooltip on a nameplate: only that unit reaches 'all', not the storm", function()
    env.inCombat, env.tooltipShown, env.tooltipUnit = false, true, "nameplate7"
    fire("nameplate7")   -- the tooltip's own unit — must pass
    fire("nameplate3")   -- a different enemy nameplate ticking DoTs — must drop
    fire("nameplate12")  -- ditto
    fire("mouseover")    -- alias for a different frame — must drop
    drain()
    assert(seen["nameplate7"], "tooltip's own unit must reach 'all' subscribers")
    assert(not seen["nameplate3"], "non-tooltip nameplate must be dropped (FPS firehose)")
    assert(not seen["nameplate12"], "non-tooltip nameplate must be dropped (FPS firehose)")
    assert(not seen["mouseover"], "non-tooltip token must be dropped (FPS firehose)")
end)

test("In combat: the subscriber bails, so only 'target' is allowed through", function()
    env.inCombat, env.tooltipShown, env.tooltipUnit = true, true, "nameplate7"
    fire("nameplate7")   -- even the tooltip's unit is pointless in combat — drop
    fire("nameplate3")
    fire("target")       -- target consumer path stays alive
    drain()
    assert(not seen["nameplate7"], "in combat the storm must not flood the dispatcher")
    assert(not seen["nameplate3"], "in combat the storm must not flood the dispatcher")
    assert(seen["target"], "target must always reach 'all' (cdm target-debuff path)")
end)

test("No tooltip shown: every non-roster token is dropped", function()
    env.inCombat, env.tooltipShown, env.tooltipUnit = false, false, nil
    fire("nameplate7")
    fire("mouseover")
    drain()
    assert(not seen["nameplate7"], "no tooltip → nothing interesting")
    assert(not seen["mouseover"], "no tooltip → nothing interesting")
end)

print("ALL PASS")
