local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Item Visual Policy
--
-- Private renderer policy used by CDMIcons. It owns item texture refreshes
-- and profession-quality overlays for item, trinket, and slot icons.
---------------------------------------------------------------------------

local CDMIconItemVisualPolicy = {}
ns.CDMIconItemVisualPolicy = CDMIconItemVisualPolicy

local PROFESSION_QUALITY_DRAW_LAYER = "ARTWORK"
local PROFESSION_QUALITY_DRAW_SUBLEVEL = 1

local function isItemBackedEntry(entry)
    local entryType = entry and entry.type
    return entryType == "item" or entryType == "trinket" or entryType == "slot"
end

function CDMIconItemVisualPolicy.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    local function getTradeSkillUI()
        if callbacks.getTradeSkillUI then
            return callbacks.getTradeSkillUI()
        end
        return C_TradeSkillUI
    end

    local function getNCDM()
        return callbacks.getNCDM and callbacks.getNCDM() or nil
    end

    local function getUseAtlasSize()
        if callbacks.getUseAtlasSize then
            return callbacks.getUseAtlasSize()
        end
        return (TextureKitConstants and TextureKitConstants.UseAtlasSize) or true
    end

    local function resolveBestOwnedItemVariant(itemID)
        if callbacks.resolveBestOwnedItemVariant then
            return callbacks.resolveBestOwnedItemVariant(itemID)
        end
        return itemID
    end

    local function getProfessionQualityInfoForItem(itemIDOrLink)
        local tradeSkillUI = getTradeSkillUI()
        if not itemIDOrLink or not tradeSkillUI then return nil end
        if tradeSkillUI.GetItemReagentQualityInfo then
            local info = tradeSkillUI.GetItemReagentQualityInfo(itemIDOrLink)
            if info then return info end
        end
        if tradeSkillUI.GetItemCraftedQualityInfo then
            return tradeSkillUI.GetItemCraftedQualityInfo(itemIDOrLink)
        end
        return nil
    end

    local function getProfessionQualityParent(icon)
        if icon and icon.TextOverlay and icon.TextOverlay.CreateTexture then
            return icon.TextOverlay
        end
        return icon
    end

    function controller:GetItemTexture(itemID)
        if not itemID then return nil end
        local texture = callbacks.queryItemIconByID and callbacks.queryItemIconByID(itemID)
        if not texture and callbacks.queryItemInfoInstant then
            local _, _, _, _, instantTexture = callbacks.queryItemInfoInstant(itemID)
            texture = instantTexture
        end
        return texture
    end

    function controller:ClearProfessionQuality(icon)
        if icon and icon._professionQualityOverlay then
            icon._professionQualityOverlay:Hide()
        end
    end

    function controller:UpdateProfessionQuality(icon)
        if not (icon and icon._spellEntry) then
            controller:ClearProfessionQuality(icon)
            return
        end

        local entry = icon._spellEntry
        local entryType = entry.type
        if not isItemBackedEntry(entry) then
            controller:ClearProfessionQuality(icon)
            return
        end

        local ncdm = getNCDM()
        local viewerType = entry.viewerType
        local containerDB = ncdm and viewerType
            and (ncdm[viewerType] or (ncdm.containers and ncdm.containers[viewerType]))
        if containerDB and containerDB.showProfessionQuality == false then
            controller:ClearProfessionQuality(icon)
            return
        end

        local lookupID
        if entryType == "item" then
            lookupID = resolveBestOwnedItemVariant(entry.id)
        else
            if callbacks.queryInventoryItemLink then
                lookupID = callbacks.queryInventoryItemLink("player", entry.id)
            end
            if not lookupID and callbacks.queryInventoryItemID then
                lookupID = callbacks.queryInventoryItemID("player", entry.id)
            end
        end

        local qualityInfo = lookupID and getProfessionQualityInfoForItem(lookupID)
        local atlas = qualityInfo and qualityInfo.iconInventory
        if not atlas then
            controller:ClearProfessionQuality(icon)
            return
        end

        local overlayParent = getProfessionQualityParent(icon)
        if not (overlayParent and overlayParent.CreateTexture) then
            controller:ClearProfessionQuality(icon)
            return
        end

        local overlay = icon._professionQualityOverlay
        if overlay and overlay.GetParent and overlay:GetParent() ~= overlayParent then
            overlay:Hide()
            overlay = nil
            icon._professionQualityOverlay = nil
        end
        if not overlay then
            overlay = overlayParent:CreateTexture(
                nil, PROFESSION_QUALITY_DRAW_LAYER, nil, PROFESSION_QUALITY_DRAW_SUBLEVEL)
            overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 2)
            icon._professionQualityOverlay = overlay
        end
        if overlay.SetDrawLayer then
            overlay:SetDrawLayer(PROFESSION_QUALITY_DRAW_LAYER, PROFESSION_QUALITY_DRAW_SUBLEVEL)
        end
        overlay:SetAtlas(atlas, getUseAtlasSize())
        overlay:Show()
    end

    function controller:RefreshInventoryItemVisuals(icon, entry, itemID)
        if not (icon and entry and itemID and icon.Icon) then return false end
        local texture = controller:GetItemTexture(itemID)
        if texture and texture ~= icon._lastTexture then
            icon.Icon:SetTexture(texture)
            icon._lastTexture = texture
            controller:UpdateProfessionQuality(icon)
            return true
        end
        return false
    end

    function controller:RefreshItemVisuals(icon, entry, itemID)
        if not (icon and entry and itemID) then return false end

        local changed = false
        if icon._lastItemVisualItemID ~= itemID then
            icon._lastItemVisualItemID = itemID
            changed = true
        end

        if icon.Icon then
            local texture = controller:GetItemTexture(itemID)
            if texture and texture ~= icon._lastTexture then
                icon.Icon:SetTexture(texture)
                icon._lastTexture = texture
                changed = true
            end
        end

        if changed then
            entry.itemID = itemID
            controller:UpdateProfessionQuality(icon)
            if callbacks.updateSecureAttributes then
                callbacks.updateSecureAttributes(icon, entry, entry.viewerType)
            end
        end

        return changed
    end

    return controller
end
