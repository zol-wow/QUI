-- tests/unit/cdm_index_equipslot_test.lua
-- The index must walk EquipSlotTracked (cat 8) so a trinket proc aura resolves
-- to its cooldown entry. Run: lua tests/unit/cdm_index_equipslot_test.lua

_G.wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end end
_G.issecretvalue = function() return false end

_G.Enum = {
    CooldownViewerCategory = {
        Essential = 0,
        Utility = 1,
        TrackedBuff = 2,
        TrackedBar = 3,
        GroupBuff = 4,
        SpecAgnosticEssential = 5,
        SpecAgnosticTracked = 6,
        EquipSlotEssential = 7,
        EquipSlotTracked = 8,
    },
}

_G.C_CooldownViewer = nil
_G.CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end
_G.EventRegistry = { RegisterCallback = function() end }

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
local chunk = loadChunk("QUI_CDM/cdm/cdm_index.lua", "cdm_index.lua")
chunk("QUI", ns)

ns.CDMSources = { QueryBaseSpell = function(spellID) return spellID end }

_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category, includeHidden)
        assert(includeHidden == true, "index should request hidden entries")
        if category == 8 then return { 901 } end  -- EquipSlotTracked
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        assert(cooldownID == 901, "unexpected cooldownID")
        return {
            spellID = 655,                 -- proc aura
            overrideTooltipSpellID = 600,  -- trinket on-use spell
            linkedSpellIDs = { 655 },
        }
    end,
}

local index = assert(ns.CDMIndex, "CDMIndex table was not exported")
index.Rebuild()

local entry = index.Get(655)
assert(entry, "EquipSlotTracked proc aura should be indexed (cat 8 must be walked)")
assert(entry.cooldownID == 901, "wrong cooldownID for trinket proc aura")
assert(entry.primarySpellID == 600, "primary spellID should be the on-use spell")

print("OK cdm_index_equipslot_test")
