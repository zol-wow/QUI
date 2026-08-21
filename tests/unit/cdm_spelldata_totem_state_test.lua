-- tests/unit/cdm_spelldata_totem_state_test.lua
-- Run: lua tests/unit/cdm_spelldata_totem_state_test.lua

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
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

local secretHaveTotem = {}
local secretName = {}
local secretIcon = {}
local haveTotem = false
local totemName = "Test Totem"
local totemIcon = 12345
local durationObject = { token = "totem-duration" }
local durationQueries = 0

function issecretvalue(value)
    return value == secretHaveTotem or value == secretName or value == secretIcon
end

function GetTotemInfo()
    return haveTotem, totemName, 0, 0, totemIcon, 1, 777
end

function GetTotemDuration()
    durationQueries = durationQueries + 1
    return durationObject
end

local ns = {
    Helpers = {
        IsSecretValue = issecretvalue,
        SafeValue = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function() return false end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local function resolve()
    return ns.CDMAuraRuntime.ResolveState({
        spellID = 777,
        entrySpellID = 777,
        entryID = 777,
        entryName = "Test Totem",
        entryKind = "aura",
        entryIsAura = true,
        entryType = "spell",
        viewerType = "customBar",
        totemSlot = 1,
    })
end

local state = resolve()
assert(state.isActive ~= true, "an empty totem slot must remain inactive")
assert(durationQueries == 0, "an empty totem slot must not query its duration object")

haveTotem = secretHaveTotem
totemName = secretName
totemIcon = secretIcon
state = resolve()
assert(state.isActive ~= true, "secret totem presence must remain unknown")
assert(state.totemName == nil and state.totemIcon == nil, "secret totem metadata must be discarded")
assert(durationQueries == 0, "secret totem presence must not query its duration object")

haveTotem = true
totemName = "Test Totem"
totemIcon = 12345
state = resolve()
assert(state.isActive == true, "a clean active totem should resolve active")
assert(state.durObj == durationObject, "an active totem should preserve its DurationObject")
assert(state.totemName == "Test Totem" and state.totemIcon == 12345,
    "an active totem should preserve clean metadata")
assert(durationQueries == 1, "an active totem should query duration exactly once")

print("OK: cdm_spelldata_totem_state_test")
