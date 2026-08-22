-- tests/unit/cdm_sources_item_quality_variant_test.lua
-- Run: lua tests/unit/cdm_sources_item_quality_variant_test.lua

local counts = {
    [1001] = 0,
    [1002] = 4,
    [1003] = 2,
}

C_Item = {
    GetItemCount = function(itemID)
        return counts[itemID] or 0
    end,
    GetItemCooldown = function(itemID)
        return 400, 30, itemID == 5512 and 1 or 0
    end,
}
local itemCooldownQueries = {}
local containerCooldownAvailable = true
C_Container = {
    GetItemCooldown = function(itemID)
        itemCooldownQueries[#itemCooldownQueries + 1] = itemID
        if containerCooldownAvailable then
            return 300, 60, 1
        end
    end,
}
local categorySourceAvailable = true
local categoryMetadataAvailable = true
local categoryIndexQueries = 0
local categoryMetadataQueries = 0
local indexVersion = 1
C_Spell = {
    GetLastCategoryCooldownSource = function(categoryID)
        if categoryID == 1711 then
            if categorySourceAvailable then return 6262, 5512 end
            return nil, nil
        end
        return nil, nil
    end,
}
local ns = {
    ConsumableMacros = {
        GetVariantOrderForItem = function(itemID)
            if itemID == 1001 or itemID == 1002 or itemID == 1003 then
                return { 1001, 1002, 1003 }
            end
            return nil
        end,
    },
    CDMIndex = {
        Version = function() return indexVersion end,
        GetByCategory = function(categoryID)
            categoryIndexQueries = categoryIndexQueries + 1
            if categoryID == 1711 and categoryMetadataAvailable then
                return { cooldownID = 7001 }
            end
            return nil
        end,
    },
    CDMCatalog = {
        GetCooldownInfo = function(cooldownID)
            categoryMetadataQueries = categoryMetadataQueries + 1
            if cooldownID == 7001 then
                return { spellID = 6262, spellCategoryID = 1711 }
            end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)

local sources = assert(ns.CDMSources, "CDMSources should be exported")

assert(sources.QueryBestOwnedItemVariant(1003) == 1002,
    "existing lower-rank item entries should resolve to the best owned variant in the macro order")

counts[1002] = 0
assert(sources.QueryBestOwnedItemVariant(1003) == 1003,
    "best-variant resolution should fall back to the configured item when no better variant is owned")

assert(sources.QueryBestOwnedItemVariant(2000) == 2000,
    "items outside a known quality family should stay unchanged")
local sourceSpellID, sourceItemID = sources.QueryLastCategoryCooldownSource(1711)
assert(sourceSpellID == 6262 and sourceItemID == 5512,
    "category cooldown source should return the last spell and item")
local categorySourceCache
for index = 1, 20 do
    local name, value = debug.getupvalue(sources.QueryLastCategoryCooldownSource, index)
    if not name then break end
    if name == "_lastCategoryCooldownSources" then
        categorySourceCache = value
        break
    end
end
local cachedSource = assert(categorySourceCache and categorySourceCache[1711])
sourceSpellID, sourceItemID = sources.QueryLastCategoryCooldownSource(1711)
assert(categorySourceCache[1711] == cachedSource,
    "unchanged category cooldown sources should reuse their cache record")
categorySourceAvailable = false
sourceSpellID, sourceItemID = sources.QueryLastCategoryCooldownSource(1711)
assert(sourceSpellID == 6262 and sourceItemID == 5512,
    "category cooldown source should retain the last readable pair when combat values are opaque")
sourceSpellID, sourceItemID = sources.QueryLastCategoryCooldownSource(1711)
assert(categoryMetadataQueries == 1,
    "unchanged category metadata should be queried once")
indexVersion = indexVersion + 1
categoryMetadataAvailable = false
sourceSpellID, sourceItemID = sources.QueryLastCategoryCooldownSource(1711)
assert(sourceSpellID == 6262 and sourceItemID == 5512 and categoryIndexQueries == 2,
    "category metadata cache should invalidate with the CDM index")
sourceSpellID, sourceItemID = sources.QueryLastCategoryCooldownSource(1711)
assert(categoryIndexQueries == 2,
    "missing category metadata should be cached until the CDM index changes")
local startTime, duration, enabled = sources.QueryItemCooldown(5512)
assert(startTime == 300 and duration == 60 and enabled == 1
        and itemCooldownQueries[1] == 5512,
    "item cooldowns should use C_Container's direct item-ID API")
containerCooldownAvailable = false
startTime, duration, enabled = sources.QueryItemCooldown(5512)
assert(startTime == 400 and duration == 30 and enabled == 1,
    "item cooldowns should fall back to C_Item when C_Container returns no tuple")

print("OK: cdm_sources_item_quality_variant_test")
