-- tests/unit/cdm_icon_item_visual_policy_test.lua
-- Run: lua tests/unit/cdm_icon_item_visual_policy_test.lua

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_item_visual_policy.lua")("QUI", ns)
local module = assert(ns.CDMIconItemVisualPolicy, "item visual policy module should be exported")

local ncdm = {
    variantItem = {},
    slot = {},
}
local bestOwnedItemID = 1001
local secureUpdates = {}

local controller = module.Create({
    getNCDM = function() return ncdm end,
    getTradeSkillUI = function()
        return {
            GetItemReagentQualityInfo = function(itemID)
                if itemID == 1001 then return { iconInventory = "rank-1-atlas" } end
                if itemID == 1002 then return { iconInventory = "rank-2-atlas" } end
                if itemID == 2001 then return { iconInventory = "slot-atlas" } end
                return nil
            end,
            GetItemCraftedQualityInfo = function()
                return nil
            end,
        }
    end,
    getUseAtlasSize = function() return "use-atlas-size" end,
    resolveBestOwnedItemVariant = function(itemID)
        if itemID == 1001 or itemID == 1002 then
            return bestOwnedItemID
        end
        return itemID
    end,
    queryInventoryItemID = function(unit, slotID)
        if unit == "player" and slotID == 13 then return 2001 end
        return nil
    end,
    queryItemIconByID = function(itemID)
        if itemID == 1001 then return "rank-1-texture" end
        return nil
    end,
    queryItemInfoInstant = function(itemID)
        if itemID == 1002 then return itemID, nil, nil, nil, "rank-2-texture" end
        if itemID == 2001 then return itemID, nil, nil, nil, "slot-texture" end
        return nil
    end,
    updateSecureAttributes = function(icon, entry, viewerType)
        secureUpdates[#secureUpdates + 1] = {
            icon = icon,
            itemID = entry and entry.itemID,
            viewerType = viewerType,
        }
    end,
})

local function createIcon(entry)
    local overlayState = {}
    local textOverlay = {}
    function textOverlay:CreateTexture(name, layer, template, sublevel)
        overlayState.createName = name
        overlayState.createLayer = layer
        overlayState.createTemplate = template
        overlayState.createSublevel = sublevel
        return {
            GetParent = function() return textOverlay end,
            SetPoint = function(_, ...)
                overlayState.point = { ... }
            end,
            SetDrawLayer = function(_, layerName, layerSublevel)
                overlayState.drawLayer = layerName
                overlayState.drawSublevel = layerSublevel
            end,
            SetAtlas = function(_, atlas, useAtlasSize)
                overlayState.atlas = atlas
                overlayState.useAtlasSize = useAtlasSize
            end,
            Show = function()
                overlayState.shown = true
            end,
            Hide = function()
                overlayState.shown = false
            end,
        }
    end

    local textureWrites = {}
    local icon = {
        _spellEntry = entry,
        TextOverlay = textOverlay,
        Icon = {
            SetTexture = function(_, texture)
                textureWrites[#textureWrites + 1] = texture
            end,
        },
    }
    return icon, overlayState, textureWrites
end

local itemEntry = {
    type = "item",
    id = 1001,
    itemID = 1001,
    viewerType = "variantItem",
}
local itemIcon, overlayState, textureWrites = createIcon(itemEntry)

controller:UpdateProfessionQuality(itemIcon)
assert(overlayState.atlas == "rank-1-atlas",
    "profession quality overlay should use the best-owned item atlas")
assert(overlayState.createLayer == "ARTWORK" and overlayState.createSublevel == 1,
    "profession quality overlay should be created on the item visual layer")
assert(overlayState.drawLayer == "ARTWORK" and overlayState.drawSublevel == 1,
    "profession quality overlay should keep its draw layer when reused")
assert(overlayState.useAtlasSize == "use-atlas-size",
    "profession quality overlay should pass atlas sizing policy through")

bestOwnedItemID = 1002
local changed = controller:RefreshItemVisuals(itemIcon, itemEntry, 1002)
assert(changed == true, "item visual refresh should report changed visual state")
assert(textureWrites[#textureWrites] == "rank-2-texture",
    "item visual refresh should update the icon texture")
assert(itemEntry.itemID == 1002,
    "item visual refresh should stamp the active item variant on the entry")
assert(overlayState.atlas == "rank-2-atlas",
    "item visual refresh should update the profession quality overlay")
assert(secureUpdates[1] and secureUpdates[1].itemID == 1002,
    "item visual refresh should notify secure attributes after item variant changes")

local slotEntry = {
    type = "slot",
    id = 13,
    viewerType = "slot",
}
local slotIcon, slotOverlay, slotTextureWrites = createIcon(slotEntry)
controller:RefreshInventoryItemVisuals(slotIcon, slotEntry, 2001)
assert(slotTextureWrites[#slotTextureWrites] == "slot-texture",
    "slot visual refresh should update the inventory item texture")
assert(slotOverlay.atlas == "slot-atlas",
    "slot visual refresh should update the inventory item quality overlay")

ncdm.variantItem.showProfessionQuality = false
controller:UpdateProfessionQuality(itemIcon)
assert(overlayState.shown == false,
    "profession quality overlay should hide when the container disables it")

itemIcon._spellEntry = { type = "spell", viewerType = "variantItem" }
overlayState.shown = true
controller:UpdateProfessionQuality(itemIcon)
assert(overlayState.shown == false,
    "profession quality overlay should hide for non-item-backed entries")

print("OK: cdm_icon_item_visual_policy_test")
