--[[
    QUI Group Frames - Aura System
    Compact aura display for group frames with priority filtering,
    table pooling, shared aura timer, and duration color coding.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = ns.LSM
local QUICore = ns.Addon
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local ApplyCooldownFromAura = Helpers.ApplyCooldownFromAura
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

-- Upvalue hot-path globals
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local wipe = wipe
local format = format
local GetTime = GetTime
local UnitExists = UnitExists
local C_UnitAuras = C_UnitAuras
local table_remove = table.remove
local sub = string.sub
local CreateFrame = CreateFrame
local table_insert = table.insert

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFA = {}
ns.QUI_GroupFrameAuras = QUI_GFA

-- Weak-keyed state for aura icons (taint safety)
local auraIconState = Helpers.CreateStateTable()

-- Layout versioning: only reposition icons when settings change
local layoutVersion = 0
local frameLayoutVersions = Helpers.CreateStateTable()

-- CENTER grow direction: track previous visible count per frame to skip
-- relayout when the count hasn't changed (avoids ClearAllPoints/SetPoint thrashing).
local framePrevDebuffCount = Helpers.CreateStateTable()
local framePrevBuffCount = Helpers.CreateStateTable()

-- (pendingAuraUnits removed: inline processing in dispatcher callback
-- eliminates the double-coalescing layer that added 1 frame of latency)

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
--     panelBuffs             = { [instID] = true },     -- passes user buff filter
--     panelDebuffs           = { [instID] = true },     -- passes user debuff filter
--     -- Curated-list matches keyed by entry index (per-spec)
--     indicatorMatches       = { [entryIdx] = auraData },
--     pinnedMatches          = { [slotIdx]  = auraData },
--     -- Pre-sorted display arrays — UpdateFrameAuras walks these directly
--     panelBuffsSorted       = { [i] = auraData },
--     panelDebuffsSorted     = { [i] = auraData },
--     -- Bookkeeping
--     panelBuffsDirty        = boolean,
--     panelDebuffsDirty      = boolean,
--     hasFullScan            = boolean,
-- }
--
-- Full scans rebuild the entire structure; UNIT_AURA deltas patch it
-- incrementally and re-run the rebuilders for any side that changed.
local unitAuraCache = {}
local auraStats = {
    fullScans = 0,
    slotScans = 0,
    legacyScans = 0,
    deltaApplied = 0,
    deltaFallback = 0,
    fastUpdates = 0,
    fullUpdateEvents = 0,
}
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_unitAuraCache", tbl = unitAuraCache }
    mp[#mp + 1] = { name = "GF_auraFullScans", fn = function() return auraStats.fullScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraSlotScans", fn = function() return auraStats.slotScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraLegacyScans", fn = function() return auraStats.legacyScans end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaApplied", fn = function() return auraStats.deltaApplied end, counter = true }
    mp[#mp + 1] = { name = "GF_auraDeltaFallback", fn = function() return auraStats.deltaFallback end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFastUpdates", fn = function() return auraStats.fastUpdates end, counter = true }
    mp[#mp + 1] = { name = "GF_auraFullUpdateEvents", fn = function() return auraStats.fullUpdateEvents end, counter = true }
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

-- Forward declaration: defined later in the file, near the filter cache and
-- comparator helpers it depends on. Called from ScanUnitAuras and
-- ApplyAuraDelta to populate the Phase-1 panel-filter subsets and pre-sorted
-- display arrays. Kept as an upvalue so the cache-mutation path can call it
-- without taking on a load-order dependency on the filter infrastructure.
local RebuildPanelSubsetsAndSort

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
        panelBuffs = {},
        panelDebuffs = {},
        -- Curated-list matches populated by sibling modules at delta time
        indicatorMatches = {},
        pinnedMatches = {},
        -- Pre-sorted display arrays
        panelBuffsSorted = {},
        panelDebuffsSorted = {},
        -- Bookkeeping
        panelBuffsDirty = false,
        panelDebuffsDirty = false,
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
    wipe(cache.panelBuffs)
    wipe(cache.panelDebuffs)
    wipe(cache.indicatorMatches)
    wipe(cache.pinnedMatches)
    wipe(cache.panelBuffsSorted)
    wipe(cache.panelDebuffsSorted)
    cache.panelBuffsDirty = false
    cache.panelDebuffsDirty = false
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

local function AppendAuraToBucket(cache, bucketName, auraData)
    local bucket = bucketName == "buffs" and cache.buffs or cache.debuffs
    bucket[#bucket + 1] = auraData

    local instID = auraData and auraData.auraInstanceID
    if not instID then
        return
    end

    if bucketName == "buffs" then
        cache.buffsByID[instID] = auraData
        cache.buffsIndexByID[instID] = #bucket
    else
        cache.debuffsByID[instID] = auraData
        cache.debuffsIndexByID[instID] = #bucket
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

    auraStats.fullScans = auraStats.fullScans + 1
    if ScanUnitAurasBySlot(unit, cache) then
        auraStats.slotScans = auraStats.slotScans + 1
    elseif ScanUnitAurasLegacy(unit, cache) then
        auraStats.legacyScans = auraStats.legacyScans + 1
    else
        return cache
    end

    RebuildDebuffMaps(unit, cache)
    RebuildBuffMaps(unit, cache)
    cache.panelBuffsDirty = true
    cache.panelDebuffsDirty = true
    if RebuildPanelSubsetsAndSort then
        RebuildPanelSubsetsAndSort(unit, cache)
    end
    cache.hasFullScan = true
    return cache
end

local function ApplyAuraDelta(unit, updateInfo)
    local cache = unitAuraCache[unit]
    if not cache or not cache.hasFullScan or type(updateInfo) ~= "table" then
        return false
    end

    local buffsDirty = false
    local debuffsDirty = false
    local GetAuraByInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID

    if updateInfo.addedAuras then
        for i = 1, #updateInfo.addedAuras do
            local auraData = updateInfo.addedAuras[i]
            local bucketName = ResolveAuraBucket(unit, auraData)
            if not bucketName then
                return false
            end
            AppendAuraToBucket(cache, bucketName, auraData)
            if bucketName == "buffs" then
                buffsDirty = true
            else
                debuffsDirty = true
            end
        end
    end

    if updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs > 0 then
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
                local freshAura = GetAuraByInstanceID(unit, instID)
                if not freshAura then
                    return false
                end
                if not ReplaceAuraInBucket(cache, bucketName, instID, freshAura) then
                    return false
                end
                if bucketName == "buffs" then
                    buffsDirty = true
                else
                    debuffsDirty = true
                end
            end
        end
    end

    if updateInfo.removedAuraInstanceIDs then
        for i = 1, #updateInfo.removedAuraInstanceIDs do
            local instID = updateInfo.removedAuraInstanceIDs[i]
            if cache.buffsByID[instID] then
                if RemoveAuraFromBucket(cache, "buffs", instID) then
                    buffsDirty = true
                end
            elseif cache.debuffsByID[instID] then
                if RemoveAuraFromBucket(cache, "debuffs", instID) then
                    debuffsDirty = true
                end
            end
        end
    end

    if buffsDirty then
        RebuildBuffMaps(unit, cache)
        cache.panelBuffsDirty = true
    end
    if debuffsDirty then
        RebuildDebuffMaps(unit, cache)
        cache.panelDebuffsDirty = true
    end

    if (buffsDirty or debuffsDirty) and RebuildPanelSubsetsAndSort then
        RebuildPanelSubsetsAndSort(unit, cache)
    end

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
QUI_GFA.auraStats = auraStats
QUI_GFA.ScanUnitAuras = ScanUnitAuras
QUI_GFA.ApplyAuraDelta = ApplyAuraDelta
QUI_GFA.PruneAuraCache = PruneAuraCache
-- Phase 1 redesign: callers can force a panel-subset rebuild (e.g. after
-- settings change before any UNIT_AURA delta arrives). Returns silently if
-- the assignment hasn't run yet (load order during early init).
QUI_GFA.RebuildPanelSubsetsAndSort = function(unit, cache)
    if RebuildPanelSubsetsAndSort then
        RebuildPanelSubsetsAndSort(unit, cache or unitAuraCache[unit])
    end
end

-- Phase 4 hook: spec-change handlers in indicator/pinned modules call this
-- before refreshing frames so cache.indicatorMatches / cache.pinnedMatches
-- repopulate with the new spec's entry/slot list. Does not re-render frames.
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
-- SHARED AURA TIMER: Single animation drives all icon duration updates
---------------------------------------------------------------------------
local timerIcons = {} -- Icons registered for duration updates
local sharedTimerFrame = CreateFrame("Frame")
local TIMER_INTERVAL = 0.2 -- Update duration text at 5 Hz (200ms)
local floor = math.floor
local timerIconCount = 0

-- Compute the bucket for a remaining duration WITHOUT allocating a string.
-- Only call FormatDuration when the bucket actually changed.
local function ComputeBucket(remaining)
    if remaining <= 0 then return -1 end
    if remaining < 10 then return floor(remaining * 10) end
    if remaining < 60 then return 1000 + floor(remaining) end
    if remaining < 3600 then return 2000 + floor(remaining / 60) end
    return 3000 + floor(remaining / 3600)
end

-- Returns formatted text for a given remaining duration.
-- PERF: Only call this when ComputeBucket indicates the display changed.
local function FormatDuration(remaining)
    if remaining <= 0 then return "" end
    if remaining < 10 then return format("%.1f", remaining) end
    if remaining < 60 then return format("%d", floor(remaining)) end
    if remaining < 3600 then return format("%dm", floor(remaining / 60)) end
    return format("%dh", floor(remaining / 3600))
end

-- Compute color band cheaply (no allocation).
local function ComputeColorBand(remaining, duration)
    if duration <= 0 or remaining <= 0 then return 0 end
    local pct = remaining / duration
    if pct > 0.5 then return 3 end
    if pct > 0.25 then return 2 end
    return 1
end

-- Returns (r, g, b, colorBand) where colorBand changes only when the color
-- would actually differ, allowing callers to skip redundant SetTextColor.
local function GetDurationColor(remaining, duration)
    if duration <= 0 or remaining <= 0 then
        return 1, 0, 0, 0
    end
    local pct = remaining / duration
    if pct > 0.5 then
        return 0.2, 1, 0.2, 3
    elseif pct > 0.25 then
        return 1, 1, 0, 2
    else
        return 1, 0.2, 0.2, 1
    end
end

local timerElapsed = 0
local cachedShowDurationColor = true
local GetFontPath

local function IsDurationTextEnabled(auraSettings, settingKey)
    if not auraSettings then return true end
    local specific = auraSettings[settingKey]
    if specific ~= nil then
        return specific ~= false
    end
    -- Backward compatibility for profiles that still only have the legacy shared key.
    return auraSettings.showDurationText ~= false
end

local function IsDurationTimeColorEnabled(auraSettings, settingKey)
    if not auraSettings then return true end
    local specific = auraSettings[settingKey]
    if specific ~= nil then
        return specific ~= false
    end
    return auraSettings.showDurationColor ~= false
end

local function GetDurationTextColor(auraSettings, colorKey)
    if auraSettings then
        local c = auraSettings[colorKey]
        if c then
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end
    end
    return 1, 1, 1, 1
end

local function GetDurationFontPath(auraSettings, fontKey)
    local fontName = auraSettings and auraSettings[fontKey]
    if fontName and fontName ~= "" then
        local fetched = LSM:Fetch("font", fontName)
        if fetched then return fetched end
    end
    return GetFontPath()
end

local function ApplyDurationTextStyle(icon, auraSettings, prefix)
    if not icon or not icon.durationText then return end

    local durationText = icon.durationText
    local fontPath = GetDurationFontPath(auraSettings, prefix .. "DurationFont")
    local fontSize = auraSettings and (auraSettings[prefix .. "DurationFontSize"] or auraSettings.durationFontSize) or 9
    local anchor = auraSettings and auraSettings[prefix .. "DurationAnchor"] or "BOTTOM"
    local offsetX = auraSettings and auraSettings[prefix .. "DurationOffsetX"] or 0
    local offsetY = auraSettings and auraSettings[prefix .. "DurationOffsetY"] or -6

    durationText:SetFont(fontPath, fontSize or 9, "OUTLINE")
    durationText:ClearAllPoints()
    durationText:SetPoint(anchor or "BOTTOM", icon, anchor or "BOTTOM", offsetX or 0, offsetY or -6)

    local state = icon._auraState
    if state then
        state._lastBucket = nil
        state._lastColorBand = nil
    end
end

local function SharedTimerOnUpdate(self, dt)
    timerElapsed = timerElapsed + dt
    if timerElapsed < TIMER_INTERVAL then return end
    timerElapsed = 0

    -- Skip when no group frames are active (solo play)
    local GF = ns.QUI_GroupFrames
    if not GF or not next(GF.unitFrameMap) then
        wipe(timerIcons)
        timerIconCount = 0
        self:SetScript("OnUpdate", nil)
        return
    end

    local now = GetTime()
    local db = GetDB()
    -- Pre-compute aura settings for both contexts (avoids per-icon table walks)
    local raidAuras = db and db.raid and db.raid.auras
    local partyAuras = db and db.party and db.party.auras
    for icon, state in pairs(timerIcons) do
        if not icon:IsShown() then
            -- Hidden icons no longer need timer work; UpdateFrameAuras will
            -- re-register them if they become visible again.
            timerIcons[icon] = nil
            timerIconCount = timerIconCount - 1
        elseif state.expirationTime then
            -- Values are guaranteed non-secret: UpdateAuraIcon only registers
            -- icons into timerIcons when duration passes IsSecretValue check.
            local expTime = state.expirationTime
            local dur = state.duration or 0
            local remaining = expTime - now

            if remaining > 0 then
                if icon.durationText then
                    local isRaid = icon.unitFrame and icon.unitFrame._isRaid
                    local auraSettings = isRaid and raidAuras or partyAuras
                    local showDurationText = IsDurationTextEnabled(auraSettings, icon._durationTextSettingKey)
                    if showDurationText then
                        -- PERF: Compute bucket (zero allocation) BEFORE formatting.
                        -- Only call FormatDuration (string.format) when display changes.
                        local bucket = ComputeBucket(remaining)
                        if bucket ~= state._lastBucket then
                            icon.durationText:SetText(FormatDuration(remaining))
                            state._lastBucket = bucket
                        end
                        -- Color: throttled to 1 Hz per icon for dynamic duration bands.
                        local useTimeColor = IsDurationTimeColorEnabled(auraSettings, icon._durationUseTimeColorKey)
                        if useTimeColor then
                            local lastColorTime = state._lastColorTime or 0
                            if (now - lastColorTime) >= 1.0 then
                                state._lastColorTime = now
                                local band = ComputeColorBand(remaining, dur)
                                if band ~= state._lastColorBand then
                                    local r, g, b = GetDurationColor(remaining, dur)
                                    icon.durationText:SetTextColor(r, g, b, 1)
                                    state._lastColorBand = band
                                end
                            end
                        elseif state._lastColorBand ~= "static" then
                            local r, g, b, a = GetDurationTextColor(auraSettings, icon._durationColorKey)
                            icon.durationText:SetTextColor(r, g, b, a)
                            state._lastColorBand = "static"
                        end
                    else
                        icon.durationText:SetText("")
                    end
                end
            else
                -- Expired
                if icon.durationText then icon.durationText:SetText("") end
                timerIcons[icon] = nil
                timerIconCount = timerIconCount - 1
            end
        else
            timerIcons[icon] = nil
            timerIconCount = timerIconCount - 1
        end
    end

    -- Auto-disable when no icons remain
    if timerIconCount <= 0 then
        timerIconCount = 0
        self:SetScript("OnUpdate", nil)
    end
end

-- Start disabled — no icons at init
sharedTimerFrame:SetScript("OnUpdate", nil)

local function RegisterIconTimer(icon, state)
    local wasEmpty = timerIconCount == 0
    if not timerIcons[icon] then
        timerIconCount = timerIconCount + 1
    end
    timerIcons[icon] = state
    if wasEmpty then
        timerElapsed = 0
        sharedTimerFrame:SetScript("OnUpdate", SharedTimerOnUpdate)
    end
end

local function UnregisterIconTimer(icon)
    if timerIcons[icon] then
        timerIcons[icon] = nil
        timerIconCount = timerIconCount - 1
        if timerIconCount < 0 then timerIconCount = 0 end
    end
end

---------------------------------------------------------------------------
-- SLOT OFFSET: Calculate icon position for configurable grow direction
---------------------------------------------------------------------------
local function CalculateSlotOffset(index, iconSize, spacing, direction, totalCount)
    local step = (index - 1) * (iconSize + spacing)
    if direction == "RIGHT" then
        return step, 0
    elseif direction == "LEFT" then
        return -step, 0
    elseif direction == "CENTER" then
        local n = totalCount or 1
        local totalSpan = n * iconSize + math.max(n - 1, 0) * spacing
        return step - totalSpan / 2, 0
    elseif direction == "UP" then
        return 0, step
    elseif direction == "DOWN" then
        return 0, -step
    end
    return step, 0 -- fallback to RIGHT
end

local function ComposeAnchor(horizontal, vertical)
    if vertical == "TOP" then
        if horizontal == "LEFT" then return "TOPLEFT" end
        if horizontal == "RIGHT" then return "TOPRIGHT" end
        return "TOP"
    elseif vertical == "BOTTOM" then
        if horizontal == "LEFT" then return "BOTTOMLEFT" end
        if horizontal == "RIGHT" then return "BOTTOMRIGHT" end
        return "BOTTOM"
    end

    if horizontal == "LEFT" then return "LEFT" end
    if horizontal == "RIGHT" then return "RIGHT" end
    return "CENTER"
end

local function GetIconAnchorForGrow(frameAnchor, direction)
    local horizontal = frameAnchor and frameAnchor:find("LEFT") and "LEFT"
        or frameAnchor and frameAnchor:find("RIGHT") and "RIGHT"
        or "CENTER"
    local vertical = frameAnchor and frameAnchor:find("TOP") and "TOP"
        or frameAnchor and frameAnchor:find("BOTTOM") and "BOTTOM"
        or "CENTER"

    if direction == "RIGHT" or direction == "CENTER" then
        horizontal = "LEFT"
    elseif direction == "LEFT" then
        horizontal = "RIGHT"
    elseif direction == "UP" then
        vertical = "BOTTOM"
    elseif direction == "DOWN" then
        vertical = "TOP"
    end

    return ComposeAnchor(horizontal, vertical)
end

-- Track icons that need mouse setup deferred from combat
local pendingMouseFix = false

---------------------------------------------------------------------------
-- AURA ICON: Create/get icon for a frame
---------------------------------------------------------------------------
-- Cached font path: rebuilt on layout invalidation, avoids per-icon DB+LSM lookups.
local _cachedFontPath = nil

function GetFontPath()
    if _cachedFontPath then return _cachedFontPath end
    local db = GetDB()
    local vdb = db and (db.party or db)
    local general = vdb and vdb.general
    local fontName = general and general.font or "Quazii"
    _cachedFontPath = LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    return _cachedFontPath
end

local function CreateAuraIcon(parent, size)
    size = size or 16
    local icon = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    icon:SetSize(size, size)

    -- Render above healthBar (+0), healPrediction (+1), absorb (+2), dispel (+6)
    local baseLevel = parent.healthBar and parent.healthBar:GetFrameLevel() or parent:GetFrameLevel()
    icon:SetFrameLevel(baseLevel + 8)

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.icon = tex

    -- Border
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(icon) or 1
    icon:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    icon:SetBackdropBorderColor(0, 0, 0, 1)

    -- Cooldown swipe
    local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    icon.cooldown = cooldown

    -- Stack count text
    local stackText = icon:CreateFontString(nil, "OVERLAY")
    local fontPath = GetFontPath()
    stackText:SetFont(fontPath, 10, "OUTLINE")
    stackText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    stackText:SetJustifyH("RIGHT")
    icon.stackText = stackText

    -- Duration text
    local durationText = icon:CreateFontString(nil, "OVERLAY")
    durationText:SetFont(fontPath, 9, "OUTLINE")
    durationText:SetPoint("TOP", icon, "BOTTOM", 0, -1)
    durationText:SetJustifyH("CENTER")
    icon.durationText = durationText

    -- Expiring pulse animation
    local pulseGroup = icon:CreateAnimationGroup()
    local pulseAlpha = pulseGroup:CreateAnimation("Alpha")
    pulseAlpha:SetFromAlpha(1)
    pulseAlpha:SetToAlpha(0.3)
    pulseAlpha:SetDuration(0.4)
    pulseGroup:SetLooping("BOUNCE")
    icon.pulseGroup = pulseGroup

    -- Mouse propagation so @mouseover targeting and click-casting keep
    -- working when the cursor is over aura icons.
    -- EnableMouse(true)                  → icon receives OnEnter/OnLeave (tooltips)
    -- SetPropagateMouseMotion(true)      → parent frame also gets motion events (@mouseover)
    -- SetPropagateMouseClicks(true)      → clicks pass through to parent (targeting/cast)
    -- SetMouseClickEnabled(false)        → icon itself doesn't consume clicks
    if not InCombatLockdown() then
        icon:EnableMouse(true)
        if icon.SetPropagateMouseMotion then icon:SetPropagateMouseMotion(true) end
        if icon.SetPropagateMouseClicks then icon:SetPropagateMouseClicks(true) end
        if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    else
        pendingMouseFix = true
    end

    -- Store parent unit frame reference for tooltip lookups
    icon.unitFrame = parent

    -- Aura tooltip on hover
    icon:SetScript("OnEnter", function(self)
        if not self:IsShown() then return end
        local state = auraIconState[self]
        local uf = self.unitFrame
        if not state or not uf or not uf.unit then return end
        local auraID = state.auraInstanceID
        if not auraID or IsSecretValue(auraID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetUnitAuraByAuraInstanceID then
            pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, uf.unit, auraID)
        end
        GameTooltip:Show()
    end)

    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    icon:Hide()
    return icon
end

local function SafeSetReverse(cooldown, reverse)
    if cooldown and cooldown.SetReverse then
        pcall(cooldown.SetReverse, cooldown, reverse == true)
    end
end

local function SafeSetDrawSwipe(cooldown, showSwipe)
    if cooldown and cooldown.SetDrawSwipe then
        pcall(cooldown.SetDrawSwipe, cooldown, showSwipe ~= false)
    end
end

local function ClearAuraIcon(icon)
    if not icon then return end
    icon:Hide()
    UnregisterIconTimer(icon)
    local state = icon._auraState
    if state then
        wipe(state)
    end
    if icon.durationText then icon.durationText:SetText("") end
    if icon.stackText then icon.stackText:SetText("") end
    if icon.cooldown then icon.cooldown:Clear() end
    if icon.pulseGroup and icon.pulseGroup:IsPlaying() then
        icon.pulseGroup:Stop()
    end
end

-- Dispel border colors (file-level to avoid per-call allocation)
local AURA_DISPEL_COLORS = {
    Magic   = { 0.2, 0.6, 1.0, 1 },
    Curse   = { 0.6, 0.0, 1.0, 1 },
    Disease = { 0.6, 0.4, 0.0, 1 },
    Poison  = { 0.0, 0.6, 0.0, 1 },
    Bleed   = { 0.8, 0.0, 0.0, 1 },
}

local function UpdateAuraIcon(icon, auraData, unit)
    if not icon or not auraData then
        ClearAuraIcon(icon)
        return
    end

    -- Reuse icon-level state table (created once, fields overwritten).
    -- Avoids per-icon table creation and keeps state off Blizzard frames (taint safety).
    local state = icon._auraState
    if not state then
        state = {}
        icon._auraState = state
        auraIconState[icon] = state  -- register for tooltip lookups
    end

    -- Cache owns the latest aura snapshot for set changes and full refreshes.
    local auraID = auraData.auraInstanceID
    local displayData = auraData

    -- Overwrite state fields (zero allocation)
    state.unit = unit
    state.auraInstanceID = auraID
    state.expirationTime = displayData.expirationTime
    state.duration = displayData.duration
    state.applications = displayData.applications

    -- Icon texture (C-side SetTexture handles secret values natively)
    if icon.icon then
        pcall(icon.icon.SetTexture, icon.icon, displayData.icon)
    end

    -- Stack count: GetAuraApplicationDisplayCount returns a display-ready
    -- string, fully secret-safe via C-side SetText.
    if icon.stackText then
        if auraID and not IsSecretValue(auraID) and C_UnitAuras.GetAuraApplicationDisplayCount then
            local ok, countStr = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraID, 2, 99)
            if ok and countStr then
                pcall(icon.stackText.SetText, icon.stackText, countStr)
            else
                icon.stackText:SetText("")
            end
        else
            local stacks = SafeToNumber(displayData.applications, 0)
            if stacks > 1 then
                icon.stackText:SetText(stacks)
            else
                icon.stackText:SetText("")
            end
        end
    end

    -- Cooldown swipe (prefer DurationObject → ExpirationTime → legacy)
    if icon.cooldown then
        local dur = displayData.duration
        local expTime = displayData.expirationTime

        ApplyCooldownFromAura(icon.cooldown, unit, auraID, expTime, dur, true)
    end

    -- Duration text + timer registration
    -- Skip entirely when values are secret (combat) — the cooldown swipe is
    -- already driven by DurationObject via C-side; Lua text/pulse would just
    -- SafeToNumber → 0 and do nothing useful.
    local dur = displayData.duration
    local expTime = displayData.expirationTime
    if not IsSecretValue(dur) and dur and dur > 0 then
        RegisterIconTimer(icon, state)

        -- Expiring pulse: uses per-frame cached setting (set by UpdateFrameAuras)
        -- to avoid calling GetDB() per icon (was ~120 DB lookups per aura batch)
        local showPulse = icon._cachedShowPulse
        if showPulse and not IsSecretValue(expTime) then
            local remaining = expTime - GetTime()
            if remaining > 0 and remaining < 5 then
                if icon.pulseGroup and not icon.pulseGroup:IsPlaying() then
                    icon.pulseGroup:Play()
                end
            else
                if icon.pulseGroup and icon.pulseGroup:IsPlaying() then
                    icon.pulseGroup:Stop()
                end
            end
        elseif icon.pulseGroup and icon.pulseGroup:IsPlaying() then
            icon.pulseGroup:Stop()
        end
    else
        UnregisterIconTimer(icon)
        if icon.durationText then icon.durationText:SetText("") end
        if icon.pulseGroup and icon.pulseGroup:IsPlaying() then
            icon.pulseGroup:Stop()
        end
    end

    -- Dispellable debuff border color
    if not IsSecretValue(displayData.dispelName) and displayData.dispelName then
        local dispelType = SafeValue(displayData.dispelName, nil)
        if dispelType and AURA_DISPEL_COLORS[dispelType] then
            local c = AURA_DISPEL_COLORS[dispelType]
            icon:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
        else
            icon:SetBackdropBorderColor(0.8, 0, 0, 1) -- Default debuff red
        end
    else
        icon:SetBackdropBorderColor(0, 0, 0, 1) -- Default black border
    end

    icon:Show()
end

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

-- Per-context (party/raid) cached filter data
-- Structure: filterCaches[contextKey] = { buffFilters={}, debuffFilters={}, filterMode="off", ... }
local filterCaches = { party = {}, raid = {} }
local cachedFilterVersion = -1

-- (Per-auraInstanceID classification cache removed: it grew unboundedly during
-- long encounters. Classification now happens inline during each full scan.
-- Cost stays bounded because full scans are coalesced and the filter checks
-- are C-side.)

local function InitFilterCache()
    return {
        buffFilters = {},
        debuffFilters = {},
        filterMode = "off",
        onlyMine = false,
        hidePermanent = false,
        buffWhitelist = nil,
        buffBlacklist = nil,
        debuffWhitelist = nil,
        debuffBlacklist = nil,
    }
end
filterCaches.party = InitFilterCache()
filterCaches.raid = InitFilterCache()

local function RebuildFilterCacheForContext(cache, auraSettings)
    if not auraSettings then return end

    cache.filterMode = auraSettings.filterMode or "off"
    cache.onlyMine = auraSettings.buffFilterOnlyMine or false
    cache.hidePermanent = auraSettings.buffHidePermanent or false

    wipe(cache.buffFilters)
    wipe(cache.debuffFilters)
    cache.buffWhitelist = nil
    cache.buffBlacklist = nil
    cache.debuffWhitelist = nil
    cache.debuffBlacklist = nil

    if cache.filterMode == "classification" then
        local buffClass = auraSettings.buffClassifications
        if buffClass then
            for key, filterStr in pairs(BUFF_CLASSIFICATION_MAP) do
                if buffClass[key] then
                    table_insert(cache.buffFilters, filterStr)
                end
            end
        end

        local debuffClass = auraSettings.debuffClassifications
        if debuffClass then
            for key, filterStr in pairs(DEBUFF_CLASSIFICATION_MAP) do
                if debuffClass[key] then
                    table_insert(cache.debuffFilters, filterStr)
                end
            end
        end
    elseif cache.filterMode == "whitelist" then
        local bwl = auraSettings.buffWhitelist
        if bwl and next(bwl) then cache.buffWhitelist = bwl end
        local dwl = auraSettings.debuffWhitelist
        if dwl and next(dwl) then cache.debuffWhitelist = dwl end
    end

    -- Blacklist always applies regardless of filter mode (additive filter)
    local bbl = auraSettings.buffBlacklist
    if bbl and next(bbl) then cache.buffBlacklist = bbl end
    local dbl = auraSettings.debuffBlacklist
    if dbl and next(dbl) then cache.debuffBlacklist = dbl end
end

local function RebuildFilterCache()
    local db = GetDB()
    if not db then return end

    -- Build party filter cache
    local partyVdb = db.party or db
    RebuildFilterCacheForContext(filterCaches.party, partyVdb.auras)

    -- Build raid filter cache
    local raidVdb = db.raid or db
    RebuildFilterCacheForContext(filterCaches.raid, raidVdb.auras)

    cachedFilterVersion = layoutVersion
end

local function GetFilterCache(isRaid)
    return isRaid and filterCaches.raid or filterCaches.party
end

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

-- Priority lookup table for zero-allocation sorting: auraData → priority.
-- Populated inline during aura collection, used by the sort comparator,
-- then wiped.  Eliminates AcquireAuraTable/ReleaseAuraTable per visible aura.
local _auraPrioMap = {}

-- Reusable sort comparator (avoids closure allocation per sort call)
local function AuraPrioritySort(a, b)
    return (_auraPrioMap[a] or 0) > (_auraPrioMap[b] or 0)
end

local function GetAuraPriority(auraData)
    if not auraData then return 0 end
    local isDispellable = SafeValue(auraData.dispelName, nil)
    local isBoss = SafeValue(auraData.isBossAura, false)

    if isDispellable then return PRIORITY_DISPELLABLE end
    if isBoss then return PRIORITY_BOSS end
    return PRIORITY_NORMAL
end

---------------------------------------------------------------------------
-- PHASE 1: Pre-classified panel subsets + pre-sorted display arrays
---------------------------------------------------------------------------
-- Populates cache.panelBuffs / panelDebuffs (instID-keyed sets passing the
-- user filter) and cache.panelBuffsSorted / panelDebuffsSorted (priority-
-- sorted auraData arrays). Render code does not yet read these — Phase 2
-- migrates UpdateFrameAuras over. Until then this is parallel work; the
-- spec accepts the cost (§6 R5) in exchange for landing the foundation.
--
-- Private prio map kept separate from render's _auraPrioMap so cache-time
-- and render-time sorts cannot clobber each other's state mid-frame.
local _cacheAuraPrioMap = {}

local function CachePrioritySort(a, b)
    return (_cacheAuraPrioMap[a] or 0) > (_cacheAuraPrioMap[b] or 0)
end

RebuildPanelSubsetsAndSort = function(unit, cache)
    if not cache then return end

    if cachedFilterVersion ~= layoutVersion then
        RebuildFilterCache()
    end

    local fCache = IsInRaid() and filterCaches.raid or filterCaches.party
    local useClassification = fCache.filterMode == "classification"
    local useWhitelist = fCache.filterMode == "whitelist"
    local onlyMine = fCache.onlyMine
    local hidePermanent = fCache.hidePermanent

    local panelBuffs = cache.panelBuffs
    local panelBuffsSorted = cache.panelBuffsSorted
    wipe(panelBuffs)
    wipe(panelBuffsSorted)

    local buffFilters = useClassification and #fCache.buffFilters > 0 and fCache.buffFilters or nil
    local buffs = cache.buffs
    for i = 1, #buffs do
        local auraData = buffs[i]
        local instID = auraData and auraData.auraInstanceID
        if instID then
            local passes = true
            -- hidePermanent: drop duration==0 buffs
            if hidePermanent then
                local dur = SafeToNumber(auraData.duration, -1)
                if dur == 0 then
                    passes = false
                end
            end
            -- onlyMine: HELPFUL|PLAYER filter (player-cast buffs only)
            if passes and onlyMine and IsAuraFilteredOut and not IsSecretValue(instID) then
                local fo = IsAuraFilteredOut(unit, instID, "HELPFUL|PLAYER")
                if fo and not IsSecretValue(fo) then
                    passes = false
                end
            end
            if passes and buffFilters and not AuraPassesFilter(unit, instID, buffFilters) then
                passes = false
            end
            if passes and useWhitelist and fCache.buffWhitelist then
                if not AuraPassesSpellFilter(auraData, fCache.buffWhitelist, nil) then
                    passes = false
                end
            end
            if passes and fCache.buffBlacklist then
                if not AuraPassesSpellFilter(auraData, nil, fCache.buffBlacklist) then
                    passes = false
                end
            end
            if passes then
                panelBuffs[instID] = true
                panelBuffsSorted[#panelBuffsSorted + 1] = auraData
            end
        end
    end

    -- Buffs have equal priority — no sort needed (matches existing render
    -- behavior where the buff path skips table.sort entirely).
    cache.panelBuffsDirty = false

    local panelDebuffs = cache.panelDebuffs
    local panelDebuffsSorted = cache.panelDebuffsSorted
    wipe(panelDebuffs)
    wipe(panelDebuffsSorted)

    local debuffFilters = useClassification and #fCache.debuffFilters > 0 and fCache.debuffFilters or nil
    local debuffs = cache.debuffs
    for i = 1, #debuffs do
        local auraData = debuffs[i]
        local instID = auraData and auraData.auraInstanceID
        if instID then
            local passes = true
            if debuffFilters and not AuraPassesFilter(unit, instID, debuffFilters) then
                passes = false
            end
            if passes and useWhitelist and fCache.debuffWhitelist then
                if not AuraPassesSpellFilter(auraData, fCache.debuffWhitelist, nil) then
                    passes = false
                end
            end
            if passes and fCache.debuffBlacklist then
                if not AuraPassesSpellFilter(auraData, nil, fCache.debuffBlacklist) then
                    passes = false
                end
            end
            if passes then
                panelDebuffs[instID] = true
                panelDebuffsSorted[#panelDebuffsSorted + 1] = auraData
            end
        end
    end

    if #panelDebuffsSorted > 1 then
        wipe(_cacheAuraPrioMap)
        for i = 1, #panelDebuffsSorted do
            _cacheAuraPrioMap[panelDebuffsSorted[i]] = GetAuraPriority(panelDebuffsSorted[i])
        end
        table.sort(panelDebuffsSorted, CachePrioritySort)
    end
    cache.panelDebuffsDirty = false

    -- Phase 4: indicator + pinned modules populate cache.indicatorMatches /
    -- cache.pinnedMatches keyed by entry index. Each module computes once
    -- per delta; render walks its configured entry list and looks up.
    local GFI = ns.QUI_GroupFrameIndicators
    if GFI and GFI.PopulateCacheMatches then
        GFI:PopulateCacheMatches(unit, cache)
    end
    local GFP = ns.QUI_GroupFramePinnedAuras
    if GFP and GFP.PopulateCacheMatches then
        GFP:PopulateCacheMatches(unit, cache)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Auras for a single frame
---------------------------------------------------------------------------
-- Pure duration/stack updates stay on the icon fast path below. Set changes
-- flow through the shared cache first, then refresh consumers from that state.

local EMPTY_AURA_LIST = {}  -- Sentinel for missing-cache reads (do not mutate)
local _renderBuffs = {}     -- Reusable scratch: pre-sorted buffs after frame-local dedup

local function UpdateFrameAuras(frame)
    if not frame or not frame.unit then return end

    local db = GetDB()
    if not db then return end
    local isRaid = frame._isRaid
    local vdb = (isRaid and db.raid or db.party) or db
    if not vdb.auras then return end
    local auraSettings = vdb.auras

    -- Cache pulse setting for this frame (read by UpdateAuraIcon, avoids per-icon GetDB)
    local showPulse = auraSettings.showExpiringPulse ~= false
    frame._cachedShowPulse = showPulse

    -- Layout versioning: only reposition icons when settings have changed
    local needsLayout = (frameLayoutVersions[frame] or 0) ~= layoutVersion

    local unit = frame.unit
    if not UnitExists(unit) then
        -- Hide all icons
        if frame.debuffIcons then
            for _, icon in ipairs(frame.debuffIcons) do
                ClearAuraIcon(icon)
            end
        end
        if frame.buffIcons then
            for _, icon in ipairs(frame.buffIcons) do
                ClearAuraIcon(icon)
            end
        end
        return
    end

    -- Phase 2: cache rebuild owns classification + filter + sort. The render
    -- path reads pre-classified, pre-sorted arrays. Lazy-rebuild covers the
    -- case where layoutVersion bumped (settings changed) but no UNIT_AURA
    -- delta has fired since to refresh the panel arrays.
    local cache = unitAuraCache[unit]
    if cache and (cache.panelBuffsDirty or cache.panelDebuffsDirty) then
        RebuildPanelSubsetsAndSort(unit, cache)
    end

    -- Process debuffs
    if auraSettings.showDebuffs then
        local maxDebuffs = auraSettings.maxDebuffs or 3
        local iconSize = auraSettings.debuffIconSize or 16

        -- Ensure icon pool exists
        if not frame.debuffIcons then
            frame.debuffIcons = {}
        end

        -- Read pre-sorted debuff array directly. Cache rebuild already ran
        -- classification, whitelist, blacklist, and priority sort.
        local sortedDebuffs = (cache and cache.panelDebuffsSorted) or EMPTY_AURA_LIST

        -- Display up to maxDebuffs
        local dAnchor = auraSettings.debuffAnchor or "BOTTOMRIGHT"
        local dGrow = auraSettings.debuffGrowDirection or "LEFT"
        local dSpacing = auraSettings.debuffSpacing or 2
        local dOffX = auraSettings.debuffOffsetX or -2
        local dOffY = auraSettings.debuffOffsetY or -18
        if sub(dAnchor, 1, 6) == "BOTTOM" then dOffY = dOffY + (frame._bottomPad or 0) end
        local dIconAnchor = GetIconAnchorForGrow(dAnchor, dGrow)
        -- CENTER: only relayout when visible count actually changes (skip thrashing)
        local dVisibleCount = nil
        if dGrow == "CENTER" then
            local vc = math.min(#sortedDebuffs, maxDebuffs)
            if vc ~= (framePrevDebuffCount[frame] or -1) then
                dVisibleCount = vc
                framePrevDebuffCount[frame] = vc
            end
        end
        for i = 1, maxDebuffs do
            local auraData = sortedDebuffs[i]
            if not frame.debuffIcons[i] then
                frame.debuffIcons[i] = CreateAuraIcon(frame, iconSize)
                needsLayout = true -- New icon always needs positioning
            end
            -- Only reposition when layout settings changed (version mismatch)
            if needsLayout or dVisibleCount then
                local offX, offY = CalculateSlotOffset(i, iconSize, dSpacing, dGrow, dVisibleCount)
                frame.debuffIcons[i]:ClearAllPoints()
                frame.debuffIcons[i]:SetPoint(dIconAnchor, frame, dAnchor, dOffX + offX, dOffY + offY)
                frame.debuffIcons[i]:SetSize(iconSize, iconSize)
            end
            local icon = frame.debuffIcons[i]
            icon._durationTextSettingKey = "showDebuffDurationText"
            icon._durationUseTimeColorKey = "debuffDurationUseTimeColor"
            icon._durationColorKey = "debuffDurationColor"
            ApplyDurationTextStyle(icon, auraSettings, "debuff")
            SafeSetDrawSwipe(icon and icon.cooldown, auraSettings.debuffHideSwipe ~= true)
            SafeSetReverse(icon and icon.cooldown, auraSettings.debuffReverseSwipe == true)
            if auraData then
                icon._cachedShowPulse = showPulse
                UpdateAuraIcon(icon, auraData, unit)
            else
                ClearAuraIcon(icon)
            end
        end

        -- Hide excess icons
        for i = maxDebuffs + 1, #frame.debuffIcons do
            ClearAuraIcon(frame.debuffIcons[i])
        end
    elseif frame.debuffIcons then
        for _, icon in ipairs(frame.debuffIcons) do
            ClearAuraIcon(icon)
        end
    end

    -- Process buffs (if enabled)
    if auraSettings.showBuffs and (auraSettings.maxBuffs or 0) > 0 then
        local maxBuffs = auraSettings.maxBuffs
        local iconSize = auraSettings.buffIconSize or 14

        if not frame.buffIcons then
            frame.buffIcons = {}
        end

        -- Cache rebuild owns hidePermanent + onlyMine + classification +
        -- whitelist + blacklist filters. Render only applies the dedup set,
        -- which is per-frame state (defensive/indicator/pinned spell IDs
        -- already shown elsewhere on this frame).
        local dedup = auraSettings.buffDeduplicateDefensives ~= false
        local dedupSet
        if dedup then
            local defIDs = frame._defensiveAuraIDs
            local indIDs = frame._indicatorAuraIDs
            local pinIDs = frame._pinnedAuraIDs
            local hasDef = defIDs and next(defIDs)
            local hasInd = indIDs and next(indIDs)
            local hasPin = pinIDs and next(pinIDs)
            local sourceCount = (hasDef and 1 or 0) + (hasInd and 1 or 0) + (hasPin and 1 or 0)
            if sourceCount > 1 then
                if not frame._buffDedupSet then frame._buffDedupSet = {} end
                wipe(frame._buffDedupSet)
                if hasDef then for id in pairs(defIDs) do frame._buffDedupSet[id] = true end end
                if hasInd then for id in pairs(indIDs) do frame._buffDedupSet[id] = true end end
                if hasPin then for id in pairs(pinIDs) do frame._buffDedupSet[id] = true end end
                dedupSet = frame._buffDedupSet
            elseif hasDef then
                dedupSet = defIDs
            elseif hasInd then
                dedupSet = indIDs
            elseif hasPin then
                dedupSet = pinIDs
            end
        end

        -- Pre-filtered, pre-sorted buff candidates from cache (already passed
        -- onlyMine/hidePermanent/classification/whitelist/blacklist). Walk in
        -- order, applying the per-frame dedup gate, capped at maxBuffs.
        local sortedBuffs = (cache and cache.panelBuffsSorted) or EMPTY_AURA_LIST
        wipe(_renderBuffs)
        local nSrc = #sortedBuffs
        for i = 1, nSrc do
            if #_renderBuffs >= maxBuffs then break end
            local ad = sortedBuffs[i]
            local instID = ad and ad.auraInstanceID
            if not (dedupSet and instID and dedupSet[instID]) then
                _renderBuffs[#_renderBuffs + 1] = ad
            end
        end

        local bAnchor = auraSettings.buffAnchor or "TOPLEFT"
        local bGrow = auraSettings.buffGrowDirection or "RIGHT"
        local bSpacing = auraSettings.buffSpacing or 2
        local bOffX = auraSettings.buffOffsetX or 2
        local bOffY = auraSettings.buffOffsetY or 16
        if sub(bAnchor, 1, 6) == "BOTTOM" then bOffY = bOffY + (frame._bottomPad or 0) end
        local bIconAnchor = GetIconAnchorForGrow(bAnchor, bGrow)
        -- CENTER: only relayout when visible count actually changes
        local bVisibleCount = nil
        if bGrow == "CENTER" then
            local vc = #_renderBuffs
            if vc ~= (framePrevBuffCount[frame] or -1) then
                bVisibleCount = vc
                framePrevBuffCount[frame] = vc
            end
        end
        for i = 1, maxBuffs do
            local auraData = _renderBuffs[i]
            if not frame.buffIcons[i] then
                frame.buffIcons[i] = CreateAuraIcon(frame, iconSize)
                needsLayout = true
            end
            -- Only reposition when layout settings changed
            if needsLayout or bVisibleCount then
                local offX, offY = CalculateSlotOffset(i, iconSize, bSpacing, bGrow, bVisibleCount)
                frame.buffIcons[i]:ClearAllPoints()
                frame.buffIcons[i]:SetPoint(bIconAnchor, frame, bAnchor, bOffX + offX, bOffY + offY)
                frame.buffIcons[i]:SetSize(iconSize, iconSize)
            end
            local bIcon = frame.buffIcons[i]
            bIcon._durationTextSettingKey = "showBuffDurationText"
            bIcon._durationUseTimeColorKey = "buffDurationUseTimeColor"
            bIcon._durationColorKey = "buffDurationColor"
            ApplyDurationTextStyle(bIcon, auraSettings, "buff")
            SafeSetDrawSwipe(bIcon and bIcon.cooldown, auraSettings.buffHideSwipe ~= true)
            SafeSetReverse(bIcon and bIcon.cooldown, auraSettings.buffReverseSwipe == true)
            if auraData then
                bIcon._cachedShowPulse = showPulse
                UpdateAuraIcon(bIcon, auraData, unit)
            else
                ClearAuraIcon(bIcon)
            end
        end

        for i = maxBuffs + 1, #frame.buffIcons do
            ClearAuraIcon(frame.buffIcons[i])
        end
    elseif frame.buffIcons then
        for _, icon in ipairs(frame.buffIcons) do
            ClearAuraIcon(icon)
        end
    end

    -- Stamp layout version so we skip repositioning until settings change
    frameLayoutVersions[frame] = layoutVersion
end

---------------------------------------------------------------------------
-- EVENT HOOKUP: Listen to UNIT_AURA via the group frame event system
---------------------------------------------------------------------------
local function FixIconMouse(icon, skipCombatCheck)
    if not icon then return end
    if not skipCombatCheck and InCombatLockdown() then return end
    pcall(function()
        icon:EnableMouse(true)
        if icon.SetPropagateMouseMotion then icon:SetPropagateMouseMotion(true) end
        if icon.SetPropagateMouseClicks then icon:SetPropagateMouseClicks(true) end
        if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    end)
end

local function FixAllIconMouse()
    if InCombatLockdown() then return end
    local GF = ns.QUI_GroupFrames
    if not GF then return end
    for _, list in pairs(GF.unitFrameMap) do
        for i = 1, #list do
            local frame = list[i]
            if frame.debuffIcons then
                for _, icon in ipairs(frame.debuffIcons) do FixIconMouse(icon, true) end
            end
            if frame.buffIcons then
                for _, icon in ipairs(frame.buffIcons) do FixIconMouse(icon, true) end
            end
        end
    end
    pendingMouseFix = false
end

-- Aura processing is inline in the dispatcher callback so all group-frame
-- consumers render from the same shared cache mutation.

-- PLAYER_REGEN_ENABLED handler (mouse fix deferred from combat)
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function(self, event)
    if pendingMouseFix then FixAllIconMouse() end
end)

-- Subscribe to centralized aura dispatcher for group frame aura updates.
-- Stack/duration-only updates stay on the icon fast path. Add/remove/full
-- changes mutate the shared cache first, then all consumers read that state.
--
-- Pure stack/duration updates (the dominant raid path — 80%+ of events) skip
-- the entire scan + overlay + filter/sort pipeline and just refresh visible
-- icon cooldown swipes via DurationObject (zero Lua allocation).
--
-- Set changes try the shared delta path first; full updates still rescan.
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("roster", function(unit, updateInfo)
        local GF = ns.QUI_GroupFrames
        if not GF or not GF.initialized then return end

        local frames = GF.unitFrameMap[unit]
        if not frames then return end
        local nFrames = #frames
        if nFrames == 0 then return end

        -- Fast path: pure stack/duration update (no auras added or removed).
        -- The display set is identical — skip full scan + all overlay updates.
        -- Only refresh the specific icons whose aura actually updated.
        -- All APIs are C-side, secret-safe — no pcall needed.
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
            auraStats.fastUpdates = auraStats.fastUpdates + 1

            local GetDuration = C_UnitAuras.GetAuraDuration
            local GetDisplayCount = C_UnitAuras.GetAuraApplicationDisplayCount
            if not GetDuration then return end

            -- Refresh only icons whose aura is in the updated set — for every
            -- frame displaying this unit (main raid panel + spotlight).
            for f = 1, nFrames do
                local frame = frames[f]
                if frame:IsShown() then
                    for listIdx = 1, 2 do
                        local icons = listIdx == 1 and frame.debuffIcons or frame.buffIcons
                        if icons then
                            for _, icon in ipairs(icons) do
                                if not icon:IsShown() then break end
                                local state = icon._auraState
                                local instID = state and state.auraInstanceID
                                if instID then
                                    -- Linear scan for match (nUpdated is typically 1-3)
                                    local hit = false
                                    for i = 1, nUpdated do
                                        if updated[i] == instID then hit = true; break end
                                    end
                                    if hit then
                                        local cd = icon.cooldown
                                        if cd and cd.SetCooldownFromDurationObject then
                                            local dObj = GetDuration(unit, instID)
                                            if dObj then cd:SetCooldownFromDurationObject(dObj, true) end
                                        end
                                        if icon.stackText and GetDisplayCount then
                                            local s = GetDisplayCount(unit, instID, 2, 99)
                                            if s then icon.stackText:SetText(s) end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return
        end

        -- Set change or full update: keep the shared cache authoritative.
        -- Full scan on cold/full/fallback; otherwise patch the cache from the
        -- UNIT_AURA delta and let every consumer read that shared state.
        local cacheUpdated = false
        local triedDelta = false
        if type(updateInfo) == "table" and not updateInfo.isFullUpdate then
            triedDelta = true
            cacheUpdated = ApplyAuraDelta(unit, updateInfo)
        elseif type(updateInfo) == "table" and updateInfo.isFullUpdate then
            auraStats.fullUpdateEvents = auraStats.fullUpdateEvents + 1
        end
        if cacheUpdated then
            auraStats.deltaApplied = auraStats.deltaApplied + 1
        else
            if triedDelta then
                auraStats.deltaFallback = auraStats.deltaFallback + 1
            end
            ScanUnitAuras(unit)
        end
        local GFI = ns.QUI_GroupFrameIndicators
        local GFP = ns.QUI_GroupFramePinnedAuras
        for f = 1, nFrames do
            local frame = frames[f]
            if frame:IsShown() then
                if GF.UpdateDispelOverlay then GF:UpdateDispelOverlay(frame) end
                if GF.UpdateDefensiveIndicator then GF:UpdateDefensiveIndicator(frame) end
                if GFI and GFI.RefreshFrame then GFI:RefreshFrame(frame) end
                if GFP and GFP.RefreshFrame then GFP:RefreshFrame(frame) end
                UpdateFrameAuras(frame)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- PUBLIC: Bump layout version (call when aura settings change in options)
---------------------------------------------------------------------------
function QUI_GFA:InvalidateLayout()
    layoutVersion = layoutVersion + 1
    _cachedFontPath = nil  -- force re-fetch on next access
    -- Refresh cached setting for shared timer
    local db = GetDB()
    cachedShowDurationColor = db and db.auras and db.auras.showDurationColor ~= false
    -- Phase 2: panel subsets depend on filter settings that may have changed.
    -- Mark every cached unit dirty so the next render or delta re-runs the
    -- panel rebuild pass against the fresh filter cache.
    for _, cache in pairs(unitAuraCache) do
        cache.panelBuffsDirty = true
        cache.panelDebuffsDirty = true
    end
end

---------------------------------------------------------------------------
-- PUBLIC: Refresh all frames
---------------------------------------------------------------------------
function QUI_GFA:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    -- Force layout recalculation on explicit refresh
    layoutVersion = layoutVersion + 1
    _cachedFontPath = nil  -- force re-fetch on next access
    -- Sync cached setting from DB
    local db = GetDB()
    cachedShowDurationColor = db and db.auras and db.auras.showDurationColor ~= false

    for unit, list in pairs(GF.unitFrameMap) do
        ScanUnitAuras(unit)
        for i = 1, #list do
            local frame = list[i]
            if frame and frame:IsShown() then
                UpdateFrameAuras(frame)
            end
        end
    end
end

function QUI_GFA:RefreshFrame(frame)
    if frame and frame.unit then
        ScanUnitAuras(frame.unit)
    end
    UpdateFrameAuras(frame)
end

function QUI_GFA:RenderFrame(frame)
    UpdateFrameAuras(frame)
end
