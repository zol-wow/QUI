-- tests/unit/cdm_debug_profile_clean_known_helper_test.lua
-- Run: lua tests/unit/cdm_debug_profile_clean_known_helper_test.lua
-- luacheck: globals SlashCmdList InCombatLockdown UnitClass GetSpecializationInfoByID print

SlashCmdList = {}

function InCombatLockdown()
    return false
end

function UnitClass(unit)
    if unit == "player" then
        return "Death Knight", "DEATHKNIGHT", 6
    end
end

local specs = {
    [252] = { name = "Unholy", classFile = "DEATHKNIGHT" },
    [255] = { name = "Survival", classFile = "HUNTER" },
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

local currentClassKnownSpell = 48707
local currentClassForeignSpell = 1252708
local foreignClassSpell = 1252709

local db = {
    _specProfiles = {
        [252] = {
            trackedBar = {
                ownedSpells = {
                    { type = "spell", id = currentClassKnownSpell },
                    { type = "spell", id = currentClassForeignSpell },
                },
                dormantSpells = {
                    [currentClassForeignSpell] = true,
                },
            },
        },
        [255] = {
            trackedBar = {
                ownedSpells = {
                    { type = "spell", id = foreignClassSpell },
                },
                dormantSpells = {
                    [foreignClassSpell] = true,
                },
            },
        },
    },
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = db,
            },
        },
    },
    CDMIcons = {},
    CDMIconFactory = { _iconPools = {} },
    CDMSources = {
        QuerySpellName = function(spellID)
            return "Spell " .. tostring(spellID)
        end,
    },
    CDMSpellData = {
        IsSpellKnown = function(_, spellID)
            return spellID == currentClassKnownSpell
        end,
    },
}

assert(loadfile("QUI_Debug/cdm_debug.lua"))("QUI_Debug", ns)
assert(SlashCmdList["QUI_CDMDEBUG"], "/cdmdebug should be registered")

local ok, err = pcall(SlashCmdList["QUI_CDMDEBUG"], "profile clean")
print = originalPrint

assert(ok, "profile clean should not call a missing IsSpellKnownByPlayer helper: " .. tostring(err))
assert(#db._specProfiles[252].trackedBar.ownedSpells == 1,
    "current-class profile should remove unknown foreign spell")
assert(db._specProfiles[252].trackedBar.ownedSpells[1].id == currentClassKnownSpell,
    "current-class profile should keep known spell")
assert(db._specProfiles[252].trackedBar.dormantSpells[currentClassForeignSpell] == nil,
    "current-class profile should clear unknown dormant shelf records")
assert(#db._specProfiles[255].trackedBar.ownedSpells == 1,
    "foreign-class profile should preserve spells unknown to the current class")
assert(db._specProfiles[255].trackedBar.ownedSpells[1].id == foreignClassSpell,
    "foreign-class profile should not treat unknown foreign spells as current-class leakage")
assert(db._specProfiles[255].trackedBar.dormantSpells[foreignClassSpell] == true,
    "foreign-class dormant records unknown to the current class should be preserved")

local printedDone = false
for _, line in ipairs(messages) do
    if line:find("Done.", 1, true) then
        printedDone = true
        break
    end
end
assert(printedDone, "profile clean should complete and print a summary")

originalPrint("OK: cdm_debug_profile_clean_known_helper_test")
