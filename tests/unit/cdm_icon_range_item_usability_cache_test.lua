local function wipeTable(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

wipe = wipeTable
UnitExists = function() return false end

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_policies.lua", "cdm_icon_range_policy.lua")("QUI", ns)

local spellQueries = 0
local itemQueries = 0
local controller = assert(ns.CDMIconRangePolicy).Create({
    resolveSettings = function()
        return { usabilityIndicator = true }
    end,
    querySpellUsable = function()
        spellQueries = spellQueries + 1
        return true, false
    end,
    queryItemUsable = function()
        itemQueries = itemQueries + 1
        return true, false
    end,
    getItemIDForEntry = function() return 5512 end,
})

local function icon(entry)
    return {
        _spellEntry = entry,
        Icon = { SetVertexColor = function() end },
    }
end

controller:UpdateAllIconRanges({
    essential = {
        icon({ id = 5512, spellID = 5512, type = "spell", viewerType = "essential" }),
        icon({ id = 1711, type = "consumable", viewerType = "essential" }),
    },
})

assert(spellQueries == 1 and itemQueries == 1)
assert(controller.usableCycleCache[5512] == true)
assert(controller.itemUsableCycleCache[5512] == true)
assert(controller.usableCycleCache["item:5512"] == nil)

print("OK: cdm_icon_range_item_usability_cache_test")
