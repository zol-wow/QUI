local _, ns = ...

local CDMSources = {}
ns.CDMSources = CDMSources

local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Item = C_Item
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local WoW_IsSecretValue = issecretvalue

local wipe = wipe or function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local function HasOpaqueValue(value)
    if WoW_IsSecretValue and WoW_IsSecretValue(value) then
        return false -- @secret-policy: reject-secret-ids
    end
    if value == nil then return false end
    return true
end

local _C_ShouldAurasBeSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret

function CDMSources.AreAurasSecret()
    if not _C_ShouldAurasBeSecret then return false end
    return _C_ShouldAurasBeSecret() == true
end
local AreAurasSecret = CDMSources.AreAurasSecret

local _C_GetSpellCharges = C_Spell and C_Spell.GetSpellCharges
local _C_GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local _C_GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local _C_GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
local _C_GetSpellBaseCooldown = C_Spell and C_Spell.GetSpellBaseCooldown
local _C_GetSpellChargeDuration = C_Spell and C_Spell.GetSpellChargeDuration
local _C_GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
local _C_GetSpellDisplayCount = C_Spell and C_Spell.GetSpellDisplayCount
local _C_GetSpellCastCount = C_Spell and C_Spell.GetSpellCastCount
local _C_GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
local _C_GetSpellName = C_Spell and C_Spell.GetSpellName
local _C_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local _C_IsSpellUsable = C_Spell and C_Spell.IsSpellUsable
local _C_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local _C_SpellHasRange = C_Spell and C_Spell.SpellHasRange
local _C_FindSpellBookSlotForSpell = C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell
local _C_GetNumSpellBookSkillLines = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines

function CDMSources.QuerySpellCharges(spellID)
    if not spellID or not _C_GetSpellCharges then return nil, false end
    return _C_GetSpellCharges(spellID), true
end

function CDMSources.QuerySpellCooldown(spellID)
    if not spellID or not _C_GetSpellCooldown then return nil end
    return _C_GetSpellCooldown(spellID)
end

function CDMSources.QuerySpellCooldownDuration(spellID, ignoreGCD)
    if not spellID or not _C_GetSpellCooldownDuration then return nil end
    return _C_GetSpellCooldownDuration(spellID, ignoreGCD and true or false)
end

function CDMSources.QueryBaseSpell(spellID)
    if not spellID or not _C_GetBaseSpell then return nil end
    return _C_GetBaseSpell(spellID)
end

function CDMSources.QuerySpellBaseCooldown(spellID)
    if not spellID or not _C_GetSpellBaseCooldown then return nil end
    return _C_GetSpellBaseCooldown(spellID)
end

function CDMSources.QuerySpellChargeDuration(spellID)
    if not spellID or not _C_GetSpellChargeDuration then return nil end
    return _C_GetSpellChargeDuration(spellID)
end

function CDMSources.QueryOverrideSpell(spellID)
    if not spellID or not _C_GetOverrideSpell then return nil end
    return _C_GetOverrideSpell(spellID)
end

local _IsSpellKnown = IsSpellKnown
local _IsPlayerSpell = IsPlayerSpell
function CDMSources.QueryIsSpellKnownOrPlayerSpell(spellID)
    if not spellID then return false end
    if _IsSpellKnown and _IsSpellKnown(spellID) then return true end
    if _IsPlayerSpell and _IsPlayerSpell(spellID) then return true end
    return false
end

function CDMSources.QuerySpellBookClassAffinity(spellID)
    if WoW_IsSecretValue and WoW_IsSecretValue(spellID) then
        return false -- @secret-policy: reject-secret-ids
    end
    if spellID == nil or not _C_FindSpellBookSlotForSpell then return nil end
    if _C_GetNumSpellBookSkillLines and _C_GetNumSpellBookSkillLines() == 0 then
        return nil
    end
    local includeHidden = true
    local includeFlyouts = true
    local includeFutureSpells = true
    local includeOffSpec = true
    local slotIndex = _C_FindSpellBookSlotForSpell(
        spellID, includeHidden, includeFlyouts, includeFutureSpells, includeOffSpec)
    return slotIndex ~= nil
end

function CDMSources.QuerySpellDisplayCount(spellID)
    if not spellID or not _C_GetSpellDisplayCount then return nil end
    return _C_GetSpellDisplayCount(spellID)
end

function CDMSources.QuerySpellCount(spellID)
    if not spellID or not _C_GetSpellCastCount then return nil end
    return _C_GetSpellCastCount(spellID)
end

function CDMSources.QuerySpellInfo(spellID)
    if not spellID or not _C_GetSpellInfo then return nil end
    return _C_GetSpellInfo(spellID)
end

function CDMSources.QuerySpellName(spellID)
    if not spellID or not _C_GetSpellName then return nil end
    return _C_GetSpellName(spellID)
end

function CDMSources.QuerySpellTexture(spellID)
    if not spellID or not _C_GetSpellTexture then return nil end
    return _C_GetSpellTexture(spellID)
end

function CDMSources.QuerySpellUsable(spellID)
    if not spellID or not _C_IsSpellUsable then return nil, nil end
    return _C_IsSpellUsable(spellID)
end

function CDMSources.QuerySpellInRange(spellID, unit)
    if not spellID or not unit or not _C_IsSpellInRange then return nil end
    return _C_IsSpellInRange(spellID, unit)
end

function CDMSources.QuerySpellHasRange(spellID)
    if not spellID or not _C_SpellHasRange then return nil end
    return _C_SpellHasRange(spellID)
end

function CDMSources.EnableSpellRangeCheck(spellID, enable)
    if not spellID or not (C_Spell and C_Spell.EnableSpellRangeCheck) then return false end
    local ok = ns.SafeCall("best-effort-style", C_Spell.EnableSpellRangeCheck, spellID, enable == true)
    return ok == true
end

local function querySpellAffinity(spellNameOrID, namespacedFn, globalFn)
    if not spellNameOrID then return nil end
    if namespacedFn then
        local ok, result = ns.SafeCall("compat", namespacedFn, spellNameOrID)
        if ok then return result end
    end
    if globalFn then
        local ok, result = ns.SafeCall("compat", globalFn, spellNameOrID)
        if ok then return result end
    end
    return nil
end

function CDMSources.QuerySpellHarmful(spellNameOrID)
    return querySpellAffinity(spellNameOrID,
        C_Spell and C_Spell.IsSpellHarmful, IsHarmfulSpell)
end

function CDMSources.QuerySpellHelpful(spellNameOrID)
    return querySpellAffinity(spellNameOrID,
        C_Spell and C_Spell.IsSpellHelpful, IsHelpfulSpell)
end

local _C_GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
local _C_GetItemIconByID = C_Item and C_Item.GetItemIconByID
local _C_GetItemNameByID = C_Item and C_Item.GetItemNameByID
local _C_GetItemSpell = C_Item and C_Item.GetItemSpell
local _C_GetItemQualityByID = C_Item and C_Item.GetItemQualityByID

function CDMSources.QueryItemInfoInstant(itemID)
    if not itemID or not _C_GetItemInfoInstant then return nil end
    return _C_GetItemInfoInstant(itemID)
end

function CDMSources.QueryItemIconByID(itemID)
    if not itemID or not _C_GetItemIconByID then return nil end
    return _C_GetItemIconByID(itemID)
end

function CDMSources.QueryItemNameByID(itemID)
    if not itemID or not _C_GetItemNameByID then return nil end
    return _C_GetItemNameByID(itemID)
end

function CDMSources.QueryItemSpell(itemID)
    if not itemID or not _C_GetItemSpell then return nil, nil end
    return _C_GetItemSpell(itemID)
end

function CDMSources.QueryItemQualityByID(itemID)
    if not itemID or not _C_GetItemQualityByID then return nil end
    return _C_GetItemQualityByID(itemID)
end

function CDMSources.QueryItemProfessionQualityInfo(itemInfo)
    if not itemInfo or not C_TradeSkillUI then return nil end
    if issecretvalue and issecretvalue(itemInfo) then return nil end -- @secret-policy: reject-secret-value
    if C_TradeSkillUI.GetItemReagentQualityInfo then
        local ok, info = ns.SafeCall("best-effort-style", C_TradeSkillUI.GetItemReagentQualityInfo, itemInfo)
        if ok and info then return info end
    end
    if C_TradeSkillUI.GetItemCraftedQualityInfo then
        local ok, info = ns.SafeCall("best-effort-style", C_TradeSkillUI.GetItemCraftedQualityInfo, itemInfo)
        if ok then return info end
    end
    return nil
end

local _C_GetFirstTriggeredSpellForItem = C_Item and C_Item.GetFirstTriggeredSpellForItem

function CDMSources.QueryFirstTriggeredSpellForItem(itemID, itemQuality)
    if not itemID or itemQuality == nil or not _C_GetFirstTriggeredSpellForItem then return nil end
    return _C_GetFirstTriggeredSpellForItem(itemID, itemQuality)
end

local _C_IsEquippedItem = C_Item and C_Item.IsEquippedItem
local _GetInventoryItemID = GetInventoryItemID
local _GetInventoryItemLink = GetInventoryItemLink
local _GetInventoryItemTexture = GetInventoryItemTexture
local _C_GetItemCount = C_Item and C_Item.GetItemCount

function CDMSources.QueryIsEquippedItem(itemID)
    if not itemID or not _C_IsEquippedItem then return nil end
    return _C_IsEquippedItem(itemID)
end

function CDMSources.QueryInventoryItemID(unit, slotID)
    if not unit or not slotID or not _GetInventoryItemID then return nil end
    return _GetInventoryItemID(unit, slotID)
end

function CDMSources.QueryInventoryItemLink(unit, slotID)
    if not unit or not slotID or not _GetInventoryItemLink then return nil end
    return _GetInventoryItemLink(unit, slotID)
end

function CDMSources.QueryInventoryItemTexture(unit, slotID)
    if not unit or not slotID or not _GetInventoryItemTexture then return nil end
    return _GetInventoryItemTexture(unit, slotID)
end

function CDMSources.QueryItemCount(itemID, includeBank, includeUses, forceUpdate)
    if not itemID or not _C_GetItemCount then return nil end
    return _C_GetItemCount(itemID, includeBank, includeUses, forceUpdate)
end

function CDMSources.QueryBestOwnedItemVariant(itemID)
    if not itemID then return nil end
    if issecretvalue and issecretvalue(itemID) then return nil end -- @secret-policy: reject-secret-ids

    local consumables = ns.ConsumableMacros
    local getVariantOrder = consumables and consumables.GetVariantOrderForItem
    local variants = getVariantOrder and getVariantOrder(itemID)
    if type(variants) ~= "table" or #variants == 0 then
        return itemID
    end

    for _, variantID in ipairs(variants) do
        if type(variantID) == "number" then
            local count = CDMSources.QueryItemCount(variantID, false, false)
            if issecretvalue and issecretvalue(count) then
                return itemID
            end
            if type(count) == "number" and count > 0 then
                return variantID
            end
        end
    end

    return itemID
end

local _C_GetItemCooldown = C_Item and C_Item.GetItemCooldown

function CDMSources.QueryItemCooldown(itemID)
    if not itemID or not _C_GetItemCooldown then return nil end
    return _C_GetItemCooldown(itemID)
end

local function QueryScannerActive(scanner, spellID, itemID)
    local active, expiration, duration, auraInstanceID, auraUnit
    if itemID and scanner.IsItemActive then
        local ok, a, e, d, instID, unit = ns.SafeCall("chain-next", scanner.IsItemActive, itemID)
        if ok then
            active, expiration, duration, auraInstanceID, auraUnit = a, e, d, instID, unit
        end
    end
    if active ~= true and spellID and scanner.IsSpellActive then
        local ok, a, e, d, instID, unit = ns.SafeCall("chain-next", scanner.IsSpellActive, spellID)
        if ok then
            active, expiration, duration, auraInstanceID, auraUnit = a, e, d, instID, unit
        end
    end
    return active == true, expiration, duration, auraInstanceID, auraUnit
end

local _scannerAuraInfoScratch = {}

local function CopyScannerAuraInfo(data, active, expiration, duration, source, sourceItemID, sourceSpellID,
                                   auraInstanceID, auraUnit)
    if not data and not active then return nil end
    local s = _scannerAuraInfoScratch
    s.active = active == true
    s.expiration = expiration
    s.duration = duration or (data and data.duration)
    s.auraInstanceID = auraInstanceID
    s.auraUnit = auraUnit
    s.useSpellID = data and data.useSpellID or sourceSpellID
    s.buffSpellID = data and data.buffSpellID or nil
    s.icon = data and data.icon or nil
    s.name = data and data.name or nil
    s.source = source
    s.sourceItemID = sourceItemID
    s.sourceSpellID = sourceSpellID
    return s
end

local function QueryScannedItemInfo(scanner, itemID)
    if not itemID or not scanner.GetScannedItemInfo then return nil end
    local ok, data = ns.SafeCall("best-effort-style", scanner.GetScannedItemInfo, itemID)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function QueryScannedSpellInfo(scanner, spellID)
    if not spellID or not scanner.GetScannedSpellInfo then return nil end
    local ok, data = ns.SafeCall("best-effort-style", scanner.GetScannedSpellInfo, spellID)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function RegisterScannerItemUseSpell(scanner, itemID, spellID)
    if not itemID or not spellID or not scanner.RegisterItemUseSpell then return end
    -- (@secret-policy: reject-secret-ids, cdm_sources.lua:279) before this
    ns.SafeCall("report", scanner.RegisterItemUseSpell, itemID, spellID)
end

function CDMSources.QueryScannedItemAuraInfo(itemID, itemSpellID)
    if not itemID and not itemSpellID then return nil end

    local root = _G and _G.QUI or QUI
    local scanner = root and root.SpellScanner
    if not scanner then return nil end

    local resolvedItemSpellID = itemSpellID
    if not resolvedItemSpellID and itemID and CDMSources.QueryItemSpell then
        local _, spellID = CDMSources.QueryItemSpell(itemID)
        resolvedItemSpellID = spellID
    end
    RegisterScannerItemUseSpell(scanner, itemID, resolvedItemSpellID)

    local data = QueryScannedItemInfo(scanner, itemID)
    local sourceItemID = itemID
    if not data and itemID then
        local consumables = ns.ConsumableMacros
        local getVariantOrder = consumables and consumables.GetVariantOrderForItem
        local variants = getVariantOrder and getVariantOrder(itemID)
        if type(variants) == "table" then
            for _, variantID in ipairs(variants) do
                if type(variantID) == "number" then
                    data = QueryScannedItemInfo(scanner, variantID)
                    if data then
                        sourceItemID = variantID
                        break
                    end
                end
            end
        end
    end
    if data then
        local useSpellID = data.useSpellID or resolvedItemSpellID
        local active, expiration, duration, auraInstanceID, auraUnit =
            QueryScannerActive(scanner, useSpellID, sourceItemID)
        return CopyScannerAuraInfo(data, active, expiration, duration, "item",
            sourceItemID, useSpellID, auraInstanceID, auraUnit)
    end

    data = QueryScannedSpellInfo(scanner, resolvedItemSpellID)
    if data then
        local active, expiration, duration, auraInstanceID, auraUnit =
            QueryScannerActive(scanner, resolvedItemSpellID, nil)
        return CopyScannerAuraInfo(data, active, expiration, duration, "spell",
            itemID, resolvedItemSpellID, auraInstanceID, auraUnit)
    end

    local active, expiration, duration, auraInstanceID, auraUnit =
        QueryScannerActive(scanner, resolvedItemSpellID, itemID)
    return CopyScannerAuraInfo(nil, active, expiration, duration, "active",
        itemID, resolvedItemSpellID, auraInstanceID, auraUnit)
end

local _C_GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
local _C_GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local _C_DoesAuraHaveExpirationTime = C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime
local _C_IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local _C_GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
local _C_GetUnitAuraBySpellID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
local _C_GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local _C_GetAuraDataBySpellID = C_UnitAuras and (C_UnitAuras.GetAuraDataBySpellID or C_UnitAuras.GetUnitAuraBySpellID)
local _C_GetCooldownAuraBySpellID = C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID
local _C_GetAuraDataBySpellName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local _C_GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras

local function EnforceAuraFilterPolarity(result, filter)
    if result == nil or filter == nil then return result end
    local wantHelpful = string.find(filter, "HELPFUL", 1, true) ~= nil
    local wantHarmful = string.find(filter, "HARMFUL", 1, true) ~= nil
    if wantHelpful == wantHarmful then return result end
    local field
    if wantHelpful then
        field = result.isHelpful
    else
        field = result.isHarmful
    end
    if issecretvalue and issecretvalue(field) then return result end
    if field == nil then return result end
    if field then return result end
    return nil
end
local _auraDataFallbackNeedsPolarity = C_UnitAuras
    and not C_UnitAuras.GetAuraDataBySpellID and _C_GetUnitAuraBySpellID ~= nil

local _auraMemoNilResult = {}
local _auraMemo = {}
local _auraMemoCacheableUnit = { player = true, target = true }
local _auraMemoFilterTag = { [false] = "n", HELPFUL = "H", HARMFUL = "h" }
local _auraMemoBucket = {
    unitBySpell   = { n = "u-n", H = "u-H", h = "u-h" },
    dataBySpell   = { n = "d-n", H = "d-H", h = "d-h" },
    byName        = { n = "m-n", H = "m-H", h = "m-h" },
    playerBySpell = { n = "p-n" },
}
local auraMemoStats

local function AuraMemoBucketKey(bucket, filter)
    local tag = _auraMemoFilterTag[filter or false]
    if not tag then return nil end
    return bucket[tag]
end

local function AuraMemoGet(unit, bucketKey, id)
    local u = _auraMemo[unit]
    if not u then return nil, false end
    local b = u[bucketKey]
    if not b then return nil, false end
    local v = b[id]
    if v == nil then return nil, false end
    if auraMemoStats then auraMemoStats.hits = auraMemoStats.hits + 1 end
    if v == _auraMemoNilResult then return nil, true end
    return v, true
end

local function AuraMemoStore(unit, bucketKey, id, result)
    local u = _auraMemo[unit]
    if not u then u = {}; _auraMemo[unit] = u end
    local b = u[bucketKey]
    if not b then b = {}; u[bucketKey] = b end
    b[id] = (result == nil) and _auraMemoNilResult or result
    if auraMemoStats then auraMemoStats.misses = auraMemoStats.misses + 1 end
end

local function AuraMemoCacheable(unit, id)
    if not _auraMemoCacheableUnit[unit] then return false end
    if WoW_IsSecretValue and WoW_IsSecretValue(id) then return false end -- @secret-policy: skip-capture-when-unknown
    return true
end

function CDMSources.QueryAuraDuration(unit, auraInstanceID)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_GetAuraDuration then return nil end
    if AreAurasSecret() then return nil end
    return _C_GetAuraDuration(unit, auraInstanceID)
end

function CDMSources.QueryAuraDataByAuraInstanceID(unit, auraInstanceID)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_GetAuraDataByAuraInstanceID then return nil end
    if AreAurasSecret() then return nil end
    return _C_GetAuraDataByAuraInstanceID(unit, auraInstanceID)
end

function CDMSources.QueryAuraHasExpirationTime(unit, auraInstanceID)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_DoesAuraHaveExpirationTime then return nil end
    if AreAurasSecret() then return nil end
    return _C_DoesAuraHaveExpirationTime(unit, auraInstanceID)
end

function CDMSources.QueryAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_IsAuraFilteredOutByInstanceID then return nil end
    if AreAurasSecret() then return nil end
    return _C_IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
end

function CDMSources.QueryAuraApplicationDisplayCount(unit, auraInstanceID, minValue, maxValue)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_GetAuraApplicationDisplayCount then return nil end
    if AreAurasSecret() then return nil end
    return _C_GetAuraApplicationDisplayCount(unit, auraInstanceID, minValue, maxValue)
end

function CDMSources.QueryUnitAuraBySpellID(unit, spellID, filter)
    if not unit or not spellID or not _C_GetUnitAuraBySpellID then return nil end
    if AuraMemoCacheable(unit, spellID) then
        local bucketKey = AuraMemoBucketKey(_auraMemoBucket.unitBySpell, filter)
        if bucketKey then
            local v, hit = AuraMemoGet(unit, bucketKey, spellID)
            if hit then return v end
            local result = EnforceAuraFilterPolarity(_C_GetUnitAuraBySpellID(unit, spellID), filter)
            AuraMemoStore(unit, bucketKey, spellID, result)
            return result
        end
    end
    if auraMemoStats then auraMemoStats.bypass = auraMemoStats.bypass + 1 end
    return EnforceAuraFilterPolarity(_C_GetUnitAuraBySpellID(unit, spellID), filter)
end

function CDMSources.QueryPlayerAuraBySpellID(spellID)
    if not spellID or not _C_GetPlayerAuraBySpellID then return nil end
    if AuraMemoCacheable("player", spellID) then
        local bucketKey = _auraMemoBucket.playerBySpell.n
        local v, hit = AuraMemoGet("player", bucketKey, spellID)
        if hit then return v end
        local result = _C_GetPlayerAuraBySpellID(spellID)
        AuraMemoStore("player", bucketKey, spellID, result)
        return result
    end
    if auraMemoStats then auraMemoStats.bypass = auraMemoStats.bypass + 1 end
    return _C_GetPlayerAuraBySpellID(spellID)
end

function CDMSources.QueryAuraDataBySpellID(unit, spellID, filter)
    if not unit or not spellID or not _C_GetAuraDataBySpellID then return nil end
    if AuraMemoCacheable(unit, spellID) then
        local bucketKey = AuraMemoBucketKey(_auraMemoBucket.dataBySpell, filter)
        if bucketKey then
            local v, hit = AuraMemoGet(unit, bucketKey, spellID)
            if hit then return v end
            local result = _C_GetAuraDataBySpellID(unit, spellID, filter)
            if _auraDataFallbackNeedsPolarity then
                result = EnforceAuraFilterPolarity(result, filter)
            end
            AuraMemoStore(unit, bucketKey, spellID, result)
            return result
        end
    end
    if auraMemoStats then auraMemoStats.bypass = auraMemoStats.bypass + 1 end
    local result = _C_GetAuraDataBySpellID(unit, spellID, filter)
    if _auraDataFallbackNeedsPolarity then
        result = EnforceAuraFilterPolarity(result, filter)
    end
    return result
end

function CDMSources.QueryCooldownAuraBySpellID(spellID)
    if not spellID or not _C_GetCooldownAuraBySpellID then return nil end
    return _C_GetCooldownAuraBySpellID(spellID)
end

function CDMSources.QueryAuraDataBySpellName(unit, name, filter)
    if not unit or not name or not _C_GetAuraDataBySpellName then return nil end
    if AuraMemoCacheable(unit, name) then
        local bucketKey = AuraMemoBucketKey(_auraMemoBucket.byName, filter)
        if bucketKey then
            local v, hit = AuraMemoGet(unit, bucketKey, name)
            if hit then return v end
            local result = _C_GetAuraDataBySpellName(unit, name, filter)
            AuraMemoStore(unit, bucketKey, name, result)
            return result
        end
    end
    if auraMemoStats then auraMemoStats.bypass = auraMemoStats.bypass + 1 end
    return _C_GetAuraDataBySpellName(unit, name, filter)
end

function CDMSources.QueryUnitAuras(unit, filter, maxCount)
    if not unit or not _C_GetUnitAuras then return nil end
    if AreAurasSecret() then return nil end
    return _C_GetUnitAuras(unit, filter, maxCount)
end

local function InvalidateAuraMemoForUnit(unit)
    local u = _auraMemo[unit]
    if not u then return end
    for _, b in pairs(u) do wipe(b) end
    if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
end

local function InvalidateAllAuraMemo()
    for _, u in pairs(_auraMemo) do
        for _, b in pairs(u) do wipe(b) end
    end
    if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
end

local function DropAuraMemoKey(u, key)
    if WoW_IsSecretValue and WoW_IsSecretValue(key) then return false end -- @secret-policy: reject-secret-ids
    if key == nil then return true end
    for _, b in pairs(u) do
        if b[key] ~= nil then
            b[key] = nil
            if auraMemoStats then auraMemoStats.deltaDrops = auraMemoStats.deltaDrops + 1 end
        end
    end
    return true
end

local _auraDeltaChangedIID = {}

local function InvalidateAuraMemoForDelta(unit, updateInfo)
    local u = _auraMemo[unit]
    if not u then return end

    if WoW_IsSecretValue and WoW_IsSecretValue(updateInfo) then
        updateInfo = nil
    end

    if updateInfo and WoW_IsSecretValue and WoW_IsSecretValue(updateInfo.isFullUpdate) then
        updateInfo = nil
    end

    if not updateInfo or updateInfo.isFullUpdate then
        for _, b in pairs(u) do wipe(b) end
        if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
        return
    end

    local changed = _auraDeltaChangedIID
    wipe(changed)
    local hasChanged, uncertainChanged = false, false

    local removed = updateInfo.removedAuraInstanceIDs
    if WoW_IsSecretValue and WoW_IsSecretValue(removed) then
        uncertainChanged = true
    elseif removed then
        for i = 1, #removed do
            local iid = removed[i]
            if WoW_IsSecretValue and WoW_IsSecretValue(iid) then
                uncertainChanged = true
            elseif iid ~= nil then
                changed[iid] = true; hasChanged = true
            end
        end
    end
    local updated = updateInfo.updatedAuraInstanceIDs
    if WoW_IsSecretValue and WoW_IsSecretValue(updated) then
        uncertainChanged = true
    elseif updated then
        for i = 1, #updated do
            local iid = updated[i]
            if WoW_IsSecretValue and WoW_IsSecretValue(iid) then
                uncertainChanged = true
            elseif iid ~= nil then
                changed[iid] = true; hasChanged = true
            end
        end
    end

    local dropAllNils, dropAllPresent = false, false
    local added = updateInfo.addedAuras
    if WoW_IsSecretValue and WoW_IsSecretValue(added) then
        dropAllNils, dropAllPresent = true, true
    elseif added then
        for i = 1, #added do
            local ad = added[i]
            if WoW_IsSecretValue and WoW_IsSecretValue(ad) then
                dropAllNils, dropAllPresent = true, true
            elseif ad then
                if not DropAuraMemoKey(u, ad.spellId) then dropAllNils, dropAllPresent = true, true end
                local mapped = ad.spellID
                if (WoW_IsSecretValue and (WoW_IsSecretValue(mapped) or WoW_IsSecretValue(ad.spellId))) then
                    if not DropAuraMemoKey(u, mapped) then dropAllNils, dropAllPresent = true, true end
                elseif mapped ~= ad.spellId and not DropAuraMemoKey(u, mapped) then
                    dropAllNils, dropAllPresent = true, true
                end
                if not DropAuraMemoKey(u, ad.name) then dropAllNils, dropAllPresent = true, true end
            end
        end
    end

    if not hasChanged and not uncertainChanged and not dropAllNils then return end

    for _, b in pairs(u) do
        for key, val in pairs(b) do
            if val == _auraMemoNilResult then
                if dropAllNils then b[key] = nil end
            elseif uncertainChanged or dropAllPresent then
                b[key] = nil
            else
                local iid = val and val.auraInstanceID
                if WoW_IsSecretValue and WoW_IsSecretValue(iid) then
                    if hasChanged then b[key] = nil end -- @secret-policy: evict-when-unreadable
                elseif iid == nil then
                elseif changed[iid] then
                    b[key] = nil
                end
            end
        end
    end
    if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
end

CDMSources.InvalidateAuraMemoForUnit = InvalidateAuraMemoForUnit
CDMSources.InvalidateAuraMemoForDelta = InvalidateAuraMemoForDelta
CDMSources.InvalidateAllAuraMemo = InvalidateAllAuraMemo

local function SetupAuraMemoInvalidation()
    if type(CreateFrame) ~= "function" then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        InvalidateAllAuraMemo()
    end)
end

local function SetupAuraMemoDebug()
    auraMemoStats = { hits = 0, misses = 0, wipes = 0, bypass = 0, deltaDrops = 0 }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_auraMemoHits",   counter = true, fn = function() return auraMemoStats.hits end }
    mp[#mp + 1] = { name = "CDM_auraMemoMisses", counter = true, fn = function() return auraMemoStats.misses end }
    mp[#mp + 1] = { name = "CDM_auraMemoWipes",  counter = true, fn = function() return auraMemoStats.wipes end }
    mp[#mp + 1] = { name = "CDM_auraMemoBypass", counter = true, fn = function() return auraMemoStats.bypass end }
    mp[#mp + 1] = { name = "CDM_auraMemoDeltaDrops", counter = true, fn = function() return auraMemoStats.deltaDrops end }
    mp[#mp + 1] = { name = "CDM_auraMemo", tbl = _auraMemo }
end

SetupAuraMemoInvalidation()
if ns.DebugRegister then
    ns.DebugRegister(SetupAuraMemoDebug)
end
