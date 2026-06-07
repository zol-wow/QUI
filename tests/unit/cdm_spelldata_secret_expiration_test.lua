-- tests/unit/cdm_spelldata_secret_expiration_test.lua
-- Run: lua tests/unit/cdm_spelldata_secret_expiration_test.lua

local originalType = type
local originalIsSecretValue = issecretvalue
local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

local secretHasExpiration = {}
local auraDurationObject = { token = "aura-duration" }
local secretChecks = 0
local secretGlobalChecks = 0
local expirationQueries = 0
local matchingExpirationQueries = 0
local durationQueries = 0

_G.C_CurveUtil = {
    EvaluateColorValueFromBoolean = function()
        error("secret hasExpiration must not be decoded through C_CurveUtil in Lua")
    end,
}

_G.issecretvalue = function(value)
    if value == secretHasExpiration then
        secretGlobalChecks = secretGlobalChecks + 1
        return true
    end
    return false
end

local ns = {
    Helpers = {
        IsSecretValue = function(value)
            if value == secretHasExpiration then
                secretChecks = secretChecks + 1
            end
            return value == secretHasExpiration
        end,
        SafeValue = function(value, fallback)
            if value == secretHasExpiration then
                return fallback
            end
            return value
        end,
        IsAuraOwnedByPlayerOrPet = function(auraData)
            return auraData and auraData.sourceUnit == "player"
        end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
    CDMBlizzMirror = {},
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function()
            return true
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local auraData = {
    spellId = 12345,
    auraInstanceID = 194,
    isHarmful = false,
    isHelpful = true,
    sourceUnit = "player",
    isFromPlayerOrPlayerPet = true,
    duration = 5,
}

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" and spellID == 12345 then
        return auraData
    end
end

ns.CDMSources.QueryAuraHasExpirationTime = function(unit, auraInstanceID)
    expirationQueries = expirationQueries + 1
    if unit == "player" and auraInstanceID == 194 then
        matchingExpirationQueries = matchingExpirationQueries + 1
        return secretHasExpiration
    end
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    durationQueries = durationQueries + 1
    assert(unit == "player" and auraInstanceID == 194,
        "secret hasExpiration should fall back to the resolved player duration")
    return auraDurationObject
end

_G.type = function(value)
    if value == secretHasExpiration then
        error("secret hasExpiration was inspected in Lua")
    end
    return originalType(value)
end

local ok, stateOrErr = pcall(function()
    return ns.CDMAuraRuntime.ResolveState({
        spellID = 12345,
        entrySpellID = 12345,
        entryID = 12345,
        entryName = "Test Buff",
        entryKind = "aura",
        entryIsAura = true,
        entryType = "spell",
        viewerType = "trackedBar",
    })
end)

_G.type = originalType
_G.issecretvalue = originalIsSecretValue

assert(ok, "secret hasExpiration should be ignored safely: " .. tostring(stateOrErr))
assert(stateOrErr.isActive == true, "aura should still resolve as active")
assert(expirationQueries > 0, "aura expiration source should be queried")
assert(matchingExpirationQueries > 0, "aura expiration source should query the resolved player instance")
assert(secretChecks == 0, "secret hasExpiration must not go through safe-helper inspection")
assert(secretGlobalChecks > 0, "secret hasExpiration should be filtered through the global secret check")
assert(durationQueries > 0, "secret hasExpiration should fall back to duration object lookup")
assert(stateOrErr.durObj == auraDurationObject, "timed aura should carry the queried duration object")
assert(stateOrErr.hasExpirationTime == true, "readable aura duration should determine expiration state")
assert(stateOrErr.hideDurationText ~= true, "timed aura should not hide duration text")

print("OK: cdm_spelldata_secret_expiration_test")
