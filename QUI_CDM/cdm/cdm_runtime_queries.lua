local _, ns = ...

local CDMRuntimeQueries = {}
ns.CDMRuntimeQueries = CDMRuntimeQueries

local pairs = pairs
local type = type
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local Sources = ns.CDMSources
local WoW_IsSecretValue = issecretvalue

local function IsSecretValue(value)
    if WoW_IsSecretValue then
        return WoW_IsSecretValue(value)
    end
    return false
end

local function GetChargeMetadataDB()
    local db = QUI and QUI.db and QUI.db.global
    if not db then return nil end
    if not db.cdmChargeSpells then db.cdmChargeSpells = {} end
    return db.cdmChargeSpells
end
CDMRuntimeQueries.GetChargeMetadataDB = GetChargeMetadataDB

local NIL_SENTINEL = {}
local runtimeQueryBatchDepth = 0
local runtimeQueryEpoch = 0
local stableOverrideCache = {}
local runtimeQueryStats

local function SetupDebugInstrumentation()
    runtimeQueryStats = {
        batches = 0,
        cooldownSource = 0,
        cooldownHits = 0,
        chargeSource = 0,
        chargeHits = 0,
        durationSource = 0,
        durationHits = 0,
        chargeDurationSource = 0,
        chargeDurationHits = 0,
        overrideSource = 0,
        overrideHits = 0,
        displayCountSource = 0,
        displayCountHits = 0,
        spellCountSource = 0,
        spellCountHits = 0,
        unbatchedSourceCalls = 0,
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_queryCacheBatches", counter = true, fn = function() return runtimeQueryStats.batches end }
    mp[#mp + 1] = { name = "CDM_queryCacheSource", counter = true, fn = function()
        return runtimeQueryStats.cooldownSource
            + runtimeQueryStats.chargeSource
            + runtimeQueryStats.durationSource
            + runtimeQueryStats.chargeDurationSource
            + runtimeQueryStats.overrideSource
            + runtimeQueryStats.displayCountSource
            + runtimeQueryStats.spellCountSource
    end }
    mp[#mp + 1] = { name = "CDM_queryCacheHits", counter = true, fn = function()
        return runtimeQueryStats.cooldownHits
            + runtimeQueryStats.chargeHits
            + runtimeQueryStats.durationHits
            + runtimeQueryStats.chargeDurationHits
            + runtimeQueryStats.overrideHits
            + runtimeQueryStats.displayCountHits
            + runtimeQueryStats.spellCountHits
    end }
    mp[#mp + 1] = { name = "CDM_queryCacheCooldownSource", counter = true, fn = function() return runtimeQueryStats.cooldownSource end }
    mp[#mp + 1] = { name = "CDM_queryCacheChargeSource", counter = true, fn = function() return runtimeQueryStats.chargeSource end }
    mp[#mp + 1] = { name = "CDM_queryCacheDurationSource", counter = true, fn = function() return runtimeQueryStats.durationSource end }
    mp[#mp + 1] = { name = "CDM_queryCacheChargeDurationSource", counter = true, fn = function() return runtimeQueryStats.chargeDurationSource end }
    mp[#mp + 1] = { name = "CDM_queryCacheOverrideSource", counter = true, fn = function() return runtimeQueryStats.overrideSource end }
    mp[#mp + 1] = { name = "CDM_queryCacheDisplayCountSource", counter = true, fn = function() return runtimeQueryStats.displayCountSource end }
    mp[#mp + 1] = { name = "CDM_queryCacheSpellCountSource", counter = true, fn = function() return runtimeQueryStats.spellCountSource end }
    mp[#mp + 1] = { name = "CDM_queryUnbatchedSource", counter = true, fn = function() return runtimeQueryStats.unbatchedSourceCalls end }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local function AdvanceRuntimeQueryEpoch()
    runtimeQueryEpoch = runtimeQueryEpoch + 1
end

function CDMRuntimeQueries.ClearStableCaches()
    wipe(stableOverrideCache)
end

function CDMRuntimeQueries.InvalidateStableOverrideForSpell(spellID)
    if spellID == nil or IsSecretValue(spellID) then return end
    stableOverrideCache[spellID] = nil
end

function CDMRuntimeQueries.BeginRuntimeQueryBatch()
    if runtimeQueryBatchDepth == 0 then
        AdvanceRuntimeQueryEpoch()
        if runtimeQueryStats then runtimeQueryStats.batches = runtimeQueryStats.batches + 1 end
    end
    runtimeQueryBatchDepth = runtimeQueryBatchDepth + 1
end

function CDMRuntimeQueries.EndRuntimeQueryBatch()
    if runtimeQueryBatchDepth <= 0 then
        runtimeQueryBatchDepth = 0
        return
    end

    runtimeQueryBatchDepth = runtimeQueryBatchDepth - 1
end

function CDMRuntimeQueries.ResetRuntimeQueryBatch()
    runtimeQueryBatchDepth = 0
    AdvanceRuntimeQueryEpoch()
end

local batchSharedCache = {
    cooldown = {},
    charge = {},
    duration = {},
    gcdDuration = {},
    chargeDuration = {},
    displayCount = {},
    spellCount = {},
}

local function ReadRuntimeCache(cacheName, _owner, key, hitStat)
    if runtimeQueryBatchDepth <= 0 then return nil, false end
    if IsSecretValue(key) then return nil, false end -- @secret-policy: reject-secret-ids
    local cache = batchSharedCache[cacheName]
    if not cache then return nil, false end
    local slot = cache[key]
    if slot and slot.epoch == runtimeQueryEpoch then
        if runtimeQueryStats then runtimeQueryStats[hitStat] = runtimeQueryStats[hitStat] + 1 end
        return slot.value, true
    end
    return nil, false
end

local function StoreRuntimeCache(cacheName, _owner, key, value, sourceStat)
    if runtimeQueryBatchDepth <= 0 then
        if runtimeQueryStats then
            runtimeQueryStats.unbatchedSourceCalls = runtimeQueryStats.unbatchedSourceCalls + 1
        end
        return value
    end
    if runtimeQueryStats then runtimeQueryStats[sourceStat] = runtimeQueryStats[sourceStat] + 1 end
    if IsSecretValue(key) then return value end
    local cache = batchSharedCache[cacheName]
    if not cache then return value end
    local slot = cache[key]
    if not slot then
        slot = {}
        cache[key] = slot
    end
    slot.epoch = runtimeQueryEpoch
    slot.value = value
    return value
end

function CDMRuntimeQueries.QueryCharges(spellID, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    local cached, found = ReadRuntimeCache("charge", owner, spellID, "chargeHits")
    if found then return cached end

    local chargeInfo
    if Sources and Sources.QuerySpellCharges then
        chargeInfo = Sources.QuerySpellCharges(spellID)
    end
    if not InCombatLockdown() then
        if chargeInfo then
            local maxC = chargeInfo.maxCharges
            if not IsSecretValue(maxC) and type(maxC) == "number" then
                if maxC > 1 then
                    local svDB = GetChargeMetadataDB()
                    if svDB then svDB[spellID] = maxC end
                else
                    local svDB = GetChargeMetadataDB()
                    if svDB and svDB[spellID] then svDB[spellID] = nil end
                end
            end
        else
            local svDB = GetChargeMetadataDB()
            if svDB and svDB[spellID] then svDB[spellID] = nil end
        end
    end
    return StoreRuntimeCache("charge", owner, spellID, chargeInfo, "chargeSource")
end

function CDMRuntimeQueries.QueryCooldown(spellID, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    local cached, found = ReadRuntimeCache("cooldown", owner, spellID, "cooldownHits")
    if found then return cached end

    local info
    if Sources and Sources.QuerySpellCooldown then
        info = Sources.QuerySpellCooldown(spellID)
    end
    if IsSecretValue(info) then
        info = nil
    end
    return StoreRuntimeCache("cooldown", owner, spellID, info, "cooldownSource")
end

local function QueryCooldownDuration(spellID, ignoreGCD, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    local cacheName = ignoreGCD and "duration" or "gcdDuration"
    local cached, found = ReadRuntimeCache(cacheName, owner, spellID, "durationHits")
    if found then return cached end

    local durObj
    if Sources and Sources.QuerySpellCooldownDuration then
        durObj = Sources.QuerySpellCooldownDuration(spellID, ignoreGCD and true or false)
    end
    return StoreRuntimeCache(cacheName, owner, spellID, durObj, "durationSource")
end

function CDMRuntimeQueries.QueryDuration(spellID, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    return QueryCooldownDuration(spellID, true, owner)
end

function CDMRuntimeQueries.QueryGCDDuration(spellID, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    return QueryCooldownDuration(spellID, false, owner)
end

function CDMRuntimeQueries.QueryChargeDuration(spellID, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    local cached, found = ReadRuntimeCache("chargeDuration", owner, spellID, "chargeDurationHits")
    if found then return cached end

    local durObj
    if Sources and Sources.QuerySpellChargeDuration then
        durObj = Sources.QuerySpellChargeDuration(spellID)
    end
    return StoreRuntimeCache("chargeDuration", owner, spellID, durObj, "chargeDurationSource")
end

function CDMRuntimeQueries.QueryOverrideSpell(spellID)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    local stable = stableOverrideCache[spellID]
    if stable ~= nil then
        if runtimeQueryStats then runtimeQueryStats.overrideHits = runtimeQueryStats.overrideHits + 1 end
        if stable == NIL_SENTINEL then
            return nil
        end
        return stable
    end

    local overrideID
    if Sources and Sources.QueryOverrideSpell then
        overrideID = Sources.QueryOverrideSpell(spellID)
    end
    if IsSecretValue(overrideID) then
        return nil -- @secret-policy: reject-secret-ids
    end
    stableOverrideCache[spellID] = overrideID == nil and NIL_SENTINEL or overrideID
    if runtimeQueryBatchDepth > 0 then
        if runtimeQueryStats then runtimeQueryStats.overrideSource = runtimeQueryStats.overrideSource + 1 end
    end
    return overrideID
end

function CDMRuntimeQueries.QueryDisplayCount(spellID, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    local cached, found = ReadRuntimeCache("displayCount", owner, spellID, "displayCountHits")
    if found then return cached end

    local count
    if Sources and Sources.QuerySpellDisplayCount then
        count = Sources.QuerySpellDisplayCount(spellID)
    end
    return StoreRuntimeCache("displayCount", owner, spellID, count, "displayCountSource")
end

function CDMRuntimeQueries.QuerySpellCount(spellID, owner)
    if IsSecretValue(spellID) or spellID == nil then return nil end
    local cached, found = ReadRuntimeCache("spellCount", owner, spellID, "spellCountHits")
    if found then return cached end

    local count
    if Sources and Sources.QuerySpellCount then
        count = Sources.QuerySpellCount(spellID)
    end
    return StoreRuntimeCache("spellCount", owner, spellID, count, "spellCountSource")
end
