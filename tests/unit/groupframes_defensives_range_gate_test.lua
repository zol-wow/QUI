-- tests/unit/groupframes_defensives_range_gate_test.lua
-- Source-text assertion test for the out-of-range fail-closed gate on
-- classification filter strips (defensives).
--
-- Blizzard's BIG_DEFENSIVE / EXTERNAL_DEFENSIVE aura filters fail OPEN on
-- distance-obfuscated aura data: for out-of-range units the engine matches
-- arbitrary buffs, so the defensives strip showed icons with nothing up
-- (originally fixed Lua-side in PR #484; that fix died with the move to the
-- secure AuraContainer engine, where QUI cannot re-verify per aura).
-- The engine-era fix fails CLOSED at the strip level instead: containers whose
-- element classifies on bigDefensive/externalDefensive are blanked (alpha 0)
-- while their unit is out of range, driven by the existing range plumbing.
-- Run: lua tests/unit/groupframes_defensives_range_gate_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_GroupFrames/groupframes/groupframes_auras.lua")
local callSrc = readAll("QUI_GroupFrames/groupframes/groupframes.lua")

local fails = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        fails = fails + 1
        print("FAIL  " .. name)
    end
end

-- THE GATE PREDICATE: only classification strips carrying the defensive
-- classes are gated — plain buff/debuff strips and tracked displays are not.
check("ElementNeedsRangeGate predicate defined",
    src:find("local function ElementNeedsRangeGate(element)", 1, true) ~= nil)
check("gate applies to filterStrip mode only",
    src:find('element.mode ~= "filterStrip"', 1, true) ~= nil)
check("gate applies to classify filterMode only",
    src:find('element.filterMode ~= "classify"', 1, true) ~= nil)
check("gate keys on the distance-obfuscated defensive classifications",
    src:find("c.bigDefensive == true", 1, true) ~= nil
    and src:find("c.externalDefensive == true", 1, true) ~= nil)

-- THE APPLICATOR: exported, and blanks via the secret-safe boolean alpha sink
-- (range can be a secret boolean in combat — never branch on it Lua-side).
check("QUI_GFA.ApplyRangeGate exported for the range plumbing",
    src:find("function QUI_GFA.ApplyRangeGate(frame, inRange)", 1, true) ~= nil)
check("gated containers blank through the SetAlphaFromBoolean secret sink",
    src:find("container:SetAlphaFromBoolean(inRange, 1, 0)", 1, true) ~= nil)
check("plain SetAlpha fallback rejects secret range values",
    src:find("elseif not IsSecretValue(inRange) then", 1, true) ~= nil)
check("only marked containers are touched",
    src:find("container._quiRangeGated", 1, true) ~= nil)

-- MARKING + SEEDING: containers are flagged as elements are anchored, a
-- container recycled onto a non-gated element gets its alpha restored, and a
-- fresh config pass seeds the gate from the live range state.
check("anchorContainer marks the container from the element",
    src:find("container._quiRangeGated = gated", 1, true) ~= nil)
check("recycled container un-gates back to full alpha",
    src:find("if container._quiRangeGated and not gated then", 1, true) ~= nil)
check("ApplyElementPass seeds the gate after the container pass",
    src:find("QUI_GFA.ApplyRangeGate(frame)", 1, true) ~= nil)
check("seed path resolves range via GF.CheckUnitRange",
    src:find("GF.CheckUnitRange", 1, true) ~= nil)

-- RANGE PLUMBING CALL SITES: both the ticker and the UNIT_IN_RANGE_UPDATE
-- event path re-apply the gate on range transitions. The event path must sit
-- OUTSIDE the range-fade settings check — the gate is correctness, not fade.
local tickerBody = callSrc:match("local function DoRangeCheck%(%)(.-)\nend")
check("DoRangeCheck (ticker) re-applies the gate on range change",
    tickerBody ~= nil
    and tickerBody:find("GFA.ApplyRangeGate(frame, inRange)", 1, true) ~= nil)
local eventBody = callSrc:match("function _state%.HandleRangeUpdate%(unit%)(.-)\nend")
check("HandleRangeUpdate (UNIT_IN_RANGE_UPDATE) re-applies the gate",
    eventBody ~= nil
    and eventBody:find("GFA.ApplyRangeGate(frame, inRange)", 1, true) ~= nil)
check("event-path gate is not conditioned on the range-fade settings",
    eventBody ~= nil
    and eventBody:find("ApplyRangeGate")
        < eventBody:find("rangeSettings and rangeSettings.enabled", 1, true))

-- BEHAVIORAL: extract the gate between its QUI_TEST_EXTRACT sentinels and
-- exercise it against stub containers. The two functions only reach ns /
-- IsSecretValue / GetFrameUnit / QUI_GFA from file scope, so a prelude can
-- inject all four.
local loadSource = loadstring or load
local s = assert(src:find("-- >>> QUI_TEST_EXTRACT range_gate", 1, true), "begin sentinel")
local fnStart = assert(src:find("\n", s)) + 1
local e = assert(src:find("\n%-%- <<< QUI_TEST_EXTRACT range_gate", fnStart), "end sentinel")
local fnSource = src:sub(fnStart, e - 1)

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local prelude = "local ns, IsSecretValue, GetFrameUnit = ...\nlocal QUI_GFA = {}\n"
local nsStub = { QUI_GroupFrames = {} }
local chunk = assert(loadSource(
    prelude .. fnSource .. "\nreturn QUI_GFA, ElementNeedsRangeGate", "range_gate"))
local QUI_GFA, ElementNeedsRangeGate = chunk(
    nsStub,
    function(v) return v == SECRET end,
    function(frame) return frame.unit end)

local function makeContainer(gated, withSink)
    local c = { _quiRangeGated = gated, alpha = "untouched", sink = nil }
    c.SetAlpha = function(self, a) self.alpha = a end
    if withSink then
        c.SetAlphaFromBoolean = function(self, b, onA, offA)
            self.sink = { b, onA, offA }
        end
    end
    return c
end
local function makeFrame(containers, unit)
    return { _quiAuraContainers = containers, unit = unit }
end

-- Predicate: exactly the defensive-classified classify strips are gated.
check("predicate gates classify strip with bigDefensive",
    ElementNeedsRangeGate({ mode = "filterStrip", filterMode = "classify",
        classifications = { bigDefensive = true } }) == true)
check("predicate gates classify strip with externalDefensive",
    ElementNeedsRangeGate({ mode = "filterStrip", filterMode = "classify",
        classifications = { externalDefensive = true } }) == true)
check("predicate ignores classify strip without defensive classes",
    ElementNeedsRangeGate({ mode = "filterStrip", filterMode = "classify",
        classifications = { raid = true, crowdControl = true } }) == false)
check("predicate ignores non-classify strips (default buff strip)",
    ElementNeedsRangeGate({ mode = "filterStrip", filterMode = "off",
        classifications = { bigDefensive = true } }) == false)
check("predicate ignores tracked elements",
    ElementNeedsRangeGate({ mode = "tracked", filterMode = "classify",
        classifications = { bigDefensive = true } }) == false)

-- Sink path: readable and SECRET range both route through SetAlphaFromBoolean.
do
    local c = makeContainer(true, true)
    QUI_GFA.ApplyRangeGate(makeFrame({ c }), false)
    check("out of range blanks the gated strip via the sink (alpha 0)",
        c.sink and c.sink[1] == false and c.sink[2] == 1 and c.sink[3] == 0)
    QUI_GFA.ApplyRangeGate(makeFrame({ c }), true)
    check("back in range restores the gated strip via the sink (alpha 1)",
        c.sink and c.sink[1] == true)
    local ok = pcall(QUI_GFA.ApplyRangeGate, makeFrame({ c }), SECRET)
    check("secret range passes through the sink untouched, no Lua branch",
        ok and c.sink and c.sink[1] == SECRET)
end

-- Fallback path (no sink API): plain booleans apply, secrets are rejected.
do
    local c = makeContainer(true, false)
    QUI_GFA.ApplyRangeGate(makeFrame({ c }), false)
    check("fallback SetAlpha(0) when out of range", c.alpha == 0)
    QUI_GFA.ApplyRangeGate(makeFrame({ c }), true)
    check("fallback SetAlpha(1) when in range", c.alpha == 1)
    c.alpha = "untouched"
    local ok = pcall(QUI_GFA.ApplyRangeGate, makeFrame({ c }), SECRET)
    check("fallback rejects a secret range value (container untouched)",
        ok and c.alpha == "untouched")
end

-- Ungated containers are never touched regardless of range.
do
    local c = makeContainer(false, true)
    QUI_GFA.ApplyRangeGate(makeFrame({ c }), false)
    check("ungated container untouched by the gate",
        c.sink == nil and c.alpha == "untouched")
end

-- Seed path: no inRange argument resolves through GF.CheckUnitRange.
do
    local c = makeContainer(true, true)
    local asked
    nsStub.QUI_GroupFrames.CheckUnitRange = function(unit)
        asked = unit
        return false
    end
    QUI_GFA.ApplyRangeGate(makeFrame({ c }, "party2"))
    check("seed path resolves range for the frame's unit",
        asked == "party2" and c.sink and c.sink[1] == false)
end

if fails > 0 then error(fails .. " failure(s) in groupframes_defensives_range_gate_test") end
print("OK: groupframes_defensives_range_gate_test (all checks passed)")
