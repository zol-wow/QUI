-- tests/unit/cdm_sources_scanned_item_aura_test.lua
-- Run: lua tests/unit/cdm_sources_scanned_item_aura_test.lua

local scanner = {}
local registered = {}
local secretAuraInstanceID = { token = "source-secret-aura-instance" }
local durationObject = { token = "duration-object" }
local durationQueries = {}
local itemInfo = {
    [2001] = {
        useSpellID = 9002,
        buffSpellID = 8002,
        duration = 30,
        icon = 123,
        name = "Variant Aura",
        scannedAt = 1,
    },
}
local spellInfo = {
    [9003] = {
        buffSpellID = 8003,
        duration = 20,
        icon = 456,
        name = "Spell Aura",
        scannedAt = 2,
    },
}

function scanner.GetScannedItemInfo(itemID)
    return itemInfo[itemID]
end

function scanner.GetScannedSpellInfo(spellID)
    return spellInfo[spellID]
end

function scanner.IsItemActive(itemID)
    if itemID == 2001 then
        return true, 150, 30
    end
    return false
end

function scanner.IsSpellActive(spellID)
    if spellID == 9003 then
        return true, 180, 20
    end
    return false
end

function scanner.RegisterItemUseSpell(itemID, useSpellID)
    registered[#registered + 1] = { itemID = itemID, useSpellID = useSpellID }
    return true
end

function issecretvalue(value) return value == secretAuraInstanceID end

_G.QUI = { SpellScanner = scanner }

C_Item = {
    GetItemSpell = function(itemID)
        if itemID == 2002 then
            return "Use Variant", 9002
        end
        return nil, nil
    end,
}

C_UnitAuras = {
    GetAuraDuration = function(unit, auraInstanceID)
        durationQueries[#durationQueries + 1] = {
            unit = unit,
            auraInstanceID = auraInstanceID,
        }
        if unit == "player" and auraInstanceID == secretAuraInstanceID then
            return durationObject
        end
        return nil
    end,
}

local ns = {
    ConsumableMacros = {
        GetVariantOrderForItem = function(itemID)
            if itemID == 2002 then
                return { 2003, 2002, 2001 }
            end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)

local sources = assert(ns.CDMSources, "CDMSources should be exported")

local info = sources.QueryScannedItemAuraInfo(2002)
assert(info, "variant item should resolve scanned aura info")
assert(info.source == "item", "variant item should preserve item scanner source")
assert(info.sourceItemID == 2001, "variant item should use scanned source variant")
assert(info.useSpellID == 9002, "variant item should carry use spell")
assert(info.buffSpellID == 8002, "variant item should carry buff spell")
assert(info.active == true, "variant item should report active scanner state")
assert(info.expiration == 150 and info.duration == 30, "variant item should carry active timing")
assert(registered[1].itemID == 2002 and registered[1].useSpellID == 9002,
    "scanned item aura query should register tracked item use spell")

info = sources.QueryScannedItemAuraInfo(3001, 9003)
assert(info, "item should fall back to scanned spell info")
assert(info.source == "spell", "spell fallback should identify spell scanner source")
assert(info.sourceItemID == 3001, "spell fallback should keep requested item ID")
assert(info.sourceSpellID == 9003, "spell fallback should keep use spell ID")
assert(info.buffSpellID == 8003, "spell fallback should carry buff spell")
assert(info.active == true, "spell fallback should report active scanner state")
assert(info.expiration == 180 and info.duration == 20, "spell fallback should carry active timing")
assert(registered[2].itemID == 3001 and registered[2].useSpellID == 9003,
    "spell fallback query should register tracked item use spell")

local queriedDuration = sources.QueryAuraDuration("player", secretAuraInstanceID)
assert(queriedDuration == durationObject, "secret aura instance IDs should pass through to duration query")
assert(durationQueries[1].auraInstanceID == secretAuraInstanceID,
    "duration query should preserve secret aura instance identity")

print("OK: cdm_sources_scanned_item_aura_test")
