-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame IsSpellKnown IsPlayerSpell

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
        RegisterEvent       = noop,
        RegisterUnitEvent   = noop,
        UnregisterEvent     = noop,
        UnregisterAllEvents = noop,
        SetScript           = noop,
    }
end
function IsSpellKnown() return true end
function IsPlayerSpell() return true end

local HAND_ADDED_ID = 8936
local CDM_HARVESTED_ID = 999001
local SHARED_BASE_ID = 8930
local UNRELATED_ID = 774

local essentialDB = {
    containerType = "cooldown",
    ownedSpells   = {
        { type = "spell", id = HAND_ADDED_ID,    kind = "cooldown", row = 1 },
        { type = "spell", id = UNRELATED_ID,     kind = "cooldown", row = 1 },
        { type = "spell", id = CDM_HARVESTED_ID, kind = "cooldown", row = 1,
          source = "blizzardCDM" },
    },
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    essential = essentialDB,
                },
            },
        },
    },
    Helpers = {
        IsSecretValue            = function() return false end,
        SafeValue                = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
        QueryOverrideSpell = function(spellID)
            if spellID == HAND_ADDED_ID then return CDM_HARVESTED_ID end
            return spellID
        end,
        QueryBaseSpell = function(spellID)
            if spellID == CDM_HARVESTED_ID then return SHARED_BASE_ID end
            return nil
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local list = ns.CDMSpellData:BuildSpellListFromOwned("essential")

local familyCount = 0
local unrelatedCount = 0
for _, entry in ipairs(list) do
    local id = entry.overrideSpellID or entry.spellID
    if id == CDM_HARVESTED_ID or id == HAND_ADDED_ID or id == SHARED_BASE_ID then
        familyCount = familyCount + 1
    elseif id == UNRELATED_ID then
        unrelatedCount = unrelatedCount + 1
    end
end

assert(familyCount == 1,
    "a spell owned under both its hand-added ID and its /cdm override ID must render once, got "
        .. tostring(familyCount))
assert(unrelatedCount == 1,
    "an unrelated spell must still render exactly once, got " .. tostring(unrelatedCount))
assert(#list == 2,
    "the collapsed list must hold exactly the two distinct abilities, got " .. tostring(#list))

local composerSource
do
    local handle = assert(io.open("QUI_CDM/cdm/settings/composer.lua", "rb"))
    composerSource = handle:read("*a")
    handle:close()
end

assert(composerSource:find("spellData.BuildOwnedSet(activeDB)", 1, true),
    "composer must build its ownedSet through the shared CDMSpellData.BuildOwnedSet")
assert(not composerSource:find('ownedSet[(entry.type or "spell")', 1, true),
    "composer must not hand-roll a second ownedSet builder that can drift from the shared one")

print("OK cdm_spelldata_owned_duplicate_family_collapse_test")
