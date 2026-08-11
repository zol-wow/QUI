-- tests/unit/resourcebars_event_orchestrator_test.lua
-- Run: lua tests/unit/resourcebars_event_orchestrator_test.lua
--
-- OnUnitPower hand-rolled the 16ms throttle twice (primary + secondary)
-- and OnRunePowerUpdate a third time, and every event rendered BOTH full
-- renderers (layout included). The orchestrator (RequestBarUpdates) is now
-- the single owner of leading-edge throttle + one-trailing-drain-per-burst;
-- event handlers only route. Trailing drains must escalate to the full
-- config path when a throttled request required it (UNIT_MAXPOWER,
-- token-less callers).

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local function extract(startMarker, endMarker)
    local s = src:find(startMarker, 1, true)
    assert(s, "missing marker: " .. startMarker)
    local e = src:find(endMarker, s + 1, true)
    assert(e, "missing marker: " .. endMarker)
    return src:sub(s, e - 1)
end

-- OnUnitPower: routes, probes the payload token, and never renders directly.
local onUnitPower = extract("function QUICore:OnUnitPower(event, unit, powerType)", "\nend")
assert(onUnitPower:find("Helpers.IsSecretValue(powerType)", 1, true),
    "powerType must be probed before the routing compares")
assert(onUnitPower:find("RoutePowerEvent(", 1, true), "OnUnitPower must route")
assert(onUnitPower:find("RequestBarUpdates(", 1, true), "OnUnitPower must delegate scheduling")
assert(onUnitPower:find('event == "UNIT_MAXPOWER"', 1, true),
    "UNIT_MAXPOWER must take the full config path")
assert(not onUnitPower:find("self:UpdatePowerBar()", 1, true),
    "OnUnitPower must not render the primary directly")
assert(not onUnitPower:find("self:UpdateSecondaryPowerBar()", 1, true),
    "OnUnitPower must not render the secondary directly")
assert(not onUnitPower:find("QueuePrimaryTrailingUpdate", 1, true)
    and not onUnitPower:find("QueueSecondaryTrailingUpdate", 1, true),
    "OnUnitPower must not hand-queue trailing drains")

-- OnRunePowerUpdate: pure routing, no inline throttle.
local onRune = extract("function QUICore:OnRunePowerUpdate()", "\nend")
assert(onRune:find("RequestBarUpdates(false, true, false, Enum.PowerType.Runes)", 1, true),
    "rune events must go through the orchestrator")
assert(not onRune:find("QueueSecondaryTrailingUpdate", 1, true),
    "OnRunePowerUpdate must not hand-queue trailing drains")

-- The orchestrator owns both queues and the instant-feedback bypass.
local orchestrator = extract("local function RequestBarUpdates(", "\nend\n")
assert(orchestrator:find("QueuePrimaryTrailingUpdate()", 1, true), "orchestrator queues primary drain")
assert(orchestrator:find("QueueSecondaryTrailingUpdate()", 1, true), "orchestrator queues secondary drain")
assert(orchestrator:find("instantFeedbackTypes[resource]", 1, true), "orchestrator owns instant bypass")

-- Drains escalate throttled full-refresh requests to the config path.
local primaryDrain = extract("local function DrainPrimaryPowerUpdate()", "\nend")
assert(primaryDrain:find("primaryFullQueued", 1, true), "primary drain honors full escalation")
local secondaryDrain = extract("local function DrainSecondaryPowerUpdate()", "\nend")
assert(secondaryDrain:find("secondaryFullQueued", 1, true), "secondary drain honors full escalation")

-- Runes must no longer be in the instant-feedback set (rune refreshes have
-- always been throttled via the rune handler; the OnUpdate timer smooths).
local instantBlock = extract("local instantFeedbackTypes = {", "\n}")
assert(not instantBlock:find("Runes", 1, true),
    "Runes must not bypass the throttle")

print("PASS resourcebars_event_orchestrator_test")
