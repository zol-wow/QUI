-- tests/unit/cdm_catalog_proc_override_identity_test.lua
-- Run: lua tests/unit/cdm_catalog_proc_override_identity_test.lua
--
-- Regression for the Paladin "Wake of Ashes disappears on proc" report.
--
-- Hammer of Light (a TRANSIENT proc override) overrides Wake of Ashes' cooldown
-- slot while the proc is live (info.overrideSpellID flips to Hammer of Light).
-- The base ability stays independently learned. The catalog must key PERSISTENT
-- identity (learned-cooldown set, seed entries, the add picker) off the base
-- spellID, not the live override -- otherwise the base drops out of the learned
-- set every proc (its icon goes dormant) and the proc spell surfaces as an
-- "unlearned" phantom entry.
--
-- Contrast: a PERMANENT talent override converts the base away (base no longer
-- known), so the override id IS the surviving identity -- that path must be
-- preserved.

_G.issecretvalue = function() return false end
_G.C_CooldownViewer = nil

local WAKE_OF_ASHES   = 255647  -- base, independently learned
local HAMMER_OF_LIGHT = 427453  -- transient proc override of Wake of Ashes
local CONV_BASE       = 111     -- talent-converted-away base (not known)
local CONV_OVERRIDE   = 222     -- the override the talent grants (known)

local ns = {}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
local chunk = loadChunk("QUI_CDM/cdm/cdm_catalog.lua", "cdm_catalog.lua")
chunk("QUI", ns)

ns.CDMSources = {
    QuerySpellInfo = function(spellID)
        local names = {
            [WAKE_OF_ASHES]   = "Wake of Ashes",
            [HAMMER_OF_LIGHT] = "Hammer of Light",
            [CONV_OVERRIDE]   = "Converted Ability",
        }
        if names[spellID] then
            return { name = names[spellID], iconID = spellID }
        end
        return nil
    end,
    QueryOverrideSpell = function(spellID) return spellID end,
    QueryIsSpellKnownOrPlayerSpell = function(spellID)
        return spellID == WAKE_OF_ASHES or spellID == CONV_OVERRIDE
    end,
}

-- cooldownID 1001 = Wake of Ashes slot mid-proc (override live).
-- cooldownID 1002 = a talent-converted slot (base gone, override is the slot).
_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then return { 1001, 1002 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 1001 then
            return {
                spellID = WAKE_OF_ASHES,
                overrideSpellID = HAMMER_OF_LIGHT,  -- proc live
                overrideTooltipSpellID = nil,
                linkedSpellIDs = {},
                isKnown = true,
            }
        elseif cooldownID == 1002 then
            return {
                spellID = CONV_BASE,
                overrideSpellID = CONV_OVERRIDE,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = {},
                isKnown = true,
            }
        end
        return nil
    end,
}

local catalog = assert(ns.CDMCatalog, "CDMCatalog table was not exported")

-- 1) Learned-cooldown set: the proc override must NOT evict the still-learned
--    base; the converted slot resolves to its override.
local learned = {}
assert(catalog.RebuildCooldownLearnedPreferredIDs(learned),
    "RebuildCooldownLearnedPreferredIDs should report success")
assert(learned[WAKE_OF_ASHES] == true,
    "Wake of Ashes (still-learned base) must stay in the learned set during a proc")
assert(learned[HAMMER_OF_LIGHT] == nil,
    "the transient proc override must NOT take the learned-set slot from its base")
assert(learned[CONV_OVERRIDE] == true,
    "a talent-converted slot (base no longer known) must contribute its override id")
assert(learned[CONV_BASE] == nil,
    "the converted-away base (no longer known) must not be in the learned set")

-- 2) Add picker: entry identity is the base, not the proc override.
local available = catalog.GetAvailableSpellsForContainer("essential", "cooldown", {}, {})
local availBySpell = {}
for _, e in ipairs(available) do availBySpell[e.spellID] = e end
assert(availBySpell[WAKE_OF_ASHES], "Wake of Ashes must be offered by its base id")
assert(availBySpell[HAMMER_OF_LIGHT] == nil,
    "the proc override must not surface as a separate addable phantom entry")
assert(availBySpell[CONV_OVERRIDE], "the converted slot must be offered by its override id")

-- 3) Snapshot seed: same identity rule.
_G.CooldownViewerSettings = {
    GetDataProvider = function()
        return {
            GetLayoutManager = function() return {} end,
            GetOrderedCooldownIDsForCategory = function(_, category)
                if category == 0 then return { 1001, 1002 } end
                return {}
            end,
        }
    end,
}
local seeded, ready = catalog.SeedFromBlizzard("essential")
assert(ready == true, "seed should report ready")
local seededSet = {}
for _, e in ipairs(seeded) do seededSet[e.id] = true end
assert(seededSet[WAKE_OF_ASHES], "seed must persist Wake of Ashes by its base id")
assert(seededSet[HAMMER_OF_LIGHT] == nil,
    "seed must not persist the transient proc override as the slot identity")
assert(seededSet[CONV_OVERRIDE], "seed must persist the converted slot by its override id")

print("OK: cdm_catalog_proc_override_identity_test")
