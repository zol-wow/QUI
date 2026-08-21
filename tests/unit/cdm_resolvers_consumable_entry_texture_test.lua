-- tests/unit/cdm_resolvers_consumable_entry_texture_test.lua
-- Consumable entries (type="consumable", id = spell CATEGORY id: 4 combat pot,
-- 30 health pot, 1711 healthstone) must resolve to the Blizzard category icon
-- (CooldownViewerItemData.lua spellCategoryMetadataLookup), NOT fall through to
-- GetSpellTexture(categoryID) which returns nil and leaves composer preview
-- icons blank.
-- Run: lua tests/unit/cdm_resolvers_consumable_entry_texture_test.lua

local function noop() end

function issecretvalue() return false end
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
        SetScript = noop,
    }
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    CDMShared = {
        IsSafeNumeric = function(value)
            return type(value) == "number"
        end,
        SafeBoolean = function(value)
            if type(value) == "boolean" then return value end
            return nil
        end,
    },
    CDMSources = {
        -- Consumable resolution must never hit the spell texture path:
        -- entry.id is a category id, not a spellID.
        QuerySpellTexture = function()
            error("consumable entry must not resolve through spell texture queries")
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_catalog.lua", "cdm_catalog.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_runtime_store.lua", "cdm_runtime_store.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local catalog = assert(ns.CDMCatalog, "CDMCatalog should be exported")
local resolvers = assert(ns.CDMResolvers, "CDMResolvers should be exported")

-- Catalog exposes the consumable category meta (icon strings mirror Blizzard's
-- spellCategoryMetadataLookup so the preview matches the native frame render).
assert(type(catalog.GetConsumableCategoryMeta) == "function",
    "CDMCatalog.GetConsumableCategoryMeta should be exported")

local combatPot = catalog.GetConsumableCategoryMeta(4)
assert(combatPot and combatPot.icon == "Interface/ICONS/INV_POTION_114",
    "combat potion icon must match Blizzard's spellCategoryMetadataLookup")
local healthPot = catalog.GetConsumableCategoryMeta(30)
assert(healthPot and healthPot.icon == "Interface/ICONS/INV_POTION_54",
    "health potion icon must match Blizzard's spellCategoryMetadataLookup")
local healthstone = catalog.GetConsumableCategoryMeta(1711)
assert(healthstone and healthstone.icon == "Interface/ICONS/Warlock_ Healthstone",
    "healthstone icon must match Blizzard's spellCategoryMetadataLookup")
local demonicHealthstone = catalog.GetConsumableCategoryMeta(2566)
assert(demonicHealthstone and demonicHealthstone.icon == "Interface/ICONS/Warlock_ Bloodstone",
    "demonic healthstone icon must match Blizzard's spellCategoryMetadataLookup")
assert(catalog.GetConsumableCategoryMeta(9999) == nil, "unknown category returns nil")

-- GetEntryTexture routes consumable entries through the category meta.
for _, catID in ipairs({ 4, 30, 1711, 2566 }) do
    local entry = { type = "consumable", id = catID }
    local tex = resolvers.GetEntryTexture(entry)
    local meta = catalog.GetConsumableCategoryMeta(catID)
    assert(tex == meta.icon, string.format(
        "GetEntryTexture must return category icon for catID %d (got %s)",
        catID, tostring(tex)))
end

-- Unknown consumable category: nil, never a spell lookup on the category id.
assert(resolvers.GetEntryTexture({ type = "consumable", id = 9999 }) == nil,
    "unknown consumable category resolves to nil")

print("OK cdm_resolvers_consumable_entry_texture_test")
