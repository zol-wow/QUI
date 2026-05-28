-- tests/unit/apply_cooldown_from_aura_test.lua
-- Run: lua tests/unit/apply_cooldown_from_aura_test.lua
-- luacheck: globals LibStub

local secretExpiration = { token = "secret-expiration" }
local secretDuration = { token = "secret-duration" }
local secretCooldownStartComparisons = 0
local secretCooldownDurationComparisons = 0
local secretCooldownStart = setmetatable({ token = "secret-cooldown-start" }, {
    __gt = function()
        secretCooldownStartComparisons = secretCooldownStartComparisons + 1
        error("secret cooldown start must not be compared")
    end,
})
local secretCooldownDuration = setmetatable({ token = "secret-cooldown-duration" }, {
    __gt = function()
        secretCooldownDurationComparisons = secretCooldownDurationComparisons + 1
        error("secret cooldown duration must not be compared")
    end,
})
local durationObject = { token = "base-duration-object" }
local durationObjectCalls = 0
local returnDurationObject = true

local function assertEquals(actual, expected, message)
    assert(actual == expected, message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

LibStub = function() return nil end

_G.issecretvalue = function(value)
    return value == secretExpiration
        or value == secretDuration
        or value == secretCooldownStart
        or value == secretCooldownDuration
end

_G.C_UnitAuras = {
    GetAuraDuration = function(unit, auraInstanceID)
        durationObjectCalls = durationObjectCalls + 1
        assertEquals(unit, "player", "duration object lookup should use the aura unit")
        assertEquals(auraInstanceID, 777, "duration object lookup should use auraInstanceID")
        if returnDurationObject then
            return durationObject
        end
    end,
}

local ns = {}
assert(loadfile("core/utils.lua"))("QUI", ns)

do
    local handle = assert(io.open("core/utils.lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    assert(not source:find("pcall%(function%(%)%s*return duration > 0 and start > 0%s*end%)"),
        "IsCooldownActive must not probe secret timing by attempting a Lua comparison")
end

local active = ns.Helpers.IsCooldownActive(secretCooldownStart, secretCooldownDuration, nil)
assert(active == true, "secret cooldown timing should be treated as active/unknown")
assertEquals(secretCooldownStartComparisons, 0, "secret cooldown start must not be Lua-compared")
assertEquals(secretCooldownDurationComparisons, 0, "secret cooldown duration must not be Lua-compared")
assert(ns.Helpers.IsCooldownActive(secretCooldownStart, secretCooldownDuration, false) == false,
    "NeverSecret isActive=false should still win over secret timing")

local defaultCooldown = {}
function defaultCooldown:SetCooldownFromDurationObject(durObj, clearIfZero)
    self.durationObject = durObj
    self.clearIfZero = clearIfZero
end
function defaultCooldown:SetCooldownFromExpirationTime(expirationTime, duration, modRate)
    self.expirationTime = expirationTime
    self.duration = duration
    self.modRate = modRate
end
function defaultCooldown:Clear()
    self.cleared = true
end

local applied = ns.Helpers.ApplyCooldownFromAura(defaultCooldown, "player", 777, 7300, 7200, true, 1.25)
assert(applied, "default clean aura timing should apply")
assertEquals(defaultCooldown.durationObject, durationObject, "default clean aura timing should prefer DurationObject")
assertEquals(defaultCooldown.expirationTime, nil, "default clean aura timing should not use numeric timing first")
assertEquals(defaultCooldown.clearIfZero, true, "default DurationObject path should preserve clearIfZero")
assertEquals(defaultCooldown.cleared, nil, "default clean aura timing should not clear the cooldown")
assertEquals(durationObjectCalls, 1, "default clean aura timing should query DurationObject once")

local cleanCooldown = {}
function cleanCooldown:SetCooldownFromDurationObject(durObj, clearIfZero)
    error("numeric fallback should only run when no DurationObject is available")
end
function cleanCooldown:SetCooldownFromExpirationTime(expirationTime, duration, modRate)
    self.expirationTime = expirationTime
    self.duration = duration
    self.modRate = modRate
end
function cleanCooldown:Clear()
    self.cleared = true
end

returnDurationObject = false
applied = ns.Helpers.ApplyCooldownFromAura(cleanCooldown, "player", 777, 7300, 7200, true, 1.25)
assert(applied, "clean aura timing should fall back when no DurationObject is available")
assertEquals(cleanCooldown.expirationTime, 7300, "numeric fallback should use expirationTime")
assertEquals(cleanCooldown.duration, 7200, "numeric fallback should preserve clean total duration")
assertEquals(cleanCooldown.modRate, 1.25, "numeric fallback should preserve modRate")
assertEquals(cleanCooldown.cleared, nil, "numeric fallback should not clear the cooldown")
assertEquals(durationObjectCalls, 2, "numeric fallback should still attempt DurationObject first")

local secretCooldown = {}
function secretCooldown:SetCooldownFromDurationObject(durObj, clearIfZero)
    self.durationObject = durObj
    self.clearIfZero = clearIfZero
end
function secretCooldown:SetCooldownFromExpirationTime()
    error("secret numeric aura timing must not call SetCooldownFromExpirationTime")
end
function secretCooldown:Clear()
    self.cleared = true
end

returnDurationObject = true
applied = ns.Helpers.ApplyCooldownFromAura(secretCooldown, "player", 777, secretExpiration, secretDuration, true)
assert(applied, "secret numeric aura timing should fall back to DurationObject")
assertEquals(secretCooldown.durationObject, durationObject, "secret numeric aura timing should use DurationObject")
assertEquals(secretCooldown.clearIfZero, true, "DurationObject path should preserve clearIfZero")
assertEquals(secretCooldown.cleared, nil, "secret numeric aura timing should not clear when DurationObject is available")
assertEquals(durationObjectCalls, 3, "secret numeric aura timing should query DurationObject once")

print("OK: apply_cooldown_from_aura_test")
