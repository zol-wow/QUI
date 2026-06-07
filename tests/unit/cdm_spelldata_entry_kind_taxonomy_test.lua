-- tests/unit/cdm_spelldata_entry_kind_taxonomy_test.lua
-- Run: lua tests/unit/cdm_spelldata_entry_kind_taxonomy_test.lua

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

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        GetBuiltinContainerEntryKind = function(containerKey)
            return ({
                essential = "cooldown",
                utility = "cooldown",
                buff = "aura",
                trackedBar = "aura",
                aliasAura = "aura",
            })[containerKey]
        end,
    },
    CDMSources = {},
    CDMBlizzMirror = {
        GetCooldownIDForViewer = function(spellID, viewerType)
            if spellID == 100 and viewerType == "essential" then return 1 end
            if spellID == 200 and viewerType == "buff" then return 2 end
            if spellID == 300 and viewerType == "essential" then return 3 end
            if spellID == 300 and viewerType == "buff" then return 4 end
            return nil
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local resolveKind = assert(ns.CDMSpellData.ResolveEntryKind,
    "ResolveEntryKind was not exported")

assert(resolveKind({ id = 1, type = "spell", kind = "aura" }, "essential") == "aura",
    "explicit entry kind should win over container taxonomy")
assert(resolveKind({ id = 1, type = "item" }, "buff") == "cooldown",
    "non-spell entries should remain cooldown entries")
assert(resolveKind({ id = 1, type = "spell" }, "buff") == "aura",
    "built-in buff container should imply aura kind")
assert(resolveKind({ id = 1, type = "spell" }, "essential") == "cooldown",
    "built-in essential container should imply cooldown kind")
assert(resolveKind({ id = 1, type = "spell" }, "aliasAura") == "aura",
    "entry kind resolution should use the shared container taxonomy helper")
assert(resolveKind({ id = 100, type = "spell" }, "customBar") == "cooldown",
    "custom container entries should use mirror cooldown classification")
assert(resolveKind({ id = 200, type = "spell" }, "customBar") == "aura",
    "custom container entries should use mirror aura classification")
assert(resolveKind({ id = 300, type = "spell" }, "customBar") == "cooldown",
    "cooldown mirror classification should win when a spell appears in both families")
assert(resolveKind({ id = 400, type = "spell" }, "customBar") == "cooldown",
    "unknown custom container spell should default to cooldown kind")

print("OK: cdm_spelldata_entry_kind_taxonomy_test")
