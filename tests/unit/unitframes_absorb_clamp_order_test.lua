-- tests/unit/unitframes_absorb_clamp_order_test.lua
-- Run: lua tests/unit/unitframes_absorb_clamp_order_test.lua

local path = "QUI_UnitFrames/unitframes/unitframes.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local startPos = assert(source:find("local function UpdateAbsorbs%(frame%)"),
    "UpdateAbsorbs should exist")
local endPos = assert(source:find("%-%- Heal absorbs", startPos),
    "UpdateAbsorbs heal-absorb section should exist")
local body = source:sub(startPos, endPos)

local damageClampModePos = assert(body:find("SetDamageAbsorbClampMode", 1, true),
    "UpdateAbsorbs should configure damage absorb clamping")
local damageAbsorbsPos = assert(body:find("calc:GetDamageAbsorbs", 1, true),
    "UpdateAbsorbs should read clamped damage absorbs")
local defaultModePos = body:find("UnitMaximumHealthMode.Default", 1, true)
    or body:find("maximumHealthMode.Default", 1, true)
assert(defaultModePos,
    "UpdateAbsorbs should reset max-health mode before reading clamped absorbs")
local withAbsorbsModePos = body:find("UnitMaximumHealthMode.WithAbsorbs", 1, true)
    or body:find("maximumHealthMode.WithAbsorbs", 1, true)
assert(withAbsorbsModePos,
    "UpdateAbsorbs should configure WithAbsorbs max-health mode for visibility")
local visibilityEvalPos = assert(body:find("calc:EvaluateCurrentHealthPercent", 1, true),
    "UpdateAbsorbs should evaluate the visibility curve")

assert(damageClampModePos < damageAbsorbsPos,
    "damage absorb clamp mode should be configured before reading clamped absorbs")
assert(defaultModePos < damageAbsorbsPos,
    "default max-health mode should be restored before GetDamageAbsorbs")
assert(damageAbsorbsPos < withAbsorbsModePos,
    "WithAbsorbs max-health mode must not be applied before GetDamageAbsorbs")
assert(withAbsorbsModePos < visibilityEvalPos,
    "WithAbsorbs max-health mode should only be applied for visibility evaluation")

print("OK: unitframes_absorb_clamp_order_test")
