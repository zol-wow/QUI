local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- CDM Sources
--
-- Thin adapters around Blizzard runtime APIs. These functions do not write
-- frames and do not decide visibility; they only return raw source data to
-- resolvers/stores.
---------------------------------------------------------------------------

local CDMSources = {}
ns.CDMSources = CDMSources

local C_Spell = C_Spell
local C_Item = C_Item
local C_UnitAuras = C_UnitAuras

function CDMSources.QuerySpellCharges(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellCharges) then return nil, false end
    local ok, result = pcall(C_Spell.GetSpellCharges, spellID)
    if ok then return result, true end
    return nil, false
end

function CDMSources.QuerySpellCooldown(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, result = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellCooldownDuration(spellID, ignoreGCD)
    if not spellID or not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local ok, result = pcall(C_Spell.GetSpellCooldownDuration, spellID, ignoreGCD and true or false)
    if ok then return result end
    return nil
end

function CDMSources.QueryBaseSpell(spellID)
    if not spellID or not (C_Spell and C_Spell.GetBaseSpell) then return nil end
    local ok, result = pcall(C_Spell.GetBaseSpell, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellBaseCooldown(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellBaseCooldown) then return nil end
    local ok, result = pcall(C_Spell.GetSpellBaseCooldown, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellChargeDuration(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellChargeDuration) then return nil end
    local ok, result = pcall(C_Spell.GetSpellChargeDuration, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QueryOverrideSpell(spellID)
    if not spellID or not (C_Spell and C_Spell.GetOverrideSpell) then return nil end
    local ok, result = pcall(C_Spell.GetOverrideSpell, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellDisplayCount(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellDisplayCount) then return nil end
    local ok, result = pcall(C_Spell.GetSpellDisplayCount, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellCount(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellCount) then return nil end
    local ok, result = pcall(C_Spell.GetSpellCount, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellInfo(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, result = pcall(C_Spell.GetSpellInfo, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellName(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellName) then return nil end
    local ok, result = pcall(C_Spell.GetSpellName, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellTexture(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellTexture) then return nil end
    local ok, result = pcall(C_Spell.GetSpellTexture, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellUsable(spellID)
    if not spellID or not (C_Spell and C_Spell.IsSpellUsable) then return nil, nil end
    local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, spellID)
    if ok then return usable, noMana end
    return nil, nil
end

function CDMSources.QuerySpellInRange(spellID, unit)
    if not spellID or not unit or not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    local ok, result = pcall(C_Spell.IsSpellInRange, spellID, unit)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellHasRange(spellID)
    if not spellID or not (C_Spell and C_Spell.SpellHasRange) then return nil end
    local ok, result = pcall(C_Spell.SpellHasRange, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QuerySpellHarmful(spellNameOrID)
    if not spellNameOrID then return nil end
    if C_Spell and C_Spell.IsSpellHarmful then
        local ok, result = pcall(C_Spell.IsSpellHarmful, spellNameOrID)
        if ok then return result end
    end
    if IsHarmfulSpell then
        local ok, result = pcall(IsHarmfulSpell, spellNameOrID)
        if ok then return result end
    end
    return nil
end

function CDMSources.QuerySpellHelpful(spellNameOrID)
    if not spellNameOrID then return nil end
    if C_Spell and C_Spell.IsSpellHelpful then
        local ok, result = pcall(C_Spell.IsSpellHelpful, spellNameOrID)
        if ok then return result end
    end
    if IsHelpfulSpell then
        local ok, result = pcall(IsHelpfulSpell, spellNameOrID)
        if ok then return result end
    end
    return nil
end

function CDMSources.QueryItemInfoInstant(itemID)
    if not itemID or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, a, b, c, d, e, f, g = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok then return a, b, c, d, e, f, g end
    return nil
end

function CDMSources.QueryItemIconByID(itemID)
    if not itemID or not (C_Item and C_Item.GetItemIconByID) then return nil end
    local ok, result = pcall(C_Item.GetItemIconByID, itemID)
    if ok then return result end
    return nil
end

function CDMSources.QueryItemNameByID(itemID)
    if not itemID or not (C_Item and C_Item.GetItemNameByID) then return nil end
    local ok, result = pcall(C_Item.GetItemNameByID, itemID)
    if ok then return result end
    return nil
end

function CDMSources.QueryItemSpell(itemID)
    if not itemID or not (C_Item and C_Item.GetItemSpell) then return nil, nil end
    local ok, name, spellID = pcall(C_Item.GetItemSpell, itemID)
    if ok then return name, spellID end
    return nil, nil
end

function CDMSources.QueryItemQualityByID(itemID)
    if not itemID or not (C_Item and C_Item.GetItemQualityByID) then return nil end
    local ok, result = pcall(C_Item.GetItemQualityByID, itemID)
    if ok then return result end
    return nil
end

function CDMSources.QueryFirstTriggeredSpellForItem(itemID, itemQuality)
    if not itemID or not (C_Item and C_Item.GetFirstTriggeredSpellForItem) then return nil end
    local ok, spellID
    if itemQuality ~= nil then
        ok, spellID = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID, itemQuality)
    else
        ok, spellID = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID)
    end
    if ok then return spellID end
    return nil
end

function CDMSources.QueryIsEquippedItem(itemID)
    if not itemID or not (C_Item and C_Item.IsEquippedItem) then return nil end
    local ok, result = pcall(C_Item.IsEquippedItem, itemID)
    if ok then return result end
    return nil
end

function CDMSources.QueryInventoryItemID(unit, slotID)
    if not unit or not slotID or not GetInventoryItemID then return nil end
    local ok, result = pcall(GetInventoryItemID, unit, slotID)
    if ok then return result end
    return nil
end

function CDMSources.QueryInventoryItemLink(unit, slotID)
    if not unit or not slotID or not GetInventoryItemLink then return nil end
    local ok, result = pcall(GetInventoryItemLink, unit, slotID)
    if ok then return result end
    return nil
end

function CDMSources.QueryInventoryItemTexture(unit, slotID)
    if not unit or not slotID or not GetInventoryItemTexture then return nil end
    local ok, result = pcall(GetInventoryItemTexture, unit, slotID)
    if ok then return result end
    return nil
end

function CDMSources.QueryItemCount(itemID, includeBank, includeUses, forceUpdate)
    if not itemID or not (C_Item and C_Item.GetItemCount) then return nil end
    local ok, result = pcall(C_Item.GetItemCount, itemID, includeBank, includeUses, forceUpdate)
    if ok then return result end
    return nil
end

function CDMSources.QueryItemCooldown(itemID)
    if not itemID or not (C_Item and C_Item.GetItemCooldown) then return nil end
    local ok, startTime, duration, enabled = pcall(C_Item.GetItemCooldown, itemID)
    if ok then return startTime, duration, enabled end
    return nil
end

function CDMSources.QueryAuraDuration(unit, auraInstanceID)
    if not unit or not auraInstanceID or not (C_UnitAuras and C_UnitAuras.GetAuraDuration) then return nil end
    local ok, result = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
    if ok then return result end
    return nil
end

function CDMSources.QueryAuraDataByAuraInstanceID(unit, auraInstanceID)
    if not unit or not auraInstanceID or not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then return nil end
    local ok, result = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if ok then return result end
    return nil
end

function CDMSources.QueryAuraHasExpirationTime(unit, auraInstanceID)
    if not unit or not auraInstanceID or not (C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime) then return nil end
    local ok, result = pcall(C_UnitAuras.DoesAuraHaveExpirationTime, unit, auraInstanceID)
    if ok then return result end
    return nil
end

function CDMSources.QueryAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if not unit or not auraInstanceID or not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then return nil end
    local ok, result = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, auraInstanceID, filter)
    if ok then return result end
    return nil
end

function CDMSources.QueryAuraApplicationDisplayCount(unit, auraInstanceID, minValue, maxValue)
    if not unit or not auraInstanceID or not (C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount) then return nil end
    local ok, result = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, minValue, maxValue)
    if ok then return result end
    return nil
end

function CDMSources.QueryUnitAuraBySpellID(unit, spellID, filter)
    if not unit or not spellID or not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then return nil end
    local ok, result = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID, filter)
    if ok then return result end
    return nil
end

function CDMSources.QueryPlayerAuraBySpellID(spellID)
    if not spellID or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QueryAuraDataBySpellID(unit, spellID, filter)
    if not unit or not spellID or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID) then return nil end
    local ok, result = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, spellID, filter)
    if ok then return result end
    return nil
end

function CDMSources.QueryCooldownAuraBySpellID(spellID)
    if not spellID or not (C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID) then return nil end
    local ok, result = pcall(C_UnitAuras.GetCooldownAuraBySpellID, spellID)
    if ok then return result end
    return nil
end

function CDMSources.QueryAuraDataBySpellName(unit, name, filter)
    if not unit or not name or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
    local ok, result = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
    if ok then return result end
    return nil
end

function CDMSources.QueryUnitAuras(unit, filter, maxCount)
    if not unit or not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return nil end
    local ok, result = pcall(C_UnitAuras.GetUnitAuras, unit, filter, maxCount)
    if ok then return result end
    return nil
end

function CDMSources.QueryMirroredCooldownState(spellID, viewerType)
    local mirror = ns.CDMBlizzMirror
    if not mirror or not spellID then return nil end
    if (viewerType == "essential" or viewerType == "utility")
       and mirror.GetMirroredStateForViewer then
        return mirror.GetMirroredStateForViewer(spellID, viewerType)
    end
    if mirror.FindCooldownState then
        return mirror.FindCooldownState(spellID)
    end
    return nil
end
