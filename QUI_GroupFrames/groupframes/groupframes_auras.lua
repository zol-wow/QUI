--[[
    QUI Group Frames - Aura System
    Compact aura display for group frames with priority filtering,
    table pooling, shared aura timer, and duration color coding.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")
local AuraModel = ns.QUI_GroupFramesAuraModel
-- Unified element renderer (groupframes_aura_render.lua). Resolved lazily at
-- render time via GetRender() so file load order can't matter.
local function GetRender() return ns.QUI_GroupFrameAuraRender end

-- Upvalue hot-path globals
local pairs = pairs
local ipairs = ipairs
local type = type
local wipe = wipe
local C_UnitAuras = C_UnitAuras
local table_remove = table.remove

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFA = {}
ns.QUI_GroupFrameAuras = QUI_GFA

---------------------------------------------------------------------------
-- ELEMENT-MODEL GLUE (inert — wired in a later flip task)
---------------------------------------------------------------------------

-- Build render work for one unit frame from the unified element model.
-- specID: the unit's active spec (or nil). cache: that unit's unitAuraCache entry.
-- Returns a list of { element = <element>, matches = <table|nil> } for the renderer.
local function BuildElementRenderList(auras, specID, cache)
    local work = {}
    if not auras then return work end
    if AuraModel.EnsureSeeded then AuraModel.EnsureSeeded(auras) end
    if auras.enabled == false then return work end
    local elements = AuraModel.ActiveElementsForSpec(auras, specID)
    for _, element in ipairs(elements) do
        local matches
        if element.mode == "tracked" then
            matches = AuraModel.PopulateElementMatches(element, cache)
        end
        work[#work + 1] = { element = element, matches = matches }
    end
    return work
end
QUI_GFA.BuildElementRenderList = BuildElementRenderList

---------------------------------------------------------------------------
-- SHARED AURA CACHE: One authoritative per-unit aura state for group frames
---------------------------------------------------------------------------
-- Populated once per throttle window, read by all consumers. All
-- classification, filtering, and sorting work happens here at delta time so
-- frame render is a trivial walk over pre-computed subsets.
--
-- Structure: unitAuraCache[unit] = {
--     -- Raw aura arrays (single source of truth)
--     buffs                  = {auraData...},
--     debuffs                = {auraData...},
--     -- Instance-ID-keyed lookups (used by render-time map probes)
--     buffsByID              = { [instID] = auraData },
--     debuffsByID            = { [instID] = auraData },
--     buffsIndexByID         = { [instID] = arrayIndex },
--     debuffsIndexByID       = { [instID] = arrayIndex },
--     buffsBySpellID         = { [spellID] = auraData },
--     debuffsBySpellID       = { [spellID] = auraData },
--     buffsByName            = { [spellName] = auraData },
--     debuffsByName          = { [spellName] = auraData },
--     -- Pre-classified subsets — render walks the orders / probes the sets
--     playerDispellable      = { [instID] = true },     -- player can dispel
--     playerDispellableOrder = { instID, ... },
--     allDispellable         = { [instID] = true },     -- anyone can dispel (any dispelName)
--     defensives             = { [instID] = true },     -- matches defensive classifier
--     defensiveOrder         = { instID, ... },
--     -- Bookkeeping
--     hasFullScan            = boolean,
-- }
--
-- Full scans rebuild the entire structure; UNIT_AURA deltas patch it
-- incrementally and re-run the rebuilders for any side that changed.
local unitAuraCache = {}
local auraStats -- debug counters; nil until QUI_Debug activates instrumentation
local function SetupDebugInstrumentation()
    auraStats = {
        fullScans = 0,
        slotScans = 0,
        legacyScans = 0,
        deltaApplied = 0,
        deltaFallback = 0,
        fastUpdates = 0,
        fullUpdateEvents = 0,
        deltaAddedAuras = 0,
        deltaRemovedAuras = 0,
        deltaUpdatedIDs = 0,
        deltaUpdatedSkipped = 0,
        deltaFreshFetches = 0,
        deltaMixedDeltas = 0,
        mixedIconRefreshes = 0,
        panelBuffRebuilds = 0,
        panelDebuffRebuilds = 0,
        panelBuffIncrementalAttempts = 0,
        panelBuffIncremental = 0,
        panelBuffIncrementalDirtySkip = 0,
        panelBuffIncrementalFilterSkip = 0,
        panelBuffIncrementalChanged = 0,
        panelBuffIncrementalNoop = 0,
        defensiveSetChanges = 0,
        curatedMatchRefreshes = 0,
        indicatorMatchChanges = 0,
        pinnedMatchChanges = 0,
        indicatorFrameRefreshes = 0,
        indicatorFrameSkips = 0,
        pinnedFrameRefreshes = 0,
        pinnedFrameSkips = 0,
        panelFrameRefreshes = 0,
        panelFrameSkips = 0,
        panelFrameDisplaySkips = 0,
        panelNoDisplay = 0,
        panelIconUpdates = 0,
        panelIconSkips = 0,
        noConsumerSkips = 0,
        framesRefreshed = 0,
        -- Dirty-flag + storm-budget effectiveness (this rework).
        heavyDeferred = 0,     -- units bumped to the drain queue (budget overflow)
        drainProcessed = 0,    -- units processed by the drain ticker
        frameSkips = 0,        -- whole frames skipped by DeltaTouchesFrame
        elementSkips = 0,      -- elements skipped by the per-element dirty gate
        elementsDispatched = 0,-- elements that actually re-dispatched (skip ratio denom)
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_unitAuraCache", tbl = unitAuraCache }
    mp[#mp + 1] = { name = "GF_auraFullScans", fn = function() return auraStats.fullScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraSlotScans", fn = function() return auraStats.slotScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraLegacyScans", fn = function() return auraStats.legacyScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaApplied", fn = function() return auraStats.deltaApplied end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaFallback", fn = function() return auraStats.deltaFallback end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFastUpdates", fn = function() return auraStats.fastUpdates end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFullUpdateEvents", fn = function() return auraStats.fullUpdateEvents end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaAdded", fn = function() return auraStats.deltaAddedAuras end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaRemoved", fn = function() return auraStats.deltaRemovedAuras end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaUpdated", fn = function() return auraStats.deltaUpdatedIDs end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaUpdatedSkipped", fn = function() return auraStats.deltaUpdatedSkipped end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFreshFetches", fn = function() return auraStats.deltaFreshFetches end, counter = true }
    mp[#mp + 1] = { name = "GF_auraMixedDeltas", fn = function() return auraStats.deltaMixedDeltas end, counter = true }
    mp[#mp + 1] = { name = "GF_auraMixedIconRefreshes", fn = function() return auraStats.mixedIconRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffRebuilds", fn = function() return auraStats.panelBuffRebuilds end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelDebuffRebuilds", fn = function() return auraStats.panelDebuffRebuilds end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncAttempts", fn = function() return auraStats.panelBuffIncrementalAttempts end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncremental", fn = function() return auraStats.panelBuffIncremental end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncDirtySkip", fn = function() return auraStats.panelBuffIncrementalDirtySkip end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffIncFilterSkip", fn = function() return auraStats.panelBuffIncrementalFilterSkip end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffChanges", fn = function() return auraStats.panelBuffIncrementalChanged end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelBuffNoops", fn = function() return auraStats.panelBuffIncrementalNoop end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDefensiveSetChanges", fn = function() return auraStats.defensiveSetChanges end, counter = true }
    mp[#mp + 1] = { name = "GF_auraCuratedRefreshes", fn = function() return auraStats.curatedMatchRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraIndicatorMatchChanges", fn = function() return auraStats.indicatorMatchChanges end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPinnedMatchChanges", fn = function() return auraStats.pinnedMatchChanges end, counter = true }
    mp[#mp + 1] = { name = "GF_auraIndicatorRefreshes", fn = function() return auraStats.indicatorFrameRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraIndicatorRefreshSkips", fn = function() return auraStats.indicatorFrameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPinnedRefreshes", fn = function() return auraStats.pinnedFrameRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPinnedRefreshSkips", fn = function() return auraStats.pinnedFrameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelRefreshes", fn = function() return auraStats.panelFrameRefreshes end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelRefreshSkips", fn = function() return auraStats.panelFrameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelDisplaySkips", fn = function() return auraStats.panelFrameDisplaySkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelNoDisplay", fn = function() return auraStats.panelNoDisplay end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelIconUpdates", fn = function() return auraStats.panelIconUpdates end, counter = true }
    mp[#mp + 1] = { name = "GF_auraPanelIconSkips", fn = function() return auraStats.panelIconSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraNoConsumerSkips", fn = function() return auraStats.noConsumerSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFramesRefreshed", fn = function() return auraStats.framesRefreshed end, counter = true }
    mp[#mp + 1] = { name = "GF_auraHeavyDeferred", fn = function() return auraStats.heavyDeferred end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDrainProcessed", fn = function() return auraStats.drainProcessed end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFrameSkips", fn = function() return auraStats.frameSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraElementSkips", fn = function() return auraStats.elementSkips end, counter = true }
    mp[#mp + 1] = { name = "GF_auraElementsDispatched", fn = function() return auraStats.elementsDispatched end, counter = true }
    QUI_GFA.auraStats = auraStats -- debug export tracks the live table (nil until activation)
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

local DISPEL_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"
local MAX_SCAN_AURAS = 40

-- Classify a single harmful aura as dispellable by the current player.
-- Returns true/false; returns nil when the API is unavailable.
-- No pcall — IsAuraFilteredOutByInstanceID is C-side, returns nil on error.
local IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot

local function ClassifyDispellable(unit, instID)
    if not instID or IsSecretValue(instID) then return nil end
    if not IsAuraFilteredOut then return nil end
    local filteredOut = IsAuraFilteredOut(unit, instID, DISPEL_FILTER)
    if filteredOut == nil or IsSecretValue(filteredOut) then return nil end
    return filteredOut == false
end

-- Classify a single helpful aura as a verified defensive (big or external).
-- Delegates to the groupframes.lua classifier which owns the spell-ID fast
-- path and the BigDefensive/ExternalDefensive filter cache.
local function ClassifyDefensive(unit, auraData)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.IsVerifiedDefensiveAura then return false end
    return GF.IsVerifiedDefensiveAura(unit, auraData) == true
end

local function CreateAuraCacheEntry()
    return {
        -- Raw aura arrays (single source of truth)
        buffs = {},
        debuffs = {},
        -- Instance-ID-keyed lookups
        buffsByID = {},
        debuffsByID = {},
        buffsIndexByID = {},
        debuffsIndexByID = {},
        buffsBySpellID = {},
        debuffsBySpellID = {},
        buffsByName = {},
        debuffsByName = {},
        -- Pre-classified subsets maintained by the rebuilders
        playerDispellable = {},
        playerDispellableOrder = {},
        allDispellable = {},
        defensives = {},
        defensiveOrder = {},
        -- Bookkeeping
        defensiveSetChanged = true,
        hasFullScan = false,
    }
end

local function EnsureAuraCache(unit)
    local cache = unitAuraCache[unit]
    if cache then
        return cache
    end
    cache = CreateAuraCacheEntry()
    unitAuraCache[unit] = cache
    return cache
end

local function ResetAuraCache(cache)
    wipe(cache.buffs)
    wipe(cache.debuffs)
    wipe(cache.buffsByID)
    wipe(cache.debuffsByID)
    wipe(cache.buffsIndexByID)
    wipe(cache.debuffsIndexByID)
    wipe(cache.buffsBySpellID)
    wipe(cache.debuffsBySpellID)
    wipe(cache.buffsByName)
    wipe(cache.debuffsByName)
    wipe(cache.playerDispellable)
    wipe(cache.playerDispellableOrder)
    wipe(cache.allDispellable)
    wipe(cache.defensives)
    wipe(cache.defensiveOrder)
    cache.defensiveSetChanged = true
    cache.hasFullScan = false
end

local function RebuildBuffMaps(unit, cache)
    wipe(cache.buffsByID)
    wipe(cache.buffsIndexByID)
    wipe(cache.buffsBySpellID)
    wipe(cache.buffsByName)
    wipe(cache.defensives)
    wipe(cache.defensiveOrder)

    local buffs = cache.buffs
    local buffsByID = cache.buffsByID
    local buffsIndexByID = cache.buffsIndexByID
    local buffsBySpellID = cache.buffsBySpellID
    local buffsByName = cache.buffsByName
    local defensives = cache.defensives
    local defensiveOrder = cache.defensiveOrder

    for i = 1, #buffs do
        local auraData = buffs[i]
        local instID = auraData and auraData.auraInstanceID
        if instID then
            buffsByID[instID] = auraData
            buffsIndexByID[instID] = i
            if ClassifyDefensive(unit, auraData) then
                defensives[instID] = true
                defensiveOrder[#defensiveOrder + 1] = instID
            end
        end

        local spellID = SafeValue(auraData and auraData.spellId, nil)
        if spellID then
            buffsBySpellID[spellID] = auraData
        end

        local spellName = SafeValue(auraData and auraData.name, nil)
        if spellName then
            buffsByName[spellName] = auraData
        end
    end
end

local function RebuildDebuffMaps(unit, cache)
    wipe(cache.debuffsByID)
    wipe(cache.debuffsIndexByID)
    wipe(cache.debuffsBySpellID)
    wipe(cache.debuffsByName)
    wipe(cache.playerDispellable)
    wipe(cache.playerDispellableOrder)
    wipe(cache.allDispellable)

    local debuffs = cache.debuffs
    local debuffsByID = cache.debuffsByID
    local debuffsIndexByID = cache.debuffsIndexByID
    local debuffsBySpellID = cache.debuffsBySpellID
    local debuffsByName = cache.debuffsByName
    local playerDispellable = cache.playerDispellable
    local playerDispellableOrder = cache.playerDispellableOrder
    local allDispellable = cache.allDispellable

    for i = 1, #debuffs do
        local auraData = debuffs[i]
        local instID = auraData and auraData.auraInstanceID
        if instID then
            debuffsByID[instID] = auraData
            debuffsIndexByID[instID] = i

            local dispelName = auraData.dispelName
            local hasDispelType = dispelName ~= nil and not IsSecretValue(dispelName)
            if hasDispelType then
                allDispellable[instID] = true
            end

            local classified = ClassifyDispellable(unit, instID)
            if classified == true or (classified == nil and hasDispelType) then
                playerDispellable[instID] = true
                playerDispellableOrder[#playerDispellableOrder + 1] = instID
            end
        end

        local spellID = SafeValue(auraData and auraData.spellId, nil)
        if spellID then
            debuffsBySpellID[spellID] = auraData
        end

        local spellName = SafeValue(auraData and auraData.name, nil)
        if spellName then
            debuffsByName[spellName] = auraData
        end
    end
end

local function ResolveAuraBucket(unit, auraData)
    if not auraData then return nil end

    local instID = auraData.auraInstanceID
    if instID and IsAuraFilteredOut then
        local buffFiltered = IsAuraFilteredOut(unit, instID, "HELPFUL")
        if buffFiltered ~= nil and not IsSecretValue(buffFiltered) then
            if buffFiltered == false then
                return "buffs"
            end
            local debuffFiltered = IsAuraFilteredOut(unit, instID, "HARMFUL")
            if debuffFiltered ~= nil and not IsSecretValue(debuffFiltered) then
                if debuffFiltered == false then
                    return "debuffs"
                end
            end
        end
    end

    local isHelpful = SafeValue(auraData.isHelpful, nil)
    if isHelpful == true then
        return "buffs"
    end

    local isHarmful = SafeValue(auraData.isHarmful, nil)
    if isHarmful == true then
        return "debuffs"
    end

    return nil
end

local function RefreshSpellIDLookupAfterRemoval(bucket, lookup, spellID)
    if not spellID or not lookup then return end
    lookup[spellID] = nil
    for i = 1, #bucket do
        local auraData = bucket[i]
        if SafeValue(auraData and auraData.spellId, nil) == spellID then
            lookup[spellID] = auraData
        end
    end
end

local function RefreshSpellNameLookupAfterRemoval(bucket, lookup, spellName)
    if not spellName or not lookup then return end
    lookup[spellName] = nil
    for i = 1, #bucket do
        local auraData = bucket[i]
        if SafeValue(auraData and auraData.name, nil) == spellName then
            lookup[spellName] = auraData
        end
    end
end

local function RemoveIDFromOrder(order, instID)
    if not order then return end
    for i = 1, #order do
        if order[i] == instID then
            table_remove(order, i)
            return
        end
    end
end

local function AddBuffDerivedData(unit, cache, auraData)
    local instID = auraData and auraData.auraInstanceID
    if not instID then return end

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID then
        cache.buffsBySpellID[spellID] = auraData
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName then
        cache.buffsByName[spellName] = auraData
    end

    if ClassifyDefensive(unit, auraData) then
        -- Append to the order array only when the set didn't already hold the
        -- instID, so defensiveOrder stays a faithful dedup mirror of defensives.
        -- An unconditional append could push a second copy whose single
        -- RemoveIDFromOrder on removal leaves a phantom (see UpdateDispelOverlay).
        if not cache.defensives[instID] then
            cache.defensiveOrder[#cache.defensiveOrder + 1] = instID
        end
        cache.defensives[instID] = true
        return true
    end
    return false
end

local function RemoveBuffDerivedData(cache, auraData, instID)
    if not auraData or not instID then return false end
    local defensiveChanged = cache.defensives[instID] == true

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID and cache.buffsBySpellID[spellID] == auraData then
        RefreshSpellIDLookupAfterRemoval(cache.buffs, cache.buffsBySpellID, spellID)
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName and cache.buffsByName[spellName] == auraData then
        RefreshSpellNameLookupAfterRemoval(cache.buffs, cache.buffsByName, spellName)
    end

    cache.defensives[instID] = nil
    RemoveIDFromOrder(cache.defensiveOrder, instID)
    return defensiveChanged
end

local function AddDebuffDerivedData(unit, cache, auraData)
    local instID = auraData and auraData.auraInstanceID
    if not instID then return end

    local dispelName = auraData.dispelName
    local hasDispelType = dispelName ~= nil and not IsSecretValue(dispelName)
    if hasDispelType then
        cache.allDispellable[instID] = true
    end

    local classified = ClassifyDispellable(unit, instID)
    if classified == true or (classified == nil and hasDispelType) then
        -- Dedup-guard the order append against the set so playerDispellableOrder
        -- stays a faithful mirror of playerDispellable; an unconditional append
        -- can leave a phantom that RemoveIDFromOrder (first-match) won't fully
        -- clear, keeping the dispel overlay lit after the debuff is gone.
        if not cache.playerDispellable[instID] then
            cache.playerDispellableOrder[#cache.playerDispellableOrder + 1] = instID
        end
        cache.playerDispellable[instID] = true
    end

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID then
        cache.debuffsBySpellID[spellID] = auraData
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName then
        cache.debuffsByName[spellName] = auraData
    end
end

local function RemoveDebuffDerivedData(cache, auraData, instID)
    if not auraData or not instID then return end

    local spellID = SafeValue(auraData.spellId, nil)
    if spellID and cache.debuffsBySpellID[spellID] == auraData then
        RefreshSpellIDLookupAfterRemoval(cache.debuffs, cache.debuffsBySpellID, spellID)
    end

    local spellName = SafeValue(auraData.name, nil)
    if spellName and cache.debuffsByName[spellName] == auraData then
        RefreshSpellNameLookupAfterRemoval(cache.debuffs, cache.debuffsByName, spellName)
    end

    cache.playerDispellable[instID] = nil
    cache.allDispellable[instID] = nil
    RemoveIDFromOrder(cache.playerDispellableOrder, instID)
end

local function AppendAuraToBucket(unit, cache, bucketName, auraData)
    local bucket = bucketName == "buffs" and cache.buffs or cache.debuffs
    local byID = bucketName == "buffs" and cache.buffsByID or cache.debuffsByID
    local indexByID = bucketName == "buffs" and cache.buffsIndexByID or cache.debuffsIndexByID
    local instID = auraData and auraData.auraInstanceID

    -- Idempotent re-add: a duplicate addedAuras entry (or an add for an
    -- already-cached instance with no intervening remove) must overwrite in
    -- place, NOT append. Re-appending would push a second copy of instID into
    -- the dedup ORDER arrays (playerDispellableOrder / defensiveOrder) whose
    -- set guards already hold it; a single RemoveIDFromOrder on removal then
    -- strips only one, leaving a phantom that keeps the dispel overlay /
    -- defensive indicator lit after the aura is gone.
    if instID and byID[instID] then
        local idx = indexByID[instID]
        if idx then bucket[idx] = auraData end
        byID[instID] = auraData
        return
    end

    bucket[#bucket + 1] = auraData
    if not instID then
        return
    end

    if bucketName == "buffs" then
        cache.buffsByID[instID] = auraData
        cache.buffsIndexByID[instID] = #bucket
        return AddBuffDerivedData(unit, cache, auraData)
    else
        cache.debuffsByID[instID] = auraData
        cache.debuffsIndexByID[instID] = #bucket
        AddDebuffDerivedData(unit, cache, auraData)
    end
end

local function RemoveAuraFromBucket(cache, bucketName, instID)
    local bucket, indexMap, byInstanceID
    if bucketName == "buffs" then
        bucket = cache.buffs
        indexMap = cache.buffsIndexByID
        byInstanceID = cache.buffsByID
    else
        bucket = cache.debuffs
        indexMap = cache.debuffsIndexByID
        byInstanceID = cache.debuffsByID
    end

    local idx = indexMap[instID]
    if not idx then
        return false
    end

    local oldAura = byInstanceID[instID]
    table_remove(bucket, idx)
    indexMap[instID] = nil
    byInstanceID[instID] = nil

    for i = idx, #bucket do
        local auraData = bucket[i]
        local auraInstID = auraData and auraData.auraInstanceID
        if auraInstID then
            indexMap[auraInstID] = i
        end
    end

    if bucketName == "buffs" then
        return true, RemoveBuffDerivedData(cache, oldAura, instID)
    else
        RemoveDebuffDerivedData(cache, oldAura, instID)
    end

    return true
end

local function ReplaceAuraInBucket(cache, bucketName, instID, auraData)
    local bucket, indexMap, byInstanceID
    if bucketName == "buffs" then
        bucket = cache.buffs
        indexMap = cache.buffsIndexByID
        byInstanceID = cache.buffsByID
    else
        bucket = cache.debuffs
        indexMap = cache.debuffsIndexByID
        byInstanceID = cache.debuffsByID
    end

    local idx = indexMap[instID]
    if not idx then
        return false
    end

    bucket[idx] = auraData
    byInstanceID[instID] = auraData
    return true
end

local function AppendSlotAuras(unit, dst, ...)
    local n = select("#", ...)
    for i = 2, n do
        local slot = select(i, ...)
        if slot then
            local auraData = GetAuraDataBySlot(unit, slot)
            if auraData and auraData.auraInstanceID then
                dst[#dst + 1] = auraData
            end
        end
    end
end

local function ScanUnitAurasBySlot(unit, cache)
    if not GetAuraSlots or not GetAuraDataBySlot then
        return false
    end

    AppendSlotAuras(unit, cache.debuffs, GetAuraSlots(unit, "HARMFUL", MAX_SCAN_AURAS))
    AppendSlotAuras(unit, cache.buffs, GetAuraSlots(unit, "HELPFUL", MAX_SCAN_AURAS))
    return true
end

local function ScanUnitAurasLegacy(unit, cache)
    local GetUnitAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
    if not GetUnitAuras then return false end

    local debuffs = GetUnitAuras(unit, "HARMFUL", MAX_SCAN_AURAS)
    if debuffs then
        local dst = cache.debuffs
        for i = 1, #debuffs do
            dst[i] = debuffs[i]
        end
    end

    local buffs = GetUnitAuras(unit, "HELPFUL", MAX_SCAN_AURAS)
    if buffs then
        local dst = cache.buffs
        for i = 1, #buffs do
            dst[i] = buffs[i]
        end
    end
    return true
end

local function ScanUnitAuras(unit)
    local cache = EnsureAuraCache(unit)
    ResetAuraCache(cache)

    if auraStats then auraStats.fullScans = auraStats.fullScans + 1 end
    if ScanUnitAurasBySlot(unit, cache) then
        if auraStats then auraStats.slotScans = auraStats.slotScans + 1 end
    elseif ScanUnitAurasLegacy(unit, cache) then
        if auraStats then auraStats.legacyScans = auraStats.legacyScans + 1 end
    else
        return cache
    end

    RebuildDebuffMaps(unit, cache)
    RebuildBuffMaps(unit, cache)
    cache.hasFullScan = true
    return cache
end

-- DELTA DIRTY SUMMARY ------------------------------------------------------
-- ApplyAuraDelta publishes which aura BUCKETS changed (helpful/harmful), whether
-- the defensive set moved, and the set of spellIDs added/removed/updated, into a
-- single reusable table. The render fan-out reads it to dirty-flag frames and
-- individual elements: a frame/element whose tracked auras the delta never
-- touched skips re-dispatch entirely. Only valid when ApplyAuraDelta returns
-- true (an incremental patch); a full scan / fallback sets dirty = nil (render
-- everything). spellsUncertain = a changed aura's spellId was secret/unreadable,
-- so tracked elements must be treated as dirty (conservative, never stale).
local _deltaSummary = { helpful = false, harmful = false, defensive = false,
                        spellsUncertain = false, spells = {} }
local function ResetDeltaSummary()
    _deltaSummary.helpful = false
    _deltaSummary.harmful = false
    _deltaSummary.defensive = false
    _deltaSummary.spellsUncertain = false
    wipe(_deltaSummary.spells)
end
local function SummaryAddSpell(auraData)
    if not auraData then _deltaSummary.spellsUncertain = true; return end
    local sid = SafeValue(auraData.spellId, nil)
    if sid then
        _deltaSummary.spells[sid] = true
    else
        _deltaSummary.spellsUncertain = true
    end
end

local function ApplyAuraDelta(unit, updateInfo)
    local cache = unitAuraCache[unit]
    if not cache or not cache.hasFullScan or type(updateInfo) ~= "table" then
        return false
    end

    ResetDeltaSummary()
    local buffsDirty = false
    local debuffsDirty = false
    local buffFreshUpdated = false
    local debuffFreshUpdated = false
    cache.defensiveSetChanged = false
    local GetAuraByInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    local nAdded = updateInfo.addedAuras and #updateInfo.addedAuras or 0
    local nRemoved = updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs or 0
    local nUpdated = updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs or 0

    -- The mixed-delta condition is intentionally repeated in the functional
    -- skipUpdatedFetches expression below; the guard body is stats-only and
    -- must never absorb functional logic.
    if auraStats then
        auraStats.deltaAddedAuras = auraStats.deltaAddedAuras + nAdded
        auraStats.deltaRemovedAuras = auraStats.deltaRemovedAuras + nRemoved
        auraStats.deltaUpdatedIDs = auraStats.deltaUpdatedIDs + nUpdated
        if nUpdated > 0 and (nAdded > 0 or nRemoved > 0) then
            auraStats.deltaMixedDeltas = auraStats.deltaMixedDeltas + 1
        end
    end
    local skipUpdatedFetches = nUpdated > 0
        and (nAdded > 0 or nRemoved > 0)
        and C_UnitAuras
        and C_UnitAuras.GetAuraDuration

    if updateInfo.addedAuras then
        for i = 1, #updateInfo.addedAuras do
            local auraData = updateInfo.addedAuras[i]
            local bucketName = ResolveAuraBucket(unit, auraData)
            if not bucketName then
                return false
            end
            local defensiveChanged = AppendAuraToBucket(unit, cache, bucketName, auraData)
            SummaryAddSpell(auraData)
            if bucketName == "buffs" then
                buffsDirty = true
                if defensiveChanged then
                    cache.defensiveSetChanged = true
                end
            else
                debuffsDirty = true
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs > 0 then
        if skipUpdatedFetches then
            if auraStats then auraStats.deltaUpdatedSkipped = auraStats.deltaUpdatedSkipped + nUpdated end
            -- Updated instances weren't re-fetched, so their spellIDs are unknown
            -- this pass. Mark uncertain so tracked elements re-dispatch (a stack
            -- change on a tracked aura must reach its icon).
            _deltaSummary.spellsUncertain = true
        else
            if not GetAuraByInstanceID then
                return false
            end

            for i = 1, #updateInfo.updatedAuraInstanceIDs do
                local instID = updateInfo.updatedAuraInstanceIDs[i]
                local bucketName = nil
                if cache.buffsByID[instID] then
                    bucketName = "buffs"
                elseif cache.debuffsByID[instID] then
                    bucketName = "debuffs"
                end

                if bucketName then
                    if auraStats then auraStats.deltaFreshFetches = auraStats.deltaFreshFetches + 1 end
                    local freshAura = GetAuraByInstanceID(unit, instID)
                    if not freshAura then
                        return false
                    end
                    if not ReplaceAuraInBucket(cache, bucketName, instID, freshAura) then
                        return false
                    end
                    SummaryAddSpell(freshAura)
                    if bucketName == "buffs" then
                        buffsDirty = true
                        buffFreshUpdated = true
                        cache.defensiveSetChanged = true
                    else
                        debuffsDirty = true
                        debuffFreshUpdated = true
                    end
                end
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for i = 1, #updateInfo.removedAuraInstanceIDs do
            local instID = updateInfo.removedAuraInstanceIDs[i]
            -- A removed instID should live in exactly ONE bucket, but a
            -- ResolveAuraBucket flip across events (secret isHelpful/isHarmful in
            -- combat) can leave a stale copy in the other bucket. Clean BOTH so
            -- derived data (playerDispellable / defensives) can never linger and
            -- strand the dispel / defensive overlay lit after the aura is gone.
            -- Separate `if`s (not else): an instID present in both is fully purged.
            local rb = cache.buffsByID[instID]
            if rb then
                local removed, defensiveChanged = RemoveAuraFromBucket(cache, "buffs", instID)
                if removed then
                    buffsDirty = true
                    SummaryAddSpell(rb)
                    if defensiveChanged then
                        cache.defensiveSetChanged = true
                    end
                end
            end
            local rd = cache.debuffsByID[instID]
            if rd and RemoveAuraFromBucket(cache, "debuffs", instID) then
                debuffsDirty = true
                SummaryAddSpell(rd)
            end
        end
    end

    if buffsDirty and buffFreshUpdated then
        RebuildBuffMaps(unit, cache)
    end
    if debuffsDirty and debuffFreshUpdated then
        RebuildDebuffMaps(unit, cache)
    end
    if cache.defensiveSetChanged then
        if auraStats then auraStats.defensiveSetChanges = auraStats.defensiveSetChanges + 1 end
    end

    -- Publish the dirty summary for the render fan-out (valid only on this true
    -- return; a false return falls back to a full scan + full render).
    _deltaSummary.helpful = buffsDirty
    _deltaSummary.harmful = debuffsDirty
    _deltaSummary.defensive = cache.defensiveSetChanged
    return true
end

-- Evict stale cache entries for units no longer in the group.
-- Called on GROUP_ROSTER_UPDATE from the centralized event dispatcher.
local function PruneAuraCache()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.unitFrameMap then return end
    for unit in pairs(unitAuraCache) do
        if not GF.unitFrameMap[unit] then
            unitAuraCache[unit] = nil
        end
    end
end

-- Expose cache for other modules (dispel overlay, defensive indicator)
QUI_GFA.unitAuraCache = unitAuraCache
-- QUI_GFA.auraStats is exported by SetupDebugInstrumentation (debug gate)
QUI_GFA.ScanUnitAuras = ScanUnitAuras
QUI_GFA.ApplyAuraDelta = ApplyAuraDelta
QUI_GFA.PruneAuraCache = PruneAuraCache

-- Spec-change handlers call this before refreshing frames so every cached unit
-- re-scans against the new spec's aura state. Does not re-render frames.
function QUI_GFA:RescanCachedUnits()
    for unit in pairs(unitAuraCache) do
        ScanUnitAuras(unit)
    end
end

-- Table reuse: unitAuraCache[unit] sub-tables are created once per unit and
-- then mutated in place across full scans and deltas. Blizzard auraData tables
-- are still C-side allocated, but the shared cache avoids rebuilding per-
-- consumer lookup tables on every roster aura change.

---------------------------------------------------------------------------
-- CLASSIFICATION FILTER: Build filter strings and check auras
---------------------------------------------------------------------------
-- Maps DB toggle keys to Blizzard classification filter strings
local BUFF_CLASSIFICATION_MAP = {
    raid              = "HELPFUL|RAID",
    raidInCombat      = "HELPFUL|RAID_IN_COMBAT",
    cancelable        = "HELPFUL|CANCELABLE",
    notCancelable     = "HELPFUL|NOT_CANCELABLE",
    important         = "HELPFUL|IMPORTANT",
    bigDefensive      = "HELPFUL|BIG_DEFENSIVE",
    externalDefensive = "HELPFUL|EXTERNAL_DEFENSIVE",
}

local DEBUFF_CLASSIFICATION_MAP = {
    raid         = "HARMFUL|RAID",
    raidInCombat = "HARMFUL|RAID_IN_COMBAT",
    crowdControl = "HARMFUL|CROWD_CONTROL",
    important    = "HARMFUL|IMPORTANT",
}

-- Check if an aura passes whitelist/blacklist filter by spellID.
-- Returns true if aura should be shown.
-- Fail-open: if spellID is secret, show the aura.
local function AuraPassesSpellFilter(auraData, whitelist, blacklist)
    local spellId = auraData and auraData.spellId
    if not spellId or IsSecretValue(spellId) then
        return true -- fail-open
    end
    if whitelist then
        return whitelist[spellId] == true
    end
    if blacklist then
        return blacklist[spellId] ~= true
    end
    return true
end

-- Check if an aura passes classification filter (OR logic, inline query).
-- Returns true if aura should be shown.
-- Fail-open: if API fails or returns secret, show the aura.
-- No per-auraInstanceID caching — classify inline during each scan.
-- IsAuraFilteredOutByInstanceID is C-side and fast.
local function AuraPassesFilter(unit, auraInstanceID, filterStrings)
    if not filterStrings or #filterStrings == 0 then
        return false
    end

    if not auraInstanceID or IsSecretValue(auraInstanceID) then
        return true -- fail-open
    end

    if not C_UnitAuras or not C_UnitAuras.IsAuraFilteredOutByInstanceID then
        return true
    end

    for _, filterStr in ipairs(filterStrings) do
        local filteredOut = IsAuraFilteredOut(unit, auraInstanceID, filterStr)
        if filteredOut == nil or IsSecretValue(filteredOut) then
            return true -- fail-open on error/secret
        end
        if not filteredOut then
            return true -- aura matches this classification
        end
    end

    return false
end

---------------------------------------------------------------------------
-- AURA PRIORITY: Sort auras by importance
---------------------------------------------------------------------------
local PRIORITY_DISPELLABLE = 3
local PRIORITY_BOSS = 2
local PRIORITY_NORMAL = 1

local function GetAuraPriority(auraData)
    if not auraData then return 0 end
    local isDispellable = SafeValue(auraData.dispelName, nil)
    local isBoss = SafeValue(auraData.isBossAura, false)

    if isDispellable then return PRIORITY_DISPELLABLE end
    if isBoss then return PRIORITY_BOSS end
    return PRIORITY_NORMAL
end

---------------------------------------------------------------------------
-- UNIFIED ELEMENT RENDER (groupframes_aura_render.lua is the sole consumer)
---------------------------------------------------------------------------
-- The v46 aura element model (groupframes_aura_model.lua) drives every group-
-- frame aura visual. For each visible frame we resolve the unit's active spec,
-- build the element work list (tracked matches pre-resolved by the model;
-- filterStrip matches resolved here from the shared cache via the element's own
-- filter config), dispatch each to the renderer, and release any element id
-- whose frames linger from a prior pass (element removed/disabled/spec change).

-- Forward declarations: GetFrameAuraSettings (and its GetVisualDB* helpers) are
-- defined just below in the panel-render section; the unified render path runs
-- only at runtime, so the upvalues are bound by the time it is called.
local GetFrameAuraSettings
local _renderCurrentIDs = {}

-- Active player spec (mirrors the editor + the retired pinned-aura module).
local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and GetSpecializationInfo then
        return (GetSpecializationInfo(specIndex))
    end
    return nil
end

-- Build the ordered, capped match set for a filterStrip element from the shared
-- cache. Reuses the same filter primitives the legacy buff/debuff panels used:
--   auraType HELPFUL/HARMFUL bucket, filterMode (off|classification|whitelist),
--   onlyMine (HELPFUL|PLAYER / HARMFUL|PLAYER probe), hidePermanent,
--   classification OR-match, whitelist/blacklist by spellID, priority sort
--   (debuffs), dedupeDefensives, capped at maxIcons.
-- Returns a fresh ORDERED array { auraData, ... } in the priority order the
-- strip computed (debuffs: dispellable > boss > normal; helpful: scan order),
-- already capped at maxIcons. RenderIcon iterates this verbatim — it does NOT
-- re-sort by spellID — so the consumer's priority order reaches the screen.
local _stripPrioMap = {}
local function StripPrioritySort(a, b)
    return (_stripPrioMap[a] or 0) > (_stripPrioMap[b] or 0)
end

-- Reusable scratch for the zero-alloc render path. Each is filled and fully
-- consumed within a single RenderFrameElements pass (Render:Dispatch only reads
-- the match tables synchronously and never retains them), so sharing across
-- frames in the UNIT_AURA combat fan-out is safe and eliminates per-frame GC
-- churn. _activeElementsScratch / _trackedMatchesScratch feed RenderFrameElements;
-- the _strip* set feeds BuildFilterStripMatches.
local _activeElementsScratch = {}
local _trackedMatchesScratch = {}
local _stripOutScratch = {}
local _stripOrderedScratch = {}
local _stripSeenScratch = {}
local _stripClassFiltersScratch = {}

local function BuildFilterStripMatches(unit, cache, element, dedupSet)
    local out = _stripOutScratch
    wipe(out)
    if not cache then return out end
    local harmful = element.auraType == "HARMFUL"
    local list = harmful and cache.debuffs or cache.buffs
    if not list or #list == 0 then return out end

    local filterMode = element.filterMode or "off"
    local classifications = element.classifications
    local whitelist = element.whitelist
    local blacklist = element.blacklist
    if whitelist and not next(whitelist) then whitelist = nil end
    if blacklist and not next(blacklist) then blacklist = nil end
    local onlyMine = element.onlyMine == true
    local hidePermanent = element.hidePermanent == true
    local dedupeDefensives = element.dedupeDefensives ~= false

    -- Build the classification filter-string list for this element (OR logic).
    local classFilters
    if filterMode == "classification" and classifications then
        classFilters = _stripClassFiltersScratch
        wipe(classFilters)
        local map = harmful and DEBUFF_CLASSIFICATION_MAP or BUFF_CLASSIFICATION_MAP
        for key, filterStr in pairs(map) do
            if classifications[key] then classFilters[#classFilters + 1] = filterStr end
        end
        if #classFilters == 0 then classFilters = nil end
    end
    local useWhitelist = filterMode == "whitelist" and whitelist

    local onlyMineFilter = harmful and "HARMFUL|PLAYER" or "HELPFUL|PLAYER"
    local ordered = _stripOrderedScratch
    wipe(ordered)
    for i = 1, #list do
        local auraData = list[i]
        local instID = auraData and auraData.auraInstanceID
        if instID then
            local passes = true

            -- dedupeDefensives: skip auras already shown by the defensive
            -- indicator (the only surviving external dedup source).
            if passes and dedupeDefensives and dedupSet and dedupSet[instID] then
                passes = false
            end

            if passes and hidePermanent then
                local dur = SafeToNumber(auraData.duration, -1)
                if dur == 0 then passes = false end
            end

            if passes and onlyMine and IsAuraFilteredOut and not IsSecretValue(instID) then
                local fo = IsAuraFilteredOut(unit, instID, onlyMineFilter)
                if fo and not IsSecretValue(fo) then passes = false end
            end

            if passes and classFilters then
                if not AuraPassesFilter(unit, instID, classFilters) then passes = false end
            elseif passes and useWhitelist then
                if not AuraPassesSpellFilter(auraData, whitelist, nil) then passes = false end
            end

            if passes and blacklist then
                if not AuraPassesSpellFilter(auraData, nil, blacklist) then passes = false end
            end

            if passes then ordered[#ordered + 1] = auraData end
        end
    end

    -- Priority-sort harmful strips (matches legacy debuff panel ordering);
    -- helpful strips kept in scan order (matches legacy buff panel behavior).
    if harmful and #ordered > 1 then
        wipe(_stripPrioMap)
        for i = 1, #ordered do _stripPrioMap[ordered[i]] = GetAuraPriority(ordered[i]) end
        table.sort(ordered, StripPrioritySort)
    end

    -- Cap at maxIcons (0 / nil = unlimited) and emit an ORDERED array in the
    -- priority order computed above (RenderIcon iterates it verbatim — it no
    -- longer re-sorts by spellID). The cap window enforces both the visible
    -- count and (for debuffs) the priority selection. Per-spellID dedup is kept
    -- so two instances of the same spell collapse to one icon, exactly as the
    -- old { [spellID] = auraData } map did.
    local maxIcons = SafeToNumber(element.maxIcons, 0)
    local n = #ordered
    if maxIcons > 0 and maxIcons < n then n = maxIcons end
    local seen = _stripSeenScratch
    wipe(seen)
    for i = 1, n do
        local auraData = ordered[i]
        local spellID = SafeValue(auraData.spellId, nil) or auraData.auraInstanceID
        if spellID then
            if seen[spellID] == nil then
                seen[spellID] = true
                out[#out + 1] = auraData
            end
        else
            out[#out + 1] = auraData
        end
    end
    return out
end

-- Per-frame element render: dispatch the work list and release stale element
-- frames. `cache` is the unit's shared aura cache entry (may be nil → only
-- empty/health-clear renders happen). The set of element ids rendered last pass
-- is tracked on frame._quiRenderedAuraElementIDs so any id that drops out (an
-- element removed/disabled, or a spec change) gets released this pass.
local function ReleaseAllRenderedElements(frame, Render)
    local prev = frame._quiRenderedAuraElementIDs
    if prev then
        for id in pairs(prev) do
            Render:Release(frame, id)
            prev[id] = nil
        end
    end
    -- A health-tint element may own the tint without a tracked id snapshot.
    if frame._quiAuraRenderHealthTintOwner then
        Render:Release(frame, frame._quiAuraRenderHealthTintOwner)
    end
end

-- AURA RELEVANCE DESCRIPTOR (reverse lookup for the dirty fan-out) -----------
-- Per aura-config: which buckets it shows a strip for, whether it has any tracked
-- element, and the union of tracked spellIDs. Lets the render fan-out skip a
-- whole frame whose elements the delta never touched, in O(changed spells)
-- instead of rebuilding the element list. Cached per (config table, spec, gen);
-- the generation bumps on any settings change (InvalidateLayout / RefreshAll).
-- Held weak-keyed so it never lands in SavedVariables and GC'd configs don't leak.
local _relGeneration = 0
local _relCache = setmetatable({}, { __mode = "k" })
local function GetAuraRelevance(auras, specID)
    local rel = _relCache[auras]
    if rel and rel.gen == _relGeneration and rel.specID == specID then
        return rel
    end
    if not rel then
        rel = { trackedSpells = {} }
        _relCache[auras] = rel
    end
    rel.gen = _relGeneration
    rel.specID = specID
    rel.hasHelpfulStrip = false
    rel.hasHarmfulStrip = false
    rel.hasTracked = false
    wipe(rel.trackedSpells)
    -- Rare path (only on spec/settings change): a plain alloc here is fine.
    local elements = AuraModel.ActiveElementsForSpec(auras, specID)
    for i = 1, #elements do
        local e = elements[i]
        if e.mode == "filterStrip" then
            if e.auraType == "HARMFUL" then
                rel.hasHarmfulStrip = true
            else
                rel.hasHelpfulStrip = true
            end
        elseif e.mode == "tracked" then
            rel.hasTracked = true
            local spells = e.spells
            if spells then
                for j = 1, #spells do rel.trackedSpells[spells[j]] = true end
            end
        end
    end
    return rel
end

-- True if this delta could change anything the frame's elements render.
local function DeltaTouchesFrame(rel, dirty)
    if dirty.helpful and rel.hasHelpfulStrip then return true end
    if dirty.harmful and rel.hasHarmfulStrip then return true end
    if rel.hasTracked then
        if dirty.spellsUncertain then return true end
        for sid in pairs(dirty.spells) do
            if rel.trackedSpells[sid] then return true end
        end
    end
    return false
end

-- `dirty` (optional): the delta summary from ApplyAuraDelta. When present, frames
-- and elements the delta never touched skip re-dispatch (their widgets stay as
-- they are). nil = full render (settings refresh / full scan / cold) → all.
local function RenderFrameElements(frame, cache, dirty)
    if not frame or not frame.unit then return end
    local Render = GetRender()
    if not Render then return end

    local auras = GetFrameAuraSettings(frame)

    -- Auras disabled (or no config): tear down every element on this frame.
    if not auras or auras.enabled == false then
        ReleaseAllRenderedElements(frame, Render)
        return
    end

    local specID = GetPlayerSpecID()
    if AuraModel.EnsureSeeded then AuraModel.EnsureSeeded(auras) end

    -- Frame-level dirty skip: if this delta can't touch any element this frame
    -- shows, leave every widget exactly as-is (no element rebuild, no release).
    local rel = GetAuraRelevance(auras, specID)
    if dirty and not DeltaTouchesFrame(rel, dirty) then
        if auraStats then auraStats.frameSkips = auraStats.frameSkips + 1 end
        return
    end

    -- Zero-alloc render: iterate the active elements directly into reusable
    -- scratch tables. Render:Dispatch only reads matches synchronously and never
    -- retains them, so the scratch is safe to reuse across frames/events.
    local elements = AuraModel.ActiveElementsForSpec(auras, specID, _activeElementsScratch)

    local rendered = frame._quiRenderedAuraElementIDs
    if not rendered then
        rendered = {}
        frame._quiRenderedAuraElementIDs = rendered
    end

    local current = _renderCurrentIDs
    wipe(current)
    local dedupSet = frame._defensiveAuraIDs
    for i = 1, #elements do
        local element = elements[i]
        -- Per-element dirty gate: skip the (expensive) match build + Dispatch for
        -- elements the delta didn't touch, but still record the id so the release
        -- reconciliation below never drops a clean element.
        local elementDirty = (dirty == nil)
        if not elementDirty then
            if element.mode == "filterStrip" then
                if element.auraType == "HARMFUL" then
                    elementDirty = dirty.harmful
                else
                    elementDirty = dirty.helpful
                end
            elseif element.mode == "tracked" then
                if dirty.spellsUncertain then
                    elementDirty = true
                else
                    local spells = element.spells
                    if spells then
                        for j = 1, #spells do
                            if dirty.spells[spells[j]] then elementDirty = true; break end
                        end
                    end
                end
            end
        end
        current[element.id] = true
        if elementDirty then
            if auraStats then auraStats.elementsDispatched = auraStats.elementsDispatched + 1 end
            local matches
            if element.mode == "filterStrip" then
                matches = BuildFilterStripMatches(frame.unit, cache, element, dedupSet)
            elseif element.mode == "tracked" then
                matches = AuraModel.PopulateElementMatches(element, cache, _trackedMatchesScratch)
            end
            Render:Dispatch(frame, element, matches)
        elseif auraStats then
            auraStats.elementSkips = auraStats.elementSkips + 1
        end
    end

    -- Release element ids that rendered last pass but are gone this pass.
    for id in pairs(rendered) do
        if not current[id] then
            -- `:` already passes Render as self; R.Release(self, frame, elementID).
            -- The old `Render:Release(Render, frame, id)` shifted args (frame=Render,
            -- elementID=frame), so removed elements never actually released and their
            -- icons lingered on live frames until a /reload rebuilt them.
            Render:Release(frame, id)
        end
    end
    -- Snapshot the current set for the next pass (reuse the table).
    wipe(rendered)
    for id in pairs(current) do rendered[id] = true end
    -- Health-tint owner that no element rendered this pass (e.g. its element was
    -- removed) must be cleared too.
    local tintOwner = frame._quiAuraRenderHealthTintOwner
    if tintOwner and not current[tintOwner] then
        Render:Release(frame, tintOwner)
    end
end
QUI_GFA.RenderFrameElements = RenderFrameElements

---------------------------------------------------------------------------
-- UPDATE: Auras for a single frame
---------------------------------------------------------------------------
-- Pure duration/stack updates stay on the icon fast path below. Set changes
-- flow through the shared cache first, then refresh consumers from that state.

local function GetVisualDBForContext(isRaid)
    local db = GetDB()
    if not db then return nil end

    return (isRaid and db.raid or db.party) or db
end

local function GetVisualDBForFrame(frame)
    return GetVisualDBForContext(frame and frame._isRaid)
end

-- Assigns the forward-declared upvalue (declared in the unified-render block
-- above) so RenderFrameElements can resolve a frame's auras config.
function GetFrameAuraSettings(frame)
    local vdb = GetVisualDBForFrame(frame)
    return vdb and vdb.auras or nil
end

-- True when the unit's context has at least one enabled aura element.
local function HasActiveAuraElements(vdb)
    local auras = vdb and vdb.auras
    if not auras or auras.enabled == false then return false end
    local elements = auras.elements
    if type(elements) ~= "table" then return false end
    -- The "*" bucket plus any per-spec bucket can carry enabled elements. We do
    -- not resolve the live spec here (this is a cheap activity gate); any
    -- enabled element in any bucket keeps the aura pipeline alive for the unit.
    for _, bucket in pairs(elements) do
        if type(bucket) == "table" then
            for _, e in ipairs(bucket) do
                if type(e) == "table" and e.enabled ~= false then
                    return true
                end
            end
        end
    end
    return false
end

local function HasDispelOverlay(vdb)
    local healer = vdb and vdb.healer
    local dispel = healer and healer.dispelOverlay
    return dispel and dispel.enabled ~= false
end

local function HasDefensiveIndicator(vdb)
    local healer = vdb and vdb.healer
    local defensive = healer and healer.defensiveIndicator
    return defensive and defensive.enabled == true
end

-- A context has active aura consumers when it has any enabled aura element
-- (the unified model — strips + tracked auras) OR a healer dispel/defensive
-- overlay (those still consume the shared cache for classification subsets).
local function HasActiveAuraConsumers(isRaid)
    local vdb = GetVisualDBForContext(isRaid)
    if not vdb then return false end

    if HasActiveAuraElements(vdb) then return true end
    if HasDispelOverlay(vdb) then return true end
    if HasDefensiveIndicator(vdb) then return true end

    return false
end

local function FrameHasActiveAuraConsumers(frame)
    return frame and HasActiveAuraConsumers(frame._isRaid) == true
end

local function AnyVisibleFrameHasActiveAuraConsumers(frames, nFrames)
    local partyActive = nil
    local raidActive = nil
    for i = 1, nFrames do
        local frame = frames[i]
        if frame and frame:IsShown() then
            if frame._isRaid then
                if raidActive == nil then
                    raidActive = HasActiveAuraConsumers(true)
                end
                if raidActive then return true end
            else
                if partyActive == nil then
                    partyActive = HasActiveAuraConsumers(false)
                end
                if partyActive then return true end
            end
        end
    end
    return false
end

function QUI_GFA:HasActiveConsumersForContext(isRaid)
    return HasActiveAuraConsumers(isRaid)
end

function QUI_GFA:HasActiveConsumersForFrame(frame)
    return FrameHasActiveAuraConsumers(frame)
end

-- The legacy buff/debuff panel renderer (UpdateFrameAuras) and its refresh gate
-- (PanelRefreshNeededForFrame) were retired by the unified element renderer.
-- RenderFrameElements (above) is now the sole per-frame aura render path; the
-- shared cache still feeds it, plus the dispel/defensive overlays.

---------------------------------------------------------------------------
-- EVENT HOOKUP: Listen to UNIT_AURA via the group frame event system
---------------------------------------------------------------------------
-- Aura processing is inline in the dispatcher callback so all group-frame
-- consumers render from the same shared cache mutation. The unified element
-- renderer owns icon mouse-propagation, the duration timer, and per-instance
-- swipe refresh (Render:RefreshUpdatedIcons / RefreshUpdatedBars) — the legacy
-- panel mouse-fix + icon refresh helpers were retired with the panel renderer.

-- Subscribe to centralized aura dispatcher for group frame aura updates.
-- Stack/duration-only updates stay on the icon fast path. Add/remove/full
-- changes mutate the shared cache first, then all consumers read that state.
--
-- Pure stack/duration updates (the dominant raid path — 80%+ of events) skip
-- the entire scan + overlay + filter/sort pipeline and just refresh visible
-- icon cooldown swipes via DurationObject (zero Lua allocation).
--
-- Set changes try the shared delta path first; full updates still rescan.
-- AURA-STORM BUDGET: M+ pulls / raid-wide debuffs fire UNIT_AURA on ~40 units in
-- one frame. Even with per-frame dirty-skipping, full-update events bypass the
-- delta path and cost a full scan + full render each, so a wall of them in one
-- frame hitches. Cap the heavy path at AURA_HEAVY_BUDGET units/frame; overflow
-- units are queued and drained ~budget/frame by a hidden OnUpdate ticker, each
-- replayed with nil updateInfo (forced full scan — lossless, never a stale
-- delta). The stack/duration fast path and the first budget units stay instant;
-- steady state never exceeds budget, so normal play sees no added latency.
local AURA_HEAVY_BUDGET = 10
local _auraFrameStamp = 0
local _auraBudgetUsed = 0
local _auraDirtyUnits = {}
local _auraDrainFrame

local function HeavyBudgetAvailable()
    local now = (GetTime and GetTime()) or 0
    if now ~= _auraFrameStamp then
        _auraFrameStamp = now
        _auraBudgetUsed = 0
    end
    if _auraBudgetUsed >= AURA_HEAVY_BUDGET then return false end
    _auraBudgetUsed = _auraBudgetUsed + 1
    return true
end

-- Process one unit's set-change / full-update: update the shared cache, then run
-- the dirty-gated render fan-out across its frames. updateInfo == nil forces a
-- full scan + full render (used by the drain queue and any fallback path).
local function ProcessUnitAuraSetChange(unit, updateInfo)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end
    local frames = GF.unitFrameMap[unit]
    if not frames then return end
    local nFrames = #frames
    if nFrames == 0 then return end

    -- Keep the shared cache authoritative: full scan on full/fallback, else patch
    -- from the UNIT_AURA delta (which also publishes the dirty summary).
    local cacheUpdated = false
    local triedDelta = false
    if type(updateInfo) == "table" and not updateInfo.isFullUpdate then
        triedDelta = true
        cacheUpdated = ApplyAuraDelta(unit, updateInfo)
    elseif type(updateInfo) == "table" and updateInfo.isFullUpdate then
        if auraStats then auraStats.fullUpdateEvents = auraStats.fullUpdateEvents + 1 end
    end
    if cacheUpdated then
        if auraStats then auraStats.deltaApplied = auraStats.deltaApplied + 1 end
    else
        if triedDelta then
            if auraStats then auraStats.deltaFallback = auraStats.deltaFallback + 1 end
        end
        ScanUnitAuras(unit)
    end

    local cache = unitAuraCache[unit]
    local Render = GetRender()
    -- dirty == nil on a full scan / fallback → full render; else the gated path.
    local dirty = cacheUpdated and _deltaSummary or nil
    for f = 1, nFrames do
        local frame = frames[f]
        if frame:IsShown() then
            if auraStats then auraStats.framesRefreshed = auraStats.framesRefreshed + 1 end
            -- Healer overlays re-evaluate on EVERY aura set-change (and every full
            -- scan), never gated by the delta's per-bucket dirty flags. This path
            -- only runs for add/remove/full events — pure stack/duration updates
            -- return on the fast path in the subscriber and never reach here — so
            -- the unconditional re-check matches the set-change cadence without
            -- re-running on refresh ticks. The previous `dirty.harmful` /
            -- `dirty.defensive` gate could SKIP the clear: the flag reports which
            -- bucket the delta mutated, but a lingering dispel/defensive set entry
            -- can survive a delta whose summary flags the OTHER bucket (or whose
            -- shape the summary under-reports), leaving the overlay lit after the
            -- debuff is gone. The overlay readers are a cheap pre-classified set
            -- walk, so re-checking each set-change is effectively free.
            if GF.UpdateDispelOverlay then
                GF:UpdateDispelOverlay(frame)
            end
            if GF.UpdateDefensiveIndicator then
                GF:UpdateDefensiveIndicator(frame)
            end
            -- Unified element pass. The defensive overlay above refreshed
            -- frame._defensiveAuraIDs first so a filterStrip's dedupeDefensives
            -- sees the current set.
            RenderFrameElements(frame, cache, dirty)
        end
    end

    -- Mixed delta (updated + added/removed): reseat C-side bar timers on the
    -- updated instances so the fill drains from the live DurationObject.
    if cacheUpdated and Render and type(updateInfo) == "table"
        and updateInfo.updatedAuraInstanceIDs
        and (updateInfo.addedAuras or updateInfo.removedAuraInstanceIDs)
    then
        local updated = updateInfo.updatedAuraInstanceIDs
        if Render.RefreshUpdatedBars then
            if Render:RefreshUpdatedBars(frames, nFrames, unit, updated) then
                if auraStats then auraStats.mixedIconRefreshes = auraStats.mixedIconRefreshes + 1 end
            end
        end
    end
end

local function EnsureAuraDrainFrame()
    if _auraDrainFrame then return _auraDrainFrame end
    _auraDrainFrame = CreateFrame("Frame")
    _auraDrainFrame:Hide()
    _auraDrainFrame:SetScript("OnUpdate", function(self)
        for unit in pairs(_auraDirtyUnits) do
            if HeavyBudgetAvailable() then
                _auraDirtyUnits[unit] = nil
                -- The queued delta is stale by now → full scan (nil updateInfo).
                ProcessUnitAuraSetChange(unit, nil)
                if auraStats then auraStats.drainProcessed = auraStats.drainProcessed + 1 end
            else
                break -- budget spent this frame; resume next frame
            end
        end
        if not next(_auraDirtyUnits) then self:Hide() end
    end)
    return _auraDrainFrame
end

if ns.AuraEvents then
    ns.AuraEvents:Subscribe("roster", function(unit, updateInfo)
        local GF = ns.QUI_GroupFrames
        if not GF or not GF.initialized then return end

        local frames = GF.unitFrameMap[unit]
        if not frames then return end
        local nFrames = #frames
        if nFrames == 0 then return end
        if not AnyVisibleFrameHasActiveAuraConsumers(frames, nFrames) then
            if auraStats then auraStats.noConsumerSkips = auraStats.noConsumerSkips + 1 end
            return
        end

        -- Fast path: pure stack/duration update (no auras added or removed).
        -- The display set is identical — skip full scan + all overlay updates.
        -- Only refresh the specific icons whose aura actually updated. Never
        -- budgeted: it's zero-alloc and latency-critical. C-side, secret-safe.
        if type(updateInfo) == "table"
            and not updateInfo.isFullUpdate
            and not updateInfo.addedAuras
            and not updateInfo.removedAuraInstanceIDs
            and updateInfo.updatedAuraInstanceIDs
            and unitAuraCache[unit]
            and unitAuraCache[unit].hasFullScan
        then
            local updated = updateInfo.updatedAuraInstanceIDs
            local nUpdated = #updated
            if nUpdated == 0 then return end
            if auraStats then auraStats.fastUpdates = auraStats.fastUpdates + 1 end

            -- Reseat only the C-side swipes/bars on element visuals whose aura
            -- instance updated (zero alloc) — no element-list rebuild.
            local Render = GetRender()
            if Render then
                if Render.RefreshUpdatedIcons then
                    Render:RefreshUpdatedIcons(frames, nFrames, unit, updated)
                end
                if Render.RefreshUpdatedBars then
                    Render:RefreshUpdatedBars(frames, nFrames, unit, updated)
                end
            end
            return
        end

        -- Heavy path (set change / full update): budget to spread aura storms.
        -- Under budget → process inline (instant). Over → queue + drain over the
        -- next frames. Steady state never exceeds budget, so no added latency.
        if HeavyBudgetAvailable() then
            _auraDirtyUnits[unit] = nil
            ProcessUnitAuraSetChange(unit, updateInfo)
        else
            _auraDirtyUnits[unit] = true
            if auraStats then auraStats.heavyDeferred = auraStats.heavyDeferred + 1 end
            EnsureAuraDrainFrame():Show()
        end
    end)
end

---------------------------------------------------------------------------
-- PUBLIC: Invalidate aura layout (call when aura settings change in options)
---------------------------------------------------------------------------
-- The shared cache drives the dispel/defensive subsets and the unified renderer
-- resolves filterStrip matches at render time, so settings changes need no cache
-- mutation here. It MUST bump the relevance generation, though: a config edit
-- (add/remove/retarget an element) changes which spells/buckets each frame cares
-- about, invalidating the cached dirty-skip descriptors.
function QUI_GFA:InvalidateLayout()
    _relGeneration = _relGeneration + 1
end

---------------------------------------------------------------------------
-- PUBLIC: Refresh all frames
---------------------------------------------------------------------------
function QUI_GFA:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    -- Full refresh = settings may have changed; invalidate cached dirty-skip
    -- descriptors so the next render rebuilds them from the current config.
    _relGeneration = _relGeneration + 1
    for unit, list in pairs(GF.unitFrameMap) do
        local shouldScan = AnyVisibleFrameHasActiveAuraConsumers(list, #list)
        if shouldScan then
            ScanUnitAuras(unit)
        end
        local cache = unitAuraCache[unit]
        for i = 1, #list do
            local frame = list[i]
            if frame and frame:IsShown() then
                RenderFrameElements(frame, cache)
            end
        end
    end
end

function QUI_GFA:RefreshFrame(frame)
    if frame and frame.unit and FrameHasActiveAuraConsumers(frame) then
        ScanUnitAuras(frame.unit)
    end
    RenderFrameElements(frame, frame and frame.unit and unitAuraCache[frame.unit] or nil)
end

function QUI_GFA:RenderFrame(frame)
    RenderFrameElements(frame, frame and frame.unit and unitAuraCache[frame.unit] or nil)
end
