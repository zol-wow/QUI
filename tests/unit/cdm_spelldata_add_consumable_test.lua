-- tests/unit/cdm_spelldata_add_consumable_test.lua
-- AddConsumable stores a {type="consumable", id=categoryID} entry on the container.
-- Run: lua5.1 tests/unit/cdm_spelldata_add_consumable_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame
local function noop() end
function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function CreateFrame()
    return { RegisterEvent = noop, RegisterUnitEvent = noop, UnregisterEvent = noop,
             UnregisterAllEvents = noop, SetScript = noop }
end

-- Bootstrap mirrors cdm_spelldata_available_owned_item_keys_test.lua:
-- inject container DB via ns.Addon.db.profile.ncdm so GetContainerDB resolves.
local containerDB = { containerType = "cooldown", ownedSpells = {} }
local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    essential = containerDB,
                },
            },
        },
    },
    Helpers = {
        IsSecretValue           = function() return false end,
        SafeValue               = function(v) return v end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        GetBuiltinContainerEntryKind = function(k)
            return ({ essential = "cooldown", utility = "cooldown", buff = "aura", trackedBar = "aura" })[k]
        end,
    },
    CDMSources = {
        QueryOverrideSpell = function(spellID) return spellID end,
        QueryBaseSpell     = function() return nil end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local SpellData = assert(ns.CDMSpellData, "CDMSpellData not exported")
assert(type(SpellData.AddConsumable) == "function", "AddConsumable must exist")

SpellData:AddConsumable("essential", 4, 1, "cooldown", "blizzardCDM")

local owned = containerDB.ownedSpells
assert(#owned == 1, "one entry added, got " .. #owned)
assert(owned[1].type == "consumable", "type must be 'consumable'")
assert(owned[1].id == 4, "id must be the spellCategoryID")
assert(owned[1].kind == "cooldown", "kind carried")
assert(owned[1].source == "blizzardCDM", "consumable source provenance carried")

SpellData:AddTrinketSlot("essential", 13, 2, "cooldown", "blizzardCDM")

assert(#owned == 2, "trinket slot entry added, got " .. #owned)
assert(owned[2].type == "slot", "type must be 'slot'")
assert(owned[2].id == 13, "id must be the inventory slot")
assert(owned[2].kind == "cooldown", "slot kind carried")
assert(owned[2].row == 2, "slot row carried")
assert(owned[2].source == "blizzardCDM", "slot source provenance carried")

print("OK cdm_spelldata_add_consumable_test")
