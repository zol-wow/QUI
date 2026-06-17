local _, ns = ...

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
local Shared = ns.CDMShared
local WoW_IsSecretValue = issecretvalue

-- WoW provides `wipe`; the standalone test harness does not. Local fallback so
-- the aura-memo invalidation helpers below run in both environments.
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local function HasOpaqueValue(value)
    if WoW_IsSecretValue and WoW_IsSecretValue(value) then
        return true
    end
    return value ~= nil
end

local function IsCooldownMirrorCategory(category)
    if Shared and Shared.IsCooldownMirrorCategory then
        return Shared.IsCooldownMirrorCategory(category)
    end
    return category == "essential" or category == "utility"
end

-- Direct API references hoisted at load. Wrappers below call these without
-- pcall because the Blizzard C bindings return nil for invalid input rather
-- than throwing under normal play. Removing pcall in the hot path saves a
-- per-call vararg frame and tuple allocation — significant at 5–17k calls/5s
-- during combat (see memaudit traces). Guards still screen out nil/missing
-- APIs so the wrapper itself doesn't fault.
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

-- Is this spell independently learned by the player right now? Covers class/
-- spec spells (IsSpellKnown) and talent-granted spells (IsPlayerSpell). Used
-- by the catalog to tell a transient proc override (base still learned) from a
-- permanent talent conversion (base no longer learned). Non-combat only.
local _IsSpellKnown = IsSpellKnown
local _IsPlayerSpell = IsPlayerSpell
function CDMSources.QueryIsSpellKnownOrPlayerSpell(spellID)
    if not spellID then return false end
    if _IsSpellKnown and _IsSpellKnown(spellID) then return true end
    if _IsPlayerSpell and _IsPlayerSpell(spellID) then return true end
    return false
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
    local ok = pcall(C_Spell.EnableSpellRangeCheck, spellID, enable == true)
    return ok == true
end

local function querySpellAffinity(spellNameOrID, namespacedFn, globalFn)
    if not spellNameOrID then return nil end
    if namespacedFn then
        local ok, result = pcall(namespacedFn, spellNameOrID)
        if ok then return result end
    end
    if globalFn then
        local ok, result = pcall(globalFn, spellNameOrID)
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
    if issecretvalue and issecretvalue(itemInfo) then return nil end
    if C_TradeSkillUI.GetItemReagentQualityInfo then
        local ok, info = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, itemInfo)
        if ok and info then return info end
    end
    if C_TradeSkillUI.GetItemCraftedQualityInfo then
        local ok, info = pcall(C_TradeSkillUI.GetItemCraftedQualityInfo, itemInfo)
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
    if issecretvalue and issecretvalue(itemID) then return nil end

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
        local ok, a, e, d, instID, unit = pcall(scanner.IsItemActive, itemID)
        if ok then
            active, expiration, duration, auraInstanceID, auraUnit = a, e, d, instID, unit
        end
    end
    if active ~= true and spellID and scanner.IsSpellActive then
        local ok, a, e, d, instID, unit = pcall(scanner.IsSpellActive, spellID)
        if ok then
            active, expiration, duration, auraInstanceID, auraUnit = a, e, d, instID, unit
        end
    end
    return active == true, expiration, duration, auraInstanceID, auraUnit
end

-- Reused scratch for the scanned-aura result. Every consumer
-- (cdm_resolvers/cdm_icon_renderer/cdm_bar_renderer/cdm_icon_custom_bar_policy)
-- reads the fields it needs synchronously and discards the table before the
-- next QueryScannedItemAuraInfo call, so a single shared table is safe and
-- removes a fresh 12-field allocation per item/aura probe (CDM_srcAuraData).
-- Every field is assigned unconditionally below so no stale value leaks across
-- calls; do NOT stash this table on an icon or read it on a later tick.
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
    local ok, data = pcall(scanner.GetScannedItemInfo, itemID)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function QueryScannedSpellInfo(scanner, spellID)
    if not spellID or not scanner.GetScannedSpellInfo then return nil end
    local ok, data = pcall(scanner.GetScannedSpellInfo, spellID)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function RegisterScannerItemUseSpell(scanner, itemID, spellID)
    if not itemID or not spellID or not scanner.RegisterItemUseSpell then return end
    pcall(scanner.RegisterItemUseSpell, itemID, spellID)
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
local _C_GetAuraDataBySpellID = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID
local _C_GetCooldownAuraBySpellID = C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID
local _C_GetAuraDataBySpellName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local _C_GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras

---------------------------------------------------------------------------
-- AURA QUERY MEMO
--
-- The by-spellID / by-name aura reads below were the one C_UnitAuras family
-- with no dedupe layer: the resolver's multi-ID fallback and the blizz-mirror
-- multi-filter fallthrough fire the SAME (unit, spellID, filter) probe many
-- times per icon per tick, and each returns a fresh ~25-field AuraData the
-- engine attributes to QUI -- a dominant slice of in-combat GC churn (memaudit
-- CDM_rsMirrorAura / CDM_rsAuraRuntime). Every other C query family already
-- dedupes (cdm_runtime_queries batch cache, ActionBars LoC batch cache); these
-- did not.
--
-- Memoize results per (unit, fn, filter, id), wiped whenever the unit's auras
-- can change: its UNIT_AURA (auras only mutate on that event), a target swap
-- (target identity changes wholesale with no UNIT_AURA), or a combat-state flip
-- (the secret-status of AuraData turns over). A hit between those events is
-- therefore exact. A miss calls the SAME C function, so semantics are identical
-- -- including RequiresNonSecretAura, which a GetAuraDataBySlot snapshot cache
-- would silently violate under combat aura-restriction.
--
-- Only player + target are cached: they are the units with reliable UNIT_AURA
-- delivery through ns.AuraEvents (roster tier + the target interest predicate).
-- pet and every other unit bypass straight to the live C call (correct, just
-- uncached). Keys are the caller-supplied spellID/name (config-derived, never
-- secret); stored values are the opaque AuraData, only forwarded downstream,
-- never compared.
---------------------------------------------------------------------------
local _auraMemoNilResult = {}            -- sentinel: "queried, engine returned nil"
local _auraMemo = {}                     -- [unit] = { [bucketKey] = { [id] = result | nil-sentinel } }
local _auraMemoCacheableUnit = { player = true, target = true }
-- Prebuilt bucket keys per (fn, filter) so a cache HIT allocates nothing (no
-- runtime string concat). filter is nil / "HELPFUL" / "HARMFUL" in every live
-- caller; an unrecognized filter yields a nil tag and takes the uncached path.
local _auraMemoFilterTag = { [false] = "n", HELPFUL = "H", HARMFUL = "h" }
local _auraMemoBucket = {
    unitBySpell   = { n = "u-n", H = "u-H", h = "u-h" },
    dataBySpell   = { n = "d-n", H = "d-H", h = "d-h" },
    byName        = { n = "m-n", H = "m-H", h = "m-h" },
    playerBySpell = { n = "p-n" },
}
local auraMemoStats  -- debug counters; nil until QUI_Debug activates instrumentation

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

-- Cacheable when the unit has reliable invalidation AND the id is a plain
-- (non-secret) value usable as a table key. Secret ids take the live path.
local function AuraMemoCacheable(unit, id)
    if not _auraMemoCacheableUnit[unit] then return false end
    if WoW_IsSecretValue and WoW_IsSecretValue(id) then return false end
    return true
end

function CDMSources.QueryAuraDuration(unit, auraInstanceID)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_GetAuraDuration then return nil end
    return _C_GetAuraDuration(unit, auraInstanceID)
end

function CDMSources.QueryAuraDataByAuraInstanceID(unit, auraInstanceID)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_GetAuraDataByAuraInstanceID then return nil end
    return _C_GetAuraDataByAuraInstanceID(unit, auraInstanceID)
end

function CDMSources.QueryAuraHasExpirationTime(unit, auraInstanceID)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_DoesAuraHaveExpirationTime then return nil end
    return _C_DoesAuraHaveExpirationTime(unit, auraInstanceID)
end

function CDMSources.QueryAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_IsAuraFilteredOutByInstanceID then return nil end
    return _C_IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
end

function CDMSources.QueryAuraApplicationDisplayCount(unit, auraInstanceID, minValue, maxValue)
    if not unit or not HasOpaqueValue(auraInstanceID) or not _C_GetAuraApplicationDisplayCount then return nil end
    return _C_GetAuraApplicationDisplayCount(unit, auraInstanceID, minValue, maxValue)
end

function CDMSources.QueryUnitAuraBySpellID(unit, spellID, filter)
    if not unit or not spellID or not _C_GetUnitAuraBySpellID then return nil end
    if AuraMemoCacheable(unit, spellID) then
        local bucketKey = AuraMemoBucketKey(_auraMemoBucket.unitBySpell, filter)
        if bucketKey then
            local v, hit = AuraMemoGet(unit, bucketKey, spellID)
            if hit then return v end
            local result = _C_GetUnitAuraBySpellID(unit, spellID, filter)
            AuraMemoStore(unit, bucketKey, spellID, result)
            return result
        end
    end
    if auraMemoStats then auraMemoStats.bypass = auraMemoStats.bypass + 1 end
    return _C_GetUnitAuraBySpellID(unit, spellID, filter)
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
            AuraMemoStore(unit, bucketKey, spellID, result)
            return result
        end
    end
    if auraMemoStats then auraMemoStats.bypass = auraMemoStats.bypass + 1 end
    return _C_GetAuraDataBySpellID(unit, spellID, filter)
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
    return _C_GetUnitAuras(unit, filter, maxCount)
end

function CDMSources.QueryMirroredCooldownState(spellID, viewerType)
    local mirror = ns.CDMBlizzMirror
    if not mirror or not spellID then return nil end
    if IsCooldownMirrorCategory(viewerType)
       and mirror.GetMirroredStateForViewer then
        return mirror.GetMirroredStateForViewer(spellID, viewerType)
    end
    if mirror.FindCooldownState then
        return mirror.FindCooldownState(spellID)
    end
    return nil
end

---------------------------------------------------------------------------
-- AURA MEMO INVALIDATION
---------------------------------------------------------------------------
local function InvalidateAuraMemoForUnit(unit)
    local u = _auraMemo[unit]
    if not u then return end
    -- Wipe each bucket's contents but keep the bucket tables for reuse, so an
    -- invalidation allocates nothing (this runs on every UNIT_AURA in combat).
    for _, b in pairs(u) do wipe(b) end
    if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
end

local function InvalidateAllAuraMemo()
    for _, u in pairs(_auraMemo) do
        for _, b in pairs(u) do wipe(b) end
    end
    if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
end

-- Drop one key across every bucket of a unit's memo. Returns true if the key
-- could be targeted; false if it was secret/unusable (caller widens to a
-- conservative nil-sweep). Dropping a still-valid present entry here is
-- harmless -- it simply re-probes once.
local function DropAuraMemoKey(u, key)
    if key == nil then return true end
    if WoW_IsSecretValue and WoW_IsSecretValue(key) then return false end
    for _, b in pairs(u) do
        if b[key] ~= nil then
            b[key] = nil
            if auraMemoStats then auraMemoStats.deltaDrops = auraMemoStats.deltaDrops + 1 end
        end
    end
    return true
end

-- Reused scratch: changed aura instanceIDs for the current delta. Module-level
-- + wiped per call so a delta invalidation allocates nothing. Not re-entrant
-- (the synchronous UNIT_AURA capture never re-enters this).
local _auraDeltaChangedIID = {}

-- Delta-scoped invalidation. UNIT_AURA carries which auras changed; nuking the
-- whole unit on every tick (combat fires UNIT_AURA ~5-10x/s) kept the memo cold.
-- Instead:
--   * isFullUpdate / no payload -> wipe the unit (no list to scope by).
--   * removed + updated instanceIDs -> drop only cached entries whose stored
--     AuraData.auraInstanceID matches (a present aura that vanished or restacked
--     is stale; everything else stays warm).
--   * addedAuras -> drop only the keys a newly-applied aura could now satisfy
--     (its spellId/spellID for direct + mapped spellID queries, its name for
--     name queries); previously-cached nil entries for those keys must re-probe.
-- The resolver always queries by the post-mapping aura spellID, so an added
-- aura's spellId matches the memo key directly. Secret ids/instanceIDs under
-- combat aura-restriction can't be matched, so they widen to a conservative
-- sweep (drop nil entries / unverifiable present entries) -- correct, just less
-- precise in that regime.
local function InvalidateAuraMemoForDelta(unit, updateInfo)
    local u = _auraMemo[unit]
    if not u then return end

    if not updateInfo or updateInfo.isFullUpdate then
        for _, b in pairs(u) do wipe(b) end
        if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
        return
    end

    local changed = _auraDeltaChangedIID
    wipe(changed)
    local hasChanged, uncertainChanged = false, false

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local iid = removed[i]
            if iid ~= nil then
                if WoW_IsSecretValue and WoW_IsSecretValue(iid) then
                    uncertainChanged = true
                else
                    changed[iid] = true; hasChanged = true
                end
            end
        end
    end
    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            local iid = updated[i]
            if iid ~= nil then
                if WoW_IsSecretValue and WoW_IsSecretValue(iid) then
                    uncertainChanged = true
                else
                    changed[iid] = true; hasChanged = true
                end
            end
        end
    end

    -- Added auras: re-probe only the keys they could satisfy. A secret-keyed
    -- add we can't target widens to dropping all nil-sentinel entries.
    local dropAllNils = false
    local added = updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local ad = added[i]
            if ad then
                if not DropAuraMemoKey(u, ad.spellId) then dropAllNils = true end
                if ad.spellID ~= ad.spellId and not DropAuraMemoKey(u, ad.spellID) then dropAllNils = true end
                if not DropAuraMemoKey(u, ad.name) then dropAllNils = true end
            end
        end
    end

    if not hasChanged and not uncertainChanged and not dropAllNils then return end

    for _, b in pairs(u) do
        for key, val in pairs(b) do
            if val == _auraMemoNilResult then
                if dropAllNils then b[key] = nil end
            else
                local iid = val and val.auraInstanceID
                if iid == nil then
                    -- No readable instanceID to match; only a full wipe clears it.
                elseif WoW_IsSecretValue and WoW_IsSecretValue(iid) then
                    if uncertainChanged then b[key] = nil end
                elseif changed[iid] then
                    b[key] = nil
                end
            end
        end
    end
    if auraMemoStats then auraMemoStats.wipes = auraMemoStats.wipes + 1 end
end

-- Public invalidation API. The hot invalidation is driven SYNCHRONOUSLY from
-- cdm_spelldata's UNIT_AURA / PLAYER_TARGET_CHANGED capture frame, called before
-- that frame notifies consumers -- so every in-frame resolve that follows an
-- aura change reads a freshly-scoped memo. A deferred dispatcher hook (next
-- OnUpdate) would let those synchronous resolves read the memo one event stale.
-- InvalidateAuraMemoForDelta is the per-UNIT_AURA path (payload-scoped);
-- InvalidateAuraMemoForUnit is the full-unit drop for a target swap.
CDMSources.InvalidateAuraMemoForUnit = InvalidateAuraMemoForUnit
CDMSources.InvalidateAuraMemoForDelta = InvalidateAuraMemoForDelta
CDMSources.InvalidateAllAuraMemo = InvalidateAllAuraMemo

local function SetupAuraMemoInvalidation()
    -- Wholesale drops the memo can't get from a per-unit UNIT_AURA: a
    -- combat-state flip turns over the secret-status of AuraData with no aura
    -- set change (so no UNIT_AURA), and a world transition swaps the aura
    -- universe. Both are rare (not hot-path). Per-unit aura/target-swap
    -- invalidation lives in cdm_spelldata's synchronous capture frame.
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
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupAuraMemoDebug)
end
