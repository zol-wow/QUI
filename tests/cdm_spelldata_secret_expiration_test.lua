-- tests/cdm_spelldata_secret_expiration_test.lua
-- Run: lua tests/cdm_spelldata_secret_expiration_test.lua

local originalType = type
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
local secretChecks = 0
local curveCalls = 0
local expirationQueries = 0
local matchingExpirationQueries = 0
local durationQueries = 0

_G.C_CurveUtil = {
    EvaluateColorValueFromBoolean = function(value, valueIfTrue, valueIfFalse)
        assert(value == secretHasExpiration, "curve util should receive the secret boolean directly")
        curveCalls = curveCalls + 1
        return valueIfFalse
    end,
}

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

assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

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
    error("permanent aura should not query a duration object")
end

_G.type = function(value)
    if value == secretHasExpiration then
        error("secret hasExpiration was inspected in Lua")
    end
    return originalType(value)
end

local ok, stateOrErr = pcall(function()
    return ns.CDMSpellData:ResolveAuraState({
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

assert(ok, "secret hasExpiration should be ignored safely: " .. tostring(stateOrErr))
assert(stateOrErr.isActive == true, "aura should still resolve as active")
assert(expirationQueries > 0, "aura expiration source should be queried")
assert(matchingExpirationQueries > 0, "aura expiration source should query the resolved player instance")
assert(secretChecks > 0, "secret hasExpiration should be checked before Lua inspection")
assert(curveCalls > 0, "secret hasExpiration should be decoded through C_CurveUtil")
assert(durationQueries == 0, "secret false expiration should skip duration object lookup")
assert(stateOrErr.durObj == nil, "permanent aura should not carry a duration object")
assert(stateOrErr.hasExpirationTime == false, "secret false hasExpiration should be preserved")
assert(stateOrErr.hideDurationText == true, "permanent aura should hide duration text")

print("OK: cdm_spelldata_secret_expiration_test")
