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

print("OK: cdm_sources_item_quality_variant_test")
