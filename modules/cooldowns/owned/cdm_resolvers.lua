-- cdm_resolvers.lua
-- Pure resolution layer for the QUI CDM owned engine.
-- Functions in this file MUST NOT write to frames; they compute and return values.
-- Tick-scoped caches live here because both resolvers and the icon factory's
-- UpdateIconCooldown driver depend on them.

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local CDMResolvers = {}
ns.CDMResolvers = CDMResolvers

---------------------------------------------------------------------------
-- TICK CACHES: wiped at the start of each UpdateAllCooldowns batch.
-- Avoids redundant C API calls when the same spellID appears in multiple
-- containers or is queried by both GetBestSpellCooldown and stack/visibility.
---------------------------------------------------------------------------
local _tickChargeCache = {}    -- [spellID] = chargeInfo or false
local _tickCooldownCache = {}  -- [spellID] = cdInfo or false
local _tickDurationCache = {}  -- [spellID] = DurationObject or false
local _tickChargeDurationCache = {} -- [spellID] = DurationObject or false
local _tickOverrideCache = {}  -- [spellID] = override spellID or false
local _tickDisplayCountCache = {} -- [spellID] = display count or false
local _tickChargeCacheTime = {}
local _tickCooldownCacheTime = {}
local _tickDurationCacheTime = {}
local _tickChargeDurationCacheTime = {}
local _tickOverrideCacheTime = {}
local _tickDisplayCountCacheTime = {}
local _tickCooldownCacheNow = 0
local _nextCooldownCachePrune = 0
local COOLDOWN_QUERY_CACHE_TTL = 0.20
local COOLDOWN_QUERY_CACHE_PRUNE_INTERVAL = 1.0
local _tickCooldownStats = {
    chargeQueries = 0,
    cooldownQueries = 0,
    durationQueries = 0,
    chargeDurationQueries = 0,
    overrideQueries = 0,
    displayCountQueries = 0,
    updateBatches = 0,
    fullUpdateBatches = 0,
    cooldownOnlyBatches = 0,
    iconsProcessed = 0,
    updateRequests = 0,
    updateFastRequests = 0,
    updateCoalesced = 0,
}
CDMResolvers._stats = _tickCooldownStats
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_spellCooldownCacheMeta", fn = function()
        local charges, cooldowns, durations, chargeDurations, overrides, displayCounts = 0, 0, 0, 0, 0, 0
        for _ in pairs(_tickChargeCacheTime) do charges = charges + 1 end
        for _ in pairs(_tickCooldownCacheTime) do cooldowns = cooldowns + 1 end
        for _ in pairs(_tickDurationCacheTime) do durations = durations + 1 end
        for _ in pairs(_tickChargeDurationCacheTime) do chargeDurations = chargeDurations + 1 end
        for _ in pairs(_tickOverrideCacheTime) do overrides = overrides + 1 end
        for _ in pairs(_tickDisplayCountCacheTime) do displayCounts = displayCounts + 1 end
        return charges + cooldowns + durations + chargeDurations + overrides + displayCounts, 0
    end }
    mp[#mp + 1] = { name = "CDM_spellChargeQueries", counter = true, fn = function()
        return _tickCooldownStats.chargeQueries
    end }
    mp[#mp + 1] = { name = "CDM_spellCooldownQueries", counter = true, fn = function()
        return _tickCooldownStats.cooldownQueries
    end }
    mp[#mp + 1] = { name = "CDM_spellDurationQueries", counter = true, fn = function()
        return _tickCooldownStats.durationQueries
    end }
    mp[#mp + 1] = { name = "CDM_spellChargeDurationQueries", counter = true, fn = function()
        return _tickCooldownStats.chargeDurationQueries
    end }
    mp[#mp + 1] = { name = "CDM_spellOverrideQueries", counter = true, fn = function()
        return _tickCooldownStats.overrideQueries
    end }
    mp[#mp + 1] = { name = "CDM_spellDisplayCountQueries", counter = true, fn = function()
        return _tickCooldownStats.displayCountQueries
    end }
    mp[#mp + 1] = { name = "CDM_updateBatches", counter = true, fn = function()
        return _tickCooldownStats.updateBatches
    end }
    mp[#mp + 1] = { name = "CDM_fullUpdateBatches", counter = true, fn = function()
        return _tickCooldownStats.fullUpdateBatches
    end }
    mp[#mp + 1] = { name = "CDM_cooldownOnlyBatches", counter = true, fn = function()
        return _tickCooldownStats.cooldownOnlyBatches
    end }
    mp[#mp + 1] = { name = "CDM_iconsProcessed", counter = true, fn = function()
        return _tickCooldownStats.iconsProcessed
    end }
    mp[#mp + 1] = { name = "CDM_updateRequests", counter = true, fn = function()
        return _tickCooldownStats.updateRequests
    end }
    mp[#mp + 1] = { name = "CDM_updateFastRequests", counter = true, fn = function()
        return _tickCooldownStats.updateFastRequests
    end }
    mp[#mp + 1] = { name = "CDM_updateCoalesced", counter = true, fn = function()
        return _tickCooldownStats.updateCoalesced
    end }
end

function CDMResolvers.ClearUpdateTickCaches()
    wipe(_tickChargeCache)
    wipe(_tickCooldownCache)
    wipe(_tickDurationCache)
    wipe(_tickChargeDurationCache)
    wipe(_tickOverrideCache)
    wipe(_tickDisplayCountCache)
    wipe(_tickChargeCacheTime)
    wipe(_tickCooldownCacheTime)
    wipe(_tickDurationCacheTime)
    wipe(_tickChargeDurationCacheTime)
    wipe(_tickOverrideCacheTime)
    wipe(_tickDisplayCountCacheTime)
    _tickCooldownCacheNow = 0
    _nextCooldownCachePrune = 0
end

local function GetCooldownCacheNow()
    local now = _tickCooldownCacheNow
    if not now or now == 0 then
        now = GetTime()
        _tickCooldownCacheNow = now
    end
    return now
end

local function PruneUpdateTickCaches(now)
    local cutoff = now - COOLDOWN_QUERY_CACHE_TTL
    for spellID, stamp in pairs(_tickChargeCacheTime) do
        if not stamp or stamp < cutoff then
            _tickChargeCache[spellID] = nil
            _tickChargeCacheTime[spellID] = nil
        end
    end
    for spellID, stamp in pairs(_tickCooldownCacheTime) do
        if not stamp or stamp < cutoff then
            _tickCooldownCache[spellID] = nil
            _tickCooldownCacheTime[spellID] = nil
        end
    end
    for spellID, stamp in pairs(_tickDurationCacheTime) do
        if not stamp or stamp < cutoff then
            _tickDurationCache[spellID] = nil
            _tickDurationCacheTime[spellID] = nil
        end
    end
    for spellID, stamp in pairs(_tickChargeDurationCacheTime) do
        if not stamp or stamp < cutoff then
            _tickChargeDurationCache[spellID] = nil
            _tickChargeDurationCacheTime[spellID] = nil
        end
    end
    for spellID, stamp in pairs(_tickOverrideCacheTime) do
        if not stamp or stamp < cutoff then
            _tickOverrideCache[spellID] = nil
            _tickOverrideCacheTime[spellID] = nil
        end
    end
    for spellID, stamp in pairs(_tickDisplayCountCacheTime) do
        if not stamp or stamp < cutoff then
            _tickDisplayCountCache[spellID] = nil
            _tickDisplayCountCacheTime[spellID] = nil
        end
    end
end

function CDMResolvers.BeginUpdateTickCaches(forceClear)
    if forceClear or not InCombatLockdown() then
        CDMResolvers.ClearUpdateTickCaches()
        return
    end

    local now = GetTime()
    _tickCooldownCacheNow = now
    if now >= _nextCooldownCachePrune then
        _nextCooldownCachePrune = now + COOLDOWN_QUERY_CACHE_PRUNE_INTERVAL
        PruneUpdateTickCaches(now)
    end
end

-- Persistent multi-charge spell cache (survives combat/reload via SavedVariables).
-- Populated OOC when GetSpellCharges returns readable values; consulted in combat
-- when secret values block runtime detection.
local function GetChargeMetadataDB()
    local db = QUI and QUI.db and QUI.db.global
    if not db then return nil end
    if not db.cdmChargeSpells then db.cdmChargeSpells = {} end
    return db.cdmChargeSpells
end

function CDMResolvers.TickCacheGetCharges(spellID)
    if not spellID then return nil end
    local now = GetCooldownCacheNow()
    local cached = _tickChargeCache[spellID]
    if cached ~= nil then
        local stamp = _tickChargeCacheTime[spellID]
        if stamp and (now - stamp) <= COOLDOWN_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickChargeCache[spellID] = nil
        _tickChargeCacheTime[spellID] = nil
    end
    _tickCooldownStats.chargeQueries = _tickCooldownStats.chargeQueries + 1
    local chargeInfo = nil
    if C_Spell.GetSpellCharges then
        local ok, result = pcall(C_Spell.GetSpellCharges, spellID)
        if ok then
            chargeInfo = result
        end
    end
    _tickChargeCache[spellID] = chargeInfo or false
    _tickChargeCacheTime[spellID] = now
    -- Persist multi-charge detection OOC for combat fallback.
    -- Also clean up stale cache entries when API returns no charges or <= 1.
    if not InCombatLockdown() then
        if chargeInfo then
            local maxC = SafeToNumber(chargeInfo.maxCharges, nil)
            if maxC and maxC > 1 then
                local svDB = GetChargeMetadataDB()
                if svDB then svDB[spellID] = maxC end
            elseif maxC then
                -- API returned readable maxCharges <= 1 — remove stale cache
                local svDB = GetChargeMetadataDB()
                if svDB and svDB[spellID] then svDB[spellID] = nil end
            end
        else
            -- API returned nil = no charge mechanic — remove stale cache
            local svDB = GetChargeMetadataDB()
            if svDB and svDB[spellID] then svDB[spellID] = nil end
        end
    end
    return chargeInfo
end

function CDMResolvers.TickCacheGetCooldown(spellID)
    if not spellID then return nil end
    local now = GetCooldownCacheNow()
    local cached = _tickCooldownCache[spellID]
    if cached ~= nil then
        local stamp = _tickCooldownCacheTime[spellID]
        if stamp and (now - stamp) <= COOLDOWN_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickCooldownCache[spellID] = nil
        _tickCooldownCacheTime[spellID] = nil
    end
    _tickCooldownStats.cooldownQueries = _tickCooldownStats.cooldownQueries + 1
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok then cdInfo = nil end
    _tickCooldownCache[spellID] = cdInfo or false
    _tickCooldownCacheTime[spellID] = now
    return cdInfo
end

function CDMResolvers.TickCacheGetDuration(spellID)
    if not spellID then return nil end
    local now = GetCooldownCacheNow()
    local cached = _tickDurationCache[spellID]
    if cached ~= nil then
        local stamp = _tickDurationCacheTime[spellID]
        if stamp and (now - stamp) <= COOLDOWN_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickDurationCache[spellID] = nil
        _tickDurationCacheTime[spellID] = nil
    end
    _tickCooldownStats.durationQueries = _tickCooldownStats.durationQueries + 1
    local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    local result = (ok and durObj) or nil
    _tickDurationCache[spellID] = result or false
    _tickDurationCacheTime[spellID] = now
    return result
end

function CDMResolvers.TickCacheGetChargeDuration(spellID)
    if not spellID or not C_Spell.GetSpellChargeDuration then return nil end
    local now = GetCooldownCacheNow()
    local cached = _tickChargeDurationCache[spellID]
    if cached ~= nil then
        local stamp = _tickChargeDurationCacheTime[spellID]
        if stamp and (now - stamp) <= COOLDOWN_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickChargeDurationCache[spellID] = nil
        _tickChargeDurationCacheTime[spellID] = nil
    end
    _tickCooldownStats.chargeDurationQueries = _tickCooldownStats.chargeDurationQueries + 1
    local ok, durObj = pcall(C_Spell.GetSpellChargeDuration, spellID)
    local result = (ok and durObj) or nil
    _tickChargeDurationCache[spellID] = result or false
    _tickChargeDurationCacheTime[spellID] = now
    return result
end

function CDMResolvers.TickCacheGetOverrideSpell(spellID)
    if not spellID or not C_Spell.GetOverrideSpell then return nil end
    local now = GetCooldownCacheNow()
    local cached = _tickOverrideCache[spellID]
    if cached ~= nil then
        local stamp = _tickOverrideCacheTime[spellID]
        if stamp and (now - stamp) <= COOLDOWN_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickOverrideCache[spellID] = nil
        _tickOverrideCacheTime[spellID] = nil
    end
    _tickCooldownStats.overrideQueries = _tickCooldownStats.overrideQueries + 1
    local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
    if not ok then return nil end
    if IsSecretValue(overrideID) then
        return nil
    end
    _tickOverrideCache[spellID] = overrideID or false
    _tickOverrideCacheTime[spellID] = now
    return overrideID
end

function CDMResolvers.TickCacheGetDisplayCount(spellID)
    if not spellID or not C_Spell.GetSpellDisplayCount then return nil end
    local now = GetCooldownCacheNow()
    local cached = _tickDisplayCountCache[spellID]
    if cached ~= nil then
        local stamp = _tickDisplayCountCacheTime[spellID]
        if stamp and (now - stamp) <= COOLDOWN_QUERY_CACHE_TTL then
            return cached or nil
        end
        _tickDisplayCountCache[spellID] = nil
        _tickDisplayCountCacheTime[spellID] = nil
    end
    _tickCooldownStats.displayCountQueries = _tickCooldownStats.displayCountQueries + 1
    local ok, val = pcall(C_Spell.GetSpellDisplayCount, spellID)
    local result = (ok and val) or nil
    if IsSecretValue(result) then
        return result
    end
    _tickDisplayCountCache[spellID] = result or false
    _tickDisplayCountCacheTime[spellID] = now
    return result
end


-- IDENTITY RESOLVERS

function CDMResolvers.IsItemLikeEntry(entry)
    return entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
end

function CDMResolvers.ResolveItemCooldownIdentity(entry)
    if not entry then return nil, nil, nil, nil end

    local itemID, slotID
    if entry.type == "item" then
        itemID = entry.id
    elseif entry.type == "trinket" or entry.type == "slot" then
        slotID = entry.id
        itemID = (GetInventoryItemID and GetInventoryItemID("player", slotID)) or entry.itemID
    elseif entry.type == "macro" then
        local resolvedID, resolvedType = CDMResolvers.ResolveMacro(entry)
        if resolvedType == "item" then
            itemID = resolvedID
        end
    end

    if not itemID then return nil, slotID, nil, nil end

    local itemSpellID = CDMIcons.GetItemUseSpellID(itemID)
    local keySource = slotID and (tostring(slotID) .. ":" .. tostring(itemID)) or tostring(itemID)
    return itemID, slotID, itemSpellID, keySource
end

function CDMResolvers.ResolveEntryItemID(entry)
    if not entry then return nil end
    if entry.type == "item" then
        return entry.id
    elseif entry.type == "trinket" or entry.type == "slot" then
        return GetInventoryItemID("player", entry.id)
    end
    return nil
end


-- TEXTURE & MACRO RESOLVERS

-- Persistent texture cache: spellID→iconID rarely changes (only on talent
-- swap / spec change), so we keep it across ticks.  Wiped on SPELLS_CHANGED
-- and PLAYER_SPECIALIZATION_CHANGED to pick up new icons.
local _textureCycleCache = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "CDM_textureCycleCache", tbl = _textureCycleCache } end
CDMResolvers._textureCycleCache = _textureCycleCache

function CDMResolvers.GetSpellTexture(spellID)
    if not spellID then return nil end
    local cached = _textureCycleCache[spellID]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local texID = info and info.iconID or nil
    _textureCycleCache[spellID] = texID or false
    return texID
end

---------------------------------------------------------------------------
-- MACRO RESOLUTION
-- Resolve a macro custom entry to its current spell or item via
-- #showtooltip / GetMacroSpell / GetMacroItem.  Re-evaluated every tick
-- so the icon tracks conditional changes (target, modifiers, stance).
---------------------------------------------------------------------------
function CDMResolvers.ResolveMacro(entry)
    local macroName = entry.macroName
    if not macroName then return nil, nil, nil end
    local macroIndex = GetMacroIndexByName(macroName)
    if not macroIndex or macroIndex == 0 then return nil, nil, nil end

    -- GetMacroSpell returns the spellID that #showtooltip resolves to
    local spellID = GetMacroSpell(macroIndex)
    if spellID then
        return spellID, "spell", nil
    end

    -- GetMacroItem returns itemName, itemLink for /use macros
    local itemName, itemLink = GetMacroItem(macroIndex)
    if itemLink then
        local itemID = C_Item.GetItemInfoInstant(itemLink)
        if itemID then
            return itemID, "item", nil
        end
    end

    -- Fallback: macro's own icon (no resolvable cooldown)
    local _, _, macroIcon = GetMacroInfo(macroIndex)
    return nil, nil, macroIcon
end

function CDMResolvers.GetEntryTexture(entry)
    if not entry then return nil end
    if entry.type == "macro" then
        local resolvedID, resolvedType, fallbackTex = CDMResolvers.ResolveMacro(entry)
        if resolvedID then
            if resolvedType == "item" then
                local _, _, _, _, icon = C_Item.GetItemInfoInstant(resolvedID)
                return icon
            else
                return CDMResolvers.GetSpellTexture(resolvedID)
            end
        end
        return fallbackTex
    end
    if entry.type == "trinket" or entry.type == "slot" then
        -- Trinket/slot entries store the equipment slot number (13/14), not the item ID.
        -- Resolve to the actual equipped item ID before looking up the icon.
        local itemID = entry.itemID or GetInventoryItemID("player", entry.id)
        if itemID then
            local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
            return icon
        end
        return nil
    end
    if entry.type == "item" then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(entry.id)
        return icon
    end
    return CDMResolvers.GetSpellTexture(entry.overrideSpellID or entry.id)
end

---------------------------------------------------------------------------
-- CLASSIFICATION
---------------------------------------------------------------------------

-- Taint helpers (Option A: imported from Helpers; Option B: local wrappers for
-- SafeBoolean and IsSafeNumeric which are not exported on Helpers).
local IsSecretValue = Helpers.IsSecretValue
local SafeToNumber  = Helpers.SafeToNumber

local function IsSafeNumeric(val)
    if IsSecretValue(val) then return false end
    return type(val) == "number"
end

local function SafeBoolean(val)
    if IsSecretValue(val) then return nil end
    if type(val) == "boolean" then return val end
    return nil
end

local GCD_MAX_DURATION = 1.75

local CDMIcons = ns.CDMIcons  -- forward ref; populated before these functions are called

function CDMResolvers.ClassifySpellCooldownState(spellID, info)
    if not info and spellID and C_Spell and C_Spell.GetSpellCooldown then
        local ok, fetchedInfo = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok then
            info = fetchedInfo
        end
    end

    local active = CDMIcons.IsCooldownInfoActive(info)
    local realActive = CDMIcons.IsCooldownInfoRealCooldown(info)
    local onGCD = false
    if CDMIcons._trustIsOnGCDForBatch == true then
        local trusted = CDMIcons._trustedGCDSpellState and spellID and CDMIcons._trustedGCDSpellState[spellID]
        if type(trusted) == "boolean" then
            onGCD = trusted
        end
    end
    -- isOnGCD is treated as a safe cooldown classifier signal.
    local infoOnGCD = type(info) == "table" and info.isOnGCD
    if onGCD == false and infoOnGCD == true then
        onGCD = true
    end

    if realActive == nil
       and active == true
       and spellID
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD(spellID) then
        realActive = true
    end

    if realActive == true and active ~= false then
        active = true
    end

    return active, realActive, onGCD, info
end

function CDMResolvers.HasRealCooldownState(icon, entry, duration, apiIsActive, blizzRealCooldownActive, durObj, runtimeSpellID)
    if not icon or not entry then
        return false
    end

    if icon._auraActive or entry.viewerType == "buff" then
        return false
    end

    if apiIsActive == false then
        return false
    end

    local chargeInfo = runtimeSpellID and TickCacheGetCharges(runtimeSpellID)
    local maxCharges = chargeInfo and SafeToNumber(chargeInfo.maxCharges, nil)
    if maxCharges and maxCharges > 1 then
        return blizzRealCooldownActive == true
            or durObj ~= nil
    end

    if blizzRealCooldownActive then
        return true
    end

    if durObj and apiIsActive == true
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD(runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id) then
        return true
    end

    if IsSafeNumeric(icon and icon._lastStart) and IsSafeNumeric(icon and icon._lastDuration)
        and icon._lastStart > 0 and icon._lastDuration > GCD_MAX_DURATION then
        return true
    end

    if type(duration) == "number" and duration > GCD_MAX_DURATION then
        return true
    end

    local lastDuration = icon._lastDuration
    if type(lastDuration) == "number" and lastDuration > GCD_MAX_DURATION then
        return true
    end

    return false
end

function CDMResolvers.ResolveSpellActiveState(spellID, icon, entry)
    if not spellID then return false end

    local active, start, duration, activeType = CDMIcons.GetSpellCastInfo(spellID)
    if active then return active, start, duration, activeType end

    active, start, duration, activeType = CDMIcons.GetSpellChannelInfo(spellID)
    if active then return active, start, duration, activeType end

    active, start, duration, activeType = CDMIcons.GetSpellBuffInfo(spellID, icon, entry)
    if active then return active, start, duration, activeType end

    if C_Spell and C_Spell.GetOverrideSpell then
        local overrideID = TickCacheGetOverrideSpell(spellID)
        if overrideID and not IsSecretValue(overrideID) and overrideID ~= spellID then
            active, start, duration, activeType = CDMIcons.GetSpellCastInfo(overrideID)
            if active then return active, start, duration, activeType end
            active, start, duration, activeType = CDMIcons.GetSpellChannelInfo(overrideID)
            if active then return active, start, duration, activeType end
            active, start, duration, activeType = CDMIcons.GetSpellBuffInfo(overrideID, icon, entry)
            if active then return active, start, duration, activeType end
        end
    end

    return false
end

function CDMResolvers.ResolveCooldownActivityState(icon, entry, containerDB, now)
    local state = {
        isOnCooldown = false,
        rechargeActive = false,
        hasChargesRemaining = false,
        -- Internal QUI metadata only; do not populate this from secret API
        -- charge predicates.
        hasCharges = entry and entry.hasCharges or false,
    }
    if not icon or not entry then return state end

    now = now or GetTime()
    local spellID = CDMIcons.ResolveEntryRuntimeSpellID(icon, entry)
    local isItemLike = CDMIcons.IsItemLikeEntry(entry)

    if spellID and not state.hasCharges then
        local gdb = QUI and QUI.db and QUI.db.global
        local svCharges = gdb and gdb.cdmChargeSpells
        if svCharges and svCharges[spellID] then
            state.hasCharges = true
        end
    end

    if spellID and not isItemLike then
        local ci = TickCacheGetCharges(spellID)
        if ci then
            local maxC = SafeToNumber(ci.maxCharges, nil)
            if maxC and maxC > 1 then
                state.hasCharges = true
            end
        end

        if state.hasCharges then
            local cdInfo = TickCacheGetCooldown(spellID)
            local cooldownActive = CDMIcons.IsCooldownInfoActive(cdInfo)
            if cooldownActive == true then
                state.rechargeActive = true
                state.isOnCooldown = true
                return state
            elseif cooldownActive == false then
                -- Do not use SpellChargeInfo.currentCharges here. The charge
                -- info payload can be restricted in combat; a readable
                -- "spell cooldown is inactive" signal is enough to know the
                -- charged spell is not fully locked out.
                state.hasChargesRemaining = true
                state.isOnCooldown = false
            end

            if ci then
                local chargeActive = SafeBoolean(ci.isActive)
                if chargeActive == true then
                    state.rechargeActive = true
                end
            end
            if not state.rechargeActive
               and (icon._hasRealCooldownActive == true or icon._showingRealCooldownSwipe == true) then
                state.rechargeActive = true
                state.isOnCooldown = true
            end
        end
    end

    if state.hasCharges then
        return state
    end

    if not state.rechargeActive then
        if icon._hasRealCooldownActive == true then
            state.isOnCooldown = true
        elseif icon._hasRealCooldownActive == false then
            state.isOnCooldown = false
        else
            local dur = icon._lastDuration or 0
            local start = icon._lastStart or 0
            if icon._hasCooldownActive then
                state.isOnCooldown = true
            elseif dur > GCD_MAX_DURATION and start > 0 then
                local remaining = (start + dur) - now
                if remaining > 0 then
                    state.isOnCooldown = true
                end
            end
        end
    end

    return state
end


-- DURATION OBJECT RESOLVERS

local TickCacheGetDuration       = CDMResolvers.TickCacheGetDuration
local TickCacheGetChargeDuration = CDMResolvers.TickCacheGetChargeDuration
local TickCacheGetOverrideSpell  = CDMResolvers.TickCacheGetOverrideSpell

function CDMResolvers.IsAuraEntry(entry)
    if not entry then return false end
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.IsAuraEntry then
        return CDMSpellData.IsAuraEntry(entry, entry.viewerType)
    end
    -- Bootstrap fallback (CDMSpellData not yet loaded)
    if entry.kind == "aura" then return true end
    if entry.kind == "cooldown" then return false end
    local vt = entry.viewerType
    return vt == "buff" or vt == "trackedBar"
end

local function QueryPlayerAuraDurationBySpellID(rawSpellID)
    if not rawSpellID or not C_UnitAuras or not C_UnitAuras.GetAuraDuration then
        return nil
    end

    local auraData
    if C_UnitAuras.GetCooldownAuraBySpellID then
        local ok, ad = pcall(C_UnitAuras.GetCooldownAuraBySpellID, rawSpellID)
        if ok and ad then
            auraData = ad
        end
    end
    if C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, ad = pcall(C_UnitAuras.GetPlayerAuraBySpellID, rawSpellID)
        if not auraData and ok and ad then
            auraData = ad
        end
    end
    if not auraData and C_UnitAuras.GetAuraDataBySpellID then
        local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", rawSpellID, "HELPFUL")
        if ok and ad then
            auraData = ad
        end
    end

    local auraInstanceID = auraData and auraData.auraInstanceID
    if not auraInstanceID then return nil end

    local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, "player", auraInstanceID)
    if ok then return durObj end
    return nil
end

local function QueryPlayerAuraDurationByName(name)
    if type(name) ~= "string"
       or name == ""
       or not C_UnitAuras
       or not C_UnitAuras.GetAuraDataBySpellName
       or not C_UnitAuras.GetAuraDuration then
        return nil
    end

    local ok, auraData = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if not ok or not auraData then
        return nil
    end

    local auraInstanceID = auraData.auraInstanceID
    if not auraInstanceID then return nil end

    local okDur, durObj = pcall(C_UnitAuras.GetAuraDuration, "player", auraInstanceID)
    if okDur then return durObj end
    return nil
end

function CDMResolvers.ResolveAuraStateForIcon(icon, entry, sid)
    local CDMSpellData = ns.CDMSpellData
    if not (icon and entry and sid and CDMSpellData and CDMSpellData.ResolveAuraState) then
        return nil
    end

    local auraEntry = CDMResolvers.IsAuraEntry(entry)
    if not auraEntry and not CDMIcons.ShouldUseBuffSwipeForIcon(icon, entry) then
        return nil
    end

    local p = icon._auraParams or {}
    icon._auraParams = p
    p.spellID = sid
    p.entrySpellID = entry.spellID
    p.entryID = entry.id
    p.entryName = entry.name
    p.viewerType = entry.viewerType
    p.blizzChild = entry._blizzChild
    p.blizzBarChild = entry._blizzBarChild
    p.totemSlot = CDMIcons.IsTotemSlotEntry(entry) and entry._totemSlot or nil
    p.disableLooseVisibilityFallback = true

    local r = CDMSpellData:ResolveAuraState(p)
    entry._blizzBarChild = r.blizzBarChild
    return r
end

function CDMResolvers.ResolveAuraDurationObjectForIcon(icon, entry, sid)
    return CDMIcons.ApplyAuraStateToIcon(icon, entry, sid, CDMResolvers.ResolveAuraStateForIcon(icon, entry, sid))
end

function CDMResolvers.ResolveItemAuraDurationObject(icon, entry, itemID, itemSpellID)
    if not (icon and entry and itemID) then
        return nil, false, nil
    end

    local function trySpellID(rawSpellID, sourceKey)
        local durObj = QueryPlayerAuraDurationBySpellID(rawSpellID)
        if durObj then
            local sourceID = "item-aura-spell:" .. tostring(itemID) .. ":" .. sourceKey
            icon._auraActive = true
            icon._auraUnit = "player"
            icon._totemSlot = entry._totemSlot or nil
            icon._isTotemInstance = nil
            icon._lastAuraDurObj = durObj
            icon._lastAuraSourceID = sourceID
            return durObj, true, sourceID
        end
        return nil, false, nil
    end

    local rawItemSpellID = CDMIcons.GetRawItemUseSpellIDForAuraQuery(itemID)
    local durObj, active, sourceID = trySpellID(rawItemSpellID, "raw-use")
    if active then return durObj, active, sourceID end

    durObj, active, sourceID = trySpellID(itemSpellID, "use")
    if active then return durObj, active, sourceID end

    durObj, active, sourceID = trySpellID(entry.spellID, "entry")
    if active then return durObj, active, sourceID end

    durObj, active, sourceID = trySpellID(entry.overrideSpellID, "override")
    if active then return durObj, active, sourceID end

    durObj, active, sourceID = trySpellID(entry.id, "id")
    if active then
        return durObj, active, sourceID
    end

    durObj = QueryPlayerAuraDurationByName(entry.name)
    if durObj then
        sourceID = "item-aura-name:" .. tostring(itemID)
        icon._auraActive = true
        icon._auraUnit = "player"
        icon._totemSlot = entry._totemSlot or nil
        icon._isTotemInstance = nil
        icon._lastAuraDurObj = durObj
        icon._lastAuraSourceID = sourceID
        return durObj, true, sourceID
    end

    return nil, false, nil
end

function CDMResolvers.ResolveItemDurationObjectForIcon(icon, entry)
    local itemID, slotID, itemSpellID, keySource = CDMResolvers.ResolveItemCooldownIdentity(entry)
    if not itemID then return nil, "inactive", nil, nil, nil, nil end

    if itemSpellID and C_Spell and C_Spell.GetSpellCooldown then
        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, itemSpellID)
        local cdInfoActive = ok and cdInfo and CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
        if cdInfoActive == true and cdInfo.isOnGCD ~= true then
            local durObj = TickCacheGetDuration(itemSpellID)
            if durObj then
                return durObj, "item-cooldown",
                    "spell:" .. tostring(itemSpellID) .. ":" .. tostring(keySource),
                    nil, nil, itemSpellID
            end
        end
    end

    local startTime, duration
    if slotID then
        startTime, duration = CDMIcons.GetSlotCooldown(slotID)
    else
        startTime, duration = CDMIcons.GetItemCooldown(itemID)
    end

    if IsSafeNumeric(startTime)
       and IsSafeNumeric(duration)
       and startTime > 0
       and duration > GCD_MAX_DURATION
       and (startTime + duration) > GetTime() then
        return nil, "item-cooldown",
            "item:" .. tostring(keySource) .. ":" .. tostring(startTime) .. ":" .. tostring(duration),
            startTime, duration, itemSpellID
    end

    return nil, "inactive", nil, nil, nil, itemSpellID
end

function CDMResolvers.ResolveIconDurationObject(icon)
    local entry = icon and icon._spellEntry
    if not entry then return nil, "inactive", nil end

    local sid = icon._runtimeSpellID
        or entry.overrideSpellID or entry.spellID or entry.id
    if sid then
        sid = TickCacheGetOverrideSpell(sid) or sid
    end
    local itemID, itemSpellID
    if CDMResolvers.IsItemLikeEntry(entry) then
        itemID, _, itemSpellID = CDMResolvers.ResolveItemCooldownIdentity(entry)
        if itemSpellID then
            sid = itemSpellID
        end
    end

    -- 1. Aura up on player → aura DurObj. Use the same ResolveAuraState path
    -- as UpdateIconCooldown so the event-driven CooldownFrame binding and the
    -- per-icon active-state update cannot disagree in combat.
    local auraDur, auraActive, auraSourceID = CDMResolvers.ResolveAuraDurationObjectForIcon(icon, entry, sid)
    if auraActive then
        return auraDur, "aura", auraSourceID
    end

    if itemID then
        local itemAuraDur, itemAuraActive, itemAuraSourceID =
            CDMResolvers.ResolveItemAuraDurationObject(icon, entry, itemID, itemSpellID)
        if itemAuraActive then
            return itemAuraDur, "aura", itemAuraSourceID
        end
    end

    if CDMResolvers.IsItemLikeEntry(entry) then
        local itemDur, itemMode, itemSourceID, itemStart, itemDuration, itemSpellID =
            CDMResolvers.ResolveItemDurationObjectForIcon(icon, entry)
        if itemMode == "item-cooldown" then
            return itemDur, itemMode, itemSourceID, itemStart, itemDuration, itemSpellID
        end
        if entry.type ~= "macro" then
            return nil, "inactive", nil, nil, nil, itemSpellID
        end
    end

    -- Aura-kind entries have no cooldown path.
    if CDMResolvers.IsAuraEntry(entry) or not sid then
        return nil, "inactive", nil
    end

    -- 2. Charge spell mid-recharge → recharge DurObj.
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, ci = pcall(C_Spell.GetSpellCharges, sid)
        local maxCharges = ok and ci and SafeToNumber(ci.maxCharges, nil)
        local chargeActive = ok and ci and SafeBoolean(ci.isActive)
        local isChargeSpell = entry.hasCharges or (maxCharges and maxCharges > 1)
        if isChargeSpell and chargeActive == true then
            local chargeDur = TickCacheGetChargeDuration(sid)
            if chargeDur then
                local serial = CDMIcons._chargeDurationObjectSerial or 0
                return chargeDur, "charge", tostring(sid) .. ":" .. tostring(serial)
            end
        end
    end

    -- 3. Spell cooldown active → spell DurObj. cdInfo.isOnGCD
    -- distinguishes real CD from GCD overlay.
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, sid)
        local cdInfoActive = ok and cdInfo and CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
        if cdInfoActive == true then
            local durObj = TickCacheGetDuration(sid)
            if durObj then
                local cdInfoOnGCD = cdInfo.isOnGCD
                if cdInfoOnGCD == true then
                    if CDMIcons.IsGCDSwipeEnabled() then
                        return durObj, "gcd-only", sid
                    end
                else
                    return durObj, "cooldown", sid
                end
            end
        end
    end

    return nil, "inactive", nil
end
