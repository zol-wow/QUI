-- tests/unit/cdm_spelldata_aura_entry_crosscat_mirror_test.lua
-- Run: lua tests/unit/cdm_spelldata_aura_entry_crosscat_mirror_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame
--
-- A buff-container aura entry whose Blizzard mirror lives in the SIBLING aura
-- viewer (trackedBar) must still resolve active. Packed mirror state
-- (PackState) signals aura activity via auraInstanceID + auraDurObj, NOT flat
-- isActive/durObj. Reading the removed fields left buff-icon entries dark
-- whenever the aura's only backing cdID was registered in the other aura
-- viewer category -- e.g. Blur (198589) applies buff 212800, which Blizzard
-- registers in trackedBar only, so the buff-container icon's fallback lookup
-- found the state but could never surface it while the trackedBar bar (whose
-- category matched the mirror) rendered fine.

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

local auraDuration = { token = "tracked-aura-duration" }

-- The mirror exists ONLY in trackedBar; the buff category has no cdID for it.
local trackedBarState = {
    cooldownID = 5000,
    viewerCategory = "trackedBar",
    spellID = 212800,
    overrideSpellID = 212800,
    auraInstanceID = 4242,
    auraDurObj = auraDuration,
    auraDurObjSource = "aura-duration",
    auraUnit = "player",
    selfAura = true,
    mirrorEpoch = 3,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
    CDMBlizzMirror = {
        GetMirroredStateForViewer = function(spellID, viewerType)
            if spellID == 212800 and viewerType == "trackedBar" then
                return trackedBarState
            end
            -- buff category: no backing cdID for this aura
            return nil
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local state = ns.CDMAuraRuntime.ResolveState({
    spellID = 212800,
    entrySpellID = 212800,
    entryID = 212800,
    entryName = "Blur",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "buff",
})

assert(state.isActive == true,
    "buff-container aura entry should resolve active from a trackedBar-only mirror")
assert(state.durObj == auraDuration,
    "buff-container aura entry should receive the trackedBar aura DurationObject")
assert(state.auraUnit == "player",
    "self aura should resolve to player")
assert(state.resolvedAuraSpellID == 212800,
    "resolved aura spellID should be the entry's aura id")

print("OK: cdm_spelldata_aura_entry_crosscat_mirror_test")
