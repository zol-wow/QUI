local _, ns = ...
local Shared = ns.CDMShared

local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local CDMResolvers = {}
ns.CDMResolvers = CDMResolvers
local Scheduler = ns.CDMScheduler
local Sources = ns.CDMSources

local resolverStats
local currentResolveCallerTag
local markFn
local function MemAuditProfilerMark(name)
    if markFn then markFn(name) end
end

local _subscribers = {}

local _fallbackSnapshotPool = {}
local _fallbackSnapshotPoolN = 0

local function publish(eventName, ...)
    if Scheduler and Scheduler.Publish then
        Scheduler.Publish(eventName, ...)
        return
    end

    local list = _subscribers[eventName]
    if not list then return end
    local n = #list
    if n == 0 then return end

    local poolN = _fallbackSnapshotPoolN
    local snapshot
    if poolN > 0 then
        snapshot = _fallbackSnapshotPool[poolN]
        _fallbackSnapshotPool[poolN] = nil
        _fallbackSnapshotPoolN = poolN - 1
    else
        snapshot = {}
    end

    for i = 1, n do snapshot[i] = list[i] end
    for i = 1, n do
        ---@diagnostic disable-next-line: redundant-parameter
        xpcall(snapshot[i], geterrorhandler(), eventName, ...)
    end

    wipe(snapshot)
    poolN = _fallbackSnapshotPoolN + 1
    _fallbackSnapshotPoolN = poolN
    _fallbackSnapshotPool[poolN] = snapshot
end

function CDMResolvers.Subscribe(eventName, handler)
    if Scheduler and Scheduler.Subscribe then
        Scheduler.Subscribe(eventName, handler)
        return
    end

    local list = _subscribers[eventName]
    if not list then
        list = {}
        _subscribers[eventName] = list
    end
    list[#list + 1] = handler
end

function CDMResolvers.Unsubscribe(eventName, handler)
    if Scheduler and Scheduler.Unsubscribe then
        Scheduler.Unsubscribe(eventName, handler)
        return
    end

    local list = _subscribers[eventName]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
            return
        end
    end
end

local _busEventFrame = CreateFrame("Frame")
local _rebuildPending = false

local function RebuildCatalog()
    if InCombatLockdown() then
        _rebuildPending = true
        return
    end
    _rebuildPending = false
    CDMResolvers._catalogVersion = (CDMResolvers._catalogVersion or 0) + 1
end

CDMResolvers._RebuildCatalog = RebuildCatalog

_busEventFrame:RegisterEvent("PLAYER_LOGIN")
_busEventFrame:RegisterEvent("TRAIT_TREE_CHANGED")
_busEventFrame:RegisterEvent("SPELLS_CHANGED")
_busEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_busEventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_ENABLED" then
        if _rebuildPending then RebuildCatalog() end
        return
    end
    RebuildCatalog()
end)

local WoW_IsSecretValue = issecretvalue
local ResolverIsSecretValue = function(value)
    if WoW_IsSecretValue then
        return WoW_IsSecretValue(value)
    end
    return false
end

local _runtimeFrame = CreateFrame("Frame")
_runtimeFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_runtimeFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
_runtimeFrame:RegisterEvent("SPELL_UPDATE_USES")
_runtimeFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_runtimeFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")

ns.CDMRuntimeEventTraceHook = nil

_runtimeFrame:SetScript("OnEvent", function(_, evt, arg1, arg2, arg3, arg4, arg5)
    local traceHook = ns.CDMRuntimeEventTraceHook
    if traceHook then
        if securecallfunction then
            securecallfunction(traceHook, "runtime-pre", evt, arg1, arg2, arg3, arg4, arg5)
        else
            traceHook("runtime-pre", evt, arg1, arg2, arg3, arg4, arg5)
        end
    end

    if evt == "SPELL_UPDATE_COOLDOWN" then
        publish("CDM:COOLDOWN_CHANGED", arg1, arg2, "refresh", arg3, arg4, arg5)
    elseif evt == "SPELL_UPDATE_CHARGES" or evt == "SPELL_UPDATE_USES" then
        publish("CDM:CHARGES_CHANGED", arg1, arg2)
    elseif evt == "UNIT_SPELLCAST_START" then
        if not ResolverIsSecretValue(arg3) then
            publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_start")
        end
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if not ResolverIsSecretValue(arg3) then
            publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_succeeded")
        end
    end
end)

local function IsSafeNumeric(val)
    if ResolverIsSecretValue and ResolverIsSecretValue(val) then
        return false -- @secret-policy: reject-secret-value
    end
    return Shared and Shared.IsSafeNumeric(val) or type(val) == "number"
end

local function GetAuraDataInstanceID(auraData)
    if not auraData then return nil end
    return auraData.auraInstanceID
end

local GCD_MAX_DURATION = 1.75
local GCD_SPELL_ID = 61304

local function DecodePotentialSecretBoolean(value)
    if ResolverIsSecretValue(value) then return nil end -- @secret-policy: reject-secret-value
    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function HasOpaqueValue(value)
    if ResolverIsSecretValue(value) then
        return true -- @secret-policy: opaque-value-present
    end
    return value ~= nil
end

local function CleanOpaqueValue(value)
    if ResolverIsSecretValue(value) then
        return nil -- @secret-policy: reject-secret-value
    end
    return value
end

function CDMResolvers.GetCooldownInfoField(info, key)
    if ResolverIsSecretValue(info) then return nil, true end -- @secret-policy: reject-secret-value
    if info == nil then return nil, false end
    local value = info[key]
    if ResolverIsSecretValue(value) then
        return nil, true -- @secret-policy: reject-secret-value
    end
    if value == nil then return nil, false end
    return value, false
end

function CDMResolvers.IsCooldownInfoActive(info)
    local active = CDMResolvers.GetCooldownInfoField(info, "isActive")
    return DecodePotentialSecretBoolean(active)
end

local GetCooldownInfoField = CDMResolvers.GetCooldownInfoField
local IsCooldownInfoActive = CDMResolvers.IsCooldownInfoActive

local RuntimeQueries = ns.CDMRuntimeQueries

local QueryCharges        = RuntimeQueries.QueryCharges
local QueryCooldown       = RuntimeQueries.QueryCooldown
local QueryDuration       = RuntimeQueries.QueryDuration
local QueryGCDDuration    = RuntimeQueries.QueryGCDDuration
local QueryChargeDuration = RuntimeQueries.QueryChargeDuration
local QueryOverrideSpell  = RuntimeQueries.QueryOverrideSpell

local function IsItemLikeEntry(entry)
    return entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
end

local function QueryItemUseSpellID(itemID)
    if not itemID then return nil end

    if Sources and Sources.QueryItemSpell then
        local _, spellID = Sources.QueryItemSpell(itemID)
        if spellID then
            return spellID
        end
    end

    if Sources and Sources.QueryFirstTriggeredSpellForItem then
        local itemQuality
        if Sources.QueryItemQualityByID then
            local quality = Sources.QueryItemQualityByID(itemID)
            if quality ~= nil then
                itemQuality = quality
            end
        end

        local spellID = Sources.QueryFirstTriggeredSpellForItem(itemID, itemQuality)
        if spellID then
            return spellID
        end
    end

    return nil
end

local function ResolveItemCooldownIdentity(entry)
    if not entry then return nil, nil, nil, nil end

    local itemID, slotID
    if entry.type == "item" then
        itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
    elseif entry.type == "trinket" or entry.type == "slot" then
        slotID = entry.id
        if Sources and Sources.QueryInventoryItemID then
            itemID = Sources.QueryInventoryItemID("player", slotID)
        end
        itemID = itemID or entry.itemID
    elseif entry.type == "macro" then
        local resolvedID, resolvedType = CDMResolvers.ResolveMacro(entry)
        if resolvedType == "item" then
            itemID = resolvedID
        end
    end

    if not itemID then return nil, slotID, nil, nil end

    local itemSpellID = QueryItemUseSpellID(itemID)
    local keySource = slotID and (tostring(slotID) .. ":" .. tostring(itemID)) or tostring(itemID)
    return itemID, slotID, itemSpellID, keySource
end

local _textureCycleCache = {}
CDMResolvers._textureCycleCache = _textureCycleCache

local function SetupDebugInstrumentation()
    resolverStats = {
        itemDurationIconReuses = 0,
        resolveBy = {
            spellID     = 0,
            aura        = 0,
            usability   = 0,
            catalog     = 0,
            walk        = 0,
            cooldownOnly = 0,
            other       = 0,
        },
        auraProbeHit           = 0,
        auraProbeGuardSkip     = 0,
        auraProbeExpensiveMiss = 0,
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_itemDurationIconReuses", counter = true, fn = function() return resolverStats.itemDurationIconReuses end }
    mp[#mp + 1] = { name = "CDM_textureCycleCache", tbl = _textureCycleCache }
    local rb = resolverStats.resolveBy
    mp[#mp + 1] = { name = "CDM_resolveBy_spellID",           counter = true, fn = function() return rb.spellID end }
    mp[#mp + 1] = { name = "CDM_resolveBy_aura",              counter = true, fn = function() return rb.aura end }
    mp[#mp + 1] = { name = "CDM_resolveBy_usability",         counter = true, fn = function() return rb.usability end }
    mp[#mp + 1] = { name = "CDM_resolveBy_catalog",           counter = true, fn = function() return rb.catalog end }
    mp[#mp + 1] = { name = "CDM_resolveBy_walk",              counter = true, fn = function() return rb.walk end }
    mp[#mp + 1] = { name = "CDM_resolveBy_cooldownOnly",      counter = true, fn = function() return rb.cooldownOnly end }
    mp[#mp + 1] = { name = "CDM_resolveBy_other",             counter = true, fn = function() return rb.other end }
    mp[#mp + 1] = { name = "CDM_resolveBy_item",              counter = true, fn = function() return rb.item or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_auraScope",         counter = true, fn = function() return rb.auraScope or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_spellQueue",        counter = true, fn = function() return rb.spellQueue or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_expiry",            counter = true, fn = function() return rb.expiry or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_auraScopedCooldown",counter = true, fn = function() return rb.auraScopedCooldown or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_ownedBar",           counter = true, fn = function() return rb.ownedBar or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_typeRefresh",        counter = true, fn = function() return rb.typeRefresh or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_runtimeTypeRefresh", counter = true, fn = function() return rb.runtimeTypeRefresh or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_iconPlaced",         counter = true, fn = function() return rb.iconPlaced or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_rangeUsable",         counter = true, fn = function() return rb.rangeUsable or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_rangeTarget",         counter = true, fn = function() return rb.rangeTarget or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_rangeCheck",          counter = true, fn = function() return rb.rangeCheck or 0 end }
    mp[#mp + 1] = { name = "CDM_auraProbeHit",            counter = true, fn = function() return resolverStats.auraProbeHit end }
    mp[#mp + 1] = { name = "CDM_auraProbeGuardSkip",      counter = true, fn = function() return resolverStats.auraProbeGuardSkip end }
    mp[#mp + 1] = { name = "CDM_auraProbeExpensiveMiss",  counter = true, fn = function() return resolverStats.auraProbeExpensiveMiss end }
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_RuntimeEvents", frame = _runtimeFrame }
    markFn = ns.DebugIsolate and ns.DebugIsolate(ns.MemAuditProfilerMark)
        or ns.MemAuditProfilerMark
    CDMResolvers.SetResolveCallerTag = function(tag)
        currentResolveCallerTag = tag
    end
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

function CDMResolvers.GetSpellTexture(spellID)
    if not spellID then return nil end
    local cached = _textureCycleCache[spellID]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    local info
    if Sources and Sources.QuerySpellInfo then
        info = Sources.QuerySpellInfo(spellID)
    end
    local texID = info and info.iconID or nil
    _textureCycleCache[spellID] = texID or false
    return texID
end

function CDMResolvers.ResolveMacro(entry)
    local macroName = entry.macroName
    if not macroName then return nil, nil, nil end
    local macroIndex = GetMacroIndexByName(macroName)
    if not macroIndex or macroIndex == 0 then return nil, nil, nil end

    local spellID = GetMacroSpell(macroIndex)
    if spellID then
        return spellID, "spell", nil
    end

    local itemName, itemLink = GetMacroItem(macroIndex)
    if itemLink then
        local itemID
        if Sources and Sources.QueryItemInfoInstant then
            itemID = Sources.QueryItemInfoInstant(itemLink)
        end
        if itemID then
            return itemID, "item", nil
        end
    end

    local _, _, macroIcon = GetMacroInfo(macroIndex)
    return nil, nil, macroIcon
end

function CDMResolvers.GetEntryTexture(entry)
    if not entry then return nil end
    if entry.type == "macro" then
        local resolvedID, resolvedType, fallbackTex = CDMResolvers.ResolveMacro(entry)
        if resolvedID then
            if resolvedType == "item" then
                local _, _, _, _, icon
                if Sources and Sources.QueryItemInfoInstant then
                    _, _, _, _, icon = Sources.QueryItemInfoInstant(resolvedID)
                end
                return icon
            else
                return CDMResolvers.GetSpellTexture(resolvedID)
            end
        end
        return fallbackTex
    end
    if entry.type == "trinket" or entry.type == "slot" then
        local itemID = entry.itemID
        if not itemID and Sources and Sources.QueryInventoryItemID then
            itemID = Sources.QueryInventoryItemID("player", entry.id)
        end
        if itemID then
            local _, _, _, _, icon
            if Sources and Sources.QueryItemInfoInstant then
                _, _, _, _, icon = Sources.QueryItemInfoInstant(itemID)
            end
            return icon
        end
        return nil
    end
    if entry.type == "item" then
        local _, _, _, _, icon
        if Sources and Sources.QueryItemInfoInstant then
            local itemID = (Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
            _, _, _, _, icon = Sources.QueryItemInfoInstant(itemID)
        end
        return icon
    end
    if entry.type == "consumable" then
        local Catalog = ns.CDMCatalog
        local meta = Catalog and Catalog.GetConsumableCategoryMeta
            and Catalog.GetConsumableCategoryMeta(entry.id)
        return meta and meta.icon or nil
    end
    return CDMResolvers.GetSpellTexture(entry.overrideSpellID or entry.id)
end

local function GetCooldownInfoBoolean(info, key)
    if not info then
        return nil
    end
    local value = GetCooldownInfoField(info, key)
    return DecodePotentialSecretBoolean(value)
end

local function GetCurrentIsOnGCD(info, trustField)
    if trustField ~= true then return nil end
    return GetCooldownInfoBoolean(info, "isOnGCD")
end

local function QueryGCDDurationObject(spellID)
    local durObj = nil
    if spellID then
        durObj = QueryGCDDuration(spellID)
    end
    if not durObj and spellID ~= GCD_SPELL_ID then
        durObj = QueryGCDDuration(GCD_SPELL_ID)
    end
    return durObj
end

local function SpellMayHaveCharges(entry, spellID)
    if entry and (entry.hasCharges == true or entry.charges == true) then
        return true
    end
    if not spellID then
        return false
    end
    local gdb = QUI and QUI.db and QUI.db.global
    local svCharges = gdb and gdb.cdmChargeSpells
    return svCharges and svCharges[spellID] ~= nil or false
end

local function IsSupportedMirrorMode(mode)
    return mode == "aura"
        or mode == "cooldown"
        or mode == "item-cooldown"
        or mode == "gcd-only"
        or mode == "inactive"
end

function CDMResolvers.GetSpellCastInfo(spellID)
    if not spellID or not UnitCastingInfo then return false end
    local _, _, _, startMS, endMS, _, _, _, castSpellID = UnitCastingInfo("player")
    if ResolverIsSecretValue(castSpellID)
        or ResolverIsSecretValue(startMS)
        or ResolverIsSecretValue(endMS) then
        return nil -- @secret-policy: reject-secret-value
    end
    if castSpellID and castSpellID == spellID and startMS and endMS then
        return true, startMS / 1000, (endMS - startMS) / 1000, "cast"
    end
    return false
end

function CDMResolvers.GetSpellChannelInfo(spellID)
    if not spellID or not UnitChannelInfo then return false end
    local _, _, _, startMS, endMS, _, _, channelSpellID = UnitChannelInfo("player")
    if ResolverIsSecretValue(channelSpellID)
        or ResolverIsSecretValue(startMS)
        or ResolverIsSecretValue(endMS) then
        return nil -- @secret-policy: reject-secret-value
    end
    if channelSpellID and channelSpellID == spellID and startMS and endMS then
        return true, startMS / 1000, (endMS - startMS) / 1000, "channel"
    end
    return false
end

function CDMResolvers.GetSpellBuffInfo(spellID, icon, entry)
    if not spellID then return false end

    local scanner = QUI and QUI.SpellScanner
    if scanner and scanner.IsSpellActive then
        local active, expiration, duration = scanner.IsSpellActive(spellID)
        if active then
            if IsSafeNumeric(expiration) and IsSafeNumeric(duration) then
                return true, expiration - duration, duration, "buff"
            end
            return true, nil, nil, "buff"
        end
        if InCombatLockdown() then
            return false
        end
    elseif InCombatLockdown() then
        return false
    end

    if Sources and Sources.QueryPlayerAuraBySpellID then
        local auraData = Sources.QueryPlayerAuraBySpellID(spellID)
        if auraData then
            local expiration = auraData.expirationTime
            local duration = auraData.duration
            if IsSafeNumeric(expiration) and IsSafeNumeric(duration) then
                return true, expiration - duration, duration, "buff"
            end
            return true, nil, nil, "buff"
        end
    end

    if icon and icon._auraActive then
        return true, nil, nil, "buff"
    end

    return false
end

function CDMResolvers.ResolveSpellActiveState(spellID, icon, entry)
    if not spellID then return false end

    local active, start, duration, activeType = CDMResolvers.GetSpellCastInfo(spellID)
    if active then return active, start, duration, activeType end

    active, start, duration, activeType = CDMResolvers.GetSpellChannelInfo(spellID)
    if active then return active, start, duration, activeType end

    active, start, duration, activeType = CDMResolvers.GetSpellBuffInfo(spellID, icon, entry)
    if active then return active, start, duration, activeType end

    local overrideID = QueryOverrideSpell(spellID)
    if overrideID and overrideID ~= spellID then
        active, start, duration, activeType = CDMResolvers.GetSpellCastInfo(overrideID)
        if active then return active, start, duration, activeType end
        active, start, duration, activeType = CDMResolvers.GetSpellChannelInfo(overrideID)
        if active then return active, start, duration, activeType end
        active, start, duration, activeType = CDMResolvers.GetSpellBuffInfo(overrideID, icon, entry)
        if active then return active, start, duration, activeType end
    end

    return false
end

local function NewCooldownActivityState(entry)
    return {
        isOnCooldown = false,
        rechargeActive = false,
        hasChargesRemaining = false,
        hasCharges = entry and entry.hasCharges or false,
        gcdOnly = false,
    }
end

local function ApplyStoredCooldownActivityState(state, storedState)
    if not (state and storedState and storedState.mode) then
        return false
    end

    local mode = storedState.mode
    state.gcdOnly = storedState.gcdOnly == true or mode == "gcd-only"
    if storedState.hasCharges ~= nil then
        state.hasCharges = storedState.hasCharges == true
    end
    if mode == "charge" then
        state.hasCharges = true
    end

    if storedState.isOnCooldown ~= nil
       or storedState.rechargeActive ~= nil
       or storedState.hasChargesRemaining ~= nil then
        state.isOnCooldown = storedState.isOnCooldown == true
        state.rechargeActive = storedState.rechargeActive == true
        state.hasChargesRemaining = storedState.hasChargesRemaining == true
        return true
    end

    if mode == "charge" then
        state.rechargeActive = storedState.active == true
        state.isOnCooldown = storedState.active == true
        state.hasChargesRemaining = state.rechargeActive == true
            and state.isOnCooldown ~= true
        return true
    elseif mode == "cooldown" or mode == "item-cooldown" then
        state.isOnCooldown = storedState.active == true
        return true
    elseif mode == "gcd-only" or mode == "aura" or mode == "inactive" then
        return true
    end

    return false
end

local function ResolveActivityRuntimeSpellID(icon, entry)
    if icon and icon._runtimeSpellID then
        return icon._runtimeSpellID
    end
    if not entry then return nil, nil end

    if entry.type == "macro" then
        local resolvedID, resolvedType = CDMResolvers.ResolveMacro(entry)
        if resolvedType == "spell" then
            return resolvedID, resolvedType
        end
        return nil, resolvedType
    end

    return entry.spellID or entry.overrideSpellID or entry.id, nil
end

local function MarkKnownChargeSpell(state, spellID)
    if not (state and spellID) or state.hasCharges then return end
    local gdb = QUI and QUI.db and QUI.db.global
    local svCharges = gdb and gdb.cdmChargeSpells
    if svCharges and svCharges[spellID] then
        state.hasCharges = true
    end
end

local function ApplyResolvedCooldownActivityState(state, resolvedState)
    if not (state and resolvedState and resolvedState.mode) then
        return false
    end

    local mode = resolvedState.mode
    state.gcdOnly = resolvedState.gcdOnly == true or mode == "gcd-only"
    state.hasCharges = resolvedState.hasCharges == true
        or state.hasCharges == true
        or mode == "charge"

    if resolvedState.isOnCooldown ~= nil
        or resolvedState.rechargeActive ~= nil
        or resolvedState.hasChargesRemaining ~= nil then
        state.isOnCooldown = resolvedState.isOnCooldown == true
        state.rechargeActive = resolvedState.rechargeActive == true
        state.hasChargesRemaining = resolvedState.hasChargesRemaining == true
        return true
    elseif mode == "cooldown" or mode == "item-cooldown" then
        state.isOnCooldown = resolvedState.active == true
        return true
    elseif mode == "charge" then
        state.rechargeActive = resolvedState.active == true
            or resolvedState.isActive == true
        state.isOnCooldown = resolvedState.active == true
        state.hasChargesRemaining = state.rechargeActive == true
            and state.isOnCooldown ~= true
        return true
    elseif mode == "gcd-only" or mode == "aura" or mode == "inactive" then
        return true
    end

    return false
end

function CDMResolvers.ResolveCooldownActivityStateFromResolvedState(entry, resolvedState)
    local state = NewCooldownActivityState(entry)
    if ApplyResolvedCooldownActivityState(state, resolvedState) then
        return state
    end
    return nil
end

local _activityCooldownStateContextOptions = {
    contextKey = "_activityCooldownStateContext",
}

local function BuildActivityCooldownStateContext(icon, entry, containerDB, spellID, runtimeOptions)
    if not (icon and entry) then return nil end

    local options = _activityCooldownStateContextOptions
    options.containerKey = (containerDB and containerDB.viewerType) or entry.viewerType
    options.totemSlot = icon._totemSlot
    options.useBuffSwipe = runtimeOptions and runtimeOptions.useBuffSwipe
    options.skipAuraPhase = runtimeOptions and runtimeOptions.skipAuraPhase == true
    options.showGCDSwipe = runtimeOptions and runtimeOptions.showGCDSwipe == true

    return CDMResolvers.BuildCooldownStateContext(icon, entry, spellID, options)
end

local function ApplyChargeRuntimeFallback(state, entry, spellID, isItemLike)
    if not (state and spellID) or isItemLike then
        return
    end
    if InCombatLockdown and InCombatLockdown()
        and not SpellMayHaveCharges(entry, spellID) then
        return
    end

    local ci = QueryCharges(spellID)
    if ci then
        local maxC = ci.maxCharges
        if IsSafeNumeric(maxC) and maxC >= 1 then
            state.hasCharges = true
        end
    end

    if not state.hasCharges then
        return
    end

    local cdInfo = QueryCooldown(spellID)
    local cooldownActive = cdInfo and IsCooldownInfoActive(cdInfo)
    if cooldownActive == true then
        state.rechargeActive = true
        state.isOnCooldown = true
        return
    elseif cooldownActive == false then
        state.hasChargesRemaining = true
        state.isOnCooldown = false
    end

    if ci then
        local chargeActive = DecodePotentialSecretBoolean(ci.isActive)
        if chargeActive == true then
            state.rechargeActive = true
        end
    end
end

local function ResolveCooldownActivityStateCore(icon, entry, containerDB, now, runtimeOptions)
    local state = NewCooldownActivityState(entry)
    if not icon or not entry then return state end

    now = now or GetTime()
    local runtimeStore = ns.CDMRuntimeStore
    local storedState = runtimeStore and runtimeStore.GetFrameState
        and runtimeStore.GetFrameState(icon)
    if ApplyStoredCooldownActivityState(state, storedState) then
        return state
    end

    local spellID, macroResolvedType = ResolveActivityRuntimeSpellID(icon, entry)
    local isItemLike = IsItemLikeEntry(entry)
        or (entry.type == "macro" and macroResolvedType == "item")

    MarkKnownChargeSpell(state, spellID)

    local resolver = CDMResolvers.ResolveCooldownState
    if resolver then
        local resolvedState = resolver(BuildActivityCooldownStateContext(icon, entry, containerDB, spellID, runtimeOptions))
        if ApplyResolvedCooldownActivityState(state, resolvedState) then
            return state
        end
    end

    ApplyChargeRuntimeFallback(state, entry, spellID, isItemLike)

    return state
end

function CDMResolvers.ResolveCooldownActivityState(icon, entry, containerDB, now, runtimeOptions)
    return ResolveCooldownActivityStateCore(icon, entry, containerDB, now, runtimeOptions)
end

function CDMResolvers.IsAuraEntry(entry)
    if not entry then return false end
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.IsAuraEntry then
        return CDMSpellData.IsAuraEntry(entry, entry.viewerType)
    end
    if entry.kind == "aura" then return true end
    if entry.kind == "cooldown" then return false end
    local vt = entry.viewerType
    return vt == "buff" or vt == "trackedBar"
end

local _auraActiveLookupIDs = {}
local _auraActiveSeenLookup = {}
local _auraActiveQuerySeen = {}

local function _AuraActiveAddLookup(id)
    if not id or _auraActiveSeenLookup[id] then return end
    _auraActiveSeenLookup[id] = true
    _auraActiveLookupIDs[#_auraActiveLookupIDs + 1] = id
end

local function _AuraActiveAddMappedLookups(CDMSpellData, id)
    if not (id and CDMSpellData.GetAuraIDsForSpell) then return end
    local mappedIDs = CDMSpellData:GetAuraIDsForSpell(id)
    if mappedIDs then
        for _, auraID in ipairs(mappedIDs) do _AuraActiveAddLookup(auraID) end
    end
end

local function _AuraActiveTryQuery(id)
    if not id or _auraActiveQuerySeen[id] then return nil end
    _auraActiveQuerySeen[id] = true
    if Sources.QueryUnitAuraBySpellID then
        local auraData = Sources.QueryUnitAuraBySpellID("player", id)
        if auraData then return auraData end
    end
    if Sources.QueryPlayerAuraBySpellID then
        local auraData = Sources.QueryPlayerAuraBySpellID(id)
        if auraData then return auraData end
    end
    return nil
end

local function _AuraActiveTryMappedIDs(CDMSpellData, id)
    if not id then return false end
    local mappedIDs = CDMSpellData:GetAuraIDsForSpell(id)
    if mappedIDs then
        for _, auraID in ipairs(mappedIDs) do
            local mappedAuraData = _AuraActiveTryQuery(auraID)
            if mappedAuraData then
                return true, "player", GetAuraDataInstanceID(mappedAuraData)
            end
        end
    end
    return false
end

function CDMResolvers.ResolveAuraActiveState(entry)
    if not entry then return false, nil, nil end

    local sid = entry.overrideSpellID or entry.spellID or entry.id
    if not sid then
        return false, nil, nil
    end

    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.GetCapturedAuraForLookup then
        wipe(_auraActiveLookupIDs)
        wipe(_auraActiveSeenLookup)
        _AuraActiveAddLookup(sid)
        _AuraActiveAddLookup(entry.spellID)
        _AuraActiveAddLookup(entry.id)
        _AuraActiveAddMappedLookups(CDMSpellData, sid)
        _AuraActiveAddMappedLookups(CDMSpellData, entry.spellID)
        _AuraActiveAddMappedLookups(CDMSpellData, entry.id)
        local captured = CDMSpellData.GetCapturedAuraForLookup(_auraActiveLookupIDs, entry.name)
        local auraInstanceID = captured and captured.auraInstanceID
        if captured and HasOpaqueValue(auraInstanceID) then
            return true, captured.unit or "player", auraInstanceID
        end
    end

    if Sources and (Sources.QueryUnitAuraBySpellID or Sources.QueryPlayerAuraBySpellID) then
        wipe(_auraActiveQuerySeen)

        local auraData = _AuraActiveTryQuery(sid)
        if auraData then return true, "player", GetAuraDataInstanceID(auraData) end
        auraData = _AuraActiveTryQuery(entry.spellID)
        if auraData then return true, "player", GetAuraDataInstanceID(auraData) end
        auraData = _AuraActiveTryQuery(entry.id)
        if auraData then return true, "player", GetAuraDataInstanceID(auraData) end

        if CDMSpellData and CDMSpellData.GetAuraIDsForSpell then
            local active, unit, instID = _AuraActiveTryMappedIDs(CDMSpellData, sid)
            if active then return active, unit, instID end
            active, unit, instID = _AuraActiveTryMappedIDs(CDMSpellData, entry.spellID)
            if active then return active, unit, instID end
            active, unit, instID = _AuraActiveTryMappedIDs(CDMSpellData, entry.id)
            if active then return active, unit, instID end
        end
    end

    if entry.name and entry.name ~= ""
        and Sources and Sources.QueryAuraDataBySpellName then
        local auraData = Sources.QueryAuraDataBySpellName("player", entry.name, "HELPFUL")
        if auraData then
            return true, "player", GetAuraDataInstanceID(auraData)
        end
    end

    return false, nil, nil
end

local PLAYER_AURA_CAPTURE_LOOKUP_UNITS = { "player", "pet" }

local _capturedDurLookupIDs = {}
local _capturedDurSeen = {}

local function _CapturedDurAddLookup(id)
    if ResolverIsSecretValue(id) then return end
    if id == nil then return end
    local idType = type(id)
    if idType ~= "number" and idType ~= "string" then return end
    if _capturedDurSeen[id] then return end
    _capturedDurSeen[id] = true
    _capturedDurLookupIDs[#_capturedDurLookupIDs + 1] = id
end

local function _CapturedDurAddCooldownAuraLookup(id)
    if ResolverIsSecretValue(id) or id == nil then return end
    if not (Sources and Sources.QueryCooldownAuraBySpellID) then return end
    _CapturedDurAddLookup(Sources.QueryCooldownAuraBySpellID(id))
end

local function QueryCapturedPlayerAuraDuration(spellID, name)
    if not InCombatLockdown()
       or not (Sources and Sources.QueryAuraDuration) then
        return nil
    end

    local CDMSpellData = ns.CDMSpellData
    if not (CDMSpellData and CDMSpellData.GetCapturedAuraForLookup) then
        return nil
    end

    wipe(_capturedDurLookupIDs)
    wipe(_capturedDurSeen)

    if CDMSpellData.GetAuraIDsForSpell and spellID then
        local catalogIDs = CDMSpellData:GetAuraIDsForSpell(spellID)
        if catalogIDs then
            for _, auraID in ipairs(catalogIDs) do
                _CapturedDurAddLookup(auraID)
            end
        end
    end
    _CapturedDurAddCooldownAuraLookup(spellID)
    _CapturedDurAddLookup(spellID)

    local captured = CDMSpellData.GetCapturedAuraForLookup(
        _capturedDurLookupIDs, name, PLAYER_AURA_CAPTURE_LOOKUP_UNITS, false)
    local auraInstanceID = captured and captured.auraInstanceID
    if not HasOpaqueValue(auraInstanceID) then
        return nil
    end

    local auraUnit = captured.unit or "player"
    return Sources.QueryAuraDuration(auraUnit, auraInstanceID),
        captured.spellID,
        auraInstanceID,
        auraUnit
end

local function QueryPlayerAuraDurationBySpellID(rawSpellID, name)
    if not rawSpellID or not (Sources and Sources.QueryAuraDuration) then
        return nil
    end

    local capturedDurObj, capturedAuraSpellID, capturedAuraInstanceID, capturedAuraUnit =
        QueryCapturedPlayerAuraDuration(rawSpellID, name)
    if capturedDurObj then
        return capturedDurObj, capturedAuraSpellID, capturedAuraInstanceID, capturedAuraUnit
    end

    local function queryAuraData(auraSpellID)
        if ResolverIsSecretValue(auraSpellID) or auraSpellID == nil then return nil end
        if Sources.QueryUnitAuraBySpellID then
            local auraData = Sources.QueryUnitAuraBySpellID("player", auraSpellID)
            if auraData then return auraData end
        end
        if Sources.QueryPlayerAuraBySpellID then
            local auraData = Sources.QueryPlayerAuraBySpellID(auraSpellID)
            if auraData then return auraData end
        end
        if Sources.QueryAuraDataBySpellID then
            local auraData = Sources.QueryAuraDataBySpellID("player", auraSpellID, "HELPFUL")
            if auraData then return auraData end
        end
        return nil
    end

    local function queryDuration(auraSpellID)
        local auraData = queryAuraData(auraSpellID)
        local auraInstanceID = GetAuraDataInstanceID(auraData)
        if not HasOpaqueValue(auraInstanceID) then return nil end

        return Sources.QueryAuraDuration("player", auraInstanceID), auraSpellID, auraInstanceID, "player"
    end

    if Sources.QueryCooldownAuraBySpellID then
        local auraSpellID = Sources.QueryCooldownAuraBySpellID(rawSpellID)
        if not ResolverIsSecretValue(auraSpellID) and auraSpellID ~= nil then
            local durObj, resolvedAuraSpellID, auraInstanceID, auraUnit = queryDuration(auraSpellID)
            if durObj then
                return durObj, resolvedAuraSpellID, auraInstanceID, auraUnit
            end
        end
    end

    return queryDuration(rawSpellID)
end

local function QueryPlayerAuraDurationByName(name)
    if type(name) ~= "string"
       or name == ""
       or not (Sources and Sources.QueryAuraDuration) then
        return nil
    end

    local capturedDurObj, _, capturedAuraInstanceID, capturedAuraUnit =
        QueryCapturedPlayerAuraDuration(nil, name)
    if capturedDurObj then
        return capturedDurObj, capturedAuraInstanceID, capturedAuraUnit
    end

    if not Sources.QueryAuraDataBySpellName then
        return nil
    end

    local auraData = Sources.QueryAuraDataBySpellName("player", name, "HELPFUL")
    if not auraData then
        return nil
    end

    local auraInstanceID = GetAuraDataInstanceID(auraData)
    if not HasOpaqueValue(auraInstanceID) then return nil end

    return Sources.QueryAuraDuration("player", auraInstanceID), auraInstanceID, "player"
end

local function ClearCooldownStateContext(context)
    context.owner = nil
    context.entry = nil
    context.runtimeSpellID = nil
    context.containerKey = nil
    context.totemSlot = nil
    context.useBuffSwipe = nil
    context.skipAuraPhase = nil
    context.showGCDSwipe = nil
    context.trustIsOnGCD = nil
    context.lastChargeRuntimeSpellID = nil
end

function CDMResolvers.BuildCooldownStateContext(owner, entry, runtimeSpellID, options)
    local context = options and options.context
    local contextKey = options and options.contextKey or "_cooldownStateContext"
    if not context and owner then
        context = owner[contextKey]
        if not context then
            context = {}
            owner[contextKey] = context
        end
    end
    if not context then
        context = {}
    end

    ClearCooldownStateContext(context)

    local containerKey = options and options.containerKey
    if containerKey == nil then
        containerKey = entry and entry.viewerType
    end
    if containerKey == nil and options then
        containerKey = options.fallbackContainerKey
    end

    local totemSlot = options and options.totemSlot
    if totemSlot == nil and owner then
        totemSlot = owner._totemSlot
    end

    context.entry = entry
    context.owner = owner
    context.runtimeSpellID = runtimeSpellID
    context.containerKey = containerKey
    context.totemSlot = totemSlot
    context.useBuffSwipe = options and options.useBuffSwipe
    context.skipAuraPhase = options and options.skipAuraPhase == true
    context.showGCDSwipe = options and options.showGCDSwipe == true
    context.trustIsOnGCD = options and options.trustIsOnGCD == true
    context.lastChargeRuntimeSpellID = options and options.lastChargeRuntimeSpellID
    return context
end

local function HasActiveChargeRecharge(spellID, mayHaveCharges)
    if not spellID then return false end
    if ResolverIsSecretValue(spellID) then return false end -- @secret-policy: reject-secret-value
    if InCombatLockdown and InCombatLockdown() and not mayHaveCharges then
        local gdb = QUI and QUI.db and QUI.db.global
        local svCharges = gdb and gdb.cdmChargeSpells
        if not (svCharges and svCharges[spellID]) then
            return false
        end
    end
    local chargeInfo = QueryCharges(spellID)
    if not chargeInfo then return false end
    local maxCharges = chargeInfo.maxCharges
    if not (IsSafeNumeric(maxCharges) and maxCharges > 1) then return false end
    return DecodePotentialSecretBoolean(chargeInfo.isActive) == true
end

local QueryItemCooldown
local QuerySlotCooldown

local function BuildDurationObjectFromStart(startTime, duration)
    if ResolverIsSecretValue(startTime) or ResolverIsSecretValue(duration) then
        return nil -- @secret-policy: reject-secret-value
    end
    if startTime == nil or duration == nil then return nil end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end

    local okCreate, durObj = pcall(C_DurationUtil.CreateDuration)
    if not okCreate or not durObj or not durObj.SetTimeFromStart then
        return nil
    end

    local okSet = pcall(durObj.SetTimeFromStart, durObj, startTime, duration)
    if okSet then return durObj end
    return nil
end

local function BuildItemDurationSourceID(icon, keySource)
    if not icon then
        return "item-duration:" .. tostring(keySource)
    end
    if icon._itemDurSourceKey == keySource and icon._itemDurSourceID then
        return icon._itemDurSourceID
    end
    local sourceID = "item-duration:" .. tostring(keySource)
    icon._itemDurSourceKey = keySource
    icon._itemDurSourceID = sourceID
    return sourceID
end

local function GetIconItemDurationObject(icon, sourceID, startTime, duration)
    if not icon then return nil end
    if ResolverIsSecretValue(startTime) or ResolverIsSecretValue(duration) then
        return nil -- @secret-policy: reject-secret-value
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) then
        return nil
    end

    local state = icon._cdmRuntimeState
    if not state or state.mode ~= "item-cooldown" or state.sourceID ~= sourceID then
        return nil
    end

    local priorStart = state.start
    local priorDuration = state.duration
    if ResolverIsSecretValue(priorStart) or ResolverIsSecretValue(priorDuration) then
        return nil -- @secret-policy: reject-secret-value
    end
    if priorStart ~= startTime or priorDuration ~= duration then
        return nil
    end

    local durObj = state.durObj or icon._lastDurObj
    if durObj then
        if resolverStats then resolverStats.itemDurationIconReuses = resolverStats.itemDurationIconReuses + 1 end
        return durObj
    end
    return nil
end

local function BuildIconItemDurationObject(icon, keySource, startTime, duration)
    local sourceID = BuildItemDurationSourceID(icon, keySource)
    local durObj = GetIconItemDurationObject(icon, sourceID, startTime, duration)
    if durObj then
        return durObj, sourceID
    end
    return BuildDurationObjectFromStart(startTime, duration), sourceID
end

local function CleanItemCooldownIsDisabled(enabled, requireEnabledOne)
    if ResolverIsSecretValue(enabled) then
        return false -- @secret-policy: reject-secret-value
    end
    if enabled == 0 or enabled == false then
        return true
    end
    if requireEnabledOne
        and enabled ~= nil
        and enabled ~= 1
        and enabled ~= true then
        return true
    end
    return false
end

local function CleanItemCooldownIsInactive(startTime, duration, enabled, requireEnabledOne)
    if CleanItemCooldownIsDisabled(enabled, requireEnabledOne) then
        return true
    end
    if ResolverIsSecretValue(startTime) or ResolverIsSecretValue(duration) then
        return false -- @secret-policy: reject-secret-value
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) then
        return true
    end
    if startTime <= 0 then
        return true
    end
    if duration <= GCD_MAX_DURATION then
        return true
    end
    if (startTime + duration) <= GetTime() then
        return true
    end
    return false
end

local function CleanItemCooldownIsActive(startTime, duration, enabled, requireEnabledOne)
    if CleanItemCooldownIsDisabled(enabled, requireEnabledOne) then
        return false
    end
    if ResolverIsSecretValue(startTime) or ResolverIsSecretValue(duration) then
        return false -- @secret-policy: reject-secret-value
    end
    return IsSafeNumeric(startTime)
        and IsSafeNumeric(duration)
        and startTime > 0
        and duration > GCD_MAX_DURATION
        and (startTime + duration) > GetTime()
end

local function HasItemCooldownTiming(startTime, duration, enabled)
    return startTime ~= nil or duration ~= nil or enabled ~= nil
end

local function ResolveItemDurationObjectForIcon(icon, entry)
    local itemID, slotID, itemSpellID, keySource = ResolveItemCooldownIdentity(entry)
    if not itemID then return nil, "inactive", nil, nil, nil, nil end

    local startTime, duration, enabled
    local requireEnabledOne = slotID ~= nil
    local itemCooldownKnown = false
    if slotID then
        startTime, duration, enabled = QuerySlotCooldown(slotID)
        itemCooldownKnown = HasItemCooldownTiming(startTime, duration, enabled)
        if CleanItemCooldownIsInactive(startTime, duration, enabled, true) then
            local itemStart, itemDuration, itemEnabled = QueryItemCooldown(itemID)
            itemCooldownKnown = itemCooldownKnown or HasItemCooldownTiming(itemStart, itemDuration, itemEnabled)
            if not CleanItemCooldownIsInactive(itemStart, itemDuration, itemEnabled, false) then
                startTime = itemStart
                duration = itemDuration
                enabled = itemEnabled
                requireEnabledOne = false
            end
        end
    else
        startTime, duration, enabled = QueryItemCooldown(itemID)
        itemCooldownKnown = HasItemCooldownTiming(startTime, duration, enabled)
    end

    if not CleanItemCooldownIsInactive(startTime, duration, enabled, requireEnabledOne) then
        local cleanNumericActive = CleanItemCooldownIsActive(startTime, duration, enabled, requireEnabledOne)
        local itemDurObj, itemDurationSourceID =
            BuildIconItemDurationObject(icon, keySource, startTime, duration)
        if itemDurObj then
            return itemDurObj, "item-cooldown",
                itemDurationSourceID,
                cleanNumericActive and startTime or nil,
                cleanNumericActive and duration or nil,
                itemSpellID
        end

        if cleanNumericActive then
            return nil, "item-cooldown",
                "item:" .. tostring(keySource) .. ":" .. tostring(startTime) .. ":" .. tostring(duration),
                startTime, duration, itemSpellID
        end
    elseif itemCooldownKnown then
        return nil, "inactive", nil, nil, nil, itemSpellID
    end

    if itemSpellID then
        local cdInfo = QueryCooldown(itemSpellID)
        local cdInfoActive = cdInfo and IsCooldownInfoActive(cdInfo)
        if cdInfoActive ~= false and GetCurrentIsOnGCD(cdInfo) ~= true then
            local durObj = QueryDuration(itemSpellID)
            if durObj then
                return durObj, "item-cooldown",
                    "spell:" .. tostring(itemSpellID) .. ":" .. tostring(keySource),
                    nil, nil, itemSpellID
            end
        end
    end

    return nil, "inactive", nil, nil, nil, itemSpellID
end

QueryItemCooldown = function(itemID)
    if not itemID or not (Sources and Sources.QueryItemCooldown) then
        return nil, nil, nil
    end
    local startTime, duration, enabled = Sources.QueryItemCooldown(itemID)
    if ResolverIsSecretValue(startTime)
        or ResolverIsSecretValue(duration)
        or ResolverIsSecretValue(enabled) then
        return nil, nil, nil -- @secret-policy: reject-secret-value
    end
    return startTime, duration, enabled
end

local _GetInventoryItemCooldown = GetInventoryItemCooldown

QuerySlotCooldown = function(slotID)
    if not slotID or not _GetInventoryItemCooldown then
        return nil, nil, nil
    end
    local startTime, duration, enabled = _GetInventoryItemCooldown("player", slotID)
    if ResolverIsSecretValue(startTime)
        or ResolverIsSecretValue(duration)
        or ResolverIsSecretValue(enabled) then
        return nil, nil, nil -- @secret-policy: reject-secret-value
    end
    return startTime, duration, enabled
end

function CDMResolvers.BuildEntryItemDurationObject(entry)
    local durObj, mode, _, startTime, duration = ResolveItemDurationObjectForIcon(nil, entry)
    if mode ~= "item-cooldown" then return nil end
    if durObj then return durObj end
    return BuildDurationObjectFromStart(startTime, duration)
end

local _cooldownStateCountScratch = {
    value = nil,
    sinkText = nil,
    shown = false,
    source = nil,
}

local _cooldownStateScratch = {
    mode = "inactive",
    active = false,
    isActive = false,
    spellID = nil,
    sourceID = nil,
    durObj = nil,
    start = nil,
    duration = nil,
    state = nil,
    cooldownID = nil,
    category = nil,
    auraInstanceID = nil,
    auraUnit = nil,
    auraData = nil,
    resolvedAuraSpellID = nil,
    hasExpirationTime = nil,
    hideDurationText = nil,
    durationStateUnknown = nil,
    countValue = nil,
    countSinkText = nil,
    countShown = false,
    countSource = nil,
    count = _cooldownStateCountScratch,
    totemSlot = nil,
    totemName = nil,
    totemIcon = nil,
    isTotemInstance = false,
    numericCooldownActive = nil,
    auraResolved = nil,
    auraActive = nil,
    auraIsActive = nil,
    isOnCooldown = false,
    rechargeActive = false,
    hasCharges = false,
    hasChargesRemaining = false,
    gcdOnly = false,
    isGCDOnly = false,
    isAuraMode = false,
    isRealCooldownMode = false,
    hasDurationObject = false,
    hasRenderableCooldown = false,
    cooldownInfo = nil,
    cooldownInfoActive = nil,
    cooldownInfoOnGCD = nil,
}

local function WipeCooldownState()
    local s = _cooldownStateScratch
    s.mode = "inactive"
    s.active = false
    s.isActive = false
    s.spellID = nil
    s.sourceID = nil
    s.durObj = nil
    s.start = nil
    s.duration = nil
    s.state = nil
    s.cooldownID = nil
    s.category = nil
    s.auraInstanceID = nil
    s.auraUnit = nil
    s.auraData = nil
    s.resolvedAuraSpellID = nil
    s.hasExpirationTime = nil
    s.hideDurationText = nil
    s.durationStateUnknown = nil
    s.countValue = nil
    s.countSinkText = nil
    s.countShown = false
    s.countSource = nil
    s.totemSlot = nil
    s.totemName = nil
    s.totemIcon = nil
    s.isTotemInstance = false
    s.numericCooldownActive = nil
    s.auraResolved = nil
    s.auraActive = nil
    s.auraIsActive = nil
    s.isOnCooldown = false
    s.rechargeActive = false
    s.hasCharges = false
    s.hasChargesRemaining = false
    s.gcdOnly = false
    s.isGCDOnly = false
    s.isAuraMode = false
    s.isRealCooldownMode = false
    s.hasDurationObject = false
    s.hasRenderableCooldown = false
    s.cooldownInfo = nil
    s.cooldownInfoActive = nil
    s.cooldownInfoOnGCD = nil

    local c = _cooldownStateCountScratch
    c.value = nil
    c.sinkText = nil
    c.shown = false
    c.source = nil
    s.count = c
    return s
end

local function SetCooldownStateActivity(state, active)
    active = active == true
    state.active = active
    state.isActive = active
end

local function CopyCountFactsToState(state, count)
    local c = _cooldownStateCountScratch
    if count then
        c.value = count.value
        c.sinkText = count.sinkText
        c.shown = count.shown == true
        c.source = count.source
    else
        c.value = nil
        c.sinkText = nil
        c.shown = false
        c.source = nil
    end
    state.count = c
    state.countValue = c.value
    state.countSinkText = c.sinkText
    state.countShown = c.shown
    state.countSource = c.source
end

local function CopyAuraFactsToState(state, aura)
    if not aura then return end
    local auraActive = aura.isActive == true
    state.auraResolved = true
    state.auraActive = auraActive
    state.auraIsActive = auraActive
    state.auraInstanceID = aura.auraInstanceID
    state.auraUnit = aura.auraUnit
    state.auraData = aura.auraData
    state.resolvedAuraSpellID = aura.resolvedAuraSpellID or state.spellID
    state.hasExpirationTime = aura.hasExpirationTime
    state.hideDurationText = aura.hideDurationText
    state.durationStateUnknown = aura.durationStateUnknown
    state.totemSlot = aura.totemSlot
    state.totemName = aura.totemName
    state.totemIcon = aura.totemIcon
    state.isTotemInstance = aura.isTotemInstance and true or false
    CopyCountFactsToState(state, aura.count)
end

local function GetAuraStateSourceID(aura, fallbackID)
    if not aura then return fallbackID end
    return aura.auraInstanceID or aura.totemSlot or fallbackID
end

local _cooldownStateAuraParams = {}

local function ResolveAuraRuntimeStateForContext(context, entry, sid, entryIsAura)
    local AuraRuntime = ns.CDMAuraRuntime
    if not (context and entry and sid) then
        return nil
    end
    if not entryIsAura and (context.useBuffSwipe == false or context.skipAuraPhase == true) then
        return nil
    end

    local p = _cooldownStateAuraParams
    p.spellID = sid
    p.entrySpellID = entry.spellID
    p.entryID = entry.id
    p.entryName = entry.name
    p.entryKind = entry.kind
    p.entryType = entry.type
    p.entryLinkedSpellID = entry.linkedSpellID
    p.entryLinkedSpellIDs = entry.linkedSpellIDs
    p.entryIsAura = entryIsAura
    p.entryTexture = CDMResolvers.GetEntryTexture(entry)
    p.viewerType = context.containerKey or entry.viewerType
    p.totemSlot = context.totemSlot
    p.disableLooseVisibilityFallback = true

    if AuraRuntime and AuraRuntime.ResolveState then
        local aura = AuraRuntime.ResolveState(p)
        if aura then
            return aura
        end
    end
    return nil
end

local function ApplyAuraStateToCooldownState(state, aura, fallbackSpellID)
    CopyAuraFactsToState(state, aura)
    if not (aura and aura.isActive) then
        return false
    end
    state.mode = "aura"
    SetCooldownStateActivity(state, true)
    state.durObj = aura.durObj
    state.sourceID = GetAuraStateSourceID(aura, fallbackSpellID)
    state.spellID = aura.resolvedAuraSpellID or fallbackSpellID
    if aura.isActive and aura.hasExpirationTime == nil and not aura.durObj then
        state.hasExpirationTime = false
        state.hideDurationText = true
    end
    return true
end

local function ApplyCleanItemAuraTiming(state, itemID, spellID, resolvedAuraSpellID, auraUnit, auraInstanceID,
                                        expiration, duration, sourceSuffix)
    if ResolverIsSecretValue(expiration) or ResolverIsSecretValue(duration) then
        return false -- @secret-policy: reject-secret-value
    end
    if not (IsSafeNumeric(expiration) and IsSafeNumeric(duration)) then
        return false
    end
    if duration <= 0 or expiration <= GetTime() then
        return false
    end

    state.mode = "aura"
    SetCooldownStateActivity(state, true)
    state.start = expiration - duration
    state.duration = duration
    state.sourceID = "item-aura-" .. tostring(sourceSuffix or "scanner") .. ":" .. tostring(itemID)
    state.spellID = spellID
    state.auraResolved = true
    state.auraActive = true
    state.auraIsActive = true
    state.auraUnit = auraUnit or "player"
    state.auraInstanceID = CleanOpaqueValue(auraInstanceID)
    state.hasAuraInstanceID = HasOpaqueValue(auraInstanceID)
    state.resolvedAuraSpellID = resolvedAuraSpellID or spellID
    return true
end

local function ResolveItemAuraForContext(state, context, entry, itemID, itemSpellID)
    if not (context and entry and itemID) then
        return false
    end

    local function trySpellID(rawSpellID, sourceKey)
        local durObj, resolvedAuraSpellID, auraInstanceID, auraUnit =
            QueryPlayerAuraDurationBySpellID(rawSpellID, entry.name)
        if durObj then
            local cleanAuraInstanceID = CleanOpaqueValue(auraInstanceID)
            state.mode = "aura"
            SetCooldownStateActivity(state, true)
            state.durObj = durObj
            state.sourceID = "item-aura-spell:" .. tostring(itemID) .. ":" .. sourceKey
            state.spellID = rawSpellID
            state.auraResolved = true
            state.auraActive = true
            state.auraIsActive = true
            state.auraUnit = auraUnit or "player"
            state.auraInstanceID = cleanAuraInstanceID
            state.hasAuraInstanceID = HasOpaqueValue(auraInstanceID)
            state.resolvedAuraSpellID = resolvedAuraSpellID or rawSpellID
            return true
        end
        return false
    end

    local rawItemSpellID = QueryItemUseSpellID(itemID)
    if trySpellID(rawItemSpellID, "raw-use") then return true end
    if trySpellID(itemSpellID, "use") then return true end

    if Sources and Sources.QueryScannedItemAuraInfo then
        local scanned = Sources.QueryScannedItemAuraInfo(itemID, itemSpellID or rawItemSpellID)
        if scanned then
            local auraInstanceID = scanned.auraInstanceID
            if HasOpaqueValue(auraInstanceID) and Sources.QueryAuraDuration then
                local auraUnit = scanned.auraUnit or "player"
                local durObj = Sources.QueryAuraDuration(auraUnit, auraInstanceID)
                if durObj then
                    local cleanAuraInstanceID = CleanOpaqueValue(auraInstanceID)
                    state.mode = "aura"
                    SetCooldownStateActivity(state, true)
                    state.durObj = durObj
                    state.sourceID = cleanAuraInstanceID
                        and ("item-aura-instance:" .. tostring(itemID) .. ":" .. tostring(cleanAuraInstanceID))
                        or ("item-aura-instance:" .. tostring(itemID))
                    state.spellID = scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID
                    state.auraResolved = true
                    state.auraActive = true
                    state.auraIsActive = true
                    state.auraUnit = auraUnit
                    state.auraInstanceID = cleanAuraInstanceID
                    state.hasAuraInstanceID = true
                    state.resolvedAuraSpellID = scanned.buffSpellID or scanned.useSpellID or state.spellID
                    return true
                end
                if Sources.QueryAuraDataByAuraInstanceID then
                    local auraData = Sources.QueryAuraDataByAuraInstanceID(auraUnit, auraInstanceID)
                    if auraData and ApplyCleanItemAuraTiming(
                        state,
                        itemID,
                        scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID,
                        scanned.buffSpellID or scanned.useSpellID,
                        auraUnit,
                        auraInstanceID,
                        auraData.expirationTime,
                        auraData.duration,
                        "aura-data") then
                        return true
                    end
                end
            end
            if trySpellID(scanned.buffSpellID, "scanner-buff") then return true end
            if trySpellID(scanned.useSpellID, "scanner-use") then return true end
            if trySpellID(scanned.sourceSpellID, "scanner-source") then return true end
            local scannedActive = scanned.active
            if ResolverIsSecretValue(scannedActive) then
                scannedActive = nil
            end
            if scannedActive == true then
                local expiration = scanned.expiration
                local duration = scanned.duration
                local scannedSpellID = scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID
                if ApplyCleanItemAuraTiming(
                    state,
                    itemID,
                    scannedSpellID,
                    scanned.buffSpellID or scanned.useSpellID or scannedSpellID,
                    scanned.auraUnit or "player",
                    scanned.auraInstanceID,
                    expiration,
                    duration,
                    "scanner") then
                    return true
                end

                state.mode = "aura"
                SetCooldownStateActivity(state, true)
                state.sourceID = "item-aura-scanner:" .. tostring(itemID)
                state.spellID = scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID
                state.auraResolved = true
                state.auraActive = true
                state.auraIsActive = true
                state.auraUnit = scanned.auraUnit or "player"
                state.auraInstanceID = CleanOpaqueValue(scanned.auraInstanceID)
                state.hasAuraInstanceID = HasOpaqueValue(scanned.auraInstanceID)
                state.resolvedAuraSpellID = scanned.buffSpellID or scanned.useSpellID or state.spellID
                state.hasExpirationTime = false
                state.hideDurationText = true
                return true
            end
        end
    end

    if trySpellID(entry.spellID, "entry") then return true end
    if trySpellID(entry.overrideSpellID, "override") then return true end
    if trySpellID(entry.id, "id") then return true end

    local durObj, auraInstanceID, auraUnit = QueryPlayerAuraDurationByName(entry.name)
    if durObj then
        local cleanAuraInstanceID = CleanOpaqueValue(auraInstanceID)
        state.mode = "aura"
        SetCooldownStateActivity(state, true)
        state.durObj = durObj
        state.sourceID = "item-aura-name:" .. tostring(itemID)
        state.auraResolved = true
        state.auraActive = true
        state.auraIsActive = true
        state.auraUnit = auraUnit or "player"
        state.auraInstanceID = cleanAuraInstanceID
        state.hasAuraInstanceID = HasOpaqueValue(auraInstanceID)
        state.resolvedAuraSpellID = itemSpellID
        state.spellID = itemSpellID
        return true
    end

    return false
end

local function IsRealCooldownDurationMode(mode)
    return mode == "cooldown"
        or mode == "charge"
        or mode == "item-cooldown"
end

local function HasDurationObject(value)
    if ResolverIsSecretValue(value) then
        return true -- @secret-policy: opaque-value-present
    end
    return value ~= nil
end

function CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    if not state then return state end

    local mode = state.mode
    if not IsSupportedMirrorMode(mode) then
        mode = "inactive"
        state.mode = mode
    end

    local active = state.active == true
    if mode == "inactive" then
        active = false
    end
    state.active = active
    state.isActive = active

    if state.auraActive ~= nil or state.auraIsActive ~= nil then
        local auraActive = state.auraActive == true
        state.auraActive = auraActive
        state.auraIsActive = auraActive
    end

    state.gcdOnly = mode == "gcd-only"
    state.isGCDOnly = state.gcdOnly
    state.isAuraMode = mode == "aura"
    state.isRealCooldownMode = IsRealCooldownDurationMode(mode)
    state.hasCharges = state.hasCharges == true or mode == "charge"
    state.isOnCooldown = state.isOnCooldown == true
    state.rechargeActive = state.rechargeActive == true
    state.hasChargesRemaining = state.hasChargesRemaining == true
    state.numericCooldownActive = state.numericCooldownActive == true or nil

    local hasDurationObject = mode ~= "inactive" and HasDurationObject(state.durObj)
    state.hasDurationObject = hasDurationObject == true
    state.hasRenderableCooldown = mode ~= "inactive"
        and (state.hasDurationObject == true or state.numericCooldownActive == true)

    local count = state.count
    if count then
        count.shown = count.shown == true
        state.countValue = count.value
        state.countSinkText = count.sinkText
        state.countShown = count.shown
        state.countSource = count.source
    else
        state.countValue = nil
        state.countSinkText = nil
        state.countShown = false
        state.countSource = nil
    end

    return state
end

local function IsNumericCooldownActive(startTime, duration)
    return IsSafeNumeric(startTime)
        and IsSafeNumeric(duration)
        and startTime > 0
        and duration > GCD_MAX_DURATION
        and (startTime + duration) > GetTime()
end

local function FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    if not state then return state end

    local mode = state.mode or "inactive"

    state.gcdOnly = mode == "gcd-only"
    state.hasCharges = nil
    state.hasChargesRemaining = nil
    state.rechargeActive = nil

    local hasNumericCooldown = (mode == "item-cooldown" or mode == "aura")
        and IsNumericCooldownActive(state.start, state.duration)
    state.numericCooldownActive = hasNumericCooldown == true or nil

    if mode == "inactive" then
        SetCooldownStateActivity(state, false)
        state.isOnCooldown = false
        return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    end

    if mode == "aura" or mode == "gcd-only" then
        state.isOnCooldown = false
        return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    end

    if mode == "item-cooldown" then
        state.isOnCooldown = HasDurationObject(state.durObj) or hasNumericCooldown == true
        return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    end

    if entryIsAura or itemBackedEntry or not sid then
        state.isOnCooldown = state.active == true
    else
        state.isOnCooldown = true
    end
    return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
end

local function ResolveCooldownStateCore(context)
    local state = WipeCooldownState()
    local entry = context and context.entry
    if not entry then
        return FinalizeCooldownStateActivity(state, context, entry, nil, nil, nil)
    end

    local entryIsAura = CDMResolvers.IsAuraEntry(entry)
    local macroResolvedID, macroResolvedType
    if entry.type == "macro" then
        macroResolvedID, macroResolvedType = CDMResolvers.ResolveMacro(entry)
    end
    local sid = (macroResolvedType == "spell" and macroResolvedID)
        or context.runtimeSpellID
        or entry.overrideSpellID or entry.spellID or entry.id
    if sid and not entryIsAura then
        sid = QueryOverrideSpell(sid) or sid
    end
    state.spellID = sid
    MemAuditProfilerMark("CDM_rsIdentity")

    local itemID, itemSpellID
    local itemBackedEntry = IsItemLikeEntry(entry)
        or (entry.type == "macro" and macroResolvedType == "item")
    if itemBackedEntry then
        local _
        itemID, _, itemSpellID = ResolveItemCooldownIdentity(entry)
        if itemSpellID then
            sid = itemSpellID
            state.spellID = sid
        end
    end
    MemAuditProfilerMark("CDM_rsItemIdentity")

    local aura = ResolveAuraRuntimeStateForContext(context, entry, sid, entryIsAura)
    MemAuditProfilerMark("CDM_rsAuraRuntime")
    if ApplyAuraStateToCooldownState(state, aura, sid) then
        if resolverStats then resolverStats.auraProbeHit = resolverStats.auraProbeHit + 1 end
        MemAuditProfilerMark("CDM_rsReturnAura")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    else
        if resolverStats then
            if (not entryIsAura) and context.useBuffSwipe == false then
                resolverStats.auraProbeGuardSkip = resolverStats.auraProbeGuardSkip + 1
            else
                resolverStats.auraProbeExpensiveMiss = resolverStats.auraProbeExpensiveMiss + 1
            end
        end
    end

    if itemID and not context.skipAuraPhase
       and ResolveItemAuraForContext(state, context, entry, itemID, itemSpellID) then
        MemAuditProfilerMark("CDM_rsReturnItemAura")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    end

    if itemBackedEntry then
        local itemDur, itemMode, itemSourceID, itemStart, itemDuration, resolvedItemSpellID =
            ResolveItemDurationObjectForIcon(context.owner, entry)
        MemAuditProfilerMark("CDM_rsItemCooldown")
        if itemMode == "item-cooldown" then
            state.mode = itemMode
            SetCooldownStateActivity(state, true)
            state.durObj = itemDur
            state.sourceID = itemSourceID
            state.start = itemStart
            state.duration = itemDuration
            state.spellID = resolvedItemSpellID
            state.numericCooldownActive = itemStart ~= nil and itemDuration ~= nil or nil
            MemAuditProfilerMark("CDM_rsReturnItemCD")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
        if entry.type ~= "macro" or macroResolvedType == "item" then
            state.mode = "inactive"
            state.spellID = resolvedItemSpellID
            MemAuditProfilerMark("CDM_rsReturnItemOff")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
    end

    if entryIsAura or not sid then
        state.mode = "inactive"
        state.spellID = sid
        MemAuditProfilerMark("CDM_rsReturnNoSpell")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    end

    local trustIsOnGCD = context.trustIsOnGCD == true
    local gcdCdInfo = QueryCooldown(sid)
    local currentOnGCD = GetCurrentIsOnGCD(gcdCdInfo, trustIsOnGCD)
    local preserveGCDOnly = not trustIsOnGCD
        and context.owner
        and context.owner._resolvedCooldownMode == "gcd-only"
    local gcdDurObj
    if trustIsOnGCD and currentOnGCD == true then
        gcdDurObj = QueryGCDDurationObject(sid)
    end
    MemAuditProfilerMark("CDM_rsGCDProbe")

    local entryMayHaveCharges = entry
        and (entry.hasCharges == true or entry.charges == true)
    if currentOnGCD == true and HasActiveChargeRecharge(sid, entryMayHaveCharges) then
        local chargeDur = QueryChargeDuration(sid)
        if chargeDur then
            state.mode = "cooldown"
            SetCooldownStateActivity(state, true)
            state.durObj = chargeDur
            state.sourceID = sid
            state.spellID = sid
            MemAuditProfilerMark("CDM_rsReturnChargeRechargeGCD")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
    end

    do
        local cdInfo = gcdCdInfo or QueryCooldown(sid)
        local cdInfoActive = IsCooldownInfoActive(cdInfo)
        local cdInfoOnGCD = GetCurrentIsOnGCD(cdInfo, trustIsOnGCD)
        if cdInfoActive == true or (cdInfoActive == nil and cdInfoOnGCD ~= true) then
            local durObj = QueryDuration(sid)
            state.cooldownInfoActive = cdInfoActive
            state.cooldownInfoOnGCD = cdInfoOnGCD
            if preserveGCDOnly then
                local gcdDur = QueryGCDDurationObject(sid)
                if gcdDur then
                    state.mode = "gcd-only"
                    SetCooldownStateActivity(state, true)
                    state.durObj = gcdDur
                    state.sourceID = sid
                    state.spellID = sid
                    MemAuditProfilerMark("CDM_rsPreserveGCD")
                    return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
                end
            end
            if durObj and cdInfoOnGCD ~= true then
                state.mode = "cooldown"
                SetCooldownStateActivity(state, true)
                state.durObj = durObj
                state.sourceID = sid
                state.spellID = sid
                MemAuditProfilerMark("CDM_rsReturnLiveCD")
                return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
            end
            if cdInfoOnGCD == true and context.showGCDSwipe == true then
                local gcdDur = QueryGCDDurationObject(sid)
                if gcdDur then
                    state.mode = "gcd-only"
                    SetCooldownStateActivity(state, true)
                    state.durObj = gcdDur
                    state.sourceID = sid
                    state.spellID = sid
                    MemAuditProfilerMark("CDM_rsReturnGCD")
                    return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
                end
            end
        end
    end
    MemAuditProfilerMark("CDM_rsLiveCDProbe")

    if gcdDurObj then
        state.mode = "gcd-only"
        SetCooldownStateActivity(state, true)
        state.durObj = gcdDurObj
        state.sourceID = sid
        state.spellID = sid
        state.cooldownInfoOnGCD = currentOnGCD
        MemAuditProfilerMark("CDM_rsReturnGCDCached")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    end

    if HasActiveChargeRecharge(sid, entryMayHaveCharges) then
        local chargeDur = QueryChargeDuration(sid)
        if chargeDur then
            state.mode = "cooldown"
            SetCooldownStateActivity(state, true)
            state.durObj = chargeDur
            state.sourceID = sid
            state.spellID = sid
            MemAuditProfilerMark("CDM_rsReturnChargeRecharge")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
    end

    state.mode = "inactive"
    state.spellID = sid
    MemAuditProfilerMark("CDM_rsReturnInactive")
    return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
end

function CDMResolvers.ResolveCooldownState(context)
    if resolverStats then
        local tag = currentResolveCallerTag or "other"
        local byTag = resolverStats.resolveBy
        byTag[tag] = (byTag[tag] or 0) + 1
    end
    return ResolveCooldownStateCore(context)
end
