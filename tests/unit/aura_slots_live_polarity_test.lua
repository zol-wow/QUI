local function fail(msg)
    print("FAIL: aura_slots_live_polarity_test - " .. msg)
    os.exit(1)
end

local SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })

local assistable, dead, phase = {}, {}, {}

UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function(unit) return dead[unit] == true end
UnitCanAssist = function(_, unit) return assistable[unit] == true end
UnitIsVisible = function() return true end
UnitPhaseReason = function(unit) return phase[unit] end
issecretvalue = function(v) return v == SECRET end

local ns = {}
assert(loadfile("core/aura_slots.lua"))("QUI", ns)
local S = ns.AuraSlots
if type(S) ~= "table" or type(S.LivePolarityMismatch) ~= "function" then
    fail("core/aura_slots.lua must export S.LivePolarityMismatch")
end

local mismatch = S.LivePolarityMismatch

for _, token in ipairs({ "player", "pet", "party3", "raid17", "boss2" }) do
    if mismatch(token, "HELPFUL") or mismatch(token, "HARMFUL") then
        fail("a token with a static reaction class must never park on live polarity: " .. token)
    end
end

local DYNAMIC = { "target", "targettarget", "focus", "focustarget", "mouseover" }

for _, token in ipairs(DYNAMIC) do
    assistable[token] = true
    if mismatch(token, "HELPFUL") then
        fail("a HELPFUL element on a live friendly " .. token .. " must not park")
    end
    if not mismatch(token, "HARMFUL") then
        fail("a HARMFUL element on a live friendly " .. token .. " must park")
    end

    assistable[token] = false
    if not mismatch(token, "HELPFUL") then
        fail("a HELPFUL element on a live hostile " .. token .. " must park")
    end
    if mismatch(token, "HARMFUL") then
        fail("a HARMFUL element on a live hostile " .. token .. " must not park")
    end
end

assistable.target = false
if not mismatch("target", nil) then
    fail("a nil auraType must read as HELPFUL and park on a hostile target")
end
if not mismatch("target", "HELPFUL|PLAYER") then
    fail("a compound HELPFUL filter string must park on a hostile target")
end
if mismatch("target", "HARMFUL|PLAYER") then
    fail("a compound HARMFUL filter string must not park on a hostile target")
end

assistable.target = true
if not mismatch("target", "HARMFUL|PLAYER") then
    fail("a compound HARMFUL filter string must park on a friendly target")
end

dead.target = true
if not mismatch("target", "HELPFUL") then
    fail("a dead friendly target must park a HELPFUL element - the engine yields no slots either")
end
dead.target = false

phase.target = "phased"
if not mismatch("target", "HELPFUL") then
    fail("a phased friendly target must park a HELPFUL element")
end
phase.target = nil

phase.target = SECRET
if not mismatch("target", "HELPFUL") then
    fail("a secret phase reason must fail closed and park a HELPFUL element")
end
phase.target = nil

local realCanAssist = UnitCanAssist
UnitCanAssist = function() error("truth test on a secret value", 0) end
if not mismatch("target", "HELPFUL") then
    fail("a probe that throws must fail closed and park a HELPFUL element")
end
if mismatch("target", "HARMFUL") then
    fail("a probe that throws must read as not-assistable, leaving HARMFUL unparked")
end
UnitCanAssist = realCanAssist

if not mismatch(nil, "HELPFUL") then
    fail("an unresolvable unit must fail closed and park a HELPFUL element")
end

print("PASS: aura_slots_live_polarity_test")
