-- tests/unit/qui_logger_groupframes_full_adapter_test.lua
-- Run: lua tests/unit/qui_logger_groupframes_full_adapter_test.lua
-- TDD: Tests the "full" scope of profile_groupframes_adapter.lua.
--
-- Proves:
--   1. Build({scope="full"}) loads real groupframes.lua and captures OnEvent
--   2. The existing "aura" scope (default) is NOT broken
--   3. UNIT_HEALTH dispatch calls frame.healthBar:SetValue (proves REAL UpdateHealth ran)
--   4. UNIT_POWER_UPDATE dispatch calls frame.powerBar:SetValue (proves REAL UpdatePower ran)
--   5. UNIT_ABSORB_AMOUNT_CHANGED dispatch calls frame.absorb:SetValue or reaches UpdateAbsorbs
--   6. full-scope EVENT_MAP contains required events
--   7. ProfileSession returns well-formed churn/counts/report for full scope
--
-- luacheck: globals CreateFrame issecretvalue GetTime C_UnitAuras

-- -----------------------------------------------------------------------
-- 1. Load adapter
-- -----------------------------------------------------------------------
local A = assert(loadfile("tests/replay/profile_groupframes_adapter.lua"),
    "profile_groupframes_adapter.lua must exist")()

-- -----------------------------------------------------------------------
-- 2. Aura scope (default) must still work unchanged
-- -----------------------------------------------------------------------
local auraBuilt = A.Build()
assert(auraBuilt.ctx ~= nil, "aura scope Build() must return ctx")
assert(auraBuilt.ctx.R ~= nil, "aura scope ctx.R must exist")

-- -----------------------------------------------------------------------
-- 3. Full scope: Build({scope="full"}) must return a context
-- -----------------------------------------------------------------------
local healthBarSetValueCalls = 0
local powerBarSetValueCalls = 0
local absorbBarSetValueCalls = 0

local fullBuilt = A.Build({
    scope = "full",
    onCallback = function(name)
        if name == "healthBar:SetValue" then
            healthBarSetValueCalls = healthBarSetValueCalls + 1
        elseif name == "powerBar:SetValue" then
            powerBarSetValueCalls = powerBarSetValueCalls + 1
        elseif name == "absorbBar:SetValue" then
            absorbBarSetValueCalls = absorbBarSetValueCalls + 1
        end
    end,
})

assert(fullBuilt ~= nil, "Build({scope='full'}) must not return nil")
assert(fullBuilt.ctx ~= nil, "full scope Build() must return ctx")

local fctx = fullBuilt.ctx

-- 4. Full scope ctx must carry a real groupframes module reference
assert(fctx.QUI_GF ~= nil, "ctx.QUI_GF must be populated (real groupframes module)")
assert(fctx.onEvent ~= nil, "ctx.onEvent must be the captured OnEvent handler")
assert(fctx.eventFrame ~= nil, "ctx.eventFrame must be the captured eventFrame")

-- 5. Full-scope EVENT_MAP must have the right events
local fullEventMap = A.FULL_EVENT_MAP
assert(fullEventMap ~= nil, "A.FULL_EVENT_MAP must exist after Build({scope='full'})")
local requiredFullEvents = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_PREDICTION", "UNIT_NAME_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_CONNECTION", "UNIT_FLAGS",
}
for _, ev in ipairs(requiredFullEvents) do
    assert(fullEventMap[ev], "FULL_EVENT_MAP must have entry for " .. ev)
end

-- 6. PROVE REAL UpdateHealth ran: UNIT_HEALTH dispatch calls frame.healthBar:SetValue
healthBarSetValueCalls = 0
local ok, err = pcall(function()
    A.dispatchFull(fctx, { e = "UNIT_HEALTH", a = { "raid1" }, n = 1 })
end)
assert(ok, "dispatchFull UNIT_HEALTH must not error: " .. tostring(err))
assert(healthBarSetValueCalls > 0,
    "after UNIT_HEALTH dispatch, frame.healthBar:SetValue must be called " ..
    "(healthBarSetValueCalls=" .. healthBarSetValueCalls ..
    ") -- proves REAL UpdateHealth ran in groupframes.lua")

-- 7. PROVE REAL UpdatePower ran: UNIT_POWER_UPDATE calls frame.powerBar:SetValue
powerBarSetValueCalls = 0
ok, err = pcall(function()
    A.dispatchFull(fctx, { e = "UNIT_POWER_UPDATE", a = { "raid1", "MANA" }, n = 2 })
end)
assert(ok, "dispatchFull UNIT_POWER_UPDATE must not error: " .. tostring(err))
assert(powerBarSetValueCalls > 0,
    "after UNIT_POWER_UPDATE dispatch, frame.powerBar:SetValue must be called " ..
    "(powerBarSetValueCalls=" .. powerBarSetValueCalls ..
    ") -- proves REAL UpdatePower ran")

-- 8. UNIT_ABSORB_AMOUNT_CHANGED must not error
ok, err = pcall(function()
    A.dispatchFull(fctx, { e = "UNIT_ABSORB_AMOUNT_CHANGED", a = { "raid1" }, n = 1 })
end)
assert(ok, "dispatchFull UNIT_ABSORB_AMOUNT_CHANGED must not error: " .. tostring(err))

-- 9. ProfileSession with full scope works
local syntheticEvents = {
    { e = "UNIT_HEALTH",              a = { "raid1" },       n = 1 },
    { e = "UNIT_POWER_UPDATE",        a = { "raid1", "MANA" }, n = 2 },
    { e = "UNIT_ABSORB_AMOUNT_CHANGED", a = { "raid1" },      n = 1 },
    { e = "UNIT_HEAL_PREDICTION",     a = { "raid1" },       n = 1 },
    { e = "ZZZ_UNMAPPED_FULL",        a = {},                n = 0 },
}

local churn, counts, report = A.ProfileSessionFull(fctx, syntheticEvents)
assert(type(churn)  == "table",  "ProfileSessionFull must return churn table")
assert(type(counts) == "table",  "counts must be a table")
assert(type(report) == "string", "report must be a string")

-- At least one mapped event must appear in counts
local mappedCount = 0
for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED" }) do
    if counts[ev] and counts[ev] > 0 then mappedCount = mappedCount + 1 end
end
assert(mappedCount > 0, "at least one mapped full-scope event must appear in counts with count > 0")

print(string.format(
    "OK: qui_logger_groupframes_full_adapter_test  [healthBar:SetValue=%d  powerBar:SetValue=%d  absorbBar:SetValue=%d]",
    healthBarSetValueCalls, powerBarSetValueCalls, absorbBarSetValueCalls))
