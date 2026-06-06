local _, ns = ...

---------------------------------------------------------------------------
-- CDM Runtime Queries
--
-- Shared runtime query/cache seam for cooldown resolver consumers. Short
-- batch query facts are stored on the current icon/bar runtime state, while
-- this module keeps trusted GCD state and charge metadata persistence out of
-- CDMResolvers' factual state interface.
---------------------------------------------------------------------------

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

local chargeDurationObjectSerial = 0

function CDMRuntimeQueries.NoteChargeDurationObjectsUpdated()
    chargeDurationObjectSerial = chargeDurationObjectSerial + 1
end

function CDMRuntimeQueries.GetChargeDurationObjectSerial()
    return chargeDurationObjectSerial
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
local runtimeQueryOwner
local runtimeQueryOwnerStack = {}
local runtimeQueryOwnerStackDepth = 0
local stableOverrideCache = {}
local runtimeQueryStats -- debug counters; nil until QUI_Debug activates instrumentation

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
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

local function AdvanceRuntimeQueryEpoch()
    runtimeQueryEpoch = runtimeQueryEpoch + 1
end

function CDMRuntimeQueries.ClearStableCaches()
    wipe(stableOverrideCache)
end

function CDMRuntimeQueries.PushRuntimeQueryOwner(owner)
    runtimeQueryOwnerStackDepth = runtimeQueryOwnerStackDepth + 1
    runtimeQueryOwnerStack[runtimeQueryOwnerStackDepth] = runtimeQueryOwner
    runtimeQueryOwner = owner
    return runtimeQueryOwnerStackDepth
end

function CDMRuntimeQueries.PopRuntimeQueryOwner()
    if runtimeQueryOwnerStackDepth <= 0 then
        runtimeQueryOwner = nil
        return
    end
    runtimeQueryOwner = runtimeQueryOwnerStack[runtimeQueryOwnerStackDepth]
    runtimeQueryOwnerStack[runtimeQueryOwnerStackDepth] = nil
    runtimeQueryOwnerStackDepth = runtimeQueryOwnerStackDepth - 1
end

function CDMRuntimeQueries.WithRuntimeQueryOwner(owner, callback, ...)
    if not callback then return nil end
    CDMRuntimeQueries.PushRuntimeQueryOwner(owner)
    local a, b, c, d, e = callback(...)
    CDMRuntimeQueries.PopRuntimeQueryOwner()
    return a, b, c, d, e
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
        runtimeQueryOwner = nil
        runtimeQueryOwnerStackDepth = 0
        wipe(runtimeQueryOwnerStack)
        return
    end

    runtimeQueryBatchDepth = runtimeQueryBatchDepth - 1
    if runtimeQueryBatchDepth == 0 then
        runtimeQueryOwner = nil
        runtimeQueryOwnerStackDepth = 0
        wipe(runtimeQueryOwnerStack)
    end
end

function CDMRuntimeQueries.ResetRuntimeQueryBatch()
    runtimeQueryBatchDepth = 0
    runtimeQueryOwner = nil
    runtimeQueryOwnerStackDepth = 0
    wipe(runtimeQueryOwnerStack)
    AdvanceRuntimeQueryEpoch()
end

-- Batch-shared query cache. Previously this layer kept a per-owner cache on
-- each icon's runtime state, which forced duplicate Blizzard API calls when
-- multiple icons (mirrors, item variants, GCD targets) all queried the same
-- spell within one batch — each fresh `C_Spell.GetSpellCooldown` return is
-- its own allocated table, and combat memaudit showed those returns
-- dominating the per-window "unattributed" allocation gap (see
-- docs/dev/perf-memaudit-2026-05-21.md notes).
--
-- The cache is keyed by (cacheName, key) only; owner parameters are still
-- accepted for source compatibility but ignored. Slots stay alive across
-- batches and are reused via epoch tagging — reads check `slot.epoch ==
-- runtimeQueryEpoch`, so stale data is invisible after the next batch
-- begin without paying for a per-batch wipe.
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
    if IsSecretValue(key) then return nil, false end
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
    if runtimeQueryBatchDepth <= 0 then return value end
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
            -- Treat secret charge counts as opaque; metadata cache only
            -- records clean, out-of-combat numeric charge counts.
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
        return nil
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
