--[[
    QUI CDM Spell Data

    Essential/Utility/Buff: observes hidden Blizzard CDM viewers and exports
    spell lists. QUI reads the spell list from hidden Blizzard icons,
    then renders with addon-owned frames.

    All three viewers are hidden (alpha=0, mouse disabled). QUI creates
    addon-owned containers and reparents Blizzard's children into them.
    Blizzard continues managing all data — textures, cooldowns, stacks.

    Initialization is driven externally by cdm_containers.lua calling
    CDMSpellData:Initialize() — no self-bootstrapping event frame.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetTime = GetTime

-- Enable CDM immediately when file loads (before any events fire)
pcall(function() SetCVar("cooldownViewerEnabled", 1) end)

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMSpellData = {}

-- Zone transition flag — set true on PLAYER_ENTERING_WORLD, cleared after
-- 2s. Suppresses SPELLS_CHANGED dormant checks and Phase 3 permanent
-- deletion while WoW APIs (IsSpellKnown, C_CooldownViewer, spellbook) are
-- returning stale/incomplete data.
local _inZoneTransition = false

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local VIEWER_NAMES = {
    essential   = "EssentialCooldownViewer",
    utility     = "UtilityCooldownViewer",
    buff        = "BuffIconCooldownViewer",
    trackedBar  = "BuffBarCooldownViewer",
}



---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local spellLists = {
    essential = {},
    utility   = {},
    buff      = {},
}
local viewersHidden = false
local scanTimer = nil
local initialized = false
local lastSpellFingerprints = { essential = "", utility = "", buff = "" }
local buffChildrenHooked = false  -- one-time hook for buff viewer aura events
local FireChangeCallback

-- Per-child cache of resolved totem slot. layoutIndex reads intermittently
-- secret in combat for secondary slot templates; caching the first plain
-- read keeps _totemSlot stable across Refresh cycles (prevents flicker).
-- Weak keys so entries drop when the Blizzard child goes away.
local _blizzChildToTotemSlot = setmetatable({}, { __mode = "k" })

-- DurationObject cache: Blizzard child → captured DurationObject/start/duration.
local _spellIDToChild = {}  -- [spellID] = { child1, child2, ... } (built OOC during scan)
local _spellMapState = Helpers.CreateStateTable()
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "CDM_spellIDToChild", tbl = _spellIDToChild } end

local function RemoveSpellChildMapping(spellID, child)
    local list = spellID and _spellIDToChild[spellID]
    if not list then return end

    for i = #list, 1, -1 do
        if list[i] == child then
            table.remove(list, i)
        end
    end

    if #list == 0 then
        _spellIDToChild[spellID] = nil
    end
end

local function ClearChildSpellMappings(child)
    if not child then return end

    local state = _spellMapState[child]
    local ids = state and state.ids
    if not ids then return end

    for i = 1, #ids do
        local spellID = ids[i]
        if spellID then
            RemoveSpellChildMapping(spellID, child)
            ids[i] = nil
        end
    end
end

local function MapSpellIDToChild(spellID, child)
    if not spellID or not child then return end

    local state = _spellMapState[child]
    if not state then
        state = {}
        _spellMapState[child] = state
    end

    local ids = state.ids
    if not ids then
        ids = {}
        state.ids = ids
    end

    for i = 1, #ids do
        if ids[i] == spellID then
            return
        end
    end

    local list = _spellIDToChild[spellID]
    if not list then
        list = {}
        _spellIDToChild[spellID] = list
    end
    list[#list + 1] = child
    ids[#ids + 1] = spellID
end

-- Per-batch memo caches for ResolveOwnedEntry candidate scoring.
-- Wiped at the start of each BuildSpellListFromOwned call so all owned
-- entries in one batch share the same spellID→icon and lsid→active lookups.
-- Prevents O(candidates × linkedSpellIDs × entries) API storms when the
-- _spellIDToChild candidate list grows large (e.g. 35+ children share a
-- linkedSpellID via a buff-viewer CDM entry).
local _resolveIconMemo = {}          -- [spellID] = iconID (false = negative lookup)
local _resolveAuraActiveMemo = {}    -- [lsid]    = bool   (true = active aura present)
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_resolveIconMemo", tbl = _resolveIconMemo }
    mp[#mp + 1] = { name = "CDM_resolveAuraMemo", tbl = _resolveAuraActiveMemo }
end

-- Short-lived caches for Blizzard aura queries. Same aura instance is
-- frequently queried by multiple icons across several UpdateAllCooldowns
-- batches. GetAuraDataByAuraInstanceID allocates a fresh Blizzard table every
-- call, so a tiny TTL cuts repeated short-lived garbage without letting stale
-- aura state linger.
-- auraInstanceID is globally unique across units, so the unit is not part of
-- the cache key.
local AURA_QUERY_CACHE_TTL = 0.25
local AURA_QUERY_CACHE_PRUNE_INTERVAL = 1.0
local _tickAuraDataCache = {}        -- [auraInstanceID] = data | false (false = negative)
local _tickAuraDurationCache = {}    -- [auraInstanceID] = durObj | false
local _tickAuraExpirationCache = {}  -- [auraInstanceID] = bool | nil (nil = unknown)
local _tickAuraExpirationResolved = {}
local _tickAuraApplicationCache = {} -- [auraInstanceID] = display string
local _tickAuraApplicationResolved = {}
local _tickAuraDataCacheTime = {}    -- [auraInstanceID] = GetTime() cache stamp
local _tickAuraDurationCacheTime = {}
local _tickAuraExpirationCacheTime = {}
local _tickAuraApplicationCacheTime = {}
local _tickAuraCacheNow = 0
local _nextAuraCachePrune = 0
local STACK_SEARCH_UNITS = { "player", "pet" }
local _tickAuraStats = {
    dataQueries = 0,
    durationQueries = 0,
    expirationQueries = 0,
    durationOnlyHits = 0,
    applicationQueries = 0,
    stackNameQueries = 0,
}
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_tickAuraData",     tbl = _tickAuraDataCache }
    mp[#mp + 1] = { name = "CDM_tickAuraDuration", tbl = _tickAuraDurationCache }
    mp[#mp + 1] = { name = "CDM_tickAuraApplications", fn = function()
        local n = 0
        for _ in pairs(_tickAuraApplicationResolved) do n = n + 1 end
        return n, 0
    end }
    mp[#mp + 1] = { name = "CDM_tickAuraCacheMeta", fn = function()
        local dataAge, durationAge = 0, 0
        for _ in pairs(_tickAuraDataCacheTime) do dataAge = dataAge + 1 end
        for _ in pairs(_tickAuraDurationCacheTime) do durationAge = durationAge + 1 end
        return dataAge, durationAge
    end }
    mp[#mp + 1] = { name = "CDM_auraDataQueries", counter = true, fn = function()
        return _tickAuraStats.dataQueries
    end }
    mp[#mp + 1] = { name = "CDM_auraDurationQueries", counter = true, fn = function()
        return _tickAuraStats.durationQueries
    end }
    mp[#mp + 1] = { name = "CDM_auraExpirationQueries", counter = true, fn = function()
        return _tickAuraStats.expirationQueries
    end }
    mp[#mp + 1] = { name = "CDM_auraDurationOnlyHits", counter = true, fn = function()
        return _tickAuraStats.durationOnlyHits
    end }
    mp[#mp + 1] = { name = "CDM_auraApplicationQueries", counter = true, fn = function()
        return _tickAuraStats.applicationQueries
    end }
    mp[#mp + 1] = { name = "CDM_auraStackNameQueries", counter = true, fn = function()
        return _tickAuraStats.stackNameQueries
    end }
end

local function ClearTickAuraCache()
    wipe(_tickAuraDataCache)
    wipe(_tickAuraDurationCache)
    wipe(_tickAuraExpirationCache)
    wipe(_tickAuraExpirationResolved)
    wipe(_tickAuraApplicationCache)
    wipe(_tickAuraApplicationResolved)
    wipe(_tickAuraDataCacheTime)
    wipe(_tickAuraDurationCacheTime)
    wipe(_tickAuraExpirationCacheTime)
    wipe(_tickAuraApplicationCacheTime)
    _tickAuraCacheNow = 0
    _nextAuraCachePrune = 0
end

local function GetTickAuraCacheNow()
    local now = _tickAuraCacheNow
    if not now or now == 0 then
        now = GetTime()
        _tickAuraCacheNow = now
    end
    return now
end

local function PruneTickAuraCache(now)
    local cutoff = now - AURA_QUERY_CACHE_TTL
    for instanceID, stamp in pairs(_tickAuraDataCacheTime) do
        if not stamp or stamp < cutoff then
            _tickAuraDataCache[instanceID] = nil
            _tickAuraDataCacheTime[instanceID] = nil
        end
    end
    for instanceID, stamp in pairs(_tickAuraDurationCacheTime) do
        if not stamp or stamp < cutoff then
            _tickAuraDurationCache[instanceID] = nil
            _tickAuraDurationCacheTime[instanceID] = nil
        end
    end
    for instanceID, stamp in pairs(_tickAuraExpirationCacheTime) do
        if not stamp or stamp < cutoff then
            _tickAuraExpirationCache[instanceID] = nil
            _tickAuraExpirationResolved[instanceID] = nil
            _tickAuraExpirationCacheTime[instanceID] = nil
        end
    end
    for instanceID, stamp in pairs(_tickAuraApplicationCacheTime) do
        if not stamp or stamp < cutoff then
            _tickAuraApplicationCache[instanceID] = nil
            _tickAuraApplicationResolved[instanceID] = nil
            _tickAuraApplicationCacheTime[instanceID] = nil
        end
    end
end

local function BeginTickAuraCache()
    local now = GetTime()
    _tickAuraCacheNow = now
    if now >= _nextAuraCachePrune then
        _nextAuraCachePrune = now + AURA_QUERY_CACHE_PRUNE_INTERVAL
        PruneTickAuraCache(now)
    end
end

---------------------------------------------------------------------------
-- EVENT-PAYLOAD AURA CAPTURE
-- WoW 12.0.5+ redacts auraInstanceID to nil on AuraData returned by
-- restricted-scope query functions (GetAuraDataBySpellName,
-- GetPlayerAuraBySpellID, GetCooldownAuraBySpellID) during combat. The
-- IDs delivered through UNIT_AURA's addedAuras payload are clean — we
-- capture them at apply time and use them as the source of truth for
-- duration resolution while restricted-scope is active.
--
-- Caches are wiped on encounter/M+/PvP start (auraInstanceID values
-- re-randomize on those transitions per CLAUDE.md).
---------------------------------------------------------------------------
local _capturedAuraBySpellID = {}    -- [spellID]      -> {auraInstanceID, unit, spellID, name}
local _capturedAuraByName    = {}    -- [name:lower()] -> same entry
local _capturedAuraIDToSpellID = {}  -- [auraInstanceID] -> spellID (for removal lookups)
local _capturedAuraIDToName    = {}  -- [auraInstanceID] -> name:lower() (for removal lookups)

local function ClearCapturedAuras()
    wipe(_capturedAuraBySpellID)
    wipe(_capturedAuraByName)
    wipe(_capturedAuraIDToSpellID)
    wipe(_capturedAuraIDToName)
end

local function CaptureAuraFromPayload(unit, ad)
    if not ad then return end
    local instID = ad.auraInstanceID
    -- instID itself must be a clean number for use as a table key. If it's
    -- secret (rare — usually it's the only clean field on AuraData), skip.
    if not instID or Helpers.IsSecretValue(instID) then return end

    -- spellId and name come back as secret values when the addedAuras
    -- payload fires under restricted-scope (mid-combat re-application of
    -- a stacking aura, for example). Filter both so we never use them as
    -- table keys — Lua/WoW raises "indexed assignment on a table that
    -- cannot be indexed with secret keys" if we try.
    local sidRaw = ad.spellId or ad.spellID
    local sid = (sidRaw and not Helpers.IsSecretValue(sidRaw)) and sidRaw or nil
    local nameRaw = ad.name
    local name = (type(nameRaw) == "string"
                  and not Helpers.IsSecretValue(nameRaw)
                  and nameRaw ~= "")
                 and nameRaw or nil

    -- Without a usable spellID or name, the entry can't be looked up by
    -- ResolveAuraState's Phase 3.4 (which keys by spellID/name), so the
    -- capture is dead weight. Skip rather than build an entry no one
    -- can find.
    if not sid and not name then return end

    local entry = {
        auraInstanceID = instID,
        unit = unit,
        spellID = sid,
        name = name,
    }
    if sid then
        _capturedAuraBySpellID[sid] = entry
        _capturedAuraIDToSpellID[instID] = sid
    end
    if name then
        local key = name:lower()
        _capturedAuraByName[key] = entry
        _capturedAuraIDToName[instID] = key
    end
end

local function ReleaseCapturedAuraByInstanceID(instID)
    if not instID then return end
    local sid = _capturedAuraIDToSpellID[instID]
    if sid then
        _capturedAuraBySpellID[sid] = nil
        _capturedAuraIDToSpellID[instID] = nil
    end
    local nameKey = _capturedAuraIDToName[instID]
    if nameKey then
        _capturedAuraByName[nameKey] = nil
        _capturedAuraIDToName[instID] = nil
    end
end

local function ReleaseCapturedAurasForUnit(unit)
    for instID, sid in pairs(_capturedAuraIDToSpellID) do
        local entry = _capturedAuraBySpellID[sid]
        if entry and entry.unit == unit then
            ReleaseCapturedAuraByInstanceID(instID)
        end
    end
    for instID, nameKey in pairs(_capturedAuraIDToName) do
        local entry = _capturedAuraByName[nameKey]
        if entry and entry.unit == unit then
            ReleaseCapturedAuraByInstanceID(instID)
        end
    end
end

-- Full rescan via AuraUtil.ForEachAura. Used on isFullUpdate (which carries
-- no addedAuras list — it's a "rescan everything" signal) and on initial
-- bootstrap so auras already on the player at /reload time are captured
-- without waiting for them to re-apply. ForEachAura returns clean
-- auraInstanceIDs OOC; if called in combat the ad table fields may be
-- secret, but auraInstanceID itself comes through clean from this path
-- (the same path Blizzard's BuffFrame walks).
--
-- usePackedAura=true (5th arg) is required: without it, Blizzard's helper
-- calls AuraUtil.UnpackAuraData on each aura, whose final expression is
-- unpack(auraData.points or {}). When points is a secret value (which the
-- `or {}` doesn't catch — only nil), unpack(secret) errors. Receiving the
-- packed table directly skips that, and CaptureAuraFromPayload is already
-- secret-safe on every field it reads.
local function RescanCapturedAurasForUnit(unit)
    if not (AuraUtil and AuraUtil.ForEachAura) then return end
    ReleaseCapturedAurasForUnit(unit)
    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(ad)
        CaptureAuraFromPayload(unit, ad)
        return false  -- continue iterating
    end, true)
    AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(ad)
        CaptureAuraFromPayload(unit, ad)
        return false
    end, true)
end

local auraCaptureFrame = CreateFrame("Frame")
auraCaptureFrame:RegisterUnitEvent("UNIT_AURA", "player", "pet")
auraCaptureFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
auraCaptureFrame:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Bootstrap capture for auras already applied at login / zone-in.
        -- Without this, only auras applied AFTER load fire addedAuras —
        -- pre-existing ones (e.g. Mana Tea stacks already on the player)
        -- never enter the cache.
        RescanCapturedAurasForUnit("player")
        RescanCapturedAurasForUnit("pet")
        return
    end
    if event ~= "UNIT_AURA" then return end
    if not updateInfo or updateInfo.isFullUpdate then
        -- isFullUpdate carries no aura list; it's a "rescan everything"
        -- signal. Walk the live aura state directly to repopulate the
        -- cache.
        RescanCapturedAurasForUnit(unit)
        return
    end
    if updateInfo.addedAuras then
        for _, ad in ipairs(updateInfo.addedAuras) do
            CaptureAuraFromPayload(unit, ad)
        end
    end
    if updateInfo.updatedAuraInstanceIDs then
        -- Updates don't change the ID; the captured entry remains valid.
        -- Nothing to do here — duration is re-fetched on demand via
        -- GetAuraDuration through the existing tick cache.
        do end
    end
    if updateInfo.removedAuraInstanceIDs then
        for _, rid in ipairs(updateInfo.removedAuraInstanceIDs) do
            ReleaseCapturedAuraByInstanceID(rid)
        end
    end
end)

local function GetCapturedAuraForLookup(spellIDs, entryName)
    if spellIDs then
        for i = 1, #spellIDs do
            local sid = spellIDs[i]
            if sid then
                local entry = _capturedAuraBySpellID[sid]
                if entry and entry.auraInstanceID then
                    return entry
                end
            end
        end
    end
    if type(entryName) == "string" and entryName ~= "" then
        local entry = _capturedAuraByName[entryName:lower()]
        if entry and entry.auraInstanceID then
            return entry
        end
    end
    return nil
end

local function TickCacheGetAuraData(unit, instanceID)
    if not instanceID then return nil end
    local now = GetTickAuraCacheNow()
    local cached = _tickAuraDataCache[instanceID]
    if cached ~= nil then
        local stamp = _tickAuraDataCacheTime[instanceID]
        if stamp and (now - stamp) <= AURA_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickAuraDataCache[instanceID] = nil
        _tickAuraDataCacheTime[instanceID] = nil
    end
    _tickAuraStats.dataQueries = _tickAuraStats.dataQueries + 1
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, instanceID)
    if ok and data then
        _tickAuraDataCache[instanceID] = data
        _tickAuraDataCacheTime[instanceID] = now
        return data
    end
    _tickAuraDataCache[instanceID] = false
    _tickAuraDataCacheTime[instanceID] = now
    return nil
end

local function TickCacheGetAuraDuration(unit, instanceID)
    if not instanceID or not C_UnitAuras.GetAuraDuration then return nil end
    local now = GetTickAuraCacheNow()
    local cached = _tickAuraDurationCache[instanceID]
    if cached ~= nil then
        local stamp = _tickAuraDurationCacheTime[instanceID]
        if stamp and (now - stamp) <= AURA_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickAuraDurationCache[instanceID] = nil
        _tickAuraDurationCacheTime[instanceID] = nil
    end
    _tickAuraStats.durationQueries = _tickAuraStats.durationQueries + 1
    local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, unit, instanceID)
    if ok and durObj then
        _tickAuraDurationCache[instanceID] = durObj
        _tickAuraDurationCacheTime[instanceID] = now
        return durObj
    end
    _tickAuraDurationCache[instanceID] = false
    _tickAuraDurationCacheTime[instanceID] = now
    return nil
end

local function TickCacheDoesAuraHaveExpirationTime(unit, instanceID)
    if not instanceID or not C_UnitAuras.DoesAuraHaveExpirationTime then return nil end
    local now = GetTickAuraCacheNow()
    if _tickAuraExpirationResolved[instanceID] then
        local stamp = _tickAuraExpirationCacheTime[instanceID]
        if stamp and (now - stamp) <= AURA_QUERY_CACHE_TTL then
            return _tickAuraExpirationCache[instanceID]
        end
        _tickAuraExpirationCache[instanceID] = nil
        _tickAuraExpirationResolved[instanceID] = nil
        _tickAuraExpirationCacheTime[instanceID] = nil
    end
    _tickAuraStats.expirationQueries = _tickAuraStats.expirationQueries + 1
    local ok, hasExpiration = pcall(C_UnitAuras.DoesAuraHaveExpirationTime, unit, instanceID)
    local readable = ok and Helpers.SafeValue(hasExpiration, nil) or nil
    if readable ~= true and readable ~= false then
        readable = nil
    end
    _tickAuraExpirationCache[instanceID] = readable
    _tickAuraExpirationResolved[instanceID] = true
    _tickAuraExpirationCacheTime[instanceID] = now
    return readable
end

local function GetReadableAuraDurationState(auraData)
    if not auraData then return nil end
    local duration = auraData.duration
    if duration == nil then
        return false
    end
    if Helpers.IsSecretValue(duration) then
        return nil
    end
    local readableDuration = Helpers.SafeToNumber(duration, nil)
    if not readableDuration or readableDuration <= 0 then
        return false
    end
    return true
end

local function ApplyAuraExpirationState(result, auraUnit, auraInstanceID, auraData)
    local hasExpiration = TickCacheDoesAuraHaveExpirationTime(auraUnit, auraInstanceID)
    if hasExpiration == nil then
        hasExpiration = GetReadableAuraDurationState(auraData)
    end
    if hasExpiration ~= nil then
        result.hasExpirationTime = hasExpiration
        if hasExpiration == false then
            result.hideDurationText = true
        end
    end
    return hasExpiration
end

local IsAuraOwnedByPlayerOrPet = Helpers.IsAuraOwnedByPlayerOrPet

-- Units whose auras are inherently "ours" for CDM display.  For target/focus
-- style units we still require explicit player/pet ownership, but self-unit
-- auras can lose readable source fields in combat.
local function IsSelfUnit(auraUnit)
    return auraUnit == "player" or auraUnit == "pet" or auraUnit == "vehicle"
end

local function IsUsableResolvedAuraData(auraUnit, auraData)
    if not auraData then return false end
    if not IsSelfUnit(auraUnit) then
        return IsAuraOwnedByPlayerOrPet(auraData, true)
    end
    local sourceUnit = Helpers.SafeValue(auraData.sourceUnit, nil)
    local sourceGUID = Helpers.SafeValue(auraData.sourceGUID, nil)
    if sourceUnit or sourceGUID then
        return IsAuraOwnedByPlayerOrPet(auraData, true)
    end
    return true
end

local function GetUsableAuraDataByInstance(auraUnit, auraInstanceID)
    if not auraInstanceID or not C_UnitAuras.GetAuraDataByAuraInstanceID then
        return nil
    end
    local auraData = TickCacheGetAuraData(auraUnit, auraInstanceID)
    if IsUsableResolvedAuraData(auraUnit, auraData) then
        return auraData
    end
    return nil
end

local function ChildLooksLive(child)
    if not child then return false end
    local viewer = child.viewerFrame
    if viewer then
        local itemPool = rawget(viewer, "itemFramePool")
        if itemPool and itemPool.EnumerateActive then
            for activeChild in itemPool:EnumerateActive() do
                if activeChild == child then
                    return true
                end
            end
        end
        local pandemicPool = rawget(viewer, "pandemicIconPool")
        if pandemicPool and pandemicPool.EnumerateActive then
            for activeChild in pandemicPool:EnumerateActive() do
                if activeChild == child then
                    return true
                end
            end
        end
    end
    local ok, shown = pcall(child.IsShown, child)
    return ok and shown or false
end

local function TryDurationOnlyAura(child, auraUnit, auraInstanceID)
    if not child or not auraInstanceID or not C_UnitAuras.GetAuraDuration then
        return nil
    end
    if not IsSelfUnit(auraUnit) then
        return nil
    end
    if not ChildLooksLive(child) then
        return nil
    end
    local auraData = GetUsableAuraDataByInstance(auraUnit, auraInstanceID)
    if not auraData then
        return nil
    end
    local hasExpiration = TickCacheDoesAuraHaveExpirationTime(auraUnit, auraInstanceID)
    if hasExpiration == nil then
        hasExpiration = GetReadableAuraDurationState(auraData)
    end
    if hasExpiration == false then
        return nil, auraData, hasExpiration
    end
    local durObj = TickCacheGetAuraDuration(auraUnit, auraInstanceID)
    if durObj then
        _tickAuraStats.durationOnlyHits = _tickAuraStats.durationOnlyHits + 1
        return durObj, auraData, hasExpiration
    end
    return nil, auraData, hasExpiration
end

local function GetAuraApplications(unit, auraInstanceID)
    if not unit or not auraInstanceID or not C_UnitAuras.GetAuraApplicationDisplayCount then
        return false, nil
    end
    local now = GetTickAuraCacheNow()
    if _tickAuraApplicationResolved[auraInstanceID] then
        local stamp = _tickAuraApplicationCacheTime[auraInstanceID]
        if stamp and (now - stamp) <= AURA_QUERY_CACHE_TTL then
            return true, _tickAuraApplicationCache[auraInstanceID]
        end
        _tickAuraApplicationCache[auraInstanceID] = nil
        _tickAuraApplicationResolved[auraInstanceID] = nil
        _tickAuraApplicationCacheTime[auraInstanceID] = nil
    end
    _tickAuraStats.applicationQueries = _tickAuraStats.applicationQueries + 1
    -- minDisplay=1 so single-stack stacking auras (e.g. Mana Tea on
    -- Mistweaver) display their first stack instead of being clamped to nil.
    local ok, stacks = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, 1, 99)
    if ok and stacks ~= nil and (Helpers.IsSecretValue(stacks) or stacks ~= "") then
        _tickAuraApplicationCache[auraInstanceID] = stacks
        _tickAuraApplicationResolved[auraInstanceID] = true
        _tickAuraApplicationCacheTime[auraInstanceID] = now
        return true, stacks
    end
    return false, nil
end

local function GetOwnedTargetFilter(filter)
    return (not filter or filter == "HARMFUL") and "HARMFUL|PLAYER" or filter
end

local function IsPlayerFilteredAuraFilter(filter)
    return type(filter) == "string" and filter:find("PLAYER", 1, true) ~= nil
end

local function IsUsableTargetAuraData(auraData, filter)
    if not auraData then return false end
    if IsPlayerFilteredAuraFilter(filter) then
        return true
    end
    return IsAuraOwnedByPlayerOrPet(auraData, true)
end

local function ScanOwnedTargetAuraBySpellID(spellID, filter)
    local scanFilter = GetOwnedTargetFilter(filter)
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "target", scanFilter, 40)
        if ok and auras then
            for i = 1, #auras do
                local auraData = auras[i]
                if auraData
                   and Helpers.SafeValue(auraData.spellId, nil) == spellID
                   and IsUsableTargetAuraData(auraData, scanFilter) then
                    return auraData
                end
            end
        end
    end

    if AuraUtil and AuraUtil.ForEachAura then
        local found
        AuraUtil.ForEachAura("target", scanFilter, nil, function(auraData)
            if auraData
               and Helpers.SafeValue(auraData.spellId, nil) == spellID
               and IsUsableTargetAuraData(auraData, scanFilter) then
                found = auraData
                return true
            end
            return false
        end, true)
        if found then return found end
    end

    return nil
end

local function ScanOwnedTargetAuraByName(spellName, filter)
    local scanFilter = GetOwnedTargetFilter(filter)
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "target", scanFilter, 40)
        if ok and auras then
            for i = 1, #auras do
                local auraData = auras[i]
                if auraData
                   and Helpers.SafeValue(auraData.name, nil) == spellName
                   and IsUsableTargetAuraData(auraData, scanFilter) then
                    return auraData
                end
            end
        end
    end

    if AuraUtil and AuraUtil.ForEachAura then
        local found
        AuraUtil.ForEachAura("target", scanFilter, nil, function(auraData)
            if auraData
               and Helpers.SafeValue(auraData.name, nil) == spellName
               and IsUsableTargetAuraData(auraData, scanFilter) then
                found = auraData
                return true
            end
            return false
        end, true)
        if found then return found end
    end

    return nil
end

local function FindOwnedTargetAuraBySpellID(spellID, filter)
    if not spellID then return nil end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        local directFilter = GetOwnedTargetFilter(filter)
        local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellID, "target", spellID, directFilter)
        if ok and ad and ad.auraInstanceID and IsUsableTargetAuraData(ad, directFilter) then
            return ad
        end
    end

    return ScanOwnedTargetAuraBySpellID(spellID, filter)
end

local function FindOwnedTargetAuraByName(spellName, filter)
    if not spellName or spellName == "" then return nil end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local directFilter = GetOwnedTargetFilter(filter)
        local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", spellName, directFilter)
        if ok and ad and ad.auraInstanceID and IsUsableTargetAuraData(ad, directFilter) then
            return ad
        end
    end

    return ScanOwnedTargetAuraByName(spellName, filter)
end

local function FindOwnedAuraBySpellID(spellID)
    if not spellID then return nil end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and ad and ad.auraInstanceID and IsAuraOwnedByPlayerOrPet(ad, true) then
            return ad
        end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        local okPlayer, playerAura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", spellID)
        if okPlayer and playerAura and playerAura.auraInstanceID and IsAuraOwnedByPlayerOrPet(playerAura, true) then
            return playerAura
            end

        local okPet, petAura = pcall(C_UnitAuras.GetAuraDataBySpellID, "pet", spellID)
        if okPet and petAura and petAura.auraInstanceID and IsAuraOwnedByPlayerOrPet(petAura, true) then
            return petAura
        end

        local targetAura = FindOwnedTargetAuraBySpellID(spellID, "HARMFUL")
        if targetAura then
            return targetAura
        end
    end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        local harmfulAura = FindOwnedTargetAuraBySpellID(spellID, "HARMFUL")
        if harmfulAura then
            return harmfulAura
        end
    end

    return nil
end

--- Check if a Blizzard viewer child matches a given spell ID.
--- Tries cooldownInfo.overrideSpellID, cooldownInfo.spellID (may be secret),
--- and cooldownID (numeric, typically not secret).
local function ChildMatchesSpellID(child, spellID)
    local ci = child.cooldownInfo
    if ci then
        local sid = ci.overrideSpellID or ci.spellID
        local safeSid = Helpers.SafeValue(sid, nil)
        if safeSid and safeSid == spellID then return true end
    end
    -- cooldownID is a direct property, not behind cooldownInfo — often readable
    local cdID = child.cooldownID
    if cdID and cdID == spellID then return true end
    return false
end

---------------------------------------------------------------------------
-- CHILD MAP: Per-tick spell→child lookup built from all Blizzard viewers.
-- Moved here from cdm_icons.lua so both icons and bars share one map.
---------------------------------------------------------------------------
local VIEWER_FRAMES = {}  -- populated lazily
local _viewerFramesBuilt = false
local function EnsureViewerFrames()
    if _viewerFramesBuilt then return end
    local found = 0
    wipe(VIEWER_FRAMES)
    for _, name in ipairs({
        "EssentialCooldownViewer", "UtilityCooldownViewer",
        "BuffIconCooldownViewer", "BuffBarCooldownViewer",
    }) do
        local vf = _G[name]
        if vf then
            VIEWER_FRAMES[#VIEWER_FRAMES+1] = vf
            found = found + 1
        end
    end
    for _, name in ipairs({
        "QUI_EssentialContainer", "QUI_UtilityContainer",
        "QUI_BuffContainer",
    }) do
        local vf = _G[name]
        if vf then VIEWER_FRAMES[#VIEWER_FRAMES+1] = vf end
    end
    if found > 0 then _viewerFramesBuilt = true end
end

local _childScratch = {}
local _nChildren = 0
local function _collectChildren(...)
    _nChildren = select("#", ...)
    for i = 1, _nChildren do _childScratch[i] = select(i, ...) end
    for i = _nChildren + 1, #_childScratch do _childScratch[i] = nil end
end
local function _safeGetChildren(viewer) _collectChildren(viewer:GetChildren()) end

local function _appendUniqueViewerChildren(dst, seen, viewer)
    if not viewer then return end

    local function addChild(ch)
        if ch and not seen[ch] then
            seen[ch] = true
            dst[#dst + 1] = ch
        end
    end

    local ok = pcall(_safeGetChildren, viewer)
    if ok and _nChildren > 0 then
        for ci = 1, _nChildren do
            addChild(_childScratch[ci])
        end
    end

    local itemPool = rawget(viewer, "itemFramePool")
    if itemPool and itemPool.EnumerateActive then
        for ch in itemPool:EnumerateActive() do
            addChild(ch)
        end
    end

    local pandemicPool = rawget(viewer, "pandemicIconPool")
    if pandemicPool and pandemicPool.EnumerateActive then
        for ch in pandemicPool:EnumerateActive() do
            addChild(ch)
        end
    end
end

local function _isViewerPoolActive(viewer, child)
    if not viewer or not child then return false end

    local itemPool = rawget(viewer, "itemFramePool")
    if itemPool and itemPool.EnumerateActive then
        for activeCh in itemPool:EnumerateActive() do
            if activeCh == child then
                return true
            end
        end
    end

    local pandemicPool = rawget(viewer, "pandemicIconPool")
    if pandemicPool and pandemicPool.EnumerateActive then
        for activeCh in pandemicPool:EnumerateActive() do
            if activeCh == child then
                return true
            end
        end
    end

    return false
end

local _childBySpellID = {}  -- [spellID] = { child1, child2, ... } (may span viewers)
local _childMapDirty = true -- set true on aura/cooldown events, not per-cycle
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "CDM_childBySpellID", tbl = _childBySpellID } end

local SafeValue = Helpers.SafeValue

--- Full resolve: populates ch._resolvedIDs with all spell IDs for this child.
local function ResolveChildIDs(ch)
    local ids = ch._resolvedIDs or {}
    local n = 0

    local cinfo = ch.cooldownInfo
    if cinfo then
        local sid = cinfo.spellID
        local safeSid = sid and SafeValue(sid, nil)
        if safeSid then n = n + 1; ids[n] = safeSid end
        local ov = cinfo.overrideSpellID
        local safeOv = ov and SafeValue(ov, nil)
        if safeOv then n = n + 1; ids[n] = safeOv end
    end
    local cdID = ch.cooldownID
    if cdID then n = n + 1; ids[n] = cdID end
    if ch.GetAuraSpellID then
        local aok, auraSid = pcall(ch.GetAuraSpellID, ch)
        local safeAura = aok and auraSid and SafeValue(auraSid, nil)
        if safeAura then n = n + 1; ids[n] = safeAura end
    end
    if ch.GetSpellID then
        local sok2, fid = pcall(ch.GetSpellID, ch)
        local safeFid = sok2 and fid and SafeValue(fid, nil)
        if safeFid then n = n + 1; ids[n] = safeFid end
    end
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = ch._cachedCdInfo
        if not info or ch._cachedCdInfoID ~= cdID then
            local iok
            iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
            if iok and info then
                ch._cachedCdInfo = info
                ch._cachedCdInfoID = cdID
            else
                info = nil
            end
        end
        if info and info.linkedSpellIDs then
            for _, lsid in ipairs(info.linkedSpellIDs) do
                local safeLsid = SafeValue(lsid, nil)
                if safeLsid then n = n + 1; ids[n] = safeLsid end
            end
        end
    end
    for i = n + 1, #ids do ids[i] = nil end
    ch._resolvedIDs = ids
    ch._resolvedKey = cdID
    return ids
end

local function RebuildChildMap()
    if not _childMapDirty then return end
    _childMapDirty = false
    wipe(_childBySpellID)
    EnsureViewerFrames()
    for _, viewer in ipairs(VIEWER_FRAMES) do
        local seenChildren = {}
        local allChildren = {}
        _appendUniqueViewerChildren(allChildren, seenChildren, viewer)
        for _, ch in ipairs(allChildren) do
            local hasID = ch and (ch.cooldownID or ch.cooldownInfo or ch.auraInstanceID)
            if hasID then
                local cdID = ch.cooldownID
                local cachedIDs = ch._resolvedIDs
                local ids = cachedIDs and ch._resolvedKey == cdID and cachedIDs or ResolveChildIDs(ch)
                for k = 1, #ids do
                    local sid = ids[k]
                    local list = _childBySpellID[sid]
                    if not list then
                        list = {}
                        _childBySpellID[sid] = list
                    end
                    list[#list + 1] = ch
                end
            end
        end
    end
end

--- Find any Blizzard child for a spell ID (any viewer).
local function FindChildForSpell(id1, id2, id3)
    RebuildChildMap()
    if id1 then
        local list = _childBySpellID[id1]
        if list and list[1] then return list[1] end
    end
    if id2 then
        local list = _childBySpellID[id2]
        if list and list[1] then return list[1] end
    end
    if id3 then
        local list = _childBySpellID[id3]
        if list and list[1] then return list[1] end
    end
    return nil
end

--- Check if a child belongs to a specific viewer (or buff container).
--- Defined at file scope to avoid closure allocation per FindBuffChildForSpell call.
local function _matchesViewer(ch, targetViewer, buffContainer)
    if not ch then return false end
    local vf = ch.viewerFrame
    if vf and vf == targetViewer then return true end
    local parent = ch:GetParent()
    return parent and (parent == targetViewer or parent == buffContainer)
end

--- Scan _childBySpellID for a child matching targetViewer across up to 3 IDs.
local function _scanViewerForIDs(targetViewer, buffContainer, id1, id2, id3)
    if id1 then
        local list = _childBySpellID[id1]
        if list then
            for _, ch in ipairs(list) do
                if _matchesViewer(ch, targetViewer, buffContainer) then return ch end
            end
        end
    end
    if id2 then
        local list = _childBySpellID[id2]
        if list then
            for _, ch in ipairs(list) do
                if _matchesViewer(ch, targetViewer, buffContainer) then return ch end
            end
        end
    end
    if id3 then
        local list = _childBySpellID[id3]
        if list then
            for _, ch in ipairs(list) do
                if _matchesViewer(ch, targetViewer, buffContainer) then return ch end
            end
        end
    end
    return nil
end

--- Find a Blizzard child from the correct buff viewer for a container type.
local function FindBuffChildForSpell(viewerType, id1, id2, id3)
    RebuildChildMap()
    local buffViewer = _G["BuffIconCooldownViewer"]
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    local buffContainer = _G["QUI_BuffContainer"]
    local primaryViewer = buffViewer
    local fallbackViewer = (primaryViewer == buffViewer) and buffBarViewer or buffViewer

    local found = _scanViewerForIDs(primaryViewer, buffContainer, id1, id2, id3)
    if found then return found end
    return _scanViewerForIDs(fallbackViewer, buffContainer, id1, id2, id3)
end

--- Authoritative "is this spell currently in the user's /cdm?" check.
--- Walks live viewer children and filters by ch.cooldownID ~= nil — Blizzard
--- only assigns a cooldownID to a child while it represents an added spell,
--- and clears it on removal (mirrors the canonical filter used by the
--- /cdm-import path, which treats viewer children as the truth source).
--- Bypasses the cached _childBySpellID map, since /cdm edits don't fire any
--- event QUI subscribes to and the cache can be stale indefinitely.
local function _matchesAnyID(info, id1, id2, id3)
    local sid = SafeValue(info.spellID, nil)
    local ov  = SafeValue(info.overrideSpellID, nil)
    local tip = SafeValue(info.overrideTooltipSpellID, nil)
    if sid and (sid == id1 or sid == id2 or sid == id3) then return true end
    if ov  and (ov  == id1 or ov  == id2 or ov  == id3) then return true end
    if tip and (tip == id1 or tip == id2 or tip == id3) then return true end
    if info.linkedSpellIDs then
        for _, lsid in ipairs(info.linkedSpellIDs) do
            local v = SafeValue(lsid, nil)
            if v and (v == id1 or v == id2 or v == id3) then return true end
        end
    end
    return false
end

local function _scanCDMViewerLive(viewer, id1, id2, id3)
    if not viewer or not C_CooldownViewer
       or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return nil
    end
    local ok, kids = pcall(function() return { viewer:GetChildren() } end)
    if not ok or not kids then return nil end
    for _, ch in ipairs(kids) do
        local cdID = ch.cooldownID or (ch.cooldownInfo and ch.cooldownInfo.cooldownID)
        if cdID then
            local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
            if okI and info and _matchesAnyID(info, id1, id2, id3) then
                return ch
            end
        end
    end
    return nil
end

local function FindCooldownChildForSpell(id1, id2, id3)
    return _scanCDMViewerLive(_G["EssentialCooldownViewer"], id1, id2, id3)
        or _scanCDMViewerLive(_G["UtilityCooldownViewer"], id1, id2, id3)
end

local function FindAuraChildForSpell(id1, id2, id3)
    return _scanCDMViewerLive(_G["BuffIconCooldownViewer"], id1, id2, id3)
        or _scanCDMViewerLive(_G["BuffBarCooldownViewer"], id1, id2, id3)
        or _scanCDMViewerLive(_G["QUI_BuffIconContainer"], id1, id2, id3)
        or _scanCDMViewerLive(_G["QUI_BuffContainer"], id1, id2, id3)
end

local childTracksSpell

local function SafeMaybeNumber(value)
    if Helpers.IsSecretValue(value) then
        return nil
    end
    return tonumber(value)
end

local function ResolveChildTotemSlot(child, explicitSlot)
    local slot = SafeMaybeNumber(explicitSlot)
    if slot and slot > 0 then
        return slot
    end
    if not child then return nil end
    local preferredSlot = SafeMaybeNumber(rawget(child, "preferredTotemUpdateSlot"))
    if preferredSlot and preferredSlot > 0 then
        _blizzChildToTotemSlot[child] = preferredSlot
        return preferredSlot
    end

    local cachedSlot = _blizzChildToTotemSlot[child]
    if cachedSlot then
        return cachedSlot
    end

    return nil
end

local function ResolveVirtualAuraState(primaryChild, secondaryChild, explicitSlot)
    local child = primaryChild or secondaryChild
    local slot = ResolveChildTotemSlot(child, explicitSlot)
    local state = { slot = slot }

    local function childMatchesSlot(candidate)
        if not candidate then return false end
        local candidateSlot = ResolveChildTotemSlot(candidate, nil)
        return candidateSlot and slot and candidateSlot == slot
    end

    if slot then
        if childMatchesSlot(primaryChild) then
            child = primaryChild
        elseif childMatchesSlot(secondaryChild) then
            child = secondaryChild
        end
    end
    state.child = child

    if slot and GetTotemInfo then
        local tok, _, totemName, _, _, totemIcon = pcall(GetTotemInfo, slot)
        if tok then
            state.totemName = totemName
            state.totemIcon = totemIcon
        end
    end

    if slot and GetTotemDuration then
        local ok, durObj = pcall(GetTotemDuration, slot)
        if ok and durObj and type(durObj) ~= "number" then
            -- Totem-slot strategy: do not branch on secret booleans from slot APIs.
            -- If the slot resolves and yields a DurationObject, treat that object as
            -- the authoritative active-state source. Display payload comes from the
            -- slot-bound Blizzard child, not from GetTotemInfo in Lua.
            state.isActive = true
            state.auraUnit = "player"
            state.durObj = durObj
            state.isTotemInstance = true
            return state
        end
    end

    return state
end

local function GetChildCooldownID(child)
    if not child then return nil end
    return SafeMaybeNumber(rawget(child, "cooldownID"))
        or SafeMaybeNumber(child.cooldownInfo and rawget(child.cooldownInfo, "cooldownID"))
end

local function _appendViewerChildren(dst, seen, targetViewer, buffContainer, id1, id2, id3)
    local function addList(list)
        if not list then return end
        for _, ch in ipairs(list) do
            if _matchesViewer(ch, targetViewer, buffContainer) and not seen[ch] then
                seen[ch] = true
                dst[#dst + 1] = ch
            end
        end
    end

    if id1 then addList(_childBySpellID[id1]) end
    if id2 then addList(_childBySpellID[id2]) end
    if id3 then addList(_childBySpellID[id3]) end
end

-- Append bar-viewer sibling children whose layoutIndex corresponds to a
-- secondary totem slot. For totem-capable CDM entries Blizzard allocates one
-- child per slot (slot 1 at lidx=1, slot 2 at lidx=2, etc.); only the primary
-- slot's child carries a readable cooldownID, so the secondary slot is
-- invisible to _childBySpellID and must be surfaced positionally. lidx is
-- non-secret even in combat.
local _totemDebugEnabled = false
local function _totemDbg(...) if _totemDebugEnabled then print("|cffFF8800[Totem]|r", ...) end end

local function _appendTotemSiblings(dst, seen, primary, viewer)
    if not viewer or #primary == 0 then
        _totemDbg("skip viewer=", viewer and viewer:GetName(), "primaryN=", #primary)
        return
    end
    local anchor
    for _, ch in ipairs(primary) do
        if ch.viewerFrame == viewer and ch.GetTotemSlot then
            anchor = ch
            break
        end
    end
    if not anchor then
        _totemDbg("no anchor in", viewer:GetName(), "primaryN=", #primary)
        return
    end
    local anchorLidx = SafeMaybeNumber(rawget(anchor, "layoutIndex"))
    _totemDbg("anchor in", viewer:GetName(), "lidx=", tostring(anchorLidx))
    if not anchorLidx then return end
    local numSlots = SafeMaybeNumber((GetNumTotemSlots and GetNumTotemSlots()) or 5) or 5
    local added = 0
    local allChildren = {}
    local viewerSeen = {}
    _appendUniqueViewerChildren(allChildren, viewerSeen, viewer)

    local anchorIDs = anchor._resolvedIDs or ResolveChildIDs(anchor)
    local anchorIDSet = {}
    for _, id in ipairs(anchorIDs or {}) do
        if id then
            anchorIDSet[id] = true
        end
    end

    local byLidx = {}
    for _, ch in ipairs(allChildren) do
        if ch and ch.GetTotemSlot then
            local lidx = SafeMaybeNumber(rawget(ch, "layoutIndex"))
            if lidx and lidx >= 1 and lidx <= numSlots then
                byLidx[lidx] = byLidx[lidx] or ch
            end
        end
    end

    local function childMatchesAnchorSpell(ch)
        if not ch then return nil end
        local ids = ch._resolvedIDs or ResolveChildIDs(ch)
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                if anchorIDSet[id] then
                    return true
                end
            end
            return false
        end
        return nil
    end

    local function walkDirection(step)
        local lidx = anchorLidx + step
        while lidx >= 1 and lidx <= numSlots do
            local ch = byLidx[lidx]
            if not ch or ch == anchor then
                break
            end
            local match = childMatchesAnchorSpell(ch)
            if match == false then
                _totemDbg("  stop at lidx=", lidx, "(different spell)")
                break
            end
            if not seen[ch] then
                seen[ch] = true
                dst[#dst + 1] = ch
                added = added + 1
                _totemDbg("  added sibling lidx=", lidx)
            end
            lidx = lidx + step
        end
    end

    walkDirection(1)
    walkDirection(-1)
    _totemDbg("total siblings added:", added, "from", viewer:GetName())
end

SLASH_QUI_TOTEMDBG1 = "/totemdbg"
SlashCmdList["QUI_TOTEMDBG"] = function()
    _totemDebugEnabled = not _totemDebugEnabled
    print("Totem debug:", _totemDebugEnabled and "ON" or "OFF")
end

local function GetBuffChildrenForSpell(viewerType, id1, id2, id3)
    RebuildChildMap()
    local buffViewer = _G["BuffIconCooldownViewer"]
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    local buffContainer = _G["QUI_BuffContainer"]
    local primaryViewer = (viewerType == "trackedBar") and buffBarViewer or buffViewer
    local fallbackViewer = (primaryViewer == buffViewer) and buffBarViewer or buffViewer
    local primary, fallback, seenPrimary, seenFallback = {}, {}, {}, {}

    if primaryViewer then
        _appendViewerChildren(primary, seenPrimary, primaryViewer, buffContainer, id1, id2, id3)
    end
    if fallbackViewer then
        _appendViewerChildren(fallback, seenFallback, fallbackViewer, buffContainer, id1, id2, id3)
    end

    return primary, fallback
end

local function ChildHasLiveState(ch, id1, id2, id3)
    if not ch then return false end

    local auraUnit, usableAuraData
    if ch.auraInstanceID then
        if not childTracksSpell(ch, id1, id2, id3) then
            return false
        end
        auraUnit = ch.auraDataUnit or "player"
        usableAuraData = GetUsableAuraDataByInstance(auraUnit, ch.auraInstanceID)
        if not usableAuraData then
            return false
        end
    end

    local viewer = ch.viewerFrame
    local pool = viewer and rawget(viewer, "itemFramePool")
    if pool and pool.EnumerateActive then
        for activeCh in pool:EnumerateActive() do
            if activeCh == ch then
                _totemDbg("live: pool-active lidx=", SafeMaybeNumber(rawget(ch, "layoutIndex")) or "?")
                return true
            end
        end
    end
    local ok, shown = pcall(ch.IsShown, ch)
    _totemDbg("live: fallback shown=", tostring(ok and shown), "lidx=", SafeMaybeNumber(rawget(ch, "layoutIndex")) or "?")
    if ok and shown then
        return true
    end

    if ch.auraInstanceID then
        if C_UnitAuras.GetAuraDuration and TickCacheGetAuraDuration(auraUnit, ch.auraInstanceID) then
            return true
        end
        return usableAuraData ~= nil
    end

    return false
end

function CDMSpellData:InvalidateChildMap()
    _childMapDirty = true
end

function CDMSpellData:WipeTickAuraCache()
    BeginTickAuraCache()
end

CDMSpellData.FindChildForSpell = FindChildForSpell
CDMSpellData.FindBuffChildForSpell = FindBuffChildForSpell
CDMSpellData.FindCooldownChildForSpell = FindCooldownChildForSpell
CDMSpellData.FindAuraChildForSpell = FindAuraChildForSpell
CDMSpellData.GetBuffChildrenForSpell = GetBuffChildrenForSpell
CDMSpellData._childBySpellID = _childBySpellID

---------------------------------------------------------------------------
-- CHILD METADATA HELPERS — single source of truth for extracting spell ID
-- and display name from a Blizzard viewer child. Used by cdm_bars (and
-- previously duplicated inline there).
---------------------------------------------------------------------------

-- Returns the C_CooldownViewer info for a child, with per-child caching
-- (matches the pattern ResolveChildIDs uses internally).
local function GetCachedCooldownInfo(child)
    local cdID = child.cooldownID
    if not cdID or not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return nil
    end
    local info = child._cachedCdInfo
    if info and child._cachedCdInfoID == cdID then return info end
    local iok
    iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
    if iok and info then
        child._cachedCdInfo = info
        child._cachedCdInfoID = cdID
        return info
    end
    return nil
end

--- Single best spellID for a Blizzard viewer child.
--- Priority: cooldownInfo.overrideSpellID → cooldownInfo.spellID
--- → cached C_CooldownViewer info → cooldownID.
function CDMSpellData.GetChildPrimarySpellID(child)
    if not child then return nil end
    local cinfo = child.cooldownInfo
    if cinfo then
        local override = SafeValue(cinfo.overrideSpellID, nil); if override then return override end
        local sid = SafeValue(cinfo.spellID, nil); if sid then return sid end
    end
    local info = GetCachedCooldownInfo(child)
    if info then
        local override = SafeValue(info.overrideSpellID, nil); if override then return override end
        local sid = SafeValue(info.spellID, nil); if sid then return sid end
    end
    return child.cooldownID
end

--- Override and base spell IDs as a pair (callers that need them separately —
--- e.g. bars' color-override lookup). Either or both may be nil.
function CDMSpellData.GetChildSpellIDPair(child)
    if not child then return nil, nil end
    local override, base
    local cinfo = child.cooldownInfo
    if cinfo then
        override = SafeValue(cinfo.overrideSpellID, nil)
        base = SafeValue(cinfo.spellID, nil)
    end
    if not override or not base then
        local info = GetCachedCooldownInfo(child)
        if info then
            override = override or SafeValue(info.overrideSpellID, nil)
            base = base or SafeValue(info.spellID, nil)
        end
    end
    return override, base
end

--- Best display name for a Blizzard viewer child.
--- Priority: cooldownInfo.name → cached info.name → caller-provided
--- nameFromRegions fallback (FontString scan is caller-specific).
function CDMSpellData.GetChildSpellName(child, nameFromRegions)
    if not child then return nil end
    local cinfo = child.cooldownInfo
    if cinfo then
        local name = SafeValue(cinfo.name, nil); if name then return name end
    end
    local info = GetCachedCooldownInfo(child)
    if info then
        local name = SafeValue(info.name, nil); if name then return name end
    end
    if nameFromRegions then return nameFromRegions(child) end
    return nil
end

---------------------------------------------------------------------------
-- HOOK CACHE QUERIES
---------------------------------------------------------------------------




---------------------------------------------------------------------------
-- UNIFIED AURA DETECTION
-- Single detection path shared by both icons (cdm_icons.lua) and bars
-- (cdm_bars.lua).  Returns all data both consumers need for display.
-- Result table is module-level, wiped each call (safe because icons and
-- bars process frames sequentially within a single UpdateAll cycle).
---------------------------------------------------------------------------
local _auraResult = {
    isActive = false,
    auraInstanceID = nil,
    auraUnit = "player",
    durObj = nil,
    blizzChild = nil,
    blizzBarChild = nil,
    stacks = nil,
    auraData = nil,
    hasExpirationTime = nil,
    hideDurationText = nil,
    totemSlot = nil,
    totemName = nil,
    totemIcon = nil,
    isTotemInstance = false,
}

local function WipeAuraResult()
    _auraResult.isActive = false
    _auraResult.auraInstanceID = nil
    _auraResult.auraUnit = "player"
    _auraResult.durObj = nil
    _auraResult.blizzChild = nil
    _auraResult.blizzBarChild = nil
    _auraResult.stacks = nil
    _auraResult.stackSource = nil
    _auraResult.auraData = nil
    _auraResult.hasExpirationTime = nil
    _auraResult.hideDurationText = nil
    _auraResult.totemSlot = nil
    _auraResult.totemName = nil
    _auraResult.totemIcon = nil
    _auraResult.isTotemInstance = false
end

local function ShouldDebugAuraState(entryName, spellID, entryID)
    local filter = _G.QUI_CDM_AURA_DEBUG
    if not filter then return false end
    if filter == true then return true end
    local text = tostring(filter):lower()
    if entryName and type(entryName) == "string" and entryName:lower():find(text, 1, true) then
        return true
    end
    if tostring(spellID or "") == text or tostring(entryID or "") == text then
        return true
    end
    return false
end

local function AuraStateDebug(enabled, ...)
    if not enabled then return end
    local parts = { "|cff34D399[CDM-Aura]|r" }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if Helpers.IsSecretValue(v) then
            parts[#parts + 1] = "<secret>"
        else
            parts[#parts + 1] = tostring(v)
        end
    end
    print(table.concat(parts, " "))
end

SLASH_QUI_CDMAURADEBUG1 = "/cdmauradebug"
SlashCmdList["QUI_CDMAURADEBUG"] = function(msg)
    local filter = msg and strtrim(msg) or ""
    if filter == "" then
        _G.QUI_CDM_AURA_DEBUG = not _G.QUI_CDM_AURA_DEBUG
        print("|cff34D399[CDM-Aura]|r", _G.QUI_CDM_AURA_DEBUG and "ON (all auras)" or "OFF")
        return
    end
    _G.QUI_CDM_AURA_DEBUG = filter
    print("|cff34D399[CDM-Aura]|r ON - filter:", filter)
end

--- Validate that a Blizzard child still tracks the given spell IDs.
--- Prevents cross-contamination from recycled children.
childTracksSpell = function(ch, spellID, altID1, altID2)
    if not ch then return false end
    local ids = ch._resolvedIDs
    if not ids then return true end
    for k = 1, #ids do
        local v = ids[k]
        if v == spellID or v == (altID1 or 0) or v == (altID2 or 0) then
            return true
        end
    end
    return false
end

-----------------------------------------------------------------------
-- Totem-slot scoring helpers, hoisted to file scope.
-- Previously these were defined inside ResolveAuraState, allocating 5+
-- closures per call. ResolveAuraState fires per CDM aura icon per
-- UpdateAllCooldowns batch (~20×/sec in combat × ~30+ aura icons), so
-- the per-call closures were a major source of garbage churn outside
-- any probed table. None of these capture per-call state — they only
-- reference module-scope upvalues — so they're safe to hoist.
-----------------------------------------------------------------------
local function scoreSlotChild(child, slot)
    if not child or not slot then return -1 end
    local childSlot = ResolveChildTotemSlot(child, nil)
    if not childSlot or childSlot ~= slot then
        return -1
    end
    local score = 0
    if _isViewerPoolActive(child.viewerFrame, child) then
        score = score + 4
    end
    if child.cooldownInfo then
        score = score + 2
    end
    if child.auraInstanceID then
        score = score + 1
    end
    if child._cachedCdInfo then
        score = score + 1
    end
    local prefSlot = SafeMaybeNumber(rawget(child, "preferredTotemUpdateSlot"))
    if prefSlot and prefSlot == slot then
        score = score + 1
    end
    return score
end

local function childHasReadableTexture(child)
    if not child then return false end
    local iconRegion = child.Icon or child.icon
    local texRegion = iconRegion and (iconRegion.Icon or iconRegion.icon or iconRegion)
    if texRegion and texRegion.GetTexture then
        local ok, tex = pcall(texRegion.GetTexture, texRegion)
        return ok and tex ~= nil
    end
    return false
end

local function scoreDisplayChild(child, slot)
    local score = scoreSlotChild(child, slot)
    if score < 0 then return score end
    if CDMSpellData.GetChildSpellName and CDMSpellData.GetChildSpellName(child) then
        score = score + 3
    end
    if childHasReadableTexture(child) then
        score = score + 3
    end
    if child.cooldownInfo then
        score = score + 1
    end
    return score
end

local function scoreFillChild(child, slot)
    local score = scoreSlotChild(child, slot)
    if score < 0 then return score end
    if child.Bar then
        score = score + 3
    end
    if child.Cooldown then
        score = score + 2
    end
    if child.auraInstanceID then
        score = score + 2
    end
    return score
end

-- findViewerChildForSlot: hoisted alongside the score helpers. Uses a
-- module-scope `seen` scratch table that is wiped on entry rather than
-- allocated fresh per call, and a shared helper instead of a per-call closure.
local _findViewerSeen = {}
local function considerViewerSlotList(list, targetViewer, slot, bestChild, bestScore)
    if not list then return bestChild, bestScore end
    for i = 1, #list do
        local ch = list[i]
        if ch and not _findViewerSeen[ch] and _matchesViewer(ch, targetViewer, nil) then
            _findViewerSeen[ch] = true
            local score = scoreSlotChild(ch, slot)
            if score > bestScore then
                bestScore = score
                bestChild = ch
            end
        end
    end
    return bestChild, bestScore
end

local function findViewerChildForSlot(targetViewer, slot, id1, id2, id3)
    if not targetViewer or not slot then return nil end
    RebuildChildMap()
    wipe(_findViewerSeen)
    local bestChild
    local bestScore = -1

    if id1 then bestChild, bestScore = considerViewerSlotList(_childBySpellID[id1], targetViewer, slot, bestChild, bestScore) end
    if id2 then bestChild, bestScore = considerViewerSlotList(_childBySpellID[id2], targetViewer, slot, bestChild, bestScore) end
    if id3 then bestChild, bestScore = considerViewerSlotList(_childBySpellID[id3], targetViewer, slot, bestChild, bestScore) end

    return bestChild
end

function CDMSpellData:ResolveAuraState(params)
    WipeAuraResult()
    local r = _auraResult

    local spellID = params.spellID
    if not spellID then return r end

    local entrySpellID = params.entrySpellID
    local entryID = params.entryID
    local entryName = params.entryName
    local viewerType = params.viewerType
    local blzChild = params.blizzChild
    local blzBarChild = params.blizzBarChild
    local debugAura = ShouldDebugAuraState(entryName, spellID, entryID)

    AuraStateDebug(debugAura,
        "begin",
        "name=", entryName or "?",
        "spellID=", spellID,
        "entrySpellID=", entrySpellID,
        "entryID=", entryID,
        "viewerType=", viewerType)

    -----------------------------------------------------------------------
    -- Phase 1: Resolve aura spell ID
    -----------------------------------------------------------------------
    local auraSpellID = spellID
    local auraMap = self._abilityToAuraSpellID
    if auraMap and auraMap[auraSpellID] then
        auraSpellID = auraMap[auraSpellID]
    end

    -----------------------------------------------------------------------
    -- Phase 2: Find Blizzard child(ren)
    -- Aura state can live on either the buff-icon viewer's child or the
    -- buff-bar viewer's child, and callers may not know which. Populate
    -- BOTH r.blizzChild (viewer-preferred, safe for write-back into
    -- entry._blizzChild) and r.blizzBarChild (bar-viewer counterpart, used
    -- by phase 3 as an aura-resolution fallback regardless of caller).
    -----------------------------------------------------------------------
    local buffIconViewer = _G["BuffIconCooldownViewer"]
    local buffBarViewer  = _G["BuffBarCooldownViewer"]
    local explicitTotemSlot = params.totemSlot
    local disableLooseVisibilityFallback = params.disableLooseVisibilityFallback

    if blzChild then
        local idsMatch = false
        local ids = blzChild._resolvedIDs
        if ids then
            for k = 1, #ids do
                if ids[k] == auraSpellID or ids[k] == (entrySpellID or 0) or ids[k] == (entryID or 0) then
                    idsMatch = true
                    break
                end
            end
        else
            idsMatch = true
        end
        local vf = blzChild.viewerFrame
        if not idsMatch then
            blzChild = nil
        elseif not explicitTotemSlot and vf ~= buffIconViewer then
            if not blzBarChild and vf == buffBarViewer then
                blzBarChild = blzChild
            end
            -- Keep non-buff-viewer children that carry an auraInstanceID
            -- (Blizzard sets these on cooldown-viewer children that track
            -- stacking auras like Mana Tea on utility). Phase 3 needs this
            -- ID to feed GetAuraDuration — and in combat it's the only
            -- source we have, since GetAuraDataBySpellName returns
            -- SecretWhenUnitAuraRestricted data and Phase 4 fallbacks fail.
            if not blzChild.auraInstanceID then
                blzChild = nil
            end
        end
    end
    -- Primary (viewer-matching) lookup
    if not blzChild then
        blzChild = FindBuffChildForSpell(viewerType, auraSpellID, entrySpellID, entryID)
    end
    -- Broader fallback: any viewer with a live auraInstanceID
    if not blzChild then
        local dynChild = FindChildForSpell(auraSpellID, entrySpellID, entryID)
        if dynChild and dynChild.auraInstanceID then
            blzChild = dynChild
        end
    end
    -- Bar-viewer counterpart for symmetric phase-3 fallback. Icon callers
    -- previously hardcoded p.blizzBarChild = nil and lost bar-viewer
    -- auraInstanceIDs; this scan recovers them from the live child map.
    if not blzBarChild and buffBarViewer then
        blzBarChild = _scanViewerForIDs(buffBarViewer, nil,
            auraSpellID, entrySpellID, entryID)
    end
    if explicitTotemSlot then
        local slotIconChild = findViewerChildForSlot(
            buffIconViewer,
            explicitTotemSlot,
            auraSpellID,
            entrySpellID,
            entryID
        )
        if slotIconChild then
            blzChild = slotIconChild
        end
        local slotBarChild = findViewerChildForSlot(
            buffBarViewer,
            explicitTotemSlot,
            auraSpellID,
            entrySpellID,
            entryID
        )
        if slotBarChild then
            blzBarChild = slotBarChild
        end

        local bestDisplayChild = blzChild
        local bestDisplayScore = scoreDisplayChild(bestDisplayChild, explicitTotemSlot)
        local bestFillChild = blzBarChild
        local bestFillScore = scoreFillChild(bestFillChild, explicitTotemSlot)

        local function considerSlotCandidate(candidate)
            if not candidate then return end
            local displayScore = scoreDisplayChild(candidate, explicitTotemSlot)
            if displayScore > bestDisplayScore then
                bestDisplayScore = displayScore
                bestDisplayChild = candidate
            end
            local fillScore = scoreFillChild(candidate, explicitTotemSlot)
            if fillScore > bestFillScore then
                bestFillScore = fillScore
                bestFillChild = candidate
            end
        end

        considerSlotCandidate(blzChild)
        considerSlotCandidate(blzBarChild)
        considerSlotCandidate(slotIconChild)
        considerSlotCandidate(slotBarChild)

        blzChild = bestDisplayChild
        blzBarChild = bestFillChild
    end
    r.blizzChild    = blzChild
    r.blizzBarChild = blzBarChild

    if explicitTotemSlot then
        local virtualState = ResolveVirtualAuraState(blzChild, blzBarChild, explicitTotemSlot)
        if virtualState.slot then
            r.totemSlot = virtualState.slot
            r.totemName = virtualState.totemName
            r.totemIcon = virtualState.totemIcon
            r.isTotemInstance = true
            local vChild = virtualState.child
            if vChild then
                local vf = vChild.viewerFrame
                if vf == buffBarViewer then
                    r.blizzBarChild = vChild
                elseif vf == buffIconViewer then
                    r.blizzChild = vChild
                end
            end
            if virtualState.isActive then
                r.isActive = true
                r.auraUnit = virtualState.auraUnit or "player"
                r.durObj = virtualState.durObj
                return r
            end
        end
    end

    -- Promote generic aura rows into explicit slot-backed resolution as soon
    -- as a resolved Blizzard child exposes a real totem slot. This prevents
    -- generic auraInstanceID lookups from latching onto sibling summons
    -- (e.g. Wild Imp) and makes the slot the single source of truth.
    if not explicitTotemSlot then
        local inferredTotemSlot = ResolveChildTotemSlot(blzChild, nil)
            or ResolveChildTotemSlot(blzBarChild, nil)
        if inferredTotemSlot then
            local virtualState = ResolveVirtualAuraState(blzChild, blzBarChild, inferredTotemSlot)
            if virtualState.slot then
                r.totemSlot = virtualState.slot
                r.totemName = virtualState.totemName
                r.totemIcon = virtualState.totemIcon
                r.isTotemInstance = true
                local vChild = virtualState.child
                if vChild then
                    local vf = vChild.viewerFrame
                    if vf == buffBarViewer then
                        r.blizzBarChild = vChild
                    elseif vf == buffIconViewer then
                        r.blizzChild = vChild
                    end
                end
                if virtualState.isActive then
                    r.isActive = true
                    r.auraUnit = virtualState.auraUnit or "player"
                    r.durObj = virtualState.durObj
                end
                return r
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 3: Direct aura query via child's auraInstanceID
    -- GetAuraDataByAuraInstanceID returns non-nil when the aura exists
    -- (nil-check, safe in combat). GetAuraDuration provides the C-side
    -- DurationObject for display — forwarded to SetCooldownFromDurationObject
    -- which handles zero/secret values natively on the C side.
    -----------------------------------------------------------------------
    local isActive = false
    local childAuraInstID = nil
    local childAuraSource = nil
    local auraUnit = "player"

    if blzChild then
        childAuraInstID = blzChild.auraInstanceID
        childAuraSource = blzChild
        auraUnit = blzChild.auraDataUnit or "player"
    end
    if not childAuraInstID and blzBarChild then
        childAuraInstID = blzBarChild.auraInstanceID
        childAuraSource = blzBarChild
        auraUnit = blzBarChild.auraDataUnit or "player"
    end

    if childAuraInstID then
        local durObj, durAuraData = TryDurationOnlyAura(childAuraSource, auraUnit, childAuraInstID)
        if durAuraData then
            ApplyAuraExpirationState(r, auraUnit, childAuraInstID, durAuraData)
        end
        if durObj then
            AuraStateDebug(debugAura, "phase3-duration", "unit=", auraUnit, "inst=", childAuraInstID)
            isActive = true
            r.durObj = durObj
            r.auraData = durAuraData or r.auraData
        end
    end

    if not isActive and childAuraInstID and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local vdata = TickCacheGetAuraData(auraUnit, childAuraInstID)
        if IsUsableResolvedAuraData(auraUnit, vdata) then
            AuraStateDebug(debugAura, "phase3-inst", "unit=", auraUnit, "inst=", childAuraInstID)
            isActive = true
            r.auraData = vdata
            if ApplyAuraExpirationState(r, auraUnit, childAuraInstID, vdata) ~= false then
                local durObj = TickCacheGetAuraDuration(auraUnit, childAuraInstID)
                if durObj then
                    r.durObj = durObj
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 3.4: Event-payload captured auraInstanceID
    -- WoW 12.0.5+ redacts auraInstanceID to nil on AuraData returned by
    -- restricted-scope query functions during combat
    -- (GetAuraDataBySpellName, GetPlayerAuraBySpellID,
    -- GetCooldownAuraBySpellID). The IDs delivered through UNIT_AURA's
    -- addedAuras event payload are clean — capture them at apply time
    -- (see auraCaptureFrame) and use them as the source of truth here.
    -- Without this, stacking auras whose CDM viewer child reports
    -- auraInstanceID = nil (e.g. Mana Tea) have no resolvable duration
    -- once UNIT_AURA scope becomes restricted.
    -----------------------------------------------------------------------
    if not isActive then
        local _lookupIDs = { auraSpellID, entrySpellID, entryID }
        local captured = GetCapturedAuraForLookup(_lookupIDs, entryName)
        if captured and captured.auraInstanceID then
            -- Validate the captured ID is still alive: encounter/M+/PvP
            -- transitions re-randomize auraInstanceID, and if our cache
            -- carries a pre-randomization ID we'd latch isActive=true
            -- with an instance that no longer exists. The post-detection
            -- block would fail to resolve a DurationObject and the icon
            -- would show aura state with no swipe. Validate via
            -- GetAuraDataByAuraInstanceID — if that returns nothing,
            -- discard the stale capture so Phase 3.5 / Phase 4 fallbacks
            -- can run. ReleaseCapturedAuraByInstanceID also drops the
            -- stale entry from the cache so we don't keep retrying it.
            local vdata = TickCacheGetAuraData(captured.unit or "player",
                captured.auraInstanceID)
            if vdata then
                AuraStateDebug(debugAura, "phase3.4-event-captured",
                    "spellID=", captured.spellID,
                    "inst=", captured.auraInstanceID,
                    "unit=", captured.unit)
                isActive = true
                childAuraInstID = captured.auraInstanceID
                auraUnit = captured.unit or "player"
                r.auraData = vdata
            else
                ReleaseCapturedAuraByInstanceID(captured.auraInstanceID)
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 3.5: Cooldown viewer aura by spellID
    -- C_UnitAuras.GetCooldownAuraBySpellID is the privileged spellID→aura
    -- lookup used by Blizzard's CooldownViewer pipeline. Unlike
    -- GetPlayerAuraBySpellID (broad player-aura scan) it targets the aura
    -- that the cooldown viewer itself tracks for a given cooldown spell —
    -- so for stacking auras like Mana Tea where the viewer child reports
    -- auraInstanceID = nil, this API can still surface the right
    -- auraInstanceID so post-detection duration resolution can run.
    -----------------------------------------------------------------------
    if not isActive and C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID then
        for tryIdx = 1, 3 do
            if isActive then break end
            local tryID = tryIdx == 1 and auraSpellID
                or tryIdx == 2 and entrySpellID or entryID
            if tryID then
                local ok, ad = pcall(C_UnitAuras.GetCooldownAuraBySpellID, tryID)
                if ok and ad and ad.auraInstanceID then
                    AuraStateDebug(debugAura, "phase3.5-cooldown-aura",
                        "tryID=", tryID, "inst=", ad.auraInstanceID)
                    isActive = true
                    childAuraInstID = ad.auraInstanceID
                    auraUnit = ad.auraDataUnit or "player"
                    r.auraData = ad
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 4: API fallbacks (unified OOC/combat)
    -- GetPlayerAuraBySpellID and GetAuraDataBySpellName work in both
    -- states. In combat, isHelpful may be secret — allow when not false.
    -- Reject harmful passives (always-present talent auras like Perdition).
    -----------------------------------------------------------------------
    -- 1. Player aura by spell ID (helpful only)
    -- GetPlayerAuraBySpellID returns ANY aura on the player with that spellID
    -- regardless of caster, so a class-mate's buff on us would otherwise
    -- mark our tracker active. Reject unless the source is the player/pet.
    if not isActive and C_UnitAuras.GetPlayerAuraBySpellID then
        for tryIdx = 1, 3 do
            if isActive then break end
            local tryID = tryIdx == 1 and auraSpellID
                or tryIdx == 2 and entrySpellID or entryID
            if tryID then
                local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, tryID)
                if ok and ad and ad.auraInstanceID then
                    -- Drop the strict ownership check for player-unit queries:
                    -- the aura is by definition on the player. In combat, ad
                    -- fields like sourceUnit / isFromPlayerOrPlayerPet come
                    -- back as secret values (SafeValue → nil), so
                    -- IsAuraOwnedByPlayerOrPet returns false and Phase 4
                    -- silently fails — exactly when stacking-aura entries
                    -- (Mana Tea) need the auraInstanceID for GetAuraDuration.
                    local helpful = Helpers.SafeValue(ad.isHelpful, nil)
                    if helpful ~= false then
                        AuraStateDebug(debugAura, "phase4-player-id", "tryID=", tryID, "inst=", ad.auraInstanceID)
                        isActive = true
                        childAuraInstID = ad.auraInstanceID
                        auraUnit = "player"
                        r.auraData = ad
                    end
                end
            end
        end
    end
    -- 2. Player buff by name
    if not isActive and entryName and entryName ~= "" and C_UnitAuras.GetAuraDataBySpellName then
        local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", entryName, "HELPFUL")
        -- Same reasoning as Phase 4.1: trust the player-unit query, drop
        -- the strict ownership check whose secret-field gates fail in combat.
        if ok and ad and ad.auraInstanceID then
            AuraStateDebug(debugAura, "phase4-player-name", "inst=", ad.auraInstanceID)
            isActive = true
            childAuraInstID = ad.auraInstanceID
            auraUnit = "player"
            r.auraData = ad
        end
    end
    -- 3. Pet buff by name
    if not isActive and entryName and entryName ~= "" and C_UnitAuras.GetAuraDataBySpellName then
        local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellName, "pet", entryName, "HELPFUL")
        if ok and ad and ad.auraInstanceID and IsAuraOwnedByPlayerOrPet(ad, true) then
            AuraStateDebug(debugAura, "phase4-pet-name", "inst=", ad.auraInstanceID)
            isActive = true
            childAuraInstID = ad.auraInstanceID
            auraUnit = "pet"
            r.auraData = ad
        end
    end
    -- 4. Target debuff by name
    if not isActive and entryName and entryName ~= "" and C_UnitAuras.GetAuraDataBySpellName then
        local ad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
        if ad and ad.auraInstanceID then
            AuraStateDebug(debugAura, "phase4-target-harmful", "inst=", ad.auraInstanceID)
            isActive = true
            childAuraInstID = ad.auraInstanceID
            auraUnit = "target"
            r.auraData = ad
        end
    end
    -- 5. Validate child auraInstanceID via GetAuraDataByAuraInstanceID
    if not isActive and childAuraInstID and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local vdata = TickCacheGetAuraData(auraUnit, childAuraInstID)
        if IsUsableResolvedAuraData(auraUnit, vdata) then
            AuraStateDebug(debugAura, "phase5-validate-inst", "unit=", auraUnit, "inst=", childAuraInstID)
            isActive = true
            r.auraData = vdata
        end
    end
    -- 5b. Primary child visibility fallback
    -- Some Blizzard-tracked summons/buffs expose their active state only by
    -- showing the viewer child, without a readable player aura or readable
    -- auraInstanceID path. Mirror the bar-child fallback for the primary
    -- child so buff icons and tracked bars can both treat a shown child as active.
    if not isActive and blzChild then
        if blzChild.auraInstanceID and childTracksSpell(blzChild, auraSpellID, entrySpellID, entryID) then
            local bok, bshown = pcall(blzChild.IsShown, blzChild)
            if bok and bshown then
                local shownAuraUnit = blzChild.auraDataUnit or "player"
                local durObj, durAuraData = TryDurationOnlyAura(blzChild, shownAuraUnit, blzChild.auraInstanceID)
                if durAuraData then
                    ApplyAuraExpirationState(r, shownAuraUnit, blzChild.auraInstanceID, durAuraData)
                end
                if durObj then
                    AuraStateDebug(debugAura, "phase5b-primary-duration", "unit=", shownAuraUnit, "inst=", blzChild.auraInstanceID)
                    childAuraInstID = blzChild.auraInstanceID
                    childAuraSource = blzChild
                    auraUnit = shownAuraUnit
                    r.durObj = durObj
                    r.auraData = durAuraData or r.auraData
                    isActive = true
                else
                    local shownAuraData = C_UnitAuras.GetAuraDataByAuraInstanceID
                        and TickCacheGetAuraData(shownAuraUnit, blzChild.auraInstanceID)
                        or nil
                    if IsUsableResolvedAuraData(shownAuraUnit, shownAuraData) then
                        AuraStateDebug(debugAura, "phase5b-primary-shown", "unit=", shownAuraUnit, "inst=", blzChild.auraInstanceID)
                        childAuraInstID = blzChild.auraInstanceID
                        childAuraSource = blzChild
                        auraUnit = shownAuraUnit
                        r.auraData = shownAuraData or r.auraData
                        isActive = true
                    end
                end
            end
        end
        if not disableLooseVisibilityFallback and not isActive then
            local bok, bshown = pcall(blzChild.IsShown, blzChild)
            local shownAuraUnit = blzChild.auraDataUnit or "player"
            if bok and bshown and shownAuraUnit ~= "target" then
                isActive = true
            end
        end
    end
    -- 6. Bar-specific: blizzBarChild visibility fallback
    if not isActive and blzBarChild then
        if blzBarChild.auraInstanceID and childTracksSpell(blzBarChild, auraSpellID, entrySpellID, entryID) then
            local bok, bshown = pcall(blzBarChild.IsShown, blzBarChild)
            if bok and bshown then
                local shownAuraUnit = blzBarChild.auraDataUnit or "player"
                local durObj, durAuraData = TryDurationOnlyAura(blzBarChild, shownAuraUnit, blzBarChild.auraInstanceID)
                if durAuraData then
                    ApplyAuraExpirationState(r, shownAuraUnit, blzBarChild.auraInstanceID, durAuraData)
                end
                if durObj then
                    AuraStateDebug(debugAura, "phase6-bar-duration", "unit=", shownAuraUnit, "inst=", blzBarChild.auraInstanceID)
                    childAuraInstID = blzBarChild.auraInstanceID
                    childAuraSource = blzBarChild
                    auraUnit = shownAuraUnit
                    r.durObj = durObj
                    r.auraData = durAuraData or r.auraData
                    isActive = true
                else
                    local shownAuraData = C_UnitAuras.GetAuraDataByAuraInstanceID
                        and TickCacheGetAuraData(shownAuraUnit, blzBarChild.auraInstanceID)
                        or nil
                    if IsUsableResolvedAuraData(shownAuraUnit, shownAuraData) then
                        AuraStateDebug(debugAura, "phase6-bar-shown", "unit=", shownAuraUnit, "inst=", blzBarChild.auraInstanceID)
                        childAuraInstID = blzBarChild.auraInstanceID
                        childAuraSource = blzBarChild
                        auraUnit = shownAuraUnit
                        r.auraData = shownAuraData or r.auraData
                        isActive = true
                    end
                end
            end
        end
        if not disableLooseVisibilityFallback and not isActive then
            local bok, bshown = pcall(blzBarChild.IsShown, blzBarChild)
            local shownAuraUnit = blzBarChild.auraDataUnit or "player"
            if bok and bshown and shownAuraUnit ~= "target" then
                isActive = true
            end
        end
    end
    -- 7. Dynamic child scan (last resort)
    if not isActive then
        local dynChild = FindChildForSpell(auraSpellID, entrySpellID, entryID)
        if dynChild and dynChild.auraInstanceID and C_UnitAuras.GetAuraDataByAuraInstanceID then
            local dynUnit = dynChild.auraDataUnit or "player"
            local vdata2 = TickCacheGetAuraData(dynUnit, dynChild.auraInstanceID)
            if IsUsableResolvedAuraData(dynUnit, vdata2) then
                AuraStateDebug(debugAura, "phase7-dyn-child", "unit=", dynUnit, "inst=", dynChild.auraInstanceID)
                isActive = true
                childAuraInstID = dynChild.auraInstanceID
                auraUnit = dynUnit
                r.auraData = vdata2
                if ApplyAuraExpirationState(r, dynUnit, dynChild.auraInstanceID, vdata2) ~= false then
                    local durObj2 = TickCacheGetAuraDuration(dynUnit, dynChild.auraInstanceID)
                    if durObj2 then
                        r.durObj = durObj2
                    end
                end
            end
        end
    end

    -- 8. Totem / virtual-summon detection for non-slot-backed callers.
    if not isActive and not explicitTotemSlot then
        local virtualState = ResolveVirtualAuraState(blzChild, blzBarChild, nil)
        if virtualState.slot then
            r.totemSlot = virtualState.slot
            r.totemName = virtualState.totemName
            r.totemIcon = virtualState.totemIcon
            r.isTotemInstance = true
            local vChild = virtualState.child
            if vChild then
                local vf = vChild.viewerFrame
                if vf == buffBarViewer then
                    r.blizzBarChild = vChild
                elseif vf == buffIconViewer then
                    r.blizzChild = vChild
                end
            end
            if virtualState.isActive then
                AuraStateDebug(debugAura, "phase8-virtual", "slot=", virtualState.slot)
                isActive = true
                auraUnit = virtualState.auraUnit or "player"
                if virtualState.durObj then
                    r.durObj = virtualState.durObj
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 6: Post-detection resolution
    -----------------------------------------------------------------------
    -- If active but no auraInstanceID, try name-based lookups.
    -- Reject foreign-source hits so we don't pull duration/stack info from
    -- a class-mate's aura on us.
    if isActive and not childAuraInstID and entryName and entryName ~= "" then
        if C_UnitAuras.GetAuraDataBySpellName then
            local tad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
            if tad and tad.auraInstanceID then
                childAuraInstID = tad.auraInstanceID
                auraUnit = "target"
            end
            if not childAuraInstID then
                local pok, pad = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", entryName, "HELPFUL")
                if pok and pad and pad.auraInstanceID and IsAuraOwnedByPlayerOrPet(pad, true) then
                    childAuraInstID = pad.auraInstanceID
                    auraUnit = "player"
                end
            end
        end
        if not childAuraInstID and C_UnitAuras.GetPlayerAuraBySpellID then
            for tryIdx = 1, 3 do
                if childAuraInstID then break end
                local tryID = tryIdx == 1 and auraSpellID or tryIdx == 2 and entrySpellID or entryID
                if tryID then
                    local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, tryID)
                    if ok and ad and ad.auraInstanceID and IsAuraOwnedByPlayerOrPet(ad, true) then
                        childAuraInstID = ad.auraInstanceID
                        auraUnit = "player"
                    end
                end
            end
        end
    end

    -- Get DurationObject from auraInstanceID
    if isActive and childAuraInstID and not r.durObj then
        local durationAuraData = r.auraData
        if not durationAuraData and C_UnitAuras.GetAuraDataByAuraInstanceID then
            local vdata = TickCacheGetAuraData(auraUnit, childAuraInstID)
            if IsUsableResolvedAuraData(auraUnit, vdata) then
                durationAuraData = vdata
                r.auraData = vdata
            end
        end
        if ApplyAuraExpirationState(r, auraUnit, childAuraInstID, durationAuraData) ~= false
            and C_UnitAuras.GetAuraDuration then
            local durObj = TickCacheGetAuraDuration(auraUnit, childAuraInstID)
            if durObj then
                r.durObj = durObj
            end
        end
    end

    -- Get stacks: instance data first, then name fallback.  Name lookups can
    -- hit a sibling aura with 0 applications, so prefer the resolved instance.
    if isActive then
        local apps
        local stackSource
        local appsResolved = false
        if childAuraInstID then
            local gotApps, stackApps = GetAuraApplications(auraUnit, childAuraInstID)
            if gotApps then
                apps = stackApps
                stackSource = "display-count"
                appsResolved = true
            end
        end
        if not appsResolved and childAuraInstID and C_UnitAuras.GetAuraDataByAuraInstanceID then
            local instData = TickCacheGetAuraData(auraUnit, childAuraInstID)
            local instApps = instData and instData.applications
            if IsUsableResolvedAuraData(auraUnit, instData) and instApps ~= nil then
                apps = instApps
                stackSource = "instance-data"
                appsResolved = true
            end
        end
        if not appsResolved and entryName and entryName ~= "" and C_UnitAuras.GetAuraDataBySpellName then
            for i = 1, #STACK_SEARCH_UNITS do
                local stackUnit = STACK_SEARCH_UNITS[i]
                if not appsResolved then
                    _tickAuraStats.stackNameQueries = _tickAuraStats.stackNameQueries + 1
                    local nok, nad = pcall(C_UnitAuras.GetAuraDataBySpellName, stackUnit, entryName, "HELPFUL")
                    local nadApps = nad and nad.applications
                    if nok and nad and nadApps ~= nil and IsUsableResolvedAuraData(stackUnit, nad) then
                        apps = nadApps
                        stackSource = "name-" .. stackUnit
                        appsResolved = true
                    end
                end
            end
            if not appsResolved then
                local tad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
                local tadApps = tad and tad.applications
                if tadApps ~= nil then
                    apps = tadApps
                    stackSource = "name-target"
                    appsResolved = true
                end
            end
        end
        r.stacks = apps
        r.stackSource = stackSource
        AuraStateDebug(debugAura, "stacks", "source=", stackSource or "nil", "value=", apps)
    end

    r.isActive = isActive
    r.auraInstanceID = childAuraInstID
    r.auraUnit = auraUnit
    AuraStateDebug(debugAura, "end", "active=", isActive, "unit=", auraUnit,
        "inst=", childAuraInstID, "hasExp=", r.hasExpirationTime,
        "hideDur=", r.hideDurationText)
    return r
end

---------------------------------------------------------------------------
-- SPELL LIST FINGERPRINTING
---------------------------------------------------------------------------

-- Fingerprint a spell list by ordered spellIDs so reordering is detected.
local function ComputeSpellFingerprint(list)
    if type(list) ~= "table" or #list == 0 then return "" end
    local parts = {}
    for i, entry in ipairs(list) do
        parts[i] = tostring(entry.spellID or 0)
    end
    return table.concat(parts, ",")
end

-- TAINT SAFETY: Track hook state in a weak-keyed table instead of writing
-- _quiBuffHooked directly to Blizzard frames. Direct property writes taint
-- the frame, causing isActive to become a "secret boolean tainted by QUI".
local hookedBuffChildren = Helpers.CreateStateTable()

-- BUG-012 (revised): The previous approach replaced viewer.RefreshTotemData
-- with an addon function to pcall-suppress secret value errors.  But writing
-- an addon value to a Blizzard frame's table taints that key; when Blizzard
-- code later reads it the entire execution context becomes tainted, causing
-- isActive and other fields on child frames to become "secret boolean
-- tainted by QUI".  The fix: do NOT replace the method.  Instead, use
-- hooksecurefunc (which never taints) to silently absorb the error at the
-- OnEvent / OnUpdate level that calls RefreshTotemData.  Since the viewers
-- are alpha 0, any totem-refresh error on a hidden viewer is harmless.
local totemSafeguardApplied = false
local function SafeguardViewerTotemRefresh()
    if totemSafeguardApplied then return end
    totemSafeguardApplied = true
end

---------------------------------------------------------------------------
-- HELPER: Check if a child frame is a cooldown icon
---------------------------------------------------------------------------
local function IsIconFrame(child)
    if not child then return false end
    return (child.Icon or child.icon) and (child.Cooldown or child.cooldown)
end

---------------------------------------------------------------------------
-- HELPER: Check if an icon has a valid spell texture
---------------------------------------------------------------------------
local function HasValidTexture(icon)
    local tex = icon.Icon or icon.icon
    if tex and tex.GetTexture then
        local texID = tex:GetTexture()
        if texID == nil then return false end
        if type(issecretvalue) == "function" and issecretvalue(texID) then
            return true -- secret texture values imply a real texture exists
        end
        return texID ~= 0 and texID ~= ""
    end
    return false
end

---------------------------------------------------------------------------
-- FORCE LOAD CDM: Ensure Blizzard_CooldownManager addon is loaded
-- TAINT SAFETY: Previous approach called CooldownViewerSettings:Show()
-- from addon code (via C_Timer.After). Despite the deferral, C_Timer
-- callbacks still run in addon (insecure) execution context. Blizzard's
-- OnShow handler populates module-level tables (wasOnGCDLookup, etc.)
-- which become permanently tainted. Later, when CooldownViewer refreshes
-- from a protected context (e.g. cutscene exit → SetAttribute → Show),
-- those tables are forbidden → "attempted to index a forbidden table".
-- Fix: Just ensure the addon is loaded via C_AddOns.LoadAddOn and let
-- Blizzard initialize viewers naturally via events. The periodic ScanAll
-- ticker (0.5s) picks up children once they're ready.
---------------------------------------------------------------------------
local function ForceLoadCDM()
    if InCombatLockdown() and not ns._inInitSafeWindow then return end
    -- Ensure the Blizzard addon is loaded (no-op if already loaded)
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownManager")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_CooldownManager")
    end
end

---------------------------------------------------------------------------
-- HIDE / SHOW BLIZZARD VIEWERS
-- Blizzard viewers are ALWAYS alpha 0 (including during Edit Mode).
-- QUI's own containers stay visible with overlays during Edit Mode.
-- SetAlpha hooks prevent Blizzard's CDM code from restoring viewer visibility
-- during combat (cooldown activation triggers SetAlpha(1) internally).
---------------------------------------------------------------------------
local viewerAlphaHooked = {} -- [viewerName] = true

local function HookViewerAlpha(viewer, viewerName)
    if viewerAlphaHooked[viewerName] then return end
    viewerAlphaHooked[viewerName] = true
    hooksecurefunc(viewer, "SetAlpha", function(self, alpha)
        if viewersHidden and alpha > 0 then
            -- TAINT SAFETY: Defer SetAlpha(0) to next frame so addon code
            -- doesn't run inside the same execution context as a protected
            -- call chain (e.g. cutscene exit → SetAttribute → Show).
            -- The alpha enforcer OnUpdate (0.1s) is the backstop.
            C_Timer.After(0, function()
                if viewersHidden and self:GetAlpha() > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end)
end

-- Disable mouse on all children of a viewer so they can't show tooltips.
-- Blizzard creates children dynamically, so the alpha enforcer re-runs this.
local function DisableViewerChildrenMouse(viewer)
    local ok, n = pcall(select, '#', viewer:GetChildren())
    if not ok or not n then return end
    for i = 1, n do
        local child = select(i, viewer:GetChildren())
        if child then
            if child.EnableMouse then child:EnableMouse(false) end
            if child.SetMouseClickEnabled then child:SetMouseClickEnabled(false) end
            if child.SetMouseMotionEnabled then child:SetMouseMotionEnabled(false) end
        end
    end
end

-- Periodic alpha enforcer: catches cases where Blizzard restores alpha
-- via internal paths that don't trigger the SetAlpha hook.
-- Only active while viewers are hidden (toggled by Hide/ShowBlizzardViewers).
local alphaEnforcerFrame = CreateFrame("Frame")
local alphaEnforcerElapsed = 0
local function AlphaEnforcerOnUpdate(self, dt)
    alphaEnforcerElapsed = alphaEnforcerElapsed + dt
    if alphaEnforcerElapsed < 0.1 then return end
    alphaEnforcerElapsed = 0
    for _, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            if viewer:GetAlpha() > 0 then
                viewer:SetAlpha(0)
            end
            -- Blizzard creates children dynamically when cooldowns activate;
            -- disable mouse on any new children so they can't show tooltips.
            DisableViewerChildrenMouse(viewer)
        end
    end
end
-- Start disabled — HideBlizzardViewers enables it
alphaEnforcerFrame:SetScript("OnUpdate", nil)

local function HideBlizzardViewers()
    if viewersHidden then return end
    -- Hide all viewers (alpha 0, no mouse on parent AND children).
    -- QUI creates addon-owned containers; Blizzard children stay here as
    -- data sources only — they must not be hit-testable.
    for vtype, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            viewer:SetAlpha(0)
            viewer:EnableMouse(false)
            if viewer.SetMouseClickEnabled then
                viewer:SetMouseClickEnabled(false)
            end
            if viewer.SetMouseMotionEnabled then
                viewer:SetMouseMotionEnabled(false)
            end
            DisableViewerChildrenMouse(viewer)
            -- Hook SetAlpha to prevent Blizzard from restoring visibility
            -- during combat (CDM system calls SetAlpha(1) when cooldowns activate)
            HookViewerAlpha(viewer, viewerName)
        end
    end
    viewersHidden = true
    alphaEnforcerElapsed = 0
    alphaEnforcerFrame:SetScript("OnUpdate", AlphaEnforcerOnUpdate)
end

local function ShowBlizzardViewers()
    if not viewersHidden then return end
    -- Clear the hidden flag BEFORE setting alpha so the hook doesn't fight us
    viewersHidden = false
    alphaEnforcerFrame:SetScript("OnUpdate", nil)
    for vtype, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer then
            viewer:SetAlpha(1)
            viewer:EnableMouse(true)
            if viewer.SetMouseClickEnabled then
                viewer:SetMouseClickEnabled(true)
            end
            if viewer.SetMouseMotionEnabled then
                viewer:SetMouseMotionEnabled(true)
            end
            -- Re-enable mouse on children so tooltips work again
            local ok, children = pcall(function() return { viewer:GetChildren() } end)
            if ok and children then
                for _, child in ipairs(children) do
                    if child.EnableMouse then child:EnableMouse(true) end
                    if child.SetMouseClickEnabled then child:SetMouseClickEnabled(true) end
                    if child.SetMouseMotionEnabled then child:SetMouseMotionEnabled(true) end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- SCAN: Extract spell data from hidden Blizzard CDM icons
-- All three viewer types: read shown children for spell lists.
---------------------------------------------------------------------------
local function ScanCooldownViewer(viewerType)
    local viewerName = VIEWER_NAMES[viewerType]
    local viewer = _G[viewerName]
    if not viewer then return end

    local container = viewer.viewerFrame or viewer

    local list = {}
    local sel = viewer.Selection

    -- For buff: scan both the Blizzard viewer AND QUI_BuffContainer.
    -- After reparenting, children live in the addon container, not the viewer.
    local containersToScan = { container }
    if viewerType == "buff" then
        local addonContainer = _G["QUI_BuffIconContainer"]
        if addonContainer and addonContainer ~= container then
            containersToScan[#containersToScan + 1] = addonContainer
        end
    end

    for _, scanContainer in ipairs(containersToScan) do
        local numChildren = scanContainer:GetNumChildren()
        for i = 1, numChildren do
            local child = select(i, scanContainer:GetChildren())
            if child and child ~= sel and not child._isCustomCDMIcon and IsIconFrame(child) then
                local hasTex = HasValidTexture(child)
                local hasCDInfo = (child.cooldownInfo ~= nil)

                -- Harvest ALL children regardless of shown state.
                -- QUI mirrors Blizzard child alpha for visibility; pool size
                -- and container dimensions are always based on all icons.
                if hasTex or hasCDInfo then
                    -- Replace this child's prior spell mappings before adding the
                    -- current IDs. Buff aura rescans run frequently and only
                    -- touch the buff viewer, so append-only mapping causes
                    -- fight-long growth and stale spell→child candidates.
                    ClearChildSpellMappings(child)

                    local spellID, overrideSpellID, name, isAura
                    local layoutIndex = child.layoutIndex or 9999

                    if child.cooldownInfo then
                        local info = child.cooldownInfo
                        spellID = Helpers.SafeValue(info.spellID, nil)
                        overrideSpellID = Helpers.SafeValue(info.overrideSpellID, nil)
                        name = Helpers.SafeValue(info.name, nil)
                        local wasSetFromAura = (type(info.wasSetFromAura) == "boolean") and info.wasSetFromAura or false
                        local useAuraDisplayTime = (type(info.cooldownUseAuraDisplayTime) == "boolean") and info.cooldownUseAuraDisplayTime or false
                        isAura = wasSetFromAura or useAuraDisplayTime

                    end

                    if spellID and not name then
                        local spellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                        if spellInfo then name = spellInfo.name end
                    end

                    if spellID then
                        -- Check for multi-charge spells
                        -- maxCharges can be a secret value in combat; only trust
                        -- pcall-safe non-secret numeric values here.
                        local hasCharges = false
                        if C_Spell.GetSpellCharges then
                            local checkChargeID = overrideSpellID or spellID
                            local okCharges, ci = pcall(C_Spell.GetSpellCharges, checkChargeID)
                            if okCharges and ci and not Helpers.IsSecretValue(ci.maxCharges) then
                                local maxC = Helpers.SafeToNumber(ci.maxCharges, 0)
                                if maxC and maxC > 1 then
                                    hasCharges = true
                                end
                            end
                        end

                        -- Debug: log harvested entry charge state
                        if _G.QUI_CDM_CHARGE_DEBUG then
                            print("|cff34D399[CDM-Charge]|r HARVEST", name or "?",
                                "spellID=", spellID, "overrideSpellID=", overrideSpellID,
                                "hasCharges=", hasCharges, "isAura=", isAura,
                                "viewerType=", viewerType,
                                "child.cooldownChargesCount=", child and child.cooldownChargesCount)
                        end

                        list[#list + 1] = {
                            spellID = spellID,
                            overrideSpellID = overrideSpellID or spellID,
                            name = name or "",
                            isAura = isAura or false,
                            kind = (viewerType == "buff" or viewerType == "trackedBar") and "aura" or "cooldown",
                            hasCharges = hasCharges,
                            layoutIndex = layoutIndex,
                            viewerType = viewerType,
                            _blizzChild = child,
                        }
                        -- Map spell IDs → Blizzard children for combat hook lookups.
                        -- Map by info struct IDs, corrected IDs, and aura-specific IDs
                        -- so tracked spells can find their Blizzard child in combat.
                        local mappedIDs = { [spellID] = true }
                        MapSpellIDToChild(spellID, child)
                        if overrideSpellID and overrideSpellID ~= spellID then
                            mappedIDs[overrideSpellID] = true
                            MapSpellIDToChild(overrideSpellID, child)
                        end
                        -- Also map by corrected aura ID (from _cdIDToCorrectSID)
                        -- and GetAuraSpellID — these are the IDs tracked spells use.
                        -- Note: _cdIDToCorrectSID may not exist yet on first scan (forward-declared).
                        local cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
                        if cdID and _cdIDToCorrectSID and _cdIDToCorrectSID[cdID] and not mappedIDs[_cdIDToCorrectSID[cdID]] then
                            local correctSid = _cdIDToCorrectSID[cdID]
                            mappedIDs[correctSid] = true
                            MapSpellIDToChild(correctSid, child)
                        end
                        if child.GetAuraSpellID then
                            local aok, auraSid = pcall(child.GetAuraSpellID, child)
                            if aok and auraSid then
                                local safeAuraSid = Helpers.SafeValue(auraSid, nil)
                                if safeAuraSid and safeAuraSid > 0 and not mappedIDs[safeAuraSid] then
                                    mappedIDs[safeAuraSid] = true
                                    MapSpellIDToChild(safeAuraSid, child)
                                end
                            end
                        end
                        if child.GetSpellID then
                            local sok, frameSid = pcall(child.GetSpellID, child)
                            if sok and frameSid then
                                local safeFrameSid = Helpers.SafeValue(frameSid, nil)
                                if safeFrameSid and safeFrameSid > 0 and not mappedIDs[safeFrameSid] then
                                    mappedIDs[safeFrameSid] = true
                                    MapSpellIDToChild(safeFrameSid, child)
                                end
                            end
                        end
                        -- Also map by linkedSpellIDs from cooldown info (e.g. Reaper's Mark
                        -- ability ID 434765 linked to debuff ID 439843 via cdID 51696).
                        if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                            local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                            if iok and info and info.linkedSpellIDs then
                                for _, lsid in ipairs(info.linkedSpellIDs) do
                                    local safeLsid = Helpers.SafeValue(lsid, nil)
                                    if safeLsid and safeLsid > 0 and not mappedIDs[safeLsid] then
                                        mappedIDs[safeLsid] = true
                                        MapSpellIDToChild(safeLsid, child)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.layoutIndex < b.layoutIndex
    end)

    spellLists[viewerType] = list
end


---------------------------------------------------------------------------
-- HOOK BUFF VIEWER CHILDREN: Aura events trigger rescan + reparent
-- Hook OnActiveStateChanged, OnUnitAuraAddedEvent,
-- OnUnitAuraRemovedEvent on each child frame.
---------------------------------------------------------------------------
local buffEventPending = false
local function OnBuffAuraEvent()
    -- Debounce: batch rapid aura events into a single rescan + reparent.
    -- Keep this short: buff bars already tick on a 100ms loop, so stacking a
    -- second 100ms debounce here makes slot-backed summons feel visually late.
    if buffEventPending then return end
    buffEventPending = true
    C_Timer.After(0.02, function()
        buffEventPending = false
        -- Rescan buff viewer to update spell list (needed for reparent)
        ScanCooldownViewer("buff")
        -- Notify containers to reparent children + buffbar to style/position
        if _G.QUI_OnBuffDataChanged then
            _G.QUI_OnBuffDataChanged()
        end
    end)
end

--- Mark a viewer child as hooked (guard for HookBuffViewerChildren).
--- Cache-populating hooks have been removed — aura detection now uses
--- direct C_UnitAuras.GetAuraDuration queries via the child's auraInstanceID.
local function HookChildCooldown(child)
    if not child then return end
    local hookState = hookedBuffChildren[child]
    if not hookState then
        hookState = {}
        hookedBuffChildren[child] = hookState
    end
    if hookState.cooldown then return end
    hookState.cooldown = true
end

--- Hook Cooldown frames on ALL children of a given viewer type.
local function HookViewerChildCooldowns(viewerType)
    local viewer = _G[VIEWER_NAMES[viewerType]]
    if not viewer then return end
    local container = viewer.viewerFrame or viewer
    local sel = viewer.Selection
    local okc, children = pcall(function() return { container:GetChildren() } end)
    if not okc or not children then return end
    for _, child in ipairs(children) do
        if child and child ~= sel then
            HookChildCooldown(child)
        end
    end
end

local function HookBuffViewerChildren()
    if buffChildrenHooked then return end

    local function hookViewer(viewerKey)
        local viewer = _G[VIEWER_NAMES[viewerKey]]
        if not viewer then return end

        local container = viewer.viewerFrame or viewer
        local numChildren = container:GetNumChildren()

        for i = 1, numChildren do
            local child = select(i, container:GetChildren())
            if child and child ~= viewer.Selection then
                -- Hook aura lifecycle methods
                -- TAINT SAFETY: Track hook state in hookedBuffChildren (weak-keyed)
                -- instead of writing _quiBuffHooked to the Blizzard frame directly.
                local hookState = hookedBuffChildren[child]
                if not hookState then
                    hookState = {}
                    hookedBuffChildren[child] = hookState
                end
                if child.OnActiveStateChanged and not hookState.active then
                    hooksecurefunc(child, "OnActiveStateChanged", OnBuffAuraEvent)
                    hookState.active = true
                end
                if child.OnUnitAuraAddedEvent and not hookState.added then
                    hooksecurefunc(child, "OnUnitAuraAddedEvent", OnBuffAuraEvent)
                    hookState.added = true
                end
                if child.OnUnitAuraRemovedEvent and not hookState.removed then
                    hooksecurefunc(child, "OnUnitAuraRemovedEvent", OnBuffAuraEvent)
                    hookState.removed = true
                end
                -- Also hook Cooldown frame for DurationObject capture
                HookChildCooldown(child)
            end
        end
    end

    hookViewer("buff")
    hookViewer("trackedBar")

    buffChildrenHooked = true
end

local function ScanViewer(viewerType)
    ScanCooldownViewer(viewerType)
    -- Hook aura event callbacks on buff children for live updates
    if viewerType == "buff" and not buffChildrenHooked then
        HookBuffViewerChildren()
    end
    -- Hook Cooldown frames on all viewer children for DurationObject capture
    HookViewerChildCooldowns(viewerType)
end

local function ScanAll()
    if InCombatLockdown() and not ns._inInitSafeWindow then return end

    -- Rebuild the spell→child map fresh each scan to prevent unbounded
    -- growth from duplicate entries.  Hooks on child Cooldown frames
    -- remain intact (attached to the frames, not this table).
    wipe(_spellIDToChild)

    SafeguardViewerTotemRefresh()

    ScanViewer("essential")
    ScanViewer("utility")
    ScanViewer("buff")
    -- Hook trackedBar viewer children for DurationObject capture
    HookViewerChildCooldowns("trackedBar")

    -- Check if spell lists changed (count OR order) via fingerprint comparison
    local changed = false
    for viewerType, list in pairs(spellLists) do
        local fingerprint = ComputeSpellFingerprint(list)
        if fingerprint ~= lastSpellFingerprints[viewerType] then
            lastSpellFingerprints[viewerType] = fingerprint
            changed = true
        end
    end

    -- Notify containers that spell data changed
    if changed then
        if _G.QUI_OnSpellDataChanged then
            _G.QUI_OnSpellDataChanged()
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- BLIZZARD SETTINGS SYNC: Detect when user changes CDM settings
-- and rescan so owned icons match Blizzard's view state.
---------------------------------------------------------------------------
local settingsHooked = false

local function HookBlizzardSettings()
    if settingsHooked then return end
    settingsHooked = true

    -- EventRegistry: fires when user adds/removes spells or changes settings
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
            C_Timer.After(0.1, ScanAll)
        end, CDMSpellData)
    end

    -- Per-viewer RefreshLayout: fires when Blizzard recalculates layout
    for _, viewerName in pairs(VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and viewer.RefreshLayout then
            hooksecurefunc(viewer, "RefreshLayout", function()
                if not Helpers.IsEditModeActive() then
                    C_Timer.After(0, ScanAll)
                end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE CVar: Sync Blizzard CVar with QUI's enable/disable settings
---------------------------------------------------------------------------
local function UpdateCooldownViewerCVar()
    local QUICore = ns.Addon
    local db = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    if not db then return end

    local essentialEnabled = db.essential and db.essential.enabled
    local utilityEnabled = db.utility and db.utility.enabled
    local buffEnabled = db.buff and db.buff.enabled

    if essentialEnabled or utilityEnabled or buffEnabled then
        pcall(function() SetCVar("cooldownViewerEnabled", 1) end)
    else
        pcall(function() SetCVar("cooldownViewerEnabled", 0) end)
    end
end

---------------------------------------------------------------------------
-- OWNED SPELL LIST: Snapshot + Build from DB
-- Phase A CDM Overhaul: own spell lists directly instead of mirroring
---------------------------------------------------------------------------

-- DB access for owned spell data
local function GetNcdmDB()
    local QUICore = ns.Addon
    return QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
end

local function GetContainerDB(containerKey)
    local ncdm = GetNcdmDB()
    if not ncdm then return nil end
    -- Built-in containers live at ncdm[key] (user's saved data).
    -- Custom containers only exist in ncdm.containers[key].
    if ncdm[containerKey] then
        return ncdm[containerKey]
    end
    if ncdm.containers and ncdm.containers[containerKey] then
        return ncdm.containers[containerKey]
    end
    return nil
end

-- Normalize legacy entries: convert raw spellID numbers to entry objects
local function NormalizeOwnedEntry(entry)
    if type(entry) == "number" then
        return { type = "spell", id = entry }
    end
    if type(entry) == "table" and entry.id then
        if not entry.type then
            entry.type = "spell"
        end
        return entry
    end
    return nil
end

-- Normalize the entire ownedSpells array in-place
local function NormalizeOwnedSpells(ownedSpells)
    if type(ownedSpells) ~= "table" then return ownedSpells end
    for i, entry in ipairs(ownedSpells) do
        ownedSpells[i] = NormalizeOwnedEntry(entry)
    end
    return ownedSpells
end

-- Check if a spell is currently known/learned by the player
-- Cache WoW globals before defining the local function
local WoW_IsSpellKnown = IsSpellKnown
local WoW_IsPlayerSpell = IsPlayerSpell
local function IsSpellKnownByPlayer(spellID)
    if not spellID then return false end
    -- IsSpellKnown covers class/spec spells
    if WoW_IsSpellKnown and WoW_IsSpellKnown(spellID) then return true end
    -- IsPlayerSpell covers talent-granted spells
    if WoW_IsPlayerSpell and WoW_IsPlayerSpell(spellID) then return true end
    -- Some talent/hero talent spells aren't recognized by the base APIs
    -- but have an override mapping. Check the override spell — if IT is
    -- known, the base spell is effectively available.
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and overrideID and overrideID ~= spellID then
            if WoW_IsSpellKnown and WoW_IsSpellKnown(overrideID) then return true end
            if WoW_IsPlayerSpell and WoW_IsPlayerSpell(overrideID) then return true end
        end
    end
    -- Final fallback: if C_Spell.GetSpellInfo returns valid data AND the
    -- spell exists in Blizzard's CDM viewer, treat it as known. This
    -- handles edge cases where talent spells are castable but neither
    -- IsSpellKnown nor IsPlayerSpell recognizes the stored ID.
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info and info.name then
            -- Spell has valid info — check if it's in the CDM viewer
            -- (Blizzard only lists spells that belong to the current spec)
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
                for cat = 0, 3 do
                    local okCat, cdIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat)
                    if okCat and cdIDs then
                        for _, cdID in ipairs(cdIDs) do
                            if C_CooldownViewer.GetCooldownViewerCooldownInfo then
                                local okI, cdInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                                if okI and cdInfo then
                                    local sid = Helpers.SafeValue(cdInfo.spellID, nil)
                                    local ov = Helpers.SafeValue(cdInfo.overrideSpellID, nil)
                                    -- Aura containers (TrackedBuff / TrackedBar)
                                    -- snapshot using overrideTooltipSpellID — the
                                    -- ID of the actual tracked aura, distinct from
                                    -- the casting spell's spellID. Match against
                                    -- it too so aura-only entries don't get falsely
                                    -- flagged as unknown.
                                    local tip = Helpers.SafeValue(cdInfo.overrideTooltipSpellID, nil)
                                    if sid == spellID or ov == spellID or tip == spellID then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- Map container key → array of CooldownViewerCategory enum values to scan.
-- Cooldown bars scan both Essential (0) + Utility (1).
-- Buff bars scan both TrackedBuff (2) + TrackedBar (3).
-- Used by Composer (available spells) and runtime lookups where a wider
-- scan is desirable so users can cross-add spells between containers.
local CDM_BAR_CATEGORIES = {
    essential  = { 0, 1 },
    utility    = { 0, 1 },
    buff       = { 2, 3 },
    trackedBar = { 2, 3 },
}

-- 1:1 mapping used ONLY during first-time snapshot so spells land in the
-- container that matches their Blizzard CDM category.
-- Essential (0) → essential, Utility (1) → utility,
-- TrackedBuff (2) → buff, TrackedBar (3) → trackedBar.
local CDM_SNAPSHOT_CATEGORIES = {
    essential  = { 0 },
    utility    = { 1 },
    buff       = { 2 },
    trackedBar = { 3 },
}

-- SpellID correction maps (populated by reconciliation, used by ResolveOwnedEntry).
-- Must be declared here before ResolveOwnedEntry which references them.
local _cdIDToCorrectSID = {}
local _spellToCooldownID = {}
-- Family-scoped membership: was this spellID seen in cats {0,1} (cooldown
-- family) or cats {2,3} (aura/auraBar family)? Buff-cat entries pull in
-- their *source ability* spellID via linkedSpellIDs (e.g. Death Strike,
-- whose CD/base ability isn't in /cdm cooldown cats but appears in /cdm
-- buff cats as the source of Blood Shield), so the combined map alone
-- can't answer "is this spell registered in the user's /cdm for this
-- container family." IsSpellInCDMCategory(id, family) consults the
-- right set.
local _spellInCDMCooldowns = {}
local _spellInCDMAuras = {}
-- Maps ability spell ID → aura spell ID for buff categories (2, 3).
-- Built during RebuildSpellToCooldownID by probing GetPlayerAuraBySpellID
-- on each ID variant to find the one that returns aura data.
local _abilityToAuraSpellID = {}

---------------------------------------------------------------------------
-- ENTRY KIND CLASSIFIER
--
-- Each entry is either "aura" (player buff/debuff to track) or "cooldown"
-- (ability/item with a recharge timer). Kind is an entry-level property,
-- independent of container shape (icon vs bar) — a custom icon container
-- can hold a mix of cooldowns and auras. Resolution order:
--   1. entry.kind if explicitly stamped (Composer add-time, migration)
--   2. Non-spell types (item/trinket/slot/macro) → cooldown
--   3. Built-in aura-only viewers (buff/trackedBar) → aura
--   4. Default cooldown
--
-- The Composer's tab-of-origin is authoritative: Passives/Buffs stamp
-- kind="aura"; All Cooldowns/Items stamp kind="cooldown". Falling through
-- here means the user added from the mixed CDM tab or by spell ID — don't
-- auto-flip to aura just because Blizzard's CDM data also lists the spell
-- in a buff category (e.g. Blood Boil → Blood Plague, Death Strike →
-- Blood Shield). Cooldown is the safer default.
--
-- Hot path: called from UpdateAllCooldowns per icon per tick.
---------------------------------------------------------------------------
local function ResolveEntryKind(entry, viewerType)
    if not entry then return "cooldown" end

    if entry.kind == "aura" or entry.kind == "cooldown" then
        return entry.kind
    end

    if entry.type and entry.type ~= "spell" then
        return "cooldown"
    end

    if viewerType == "buff" or viewerType == "trackedBar" then
        return "aura"
    end

    return "cooldown"
end

local function IsAuraEntry(entry, viewerType)
    return ResolveEntryKind(entry, viewerType) == "aura"
end

-- Forward declarations for functions defined in reconciliation section
local RebuildCdIDToCorrectSID
local RebuildSpellToCooldownID
local ResolveInfoSpellID
local ResolveChildSpellID

-- Memoized C_Spell.GetSpellInfo icon lookup.  The raw API can fire 30+ times
-- per ResolveOwnedEntry in the viewer-child tiebreaker when candidate lists
-- are large; memoizing per batch collapses this to one call per unique ID.
-- `false` is stored for negative results so we don't retry missing spells.
local function GetMemoIcon(spellID)
    if not spellID then return nil end
    local cached = _resolveIconMemo[spellID]
    if cached ~= nil then
        return cached or nil
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        local iconID = info and info.iconID or nil
        _resolveIconMemo[spellID] = iconID or false
        return iconID
    end
    _resolveIconMemo[spellID] = false
    return nil
end

-- Memoized active-aura presence check.  Same rationale as GetMemoIcon:
-- C_UnitAuras.GetPlayerAuraBySpellID runs per linkedSpellID per tying
-- candidate, so memoizing per batch is a large win.
local function IsMemoAuraActive(lsid)
    if not lsid then return false end
    local cached = _resolveAuraActiveMemo[lsid]
    if cached ~= nil then return cached end
    local active = FindOwnedAuraBySpellID(lsid) ~= nil
    _resolveAuraActiveMemo[lsid] = active
    return active
end

-- Resolve a single owned entry to a spell data table compatible with
-- the existing icon/bar building pipeline.
local function ResolveOwnedEntry(entry, containerKey, index)
    if not entry or not entry.id then return nil end

    local resolved = {
        spellID = nil,
        overrideSpellID = nil,
        name = "",
        isAura = false,
        hasCharges = false,
        layoutIndex = index or 9999,
        viewerType = containerKey,
        _isOwnedEntry = true,
        _ownedEntry = entry,
        -- Forward entry type info for custom-like cooldown resolution
        type = entry.type,
        id = entry.id,
    }

    if entry.type == "spell" then
        resolved.spellID = entry.id

        -- Apply the aura ID correction map for any entry classified as an
        -- aura — the CDM info struct often returns the ability ID
        -- (e.g. Death Strike) instead of the tracked aura ID (e.g.
        -- Coagulating Blood). Classification is per-entry now: an aura
        -- entry on a cooldown-shaped container still gets aura ID resolution.
        local isAuraEntry = ResolveEntryKind(entry, containerKey) == "aura"
        local displayID = entry.id

        if isAuraEntry then
            -- Try correction: entry.id → cooldownID → corrected aura spellID.
            -- Only apply if entry.id is the base/override ability ID of the CDM
            -- entry — not if it's already a linked buff ID.  Multiple independent
            -- buffs (e.g. Blood Shield + Coagulopathy from Death Strike) share
            -- one cooldownID; blindly remapping would collapse them into one.
            local cdID = _spellToCooldownID[entry.id]
            if cdID and _cdIDToCorrectSID[cdID] then
                local corrected = _cdIDToCorrectSID[cdID]
                -- Only remap if the corrected ID differs AND entry.id is the
                -- base ability (not already a different valid buff spell).
                local isBaseAbility = false
                if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local okI, cdInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    if okI and cdInfo then
                        local baseSid = Helpers.SafeValue(cdInfo.spellID, nil)
                        local baseOv = Helpers.SafeValue(cdInfo.overrideSpellID, nil)
                        isBaseAbility = (entry.id == baseSid or entry.id == baseOv)
                    end
                end
                if isBaseAbility then
                    displayID = corrected
                    resolved.spellID = displayID
                end
            end
            -- Try ability→aura mapping (built from buff categories 2/3).
            -- Only maps ability IDs → aura IDs (not aura → aura).
            if displayID == entry.id and _abilityToAuraSpellID[entry.id] then
                displayID = _abilityToAuraSpellID[entry.id]
                resolved.spellID = displayID
            end
            resolved.isAura = true
            resolved.kind = "aura"
        else
            resolved.kind = "cooldown"
        end

        -- Check for override spell (e.g., talent replacements).
        -- Skip for aura entries: displayID is already the resolved buff
        -- spell ID (via _cdIDToCorrectSID / _abilityToAuraSpellID).
        -- GetOverrideSpell is for ability overrides, not buffs — calling it
        -- on an aura spell ID returns unrelated spells (e.g. Beacon of Light
        -- resolving to Blessing of Freedom).
        if not isAuraEntry and C_Spell and C_Spell.GetOverrideSpell then
            local ok, overrideID = pcall(C_Spell.GetOverrideSpell, displayID)
            if ok and overrideID and overrideID ~= displayID then
                resolved.overrideSpellID = overrideID
            else
                resolved.overrideSpellID = displayID
            end
        else
            resolved.overrideSpellID = displayID
        end
        -- Get spell name: try the resolved display/aura ID first, then fall back to
        -- the original entry ID. This handles cases where the CDM maps an ability to
        -- an aura/debuff spell ID whose GetSpellInfo returns no name (e.g. target
        -- debuffs that use internal rank IDs not exposed via C_Spell, or CD-only
        -- entries like Call Dreadstalkers where the aura ID lookup yields nothing).
        --
        -- Route through ns._GetCachedSpellName (cdm_icons.lua) so the in-combat
        -- relayout path (e.g. hideNonUsable filter flipping mid-fight) reads
        -- a cleanly-cached non-secret name instead of calling GetSpellInfo
        -- directly — info.name can be a secret value during combat, and a
        -- secret name silently breaks GetAuraDataBySpellName downstream.
        -- GetCachedSpellName only returns clean strings (it filters out
        -- secret values + nil internally), so a truthy check is enough —
        -- no `~= ""` comparison needed.
        local cachedName = ns._GetCachedSpellName
        if cachedName then
            local lookupID = resolved.overrideSpellID or displayID
            local n = cachedName(lookupID)
            if n then
                resolved.name = n
            elseif lookupID ~= entry.id then
                local n2 = cachedName(entry.id)
                if n2 then
                    resolved.name = n2
                end
            end
        end
        -- Check for multi-charge spells (runtime + SavedVariables fallback)
        if C_Spell and C_Spell.GetSpellCharges then
            local checkID = resolved.overrideSpellID or displayID
            local ok, ci = pcall(C_Spell.GetSpellCharges, checkID)
            local apiReadable = false
            if ok then
                if ci then
                    local maxC = Helpers.SafeToNumber(ci.maxCharges, 0)
                    if maxC then
                        apiReadable = true
                        if maxC > 1 then
                            resolved.hasCharges = true
                        end
                    end
                    -- ci exists but maxCharges is secret — apiReadable stays false
                else
                    -- API returned nil = spell has no charge mechanic.
                    -- This is a definitive answer, not a failure.
                    apiReadable = true
                end
            end
            -- Combat fallback: only when API call failed (pcall error) or
            -- returned secret maxCharges.  A nil result (no charges) and a
            -- readable maxCharges <= 1 are both authoritative — skip cache.
            if not apiReadable and not resolved.hasCharges and checkID then
                local gdb = QUI and QUI.db and QUI.db.global
                local svCharges = gdb and gdb.cdmChargeSpells
                if svCharges and svCharges[checkID] then
                    resolved.hasCharges = true
                end
            end
            -- Debug: log charge resolution at build time
            if _G.QUI_CDM_CHARGE_DEBUG then
                local _dbgMaxC = ci and Helpers.SafeToNumber(ci.maxCharges, "secret") or "nil"
                local _dbgCurC = ci and Helpers.SafeToNumber(ci.currentCharges, "secret") or "nil"
                print("|cff34D399[CDM-Charge]|r RESOLVE", resolved.name or "?",
                    "checkID=", checkID, "entryID=", entry.id,
                    "overrideSpellID=", resolved.overrideSpellID,
                    "maxCharges=", _dbgMaxC, "currentCharges=", _dbgCurC,
                    "hasCharges=", resolved.hasCharges,
                    "apiReadable=", apiReadable, "containerKey=", containerKey)
            end
        end

    elseif entry.type == "item" then
        -- Item IDs must NOT be stored as spellID — they are different ID spaces.
        -- spellID/overrideSpellID stay nil; item-specific code paths use entry.id.
        resolved.id = entry.id
        local ok, itemName = pcall(C_Item.GetItemNameByID, entry.id)
        if ok and itemName then
            resolved.name = itemName
        end

    elseif entry.type == "slot" then
        resolved.id = entry.id
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            -- Store resolved item ID for texture/tooltip but NOT as spellID
            resolved.itemID = itemID
            local ok, itemName = pcall(C_Item.GetItemNameByID, itemID)
            if ok and itemName then
                resolved.name = itemName
            end
        end

    elseif entry.type == "macro" then
        resolved.macroName = entry.macroName
        resolved.name = entry.macroName or ""
        -- Resolve current spell for texture (updates dynamically via update ticker)
        local macroIndex = entry.macroName and GetMacroIndexByName(entry.macroName)
        if macroIndex and macroIndex > 0 then
            local macroSpellID = GetMacroSpell(macroIndex)
            if macroSpellID then
                resolved.spellID = macroSpellID
                resolved.overrideSpellID = macroSpellID
            else
                local itemName, itemLink = GetMacroItem(macroIndex)
                if itemLink then
                    local itemID = C_Item.GetItemInfoInstant(itemLink)
                    if itemID then
                        resolved.spellID = itemID
                        resolved.overrideSpellID = itemID
                    end
                end
            end
        end
    end

    -- Attach Blizzard viewer child reference for aura lookups.
    -- Priority: buff viewer child with auraInstanceID > any buff viewer child
    -- > any child with auraInstanceID > any child with Cooldown.
    -- Search all ID variants since the child may be indexed under a different ID.
    local buffViewer = _G["BuffIconCooldownViewer"]
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    local searchIDs = {}
    if resolved.overrideSpellID then searchIDs[#searchIDs+1] = resolved.overrideSpellID end
    if resolved.spellID and resolved.spellID ~= resolved.overrideSpellID then searchIDs[#searchIDs+1] = resolved.spellID end
    if resolved.id and resolved.id ~= resolved.spellID and resolved.id ~= resolved.overrideSpellID then searchIDs[#searchIDs+1] = resolved.id end

    local bestChild, bestScore = nil, 0
    local bestChildHasCdInfo = false -- preserve original "bestChild.cooldownInfo" guard
    local bestChildLinkedIcon = nil  -- icon of bestChild.cooldownInfo.linkedSpellIDs[1]
    for _, searchSid in ipairs(searchIDs) do
        local candidates = _spellIDToChild[searchSid]
        if candidates then
            for _, ch in ipairs(candidates) do
                local score = 0
                local vf = ch.viewerFrame
                local isBuff = vf and (vf == buffViewer or vf == buffBarViewer)
                local hasAura = (ch.auraInstanceID ~= nil)
                if isBuff and hasAura then score = 4
                elseif isBuff then score = 3
                elseif hasAura then score = 2
                elseif ch.Cooldown then score = 1 end
                -- Tiebreaker for duplicate spellID children (e.g. Inertia):
                -- Blizzard creates multiple CDM entries for the same spell
                -- with different linked buff IDs — only one actually
                -- activates during combat.
                -- 1) Prefer child with an active aura (combat case).
                -- 2) OOC: prefer child whose linkedSpellIDs[1] matches the
                --    _abilityToAuraSpellID map (the "canonical" aura).
                -- 3) Final fallback: lower cooldownID for determinism.
                if score == bestScore and score >= 3 and ch.cooldownInfo then
                    local linked = ch.cooldownInfo.linkedSpellIDs
                    if linked then
                        -- Active aura check (memoized per batch — see
                        -- IsMemoAuraActive).  Works in and out of combat.
                        for li = 1, #linked do
                            local lsid = Helpers.SafeValue(linked[li], nil)
                            if lsid and lsid > 0 and IsMemoAuraActive(lsid) then
                                score = score + 1
                                break
                            end
                        end
                        -- OOC tiebreaker: prefer the child whose linked
                        -- aura has a distinct icon from the base spell.
                        -- The active buff typically has its own icon; passive
                        -- or hidden variants share the ability icon.
                        if score == bestScore and bestChild and bestChildHasCdInfo then
                            local baseSid = Helpers.SafeValue(ch.cooldownInfo.spellID, nil)
                            local baseIcon = baseSid and GetMemoIcon(baseSid) or nil
                            if baseIcon then
                                local chIcon
                                if linked[1] then
                                    local lsid = Helpers.SafeValue(linked[1], nil)
                                    if lsid then chIcon = GetMemoIcon(lsid) end
                                end
                                -- Prefer child with distinct aura icon.
                                -- bestChildLinkedIcon is cached at
                                -- bestChild-assignment time, avoiding a
                                -- repeat lookup every iteration.
                                if chIcon and chIcon ~= baseIcon
                                    and (not bestChildLinkedIcon or bestChildLinkedIcon == baseIcon) then
                                    score = score + 1
                                end
                            end
                        end
                    end
                end
                if score > bestScore then
                    bestChild = ch
                    bestScore = score
                    -- Cache bestChild's linked[1] icon so subsequent
                    -- tiebreakers don't re-resolve it every iteration.
                    bestChildLinkedIcon = nil
                    local bci = ch.cooldownInfo
                    bestChildHasCdInfo = (bci ~= nil)
                    local bl = bci and bci.linkedSpellIDs
                    if bl and bl[1] then
                        local lsid = Helpers.SafeValue(bl[1], nil)
                        if lsid then bestChildLinkedIcon = GetMemoIcon(lsid) end
                    end
                end
            end
        end
    end
    if bestChild and bestChild.viewerFrame
        and (bestChild.viewerFrame == buffViewer or bestChild.viewerFrame == buffBarViewer) then
        resolved._blizzChild = bestChild
    else
        resolved._blizzChild = nil
    end
    resolved._blizzBarChild = _scanViewerForIDs(buffBarViewer, nil,
        resolved.overrideSpellID, resolved.spellID, resolved.id)
    local iconSeedSlot = ResolveChildTotemSlot(resolved._blizzChild, nil)
    local barSeedSlot = ResolveChildTotemSlot(resolved._blizzBarChild, nil)
    resolved._isTotemBacked = resolved.isAura and (iconSeedSlot ~= nil or barSeedSlot ~= nil)

    return resolved
end

local function CloneResolvedEntry(entry)
    local clone = {}
    for k, v in pairs(entry) do
        clone[k] = v
    end
    return clone
end

local function BuildAuraInstanceKey(containerKey, child, ordinal)
    local viewerName = child and child.viewerFrame and child.viewerFrame.GetName and child.viewerFrame:GetName() or nil
    local auraInstanceID = child and Helpers.SafeValue(child.auraInstanceID, nil)
    if auraInstanceID then
        return string.format("%s:%s:%s", containerKey or "aura", viewerName or "viewer", auraInstanceID)
    end
    if child then
        return string.format("%s:%s:%s", containerKey or "aura", viewerName or "viewer", tostring(child))
    end
    return string.format("%s:entry:%d", containerKey or "aura", ordinal or 1)
end

local function ExpandResolvedAuraEntry(containerKey, resolved)
    local viewerType = (containerKey == "trackedBar") and "trackedBar" or "buff"
    local primaryChildren, fallbackChildren = GetBuffChildrenForSpell(
        viewerType,
        resolved.overrideSpellID,
        resolved.spellID,
        resolved.id
    )
    local buffViewer = _G["BuffIconCooldownViewer"]
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    local activeChildren = {}
    local byAuraInstanceID = {}
    local byTotemSlot = {}
    local byFrameKey = {}

    local function scoreTotemChild(child)
        if not child then return -1 end
        local score = 0
        local viewer = child.viewerFrame
        if _isViewerPoolActive(viewer, child) then
            score = score + 4
        end
        if child.cooldownInfo then
            score = score + 2
        end
        if child.auraInstanceID then
            score = score + 1
        end
        if child._cachedCdInfo then
            score = score + 1
        end
        if SafeMaybeNumber(rawget(child, "preferredTotemUpdateSlot")) then
            score = score + 1
        end
        return score
    end

    local function slotHasLiveDuration(slot)
        if not slot or not GetTotemDuration then return false end
        local ok, durObj = pcall(GetTotemDuration, slot)
        return ok and durObj and type(durObj) ~= "number"
    end

    local anchorCooldownID = GetChildCooldownID(resolved._blizzChild) or GetChildCooldownID(resolved._blizzBarChild)

    local function findAnySlotChild(targetViewer, slot)
        if not targetViewer or not slot then return nil end
        local allChildren = {}
        local seen = {}
        _appendUniqueViewerChildren(allChildren, seen, targetViewer)
        local bestChild
        local bestScore = -1
        for _, ch in ipairs(allChildren) do
            local childCooldownID = GetChildCooldownID(ch)
            local cooldownMatches = (not anchorCooldownID) or (childCooldownID and childCooldownID == anchorCooldownID)
            if cooldownMatches and ResolveChildTotemSlot(ch, nil) == slot then
                local score = scoreTotemChild(ch)
                if score > bestScore then
                    bestScore = score
                    bestChild = ch
                end
            end
        end
        return bestChild
    end

    if resolved._isTotemBacked then
        local expanded = {}
        local candidateSlots = {}
        local function addCandidateSlot(slot)
            if slot and slot > 0 and not candidateSlots[slot] then
                candidateSlots[slot] = true
            end
        end
        addCandidateSlot(ResolveChildTotemSlot(resolved._blizzChild, nil))
        addCandidateSlot(ResolveChildTotemSlot(resolved._blizzBarChild, nil))
        for _, ch in ipairs(primaryChildren) do
            addCandidateSlot(ResolveChildTotemSlot(ch, nil))
        end
        for _, ch in ipairs(fallbackChildren) do
            addCandidateSlot(ResolveChildTotemSlot(ch, nil))
        end
        if anchorCooldownID then
            local function addCooldownLinkedSlots(targetViewer)
                if not targetViewer then return end
                local allChildren = {}
                local seen = {}
                _appendUniqueViewerChildren(allChildren, seen, targetViewer)
                for _, ch in ipairs(allChildren) do
                    if GetChildCooldownID(ch) == anchorCooldownID then
                        addCandidateSlot(ResolveChildTotemSlot(ch, nil))
                    end
                end
            end
            addCooldownLinkedSlots(buffViewer)
            addCooldownLinkedSlots(buffBarViewer)
        end
        local numSlots = SafeMaybeNumber((GetNumTotemSlots and GetNumTotemSlots()) or 5) or 5
        for slot = 1, numSlots do
            if slotHasLiveDuration(slot) or (containerKey == "buff" and candidateSlots[slot]) then
                local clone = CloneResolvedEntry(resolved)
                local primaryChild = findAnySlotChild(buffBarViewer, slot)
                local fallbackChild = findAnySlotChild(buffViewer, slot)
                clone._instanceKey = string.format("%s:totem:%d", containerKey or "aura", slot)
                if containerKey == "trackedBar" then
                    clone._blizzBarChild = primaryChild or fallbackChild
                    clone._blizzChild = fallbackChild or primaryChild
                else
                    clone._blizzChild = fallbackChild or primaryChild
                    clone._blizzBarChild = primaryChild or fallbackChild
                end
                clone._isTotemInstance = true
                clone._totemSlot = slot
                expanded[#expanded + 1] = clone
            end
        end
        if #expanded > 0 then
            return expanded
        end
    end

    local function assignRowChild(row, key, child)
        if not child then return end
        local current = row[key]
        if not current or scoreTotemChild(child) > scoreTotemChild(current) then
            row[key] = child
        end
    end

    local function addActive(children, isPrimary)
        for _, child in ipairs(children) do
            if ChildHasLiveState(child, resolved.overrideSpellID, resolved.spellID, resolved.id) then
                local totemSlot = ResolveChildTotemSlot(child, nil)
                if totemSlot then
                    local row = byTotemSlot[totemSlot]
                    if not row then
                        row = { primary = nil, fallback = nil, totemSlot = totemSlot }
                        byTotemSlot[totemSlot] = row
                        activeChildren[#activeChildren + 1] = row
                    end
                    if isPrimary then
                        assignRowChild(row, "primary", child)
                    else
                        assignRowChild(row, "fallback", child)
                    end
                else
                    local auraInstanceID = child and Helpers.SafeValue(child.auraInstanceID, nil)
                    if auraInstanceID then
                        local row = byAuraInstanceID[auraInstanceID]
                        if not row then
                            row = { primary = nil, fallback = nil, auraInstanceID = auraInstanceID }
                            byAuraInstanceID[auraInstanceID] = row
                            activeChildren[#activeChildren + 1] = row
                        end
                        if isPrimary then
                            row.primary = row.primary or child
                        else
                            row.fallback = row.fallback or child
                        end
                    else
                        local frameKey = tostring(child)
                        if not byFrameKey[frameKey] then
                            local row = { primary = nil, fallback = nil, frameKey = frameKey }
                            if isPrimary then
                                row.primary = child
                            else
                                row.fallback = child
                            end
                            byFrameKey[frameKey] = row
                            activeChildren[#activeChildren + 1] = row
                        else
                            local row = byFrameKey[frameKey]
                            if isPrimary then
                                row.primary = row.primary or child
                            else
                                row.fallback = row.fallback or child
                            end
                        end
                    end
                end
            end
        end
    end

    addActive(primaryChildren, true)
    addActive(fallbackChildren, false)

    _totemDbg("Expand: container=", containerKey, "primaryN=", #primaryChildren,
        "fallbackN=", #fallbackChildren, "activeN=", #activeChildren)

    -- Slot-backed virtual auras should not fall back to a generic base row
    -- once their slot instances have collapsed. That creates a teardown
    -- flash where the summon briefly reappears as a non-slot row before
    -- the next batch finally removes it.
    if resolved._isTotemBacked and #activeChildren == 0 then
        return {}
    end

    if resolved._isTotemBacked and #activeChildren == 1 then
        local row = activeChildren[1]
        local clone = CloneResolvedEntry(resolved)
        local primaryChild = row.primary
        local fallbackChild = row.fallback
        if containerKey == "trackedBar" then
            clone._blizzBarChild = primaryChild or fallbackChild or resolved._blizzBarChild
            clone._blizzChild = fallbackChild or primaryChild or resolved._blizzChild
        else
            clone._blizzChild = primaryChild or fallbackChild or resolved._blizzChild
            clone._blizzBarChild = fallbackChild or primaryChild or resolved._blizzBarChild
        end
        clone._instanceKey = row.totemSlot
            and string.format("%s:totem:%d", containerKey or "aura", row.totemSlot)
            or BuildAuraInstanceKey(containerKey, clone._blizzChild or clone._blizzBarChild, 1)
        clone._isTotemInstance = row.totemSlot and true or nil
        clone._totemSlot = row.totemSlot
        return { clone }
    end

    if #activeChildren <= 1 then
        resolved._instanceKey = BuildAuraInstanceKey(containerKey, resolved._blizzChild, 1)
        return { resolved }
    end

    local expanded = {}
    for idx, row in ipairs(activeChildren) do
        local clone = CloneResolvedEntry(resolved)
        local primaryChild = row.primary
        local fallbackChild = row.fallback
        local keyChild = primaryChild or fallbackChild or resolved._blizzChild
        clone._instanceKey = BuildAuraInstanceKey(containerKey, keyChild, idx)
        if containerKey == "trackedBar" then
            clone._blizzBarChild = primaryChild or fallbackChild or resolved._blizzBarChild
            clone._blizzChild = fallbackChild or primaryChild or resolved._blizzChild
        else
            clone._blizzChild = primaryChild or fallbackChild or resolved._blizzChild
            clone._blizzBarChild = fallbackChild or primaryChild or resolved._blizzBarChild
        end
        -- Only rows that were grouped by a real resolved totem slot are
        -- allowed to become totem-instance clones. Do not infer slot-backed
        -- identity here from generic child capabilities; that causes normal
        -- aura rows to inherit stale _totemSlot state and contaminate the
        -- icon/bar build paths.
        if row.totemSlot then
            clone._isTotemInstance = true
            clone._totemSlot = row.totemSlot
        else
            clone._isTotemInstance = nil
            clone._totemSlot = nil
        end
        expanded[#expanded + 1] = clone
    end

    return expanded
end

-- SnapshotBlizzardCDM: One-time capture of Blizzard viewer spells into ownedSpells
function CDMSpellData:SnapshotBlizzardCDM(containerKey)
    if InCombatLockdown() and not ns._inInitSafeWindow then
        return false
    end

    -- Custom containers have no Blizzard viewer — skip snapshot
    if not VIEWER_NAMES[containerKey] then return false end

    local db = GetContainerDB(containerKey)
    if not db then
        return false
    end

    -- Only snapshot if ownedSpells == nil (first time)
    if db.ownedSpells ~= nil then
        return false
    end

    -- Use existing scan to get the current spell list
    local scanList = spellLists[containerKey]
    if not scanList or type(scanList) ~= "table" or #scanList == 0 then
        -- Try a fresh scan first
        if containerKey == "trackedBar" then
            -- TrackedBar uses BuffBarCooldownViewer — scan its children
            local viewer = _G["BuffBarCooldownViewer"]
            if not viewer then return false end
            -- Collect spellIDs from bar children (dedup)
            local owned = {}
            local seenBarIDs = {}
            local sel = viewer.Selection
            local okc, children = pcall(function() return { viewer:GetChildren() } end)
            if okc and children then
                for _, child in ipairs(children) do
                    if child and child ~= sel and child.Bar then
                        local cdInfo = child.cooldownInfo
                        if cdInfo then
                            local sid = Helpers.SafeValue(cdInfo.overrideSpellID, nil) or Helpers.SafeValue(cdInfo.spellID, nil)
                            if sid and not seenBarIDs[sid] then
                                seenBarIDs[sid] = true
                                owned[#owned + 1] = { type = "spell", id = sid }
                                -- Map spell ID → child for combat hook lookups
                                if not _spellIDToChild[sid] then _spellIDToChild[sid] = {} end
                                _spellIDToChild[sid][#_spellIDToChild[sid] + 1] = child
                                local altSid = Helpers.SafeValue(cdInfo.spellID, nil)
                                if altSid and altSid ~= sid then
                                    if not _spellIDToChild[altSid] then _spellIDToChild[altSid] = {} end
                                    _spellIDToChild[altSid][#_spellIDToChild[altSid] + 1] = child
                                end
                            end
                        end
                        -- Hook Cooldown frame for DurationObject capture
                        HookChildCooldown(child)
                    end
                end
            end
            if #owned > 0 then
                db.ownedSpells = owned
                local ncdm = GetNcdmDB()
                if ncdm then
                    ncdm._snapshotVersion = (ncdm._snapshotVersion or 0) + 1
                end
                return true
            end
            -- Children exist but have no cooldownInfo yet (too early at login).
            -- Fall through to C_CooldownViewer API path below.
        else
            -- Essential/utility/buff: use existing scanned lists
            ScanViewer(containerKey)
            scanList = spellLists[containerKey]
        end
    end

    -- Primary path: C_CooldownViewer API returns ALL spells in a category,
    -- including those the user has not "added" to their CDM bars. The API
    -- has no field to distinguish added vs not-added. Use viewer children
    -- as the authoritative source: Blizzard only creates children for spells
    -- the user has added. When viewer children exist, filter API results
    -- to match. When the viewer is empty (first install), include all.
    local isAuraContainer = (containerKey == "buff" or containerKey == "trackedBar")
    local owned = {}
    local seenIDs = {}

    -- Build map of cooldownID → layoutIndex from Blizzard viewer children.
    -- These are the spells the user has actually "added" to their CDM bar.
    -- layoutIndex preserves Blizzard's visual ordering.
    local viewerCDIDs = {}
    local viewerChildCount = 0
    local viewerName = VIEWER_NAMES[containerKey]
    local viewer = viewerName and _G[viewerName]
    if viewer then
        local containersToScan = { viewer.viewerFrame or viewer }
        -- For buff, also check the addon container (children may be reparented)
        if containerKey == "buff" then
            local addonContainer = _G["QUI_BuffIconContainer"]
            if addonContainer and addonContainer ~= containersToScan[1] then
                containersToScan[#containersToScan + 1] = addonContainer
            end
        end
        for _, scanContainer in ipairs(containersToScan) do
            local okc, children = pcall(function() return { scanContainer:GetChildren() } end)
            if okc and children then
                for _, ch in ipairs(children) do
                    local chCdID = ch.cooldownID or (ch.cooldownInfo and ch.cooldownInfo.cooldownID)
                    if chCdID then
                        viewerCDIDs[chCdID] = ch.layoutIndex or 9999
                        viewerChildCount = viewerChildCount + 1
                    end
                end
            end
        end
    end
    local hasViewerFilter = (viewerChildCount > 0)

    -- CooldownSetSpellFlags.HideByDefault — Blizzard hides these spells from
    -- the CDM bars by default (moves them to pseudo-categories -1/-2 on the
    -- Lua side).  The C-side API still returns them in their real category,
    -- so we filter them out here so only user-visible spells are imported.
    local HIDE_BY_DEFAULT = 2

    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
       and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        -- Use 1:1 snapshot categories so spells land in the correct container
        -- (e.g. Blizzard Essential → QUI essential, Utility → utility).
        local categories = CDM_SNAPSHOT_CATEGORIES[containerKey] or CDM_BAR_CATEGORIES[containerKey] or { 0, 1, 2, 3 }
        for _, category in ipairs(categories) do
            local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
            if ok and cooldownIDs then
                for _, cdID in ipairs(cooldownIDs) do
                    local okInfo, cdInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    if okInfo and cdInfo then
                        local flags = cdInfo.flags or 0
                        if bit.band(flags, HIDE_BY_DEFAULT) ~= 0 then
                            -- Skip — hidden by default in Blizzard's CDM
                        elseif hasViewerFilter and not viewerCDIDs[cdID] then
                            -- Skip — in API but not in viewer = "not added"
                        else
                            local sid = _cdIDToCorrectSID[cdID]
                            if not sid and isAuraContainer then
                                local tooltipSid = Helpers.SafeValue(cdInfo.overrideTooltipSpellID, nil)
                                if tooltipSid and tooltipSid > 0 then
                                    sid = tooltipSid
                                end
                            end
                            if not sid then
                                -- Cooldown containers: store the stable base
                                -- spellID so the entry survives talent swaps.
                                -- The override is resolved dynamically each
                                -- tick via C_Spell.GetOverrideSpell.
                                -- Aura containers still use ResolveInfoSpellID
                                -- (override points to the actual tracked aura).
                                if not isAuraContainer then
                                    local baseSid2 = Helpers.SafeValue(cdInfo.spellID, nil)
                                    if baseSid2 and baseSid2 > 0 then
                                        sid = baseSid2
                                    else
                                        sid = ResolveInfoSpellID(cdInfo)
                                    end
                                else
                                    sid = ResolveInfoSpellID(cdInfo)
                                end
                            end
                            if sid and not seenIDs[sid] then
                                seenIDs[sid] = true
                                owned[#owned + 1] = {
                                    type = "spell",
                                    id = sid,
                                    kind = isAuraContainer and "aura" or "cooldown",
                                    _layoutIndex = viewerCDIDs[cdID] or 9999,
                                }
                                -- Also mark the override spellID so the fallback
                                -- merge doesn't re-add it as a duplicate.
                                local baseSid = Helpers.SafeValue(cdInfo.spellID, nil)
                                if baseSid and baseSid ~= sid then
                                    seenIDs[baseSid] = true
                                end
                                local ovSid = Helpers.SafeValue(cdInfo.overrideSpellID, nil)
                                if ovSid and ovSid ~= sid then
                                    seenIDs[ovSid] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Fallback: merge any viewer-child spells not already found by the API
    -- (handles edge cases where children exist but the API doesn't list them).
    -- Buff + trackedBar are allowed to cross-pull from each other because they
    -- are two views of the same aura-backed data. The important boundary is
    -- against non-aura categories, not between the two aura viewers.
    if scanList and type(scanList) == "table" then
        for _, entry in ipairs(scanList) do
            local sid = entry.spellID
            if isAuraContainer and entry._blizzChild then
                local correctedSID = ResolveChildSpellID(entry._blizzChild)
                if correctedSID then
                    sid = correctedSID
                end
            end
            if sid and not seenIDs[sid] then
                seenIDs[sid] = true
                owned[#owned + 1] = {
                    type = "spell",
                    id = sid,
                    kind = isAuraContainer and "aura" or "cooldown",
                }
            end
        end
    end

    if #owned == 0 then
        return false
    end

    -- Sort by Blizzard viewer layoutIndex to match visual order
    if hasViewerFilter then
        table.sort(owned, function(a, b)
            return (a._layoutIndex or 9999) < (b._layoutIndex or 9999)
        end)
    end

    -- Strip temporary sort keys before persisting
    for _, entry in ipairs(owned) do
        entry._layoutIndex = nil
    end

    -- Auto-assign row fields to respect per-row iconCount limits.
    -- Without this, all entries land on row 1 and overflow the max.
    if db.row1 or db.row2 or db.row3 then
        local activeRows = {}
        for r = 1, 3 do
            local rd = db["row" .. r]
            if rd and rd.iconCount and rd.iconCount > 0 then
                activeRows[#activeRows + 1] = { rowNum = r, capacity = rd.iconCount }
            end
        end
        if #activeRows > 0 then
            local rowIdx = 1
            local placed = 0
            for _, entry in ipairs(owned) do
                if rowIdx <= #activeRows then
                    entry.row = activeRows[rowIdx].rowNum
                    placed = placed + 1
                    if placed >= activeRows[rowIdx].capacity then
                        rowIdx = rowIdx + 1
                        placed = 0
                    end
                end
                -- Entries beyond all rows' capacity: no row assignment,
                -- they'll overflow into the last row visually.
            end
        end
    end

    db.ownedSpells = owned
    local ncdm = GetNcdmDB()
    if ncdm then
        ncdm._snapshotVersion = (ncdm._snapshotVersion or 0) + 1
    end
    return true
end

-- BuildSpellListFromOwned: Build runtime spell list from owned data
function CDMSpellData:BuildSpellListFromOwned(containerKey)
    local db = GetContainerDB(containerKey)
    if not db or type(db.ownedSpells) ~= "table" then return {} end

    -- Ensure correction maps are built for accurate aura spellID resolution
    if not next(_cdIDToCorrectSID) then
        RebuildCdIDToCorrectSID()
    end
    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end

    -- Wipe per-batch memo caches so a stale aura-active result from the
    -- previous batch can't persist across buff-data-changed dispatches.
    -- Icon lookups would be safe to carry, but wiping both keeps the
    -- invariant simple: memos live for exactly one batch.
    wipe(_resolveIconMemo)
    wipe(_resolveAuraActiveMemo)

    local ownedSpells = NormalizeOwnedSpells(db.ownedSpells)
    local removedSpells = db.removedSpells or {}

    -- Resolve entries, preserving row assignment from ownedSpells
    local result = {}
    local seenInstanceKeys = {}
    for i, entry in ipairs(ownedSpells) do
        if entry and entry.id then
            -- Skip removed spells
            local isRemoved = false
            if entry.type == "spell" and removedSpells[entry.id] then
                isRemoved = true
            end
            -- Owned spells are explicitly configured by the user via /cdm.
            -- No spellbook filter needed — the dormant system handles
            -- spec-switching cleanup separately.

            if not isRemoved then
                local resolved = ResolveOwnedEntry(entry, containerKey, i)
                if resolved then
                    resolved._assignedRow = entry.row  -- carry row assignment
                    local expanded = resolved
                    if resolved.isAura then
                        expanded = ExpandResolvedAuraEntry(containerKey, resolved)
                    else
                        resolved._instanceKey = BuildAuraInstanceKey(containerKey, resolved._blizzChild, 1)
                        expanded = { resolved }
                    end
                    for _, expandedEntry in ipairs(expanded) do
                        local instanceKey = expandedEntry and expandedEntry._instanceKey
                        local shouldDedupe = expandedEntry and (
                            expandedEntry._isTotemInstance
                            or (expandedEntry.isAura and instanceKey and not instanceKey:find(":entry:", 1, true))
                        )
                        if shouldDedupe and instanceKey then
                            if not seenInstanceKeys[instanceKey] then
                                seenInstanceKeys[instanceKey] = true
                                result[#result + 1] = expandedEntry
                            end
                        else
                            result[#result + 1] = expandedEntry
                        end
                    end
                end
            end
        end
    end

    -- Sort by assigned row: entries with row assignment come first (grouped by row),
    -- then unassigned entries in original order. Within a row, original order is preserved.
    local hasAnyRow = false
    for _, r in ipairs(result) do
        if r._assignedRow then hasAnyRow = true; break end
    end
    if hasAnyRow then
        -- Stable sort: preserve relative order within same row
        for idx, r in ipairs(result) do r._sortIdx = idx end
        table.sort(result, function(a, b)
            local ar = a._assignedRow or 0
            local br = b._assignedRow or 0
            if ar ~= br then return ar < br end
            return a._sortIdx < b._sortIdx
        end)
    end

    _totemDbg("BuildSpellListFromOwned container=", containerKey, "result=", #result)
    return result
end

---------------------------------------------------------------------------
-- DORMANT SPELL CHECKING
-- Checks ownedSpells against currently known spells and updates dormantSpells.
-- Called on talent/spec changes. Dormant spells are skipped during display
-- but preserved in ownedSpells for when the player respecs back.
---------------------------------------------------------------------------
-- CheckDormantSpells: Three-phase talent-aware reconciliation.
-- Phase 1: Move unlearned spells from ownedSpells → dormantSpells, saving slot index.
-- Phase 2: Re-insert returning dormant spells at their saved position.
-- Phase 3: Clean obsolete dormant entries for spells removed from game.
-- dormantSpells is a map: { [spellID] = { slot = originalSlotIndex, row = rowNum } }
--
-- restoreOnly (boolean): when true, skip Phase 1 (marking spells dormant) and
-- Phase 3 (permanent deletion). Only run Phase 2 (restore returning spells).
-- Used by recovery handlers (PLAYER_REGEN_ENABLED, CHALLENGE_MODE_START) that
-- should rescue incorrectly-dormanted spells without risking re-dormanting more.
function CDMSpellData:CheckDormantSpells(containerKey, restoreOnly)
    local db = GetContainerDB(containerKey)
    if not db or type(db.ownedSpells) ~= "table" then
        return
    end

    local ownedSpells = NormalizeOwnedSpells(db.ownedSpells)

    -- Migrate legacy dormantSpells from array to map format
    if type(db.dormantSpells) ~= "table" then
        db.dormantSpells = {}
    else
        -- If it's an array (ipairs-style), convert to map
        local first = db.dormantSpells[1]
        if type(first) == "number" then
            local migrated = {}
            for _, sid in ipairs(db.dormantSpells) do
                if type(sid) == "number" then
                    migrated[sid] = 9999  -- no saved position from legacy data
                end
            end
            db.dormantSpells = migrated
        end
    end

    -- Phase 1: Move unlearned spells to dormant.
    -- Skipped when restoreOnly is true — recovery handlers should only
    -- rescue spells from dormant, not risk marking more spells dormant
    -- while APIs may still be settling after a zone transition.
    if not restoreOnly then
        local toRemove = {}  -- indices to remove (descending order)
        for i, entry in ipairs(ownedSpells) do
            if entry and entry.id and entry.type == "spell" then
                local known = IsSpellKnownByPlayer(entry.id)
                if not known then
                    -- Save slot position AND row assignment so both are restored
                    db._dormantSequence = (db._dormantSequence or 0) + 1
                    db.dormantSpells[entry.id] = {
                        slot = i,
                        row = entry.row,
                        seq = db._dormantSequence,
                    }
                    toRemove[#toRemove + 1] = i
                end
            end
        end
        -- Remove from ownedSpells in reverse order to preserve indices
        for j = #toRemove, 1, -1 do
            table.remove(db.ownedSpells, toRemove[j])
        end
    end

    -- Phase 2: Re-insert returning dormant spells at saved positions
    local returning = {}
    for sid, savedData in pairs(db.dormantSpells) do
        if IsSpellKnownByPlayer(sid) then
            -- Support both legacy (number) and new (table) dormant format
            local savedSlot, savedRow, savedSeq
            if type(savedData) == "table" then
                savedSlot = savedData.slot or 9999
                savedRow = savedData.row
                savedSeq = savedData.seq or savedSlot
            else
                savedSlot = savedData or 9999
                savedSeq = savedSlot
            end
            returning[#returning + 1] = {
                id = sid,
                slot = savedSlot,
                row = savedRow,
                seq = savedSeq,
            }
        end
    end
    -- Sort by saved slot, then by dormant sequence for deterministic same-slot restores.
    table.sort(returning, function(a, b)
        if a.slot ~= b.slot then
            return a.slot < b.slot
        end
        if a.seq ~= b.seq then
            return a.seq < b.seq
        end
        return a.id < b.id
    end)
    if #returning > 0 then
    end
    for _, info in ipairs(returning) do
        db.dormantSpells[info.id] = nil  -- remove from dormant
        local insertAt = math.min(info.slot, #db.ownedSpells + 1)
        local restored = { type = "spell", id = info.id, row = info.row }
        restored.kind = ResolveEntryKind(restored, containerKey)
        table.insert(db.ownedSpells, insertAt, restored)
    end

    -- Phase 3: Clean obsolete dormant spells no longer in the CDM system.
    -- Skip when restoreOnly (recovery path) or during zone transitions —
    -- C_CooldownViewer and spellbook APIs return incomplete data during
    -- transitions, which causes valid dormant spells to be permanently
    -- deleted with no way to recover them.
    if restoreOnly or _inZoneTransition then
        -- skip Phase 3
    elseif C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        local allCDMSpells = {}
        for cat = 0, 3 do
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
            if ok and ids then
                for _, cdID in ipairs(ids) do
                    if C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                        if okI and info then
                            local sid = Helpers.SafeValue(info.spellID, nil)
                            if sid then allCDMSpells[sid] = true end
                            local ov = Helpers.SafeValue(info.overrideSpellID, nil)
                            if ov then allCDMSpells[ov] = true end
                        end
                    end
                end
            end
        end
        -- Also include spellbook spells as "still existing"
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
            local okT, numTabs = pcall(C_SpellBook.GetNumSpellBookSkillLines)
            if okT and numTabs then
                for tab = 1, numTabs do
                    local okL, sli = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tab)
                    if okL and sli then
                        local offset = sli.itemIndexOffset or 0
                        for i = 1, (sli.numSpellBookItems or 0) do
                            local okI, ii = pcall(C_SpellBook.GetSpellBookItemInfo, offset + i, Enum.SpellBookSpellBank.Player)
                            if okI and ii and ii.spellID then allCDMSpells[ii.spellID] = true end
                        end
                    end
                end
            end
        end
        local obsoleteCount = 0
        for sid in pairs(db.dormantSpells) do
            if not allCDMSpells[sid] then
                db.dormantSpells[sid] = nil  -- spell removed from game
                obsoleteCount = obsoleteCount + 1
            end
        end
        if obsoleteCount > 0 then
        end
    end

    -- Summary
    local finalOwned = type(db.ownedSpells) == "table" and #db.ownedSpells or 0
    local finalDormant = 0
    if type(db.dormantSpells) == "table" then
        for _ in pairs(db.dormantSpells) do finalDormant = finalDormant + 1 end
    end
end

-- CheckAllDormantSpells: Run dormant check on all container keys.
-- restoreOnly: when true, only Phase 2 (restore) runs — no new dormanting
-- or permanent deletion. Used by recovery handlers.
function CDMSpellData:CheckAllDormantSpells(restoreOnly)
    local containerKeys = { "essential", "utility", "buff", "trackedBar" }
    if ns.CDMContainers and ns.CDMContainers.GetAllContainerKeys then
        containerKeys = ns.CDMContainers.GetAllContainerKeys()
    end
    for _, key in ipairs(containerKeys) do
        self:CheckDormantSpells(key, restoreOnly)
    end
end

---------------------------------------------------------------------------
-- EXTRA SPELL TABLES (racials, health items)
---------------------------------------------------------------------------
local RACE_RACIALS = {
    Scourge            = { 7744 },
    Tauren             = { 20549 },
    Orc                = { 20572, 33697, 33702 },
    BloodElf           = { 202719, 50613, 25046, 69179, 80483, 155145, 129597, 232633, 28730 },
    Dwarf              = { 20594 },
    Troll              = { 26297 },
    Draenei            = { 28880 },
    NightElf           = { 58984 },
    Human              = { 59752 },
    DarkIronDwarf      = { 265221 },
    Gnome              = { 20589 },
    HighmountainTauren = { 69041 },
    Worgen             = { 68992 },
    Goblin             = { 69070 },
    Pandaren           = { 107079 },
    MagharOrc          = { 274738 },
    LightforgedDraenei = { 255647 },
    VoidElf            = { 256948 },
    Nightborne         = { 260364 },
    KulTiran           = { 287712 },
    ZandalariTroll     = { 291944 },
    Vulpera            = { 312411 },
    Mechagnome         = { 312924 },
    Dracthyr           = { 357214, { 368970, class = "EVOKER" } },
    EarthenDwarf       = { 436344 },
    Haranir            = { 1287685 },
}

local HEALTH_ITEMS = {
    { itemID = 241304, spellID = 1234768, altItemID = 241305 },
    { itemID = 241308, spellID = 1236616, altItemID = 241309 },
    { itemID = 5512,   spellID = 6262 },
    { itemID = 224464, spellID = 452930, class = "WARLOCK" },
}

---------------------------------------------------------------------------
-- SPELLID RESOLUTION
-- Blizzard's CDM info struct can return wrong spellIDs (especially for
-- buff bars where it returns spec aura ID instead of actual tracked buff).
-- Two-layer resolution: info struct → frame methods → persistent correction map.
---------------------------------------------------------------------------

-- Resolve spellID from CDM info struct.
-- Priority: overrideSpellID → first linkedSpellID → spellID
ResolveInfoSpellID = function(info)
    if not info then return nil end
    local ov = Helpers.SafeValue(info.overrideSpellID, nil)
    if ov and ov > 0 then return ov end
    local linked = info.linkedSpellIDs
    if linked then
        for i = 1, #linked do
            local lsid = Helpers.SafeValue(linked[i], nil)
            if lsid and lsid > 0 then return lsid end
        end
    end
    local sid = Helpers.SafeValue(info.spellID, nil)
    if sid and sid > 0 then return sid end
    return nil
end

-- Resolve spellID from a viewer child frame (out-of-combat only).
-- Frame methods are more accurate but can return secret values in combat.
ResolveChildSpellID = function(child)
    if not child then return nil end
    -- Prefer aura spellID (most accurate for buff viewers)
    if child.GetAuraSpellID then
        local ok, auraID = pcall(child.GetAuraSpellID, child)
        if ok and auraID then
            local cmpOk, gt = pcall(function() return auraID > 0 end)
            if cmpOk and gt then return auraID end
        end
    end
    -- Then try the frame's own spellID
    if child.GetSpellID then
        local ok, fid = pcall(child.GetSpellID, child)
        if ok and fid then
            local cmpOk, gt = pcall(function() return fid > 0 end)
            if cmpOk and gt then return fid end
        end
    end
    -- Fall back to cooldownInfo struct
    local cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok then return ResolveInfoSpellID(info) end
    end
    return nil
end

-- Build persistent correction map from buff viewer children.
-- Called out of combat — compares info struct spellID vs frame-resolved spellID.
RebuildCdIDToCorrectSID = function()
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCooldownInfo then return end
    -- Only scan buff viewers where misidentification is common
    for _, vName in ipairs({ VIEWER_NAMES.buff, VIEWER_NAMES.trackedBar }) do
        local vf = _G[vName]
        if vf then
            local numChildren = vf:GetNumChildren()
            for ci = 1, numChildren do
                local ch = select(ci, vf:GetChildren())
                if ch then
                    local cdID = ch.cooldownID or (ch.cooldownInfo and ch.cooldownInfo.cooldownID)
                    if cdID and not _cdIDToCorrectSID[cdID] then
                        local correctSid = ResolveChildSpellID(ch)
                        if correctSid and correctSid > 0 then
                            local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                            if ok and info then
                                local infoSid = ResolveInfoSpellID(info)
                                if infoSid and correctSid ~= infoSid then
                                    _cdIDToCorrectSID[cdID] = correctSid
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Build global spellID → cooldownID lookup across all 4 CDM categories.
-- Maps base, override, and linked spellIDs. Rebuilt on spec change.
RebuildSpellToCooldownID = function()
    wipe(_spellToCooldownID)
    wipe(_spellInCDMCooldowns)
    wipe(_spellInCDMAuras)
    wipe(_abilityToAuraSpellID)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return end
    for cat = 0, 3 do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
        if ok and ids then
            local isBuffCat = (cat == 2 or cat == 3)
            local familySet = isBuffCat and _spellInCDMAuras or _spellInCDMCooldowns
            for _, cdID in ipairs(ids) do
                local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                if okI and info then
                    local sid = Helpers.SafeValue(info.spellID, nil)
                    if sid and sid > 0 then
                        _spellToCooldownID[sid] = cdID
                        familySet[sid] = true
                    end
                    local ov = Helpers.SafeValue(info.overrideSpellID, nil)
                    if ov and ov > 0 then
                        _spellToCooldownID[ov] = cdID
                        familySet[ov] = true
                    end
                    if info.linkedSpellIDs then
                        for _, lsid in ipairs(info.linkedSpellIDs) do
                            local lv = Helpers.SafeValue(lsid, nil)
                            if lv and lv > 0 then
                                _spellToCooldownID[lv] = cdID
                                familySet[lv] = true
                            end
                        end
                    end

                    -- For buff categories (2=buff icon, 3=buff bar), map the
                    -- base spellID to the aura spell ID.  The info struct's
                    -- overrideSpellID or linkedSpellIDs contain the actual aura
                    -- spell ID that GetPlayerAuraBySpellID accepts in combat.
                    -- Priority: overrideSpellID > first linkedSpellID > spellID.
                    if isBuffCat then
                        -- For buff categories, linkedSpellIDs contains the BUFF
                        -- spell ID(s) (what GetPlayerAuraBySpellID accepts).
                        -- The base/override is the ABILITY spell ID.
                        -- Only map ability ID → first linked buff.
                        -- Do NOT map other linked buff IDs to each other —
                        -- they are independent auras (e.g. Death Strike →
                        -- Blood Shield AND Coagulopathy are separate buffs).
                        local auraID
                        if info.linkedSpellIDs then
                            for _, lsid in ipairs(info.linkedSpellIDs) do
                                local lv = Helpers.SafeValue(lsid, nil)
                                if lv and lv > 0 then auraID = lv; break end
                            end
                        end
                        if not auraID then auraID = ov or sid end

                        if auraID then
                            local baseKey = sid or ov
                            local existing = baseKey and _abilityToAuraSpellID[baseKey]
                            -- When multiple CDM entries share the same base
                            -- spellID but link to different auras (e.g. Inertia
                            -- 427640 → 427641 and 427640 → 1215159), prefer the
                            -- linked aura whose icon differs from the base — that
                            -- is the active buff, not a passive/hidden variant.
                            if existing and existing ~= auraID and baseKey then
                                local baseIcon
                                if C_Spell and C_Spell.GetSpellInfo then
                                    local bi = C_Spell.GetSpellInfo(baseKey)
                                    baseIcon = bi and bi.iconID
                                end
                                if baseIcon then
                                    local existIcon, newIcon
                                    if C_Spell.GetSpellInfo then
                                        local ei = C_Spell.GetSpellInfo(existing)
                                        existIcon = ei and ei.iconID
                                        local ni = C_Spell.GetSpellInfo(auraID)
                                        newIcon = ni and ni.iconID
                                    end
                                    -- Prefer the aura with a distinct icon
                                    if existIcon == baseIcon and newIcon and newIcon ~= baseIcon then
                                        _abilityToAuraSpellID[baseKey] = auraID
                                        if ov and ov ~= auraID and ov ~= baseKey then
                                            _abilityToAuraSpellID[ov] = auraID
                                        end
                                    end
                                    -- If existing already has distinct icon, keep it
                                end
                            else
                                -- Map base ability → first linked aura
                                if sid and sid ~= auraID then
                                    _abilityToAuraSpellID[sid] = auraID
                                end
                                -- Map override ability → first linked aura
                                if ov and ov ~= auraID and ov ~= sid then
                                    _abilityToAuraSpellID[ov] = auraID
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Also map correct spellIDs from the persistent correction map
    for cdID, correctSid in pairs(_cdIDToCorrectSID) do
        _spellToCooldownID[correctSid] = cdID
    end
end

---------------------------------------------------------------------------
-- DYNAMIC SPELL RECONCILIATION
-- Two-pass approach: preserve existing tracked spells (maintain user ordering),
-- then append newly discovered spells at the end.
---------------------------------------------------------------------------


-- globalTracked: set of "type:id" keys across ALL containers. Built once in
-- ReconcileAllContainers and passed in. Prevents the same spell from being
-- auto-added to multiple containers (e.g. essential AND utility both scan
-- categories {0,1}, so without this a spell would appear in both).
-- Updated in-place as new spells are added so subsequent containers see them.
function CDMSpellData:ReconcileOwnedSpells(containerKey, globalTracked)
    if InCombatLockdown() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end
    -- Only reconcile containers that have been snapshotted
    if db.ownedSpells == nil then return false end

    -- Build set of existing tracked entries in THIS container (for within-container dedup)
    local keptSet = {}
    for _, entry in ipairs(db.ownedSpells) do
        local norm = NormalizeOwnedEntry(entry)
        if norm and norm.id then
            keptSet[norm.type .. ":" .. norm.id] = true
        end
    end

    local added = false

    -- Reconciliation does NOT auto-add spells to a curated list.
    -- Once ownedSpells has been snapshotted, only the user adds/removes
    -- entries via the Composer. Reconciliation only handles:
    --   - Dormant spell management (CheckDormantSpells, called before this)
    --   - Correction map rebuild for accurate aura display
    RebuildCdIDToCorrectSID()

    return false
end

function CDMSpellData:ReconcileAllContainers()
    if InCombatLockdown() then
        return
    end

    -- Rebuild spellID maps before reconciliation
    RebuildSpellToCooldownID()

    local containerKeys = { "essential", "utility", "buff", "trackedBar" }
    if ns.CDMContainers and ns.CDMContainers.GetAllContainerKeys then
        containerKeys = ns.CDMContainers:GetAllContainerKeys()
    end

    -- Build global tracked set: union of all containers' ownedSpells + removedSpells + dormantSpells.
    -- Passed to each ReconcileOwnedSpells and updated in-place as new spells are added,
    -- so a spell added to essential won't also be auto-added to utility.
    local globalTracked = {}
    for _, key in ipairs(containerKeys) do
        local db = GetContainerDB(key)
        if db then
            if type(db.ownedSpells) == "table" then
                for _, entry in ipairs(db.ownedSpells) do
                    local norm = NormalizeOwnedEntry(entry)
                    if norm and norm.id then
                        globalTracked[norm.type .. ":" .. norm.id] = true
                    end
                end
            end
            if type(db.removedSpells) == "table" then
                for sid, _ in pairs(db.removedSpells) do
                    if type(sid) == "number" then
                        globalTracked["spell:" .. sid] = true
                    end
                end
            end
            if type(db.dormantSpells) == "table" then
                -- dormantSpells is a map: { [spellID] = { slot, row } }
                for sid, _ in pairs(db.dormantSpells) do
                    if type(sid) == "number" then
                        globalTracked["spell:" .. sid] = true
                    end
                end
            end
        end
    end

    local anyAdded = false
    for _, key in ipairs(containerKeys) do
        local added = self:ReconcileOwnedSpells(key, globalTracked)
        if added then anyAdded = true end
    end

    if anyAdded then
        FireChangeCallback()
    end
end

---------------------------------------------------------------------------
-- LEARNED COOLDOWNS CACHE: Invalidated on SPELLS_CHANGED
---------------------------------------------------------------------------
local learnedCooldownsCache = nil
local learnedCooldownsCacheDirty = true

local function InvalidateLearnedCooldownsCache()
    learnedCooldownsCache = nil
    learnedCooldownsCacheDirty = true
end

---------------------------------------------------------------------------
-- MUTATION HELPERS
---------------------------------------------------------------------------

-- Combat guard: returns true if in combat (mutation refused)
local function CombatGuard()
    return InCombatLockdown()
end

-- Fire the change callback after any mutation.
-- Phase B.3: the legacy customTrackers bridge (SyncCustomBarsToLegacy
-- + its field/color tables + CT:RefreshAll kick) was removed along
-- with the legacy renderer. customBar containers now render via the
-- unified CDM pipeline driven by QUI_OnSpellDataChanged.
FireChangeCallback = function()
    if _G.QUI_OnSpellDataChanged then
        _G.QUI_OnSpellDataChanged()
    end
    -- Keep spec profile in sync so /reload or spec-switch never
    -- overwrites Composer edits with a stale _specProfiles copy.
    if ns.CDMContainers and ns.CDMContainers.SaveActiveSpecProfile then
        ns.CDMContainers.SaveActiveSpecProfile()
    end
end

-- Validate an entry has required fields
local function ValidateEntry(entry)
    if type(entry) ~= "table" then return false end
    if not entry.type then return false end
    if entry.type == "macro" then
        return entry.macroName and type(entry.macroName) == "string"
    end
    return entry.id and type(entry.id) == "number"
end

---------------------------------------------------------------------------
-- MUTATION API
---------------------------------------------------------------------------

-- customBar containers store their entries in `db.entries` (mixed spell/
-- item/slot types from the legacy customTrackers schema). Built-in CDM
-- containers store them in `db.ownedSpells`.
local function GetEntryListField(db)
    if not db then return nil end
    if db.containerType == "customBar" then return "entries" end
    return "ownedSpells"
end

---------------------------------------------------------------------------
-- PER-SPEC ENTRY STORAGE (Phase B.3)
-- When a container has db.specSpecific = true, its entry list is served
-- from db.global.ncdm.specTrackerSpells[containerKey][specKey] instead of
-- db.entries / db.ownedSpells. Each spec keeps its own list. Rendering
-- re-reads via GetSpecEntries on PLAYER_SPECIALIZATION_CHANGED.
---------------------------------------------------------------------------

local function GetCurrentSpecID()
    local specIdx = GetSpecialization and GetSpecialization() or nil
    if not specIdx then return nil end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIdx) or nil
    return type(specID) == "number" and specID or nil
end

local function GetSpecKeyForSpecID(specID)
    local class
    if UnitClass then
        local _
        _, class = UnitClass("player")
    end
    if not class or not specID then return class or "UNKNOWN" end
    return class .. "-" .. tostring(specID)
end

local function GetCurrentSpecKey()
    local class
    if UnitClass then
        local _
        _, class = UnitClass("player")
    end
    local specID = GetCurrentSpecID()
    if not specID then return class or "UNKNOWN" end
    return GetSpecKeyForSpecID(specID)
end

local function GetNumericSpecKey(specKey)
    if type(specKey) ~= "string" then return nil end
    return specKey:match("%-(%d+)$") or specKey:match("^(%d+)$")
end

local function GetSpecTrackerRoot(createIfMissing)
    local core = ns.Addon
    local globalDB = core and core.db and core.db.global
    if not globalDB then return nil end
    if not globalDB.ncdm then
        if not createIfMissing then return nil end
        globalDB.ncdm = {}
    end
    if not globalDB.ncdm.specTrackerSpells then
        if not createIfMissing then return nil end
        globalDB.ncdm.specTrackerSpells = {}
    end
    return globalDB.ncdm.specTrackerSpells
end

local function GetSpecEntryList(containerKey, specKey, createIfMissing)
    local root = GetSpecTrackerRoot(createIfMissing)
    if not root then return nil end
    local byContainer = root[containerKey]
    if not byContainer then
        if not createIfMissing then return nil end
        byContainer = {}
        root[containerKey] = byContainer
    end
    specKey = specKey or GetCurrentSpecKey()
    local list = byContainer[specKey]
    if type(list) ~= "table" then
        local numericKey = GetNumericSpecKey(specKey)
        if numericKey and numericKey ~= specKey then
            list = byContainer[numericKey]
        end
    end
    if not list and createIfMissing then
        list = {}
        byContainer[specKey] = list
    end
    return list, specKey
end

local function CloneEntry(entry)
    if type(entry) ~= "table" then return entry end
    local out = {}
    for k, v in pairs(entry) do out[k] = v end
    return out
end

local function EntriesEquivalent(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.type == b.type
        and a.id == b.id
        and a.macroName == b.macroName
        and a.customName == b.customName
end

local function MergeEntryLists(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local changed = false
    for _, entry in ipairs(src) do
        if type(entry) == "table" then
            local exists = false
            for _, existing in ipairs(dst) do
                if EntriesEquivalent(existing, entry) then
                    exists = true
                    break
                end
            end
            if not exists then
                dst[#dst + 1] = CloneEntry(entry)
                changed = true
            end
        end
    end
    return changed
end

local function ResolveContainerSourceSpecID(db)
    local sourceSpecID = db and db._sourceSpecID
    if type(sourceSpecID) == "number" and sourceSpecID > 0 then
        return sourceSpecID
    end
    local profile = ns.Addon and ns.Addon.db and ns.Addon.db.profile
    local lastSpecID = profile and profile.ncdm and profile.ncdm._lastSpecID
    if type(lastSpecID) == "number" and lastSpecID > 0 then
        return lastSpecID
    end
    return GetCurrentSpecID()
end

local function MoveLegacySpecEntriesToPerSpecStorage(containerKey, db)
    if type(db) ~= "table" or not db.specSpecific then return nil end
    if type(db.entries) ~= "table" or #db.entries == 0 then return nil end

    local sourceSpecID = ResolveContainerSourceSpecID(db)
    if type(sourceSpecID) ~= "number" or sourceSpecID <= 0 then return nil end

    local specKey = GetSpecKeyForSpecID(sourceSpecID)
    local list = GetSpecEntryList(containerKey, specKey, true)
    if type(list) ~= "table" then return nil end

    MergeEntryLists(list, db.entries)
    db._sourceSpecID = sourceSpecID
    db.entries = {}

    if sourceSpecID == GetCurrentSpecID() then
        return list
    end
    return nil
end

-- Resolve the mutable entry list for a container. Honors specSpecific —
-- specSpecific containers mutate the current spec's private list instead
-- of the container's shared field.
local function GetMutableEntryList(db, containerKey, createIfMissing)
    if not db then return nil end
    if db.specSpecific then
        return GetSpecEntryList(containerKey, nil, createIfMissing)
    end
    local field = GetEntryListField(db)
    if createIfMissing and db[field] == nil then db[field] = {} end
    return db[field]
end

-- Public: read the entry list for a given spec (defaults to current).
-- Used by cdm_icons BuildIcons to render specSpecific containers.
function CDMSpellData:GetSpecEntries(containerKey, specKey)
    local list = GetSpecEntryList(containerKey, specKey, false)
    if type(list) == "table" then
        return list
    end

    local db = GetContainerDB(containerKey)
    if type(db) == "table" and db.specSpecific then
        return MoveLegacySpecEntriesToPerSpecStorage(containerKey, db)
    end
    return list
end

-- Composer fires this when the user flips the specSpecific toggle.
-- Enabling: seed the current spec with a clone of whatever was in the
-- container's shared list so the user doesn't lose their setup.
-- Disabling: fold the current spec's list back into the shared field
-- so the visible arrangement persists across the toggle.
function CDMSpellData:OnSpecSpecificToggled(containerKey)
    local db = GetContainerDB(containerKey)
    if not db then return end
    local field = GetEntryListField(db)
    if db.specSpecific then
        local specList = GetSpecEntryList(containerKey, nil, true)
        if specList and #specList == 0 and type(db[field]) == "table" and #db[field] > 0 then
            for i, e in ipairs(db[field]) do
                specList[i] = CloneEntry(e)
            end
        end
    else
        local specList = GetSpecEntryList(containerKey, nil, false)
        if specList and #specList > 0 then
            db[field] = {}
            for i, e in ipairs(specList) do
                db[field][i] = CloneEntry(e)
            end
        end
    end
    FireChangeCallback()
end

function CDMSpellData:AddEntry(containerKey, entry)
    if CombatGuard() then return false end
    if not ValidateEntry(entry) then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    local list = GetMutableEntryList(db, containerKey, true)
    if not list then return false end

    -- Stamp entry.kind on insert. Caller can pre-set entry.kind to
    -- override (e.g., Composer's Passives/Buffs tabs forcing aura).
    -- Falls through to the runtime classifier when nil.
    if entry.kind == nil then
        entry.kind = ResolveEntryKind(entry, containerKey)
    end

    -- Within-container dedup — prevent adding duplicates. customBar
    -- entries are already typed as {type,id}; ownedSpells may have the
    -- older {id=N} shape which NormalizeOwnedEntry handles.
    for _, existing in ipairs(list) do
        local norm = NormalizeOwnedEntry(existing)
        if norm and norm.type == entry.type and norm.id == entry.id then
            return false  -- already exists
        end
    end

    list[#list + 1] = entry
    FireChangeCallback()
    return true
end

function CDMSpellData:RemoveEntry(containerKey, index)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end
    local list = GetMutableEntryList(db, containerKey, false)
    if type(list) ~= "table" then return false end
    if index < 1 or index > #list then return false end

    local entry = list[index]
    table.remove(list, index)

    -- removedSpells bookkeeping applies only to ownedSpells-backed
    -- containers (for re-snapshot protection). customBar and spec-scoped
    -- lists have no snapshot concept.
    if not db.specSpecific and GetEntryListField(db) == "ownedSpells"
        and entry and entry.id then
        if not db.removedSpells then
            db.removedSpells = {}
        end
        db.removedSpells[entry.id] = true
    end

    FireChangeCallback()
    return true
end

function CDMSpellData:ReorderEntry(containerKey, fromIndex, toIndex)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end
    local list = GetMutableEntryList(db, containerKey, false)
    if type(list) ~= "table" then return false end

    local len = #list
    if fromIndex < 1 or fromIndex > len then return false end
    if toIndex < 1 then return false end
    if fromIndex == toIndex then return true end

    local entry = table.remove(list, fromIndex)
    local insertAt = math.min(toIndex, #list + 1)
    table.insert(list, insertAt, entry)

    FireChangeCallback()
    return true
end

function CDMSpellData:MoveEntryBetweenContainers(fromKey, toKey, index)
    if CombatGuard() then return false end

    local fromDB = GetContainerDB(fromKey)
    local toDB = GetContainerDB(toKey)
    if not fromDB or type(fromDB.ownedSpells) ~= "table" then return false end
    if not toDB then return false end
    if index < 1 or index > #fromDB.ownedSpells then return false end

    local entry = table.remove(fromDB.ownedSpells, index)

    if toDB.ownedSpells == nil then
        toDB.ownedSpells = {}
    end
    toDB.ownedSpells[#toDB.ownedSpells + 1] = entry

    FireChangeCallback()
    return true
end

function CDMSpellData:RestoreRemovedEntry(containerKey, spellID)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    -- Remove from removedSpells
    if db.removedSpells then
        db.removedSpells[spellID] = nil
    end

    -- Add back to ownedSpells. Reclassify kind via the runtime
    -- classifier — removedSpells only stored the spellID, so the
    -- original kind hint is gone.
    if db.ownedSpells == nil then
        db.ownedSpells = {}
    end
    local restored = { type = "spell", id = spellID }
    restored.kind = ResolveEntryKind(restored, containerKey)
    db.ownedSpells[#db.ownedSpells + 1] = restored

    FireChangeCallback()
    return true
end

function CDMSpellData:RestoreDormantEntry(containerKey, spellID)
    if CombatGuard() then return false end
    local db = GetContainerDB(containerKey)
    if not db then return false end
    if type(db.dormantSpells) ~= "table" then return false end
    local savedData = db.dormantSpells[spellID]
    if not savedData then return false end
    db.dormantSpells[spellID] = nil
    if db.ownedSpells == nil then db.ownedSpells = {} end
    -- Support both legacy (number) and new (table) dormant format
    local savedSlot, savedRow
    if type(savedData) == "table" then
        savedSlot = savedData.slot or 9999
        savedRow = savedData.row
    else
        savedSlot = savedData or 9999
    end
    local insertAt = math.min(savedSlot, #db.ownedSpells + 1)
    local restored = { type = "spell", id = spellID, row = savedRow }
    restored.kind = ResolveEntryKind(restored, containerKey)
    table.insert(db.ownedSpells, insertAt, restored)
    FireChangeCallback()
    return true
end

function CDMSpellData:RemoveDormantEntry(containerKey, spellID)
    if CombatGuard() then return false end
    local db = GetContainerDB(containerKey)
    if not db then return false end
    if type(db.dormantSpells) == "table" then
        db.dormantSpells[spellID] = nil
    end
    FireChangeCallback()
    return true
end

function CDMSpellData:IsSpellKnown(spellID)
    return IsSpellKnownByPlayer(spellID)
end

-- True if the spellID is registered in /cdm under the given container
-- family — "cooldown" checks cats 0+1 (essential/utility), "aura" /
-- "auraBar" check cats 2+3 (buff icon/buff bar). Used by the composer
-- to scope the "Not added to /cdm" warning: spells added via QUI's
-- non-CDM picker tabs (All Cooldowns, Other Auras, Active Buffs, Spell
-- ID, Items) often aren't in their target container family's /cdm cats,
-- so flagging them is a false positive. The check has to be family-
-- scoped because buff-cat entries pull their *source ability* spellID
-- via linkedSpellIDs (e.g. Death Strike's CD/base ability isn't in
-- /cdm cooldown cats, but DS appears as the ability behind Blood
-- Shield in cat 2/3) — a single combined "any category" check would
-- false-positive that case. Lazily builds the maps the same way
-- BuildSpellListFromOwned does.
function CDMSpellData:IsSpellInCDMCategory(spellID, family)
    local id = tonumber(spellID)
    if not id then return false end
    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end
    if family == "cooldown" then
        return _spellInCDMCooldowns[id] == true
    elseif family == "aura" or family == "auraBar" then
        return _spellInCDMAuras[id] == true
    end
    return _spellToCooldownID[id] ~= nil
end

function CDMSpellData:ResnapshotFromBlizzard(containerKey)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    -- Reset owned data to allow fresh snapshot
    db.ownedSpells = nil
    db.removedSpells = {}

    -- Re-snapshot from Blizzard viewers
    self:SnapshotBlizzardCDM(containerKey)

    FireChangeCallback()
    return true
end

-- Convenience wrappers. Optional `kind` arg overrides the runtime
-- classifier — pass it from the Composer when the picker tab dictates
-- (Passives/Buffs → aura; all_cooldowns/items → cooldown).
function CDMSpellData:AddSpell(containerKey, spellID, kind)
    return self:AddEntry(containerKey, { type = "spell", id = spellID, kind = kind })
end

function CDMSpellData:AddItem(containerKey, itemID)
    return self:AddEntry(containerKey, { type = "item", id = itemID, kind = "cooldown" })
end

function CDMSpellData:AddTrinketSlot(containerKey, slotID)
    return self:AddEntry(containerKey, { type = "slot", id = slotID, kind = "cooldown" })
end


function CDMSpellData:SetEntryRow(containerKey, index, rowNum)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db or type(db.ownedSpells) ~= "table" then return false end
    if index < 1 or index > #db.ownedSpells then return false end

    local entry = db.ownedSpells[index]
    if not entry then return false end

    entry.row = rowNum
    FireChangeCallback()
    return true
end

---------------------------------------------------------------------------
-- PER-SPELL OVERRIDE API
---------------------------------------------------------------------------

function CDMSpellData:SetSpellOverride(containerKey, spellID, key, value)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    if not db.spellOverrides then
        db.spellOverrides = {}
    end
    if not db.spellOverrides[spellID] then
        db.spellOverrides[spellID] = {}
    end

    db.spellOverrides[spellID][key] = value

    FireChangeCallback()
    return true
end

function CDMSpellData:ClearSpellOverride(containerKey, spellID, key)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db or not db.spellOverrides or not db.spellOverrides[spellID] then
        return false
    end

    db.spellOverrides[spellID][key] = nil

    -- Clean up empty override table
    if next(db.spellOverrides[spellID]) == nil then
        db.spellOverrides[spellID] = nil
    end

    FireChangeCallback()
    return true
end

function CDMSpellData:GetSpellOverride(containerKey, spellID)
    local db = GetContainerDB(containerKey)
    if not db or not db.spellOverrides then return nil end
    return db.spellOverrides[spellID]
end

---------------------------------------------------------------------------
-- ENUMERATION API
---------------------------------------------------------------------------

function CDMSpellData:GetAvailableSpells(containerKey)
    local db = GetContainerDB(containerKey)

    -- Build a set of already-owned spell IDs for fast lookup
    local ownedSet = {}
    if db and type(db.ownedSpells) == "table" then
        for _, entry in ipairs(db.ownedSpells) do
            local normalized = NormalizeOwnedEntry(entry)
            if normalized and normalized.type == "spell" and normalized.id then
                ownedSet[normalized.id] = true
                -- Also mark override spells as owned
                if C_Spell and C_Spell.GetOverrideSpell then
                    local okO, oid = pcall(C_Spell.GetOverrideSpell, normalized.id)
                    if okO and oid and oid ~= normalized.id then
                        ownedSet[oid] = true
                    end
                end
            end
        end
    end

    local available = {}
    local seen = {}

    -- Resolve container type: built-in containers may store containerType in
    -- ncdm.containers[key] (migration target) rather than ncdm[key] (user data).
    local containerType = db and db.containerType
    if not containerType then
        local ncdm = GetNcdmDB()
        if ncdm and ncdm.containers and ncdm.containers[containerKey] then
            containerType = ncdm.containers[containerKey].containerType
        end
    end
    local isAuraContainer = (containerType == "aura" or containerType == "auraBar")

    -- Query Blizzard CDM API with proper category parameters.
    -- Scan multiple categories per container (e.g. cooldown bars scan Essential + Utility).
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
       and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local categories = CDM_BAR_CATEGORIES[containerKey] or { 0, 1, 2, 3 }

        for _, category in ipairs(categories) do
            local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
            if ok and cooldownIDs then
                for _, cdID in ipairs(cooldownIDs) do
                    local okInfo, cdInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    if okInfo and cdInfo then
                        -- Use correction map if available, otherwise resolve from info.
                        -- For aura containers, prefer overrideTooltipSpellID when present —
                        -- it points to the actual tracked aura (e.g. Blood Plague 55078)
                        -- instead of the casting ability (e.g. Blood Boil 50842).
                        local sid = _cdIDToCorrectSID[cdID]
                        if not sid and isAuraContainer then
                            local tooltipSid = Helpers.SafeValue(cdInfo.overrideTooltipSpellID, nil)
                            if tooltipSid and tooltipSid > 0 then
                                sid = tooltipSid
                            end
                        end
                        if not sid then
                            -- Cooldown containers: use stable base spellID
                            -- so adding a spell stores the base, not the
                            -- volatile override. Same logic as snapshot.
                            if not isAuraContainer then
                                local baseSid3 = Helpers.SafeValue(cdInfo.spellID, nil)
                                if baseSid3 and baseSid3 > 0 then
                                    sid = baseSid3
                                else
                                    sid = ResolveInfoSpellID(cdInfo)
                                end
                            else
                                sid = ResolveInfoSpellID(cdInfo)
                            end
                        end
                        if sid and not seen[sid] then
                            seen[sid] = true
                            -- Mark both base and override as seen so they
                            -- don't both appear in the available list.
                            local baseSid2 = Helpers.SafeValue(cdInfo.spellID, nil)
                            if baseSid2 and baseSid2 ~= sid then
                                seen[baseSid2] = true
                            end
                            local ovSid2 = Helpers.SafeValue(cdInfo.overrideSpellID, nil)
                            if ovSid2 and ovSid2 ~= sid then
                                seen[ovSid2] = true
                            end

                            if not ownedSet[sid] then
                                -- Skip spells whose current override is already owned
                                -- (e.g., Divine Toll base when Holy Bulwark override
                                -- is already in the owned list).
                                local overrideOwned = false
                                if C_Spell and C_Spell.GetOverrideSpell then
                                    local okOv, ovSid = pcall(C_Spell.GetOverrideSpell, sid)
                                    if okOv and ovSid and ovSid ~= sid and ownedSet[ovSid] then
                                        overrideOwned = true
                                    end
                                end

                                if not overrideOwned then
                                    -- Show the current override name/icon in the
                                    -- picker so the user sees what they'll get,
                                    -- but store the base ID when they add it.
                                    local displaySid = sid
                                    if C_Spell and C_Spell.GetOverrideSpell then
                                        local okOv2, ovDisplay = pcall(C_Spell.GetOverrideSpell, sid)
                                        if okOv2 and ovDisplay and ovDisplay ~= sid then
                                            displaySid = ovDisplay
                                        end
                                    end
                                    local name, icon
                                    if C_Spell and C_Spell.GetSpellInfo then
                                        local okI, spellInfo = pcall(C_Spell.GetSpellInfo, displaySid)
                                        if okI and spellInfo then
                                            name = spellInfo.name
                                            icon = spellInfo.iconID
                                        end
                                    end

                                    available[#available + 1] = {
                                        spellID = sid,
                                        name = name or "",
                                        icon = icon or 0,
                                        isKnown = cdInfo.isKnown,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Also include spells from the scanned viewer data (fallback).
    -- For aura containers, apply correction map to resolve raw spellIDs
    -- (e.g. Death Strike 49998 → Coagulating Blood 463730).
    local scanList = spellLists[containerKey]
    if scanList and type(scanList) == "table" then
        for _, entry in ipairs(scanList) do
            local sid = entry.spellID
            if sid then
                -- Apply correction map for aura containers
                if isAuraContainer then
                    local cdID = _spellToCooldownID[sid]
                    if cdID and _cdIDToCorrectSID[cdID] then
                        sid = _cdIDToCorrectSID[cdID]
                    end
                end
                if not ownedSet[sid] and not seen[sid] then
                    seen[sid] = true
                    local name, icon = entry.name or "", 0
                    if C_Spell and C_Spell.GetSpellInfo then
                        local okI, spellInfo = pcall(C_Spell.GetSpellInfo, sid)
                        if okI and spellInfo then
                            name = spellInfo.name or name
                            icon = spellInfo.iconID or 0
                        end
                    end
                    available[#available + 1] = {
                        spellID = sid,
                        name = name,
                        icon = icon,
                    }
                end
            end
        end
    end

    return available
end

function CDMSpellData:GetAllLearnedCooldowns()
    -- Return cached results if valid
    if learnedCooldownsCache and not learnedCooldownsCacheDirty then
        return learnedCooldownsCache
    end

    local result = {}
    local seen = {}

    -- Iterate spell book using C_SpellBook APIs
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local okTabs, numTabs = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        if okTabs and numTabs then
            for tab = 1, numTabs do
                local okLine, skillLineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tab)
                if okLine and skillLineInfo and skillLineInfo.name ~= GENERAL then
                    local offset = skillLineInfo.itemIndexOffset or 0
                    local numEntries = skillLineInfo.numSpellBookItems or 0
                    for i = 1, numEntries do
                        local slotIndex = offset + i
                        local okItem, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, slotIndex, Enum.SpellBookSpellBank.Player)
                        if okItem and itemInfo and itemInfo.spellID and not itemInfo.isPassive and not itemInfo.isOffSpec then
                            local sid = itemInfo.spellID
                            if not seen[sid] then
                                seen[sid] = true
                                -- Check base cooldown (ms) for sorting/display
                                local baseCDms = 0
                                if C_Spell and C_Spell.GetSpellBaseCooldown then
                                    local okCD, ms = pcall(C_Spell.GetSpellBaseCooldown, sid)
                                    if okCD and ms then
                                        baseCDms = Helpers.SafeToNumber(ms, 0) or 0
                                    end
                                end
                                if baseCDms <= 1500 and C_Spell and C_Spell.GetSpellCharges then
                                    local okCh, ci = pcall(C_Spell.GetSpellCharges, sid)
                                    if okCh and ci then
                                        local maxC = Helpers.SafeToNumber(ci.maxCharges, 0) or 0
                                        if maxC > 1 then baseCDms = 2000 end
                                    end
                                end
                                local name, icon
                                if C_Spell and C_Spell.GetSpellInfo then
                                    local okI, spellInfo = pcall(C_Spell.GetSpellInfo, sid)
                                    if okI and spellInfo then
                                        name = spellInfo.name
                                        icon = spellInfo.iconID
                                    end
                                end
                                result[#result + 1] = {
                                    spellID = sid,
                                    name = name or "",
                                    icon = icon or 0,
                                    cooldown = baseCDms / 1000,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Append racial abilities — not included in Blizzard's CDM categories
    -- and may be missing from the spellbook scan (no specID on racial tab).
    do
        local _, raceFile = UnitRace("player")
        local _, classFile = UnitClass("player")
        local racials = raceFile and RACE_RACIALS[raceFile]
        if racials then
            for _, racialEntry in ipairs(racials) do
                local sid, classFilter
                if type(racialEntry) == "table" then
                    sid = racialEntry[1]
                    classFilter = racialEntry.class
                else
                    sid = racialEntry
                end
                if sid and not seen[sid] and (not classFilter or classFilter == classFile) then
                    seen[sid] = true
                    local rName, rIcon
                    if C_Spell and C_Spell.GetSpellInfo then
                        local okI, spellInfo = pcall(C_Spell.GetSpellInfo, sid)
                        if okI and spellInfo then
                            rName = spellInfo.name
                            rIcon = spellInfo.iconID
                        end
                    end
                    if rName then
                        local baseCDms = 0
                        if C_Spell and C_Spell.GetSpellBaseCooldown then
                            local okCD, ms = pcall(C_Spell.GetSpellBaseCooldown, sid)
                            if okCD and ms then
                                baseCDms = Helpers.SafeToNumber(ms, 0) or 0
                            end
                        end
                        result[#result + 1] = {
                            spellID = sid,
                            name = rName,
                            icon = rIcon or 0,
                            cooldown = baseCDms / 1000,
                        }
                    end
                end
            end
        end
    end

    learnedCooldownsCache = result
    learnedCooldownsCacheDirty = false
    return result
end

function CDMSpellData:GetActiveAuras(filter)
    local result = {}
    local seen = {}  -- dedupe by spellID: many buffs stack with multiple instances

    if not (AuraUtil and AuraUtil.ForEachAura) then return result end

    AuraUtil.ForEachAura("player", filter or "HELPFUL", nil, function(auraData)
        if not auraData then return false end
        local sid = Helpers.SafeValue(auraData.spellId, nil)
        if not sid or seen[sid] then return false end
        seen[sid] = true
        result[#result + 1] = {
            spellID = sid,
            name = Helpers.SafeValue(auraData.name, nil) or "",
            icon = Helpers.SafeValue(auraData.icon, nil) or 0,
            duration = Helpers.SafeToNumber(auraData.duration, 0) or 0,
        }
        return false
    end, true)  -- usePackedAura=true: callback receives an auraData table (not individual args)

    return result
end

---------------------------------------------------------------------------
-- GetPassiveAuras — returns passive spells from class/spec spellbook tabs
-- (skips General). These are talent-granted passives that may produce
-- visible player buffs trackable in aura containers.
---------------------------------------------------------------------------
function CDMSpellData:GetPassiveAuras()
    local result = {}
    local seen = {}

    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then
        return result
    end

    local okTabs, numTabs = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not okTabs or not numTabs then return result end

    for tab = 1, numTabs do
        local okLine, skillLineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tab)
        if okLine and skillLineInfo and skillLineInfo.name ~= GENERAL then
            local offset = skillLineInfo.itemIndexOffset or 0
            local numEntries = skillLineInfo.numSpellBookItems or 0
            for i = 1, numEntries do
                local slotIndex = offset + i
                local okItem, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, slotIndex, Enum.SpellBookSpellBank.Player)
                if okItem and itemInfo and itemInfo.spellID and itemInfo.isPassive and not itemInfo.isOffSpec then
                    local sid = itemInfo.spellID
                    if not seen[sid] then
                        seen[sid] = true
                        local name, icon
                        if C_Spell and C_Spell.GetSpellInfo then
                            local okI, spellInfo = pcall(C_Spell.GetSpellInfo, sid)
                            if okI and spellInfo then
                                name = spellInfo.name
                                icon = spellInfo.iconID
                            end
                        end
                        result[#result + 1] = {
                            spellID = sid,
                            name = name or "",
                            icon = icon or 0,
                        }
                    end
                end
            end
        end
    end

    return result
end

function CDMSpellData:GetUsableItems()
    local result = {}

    -- Scan equipped trinkets (slots 13 and 14)
    for _, slotID in ipairs({ 13, 14 }) do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local name, icon
            local okN, itemName = pcall(C_Item.GetItemNameByID, itemID)
            if okN then name = itemName end
            local okI, itemIcon = pcall(C_Item.GetItemIconByID, itemID)
            if okI then icon = itemIcon end

            -- Check if trinket has an on-use spell
            local hasSpell = false
            if C_Item and C_Item.GetItemSpell then
                local okS, spellName = pcall(C_Item.GetItemSpell, itemID)
                if okS and spellName then
                    hasSpell = true
                end
            end

            if hasSpell then
                result[#result + 1] = {
                    type = "slot",
                    id = slotID,
                    itemID = itemID,
                    name = name or "",
                    icon = icon or 0,
                    slotID = slotID,
                }
            end
        end
    end

    -- Scan bags for items with on-use spells
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            local okN, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
            if okN and numSlots then
                for slot = 1, numSlots do
                    local okC, containerInfo = pcall(C_Container.GetContainerItemInfo, bag, slot)
                    if okC and containerInfo and containerInfo.itemID then
                        local itemID = containerInfo.itemID
                        -- Check for on-use spell
                        if C_Item and C_Item.GetItemSpell then
                            local okS, spellName = pcall(C_Item.GetItemSpell, itemID)
                            if okS and spellName then
                                local name = containerInfo.itemName or ""
                                local icon = containerInfo.iconFileID or 0
                                result[#result + 1] = {
                                    type = "item",
                                    id = itemID,
                                    itemID = itemID,
                                    name = name,
                                    icon = icon,
                                    slotID = nil,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end


---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

-- GetSpellList: Routing function — owned path if snapshotted, scan fallback
function CDMSpellData:GetSpellList(viewerType)
    local db = GetContainerDB(viewerType)
    local hasOwned = db and db.ownedSpells ~= nil
    if hasOwned then
        -- Owned path: build from DB
        local result = self:BuildSpellListFromOwned(viewerType)
        return result
    end
    -- Fallback: existing scan-based approach (backward compat)
    -- Custom containers with no ownedSpells yet return empty
    if not VIEWER_NAMES[viewerType] then
        return {}
    end
    local list = spellLists[viewerType] or {}
    return list
end

function CDMSpellData:ForceScan()
    -- Scan all three viewers synchronously but do NOT fire QUI_OnSpellDataChanged.
    -- This prevents a feedback loop: RefreshAll → ForceScan → changed → callback → RefreshAll.
    -- Update fingerprints so the periodic ScanAll ticker won't re-detect the same change.
    if InCombatLockdown() and not ns._inInitSafeWindow then
        return
    end
    ScanViewer("essential")
    ScanViewer("utility")
    ScanViewer("buff")
    for viewerType, list in pairs(spellLists) do
        lastSpellFingerprints[viewerType] = ComputeSpellFingerprint(list)
    end
end


function CDMSpellData:UpdateCVar()
    UpdateCooldownViewerCVar()
end

function CDMSpellData:InvalidateLearnedCache()
    InvalidateLearnedCooldownsCache()
end

-- Wipe per-batch resolve memos. Normally cleared once per batch in
-- BuildSpellListFromOwned; exposed for the /qui cdm_cache reset path.
function CDMSpellData:ClearResolveMemos()
    wipe(_resolveIconMemo)
    wipe(_resolveAuraActiveMemo)
end

-- Aggressive reset: nuke per-child caches stamped on Blizzard viewer
-- children (cooldown info + resolved IDs). They self-refresh on next
-- read, so the only effect is a one-shot rebuild cost.
function CDMSpellData:ClearChildCaches()
    local viewerNames = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
        "BuffBarCooldownViewer",
    }
    for _, vname in ipairs(viewerNames) do
        local viewer = _G[vname]
        if viewer and viewer.GetChildren then
            local ok, kids = pcall(function() return { viewer:GetChildren() } end)
            if ok and kids then
                for i = 1, #kids do
                    local ch = kids[i]
                    if ch then
                        ch._cachedCdInfo = nil
                        ch._cachedCdInfoID = nil
                        ch._resolvedIDs = nil
                        ch._resolvedKey = nil
                    end
                end
            end
        end
    end
    -- Per-child totem slot resolution map keyed by Blizzard child frame.
    if _blizzChildToTotemSlot then
        wipe(_blizzChildToTotemSlot)
    end
end

-- Aggregate cache stats for /qui cdm_cache status.
function CDMSpellData:GetCacheStats()
    local function size(t)
        if type(t) ~= "table" then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
    local learnedSize = 0
    if type(learnedCooldownsCache) == "table" then
        learnedSize = #learnedCooldownsCache
    end
    return {
        childMapDirty       = _childMapDirty and true or false,
        childMapSize        = size(_childBySpellID),
        learnedDirty        = learnedCooldownsCacheDirty and true or false,
        learnedSize         = learnedSize,
        tickAuraData        = size(_tickAuraDataCache),
        tickAuraDuration    = size(_tickAuraDurationCache),
        tickAuraExpiration  = size(_tickAuraExpirationCache),
        tickAuraApplication = size(_tickAuraApplicationCache),
        resolveIconMemo     = size(_resolveIconMemo),
        resolveAuraMemo     = size(_resolveAuraActiveMemo),
        totemSlotMap        = size(_blizzChildToTotemSlot),
    }
end


---------------------------------------------------------------------------
-- EDIT MODE INTEGRATION
-- Show Blizzard viewers during Edit Mode, hide them when exiting.
---------------------------------------------------------------------------
local function RegisterEditModeCallbacks()
    local QUICore = ns.Addon
    if not QUICore then return end

    if QUICore.RegisterEditModeEnter then
        QUICore:RegisterEditModeEnter(function()
            -- Blizzard viewers stay at alpha 0 — QUI containers + overlays
            -- handle all display during Edit Mode. Zero Blizzard frame writes.
            if _G.QUI_OnEditModeEnterCDM then
                _G.QUI_OnEditModeEnterCDM()
            end
        end)
    end

    if QUICore.RegisterEditModeExit then
        QUICore:RegisterEditModeExit(function()
            -- Save QUI container positions, rebuild layout.
            if _G.QUI_OnEditModeExitCDM then
                _G.QUI_OnEditModeExitCDM()
            end
            -- Rescan after Edit Mode (Blizzard may have changed settings)
            C_Timer.After(0.3, ScanAll)
        end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZE: Called by cdm_containers.lua Initialize() to bootstrap
-- spell data scanning. Replaces the self-bootstrapping event frame.
---------------------------------------------------------------------------
function CDMSpellData:Initialize()
    -- Hide Blizzard viewers IMMEDIATELY to prevent flash of unstyled buff
    -- icons during the ~0.5s window before the deferred init completes.
    HideBlizzardViewers()
    ForceLoadCDM()
    -- Immediate scan: succeeds during /reload when viewers are already
    -- populated. At ADDON_LOADED the safe window allows this even on
    -- combat reload while InCombatLockdown() still reports true.
    ScanAll()
    -- Deferred re-scan: handles first login where viewers populate after us.
    C_Timer.After(0.5, function()
        UpdateCooldownViewerCVar()
        HideBlizzardViewers()  -- re-apply in case ForceLoadCDM restored them
        ScanAll()
        RegisterEditModeCallbacks()
        HookBlizzardSettings()
        initialized = true
        -- Initial reconciliation after scan data is available
        if not InCombatLockdown() then
            CDMSpellData:ReconcileAllContainers()
        end
        -- Start periodic scan (out of combat only, 0.5s base interval).
        -- Backs off to every 2s after 3s of no changes to reduce idle CPU.
        if not scanTimer then
            local scanIdleCount = 0
            local scanSkipCount = 0
            scanTimer = C_Timer.NewTicker(0.5, function()
                if InCombatLockdown() then return end
                -- After 6 idle scans (3s of no changes), relax to every 4th tick (2s effective)
                if scanIdleCount >= 6 then
                    scanSkipCount = scanSkipCount + 1
                    if scanSkipCount < 4 then return end
                    scanSkipCount = 0
                end
                local changed = ScanAll()
                if changed then
                    scanIdleCount = 0
                    scanSkipCount = 0
                else
                    scanIdleCount = scanIdleCount + 1
                end
            end)
        end
    end)
    -- Register runtime events
    local _spellsChangedToken = 0
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- 12.0.5: auraInstanceID values re-randomize on encounter/M+/PvP start,
    -- so the auraInstanceID-keyed tick caches must be evicted to avoid stale
    -- negative entries masking newly-applied auras.
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("PVP_MATCH_ACTIVE")
    eventFrame:SetScript("OnEvent", function(self, event, arg)
        if event == "SPELL_UPDATE_COOLDOWN" then
            -- No-op: ScanAll runs on its own 0.5s ticker (line 3178).
            -- Calling it here on every SPELL_UPDATE_COOLDOWN was redundant —
            -- this event fires every GCD tick (dozens of times per second OOC).
            -- CDM icon/bar updates are driven by ScheduleCDMUpdate in cdm_icons,
            -- which coalesces via C_Timer; the scan ticker catches viewer child
            -- changes with acceptable latency.
            do end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Spec change is coordinated by cdm_containers.lua which calls
            -- CheckAllDormantSpells / ReconcileAllContainers at the right time
            -- (after loading the new spec profile). Only invalidate the
            -- learned cooldowns cache here so stale data is not returned.
            InvalidateLearnedCooldownsCache()
        elseif event == "SPELLS_CHANGED" then
            -- Talent/spell changes: update dormant spell lists and invalidate cache.
            -- Cache invalidation is immediate so stale data is never returned.
            InvalidateLearnedCooldownsCache()
            -- Skip dormant checks during zone transitions — WoW APIs
            -- (IsSpellKnown, IsPlayerSpell, CDM viewer) are temporarily
            -- stale after PLAYER_ENTERING_WORLD, causing override spells
            -- (e.g. Ice Cold 414658 replacing Ice Block 45438) to be
            -- incorrectly marked dormant. Dedicated handlers for
            -- CHALLENGE_MODE_START and PLAYER_ENTERING_WORLD already run
            -- dormant checks with better timing once APIs stabilise.
            if _inZoneTransition then
                return
            end
            -- Debounce dormant/reconcile — SPELLS_CHANGED fires multiple times
            -- during talent swaps; collapse into a single deferred rebuild.
            _spellsChangedToken = _spellsChangedToken + 1
            local token = _spellsChangedToken
            C_Timer.After(0.3, function()
                if token ~= _spellsChangedToken then
                    return
                end
                if not InCombatLockdown() then
                    CDMSpellData:CheckAllDormantSpells()
                    CDMSpellData:ReconcileAllContainers()
                    -- Notify containers to refresh display after dormant cleanup
                    -- removed stale spells from ownedSpells.
                    FireChangeCallback()
                else
                end
            end)
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            -- Trinket changes: reconcile to pick up new trinket slots
            if not InCombatLockdown() then
                CDMSpellData:ReconcileAllContainers()
            end
        elseif event == "ENCOUNTER_START" or event == "CHALLENGE_MODE_START" or event == "PVP_MATCH_ACTIVE" then
            -- Blizzard re-randomizes auraInstanceID values on these events
            -- (12.0.5+). Wipe the auraInstanceID-keyed tick caches so old
            -- negative entries (`false`) don't mask newly-applied auras that
            -- happen to land on a previously-seen ID.
            ClearTickAuraCache()
            -- Rescan captured auras with the new (post-randomization) IDs.
            -- Without this, auras already applied at encounter start (e.g.
            -- pre-pull buffs) keep their stale IDs in the cache or stay
            -- absent entirely.
            RescanCapturedAurasForUnit("player")
            RescanCapturedAurasForUnit("pet")
        elseif event == "PLAYER_REGEN_ENABLED" then
            ClearTickAuraCache()
            -- OOC rescan: ForEachAura returns clean auraInstanceIDs with no
            -- restricted-scope redaction, so this is the most reliable
            -- moment to refresh the capture cache.
            RescanCapturedAurasForUnit("player")
            RescanCapturedAurasForUnit("pet")
        elseif event == "PLAYER_ENTERING_WORLD" then
            ClearTickAuraCache()
            ClearCapturedAuras()
            -- Suppress SPELLS_CHANGED dormant checks during zone transitions.
            -- APIs are stale for ~1-2s after entering a new zone/instance.
            _inZoneTransition = true
            C_Timer.After(2.0, function() _inZoneTransition = false end)
            -- Hide viewers immediately to prevent flash of unstyled icons
            HideBlizzardViewers()
            C_Timer.After(1.0, function()
                if not initialized then
                    -- Blizzard_CooldownManager may have loaded before us
                    ForceLoadCDM()
                    C_Timer.After(0.5, function()
                        UpdateCooldownViewerCVar()
                        HideBlizzardViewers()
                        ScanAll()
                        RegisterEditModeCallbacks()
                        HookBlizzardSettings()
                        initialized = true
                    end)
                else
                    HideBlizzardViewers()
                    ScanAll()
                end
            end)
        end
    end)
end

--- Find a viewer child for a spell ID via the OOC-built _spellIDToChild map.
--- Returns the first matching child with a non-nil auraInstanceID, or nil.
function CDMSpellData:FindChildForSpellID(spellID)
    if not spellID then return nil end
    local children = _spellIDToChild[spellID]
    if not children then return nil end
    for _, child in ipairs(children) do
        if child.auraInstanceID ~= nil then
            local ids = child._resolvedIDs
            if ids then
                for k = 1, #ids do
                    if ids[k] == spellID then return child end
                end
            else
                return child
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- DEBUG: /cdmdump <name> — dump all viewer children matching <name>.
-- Prints spellID, overrideSpellID, iconFileID, wasSetFromAura, shown,
-- auraInstanceID, and viewer type for each match.
---------------------------------------------------------------------------
SLASH_QUI_CDMDUMP1 = "/cdmdump"
SlashCmdList["QUI_CDMDUMP"] = function(msg)
    local filter = msg and strtrim(msg):lower() or ""
    if filter == "" then
        print("|cff34D399[CDM-Dump]|r Usage: /cdmdump <name or spellID>")
        return
    end
    local filterNum = tonumber(filter)
    local viewers = {
        { name = "EssentialCooldownViewer", type = "ess"  },
        { name = "UtilityCooldownViewer",   type = "util" },
        { name = "BuffIconCooldownViewer",  type = "icon" },
        { name = "BuffBarCooldownViewer",   type = "bar"  },
    }
    local found = 0
    local seenChildren = {}
    for _, v in ipairs(viewers) do
        local viewer = _G[v.name]
        if viewer then
            local allChildren = {}
            local numChildren = viewer:GetNumChildren()
            for i = 1, numChildren do
                local ch = select(i, viewer:GetChildren())
                if ch and not seenChildren[ch] then
                    seenChildren[ch] = true
                    allChildren[#allChildren + 1] = { ch, "GetChildren", i }
                end
            end
            if viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
                local idx = 0
                for ch in viewer.itemFramePool:EnumerateActive() do
                    idx = idx + 1
                    if ch and not seenChildren[ch] then
                        seenChildren[ch] = true
                        allChildren[#allChildren + 1] = { ch, "PoolActive", idx }
                    end
                end
            end
            for _, rec in ipairs(allChildren) do
                local child, source, i = rec[1], rec[2], rec[3]
                if child then
                    local ci = child.cooldownInfo
                    local childName = ci and Helpers.SafeValue(ci.name, nil)
                    local childSid = ci and Helpers.SafeValue(ci.spellID, nil)
                    local childOv = ci and Helpers.SafeValue(ci.overrideSpellID, nil)
                    -- Match by name substring OR by spell ID
                    local match = false
                    if filterNum then
                        match = (childSid == filterNum) or (childOv == filterNum)
                    end
                    if not match and childName and childName:lower():find(filter, 1, true) then
                        match = true
                    end
                    if match then
                        found = found + 1
                        local sid = Helpers.SafeValue(ci.spellID, "secret")
                        local ov = Helpers.SafeValue(ci.overrideSpellID, "secret")
                        local iconFile = Helpers.SafeValue(ci.iconFileID, "secret")
                        local wasAura = ci.wasSetFromAura
                        local useAuraTime = ci.cooldownUseAuraDisplayTime
                        local shown = pcall(child.IsShown, child) and child:IsShown()
                        local auraInstID = child.auraInstanceID
                            and Helpers.SafeValue(child.auraInstanceID, "secret") or "nil"
                        local auraUnit = child.auraDataUnit or "nil"
                        local cooldownID = ci.cooldownID
                            and Helpers.SafeValue(ci.cooldownID, "secret") or "nil"
                        local totemSlot = child.totemSlot
                            and Helpers.SafeValue(child.totemSlot, "secret") or "nil"
                        local layoutIdx = child.layoutIndex
                            and Helpers.SafeValue(child.layoutIndex, "secret") or "nil"
                        print("|cff34D399[CDM-Dump]|r", v.type, source .. "#" .. i, childName)
                        print("  spellID=", sid, "overrideSpellID=", ov)
                        print("  iconFileID=", iconFile, "cooldownID=", cooldownID)
                        print("  totemSlot=", totemSlot, "layoutIndex=", layoutIdx)
                        print("  wasSetFromAura=", tostring(wasAura),
                              "useAuraDisplayTime=", tostring(useAuraTime))
                        print("  shown=", tostring(shown),
                              "auraInstanceID=", auraInstID,
                              "auraDataUnit=", auraUnit)
                        -- Dump child methods that reveal spell identity
                        if child.GetSpellID then
                            local ok, gsid = pcall(child.GetSpellID, child)
                            print("  GetSpellID()=", ok and Helpers.SafeValue(gsid, "secret") or "err")
                        end
                        if child.GetAuraSpellID then
                            local ok, asid = pcall(child.GetAuraSpellID, child)
                            print("  GetAuraSpellID()=", ok and Helpers.SafeValue(asid, "secret") or "err")
                        end
                        -- Dump actual icon texture from the child's Icon region
                        local iconRegion = child.Icon or child.icon
                        if iconRegion then
                            local nested = iconRegion.Icon or iconRegion.icon
                            local texRegion = (nested and nested.GetTexture) and nested or iconRegion
                            if texRegion and texRegion.GetTexture then
                                local tok, tex = pcall(texRegion.GetTexture, texRegion)
                                print("  Icon texture=", tok and tex or "err")
                            end
                        end
                        -- Dump all cooldownInfo keys for full visibility
                        print("  cooldownInfo keys:")
                        for k, val in pairs(ci) do
                            if k == "linkedSpellIDs" and type(val) == "table" then
                                local ids = {}
                                for li, lv in ipairs(val) do
                                    ids[li] = tostring(Helpers.SafeValue(lv, "secret"))
                                end
                                print("    ", k, "= {", table.concat(ids, ", "), "}")
                            else
                                local safe = Helpers.SafeValue(val, "secret")
                                print("    ", k, "=", tostring(safe))
                            end
                        end
                    end
                end
            end
        end
    end
    if found == 0 then
        print("|cff34D399[CDM-Dump]|r No viewer children matching '" .. msg .. "'")
    else
        print("|cff34D399[CDM-Dump]|r", found, "children found")
    end
    if filterNum then
        RebuildChildMap()
        local list = _childBySpellID[filterNum]
        local n = list and #list or 0
        print("|cff34D399[CDM-Dump]|r _childBySpellID[" .. filterNum .. "] =",
            n, "entr" .. (n == 1 and "y" or "ies"))
        if list then
            for i, ch in ipairs(list) do
                local parent = ch:GetParent()
                local pname = parent and parent:GetName() or "nil"
                local cdID = ch.cooldownID or "nil"
                local totSlot = ch.totemSlot and Helpers.SafeValue(ch.totemSlot, "secret") or "nil"
                print("  [" .. i .. "] parent=", pname,
                    "cooldownID=", cdID, "totemSlot=", totSlot)
            end
        end
    end
end

---------------------------------------------------------------------------
-- DEBUG: /cdmdumpall [viewer] — dump every child from a viewer, plus
-- GetTotemInfo per slot. Taint-light variant: reads only safe frame
-- methods (GetName/GetObjectType/GetID) and rawget on non-secret keys
-- (layoutIndex, cooldownID). Does NOT access cooldownInfo, totemData, or
-- call Get* accessor methods on Blizzard viewer children (those return
-- secret values and poison Blizzard's own CDM state).
-- viewer: ess | util | icon | bar | all (default: all)
---------------------------------------------------------------------------
SLASH_QUI_CDMDUMPALL1 = "/cdmdumpall"
SlashCmdList["QUI_CDMDUMPALL"] = function(msg)
    local which = (msg and strtrim(msg):lower()) or "all"
    if which == "" then which = "all" end
    local map = {
        ess  = { "EssentialCooldownViewer" },
        util = { "UtilityCooldownViewer" },
        icon = { "BuffIconCooldownViewer" },
        bar  = { "BuffBarCooldownViewer" },
        all  = { "EssentialCooldownViewer", "UtilityCooldownViewer",
                 "BuffIconCooldownViewer", "BuffBarCooldownViewer" },
    }
    local names = map[which]
    if not names then
        print("|cff34D399[CDM-DumpAll]|r Usage: /cdmdumpall [ess|util|icon|bar|all]")
        return
    end
    for _, vname in ipairs(names) do
        local viewer = _G[vname]
        if not viewer then
            print("|cff34D399[CDM-DumpAll]|r", vname, "not found")
        else
            local seen = {}
            local rows = {}
            local numChildren = viewer:GetNumChildren()
            for i = 1, numChildren do
                local ch = select(i, viewer:GetChildren())
                if ch and not seen[ch] then
                    seen[ch] = true
                    rows[#rows+1] = { ch, "GC", i }
                end
            end
            -- Enumerate the Blizzard item pool too — totem-spawned bars often
            -- live here rather than among the template GetChildren set.
            local poolCount = 0
            if rawget(viewer, "itemFramePool") then
                local pool = rawget(viewer, "itemFramePool")
                if pool and pool.EnumerateActive then
                    local idx = 0
                    for ch in pool:EnumerateActive() do
                        idx = idx + 1
                        poolCount = poolCount + 1
                        if ch and not seen[ch] then
                            seen[ch] = true
                            rows[#rows+1] = { ch, "Pool", idx }
                        end
                    end
                end
            end
            -- Also peek at the pandemic icon pool (some effect buffs/totems may use it).
            local pandemicCount = 0
            if rawget(viewer, "pandemicIconPool") then
                local pool = rawget(viewer, "pandemicIconPool")
                if pool and pool.EnumerateActive then
                    local idx = 0
                    for ch in pool:EnumerateActive() do
                        idx = idx + 1
                        pandemicCount = pandemicCount + 1
                        if ch and not seen[ch] then
                            seen[ch] = true
                            rows[#rows+1] = { ch, "Pand", idx }
                        end
                    end
                end
            end
            print(string.format(
                "|cff34D399[CDM-DumpAll]|r %s — %d total (GC=%d Pool=%d Pand=%d)",
                vname, #rows, numChildren, poolCount, pandemicCount))
            for _, rec in ipairs(rows) do
                local ch, src, i = rec[1], rec[2], rec[3]
                -- Safe: basic frame methods + rawget on shallow non-secret keys.
                local otype = ch.GetObjectType and ch:GetObjectType() or "?"
                local fname = ch.GetName and ch:GetName() or "?"
                local fid = ch.GetID and ch:GetID() or "?"
                local lidx = rawget(ch, "layoutIndex")
                local cdID = rawget(ch, "cooldownID")
                local hasTotemData = rawget(ch, "totemData") ~= nil
                local prefSlot = rawget(ch, "preferredTotemUpdateSlot")
                local shown = ch.IsShown and ch:IsShown()
                local w = ch.GetWidth and ch:GetWidth() or 0
                local h = ch.GetHeight and ch:GetHeight() or 0
                local alpha = ch.GetAlpha and ch:GetAlpha() or 0
                print(string.format(
                    "  [%s#%d] %s name=%s id=%s lidx=%s cdID=%s totemData=%s prefSlot=%s shown=%s size=%.0fx%.0f alpha=%.2f",
                    src, i, tostring(otype), tostring(fname), tostring(fid),
                    tostring(Helpers.SafeValue(lidx, "secret")),
                    tostring(Helpers.SafeValue(cdID, "secret")),
                    tostring(hasTotemData),
                    tostring(Helpers.SafeValue(prefSlot, "secret")),
                    tostring(shown), w, h, alpha))
            end
        end
    end
    -- Per-slot GetTotemInfo dump (non-viewer-child path; low taint risk).
    local numSlots = Helpers.SafeValue(
        (GetNumTotemSlots and GetNumTotemSlots()) or 5, 5)
    for slot = 1, numSlots do
        local r1, r2, r3, r4, r5, r6, r7, r8 = GetTotemInfo(slot)
        local safeHas = Helpers.SafeValue(r1, false)
        if safeHas == true then
            print(string.format(
                "|cff34D399[CDM-DumpAll]|r TotemSlot[%d] r1=%s r2=%s r3=%s r4=%s r5=%s r6=%s r7=%s r8=%s",
                slot,
                tostring(Helpers.SafeValue(r1, "secret")),
                tostring(Helpers.SafeValue(r2, "secret")),
                tostring(Helpers.SafeValue(r3, "secret")),
                tostring(Helpers.SafeValue(r4, "secret")),
                tostring(Helpers.SafeValue(r5, "secret")),
                tostring(Helpers.SafeValue(r6, "secret")),
                tostring(Helpers.SafeValue(r7, "secret")),
                tostring(Helpers.SafeValue(r8, "secret"))))
        end
    end
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
CDMSpellData._spellIDToChild = _spellIDToChild
CDMSpellData._abilityToAuraSpellID = _abilityToAuraSpellID
CDMSpellData.ResolveEntryKind = ResolveEntryKind
CDMSpellData.IsAuraEntry = IsAuraEntry

--- Resolve the live spell ID from a Blizzard viewer child, falling back to
--- entry IDs.  Used by both icons (tooltips) and bars (name text) so that
--- talent replacements like Berserk → Incarnation display correctly.
--- @param entry table  The resolved owned-spell entry.
--- @param blizzChildOverride frame|nil  Optional explicit child (e.g. bar._blizzIconChild).
--- @return number|nil spellID  The current spell ID, or nil.
function CDMSpellData:ResolveDisplaySpellID(entry, blizzChildOverride)
    local child = blizzChildOverride or (entry and entry._blizzChild)
    if child and child.GetSpellID then
        local ok, childSid = pcall(child.GetSpellID, child)
        -- childSid may be a secret value in combat — skip numeric comparison,
        -- callers pass it to C-side functions that handle secrets natively.
        if ok and childSid then return childSid end
    end
    return entry and (entry.overrideSpellID or entry.spellID or entry.id)
end

--- Resolve the display name for an entry, using the live viewer child spell
--- for aura entries (talent replacements) and falling back to entry.name.
--- @param entry table  The resolved owned-spell entry.
--- @param blizzChildOverride frame|nil  Optional explicit child.
--- @return string name
function CDMSpellData:ResolveDisplayName(entry, blizzChildOverride)
    if entry and entry.isAura then
        local sid = self:ResolveDisplaySpellID(entry, blizzChildOverride)
        if sid then
            -- C_Spell.GetSpellInfo and FontString:SetText are both C-side
            -- and handle secret values natively.
            local ok, info = pcall(C_Spell.GetSpellInfo, sid)
            if ok and info and info.name then return info.name end
        end
    end
    return (entry and entry.name) or ""
end

---------------------------------------------------------------------------
-- DEBUG: /cdmprofiles — dump _specProfiles contents and current spec state.
---------------------------------------------------------------------------
SLASH_QUI_CDMPROFILES1 = "/cdmprofiles"
SlashCmdList["QUI_CDMPROFILES"] = function()
    local P = "|cff34D399[CDM-Profiles]|r"
    local db = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    if not db then
        print(P, "No ncdm database found.")
        return
    end

    local currentSpecID = GetSpecialization and GetSpecializationInfo(GetSpecialization()) or "?"
    print(P, "Current spec ID:", currentSpecID)
    print(P, "_lastSpecID:", db._lastSpecID or "nil")

    local profiles = db._specProfiles
    if not profiles or not next(profiles) then
        print(P, "_specProfiles: empty/nil")
        return
    end

    for specID, specData in pairs(profiles) do
        local label = specID
        -- Try to get spec name for readability
        if GetSpecializationInfoByID then
            local _, name, _, _, role = GetSpecializationInfoByID(specID)
            if name then label = specID .. " (" .. name .. ")" end
        end
        local containerCount = 0
        local totalSpells = 0
        for key, cData in pairs(specData) do
            if type(cData) == "table" and cData.ownedSpells then
                containerCount = containerCount + 1
                local count = type(cData.ownedSpells) == "table" and #cData.ownedSpells or 0
                totalSpells = totalSpells + count
                -- Print first few spell names/IDs
                local spellNames = {}
                if type(cData.ownedSpells) == "table" then
                    for i = 1, math.min(5, #cData.ownedSpells) do
                        local entry = cData.ownedSpells[i]
                        if entry and entry.id then
                            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.id)
                            spellNames[#spellNames + 1] = (name or "?") .. "(" .. entry.id .. ")"
                        end
                    end
                end
                local dormantCount = 0
                if type(cData.dormantSpells) == "table" then
                    for _ in pairs(cData.dormantSpells) do dormantCount = dormantCount + 1 end
                end
                local removedCount = 0
                if type(cData.removedSpells) == "table" then
                    for _ in pairs(cData.removedSpells) do removedCount = removedCount + 1 end
                end
                print(P, "  " .. key .. ":", count, "owned,", dormantCount, "dormant,", removedCount, "removed")
                if #spellNames > 0 then
                    local suffix = count > 5 and (" +" .. (count - 5) .. " more") or ""
                    print(P, "    ", table.concat(spellNames, ", ") .. suffix)
                end
            end
        end
        print(P, label .. ":", containerCount, "containers,", totalSpells, "total spells")
    end
end

---------------------------------------------------------------------------
-- DEBUG: /cdmclean — purge cross-class spell corruption from _specProfiles.
-- For each spec belonging to the current character's class, removes spells
-- that IsSpellKnownByPlayer says aren't learned (cross-class contamination).
-- Specs belonging to other classes are left untouched — run the command on
-- each character to clean their own specs.
---------------------------------------------------------------------------
SLASH_QUI_CDMCLEAN1 = "/cdmclean"
SlashCmdList["QUI_CDMCLEAN"] = function()
    local P = "|cff34D399[CDM-Clean]|r"

    if InCombatLockdown() then
        print(P, "Cannot clean during combat.")
        return
    end

    local db = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    if not db or not db._specProfiles then
        print(P, "No spec profiles to clean.")
        return
    end

    local _, playerClass = UnitClass("player")
    if not playerClass then
        print(P, "Could not determine player class.")
        return
    end

    -- Build set of all spells the current character knows (any spec)
    -- by querying the CDM API + spellbook for comprehensive coverage.
    local knownSpells = {}
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
       and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        for cat = 0, 3 do
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
            if ok and ids then
                for _, cdID in ipairs(ids) do
                    local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                    if okI and info then
                        local sid = Helpers.SafeValue(info.spellID, nil)
                        if sid then knownSpells[sid] = true end
                        local ov = Helpers.SafeValue(info.overrideSpellID, nil)
                        if ov then knownSpells[ov] = true end
                    end
                end
            end
        end
    end
    -- Also include spellbook spells
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local okT, numTabs = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        if okT and numTabs then
            for tab = 1, numTabs do
                local okL, sli = pcall(C_SpellBook.GetSpellBookSkillLineInfo, tab)
                if okL and sli then
                    local offset = sli.itemIndexOffset or 0
                    for i = 1, (sli.numSpellBookItems or 0) do
                        local okI, ii = pcall(C_SpellBook.GetSpellBookItemInfo, offset + i, Enum.SpellBookSpellBank.Player)
                        if okI and ii and ii.spellID then knownSpells[ii.spellID] = true end
                    end
                end
            end
        end
    end

    local totalCleaned = 0
    local profilesChecked = 0

    for specID, specData in pairs(db._specProfiles) do
        local specLabel = tostring(specID)
        local specClass
        if GetSpecializationInfoByID then
            local _, specName, _, _, _, classFile = GetSpecializationInfoByID(specID)
            if specName then specLabel = specID .. " (" .. specName .. ")" end
            specClass = classFile
        end

        if specClass == playerClass then
            -- This spec belongs to our class — surgically remove foreign spells
            profilesChecked = profilesChecked + 1
            local specCleaned = 0
            for containerKey, cData in pairs(specData) do
                if type(cData) == "table" and type(cData.ownedSpells) == "table" then
                    local cleaned = {}
                    local removed = 0
                    for _, entry in ipairs(cData.ownedSpells) do
                        if entry and entry.id and entry.type == "spell" then
                            if knownSpells[entry.id] or IsSpellKnownByPlayer(entry.id) then
                                cleaned[#cleaned + 1] = entry
                            else
                                removed = removed + 1
                                local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.id) or "?"
                                print(P, "  Removed", spellName .. "(" .. entry.id .. ") from", specLabel, containerKey)
                            end
                        else
                            -- Keep non-spell entries (macros, items) as-is
                            cleaned[#cleaned + 1] = entry
                        end
                    end
                    if removed > 0 then
                        cData.ownedSpells = cleaned
                        specCleaned = specCleaned + removed
                    end
                    -- Also clean dormantSpells of foreign entries
                    if type(cData.dormantSpells) == "table" then
                        for sid in pairs(cData.dormantSpells) do
                            if type(sid) == "number" and not knownSpells[sid] and not IsSpellKnownByPlayer(sid) then
                                cData.dormantSpells[sid] = nil
                                specCleaned = specCleaned + 1
                            end
                        end
                    end
                end
            end
            if specCleaned > 0 then
                totalCleaned = totalCleaned + specCleaned
                print(P, specLabel .. ": cleaned", specCleaned, "foreign spells")
            else
                print(P, specLabel .. ": clean")
            end
        elseif specClass and specClass ~= playerClass then
            -- Different class — surgically remove any of OUR spells that
            -- leaked into their profile, preserving their legitimate spells.
            local specCleaned = 0
            for containerKey, cData in pairs(specData) do
                if type(cData) == "table" and type(cData.ownedSpells) == "table" then
                    local cleaned = {}
                    local removed = 0
                    for _, entry in ipairs(cData.ownedSpells) do
                        if entry and entry.id and entry.type == "spell"
                           and (knownSpells[entry.id] or IsSpellKnownByPlayer(entry.id)) then
                            -- This spell belongs to US, not to that class
                            removed = removed + 1
                            local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.id) or "?"
                            print(P, "  Removed", spellName .. "(" .. entry.id .. ") from", specLabel, containerKey)
                        else
                            cleaned[#cleaned + 1] = entry
                        end
                    end
                    if removed > 0 then
                        cData.ownedSpells = cleaned
                        specCleaned = specCleaned + removed
                    end
                    -- Also clean dormantSpells
                    if type(cData.dormantSpells) == "table" then
                        for sid in pairs(cData.dormantSpells) do
                            if type(sid) == "number" and (knownSpells[sid] or IsSpellKnownByPlayer(sid)) then
                                cData.dormantSpells[sid] = nil
                                specCleaned = specCleaned + 1
                            end
                        end
                    end
                end
            end
            if specCleaned > 0 then
                totalCleaned = totalCleaned + specCleaned
                print(P, specLabel .. ": cleaned", specCleaned, "foreign spells")
            else
                print(P, specLabel .. ": clean")
            end
        else
            print(P, specLabel .. ": skipped (unknown spec)")
        end
    end

    print(P, "Done.", profilesChecked, "profiles checked,", totalCleaned, "foreign spells removed.")
    print(P, "Run /cdmprofiles to verify. Run this on each character to clean their specs.")
end

ns.CDMSpellData = CDMSpellData
