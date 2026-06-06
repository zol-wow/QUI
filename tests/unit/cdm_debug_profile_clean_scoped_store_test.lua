-- tests/unit/cdm_debug_profile_clean_scoped_store_test.lua
-- Run: lua tests/unit/cdm_debug_profile_clean_scoped_store_test.lua
-- luacheck: globals SlashCmdList InCombatLockdown UnitClass GetSpecialization GetSpecializationInfo
-- luacheck: globals GetSpecializationInfoByID print

SlashCmdList = {}

function InCombatLockdown()
    return false
end

function UnitClass(unit)
    if unit == "player" then
        return "Death Knight", "DEATHKNIGHT", 6
    end
end

function GetSpecialization()
    return 1
end

function GetSpecializationInfo(index)
    if index == 1 then
        return 250, "Blood", "", 0, "TANK"
    end
end

local specs = {
    [250] = { name = "Blood", classFile = "DEATHKNIGHT" },
    [252] = { name = "Unholy", classFile = "DEATHKNIGHT" },
}

function GetSpecializationInfoByID(specID)
    local spec = specs[specID]
    if not spec then return nil end
    return specID, spec.name, "", 0, "DAMAGER", spec.classFile
end

local messages = {}
local originalPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    messages[#messages + 1] = table.concat(parts, " ")
end

local bloodSpell = 50842
local unholySpell = 85948
local manualAuraSpell = 1234567

local profileNcdm = {
    perLoadoutSpec = false,
    _lastSpecID = 250,
    _lastSpecCharKey = "Ghstridr - Illidan",
    essential = {
        ownedSpells = {
            { type = "spell", id = bloodSpell },
            { type = "spell", id = unholySpell },
        },
    },
    buff = {
        ownedSpells = {
            { type = "spell", id = manualAuraSpell, kind = "aura" },
        },
    },
}

local charNcdm = {
    _lastSpecID = 250,
    _lastSpecCharKey = "Ghstridr - Illidan",
    _specProfilesByProfile = {
        Default = {
            [250] = {
                [0] = {
                    essential = {
                        ownedSpells = {
                            { type = "spell", id = bloodSpell },
                            { type = "spell", id = unholySpell },
                        },
                    },
                    buff = {
                        ownedSpells = {
                            { type = "spell", id = manualAuraSpell, kind = "aura" },
                        },
                    },
                },
            },
            [252] = {
                [0] = {
                    essential = {
                        ownedSpells = {
                            { type = "spell", id = unholySpell },
                        },
                    },
                },
            },
        },
    },
}

local addonDB = {
    profile = { ncdm = profileNcdm },
    char = { ncdm = charNcdm },
}

function addonDB:GetCurrentProfile()
    return "Default"
end

local ns = {
    Addon = { db = addonDB },
    CDMIcons = {},
    CDMIconFactory = { _iconPools = {} },
    CDMSources = {
        QuerySpellName = function(spellID)
            return "Spell " .. tostring(spellID)
        end,
    },
    CDMCatalog = {
        CollectKnownCDMSpellIDs = function(out)
            out[bloodSpell] = true
            return out
        end,
    },
    CDMSpellData = {
        IsSpellKnown = function(_, spellID)
            return spellID == bloodSpell or spellID == unholySpell
        end,
    },
}

assert(loadfile("QUI_Debug/cdm_debug.lua"))("QUI_Debug", ns)
assert(SlashCmdList["QUI_CDMDEBUG"], "/cdmdebug should be registered")

local ok, err = pcall(SlashCmdList["QUI_CDMDEBUG"], "profile clean")
print = originalPrint

assert(ok, "profile clean should run against scoped profiles: " .. tostring(err))

local scopedOwned = charNcdm._specProfilesByProfile.Default[250][0].essential.ownedSpells
assert(#scopedOwned == 1 and scopedOwned[1].id == bloodSpell,
    "current spec scoped slot should remove same-class spells missing from the current CDM catalog")

local liveOwned = profileNcdm.essential.ownedSpells
assert(#liveOwned == 1 and liveOwned[1].id == bloodSpell,
    "current live profile should remove same-class spells missing from the current CDM catalog")

local scopedBuffOwned = charNcdm._specProfilesByProfile.Default[250][0].buff.ownedSpells
assert(#scopedBuffOwned == 1 and scopedBuffOwned[1].id == manualAuraSpell,
    "manual aura spell IDs should not be removed just because they are absent from Blizzard CDM")

local unholyOwned = charNcdm._specProfilesByProfile.Default[252][0].essential.ownedSpells
assert(#unholyOwned == 1 and unholyOwned[1].id == unholySpell,
    "cleanup must not use the current spec catalog to rewrite other specs")

local printedScoped = false
for _, line in ipairs(messages) do
    if line:find("current spec scoped", 1, true) then
        printedScoped = true
        break
    end
end
assert(printedScoped, "profile clean should report scoped current-spec cleanup")

originalPrint("OK: cdm_debug_profile_clean_scoped_store_test")
