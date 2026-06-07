-- tests/unit/cdm_spelldata_usable_items_quality_order_test.lua
-- Run: lua tests/unit/cdm_spelldata_usable_items_quality_order_test.lua

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
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

local bagItems = {
    [1] = {
        itemID = 1001,
        itemName = "Test Potion",
        iconFileID = 10001,
        hyperlink = "item:1001",
    },
    [2] = {
        itemID = 1002,
        itemName = "Test Potion",
        iconFileID = 10002,
        hyperlink = "item:1002",
    },
    [3] = {
        itemID = 1003,
        itemName = "Unranked Gadget",
        iconFileID = 10003,
        hyperlink = "item:1003",
    },
}

C_Container = {
    GetContainerNumSlots = function(bag)
        return bag == 0 and #bagItems or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        if bag ~= 0 then return nil end
        return bagItems[slot]
    end,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
        QueryInventoryItemID = function() return nil end,
        QueryItemSpell = function(itemID)
            if itemID == 1001 or itemID == 1002 or itemID == 1003 then
                return "Usable Item", 9000 + itemID
            end
            return nil
        end,
        QueryItemProfessionQualityInfo = function(itemInfo)
            if itemInfo == "item:1001" then return { quality = 1 } end
            if itemInfo == "item:1002" then return { quality = 3 } end
            return nil
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local items = ns.CDMSpellData:GetUsableItems()
assert(#items == 3, "bag scan should return all usable item candidates")
assert(items[1].itemID == 1002, "highest profession-quality bag item should be listed first")
assert(items[2].itemID == 1001, "lower profession-quality variant should follow the higher-quality item")
assert(items[3].itemID == 1003, "unranked items should keep their relative bag order after ranked items")
assert(items[1]._professionQualityRank == nil and items[1]._bagOrder == nil,
    "temporary quality-sort metadata should not leak through GetUsableItems")

print("OK: cdm_spelldata_usable_items_quality_order_test")
