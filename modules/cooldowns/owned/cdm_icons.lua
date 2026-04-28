--[[
    QUI CDM Icon Factory

    Creates and manages addon-owned icon frames for the CDM system.
    All icons are simple Frame objects (not Buttons) with no protected
    attributes, eliminating all combat taint concerns for frame operations.

    Absorbs cdm_custom.lua functionality — custom entries use the same
    icon pool as harvested entries.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = ns.LSM

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMIcons = {}
ns.CDMIcons = CDMIcons
local CDMCooldown = ns.CDMCooldown or {}
ns.CDMCooldown = CDMCooldown

-- CustomCDM exposed on CDMIcons for engine access (provider wires to ns.CustomCDM)
local CustomCDM = {}
CDMIcons.CustomCDM = CustomCDM

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local ApplyCooldownFromStart = Helpers.ApplyCooldownFromStart
local ApplyCooldownFromSpell = Helpers.ApplyCooldownFromSpell
local IsSecretValue = Helpers.IsSecretValue
local SafeToNumber = Helpers.SafeToNumber
local SafeValue = Helpers.SafeValue

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local CreateFrame = CreateFrame
local GetTime = GetTime
local wipe = wipe
local select = select
local tostring = tostring
local format = format
local InCombatLockdown = InCombatLockdown
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local C_Item = C_Item
local C_CooldownViewer = C_CooldownViewer
local C_StringUtil = C_StringUtil
local issecretvalue = issecretvalue
local DebugIconSwipe

local function IsSafeNumeric(val)
    if IsSecretValue(val) then return false end
    return type(val) == "number"
end

local function GetContainerTypeForViewer(viewerType)
    if not viewerType then return nil end
    local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
    local containerDB = ncdm and (ncdm[viewerType] or (ncdm.containers and ncdm.containers[viewerType]))
    local cType = containerDB and containerDB.containerType
    if not cType then
        cType = (viewerType == "buff" or viewerType == "trackedBar") and "aura" or "cooldown"
    end
    return cType
end

local function IsAuraContainerViewer(viewerType)
    local cType = GetContainerTypeForViewer(viewerType)
    return cType == "aura" or cType == "auraBar"
end

local function UsesAPIAuraStackText(entry)
    if not entry then return false end
    return IsAuraContainerViewer(entry.viewerType)
end

-- True when the actual Blizzard child lives in a buff viewer.  Used to
-- route stack-text handling through the API hook path even when the QUI
-- container is cooldown-typed: Blizzard's buff viewer doesn't drive
-- ChargeCount/Applications reliably after a reparent, so stacks for spells
-- like Mana Tea blank out on custom cooldown containers if we don't
-- detect this case independently of container type.
local function IsBuffViewerChild(blizzChild)
    if not blizzChild or not blizzChild.viewerFrame then return false end
    local buffViewer = _G["BuffIconCooldownViewer"]
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    return blizzChild.viewerFrame == buffViewer or blizzChild.viewerFrame == buffBarViewer
end

-- True when the entry's stack text should come from the buff-viewer hook
-- path rather than the reparent path.  Either an aura/auraBar container
-- or a cooldown container backed by a buff-viewer child qualifies.
local function UsesHookStackText(entry, blizzChild)
    if UsesAPIAuraStackText(entry) then return true end
    return IsBuffViewerChild(blizzChild or (entry and entry._blizzChild))
end


-- Per-spell override lookup helper.  Returns the cached override table
-- for the icon's spell/container, or nil.  Cheap (two table lookups).
local function GetIconSpellOverride(icon)
    local entry = icon and icon._spellEntry
    if not entry then return nil end
    local CDMSpellData = ns.CDMSpellData
    if not CDMSpellData then return nil end
    local spellID = entry.spellID or entry.id
    local containerKey = entry.viewerType
    if not spellID or not containerKey then return nil end
    return CDMSpellData:GetSpellOverride(containerKey, spellID)
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local MAX_RECYCLE_POOL_SIZE = 20
local DEFAULT_ICON_SIZE = 39
local BASE_CROP = 0.08
local GCD_SPELL_ID = 61304
local GCD_MAX_DURATION = 1.75

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local iconPools = {
    essential = {},
    utility   = {},
    buff      = {},
}
-- Phase G: Pools for custom containers are created dynamically via EnsurePool().
local recyclePool = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_iconRecyclePool", tbl = recyclePool }
    -- iconPools is a multi-key map of arrays; count across every sub-pool
    -- (incl. dynamically created Composer pools) so retention growth surfaces.
    mp[#mp + 1] = { name = "CDM_iconPools", fn = function()
        local count, deep = 0, 0
        for _, pool in pairs(iconPools) do
            count = count + 1
            if type(pool) == "table" then
                for _ in pairs(pool) do deep = deep + 1 end
            end
        end
        return count, deep
    end }
end
local iconCounter = 0
local updateTicker = nil

-- TAINT SAFETY: Blizzard CD mirror state tracked in a weak-keyed table.
-- Maps Blizzard CooldownFrame → { icon = quiIcon, hooked = bool } so mirror
-- hooks can forward SetCooldown/SetCooldownFromDurationObject calls to the
-- addon-owned CooldownFrame without writing to the Blizzard frame.
local blizzCDState = setmetatable({}, { __mode = "k" })

-- TAINT SAFETY: Blizzard Icon texture hook state tracked in a weak-keyed table.
-- Maps Blizzard child Icon regions → { icon = quiIcon } so the SetTexture hook
-- can mirror texture changes to the addon-owned icon without reading restricted
-- frames during combat.
local blizzTexState = setmetatable({}, { __mode = "k" })

-- Minimal state for reparented Blizzard stack/charge frames.
-- Maps _blizzChild → { icon, blizzChild }.  The native ChargeCount and
-- Applications frames are reparented onto our CDM icons and Blizzard
-- manages SetText/Show/Hide natively — no hook forwarding needed.
local blizzStackState = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- DEBUG: Charge/stack transform debugging.
-- Enable via:  /run QUI_CDM_CHARGE_DEBUG = true
-- Disable via: /run QUI_CDM_CHARGE_DEBUG = false
-- Optionally filter to a specific spell name:
--   /run QUI_CDM_CHARGE_DEBUG = "Holy Bulwark"
---------------------------------------------------------------------------
local _chargeDebugThrottle = {}  -- [key] = lastTime
local function ChargeDebug(spellName, ...)
    if not _G.QUI_CDM_CHARGE_DEBUG then return end
    -- If debug is a string, only log that spell
    local filter = _G.QUI_CDM_CHARGE_DEBUG
    if type(filter) == "string" and spellName and not spellName:find(filter) then return end
    -- Throttle tick-based messages to 1 per second per spell+tag combo
    local tag = select(1, ...) or ""
    if tag == "FWD path:" or tag == "SKIP API path:" or tag == "API path:" or tag == "FWD path CLEAR:"
        or tag == "DESAT GCD bail:" or tag == "DESAT charged check:" or tag == "DESAT result:"
        or tag == "MIRROR hook:" then
        local key = (spellName or "") .. tag
        local now = GetTime()
        if _chargeDebugThrottle[key] and now - _chargeDebugThrottle[key] < 1 then return end
        _chargeDebugThrottle[key] = now
    end
    local parts = { "|cff34D399[CDM-Charge]|r", spellName or "?", "-" }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if issecretvalue and issecretvalue(v) then
            parts[#parts + 1] = "<secret>"
        else
            parts[#parts + 1] = tostring(v)
        end
    end
    print(table.concat(parts, " "))
end

---------------------------------------------------------------------------
-- PER-TICK CACHES: wiped at the start of each UpdateAllCooldowns batch.
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

local function ClearUpdateTickCaches()
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

local function BeginUpdateTickCaches(forceClear)
    if forceClear or not InCombatLockdown() then
        ClearUpdateTickCaches()
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

local function TickCacheGetCharges(spellID)
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
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID) or nil
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

local function TickCacheGetCooldown(spellID)
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
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    _tickCooldownCache[spellID] = cdInfo or false
    _tickCooldownCacheTime[spellID] = now
    return cdInfo
end

local function TickCacheGetDuration(spellID)
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

local function TickCacheGetChargeDuration(spellID)
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

local function TickCacheGetOverrideSpell(spellID)
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
    local overrideID = C_Spell.GetOverrideSpell(spellID)
    if overrideID and IsSecretValue(overrideID) then
        return overrideID
    end
    _tickOverrideCache[spellID] = overrideID or false
    _tickOverrideCacheTime[spellID] = now
    return overrideID
end

local function TickCacheGetDisplayCount(spellID)
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
    if result and IsSecretValue(result) then
        return result
    end
    _tickDisplayCountCache[spellID] = result or false
    _tickDisplayCountCacheTime[spellID] = now
    return result
end


---------------------------------------------------------------------------
-- DYNAMIC CHILD LOOKUP: Scan ALL viewer children to find the one with
-- auraInstanceID matching a tracked spell.  Blizzard recycles children
-- across auras, so the child→spell assignment changes at runtime.
-- Child lookup infrastructure lives in cdm_spelldata.lua (shared by icons + bars).
-- Local wrappers for hot-path performance.
---------------------------------------------------------------------------
local function FindChildForSpell(id1, id2, id3)
    return ns.CDMSpellData.FindChildForSpell(id1, id2, id3)
end
local function FindBuffChildForSpell(viewerType, id1, id2, id3)
    return ns.CDMSpellData.FindBuffChildForSpell(viewerType, id1, id2, id3)
end

local function IsTotemSlotEntry(entry)
    return entry and entry._isTotemInstance and entry._totemSlot ~= nil
end

local DumpDebugIcon

local function QueueTotemSlotRebuild(icon, entry, r)
    if not icon or icon._pendingTotemSlotRefresh then return end
    if not entry or IsTotemSlotEntry(entry) then return end
    if entry.viewerType ~= "buff" then return end

    local child = (r and (r.blizzChild or r.blizzBarChild)) or entry._blizzChild or entry._blizzBarChild
    local pref = child and rawget(child, "preferredTotemUpdateSlot")
    local hasExplicitSlotSignal = pref ~= nil and not Helpers.IsSecretValue(pref) and tonumber(pref) ~= nil
    local shouldRebuild = (r and r.isTotemInstance and r.totemSlot) or hasExplicitSlotSignal
    if not shouldRebuild then
        return
    end

    icon._pendingTotemSlotRefresh = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if _G.QUI_OnBuffDataChanged then
                _G.QUI_OnBuffDataChanged()
            elseif _G.QUI_OnSpellDataChanged then
                _G.QUI_OnSpellDataChanged()
            elseif _G.QUI_RefreshNCDM then
                _G.QUI_RefreshNCDM()
            end
        end)
    end
end

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetLegacyCustomData(trackerKey)
    if QUICore and QUICore.db and QUICore.db.char and QUICore.db.char.ncdm
        and QUICore.db.char.ncdm[trackerKey] and QUICore.db.char.ncdm[trackerKey].customEntries then
        return QUICore.db.char.ncdm[trackerKey].customEntries
    end
    return nil
end

local function GetCustomData(trackerKey)
    if type(trackerKey) ~= "string" or trackerKey == "" then
        return nil
    end

    if Helpers and Helpers.GetNCDMCustomEntries then
        local activeData = Helpers.GetNCDMCustomEntries(trackerKey)
        if activeData then
            return activeData
        end
    end

    return GetLegacyCustomData(trackerKey)
end

---------------------------------------------------------------------------
-- TEXTURE HELPERS
---------------------------------------------------------------------------
-- Persistent texture cache: spellID→iconID rarely changes (only on talent
-- swap / spec change), so we keep it across ticks.  Wiped on SPELLS_CHANGED
-- and PLAYER_SPECIALIZATION_CHANGED to pick up new icons.
local _textureCycleCache = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "CDM_textureCycleCache", tbl = _textureCycleCache } end

local function GetSpellTexture(spellID)
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
local function ResolveMacro(entry)
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

local function GetEntryTexture(entry)
    if not entry then return nil end
    if entry.type == "macro" then
        local resolvedID, resolvedType, fallbackTex = ResolveMacro(entry)
        if resolvedID then
            if resolvedType == "item" then
                local _, _, _, _, icon = C_Item.GetItemInfoInstant(resolvedID)
                return icon
            else
                return GetSpellTexture(resolvedID)
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
    return GetSpellTexture(entry.overrideSpellID or entry.id)
end

---------------------------------------------------------------------------
-- COOLDOWN RESOLUTION
-- Ported from cdm_custom.lua:116-181 (GetBestSpellCooldown)
---------------------------------------------------------------------------
-- Zero-allocation cooldown resolution: no table, no closure per call.
-- This function is called once per cooldown icon per tick (~12-24x per cycle).
-- Consider logic is fully inlined to avoid closure overhead.
-- Extract a DurationObject from a cooldown info table if the API provides one.
-- 12.0.5+ may expose DurationObjects on SpellCooldownInfo/SpellChargeInfo.
-- Field names are probed defensively; returns nil when unavailable.
local function ExtractCooldownDurObj(info)
    if not info then return nil end
    local obj = info.cooldownDurationObject or info.durationObject
    if obj and type(obj) == "table" then return obj end
    return nil
end

-- Evaluate a single SpellCooldownInfo/SpellChargeInfo result and accumulate
-- into the best safe numeric values, secret fallbacks, and DurationObject.
local function AccumulateCooldown(st, dur, info, bestStart, bestDur, secStart, secDur, bestDurObj)
    local durObj = ExtractCooldownDurObj(info)
    if IsSecretValue(st) or IsSecretValue(dur) then
        if not secStart then secStart, secDur = st, dur end
        -- Secret path: take any durObj as fallback
        if durObj and not bestDurObj then bestDurObj = durObj end
    elseif IsSafeNumeric(st) and IsSafeNumeric(dur) and dur > 0 then
        if not bestDur or dur > bestDur then
            bestStart, bestDur = st, dur
            -- Always sync durObj with the longest duration — even if
            -- this source has no durObj (nil clears a stale one from a
            -- shorter cooldown like GCD, so Priority 2 numeric values
            -- are used instead of the wrong DurationObject).
            bestDurObj = durObj
        elseif not bestDurObj and durObj then
            bestDurObj = durObj  -- any durObj is better than none
        end
    end
    return bestStart, bestDur, secStart, secDur, bestDurObj
end

local function GetBestSpellCooldown(spellID)
    if not spellID then return nil, nil, nil end

    local bestStart, bestDuration = nil, nil
    local secretStart, secretDuration = nil, nil
    local bestDurObj = nil
    local isActive = false

    -- Check primary spell (per-tick cached)
    local cdInfo = TickCacheGetCooldown(spellID)
    if cdInfo then
        bestStart, bestDuration, secretStart, secretDuration, bestDurObj =
            AccumulateCooldown(cdInfo.startTime, cdInfo.duration, cdInfo,
                bestStart, bestDuration, secretStart, secretDuration, bestDurObj)
    end
    local chargeInfo = TickCacheGetCharges(spellID)
    if chargeInfo then
        -- Use the new non-secret isActive boolean (12.0.5+) which is true
        -- when maxCharges > 1 AND currentCharges < maxCharges AND the
        -- recharge timer is running.  Falls back to manual comparison for
        -- older API versions.  isActive is non-secret even in combat,
        -- fixing charge detection that failed with secret currentCharges.
        local chargeActive = chargeInfo.isActive == true
        if chargeActive then
            bestStart, bestDuration, secretStart, secretDuration, bestDurObj =
                AccumulateCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo,
                    bestStart, bestDuration, secretStart, secretDuration, bestDurObj)
        end
    end

    -- Check override spell (no table allocation — just a second ID)
    if C_Spell.GetOverrideSpell then
        local overrideID = TickCacheGetOverrideSpell(spellID)
        -- overrideID may be secret in combat — guard the comparison.
        local isOverridden = false
        if overrideID and not IsSecretValue(overrideID) then
            isOverridden = overrideID ~= spellID
        end
        if isOverridden then
            cdInfo = TickCacheGetCooldown(overrideID)
            if cdInfo then
                bestStart, bestDuration, secretStart, secretDuration, bestDurObj =
                    AccumulateCooldown(cdInfo.startTime, cdInfo.duration, cdInfo,
                        bestStart, bestDuration, secretStart, secretDuration, bestDurObj)
            end
            chargeInfo = TickCacheGetCharges(overrideID)
            if chargeInfo then
                local chargeActive2 = chargeInfo.isActive == true
                if chargeActive2 then
                    bestStart, bestDuration, secretStart, secretDuration, bestDurObj =
                        AccumulateCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo,
                            bestStart, bestDuration, secretStart, secretDuration, bestDurObj)
                end
            end
        end
    end

    -- isActive: non-secret boolean from cooldown APIs (12.0.5+).
    if cdInfo and cdInfo.isActive ~= nil then
        isActive = cdInfo.isActive == true
    end
    if chargeInfo and chargeInfo.isActive == true then
        isActive = true
    end

    -- DurationObject APIs (12.0+, secret-safe). These are the only
    -- authoritative spell timing source we forward to owned cooldowns.
    -- Gate queries behind the non-secret isActive signal so zero-span
    -- ready-state objects do not drive false cooldown renders.
    if not bestDurObj and isActive then
        -- Check charge duration FIRST — for charged spells, the charge
        -- recharge DurationObject is what we want to display, not the
        -- spell's own cooldown DurationObject (which may be a shorter
        -- per-use CD or GCD).  GetSpellChargeDuration returns the
        -- recharge timer DurationObject, secret-safe for combat.
        bestDurObj = TickCacheGetChargeDuration(spellID)
        if not bestDurObj and C_Spell.GetOverrideSpell and C_Spell.GetSpellChargeDuration then
            local overrideID = TickCacheGetOverrideSpell(spellID)
            if overrideID and not IsSecretValue(overrideID) and overrideID ~= spellID then
                bestDurObj = TickCacheGetChargeDuration(overrideID)
            end
        end
        -- Fall back to spell cooldown duration (non-charged spells, per-tick cached)
        if not bestDurObj then
            bestDurObj = TickCacheGetDuration(spellID)
        end
        if not bestDurObj and C_Spell.GetOverrideSpell then
            local overrideID = TickCacheGetOverrideSpell(spellID)
            if overrideID and not IsSecretValue(overrideID) and overrideID ~= spellID then
                bestDurObj = TickCacheGetDuration(overrideID)
            end
        end
    end
    -- Discard DurationObjects extracted from cdInfo when no source confirms
    -- an active cooldown.  12.0.5+ cooldown info tables may carry zero-span
    -- DurationObjects for ready-to-use spells.
    if not isActive then
        bestDurObj = nil
    end

    if bestDurObj then
        return nil, nil, bestDurObj, isActive
    end

    return nil, nil, nil, isActive
end

-- Item cooldown resolution
local function GetItemCooldown(itemID)
    if not itemID or not C_Item.GetItemCooldown then return nil, nil, nil end
    local startTime, duration = C_Item.GetItemCooldown(itemID)
    if IsSecretValue(startTime) or IsSecretValue(duration) then
        -- Secret values can no longer be forwarded via SetCooldown (12.0.5+).
        -- No DurationObject API exists for items; graceful degradation.
        return nil, nil, nil
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) or duration <= 0 then
        return nil, nil, nil
    end
    return startTime, duration, nil
end

local function GetSlotCooldown(slotID)
    if not slotID or not GetInventoryItemCooldown then return nil, nil, nil end
    local startTime, duration, enabled = GetInventoryItemCooldown("player", slotID)
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) then
        return nil, nil, nil
    end
    if enabled ~= 1 or duration <= 1.5 then
        return nil, nil, nil
    end
    return startTime, duration, nil
end

local function ApplyResolvedCooldown(cd, startTime, duration, durObj, reverse)
    return ApplyCooldownFromStart(cd, durObj, startTime, duration, nil, reverse)
end

local function CooldownHasExpiredNow(startTime, duration, durObj, now)
    -- Never inspect DurationObject state in Lua during combat. Secret values
    -- must be forwarded directly to C-side APIs; expiry decisions here are
    -- limited to safe numeric cooldown payloads only.
    if IsSafeNumeric(startTime) and IsSafeNumeric(duration) and duration > 0 then
        return ((startTime + duration) - (now or GetTime())) <= 0.02
    end
    return false
end

local function HasRealCooldownState(icon, entry, duration, apiIsActive, mirrorActive, blizzRealCooldownActive)
    if not icon or not entry then
        return false
    end

    if icon._auraActive or entry.viewerType == "buff" then
        return false
    end

    if blizzRealCooldownActive then
        return true
    end

    if icon._showingRealCooldownSwipe then
        return true
    end

    if entry.hasCharges then
        return apiIsActive == true
    end

    if mirrorActive then
        return true
    end

    if IsSafeNumeric(icon and icon._lastStart) and IsSafeNumeric(icon and icon._lastDuration)
        and icon._lastStart > 0 and icon._lastDuration > 0 then
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

-- Expose for external use
CDMIcons.GetBestSpellCooldown = GetBestSpellCooldown
CDMCooldown.GetBestSpellCooldown = GetBestSpellCooldown
CDMCooldown.GetItemCooldown = GetItemCooldown
CDMCooldown.GetSlotCooldown = GetSlotCooldown
CDMCooldown.ApplyResolvedCooldown = ApplyResolvedCooldown

---------------------------------------------------------------------------
-- SWIPE STYLING
---------------------------------------------------------------------------

-- Re-apply QUI swipe styling to the addon-owned CooldownFrame.
local function ReapplySwipeStyle(cd, icon)
    if not cd then return end
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    local CooldownSwipe = QUI.CooldownSwipe
    if CooldownSwipe and CooldownSwipe.ApplyToIcon then
        CooldownSwipe.ApplyToIcon(icon)
    end
end

local function IsGCDSwipeEnabled()
    local swipe = ns._OwnedSwipe
    local settings = swipe and swipe.GetSettings and swipe.GetSettings()
    return settings and settings.showGCDSwipe == true
end

local function GetIconCooldownIdentifier(icon)
    local entry = icon and icon._spellEntry
    if not entry then return nil end
    -- Resolve from BASE spell at runtime so dynamic transforms are current
    local base = entry.spellID or entry.id
    if base and C_Spell.GetOverrideSpell then
        local ovId = TickCacheGetOverrideSpell(base)
        if ovId then return ovId end
    end
    return base
end

local function RefreshIconGCDState(icon)
    local sid = GetIconCooldownIdentifier(icon)
    if not sid or not C_Spell or not C_Spell.GetSpellCooldown then return end

    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, sid)
    if ok and cdInfo and not IsSecretValue(cdInfo.isOnGCD) then
        icon._isOnGCD = cdInfo.isOnGCD or false
    end
end

local function SyncMirroredCooldownState(icon, blizzCD, fallbackActive)
    if not icon then
        return
    end

    if not blizzCD or not blizzCD.GetCooldownTimes then
        if fallbackActive ~= nil then
            icon._hasCooldownActive = fallbackActive
        end
        return
    end

    local ok, rawStart, rawDuration, isEnabled = pcall(blizzCD.GetCooldownTimes, blizzCD)
    if not ok or IsSecretValue(rawStart) or IsSecretValue(rawDuration) then
        if fallbackActive ~= nil then
            icon._hasCooldownActive = fallbackActive
        end
        return
    end

    local start = (type(rawStart) == "number") and rawStart or nil
    local duration = (type(rawDuration) == "number") and rawDuration or nil
    if not start or not duration then
        if fallbackActive ~= nil then
            icon._hasCooldownActive = fallbackActive
        end
        return
    end

    if start > 100000 or duration > 100000 then
        start = start / 1000
        duration = duration / 1000
    end

    local enabled = true
    if isEnabled ~= nil and not IsSecretValue(isEnabled) then
        enabled = (isEnabled ~= 0 and isEnabled ~= false)
    end

    icon._lastStart = start
    icon._lastDuration = duration
    if duration == 0 or not enabled then
        icon._lastStart = 0
        icon._lastDuration = 0
    end
    icon._hasCooldownActive = enabled and start > 0 and duration > 0
end

local function MirrorCurrentBlizzCooldown(icon, blizzCD)
    local addonCD = icon and icon.Cooldown
    if not addonCD or not blizzCD then return false end

    local synced = false
    -- Pull the spell's DurationObject from C_Spell.GetSpellCooldownDuration —
    -- the secret-safe authority. blizzCD:GetCooldownDuration returns a number
    -- (secret in combat), not a DurationObject, so it cannot be forwarded to
    -- SetCooldownFromDurationObject from tainted code.
    if addonCD.SetCooldownFromDurationObject and C_Spell and C_Spell.GetSpellCooldownDuration then
        local entry = icon and icon._spellEntry
        local sid = icon and icon._runtimeSpellID
            or (entry and (entry.spellID or entry.overrideSpellID or entry.id))
        if sid then
            local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, sid)
            if okDur and durObj then
                synced = pcall(addonCD.SetCooldownFromDurationObject, addonCD, durObj) and true or false
            end
        end
    end

    if synced then
        icon._durObjHookSync = GetTime()
        icon._showingGCDSwipe = nil
        icon._showingRealCooldownSwipe = true
        SyncMirroredCooldownState(icon, blizzCD, true)
        RefreshIconGCDState(icon)
        return true
    end

    if blizzCD.GetCooldownTimes then
        local ok, rawStart, rawDuration, isEnabled = pcall(blizzCD.GetCooldownTimes, blizzCD)
        if ok and not IsSecretValue(rawStart) and not IsSecretValue(rawDuration) then
            local start = (type(rawStart) == "number") and rawStart or nil
            local duration = (type(rawDuration) == "number") and rawDuration or nil
            local enabled = true

            if isEnabled ~= nil and not IsSecretValue(isEnabled) then
                enabled = (isEnabled ~= 0 and isEnabled ~= false)
            end

            if start and duration then
                if start > 100000 or duration > 100000 then
                    start = start / 1000
                    duration = duration / 1000
                end

                if enabled and start > 0 and duration > 0 then
                    synced = ApplyResolvedCooldown(addonCD, start, duration, nil, false)
                elseif duration == 0 or not enabled then
                    addonCD:Clear()
                    synced = true
                end
            end
        end
    end

    SyncMirroredCooldownState(icon, blizzCD, synced)
    RefreshIconGCDState(icon)
    return synced
end

local function GetBlizzCooldownPayload(blizzCD)
    if not blizzCD then
        return nil, nil, nil
    end

    -- Cooldown:GetCooldownDuration returns a number (secret in combat), not a
    -- DurationObject — passing it to SetCooldownFromDurationObject silently
    -- no-ops. Use C_Spell.GetSpellCooldownDuration upstream for the
    -- DurationObject; this helper now only surfaces the numeric snapshot.
    if blizzCD.GetCooldownTimes then
        local okTimes, rawStart, rawDuration = pcall(blizzCD.GetCooldownTimes, blizzCD)
        if okTimes and not IsSecretValue(rawStart) and not IsSecretValue(rawDuration) then
            local start = (type(rawStart) == "number") and rawStart or nil
            local duration = (type(rawDuration) == "number") and rawDuration or nil
            if start and duration then
                if start > 100000 or duration > 100000 then
                    start = start / 1000
                    duration = duration / 1000
                end
                return start, duration, nil
            end
        end
    end

    return nil, nil, nil
end

-- Keep CooldownFrame ready-flash ("bling") hidden when icon is effectively invisible.
-- This prevents GCD-ready glow from leaking through when row/container alpha is 0.
local function SyncCooldownBling(icon)
    if not icon or not icon.Cooldown or not icon.Cooldown.SetDrawBling then return end
    local effectiveAlpha = SafeToNumber((icon.GetEffectiveAlpha and icon:GetEffectiveAlpha()) or icon:GetAlpha(), 1)
    local shouldDrawBling = (effectiveAlpha > 0.001) and icon:IsShown()
    if icon._drawBlingEnabled ~= shouldDrawBling then
        icon._drawBlingEnabled = shouldDrawBling
        icon.Cooldown:SetDrawBling(shouldDrawBling)
    end
end

---------------------------------------------------------------------------
-- BLIZZARD COOLDOWN MIRRORING
-- Instead of reparenting Blizzard's CooldownFrame onto our icon (which
-- taints it and causes isActive / wasOnGCDLookup errors in
-- Blizzard_CooldownViewer), we leave the Blizzard CooldownFrame
-- untouched and mirror its updates to our addon-owned CooldownFrame
-- via hooksecurefunc.  The hooks receive the same parameters Blizzard
-- passes (including secret values during combat) and forward them to
-- the addon CD's C-side SetCooldown/SetCooldownFromDurationObject,
-- which handles secret values natively.
---------------------------------------------------------------------------
local function MirrorBlizzCooldown(icon, blizzChild)
    if not blizzChild or not blizzChild.Cooldown then return end
    local blizzCD = blizzChild.Cooldown

    -- TAINT SAFETY: Track CD→icon association in a weak-keyed table.
    local state = blizzCDState[blizzCD]
    if not state then
        state = {}
        blizzCDState[blizzCD] = state
    end
    state.icon = icon

    -- The addon-created CooldownFrame stays as icon.Cooldown (the display).
    -- Style it to match QUI defaults.
    local addonCD = icon.Cooldown
    addonCD:SetDrawSwipe(true)
    addonCD:SetHideCountdownNumbers(false)
    addonCD:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    addonCD:SetSwipeColor(0, 0, 0, 0.8)
    addonCD:Show()

    -- Track the Blizzard CD reference for cleanup
    icon._blizzCooldown = blizzCD

    -- Install mirror hooks (once per Blizzard CD, survives re-assignment).
    -- These forward Blizzard's cooldown updates to the addon-owned
    -- CooldownFrame WITHOUT writing to the Blizzard frame at all.
    if not state.hooked then
        state.hooked = true

        if blizzCD.SetCooldownFromDurationObject then
            hooksecurefunc(blizzCD, "SetCooldownFromDurationObject", function(self, durationObj)
                local s = blizzCDState[self]
                if not s or s.bypass then return end
                local targetIcon = s.icon
                if not targetIcon then return end
                -- Stale mapping guard: if the icon's entry now references a
                -- different Blizzard child, this hook is orphaned.
                local tEntry = targetIcon._spellEntry
                if tEntry and tEntry._blizzChild and tEntry._blizzChild.Cooldown ~= self then

                    return
                end

                -- Mirror to addon-owned CD.
                -- Skip forwarding for charged entries — Blizzard's viewer
                -- sends zero-span DurationObjects when the spell is usable
                -- (isActive=false), which clears the addon CooldownFrame
                -- and overwrites the API's charge recharge swipe.  The API
                -- path (GetBestSpellCooldown + isActive) handles charged
                -- cooldowns correctly without mirror interference.
                -- Also skip when the icon is in aura-active mode — the tick
                -- function drives the aura swipe via ResolveAuraState and
                -- forwarding the cooldown DurationObject would overwrite it.
                local cd = targetIcon.Cooldown
                local tSkipCharge = tEntry and tEntry.hasCharges
                local tSkipAura = targetIcon._auraActive
                RefreshIconGCDState(targetIcon)

                if not tSkipCharge and not tSkipAura and cd and cd.SetCooldownFromDurationObject then
                    pcall(cd.SetCooldownFromDurationObject, cd, durationObj)
                    -- Track that this hook successfully forwarded a DurationObject
                    -- so the API path can skip competing CooldownFrame writes.
                    targetIcon._durObjHookSync = GetTime()
                    targetIcon._showingGCDSwipe = nil
                    targetIcon._showingRealCooldownSwipe = true
                end
                ChargeDebug(tEntry and tEntry.name, "MIRROR hook: tSkipCharge=", tSkipCharge,
                    "tSkipAura=", tSkipAura,
                    "_hasCooldownActive=", targetIcon._hasCooldownActive)

                if not tSkipCharge and not tSkipAura then
                    SyncMirroredCooldownState(targetIcon, self, true)
                end

                ReapplySwipeStyle(cd, targetIcon)
            end)
        end

        hooksecurefunc(blizzCD, "SetCooldown", function(self, start, duration)
            local s = blizzCDState[self]
            if not s or s.bypass then return end
            local targetIcon = s.icon
            if not targetIcon then return end
            -- Stale mapping guard
            local tEntry = targetIcon._spellEntry
            if tEntry and tEntry._blizzChild and tEntry._blizzChild.Cooldown ~= self then

                return
            end

            -- Swipe is driven by UpdateIconCooldown via the override chain
            -- (GetOverrideSpell → GetSpellCooldown/Duration).  The hook
            -- only needs to refresh GCD state — no CooldownFrame writes.
            RefreshIconGCDState(targetIcon)
        end)

        -- No SetAllPoints/SetPoint/SetParent hooks: the Blizzard
        -- CooldownFrame stays on its original parent frame.  Nothing
        -- to guard against re-anchoring because we never moved it.
    end

    -- Initial cooldown sync: on reload, the Blizzard CD may already have
    -- an active cooldown running. Forward its current state to the addon CD
    -- so swipe/countdown display correctly without waiting for the next update.
    local addonCD = icon.Cooldown
    if addonCD then
        MirrorCurrentBlizzCooldown(icon, blizzCD)
        -- Mirror reverse state (aura timers show reversed swipe)
        local okR, isReversed = pcall(blizzCD.GetReverse, blizzCD)
        if okR and not IsSecretValue(isReversed) then
            pcall(addonCD.SetReverse, addonCD, isReversed)
        end
        ReapplySwipeStyle(addonCD, icon)
    end
end

local function UnmirrorBlizzCooldown(icon)
    if not icon._blizzCooldown then return end

    -- Disconnect hook references (hooks become no-ops via nil check)
    local state = blizzCDState[icon._blizzCooldown]
    if state then state.icon = nil end

    -- No reparenting to undo — the Blizzard CD was never moved.
    icon._blizzCooldown = nil
    icon._auraActive = nil
    icon._auraUnit = nil
end

---------------------------------------------------------------------------
-- BLIZZARD ICON TEXTURE HOOK
-- Mirrors texture changes from Blizzard's hidden viewer Icon to our
-- addon-owned icon via a SetTexture hook.  Spell replacements (e.g.,
-- Judgment → Hammer of Wrath when Wake of Ashes is active) update the
-- Blizzard child's Icon; the hook forwards those changes immediately
-- without reading restricted frame properties during combat.
---------------------------------------------------------------------------
local function HookBlizzTexture(icon, blizzChild)
    if not blizzChild then return end
    local iconRegion = blizzChild.Icon or blizzChild.icon
    if not iconRegion then return end
    -- Bar viewer children have .Icon as a Frame containing .Icon (Texture).
    -- Resolve to the actual Texture region for hooking.
    if not iconRegion.SetTexture then
        local nested = iconRegion.Icon
        if nested and nested.SetTexture then
            iconRegion = nested
        else
            return  -- no hookable texture region
        end
    end

    -- Update the mapping (may point to a different QUI icon after pool recycle)
    local state = blizzTexState[iconRegion]
    if not state then
        state = {}
        blizzTexState[iconRegion] = state
    end
    state.icon = icon

    -- Install hooks once per Blizzard texture region
    if not state.hooked then
        state.hooked = true
        hooksecurefunc(iconRegion, "SetTexture", function(self, texture)
            local s = blizzTexState[self]
            if not s or not s.icon then return end
            local quiIcon = s.icon
            -- Stale mapping guard: if the icon's entry now references a
            -- different Blizzard child, this hook is orphaned — skip to
            -- prevent cross-icon texture contamination when Blizzard
            -- recycles viewer children.
            local tEntry = quiIcon._spellEntry
            if tEntry and tEntry._blizzChild then
                local curRegion = tEntry._blizzChild.Icon or tEntry._blizzChild.icon
                -- Resolve nested texture for bar viewer children
                if curRegion and not curRegion.SetTexture and curRegion.Icon then
                    curRegion = curRegion.Icon
                end
                if curRegion ~= self then return end
            end
            -- Skip when the icon has a resolved desired texture — the Blizzard
            -- child may use a different icon (e.g., debuff instead of ability).
            if quiIcon._desiredTexture then return end
            -- Block debuff texture bleed on non-aura cooldown entries.
            -- When an ability applies a DOT (e.g. Outbreak → Dread Plague),
            -- Blizzard sets wasSetFromAura on the viewer child and updates
            -- the Icon texture to the debuff icon.  For non-aura cooldown
            -- entries (essential/utility), block this — the user wants the
            -- ability icon, not the debuff icon.  For aura entries and spell
            -- override transitions (wasSetFromAura = false), forward normally.
            if tEntry and not tEntry.isAura and tEntry._blizzChild then
                local child = tEntry._blizzChild
                -- wasSetFromAura is a secret value in combat — type() returns
                -- "number" not "boolean".  Use truthiness check instead.
                if child.wasSetFromAura then
                    return
                end
            end
            if quiIcon.Icon and texture then
                -- Detect spell override transitions (e.g., Wake of Ashes →
                -- Hammer of Light).  When texture changes, the spell has
                -- transformed — clear cached DurationObject to force a swipe
                -- refresh so the new spell's cooldown state is shown.
                -- Forward texture to our icon (C-side handles secret values).
                -- Texture may be secret in combat — no Lua comparisons.
                pcall(quiIcon.Icon.SetTexture, quiIcon.Icon, texture)
            end
        end)

        -- Desaturation is now driven solely by UpdateIconCooldown's
        -- desaturation block, which uses _isOnGCD + DurationObject remaining
        -- to filter GCD from real cooldowns.  The mirror hook was forwarding
        -- Blizzard's GCD-driven desaturation toggles, causing flickering.
        -- Intentionally removed: no SetDesaturated forwarding.
    end
end

local function UnhookBlizzTexture(icon)
    local entry = icon._spellEntry
    if not entry or not entry._blizzChild then return end
    local iconRegion = entry._blizzChild.Icon or entry._blizzChild.icon
    if not iconRegion then return end
    -- Resolve nested texture for bar viewer children
    if not iconRegion.SetTexture and iconRegion.Icon then
        iconRegion = iconRegion.Icon
    end
    local state = blizzTexState[iconRegion]
    if state then state.icon = nil end
end

---------------------------------------------------------------------------
-- BLIZZARD STACK/CHARGE TEXT HOOK
-- Mirrors charge counts and application stacks from Blizzard's hidden
-- viewer children to our addon-owned icon.StackText via hooksecurefunc.
-- Polling IsShown()/GetText() is unreliable — child frames under hidden
-- Blizzard viewers may return secret values during combat.  Hook parameters
-- come from Blizzard's secure calling code and are clean.
-- No initial seeding — hooks fire when Blizzard
-- first updates the frames (next charge/aura change after BuildIcons).
---------------------------------------------------------------------------


local function HookTextHasDisplay(text)
    if text == nil then return false end
    local ok, isEmpty = pcall(function() return text == "" end)
    return (not ok) or (not isEmpty)
end

local function ClearAuraHookStackText(entry, icon)
    local child = entry and entry._blizzChild
    local state = child and blizzStackState[child]
    if state and (not icon or state.icon == icon) then
        state.auraText = nil
    end
end

local function ForwardAuraHookStackText(blizzChild, text, source)
    local state = blizzStackState[blizzChild]
    if not state or not state.icon then return end
    local icon = state.icon
    local entry = icon and icon._spellEntry
    -- Allow forwarding when the entry is in an aura container OR when the
    -- QUI container is cooldown-typed but the actual blizzChild lives in
    -- a buff viewer (e.g. Mana Tea on a custom cooldown container).
    local cooldownWithBuffChild = entry and not UsesAPIAuraStackText(entry)
        and IsBuffViewerChild(blizzChild)
    if not HookTextHasDisplay(text) then
        if not InCombatLockdown() then
            state.auraText = nil
        end
        -- Cooldown-container icons stay visible after the aura drops, so
        -- we must actively clear the addon StackText — the icon won't be
        -- hidden by aura-state changes the way aura-container icons are.
        if cooldownWithBuffChild and icon and icon.StackText and not InCombatLockdown() then
            pcall(icon.StackText.SetText, icon.StackText, "")
            pcall(icon.StackText.Hide, icon.StackText)
        end
        return
    end
    if not entry or entry._blizzChild ~= blizzChild then return end
    if not UsesAPIAuraStackText(entry) and not cooldownWithBuffChild then return end
    if not icon.StackText then return end

    if pcall(icon.StackText.SetText, icon.StackText, text) then
        state.auraText = text
        state.lastHookTime = GetTime()
        pcall(icon.StackText.Show, icon.StackText)
        ChargeDebug(entry.name, "AURA HOOK", source or "text", "text=", text)
    end
end

--- Check whether Blizzard/native hook text is actively displaying on this
--- icon.  When true, API-based stack writes in UpdateIconCooldown should
--- yield so they do not overwrite clean hook arguments in the same frame.
local function IsHookStackActive(entry, icon)
    if not entry or not entry._blizzChild then return false end
    local child = entry._blizzChild
    if UsesAPIAuraStackText(entry) then
        local state = blizzStackState[child]
        return icon and icon._auraActive and state and state.icon == icon and state.auraText ~= nil
    end
    -- Cooldown container backed by a buff-viewer child: stacks come from
    -- the API hook path (ForwardAuraHookStackText), not from reparented
    -- native frames.  Hook is "active" whenever it has driven a non-empty
    -- text into our StackText for this icon.
    if IsBuffViewerChild(child) then
        local state = blizzStackState[child]
        return state and state.icon == icon and state.auraText ~= nil
    end
    local textOverlay = icon.TextOverlay
    if not textOverlay then return false end
    -- If we reparented ChargeCount or Applications onto our TextOverlay,
    -- Blizzard's native stack display is driving this icon.
    if child.ChargeCount and child.ChargeCount:GetParent() == textOverlay then return true end
    if child.Applications and child.Applications:GetParent() == textOverlay then return true end
    return false
end

local function HookBlizzStackText(icon, blizzChild)
    if not blizzChild then return end

    local entry = icon._spellEntry
    local chargeFrame = blizzChild.ChargeCount
    local appFrame = blizzChild.Applications

    -- Aura containers OR cooldown containers backed by a buff-viewer child:
    -- do NOT reparent Applications/ChargeCount. Blizzard's buff-viewer display
    -- layer doesn't reliably drive these frames the way cooldown viewer
    -- templates do, so reparenting can leave counts blank.  This is decided
    -- by the actual child's viewer, not the QUI container type — Mana Tea on
    -- a custom cooldown container still resolves to a buff viewer child via
    -- ResolveOwnedEntry's score and would lose its stacks under reparenting.
    -- Leave the native frames on their original parent, but hook their SetText
    -- calls so clean Blizzard arguments can drive icon.StackText directly.
    if UsesHookStackText(entry, blizzChild) then
        local state = blizzStackState[blizzChild]
        if not state then
            state = {}
            blizzStackState[blizzChild] = state
        end
        if state.icon ~= icon then
            state.auraText = nil
        end
        state.icon = icon
        state.blizzChild = blizzChild

        if not state.auraHooked then
            state.auraHooked = true
            -- Hook ChargeCount.Current for charge-style stacks (multi-charge
            -- spells whose Blizzard child still tracks chargeCount).  For
            -- buff-viewer-backed cooldown containers we don't gate on
            -- entry.hasCharges since the buff viewer may write to either
            -- ChargeCount or Applications depending on the spell.
            local hookCharge = (entry and entry.hasCharges) or IsBuffViewerChild(blizzChild)
            if hookCharge and chargeFrame and chargeFrame.Current then
                hooksecurefunc(chargeFrame.Current, "SetText", function(_, text)
                    ForwardAuraHookStackText(blizzChild, text, "ChargeCount")
                end)
            end
            if appFrame and appFrame.Applications then
                hooksecurefunc(appFrame.Applications, "SetText", function(_, text)
                    ForwardAuraHookStackText(blizzChild, text, "Applications")
                end)
            end
        end

        ChargeDebug(entry and entry.name, "HookBlizzStackText AURA ASSIGN",
            "spellID=", entry and entry.spellID, "overrideSpellID=", entry and entry.overrideSpellID,
            "hasCharges=", entry and entry.hasCharges,
            "buffViewerChild=", IsBuffViewerChild(blizzChild),
            "child.cooldownChargesCount=", blizzChild.cooldownChargesCount,
            "ChargeCount=", chargeFrame and "exists" or "nil",
            "Applications=", appFrame and "exists" or "nil")
        return
    end

    -- Reparent and style Blizzard's native ChargeCount and Applications
    -- frames onto our CDM icon.  Blizzard manages SetText/Show/Hide
    -- natively — no hooks needed for stack text forwarding.  This avoids
    -- all secret-value comparison issues: Blizzard's C-side code handles
    -- zero detection, visibility toggling, and clearing internally.
    --
    -- For non-charged entries (Spirit Bomb / Soul Fragments): the native
    -- ChargeCount.Current and Applications.Applications FontStrings
    -- display stacks directly.  Blizzard clears them when stacks deplete.
    --
    -- For charged entries (hasCharges=true): the FWD path drives
    -- icon.StackText via cooldownChargesCount — Blizzard native frames
    -- are still reparented but the FWD path is the authority.

    -- Reparent ChargeCount to our icon's TextOverlay so it renders
    -- above the cooldown swipe.  Blizzard still owns the frame and
    -- calls Show/Hide/SetText on it normally.
    if chargeFrame then
        local textOverlay = icon.TextOverlay
        if textOverlay then
            local lvl = textOverlay:GetFrameLevel() + 1
            pcall(chargeFrame.SetParent, chargeFrame, textOverlay)
            pcall(chargeFrame.SetFrameLevel, chargeFrame, lvl)
        end
        -- Show ChargeCount — Blizzard may start it hidden on essential
        -- viewer children but still updates its text.  Making it visible
        -- lets the native text display.  Blizzard's Hide() calls will
        -- still work and correctly hide when stacks deplete.
        if not (entry and entry.hasCharges) then
            chargeFrame:Show()
        end
    end

    -- Same for Applications.
    if appFrame then
        local textOverlay = icon.TextOverlay
        if textOverlay then
            local lvl = textOverlay:GetFrameLevel() + 1
            pcall(appFrame.SetParent, appFrame, textOverlay)
            pcall(appFrame.SetFrameLevel, appFrame, lvl)
        end
    end

    -- Style the native FontStrings (font/color/position applied in
    -- ConfigureIcon via StyleBlizzNativeStacks, called after this).

    -- Minimal state tracking for IsHookStackActive and the FWD path.
    local state = blizzStackState[blizzChild]
    if not state then
        state = {}
        blizzStackState[blizzChild] = state
    end
    state.icon = icon
    state.blizzChild = blizzChild

    ChargeDebug(entry and entry.name, "HookBlizzStackText ASSIGN",
        "spellID=", entry and entry.spellID, "overrideSpellID=", entry and entry.overrideSpellID,
        "hasCharges=", entry and entry.hasCharges,
        "child.cooldownChargesCount=", blizzChild.cooldownChargesCount,
        "ChargeCount=", chargeFrame and "exists" or "nil",
        "Applications=", appFrame and "exists" or "nil")
end

local function ClearIconStackText(icon)
    if not icon or not icon.StackText then return end
    pcall(icon.StackText.SetText, icon.StackText, "")
    pcall(icon.StackText.Hide, icon.StackText)
end

local function ApplyAuraStackText(icon, stackValue, showZero, preserveWhenMissing)
    if not icon or not icon.StackText then return end

    if stackValue == nil then
        if not preserveWhenMissing then
            ClearIconStackText(icon)
        end
        return
    end

    if IsSecretValue(stackValue) then
        local text = stackValue
        if not showZero then
            local truncOk, truncText = pcall(C_StringUtil.TruncateWhenZero, stackValue)
            if not truncOk then
                ClearIconStackText(icon)
                return
            end
            text = truncText
        end
        if pcall(icon.StackText.SetText, icon.StackText, text) then
            pcall(icon.StackText.Show, icon.StackText)
        end
        return
    end

    if showZero then
        if pcall(icon.StackText.SetText, icon.StackText, stackValue) then
            pcall(icon.StackText.Show, icon.StackText)
        end
        return
    end

    local truncOk, displayText = pcall(C_StringUtil.TruncateWhenZero, stackValue)
    if not truncOk then
        displayText = nil
    end

    if displayText and displayText ~= "" then
        if pcall(icon.StackText.SetText, icon.StackText, displayText) then
            pcall(icon.StackText.Show, icon.StackText)
        end
    else
        ClearIconStackText(icon)
    end
end

--- Style the reparented Blizzard ChargeCount/Applications FontStrings
--- with our font, color, and position.  Called from ConfigureIcon after
--- HookBlizzStackText has reparented the frames.
local function StyleBlizzNativeStacks(icon, blizzChild, font, size, outline, r, g, b, a, anchor, ox, oy)
    if not blizzChild then return end
    local chargeFrame = blizzChild.ChargeCount
    local appFrame = blizzChild.Applications

    if chargeFrame and chargeFrame.Current then
        local fs = chargeFrame.Current
        pcall(fs.SetFont, fs, font, size, outline)
        pcall(fs.SetTextColor, fs, r, g, b, a)
        pcall(fs.ClearAllPoints, fs)
        pcall(fs.SetPoint, fs, anchor, icon, anchor, ox, oy)
        pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
    end

    if appFrame and appFrame.Applications then
        local fs = appFrame.Applications
        pcall(fs.SetFont, fs, font, size, outline)
        pcall(fs.SetTextColor, fs, r, g, b, a)
        pcall(fs.ClearAllPoints, fs)
        pcall(fs.SetPoint, fs, anchor, icon, anchor, ox, oy)
        pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
    end
end

local function UnhookBlizzStackText(icon)
    local entry = icon._spellEntry
    if not entry or not entry._blizzChild then return end
    local state = blizzStackState[entry._blizzChild]
    if state then state.icon = nil end
end

---------------------------------------------------------------------------
-- CAST-BASED STALE STACK DETECTION — DISABLED
-- Previously listened for UNIT_SPELLCAST_SUCCEEDED to detect when stacks
-- drop to 0 (Blizzard may not call SetText/Hide on the viewer child).
-- Removed because the hook for the charge change fires BEFORE the cast
-- event in the same frame, making it impossible to distinguish "hook
-- confirmed new count" from "hook hasn't fired yet."  The 0.3s deferred
-- clear + apiOverride mechanism caused visible flicker after every
-- charge-consuming cast — both in and out of combat.
-- Stale stacks from zero-charge edge cases are now handled by the
-- ChargeCount Hide hook (which Blizzard does fire for most abilities)
-- and by the OOC API fallback in UpdateIconCooldown.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- BLIZZARD BUFF VISIBILITY
-- Buff icon visibility is driven by the rescan mechanism: aura events
-- trigger ScanCooldownViewer → LayoutContainer which rebuilds the icon
-- pool.  Icons start at alpha=1 on init; during normal gameplay the
-- update ticker mirrors the Blizzard child's alpha (multiplied by row
-- opacity).  During Edit Mode, icons stay at full visibility.
---------------------------------------------------------------------------
local function InitBuffVisibility(icon, blizzChild)
    if not blizzChild then return end
    -- Start at full alpha — the update ticker will mirror Blizzard child
    -- alpha outside Edit Mode.
    icon:SetAlpha(1)
end

---------------------------------------------------------------------------
-- ICON CREATION
-- Frame structure: Frame parent with .Icon, .Cooldown, .Border,
-- .DurationText, .StackText children.
---------------------------------------------------------------------------
local function CreateIcon(parent, spellEntry)
    iconCounter = iconCounter + 1
    local frameName = "QUICDMIcon" .. iconCounter

    local icon = CreateFrame("Frame", frameName, parent)
    local size = DEFAULT_ICON_SIZE
    icon:SetSize(size, size)

    -- .Icon texture (ARTWORK layer)
    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetAllPoints(icon)

    -- .Cooldown frame (CooldownFrameTemplate for swipe/countdown)
    icon.Cooldown = CreateFrame("Cooldown", frameName .. "Cooldown", icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints(icon)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    icon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    icon.Cooldown:SetDrawBling(true)
    icon.Cooldown:EnableMouse(false)

    -- .TextOverlay (sits above the CooldownFrame so text is never behind the swipe)
    icon.TextOverlay = CreateFrame("Frame", nil, icon)
    icon.TextOverlay:SetAllPoints(icon)
    icon.TextOverlay:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 2)
    icon.TextOverlay:EnableMouse(false)

    -- .Border texture (BACKGROUND, sublayer -8, pre-created)
    icon.Border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.Border:Hide()

    -- .DurationText (OVERLAY, sublayer 7 — parented to TextOverlay, above swipe)
    icon.DurationText = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.DurationText:SetPoint("CENTER")

    -- .StackText (OVERLAY, sublayer 7 — parented to TextOverlay, above swipe)
    icon.StackText = icon.TextOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    icon.StackText:SetPoint("BOTTOMRIGHT")

    -- Set a default font so SetText() never fires before ConfigureIcon styles them
    local defaultFont = GetGeneralFont()
    local defaultOutline = GetGeneralFontOutline()
    icon.DurationText:SetFont(defaultFont, 10, defaultOutline)
    icon.StackText:SetFont(defaultFont, 10, defaultOutline)

    -- Metadata
    icon._spellEntry = spellEntry
    icon._isQUICDMIcon = true

    -- Set texture
    if spellEntry then
        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        -- Aura entries: try the child's linkedSpellIDs for the actual buff
        -- icon (e.g., Roll the Bones → Broadside). The tick update also
        -- resolves this, but setting it at init avoids a 1-frame flash.
        if spellEntry.isAura and spellEntry._blizzChild then
            local ci = spellEntry._blizzChild.cooldownInfo
            if ci and ci.linkedSpellIDs then
                local lsid = SafeValue(ci.linkedSpellIDs[1], nil)
                if lsid and lsid > 0 then
                    local linkedTex = GetSpellTexture(lsid)
                    if linkedTex then texID = linkedTex end
                end
            end
        end
        if texID then
            icon.Icon:SetTexture(texID)
            -- Only lock texture for cooldown entries — aura icons rely on
            -- the tick update + Blizzard texture hook for dynamic changes.
            if not spellEntry.isAura then
                icon._desiredTexture = texID
            end
        end
    end

    -- Tooltip support
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
        local tooltipProvider = ns.TooltipProvider
        if tooltipProvider then
            if tooltipProvider.IsOwnerFadedOut and tooltipProvider:IsOwnerFadedOut(self) then
                pcall(GameTooltip.Hide, GameTooltip)
                return
            end
            if tooltipProvider.ShouldShowTooltip and not tooltipProvider:ShouldShowTooltip("cdm") then
                pcall(GameTooltip.Hide, GameTooltip)
                return
            end
        end
        local entry = self._spellEntry
        if not entry then return end
        local tooltipSettings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip
        if (not tooltipProvider) and tooltipSettings and tooltipSettings.hideInCombat and InCombatLockdown() then return end
        if tooltipSettings and tooltipSettings.anchorToCursor then
            local anchorTooltip = ns.QUI_AnchorTooltipToCursor
            if anchorTooltip then
                anchorTooltip(GameTooltip, self, tooltipSettings)
            else
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            end
        else
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        end
        -- Aura entries: use the Blizzard child's live GetSpellID()
        -- which dynamically tracks the active buff (e.g. Roll the
        -- Bones cycling between Broadside/One of a Kind/etc.).
        -- Non-aura entries: use _runtimeSpellID (live override).
        -- Both may be secret in combat — pass directly to C-side
        -- SetSpellByID which handles secrets natively.
        local sid
        if entry.isAura and entry._blizzChild and entry._blizzChild.GetSpellID then
            local ok, childSid = pcall(entry._blizzChild.GetSpellID, entry._blizzChild)
            if ok and childSid then sid = childSid end
        end
        if not sid then
            sid = self._runtimeSpellID
        end
        if not sid then
            sid = ns.CDMSpellData:ResolveDisplaySpellID(entry)
        end
        if sid then
            if entry.type == "trinket" or entry.type == "slot" then
                local itemID = entry.itemID or GetInventoryItemID("player", entry.id)
                if itemID then
                    pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
                end
            elseif entry.type == "item" then
                pcall(GameTooltip.SetItemByID, GameTooltip, entry.id)
            else
                pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
            end
        end
        pcall(GameTooltip.Show, GameTooltip)
    end)
    icon:SetScript("OnLeave", function()
        pcall(GameTooltip.Hide, GameTooltip)
    end)

    icon:Hide()
    return icon
end

---------------------------------------------------------------------------
-- CLICK-TO-CAST: Secure overlay button for CDM icons
-- Creates a SecureActionButtonTemplate child that receives clicks and
-- forwards them to the WoW secure action system.  The parent icon
-- stays as a plain Frame so layout/pooling remain taint-free.
---------------------------------------------------------------------------
local function SyncClickButtonFrameLevel(icon)
    if not icon or not icon.clickButton or not icon.TextOverlay then return end
    if InCombatLockdown() then return end
    local requiredLevel = icon.TextOverlay:GetFrameLevel() + 2
    if icon.clickButton:GetFrameLevel() ~= requiredLevel then
        icon.clickButton:SetFrameLevel(requiredLevel)
    end
end

-- Keep text above cooldown (baseline) and optionally above another frame level.
-- Also keeps clickButton above text if one exists.
function CDMIcons:EnsureTextOverlayLevel(icon, minLevel)
    if not icon or not icon.TextOverlay then return end

    local requiredLevel = minLevel
    if icon.Cooldown and icon.Cooldown.GetFrameLevel then
        local baselineLevel = icon.Cooldown:GetFrameLevel() + 2
        if not requiredLevel or requiredLevel < baselineLevel then
            requiredLevel = baselineLevel
        end
    end

    if requiredLevel and icon.TextOverlay:GetFrameLevel() < requiredLevel then
        icon.TextOverlay:SetFrameLevel(requiredLevel)
    end

    SyncClickButtonFrameLevel(icon)
end

local function EnsureClickButton(icon)
    if icon.clickButton then
        CDMIcons:EnsureTextOverlayLevel(icon)
        return icon.clickButton
    end

    local btn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
    btn:SetAllPoints()
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:EnableMouse(true)
    btn:Hide()

    -- Forward tooltip events to the parent icon's handler
    btn:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        if parent then
            local onEnter = parent:GetScript("OnEnter")
            if onEnter then onEnter(parent) end
        end
    end)
    btn:SetScript("OnLeave", function()
        pcall(GameTooltip.Hide, GameTooltip)
    end)

    icon.clickButton = btn
    CDMIcons:EnsureTextOverlayLevel(icon)
    return btn
end

local function ClearClickButtonAttributes(btn)
    btn:SetAttribute("type", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("item", nil)
    btn:SetAttribute("macro", nil)
end

---------------------------------------------------------------------------
-- MACRO RESOLUTION
-- Scan all player macros for one that casts the given spell.
-- If found, clicking the CDM icon will execute through the macro,
-- preserving all conditionals (@mouseover, /cancelaura, modifiers, etc.).
--
-- Scans macro indices directly (1-120 account, 121-138 character) instead
-- of action bar slots, because GetActionInfo returns bogus "macro" entries
-- with spell IDs instead of real macro indices in WoW 12.0+.
--
-- Match priority (highest → lowest):
--   1. GetMacroSpell — WoW resolved the macro's tooltip to our spell
--   2. #showtooltip / #show line names our spell — the macro's declared identity
--   3. /cast or /use line names our spell — broadest fallback
-- Multi-spell macros (e.g. Lichborne + Death Coil) only match via their
-- tooltip identity, not via a /cast line for a secondary spell.
---------------------------------------------------------------------------
local MAX_ACCOUNT_MACROS = 120
local MAX_CHARACTER_MACROS = 18

-- Extract the spell name from #showtooltip or #show lines.
-- Returns lowercase name or nil.  Handles:
--   #showtooltip              → nil (bare, no explicit spell)
--   #showtooltip Spell Name   → "spell name"
--   #show Spell Name          → "spell name"
local function GetMacroTooltipSpell(body)
    if not body then return nil end
    local name = body:match("^#showtooltip%s+(.+)") or body:match("\n#showtooltip%s+(.+)")
    if not name then
        name = body:match("^#show%s+(.+)") or body:match("\n#show%s+(.+)")
    end
    if name then
        name = name:match("^(.-)%s*$")
        if name and name ~= "" then return name:lower() end
    end
    return nil
end

-- Session cache: spellID → macroName or false. Invalidated on UPDATE_MACROS.
local _macroCache = {}
local _macroCacheDirty = true
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "CDM_macroCache", tbl = _macroCache } end

local function InvalidateMacroCache()
    wipe(_macroCache)
    _macroCacheDirty = true
end

local function FindMacroForSpell(spellID, overrideSpellID)
    if not spellID and not overrideSpellID then return nil end

    -- Check session cache (keyed on primary spellID)
    local cacheKey = spellID or overrideSpellID
    local cached = _macroCache[cacheKey]
    if cached ~= nil then return cached or nil end

    -- Build lowercase spell name set for matching
    local names = {}
    if spellID and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then names[info.name:lower()] = true end
    end
    if overrideSpellID and overrideSpellID ~= spellID and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(overrideSpellID)
        if info and info.name then names[info.name:lower()] = true end
    end
    if not next(names) then
        _macroCache[cacheKey] = false
        return nil
    end

    -- Pass 1: GetMacroSpell (WoW-resolved tooltip spell ID)
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local macroName = GetMacroInfo(i)
        if macroName then
            local macroSpell = GetMacroSpell(i)
            if macroSpell and (macroSpell == spellID or macroSpell == overrideSpellID) then
                _macroCache[cacheKey] = macroName
                return macroName
            end
        end
    end

    -- Pass 2: #showtooltip / #show declares the macro's identity spell
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local macroName = GetMacroInfo(i)
        if macroName then
            local tooltipSpell = GetMacroTooltipSpell(GetMacroBody(i))
            if tooltipSpell and names[tooltipSpell] then
                _macroCache[cacheKey] = macroName
                return macroName
            end
        end
    end

    -- Pass 3: /cast or /use line mentions our spell (broadest, skips
    -- multi-spell macros whose tooltip identity is a different spell)
    for i = 1, MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS do
        local macroName = GetMacroInfo(i)
        if macroName then
            local body = GetMacroBody(i)
            if body then
                local tooltipSpell = GetMacroTooltipSpell(body)
                if tooltipSpell and not names[tooltipSpell] then
                    -- Tooltip declares a different spell — skip
                else
                    local lowerBody = body:lower()
                    for name in pairs(names) do
                        if lowerBody:find(name, 1, true) then
                            _macroCache[cacheKey] = macroName
                            return macroName
                        end
                    end
                end
            end
        end
    end
    _macroCache[cacheKey] = false
    return nil
end

---------------------------------------------------------------------------
-- SECURE ATTRIBUTE MANAGEMENT
-- Sets or clears the click-to-cast secure button attributes on a CDM icon.
---------------------------------------------------------------------------
local function UpdateIconSecureAttributes(icon, entry, viewerType)
    if not icon then return end

    -- Can't modify secure attributes during combat
    if InCombatLockdown() then
        icon._pendingSecureUpdate = true
        return
    end

    -- Never clickable for buff icons
    if viewerType == "buff" then
        if icon.clickButton then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
        return
    end

    local db = GetDB()
    local viewerDB = db and db[viewerType]

    -- Feature disabled or no config
    if not viewerDB or not viewerDB.clickableIcons then
        if icon.clickButton then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
        return
    end

    -- No entry assigned
    if not entry then
        if icon.clickButton then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
        return
    end

    local btn = EnsureClickButton(icon)

    -- Determine secure attributes based on entry type
    if entry.type == "macro" and entry.macroName then
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macro", entry.macroName)
        btn:Show()
    elseif entry.type == "trinket" or entry.type == "slot" then
        local itemID = entry.itemID or GetInventoryItemID("player", entry.id)
        if itemID then
            local itemName = C_Item.GetItemNameByID(itemID)
            if itemName then
                btn:SetAttribute("type", "item")
                btn:SetAttribute("item", itemName)
                btn:Show()
            else
                ClearClickButtonAttributes(btn)
                btn:Hide()
            end
        else
            ClearClickButtonAttributes(btn)
            btn:Hide()
        end
    elseif entry.type == "item" then
        local itemName = C_Item.GetItemNameByID(entry.id)
        if itemName then
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", itemName)
            btn:Show()
        else
            ClearClickButtonAttributes(btn)
            btn:Hide()
        end
    else
        -- Spell (harvested or custom spell type)
        -- Prefer player macro if one casts this spell, so clicking
        -- the CDM icon executes through the macro's conditionals.
        local spellID = entry.overrideSpellID or entry.spellID
        local macroName = FindMacroForSpell(entry.spellID, entry.overrideSpellID)
        if macroName then
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macro", macroName)
            btn:Show()
        elseif spellID then
            local spellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                btn:SetAttribute("type", "spell")
                btn:SetAttribute("spell", spellInfo.name)
                btn:Show()
            else
                ClearClickButtonAttributes(btn)
                btn:Hide()
            end
        else
            ClearClickButtonAttributes(btn)
            btn:Hide()
        end
    end

    icon._pendingSecureUpdate = nil
end

---------------------------------------------------------------------------
-- ICON CONFIGURATION
-- Applies size, border, zoom, texcoord, text styling to an icon.
-- No combat guards needed — all addon-owned frames.
---------------------------------------------------------------------------
local function ApplyTexCoord(icon, zoom, aspectRatioCrop)
    if not icon then return end
    local z = zoom or 0
    local aspectRatio = aspectRatioCrop or 1.0

    local left = BASE_CROP + z
    local right = 1 - BASE_CROP - z
    local top = BASE_CROP + z
    local bottom = 1 - BASE_CROP - z

    -- Apply aspect ratio crop on top of existing crop
    if aspectRatio > 1.0 then
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local availableHeight = bottom - top
        local offset = (cropAmount * availableHeight) / 2.0
        top = top + offset
        bottom = bottom - offset
    end

    if icon.Icon and icon.Icon.SetTexCoord then
        icon.Icon:SetTexCoord(left, right, top, bottom)
    end
end

local function ConfigureIcon(icon, rowConfig)
    if not icon or not rowConfig then return end

    local size = rowConfig.size or DEFAULT_ICON_SIZE
    local aspectRatio = rowConfig.aspectRatioCrop or 1.0
    local width = size
    local height = size / aspectRatio

    -- Pixel-snap dimensions
    if QUICore and QUICore.PixelRound then
        width = QUICore:PixelRound(width, icon)
        height = QUICore:PixelRound(height, icon)
    end

    icon:SetSize(width, height)

    -- Icon texture fills the frame
    if icon.Icon then
        icon.Icon:ClearAllPoints()
        icon.Icon:SetAllPoints(icon)
    end

    -- Cooldown frame matches icon size
    if icon.Cooldown then
        icon.Cooldown:ClearAllPoints()
        icon.Cooldown:SetAllPoints(icon)
    end

    -- Border
    local borderSize = rowConfig.borderSize or 0
    if borderSize > 0 then
        local bs = (QUICore and QUICore.Pixels) and QUICore:Pixels(borderSize, icon) or borderSize
        local bc = rowConfig.borderColorTable or {0, 0, 0, 1}

        icon.Border:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        icon.Border:ClearAllPoints()
        icon.Border:SetPoint("TOPLEFT", icon, "TOPLEFT", -bs, bs)
        icon.Border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", bs, -bs)
        icon.Border:Show()

        icon:SetHitRectInsets(-bs, -bs, -bs, -bs)
        if icon.clickButton then
            icon.clickButton:SetHitRectInsets(-bs, -bs, -bs, -bs)
        end
    else
        icon.Border:Hide()
        icon:SetHitRectInsets(0, 0, 0, 0)
        if icon.clickButton then
            icon.clickButton:SetHitRectInsets(0, 0, 0, 0)
        end
    end

    -- TexCoord (zoom + aspect ratio crop)
    ApplyTexCoord(icon, rowConfig.zoom or 0, aspectRatio)

    -- Duration text styling
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()

    local durationSize = rowConfig.durationSize or 14
    local hideDurationText = rowConfig.hideDurationText
    if durationSize > 0 and not hideDurationText then
        local dtc = rowConfig.durationTextColor or {1, 1, 1, 1}
        local dAnchor = rowConfig.durationAnchor or "CENTER"
        local dox = rowConfig.durationOffsetX or 0
        local doy = rowConfig.durationOffsetY or 0

        -- Style the Cooldown frame's built-in text
        if icon.Cooldown then
            local ok, regions = pcall(function() return { icon.Cooldown:GetRegions() } end)
            if ok and regions then
                for _, region in ipairs(regions) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:SetFont(generalFont, durationSize, generalOutline)
                        region:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
                        region:Show()
                        pcall(function()
                            region:ClearAllPoints()
                            region:SetPoint(dAnchor, icon, dAnchor, dox, doy)
                            region:SetDrawLayer("OVERLAY", 7)
                        end)
                    end
                end
            end
        end

        -- Also style our DurationText
        icon.DurationText:SetFont(generalFont, durationSize, generalOutline)
        icon.DurationText:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
        icon.DurationText:ClearAllPoints()
        icon.DurationText:SetPoint(dAnchor, icon, dAnchor, dox, doy)
        icon.DurationText:Show()
    elseif hideDurationText then
        -- Hide all duration text elements
        if icon.Cooldown then
            local ok, regions = pcall(function() return { icon.Cooldown:GetRegions() } end)
            if ok and regions then
                for _, region in ipairs(regions) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:Hide()
                    end
                end
            end
        end
        icon.DurationText:Hide()
    end

    -- Stack text styling
    local stackSize = rowConfig.stackSize or 14
    if stackSize > 0 then
        local stc = rowConfig.stackTextColor or {1, 1, 1, 1}
        local sAnchor = rowConfig.stackAnchor or "BOTTOMRIGHT"
        local sox = rowConfig.stackOffsetX or 0
        local soy = rowConfig.stackOffsetY or 0

        icon.StackText:SetFont(generalFont, stackSize, generalOutline)
        icon.StackText:SetTextColor(stc[1], stc[2], stc[3], stc[4] or 1)
        icon.StackText:ClearAllPoints()
        icon.StackText:SetPoint(sAnchor, icon, sAnchor, sox, soy)
        icon.StackText:SetDrawLayer("OVERLAY", 7)

        -- Also style reparented Blizzard native stack FontStrings
        -- (ChargeCount.Current, Applications.Applications) so they
        -- match our font/color/position.
        local entry = icon._spellEntry
        if entry and entry._blizzChild then
            StyleBlizzNativeStacks(icon, entry._blizzChild,
                generalFont, stackSize, generalOutline,
                stc[1], stc[2], stc[3], stc[4] or 1,
                sAnchor, sox, soy)
        end
    end

    -- Apply row opacity
    local opacity = rowConfig.opacity or 1.0
    icon:SetAlpha(opacity)
    icon._rowOpacity = opacity

    ---------------------------------------------------------------------------
    -- Per-spell overrides (additive on top of row-level settings)
    ---------------------------------------------------------------------------
    local spellOvr = GetIconSpellOverride(icon)
    if spellOvr then
        -- iconSizeOverride: override icon + sub-region sizes
        if spellOvr.iconSizeOverride then
            local ovrSize = spellOvr.iconSizeOverride
            local aspectRatio = rowConfig.aspectRatioCrop or 1.0
            local ovrW = ovrSize
            local ovrH = ovrSize / aspectRatio
            if QUICore and QUICore.PixelRound then
                ovrW = QUICore:PixelRound(ovrW, icon)
                ovrH = QUICore:PixelRound(ovrH, icon)
            end
            icon:SetSize(ovrW, ovrH)
            if icon.Cooldown then
                icon.Cooldown:ClearAllPoints()
                icon.Cooldown:SetAllPoints(icon)
            end
            if icon.Icon then
                icon.Icon:ClearAllPoints()
                icon.Icon:SetAllPoints(icon)
            end
        end

        -- showDurationText: per-spell duration text visibility override
        if spellOvr.showDurationText == false then
            if icon.Cooldown then
                local ok, regions = pcall(function() return { icon.Cooldown:GetRegions() } end)
                if ok and regions then
                    for _, region in ipairs(regions) do
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            region:Hide()
                        end
                    end
                end
            end
            icon.DurationText:Hide()
        elseif spellOvr.showDurationText == true then
            icon.DurationText:Show()
        end

        -- customBorderColor: per-spell border color override
        if spellOvr.customBorderColor and icon.Border and icon.Border:IsShown() then
            local bc = spellOvr.customBorderColor
            icon.Border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
        end

        -- desaturate: cache for UpdateIconCooldown to use per-icon
        icon._spellOverrideDesaturate = spellOvr.desaturate

        -- desaturateIgnoreAura: when true, aura-active state does not suppress
        -- cooldown desaturation — the icon desaturates based on charge/CD state
        -- even while the spell's debuff/buff is ticking on the target.
        icon._desaturateIgnoreAura = spellOvr.desaturateIgnoreAura or nil
    else
        icon._spellOverrideDesaturate = nil
        icon._desaturateIgnoreAura = nil
    end

    SyncCooldownBling(icon)
end

---------------------------------------------------------------------------
-- COOLDOWN UPDATE
-- Update cooldown state for a single icon.
---------------------------------------------------------------------------
local function GetTrackerSettings(viewerType)
    local db = GetDB()
    if not db or not viewerType then return nil end
    return db[viewerType]
end

-- _hoistedNcdm is set once per UpdateAllCooldowns batch (avoids 4 table
-- hops per icon).  Local to file scope so UpdateIconCooldown can read it.
local _hoistedNcdm = nil
-- _batchTime is set once per UpdateAllCooldowns batch so per-icon code
-- can read GetTime() without crossing the C boundary for every icon.
local _batchTime = 0
-- _showGCDSwipe is hoisted once per batch from swipe module settings.
-- When true, GCD-only cooldowns are allowed through to the CooldownFrame
-- instead of being cleared, so the GCD swipe animation can render.
local _showGCDSwipe = false
-- _showBuffSwipe is hoisted once per batch from swipe module settings.
-- When false, cooldown-container icons skip aura detection entirely so
-- the icon shows the recharge/cooldown timer instead of the aura duration.
local _showBuffSwipe = true

local function WipeUpdateTickCaches()
    BeginUpdateTickCaches()
    if ns.CDMSpellData and ns.CDMSpellData.WipeTickAuraCache then
        ns.CDMSpellData:WipeTickAuraCache()
    end
end

local function GetChildIconTexture(child)
    if not child then return nil end
    local blzIcon = child.Icon or child.icon
    local texRegion = blzIcon and (blzIcon.Icon or blzIcon.icon or blzIcon)
    if texRegion and texRegion.GetTexture then
        local ok, tex = pcall(texRegion.GetTexture, texRegion)
        if ok then
            return tex
        end
    end
    return nil
end

local function UpdateIconCooldown(icon)
    if not icon or not icon._spellEntry then return end
    local entry = icon._spellEntry

    -- Runtime override: resolve from the BASE spell each tick so dynamic
    -- transforms (Glacial Spike ↔ Frostbolt, Mind Blast → Void Blast)
    -- are always current.  Shared across all paths in this function.
    local _runtimeSid = entry.spellID or entry.overrideSpellID or entry.id
    if _runtimeSid and C_Spell.GetOverrideSpell then
        local ovId = TickCacheGetOverrideSpell(_runtimeSid)
        if ovId then _runtimeSid = ovId end
    end
    -- Stash live override on icon so tooltip/display can pass it
    -- directly to C-side functions (handles secret values natively).
    icon._runtimeSpellID = _runtimeSid

        -- Aura-driven update: delegates to shared CDMSpellData:ResolveAuraState().
        -- Icons apply result to swipe/stacks display on CooldownFrame.
        do
            local cType = GetContainerTypeForViewer(entry.viewerType)
            if cType == "aura" or cType == "auraBar" then
                local auraSpellID = _runtimeSid
                if auraSpellID and ns.CDMSpellData then
                    local p = icon._auraParams or {}
                    icon._auraParams = p
                    p.spellID = auraSpellID
                    p.entrySpellID = entry.spellID
                    p.entryID = entry.id
                    p.entryName = entry.name
                    p.viewerType = entry.viewerType
                    p.blizzChild = entry._blizzChild
                    p.blizzBarChild = entry._blizzBarChild
                    p.totemSlot = IsTotemSlotEntry(entry) and entry._totemSlot or nil
                    p.disableLooseVisibilityFallback = true

                    local r = ns.CDMSpellData:ResolveAuraState(p)
                    local isTotemSlot = IsTotemSlotEntry(entry)
                    icon._totemSlot = entry._totemSlot or nil
                    if r.blizzChild and r.blizzChild ~= entry._blizzChild then
                        -- Blizzard child changed — reconnect mirror/texture/stack
                        -- hooks to the new child. Old hooks on the previous child
                        -- self-disable via stale mapping guards in each callback.
                        entry._blizzChild = r.blizzChild
                        if not isTotemSlot then
                            MirrorBlizzCooldown(icon, r.blizzChild)
                            HookBlizzTexture(icon, r.blizzChild)
                            HookBlizzStackText(icon, r.blizzChild)
                        end
                    end
                    -- Cache bar-viewer counterpart so the next tick passes it
                    -- through without rescanning BuffBarCooldownViewer.
                    entry._blizzBarChild = r.blizzBarChild

                    if r.isActive then
                        icon._auraActive = true
                        icon._auraUnit = r.auraUnit
                        icon._isTotemInstance = isTotemSlot or nil

                        if icon.Cooldown and r.durObj and icon.Cooldown.SetCooldownFromDurationObject then
                            pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, r.durObj, true)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                        end

                        -- Stacks: forward r.stacks directly to C-side where
                        -- possible. Blizzard aura APIs can return secret or
                        -- otherwise non-finite values in combat, so keep stack
                        -- formatting behind pcall and collapse invalid counts
                        -- to empty text.
                        local _auraHookActive = (not r.isTotemInstance) and IsHookStackActive(entry, icon)
                        if not _auraHookActive then
                            if r.isTotemInstance then
                                ClearIconStackText(icon)
                                ClearAuraHookStackText(entry, icon)
                            else
                                ApplyAuraStackText(icon, r.stacks, entry.hasCharges, InCombatLockdown())
                            end
                        end

                        -- Keep texture showing the active aura buff.
                        -- Totem instances use slot payloads from GetTotemInfo:
                        -- active state comes from GetTotemDuration(slot),
                        -- display icon comes from the same slot.
                        if icon.Icon then
                            local mirrored = false
                            if r.isTotemInstance then
                                if r.totemIcon then
                                    icon._totemIconCache = r.totemIcon
                                end
                                local totemTex = r.totemIcon or icon._totemIconCache
                                if totemTex then
                                    icon._desiredTexture = nil
                                    pcall(icon.Icon.SetTexture, icon.Icon, totemTex)
                                    icon._lastTexture = totemTex
                                    mirrored = true
                                end
                            elseif entry._blizzChild then
                                local tex = GetChildIconTexture(entry._blizzChild)
                                if tex then
                                    pcall(icon.Icon.SetTexture, icon.Icon, tex)
                                    mirrored = true
                                end
                            end
                            -- Fallback: auraData.icon then base aura spell
                            -- texture (used when child Icon region isn't
                            -- yet resolvable, e.g. first show).
                            if not mirrored and not r.isTotemInstance then
                                local texID
                                if r.auraData then
                                    local aIcon = SafeValue(r.auraData.icon, nil)
                                    if aIcon and aIcon ~= 0 then texID = aIcon end
                                end
                                if not texID then
                                    texID = GetSpellTexture(auraSpellID)
                                end
                                if texID and texID ~= icon._lastTexture then
                                    icon.Icon:SetTexture(texID)
                                    icon._lastTexture = texID
                                end
                            end
                        end

                        ReapplySwipeStyle(icon.Cooldown, icon)
                        return  -- Aura path complete
                    else
                        icon._auraActive = false
                        icon._isTotemInstance = nil
                        icon._totemSlot = entry._totemSlot or nil
                        if icon.Cooldown then icon.Cooldown:Clear() end

                        -- Only clear our StackText overlay if Blizzard's
                        -- native stack frames aren't actively displaying.
                        if r.isTotemInstance or not IsHookStackActive(entry, icon) then
                            ClearIconStackText(icon)
                        end
                        ClearAuraHookStackText(entry, icon)
                        return  -- Aura path complete
                    end
                end
            end
        end

        -- Custom entry: use addon-created CD with our cooldown resolution
        local startTime, duration, durObj, apiIsActive, blizzRealCooldownActive
        if entry.type == "macro" then
            local resolvedID, resolvedType, fallbackTex = ResolveMacro(entry)
            if resolvedID then
                if resolvedType == "item" then
                    startTime, duration, durObj = GetItemCooldown(resolvedID)
                else
                    startTime, duration, durObj = GetBestSpellCooldown(resolvedID)
                end
            end
            -- Update icon texture from already-resolved macro result
            -- (eliminates a redundant second ResolveMacro call via GetEntryTexture)
            local newTex
            if resolvedID then
                if resolvedType == "item" then
                    local _, _, _, _, tex = C_Item.GetItemInfoInstant(resolvedID)
                    newTex = tex
                else
                    newTex = GetSpellTexture(resolvedID)
                end
            else
                newTex = fallbackTex
            end
            if newTex and icon.Icon and newTex ~= icon._lastTexture then
                icon.Icon:SetTexture(newTex)
                icon._lastTexture = newTex
            end
        elseif entry.type == "trinket" or entry.type == "slot" then
            -- Trinket/slot entries store equipment slot (13/14), resolve to item ID
            local slotID = entry.id
            local itemID = GetInventoryItemID("player", slotID)
            if itemID then
                startTime, duration, durObj = GetSlotCooldown(slotID)
                -- Update texture in case trinket was swapped
                if icon.Icon then
                    local ok, tex = pcall(C_Item.GetItemIconByID, itemID)
                    if ok and tex and tex ~= icon._lastTexture then
                        icon.Icon:SetTexture(tex)
                        icon._lastTexture = tex
                    end
                end
            end
            -- Hide stack text for trinkets
            icon.StackText:SetText("")
            icon.StackText:Hide()
        elseif entry.type == "item" then
            startTime, duration, durObj = GetItemCooldown(entry.id)
            -- Show item count as stack text (includeUses=true for charge items)
            if C_Item and C_Item.GetItemCount then
                local ok, count = pcall(C_Item.GetItemCount, entry.id, false, true)
                if ok and count and count > 0 then
                    icon.StackText:SetText(tostring(count))
                    icon.StackText:Show()
                else
                    icon.StackText:SetText("0")
                    icon.StackText:Show()
                end
            end
        else
            if entry._blizzChild and not entry.hasCharges then
                local sid = _runtimeSid

                -- Non-charged abilities may have an aura phase (e.g.,
                -- defensive CDs that grant a buff). Detect active aura
                -- and show it; mirror hook is suppressed via _auraActive
                -- so the cooldown DurationObject doesn't overwrite it.
                -- Many utility/defensive CDs grant a buff with the same
                -- spell ID but aren't in Blizzard's buff CDM categories,
                -- so we always try ResolveAuraState (not gated on the
                -- _abilityToAuraSpellID mapping).
                -- When buff/debuff swipe is disabled, skip aura detection
                -- so the icon shows the recharge/cooldown timer instead.
                local _ncAuraActive = false
                local _ncTotemTexture = nil
                if ns.CDMSpellData and _showBuffSwipe then
                    local p = icon._auraParams or {}
                    icon._auraParams = p
                    p.spellID = sid
                    p.entrySpellID = entry.spellID
                    p.entryID = entry.id
                    p.entryName = entry.name
                    p.viewerType = entry.viewerType
                    p.blizzChild = entry._blizzChild
                    p.blizzBarChild = entry._blizzBarChild
                    p.totemSlot = IsTotemSlotEntry(entry) and entry._totemSlot or nil
                    p.disableLooseVisibilityFallback = true

                    local r = ns.CDMSpellData:ResolveAuraState(p)
                    entry._blizzBarChild = r.blizzBarChild

                    if r.isActive then
                        _ncAuraActive = true
                        icon._totemSlot = entry._totemSlot or nil
                        if IsTotemSlotEntry(entry) then
                            icon._isTotemInstance = true
                            if r.totemIcon then
                                icon._totemIconCache = r.totemIcon
                            end
                            _ncTotemTexture = r.totemIcon or icon._totemIconCache
                            icon.StackText:SetText("")
                            icon.StackText:Hide()
                        else
                            icon._isTotemInstance = nil
                        end
                        icon._auraActive = true
                        icon._auraUnit = r.auraUnit
                        if icon.Cooldown and r.durObj and icon.Cooldown.SetCooldownFromDurationObject then
                            pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, r.durObj, true)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                            ReapplySwipeStyle(icon.Cooldown, icon)
                        end
                    else
                        icon._isTotemInstance = nil
                        icon._totemSlot = entry._totemSlot or nil
                        if icon._auraActive then
                            icon._auraActive = false
                            if icon.Cooldown then
                                pcall(icon.Cooldown.SetReverse, icon.Cooldown, false)
                                pcall(icon.Cooldown.Clear, icon.Cooldown)
                                ReapplySwipeStyle(icon.Cooldown, icon)
                            end
                        end
                    end
                elseif not _showBuffSwipe and icon._auraActive then
                    -- Buff/debuff swipe was just disabled: clear aura state
                    -- so the mirror hook resumes forwarding cooldown data.
                    icon._auraActive = false
                    if icon.Cooldown then
                        pcall(icon.Cooldown.SetReverse, icon.Cooldown, false)
                        pcall(icon.Cooldown.Clear, icon.Cooldown)
                        ReapplySwipeStyle(icon.Cooldown, icon)
                    end
                end

                -- Use runtime-resolved override for cooldown queries + texture.
                local cdSid = _runtimeSid

                if not _ncAuraActive then
                    -- Blizzard-backed non-charged entries are mirror-driven.
                    -- Use non-secret API fields only for GCD/usability gating
                    -- and keep the owned cooldown frame synced from the live
                    -- Blizzard child instead of reconstructing cooldown state
                    -- in Lua every tick.
                    local childCi = TickCacheGetCooldown(cdSid)
                    if childCi and childCi.isActive ~= nil then
                        apiIsActive = childCi.isActive
                    end
                    -- Refresh _isOnGCD from per-tick API data.  Hooks alone can
                    -- leave it stale after GCD ends (Blizzard may not fire a new
                    -- SetCooldownFromDurationObject when transitioning from GCD
                    -- to real CD on the viewer child).
                    if childCi and not IsSecretValue(childCi.isOnGCD) then
                        icon._isOnGCD = childCi.isOnGCD or false
                    end
                    -- Forward the spell's DurationObject from
                    -- C_Spell.GetSpellCooldownDuration via SetCooldownFromDurationObject
                    -- (the one secret-safe setter). This reflects resource waits for
                    -- resource-gated spells (rune spenders, etc.) — the spell's own
                    -- Cooldown frame GetCooldownDuration returns a plain number per
                    -- FrameAPICooldownDocumentation, not a DurationObject, so the
                    -- spell-level API is required. _mirrorDriven lets the C-side own
                    -- draw/no-draw decisions (SetCooldownFromDurationObject clears at
                    -- zero) and skips the numeric tick-apply/clear fallback below.
                    if entry._blizzChild and icon.Cooldown and icon.Cooldown.SetCooldownFromDurationObject and not icon._auraActive then
                        local spellDurObj = TickCacheGetDuration(cdSid)
                        if spellDurObj then
                            pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, spellDurObj)
                            icon._durObjHookSync = GetTime()
                            icon._showingRealCooldownSwipe = true
                            icon._showingGCDSwipe = nil
                            icon._mirrorDriven = true
                            blizzRealCooldownActive = true
                            ReapplySwipeStyle(icon.Cooldown, icon)
                        else
                            icon._mirrorDriven = false
                        end
                        if entry._blizzChild.Cooldown then
                            SyncMirroredCooldownState(icon, entry._blizzChild.Cooldown, apiIsActive)
                        end
                    end
                    startTime, duration, durObj = nil, nil, nil
                else
                    -- Aura active: still refresh GCD + cooldown activity
                    -- from API so desaturation clears when the CD ends.
                    -- Do NOT set the local apiIsActive — that would cause
                    -- the CooldownFrame write to overwrite the aura swipe.
                    local childCi = TickCacheGetCooldown(cdSid)
                    if childCi and not IsSecretValue(childCi.isOnGCD) then
                        icon._isOnGCD = childCi.isOnGCD or false
                    end
                    if childCi and childCi.isActive ~= nil then
                        icon._hasCooldownActive = childCi.isActive
                    end
                end

                -- Texture: mirror the current runtime spell each tick.
                -- Non-aura cooldown entries keep _desiredTexture set so
                -- HookBlizzTexture's wasSetFromAura guard blocks debuff
                -- texture bleed (e.g. Outbreak → Virulent Plague).
                -- Uses persistent _textureCycleCache (wiped on SPELLS_CHANGED)
                -- so GetSpellInfo isn't called 20×/sec per icon.
                if icon.Icon and _ncAuraActive and _ncTotemTexture then
                    icon._desiredTexture = nil
                    pcall(icon.Icon.SetTexture, icon.Icon, _ncTotemTexture)
                    icon._lastTexture = _ncTotemTexture
                elseif icon.Icon and entry._blizzChild and not entry.isAura then
                    local texID = GetSpellTexture(cdSid)
                    if texID then
                        if icon._desiredTexture ~= texID then
                            icon._desiredTexture = texID
                            pcall(icon.Icon.SetTexture, icon.Icon, texID)
                        end
                    end
                elseif icon.Icon and entry._blizzChild then
                    icon._desiredTexture = nil
                elseif icon.Icon then
                    local texID = GetSpellTexture(cdSid)
                    if texID then
                        icon._desiredTexture = texID
                        pcall(icon.Icon.SetTexture, icon.Icon, texID)
                    end
                end
            else
                -- Charged entries may have an aura phase (e.g., utility
                -- abilities that grant a timed buff before the recharge
                -- timer begins). Detect active aura via ResolveAuraState
                -- and show it; when the aura fades, fall through to the
                -- normal charge-recharge display via GetBestSpellCooldown.
                -- When buff/debuff swipe is disabled, skip aura detection
                -- so the icon shows the recharge/cooldown timer instead.
                local _chargedAuraActive = false
                local _chargedTotemTexture = nil
                if entry.hasCharges and ns.CDMSpellData and _showBuffSwipe then
                    local _cBaseID = _runtimeSid

                    local p = icon._auraParams or {}
                    icon._auraParams = p
                    p.spellID = _cBaseID
                    p.entrySpellID = entry.spellID
                    p.entryID = entry.id
                    p.entryName = entry.name
                    p.viewerType = entry.viewerType
                    p.blizzChild = entry._blizzChild
                    p.blizzBarChild = entry._blizzBarChild
                    p.totemSlot = IsTotemSlotEntry(entry) and entry._totemSlot or nil
                    p.disableLooseVisibilityFallback = true

                    local r = ns.CDMSpellData:ResolveAuraState(p)
                    entry._blizzBarChild = r.blizzBarChild

                    if r.isActive then
                        icon._auraActive = true
                        icon._auraUnit = r.auraUnit
                        icon._totemSlot = entry._totemSlot or nil
                        if IsTotemSlotEntry(entry) then
                            icon._isTotemInstance = true
                            if r.totemIcon then
                                icon._totemIconCache = r.totemIcon
                            end
                            _chargedTotemTexture = r.totemIcon or icon._totemIconCache
                            icon.StackText:SetText("")
                            icon.StackText:Hide()
                        else
                            icon._isTotemInstance = nil
                        end
                        -- Only block the normal cooldown path when we have
                        -- a DurationObject to display. If ResolveAuraState
                        -- reports active but has no durObj (spurious match),
                        -- fall through to GetBestSpellCooldown so the
                        -- recharge swipe still renders.
                        if icon.Cooldown and r.durObj and icon.Cooldown.SetCooldownFromDurationObject then
                            _chargedAuraActive = true
                            pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, r.durObj, true)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                            ReapplySwipeStyle(icon.Cooldown, icon)
                        end
                    else
                        icon._isTotemInstance = nil
                        icon._totemSlot = entry._totemSlot or nil
                        if icon._auraActive then
                            icon._auraActive = false
                            if icon.Cooldown then
                                pcall(icon.Cooldown.SetReverse, icon.Cooldown, false)
                                pcall(icon.Cooldown.Clear, icon.Cooldown)
                                ReapplySwipeStyle(icon.Cooldown, icon)
                            end
                        end
                    end
                elseif entry.hasCharges and not _showBuffSwipe and icon._auraActive then
                    -- Buff/debuff swipe was just disabled: clear aura state
                    -- so the mirror hook resumes forwarding cooldown data.
                    icon._auraActive = false
                    if icon.Cooldown then
                        pcall(icon.Cooldown.SetReverse, icon.Cooldown, false)
                        pcall(icon.Cooldown.Clear, icon.Cooldown)
                        ReapplySwipeStyle(icon.Cooldown, icon)
                    end
                end

                if not _chargedAuraActive then
                    -- Custom entry / charged recharge: full API resolution.
                    startTime, duration, durObj, apiIsActive = GetBestSpellCooldown(_runtimeSid)
                else
                    -- Aura active: keep _hasCooldownActive in sync so
                    -- desaturation clears when the recharge completes.
                    local _, _, _, _auraApiActive = GetBestSpellCooldown(_runtimeSid)
                    if _auraApiActive ~= nil then
                        icon._hasCooldownActive = _auraApiActive
                    end
                end

                -- Refresh _isOnGCD from tick-cached API data (same query
                -- GetBestSpellCooldown already performed via TickCacheGetCooldown).
                local _tickCi = TickCacheGetCooldown(_runtimeSid)
                if _tickCi and not IsSecretValue(_tickCi.isOnGCD) then
                    icon._isOnGCD = _tickCi.isOnGCD or false
                end
                -- Texture: mirror runtime override each tick (same as
                -- non-charged path). Keeps _desiredTexture set to block
                -- debuff bleed, but updates it for talent swaps.
                -- Uses persistent _textureCycleCache (wiped on SPELLS_CHANGED).
                if icon.Icon and _chargedAuraActive and _chargedTotemTexture then
                    icon._desiredTexture = nil
                    pcall(icon.Icon.SetTexture, icon.Icon, _chargedTotemTexture)
                    icon._lastTexture = _chargedTotemTexture
                elseif icon.Icon and entry._blizzChild and not entry.isAura then
                    local texID = GetSpellTexture(_runtimeSid)
                    if texID then
                        if icon._desiredTexture ~= texID then
                            icon._desiredTexture = texID
                            pcall(icon.Icon.SetTexture, icon.Icon, texID)
                        end
                    end
                elseif icon.Icon and entry._blizzChild then
                    icon._desiredTexture = nil
                elseif icon.Icon then
                    local texID = GetSpellTexture(_runtimeSid)
                    if texID then
                        icon._desiredTexture = texID
                        pcall(icon.Icon.SetTexture, icon.Icon, texID)
                    end
                end
            end
        end

        -- _lastStart / _lastDuration: always update from API when readable.
        -- These are used by the desaturation check and visibility logic below.
        local hasSafeStart = IsSafeNumeric(startTime)
        local hasSafeDuration = IsSafeNumeric(duration)
        if hasSafeDuration then
            icon._lastDuration = duration
        end
        if hasSafeStart then
            icon._lastStart = startTime
        end
        if hasSafeDuration and duration == 0 then
            icon._lastStart = 0
            icon._lastDuration = 0
        end
        -- When API returns no data (fully charged / off CD), clear stale
        -- values so desaturation doesn't persist from a previous recharge.
        if not startTime and not duration then
            icon._lastStart = 0
            icon._lastDuration = 0
        end

        -- Detect whether the DurationObject mirror hook is actively driving
        -- this icon's CooldownFrame swipe.  When it is, skip API writes to
        -- icon.Cooldown to avoid restarting the swipe animation (flickering).
        -- _durObjHookSync is set by the SetCooldownFromDurationObject hook
        -- when it successfully forwards a DurationObject to our CooldownFrame.
        -- Charged entries are excluded: mirror hooks skip them (tSkipCharge).
        local mirrorActive = not entry.hasCharges
            and not _chargeCountForwarded
            and icon._durObjHookSync
            and apiIsActive ~= false
            and (_batchTime - icon._durObjHookSync) < 10


        if icon.Cooldown then
            -- isOnGCD means this spell participates in the global cooldown
            -- system, not that the current icon state is "only GCD".
            -- Decide what to draw from the actual rendered state first:
            -- aura swipe wins, then real cooldown/recharge, then GCD.
            local auraSwipeActive = icon._auraActive or entry.viewerType == "buff"
            local isItemEntry = entry.type == "item" or entry.type == "trinket" or entry.type == "slot"
            local spellUsable = nil
            -- Spell usability is only meaningful for actual spell entries.
            -- For item/trinket/slot entries, _runtimeSid is an item / slot ID
            -- and C_Spell.IsSpellUsable returns garbage that can false-positive
            -- the "spell is usable → no real cooldown" override below.
            if not isItemEntry and _runtimeSid and C_Spell and C_Spell.IsSpellUsable then
                local okUsable, isUsable = pcall(C_Spell.IsSpellUsable, _runtimeSid)
                if okUsable then
                    spellUsable = (isUsable == true)
                end
            end
            local realCooldownActive = HasRealCooldownState(icon, entry, duration, apiIsActive, mirrorActive, blizzRealCooldownActive)
            -- For non-charged spells, spell usability is the best runtime split
            -- between "pure GCD" (still usable) and "real cooldown/resource
            -- wait" (not usable).  Do not let a mirrored GCD DurationObject
            -- masquerade as a real cooldown.  Skipped for item entries since
            -- spellUsable doesn't apply there.
            if not entry.hasCharges and not auraSwipeActive and not isItemEntry then
                if spellUsable == true then
                    mirrorActive = false
                    blizzRealCooldownActive = false
                    realCooldownActive = false
                elseif spellUsable == false and (mirrorActive or blizzRealCooldownActive) then
                    realCooldownActive = true
                end
            end
            -- Treat the remaining active-cooldown case as GCD when there is
            -- no aura swipe and no real cooldown/recharge swipe to render.
            -- For owned cooldown icons, apiIsActive=true is the reliable
            -- runtime signal that "something is active right now"; if the
            -- active state is not explained by aura/recharge/real cooldown,
            -- the shared GCD swipe should fill that gap.
            local gcdSwipeWanted = _showGCDSwipe
                and not auraSwipeActive
                and not realCooldownActive
                and icon._isOnGCD == true
                and apiIsActive == true
                and spellUsable == true
            if realCooldownActive and not mirrorActive and not startTime and not duration and not durObj
                and not entry.hasCharges then
                -- Prefer the spell's DurationObject (secret-safe primary API).
                -- Covers the post-aura-phase case where the mirror hook may not
                -- re-fire when a self-buff defensive transitions from aura to
                -- pure-cooldown display (e.g. Divine Protection, Divine Shield).
                if _runtimeSid and C_Spell and C_Spell.GetSpellCooldownDuration then
                    local okDur, spellDurObj = pcall(C_Spell.GetSpellCooldownDuration, _runtimeSid)
                    if okDur and spellDurObj then
                        durObj = spellDurObj
                    end
                end
                -- Numeric fallback (out of combat / non-secret payloads only).
                if not durObj and entry._blizzChild and entry._blizzChild.Cooldown then
                    startTime, duration, durObj = GetBlizzCooldownPayload(entry._blizzChild.Cooldown)
                end
            end
            local expiredNow = CooldownHasExpiredNow(startTime, duration, durObj, _batchTime)
            local cooldownInactive = (apiIsActive == false)
                or (apiIsActive == nil and expiredNow)
            if icon._mirrorDriven and not entry.hasCharges then
                -- Mirror path already wrote via SetCooldownFromDurationObject
                -- upstream (non-charged Blizzard-backed entries). Skip all
                -- Clear/apply gating and let the C-side CooldownFrame decide
                -- draw state. Charged entries never qualify because the
                -- upstream mirror runs only on the non-charged branch; guard
                -- against stale _mirrorDriven from pool reuse across entries.
                DebugIconSwipe(icon, "tick-mirror-driven",
                    "apiIsActive=", tostring(apiIsActive),
                    "hasCharges=", tostring(entry.hasCharges))
            elseif cooldownInactive and not gcdSwipeWanted and not realCooldownActive then
                icon.Cooldown:Clear()
                icon._durObjHookSync = nil
                icon._showingGCDSwipe = nil
                icon._showingRealCooldownSwipe = nil
                DebugIconSwipe(icon, "tick-clear",
                    "apiIsActive=", tostring(apiIsActive),
                    "hasCharges=", tostring(entry.hasCharges),
                    "realCooldownActive=", tostring(realCooldownActive),
                    "gcdSwipeWanted=", tostring(gcdSwipeWanted))
            elseif realCooldownActive and not mirrorActive then
                local applied = ApplyResolvedCooldown(icon.Cooldown, startTime, duration, durObj, false)
                icon._showingGCDSwipe = nil
                icon._showingRealCooldownSwipe = applied and true or nil
                if applied then
                    icon._durObjHookSync = GetTime()
                end
                DebugIconSwipe(icon, "tick-apply",
                    "applied=", tostring(applied),
                    "apiIsActive=", tostring(apiIsActive),
                    "hasCharges=", tostring(entry.hasCharges),
                    "durObj=", durObj and "yes" or "no",
                    "startTime=", tostring(startTime),
                    "duration=", tostring(duration))
            elseif gcdSwipeWanted then
                -- GCD fallback should not be blocked by stale mirrored state.
                -- If there is no real cooldown active for this icon, let the
                -- owned frame render the shared global cooldown directly.
                icon._durObjHookSync = nil
                local applied = ApplyCooldownFromSpell(icon.Cooldown, GCD_SPELL_ID, false)
                icon._showingRealCooldownSwipe = nil
                icon._showingGCDSwipe = applied and true or nil
                DebugIconSwipe(icon, "tick-gcd",
                    "applied=", tostring(applied),
                    "hasCharges=", tostring(entry.hasCharges))
            else
                DebugIconSwipe(icon, "tick-skip",
                    "apiIsActive=", tostring(apiIsActive),
                    "hasCharges=", tostring(entry.hasCharges),
                    "mirrorActive=", tostring(mirrorActive),
                    "realCooldownActive=", tostring(realCooldownActive),
                    "gcdSwipeWanted=", tostring(gcdSwipeWanted),
                    "cooldownInactive=", tostring(cooldownInactive))
            end

            -- Reapply swipe styling when GCD or cooldown-active state
            -- transitions so SetDrawSwipe/SetDrawEdge and colors update.
            -- GCD transition: e.g., GCD → cooldown mode re-hides the swipe
            -- when radial darkening is off.
            -- isActive transition: ensures edge/color switches correctly
            -- when a cooldown starts (ready → active) or ends (active → ready)
            -- without waiting for a mirror hook that may not fire.
            local prevGCD = icon._wasShowingGCDSwipe or false
            local curGCD = icon._showingGCDSwipe or false
            local prevActive = icon._wasApiActive
            local curActive = apiIsActive
            if prevGCD ~= curGCD or prevActive ~= curActive then
                icon._wasShowingGCDSwipe = curGCD
                icon._wasApiActive = curActive
                ReapplySwipeStyle(icon.Cooldown, icon)
            end

            -- isActive drives _hasCooldownActive for desaturation/visibility.
            if apiIsActive ~= nil then
                -- When a real cooldown starts, clear usability tint so the
                -- desaturation gate opens.  Reset _lastVisualState so the
                -- range poll can reapply usability tint after the CD ends.
                -- Skip GCD-only transitions — GCD doesn't change spell
                -- usability, and clearing tint here causes a brief flash
                -- before the visual state poll reapplies it.
                if apiIsActive and not icon._hasCooldownActive and icon._usabilityTinted
                   and not icon._isOnGCD then
                    icon.Icon:SetVertexColor(1, 1, 1, 1)
                    icon._usabilityTinted = nil
                    icon._lastVisualState = nil
                end
                icon._hasCooldownActive = apiIsActive
            end
        end

    -- Stack/charge text: API-driven on each tick.
    -- Cache chargeInfo for this icon — reused by desaturation check below
    -- (was called 3x per cooldown icon per tick, now 1x)
    local _cachedChargeInfo = nil
    local _cachedChargeOk = false

    -- Populate _cachedChargeInfo unconditionally (needed for desaturation
    -- check below), independent of whether hooks are driving stack text.
    do
        local spellID = _runtimeSid
        if spellID then
            local chargeInfo = TickCacheGetCharges(spellID)
            _cachedChargeOk = chargeInfo ~= nil
            _cachedChargeInfo = chargeInfo
        end
    end

    -- When hooks are actively driving stack text for this icon, skip all
    -- API-based stack writes.  Our event handler runs AFTER Blizzard's
    -- hooks in the same frame — API writes would overwrite the correct
    -- hook-driven values, causing visible flicker every tick.
    local _hookActive = IsHookStackActive(entry, icon)

    -- Forward cooldownChargesCount from the Blizzard child every tick.
    -- Gate: GetSpellCharges on the base spell returns maxCharges > 1.
    -- maxCharges is non-secret (12.0.5+) and updates dynamically when
    -- the spell gains charges (e.g., Mind Blast base ID reports max=2
    -- when Void Blast is active). Single-charge spells (max=1) excluded.
    local _chargeCountForwarded = false
    if entry._blizzChild and C_Spell.GetSpellCharges then
        local baseSid = entry.spellID or entry.id
        local ci = baseSid and TickCacheGetCharges(baseSid)
        -- When the base spell transforms (e.g., Holy Bulwark → Sacred Weapon),
        -- GetSpellCharges on the base ID may return nil/<=1 even though the
        -- spell is still multi-charge.  Try the override spell ID as fallback.
        if (not ci or not ci.maxCharges or ci.maxCharges <= 1)
            and entry.overrideSpellID and entry.overrideSpellID ~= baseSid then
            local oci = TickCacheGetCharges(entry.overrideSpellID)
            if oci and oci.maxCharges and oci.maxCharges > 1 then
                ci = oci
                ChargeDebug(entry.name, "FWD override fallback: overrideSpellID=", entry.overrideSpellID,
                    "maxCharges=", oci.maxCharges, "currentCharges=", oci.currentCharges)
            end
        end
        if ci and ci.maxCharges and ci.maxCharges > 1 then
            -- Read cooldownChargesCount from the correct viewer child.
            -- entry._blizzChild can get reassigned to the buff viewer
            -- child (which lacks charge data), so we look up an alternate
            -- child from any cooldown viewer in _spellIDToChild. The QUI
            -- container the user picked (essential vs utility) is independent
            -- of where Blizzard places the spell — accept a child from either
            -- cooldown viewer so cross-category placement still mirrors charge
            -- data.
            local ccc = entry._blizzChild.cooldownChargesCount
            local _dbgCccSource = ccc ~= nil and "direct" or nil
            if ccc == nil and ns.CDMSpellData then
                local essentialViewer = _G["EssentialCooldownViewer"]
                local utilityViewer = _G["UtilityCooldownViewer"]
                local essentialContainer = essentialViewer and (essentialViewer.viewerFrame or essentialViewer)
                local utilityContainer = utilityViewer and (utilityViewer.viewerFrame or utilityViewer)
                local childMap = ns.CDMSpellData._spellIDToChild
                local children = childMap and childMap[baseSid]
                if children then
                    for _, altChild in ipairs(children) do
                        local vf = altChild.viewerFrame
                        local isCooldownViewerChild = vf and (
                            vf == essentialViewer or vf == utilityViewer
                            or vf == essentialContainer or vf == utilityContainer
                        )
                        if isCooldownViewerChild and altChild.cooldownChargesCount ~= nil then
                            ccc = altChild.cooldownChargesCount
                            _dbgCccSource = "altChild"
                            break
                        end
                    end
                end
            end
            ChargeDebug(entry.name, "FWD path: baseSid=", baseSid,
                "maxCharges=", ci.maxCharges, "currentCharges=", ci.currentCharges,
                "ccc=", ccc, "cccSource=", _dbgCccSource or "nil",
                "hasCharges=", entry.hasCharges,
                "overrideSpellID=", entry.overrideSpellID)
            if ccc ~= nil then
                pcall(icon.StackText.SetText, icon.StackText, ccc)
                icon.StackText:Show()
                _chargeCountForwarded = true
            end
        elseif ci and ci.maxCharges then
            ChargeDebug(entry.name, "FWD path CLEAR: baseSid=", baseSid,
                "maxCharges=", ci.maxCharges, "(<=1, clearing stacks)",
                "overrideSpellID=", entry.overrideSpellID)
            icon.StackText:SetText("")
            _chargeCountForwarded = true
        end
    end

    -- Charged entries where the FWD path couldn't find charges:
    -- Blizzard's native ChargeCount.Current (reparented onto our icon)
    -- displays the correct value natively — no fallback forwarding needed.

    if _hookActive or _chargeCountForwarded then
        ChargeDebug(entry.name, "SKIP API path: hookActive=", _hookActive,
            "chargeCountForwarded=", _chargeCountForwarded)
    end
    if not _hookActive and not _chargeCountForwarded then
        if entry.type == "item" then
            -- Item stack text was already set above in the cooldown section;
            -- nothing to do here — just prevent the else clause from clearing it.
        elseif entry.type == "spell" then
            -- Custom spell entry: check charges/stacks via API.
            -- Values may be secret in combat — pass directly to C-side functions
            -- (TruncateWhenZero, SetText) without reading in Lua.
            local spellID = _runtimeSid
            local stackVal  -- raw value (may be secret), forwarded to C-side

            -- Only show charge count when maxCharges > 1 (multi-charge spell).
            -- maxCharges is non-secret (12.0.5+), always readable in combat.
            -- Resource overlay counts (Soul Fragments etc.) are driven by the
            -- hook path (HookBlizzStackText), not the API path.
            local isMultiCharge = _cachedChargeInfo
                and _cachedChargeInfo.maxCharges
                and _cachedChargeInfo.maxCharges > 1

            if isMultiCharge then
                -- GetSpellDisplayCount is the canonical charge display API.
                if spellID and C_Spell.GetSpellDisplayCount then
                    stackVal = TickCacheGetDisplayCount(spellID)
                end
                -- Fallback: currentCharges directly
                if not stackVal and _cachedChargeInfo.currentCharges then
                    stackVal = _cachedChargeInfo.currentCharges
                end
                ChargeDebug(entry.name, "API path: spellID=", spellID,
                    "maxCharges=", _cachedChargeInfo.maxCharges,
                    "currentCharges=", _cachedChargeInfo.currentCharges,
                    "displayCount=", stackVal, "isMultiCharge=", isMultiCharge)
            end


            -- Forward to C-side for display. Multi-charge spells always
            -- show their count (including "0" when depleted). Non-charge
            -- stacks use TruncateWhenZero to hide zero (resource overlays,
            -- non-charge spells that return 0 from GetSpellDisplayCount).
            if stackVal then
                if isMultiCharge then
                    -- Always show charge count — "0" is meaningful
                    pcall(icon.StackText.SetText, icon.StackText, stackVal)
                    icon.StackText:Show()
                else
                    local truncOk, truncText = pcall(C_StringUtil.TruncateWhenZero, stackVal)
                    local displayText = truncOk and truncText or stackVal
                    local hasText = displayText ~= nil
                    if hasText then
                        local etOk, etEq = pcall(function() return displayText == "" end)
                        if etOk and etEq then hasText = false end
                    end
                    if hasText then
                        pcall(icon.StackText.SetText, icon.StackText, displayText)
                        icon.StackText:Show()
                    else
                        icon.StackText:SetText("")
                        icon.StackText:Hide()
                    end
                end
            elseif not InCombatLockdown() then
                icon.StackText:SetText("")
                icon.StackText:Hide()
            end
        else
            -- Harvested entries and other types: hooks drive stack text.
            -- OOC only: clear stacks (hooks are authoritative but may not
            -- have fired yet for this tick).
            if not InCombatLockdown() then

                icon.StackText:SetText("")
                icon.StackText:Hide()
            end
        end
    end

    -- Desaturation for cooldown entries based on cooldown state.
    if icon.Icon and icon.Icon.SetDesaturated then
        local viewerType = entry.viewerType

        -- Skip buff viewer icons and aura-active icons (they show buff timers).
        -- _desaturateIgnoreAura: per-spell override lets charged abilities that
        -- apply auras still desaturate based on charge/CD state while the aura
        -- is active (e.g. a charged debuff spell should grey out when fully depleted).
        local auraBlocks = icon._auraActive and not icon._desaturateIgnoreAura
        if viewerType ~= "buff" and not auraBlocks and not icon._rangeTinted and not icon._usabilityTinted then
            -- Per-spell desaturate override takes precedence over tracker-wide setting
            local desatOverride = icon._spellOverrideDesaturate
            local settings = _hoistedNcdm and _hoistedNcdm[viewerType]
            local shouldDesaturate = settings and settings.desaturateOnCooldown
            if desatOverride == true then
                shouldDesaturate = true
            elseif desatOverride == false then
                shouldDesaturate = false
            end
            if shouldDesaturate then
                -- GCD-only cooldowns should never desaturate.
                -- When on GCD AND we know the real CD is over
                -- (_hasCooldownActive == false, set from the non-secret
                -- isActive field), clear desaturation immediately instead
                -- of waiting for the GCD to end (~1.5s visible delay).
                -- Only preserve existing desaturation during GCD when the
                -- real CD state is unknown (nil / not yet set).
                if icon._isOnGCD then
                    -- isOnGCD == true means the GCD is the dominant cooldown —
                    -- there is no longer real cooldown underneath.  Always clear
                    -- desaturation.  (_hasCooldownActive is unreliable here
                    -- because cdInfo.isActive returns true for GCD itself.)
                    ChargeDebug(entry.name, "DESAT GCD bail: _hasCooldownActive=",
                        icon._hasCooldownActive, "_cdDesaturated=", icon._cdDesaturated,
                        "hasCharges=", entry.hasCharges)
                    if icon._cdDesaturated then
                        icon.Icon:SetDesaturated(false)
                        icon._cdDesaturated = nil
                    end
                    return
                end

                -- Not on GCD: use the cooldown state we already resolved above.
                -- Do not inspect DurationObjects in Lua here.
                local hasRealCD = false
                if not entry.hasCharges then
                    hasRealCD = realCooldownActive == true
                end
                -- _hasCooldownActive fallback: works for both charged and
                -- non-charged entries (isActive accounts for charge state).
                -- For charged entries, only desaturate when ALL charges
                -- are depleted.  GetSpellCooldown.isActive (non-secret) is
                -- false when charges remain (spell castable) and true when
                -- all charges consumed.  Combined with charge.isActive
                -- (non-secret) to confirm recharge is running.
                if not hasRealCD and icon._hasCooldownActive then
                    if entry.hasCharges then
                        local _dsSpellID = _runtimeSid
                        local _dsCdInfo = TickCacheGetCooldown(_dsSpellID)
                        if _dsCdInfo and _dsCdInfo.isActive == true then
                            hasRealCD = true
                        end
                        ChargeDebug(entry.name, "DESAT charged check: _dsSpellID=", _dsSpellID,
                            "_dsCdInfo=", _dsCdInfo and "exists" or "nil",
                            "cdInfo.isActive=", _dsCdInfo and _dsCdInfo.isActive,
                            "_hasCooldownActive=", icon._hasCooldownActive,
                            "hasRealCD=", hasRealCD,
                            "hasCharges=", entry.hasCharges)
                    else
                        hasRealCD = true
                    end
                end

                -- apiIsActive (non-secret, 12.0.5+) is authoritative.
                -- DurationObject remaining can be secret/stale after procs
                -- reset the CD.  When apiIsActive is definitively false,
                -- the CD is over — override the DurationObject signal.
                if hasRealCD and icon._hasCooldownActive == false then
                    hasRealCD = false
                end

                ChargeDebug(entry.name, "DESAT result: hasRealCD=", hasRealCD,
                    "durObj=", durObj and "exists" or "nil",
                    "_hasCooldownActive=", icon._hasCooldownActive,
                    "hasCharges=", entry.hasCharges,
                    "_isOnGCD=", icon._isOnGCD,
                    "viewerType=", entry.viewerType)

                if hasRealCD then
                    icon.Icon:SetDesaturated(true)
                    icon._cdDesaturated = true
                    return
                end

                -- Off cooldown or GCD-only — clear desaturation
                icon.Icon:SetDesaturated(false)
                icon._cdDesaturated = nil
            else
                icon.Icon:SetDesaturated(false)
                icon._cdDesaturated = nil
            end
        else
            icon.Icon:SetDesaturated(false)
            icon._cdDesaturated = nil
        end
    end

    -- Self-heal usability tint: icon rebuilds (BuildIcons via ScanAll)
    -- wipe _usabilityTinted.  Restore from _lastVisualState which
    -- persists on the recycled table when the same spell is re-acquired.
    if icon._lastVisualState == "unusable" and not icon._usabilityTinted and not icon._cdDesaturated then
        icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
        icon._usabilityTinted = true
    end
end

---------------------------------------------------------------------------
-- ICON POOL MANAGEMENT
---------------------------------------------------------------------------
function CDMIcons:AcquireIcon(parent, spellEntry)
    local icon = table.remove(recyclePool)
    if icon then
        icon:SetParent(parent)
        icon:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
        icon._spellEntry = spellEntry
        icon._isQUICDMIcon = true
        icon._lastStart = nil
        icon._lastDuration = nil
        icon._isOnGCD = nil
        icon._wasOnGCD = nil
        icon._showingGCDSwipe = nil
        icon._showingRealCooldownSwipe = nil
        icon._mirrorDriven = nil
        icon._wasShowingGCDSwipe = nil
        icon._hasCooldownActive = nil
        icon._isTotemInstance = nil
        icon._totemSlot = spellEntry and spellEntry._totemSlot or nil
        icon._totemIconCache = nil
        icon._pendingTotemSlotRefresh = nil

        -- Update texture
        local texID
        if spellEntry.type then
            texID = GetEntryTexture(spellEntry)
        else
            texID = GetSpellTexture(spellEntry.overrideSpellID or spellEntry.spellID)
        end
        if icon.Icon then
            if texID then
                icon.Icon:SetTexture(texID)
                -- Only lock texture for cooldown entries — aura icons rely on
                -- the Blizzard texture hook for the correct aura icon.
                icon._desiredTexture = (not spellEntry.isAura) and texID or nil
            else
                -- Clear stale texture from previous owner to prevent
                -- recycled icons showing the wrong spell/item icon.
                icon.Icon:SetTexture(nil)
                icon._desiredTexture = nil
            end
            icon.Icon:SetDesaturated(false)
        end

        if icon.Cooldown then
            icon.Cooldown:Clear()
        end
        icon.StackText:SetText("")
        icon.StackText:Hide()
        -- Update click-to-cast secure attributes for recycled icons
        if spellEntry.viewerType ~= "buff" then
            UpdateIconSecureAttributes(icon, spellEntry, spellEntry.viewerType)
        end
        icon:Hide()
        -- Notify rotation helper that an icon was assigned a spell
        if ns._onIconAssigned then pcall(ns._onIconAssigned, icon) end
        return icon
    end
    local newIcon = CreateIcon(parent, spellEntry)
    -- Update click-to-cast secure attributes for new icons
    if spellEntry.viewerType ~= "buff" then
        UpdateIconSecureAttributes(newIcon, spellEntry, spellEntry.viewerType)
    end
    -- Notify rotation helper that an icon was assigned a spell
    if ns._onIconAssigned then pcall(ns._onIconAssigned, newIcon) end
    return newIcon
end

function CDMIcons:ReleaseIcon(icon)
    if not icon then return end
    -- Disconnect hooks before clearing _spellEntry (needs blizzChild ref)
    UnmirrorBlizzCooldown(icon)
    UnhookBlizzTexture(icon)
    UnhookBlizzStackText(icon)
    if ns._OwnedGlows and ns._OwnedGlows.ClearPandemicState then
        ns._OwnedGlows.ClearPandemicState(icon)
    end
    icon:Hide()
    icon:ClearAllPoints()
    icon._spellEntry = nil
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
    icon._cdDesaturated = nil
    icon._spellOverrideDesaturate = nil
    icon._desaturateIgnoreAura = nil
    icon._lastStart = nil
    icon._lastDuration = nil
    icon._isOnGCD = nil
    icon._wasOnGCD = nil
    icon._showingGCDSwipe = nil
    icon._showingRealCooldownSwipe = nil
    icon._wasShowingGCDSwipe = nil
    icon._hasCooldownActive = nil
    icon._isTotemInstance = nil
    icon._totemSlot = nil
    icon._totemIconCache = nil
    icon._pendingTotemSlotRefresh = nil
    icon._lastLayoutFilterHidden = nil
    -- Reset grey-out child alpha (set by greyOutInactive/greyOutInactiveBuffs)
    icon._greyType = nil
    if icon._greyedOut then
        icon._greyedOut = nil
        if icon.Icon then icon.Icon:SetAlpha(1) end
        if icon.Cooldown then icon.Cooldown:SetAlpha(1) end
        if icon.Border then icon.Border:SetAlpha(1) end
        if icon.DurationText then icon.DurationText:SetAlpha(1) end
        if icon.StackText then icon.StackText:SetAlpha(1) end
    end
    if icon.Icon then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon.Icon:SetDesaturated(false)
    end
    if icon.Cooldown then
        icon.Cooldown:Clear()
    end
    icon.StackText:SetText("")
    icon.Border:Hide()

    -- Clear click-to-cast secure button
    if icon.clickButton then
        if not InCombatLockdown() then
            ClearClickButtonAttributes(icon.clickButton)
            icon.clickButton:Hide()
        end
    end
    icon._pendingSecureUpdate = nil

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        icon:SetParent(UIParent)
        recyclePool[#recyclePool + 1] = icon
    end
end

function CDMIcons:GetIconPool(viewerType)
    return iconPools[viewerType] or {}
end

--- Ensure an icon pool exists for the given container key (Phase G).
function CDMIcons:EnsurePool(viewerType)
    if not iconPools[viewerType] then
        iconPools[viewerType] = {}
    end
end

function CDMIcons:ClearPool(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        for _, icon in ipairs(pool) do
            self:ReleaseIcon(icon)
        end
    end
    iconPools[viewerType] = {}
end


---------------------------------------------------------------------------
-- BUILD ICONS: Create icons from harvested spell data + custom entries
---------------------------------------------------------------------------
function CDMIcons:BuildIcons(viewerType, container)
    if not container then return {} end

    -- Release old icons
    self:ClearPool(viewerType)

    local pool = {}
    local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList(viewerType) or {}

    -- Create icons from harvested spell data
    for _, entry in ipairs(spellData) do
        local icon = self:AcquireIcon(container, entry)
        pool[#pool + 1] = icon
    end

    -- Merge custom entries (essential and utility only)
    if viewerType == "essential" or viewerType == "utility" then
        local customData = GetCustomData(viewerType)
        if customData and customData.enabled and customData.entries then
            local placement = customData.placement or "after"

            -- Separate positioned and unpositioned custom entries
            local positioned = {}
            local unpositioned = {}
            for idx, entry in ipairs(customData.entries) do
                if entry.enabled ~= false then
                    local isSpellType = (entry.type ~= "item" and entry.type ~= "trinket")
                    local spellEntry = {
                        spellID = isSpellType and entry.id or nil,
                        overrideSpellID = isSpellType and entry.id or nil,
                        name = "",
                        isAura = false,
                        layoutIndex = 99000 + idx,
                        viewerType = viewerType,
                        type = entry.type,
                        id = entry.id,
                        _isCustomEntry = true,
                    }
                    -- Get name and resolve IDs per entry type
                    if entry.type == "macro" then
                        spellEntry.macroName = entry.macroName
                        spellEntry.name = entry.macroName or ""
                        -- Resolve current spell for initial texture (updates dynamically)
                        local resolvedID, resolvedType = ResolveMacro(spellEntry)
                        if resolvedID then
                            spellEntry.spellID = resolvedID
                            spellEntry.overrideSpellID = resolvedID
                        end
                    elseif entry.type == "trinket" then
                        -- Trinket entries store equipment slot (13/14), resolve to item ID
                        local itemID = GetInventoryItemID("player", entry.id)
                        if itemID then
                            local itemName = C_Item.GetItemNameByID(itemID)
                            spellEntry.name = itemName or ""
                        end
                    elseif entry.type == "item" then
                        local itemName = C_Item.GetItemNameByID(entry.id)
                        spellEntry.name = itemName or ""
                    else
                        local spellInfo = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.id)
                        spellEntry.name = spellInfo and spellInfo.name or ""
                    end

                    if entry.position and entry.position > 0 then
                        positioned[#positioned + 1] = { entry = spellEntry, position = entry.position, origIndex = idx }
                    else
                        unpositioned[#unpositioned + 1] = spellEntry
                    end
                end
            end

            -- Insert unpositioned entries (before or after harvested icons)
            if #unpositioned > 0 then
                if placement == "before" then
                    local merged = {}
                    for _, entry in ipairs(unpositioned) do
                        local icon = self:AcquireIcon(container, entry)
                        merged[#merged + 1] = icon
                    end
                    for _, icon in ipairs(pool) do
                        merged[#merged + 1] = icon
                    end
                    pool = merged
                else
                    for _, entry in ipairs(unpositioned) do
                        local icon = self:AcquireIcon(container, entry)
                        pool[#pool + 1] = icon
                    end
                end
            end

            -- Insert positioned entries at specific slots (descending to avoid shifts)
            table.sort(positioned, function(a, b)
                if a.position ~= b.position then return a.position > b.position end
                return a.origIndex < b.origIndex
            end)
            for _, item in ipairs(positioned) do
                local icon = self:AcquireIcon(container, item.entry)
                local insertAt = math.min(item.position, #pool + 1)
                table.insert(pool, insertAt, icon)
            end
        end
    end

    -- Initialize owned icons: configure addon CD and mark aura containers
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry then
            local addonCD = icon.Cooldown
            if addonCD then
                addonCD:SetDrawSwipe(true)
                addonCD:SetHideCountdownNumbers(false)
                addonCD:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                addonCD:SetSwipeColor(0, 0, 0, 0.8)
                addonCD:Show()
            end
            -- Mark aura containers so visibility handling works correctly
            local cType = GetContainerTypeForViewer(entry.viewerType)
            if cType == "aura" or cType == "auraBar" then
                icon._auraActive = false  -- will be set true by UpdateIconCooldown when aura present
                icon._auraUnit = nil
                        end
        end
    end

    -- Fallback _blizzChild resolution: if ResolveOwnedEntry couldn't find
    -- a viewer child (e.g., _spellIDToChild wasn't populated yet), retry
    -- now.  Also handles custom entries from GetCustomData which skip
    -- ResolveOwnedEntry entirely. The QUI container the user picked
    -- (essential vs utility) is independent of where Blizzard places the
    -- spell — accept a child from either cooldown viewer so cross-category
    -- placement still mirrors cooldown data.
    if (viewerType == "essential" or viewerType == "utility") and ns.CDMSpellData then
        local spellMap = ns.CDMSpellData._spellIDToChild
        local essentialViewer = _G["EssentialCooldownViewer"]
        local utilityViewer = _G["UtilityCooldownViewer"]
        local essentialContainer = essentialViewer and (essentialViewer.viewerFrame or essentialViewer)
        local utilityContainer = utilityViewer and (utilityViewer.viewerFrame or utilityViewer)
        if spellMap and (essentialViewer or utilityViewer) then
            for _, icon in ipairs(pool) do
                local entry = icon._spellEntry
                if entry and not entry._blizzChild
                    and entry.type ~= "item" and entry.type ~= "trinket" and entry.type ~= "slot" then
                    -- Try all ID variants (same as ResolveOwnedEntry)
                    local searchIDs = {}
                    if entry.overrideSpellID then searchIDs[#searchIDs+1] = entry.overrideSpellID end
                    if entry.spellID and entry.spellID ~= entry.overrideSpellID then searchIDs[#searchIDs+1] = entry.spellID end
                    if entry.id and entry.id ~= entry.spellID and entry.id ~= entry.overrideSpellID then searchIDs[#searchIDs+1] = entry.id end
                    for _, sid in ipairs(searchIDs) do
                        local children = spellMap[sid]
                        if children then
                            for _, child in ipairs(children) do
                                local vf = child.viewerFrame
                                if vf and (vf == essentialViewer or vf == utilityViewer
                                    or vf == essentialContainer or vf == utilityContainer) then
                                    entry._blizzChild = child
                                    break
                                end
                            end
                        end
                        if entry._blizzChild then break end
                    end
                end
            end
        end
    end

    -- Mirror Blizzard viewer children's CooldownFrame updates and texture
    -- hooks onto QUI icons.  Mirror hooks forward SetCooldown /
    -- SetCooldownFromDurationObject calls (including secret values) to our
    -- addon-owned CooldownFrames without touching the Blizzard frames.
    -- Texture hooks mirror spell-replacement icon changes without polling
    -- restricted frames.
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry and entry._blizzChild then
            if not IsTotemSlotEntry(entry) then
                MirrorBlizzCooldown(icon, entry._blizzChild)
                HookBlizzTexture(icon, entry._blizzChild)
                HookBlizzStackText(icon, entry._blizzChild)
            end

            -- Hook pandemic state from Blizzard CDM child
            if ns._OwnedGlows and ns._OwnedGlows.HookBlizzPandemic then
                ns._OwnedGlows.HookBlizzPandemic(icon, entry._blizzChild)
            end

            -- Buff icons are aura containers, but the active state must still
            -- come from UpdateIconCooldown/ResolveAuraState. Pre-marking them
            -- active here makes empty rows render as active-looking.
            if entry.viewerType == "buff" then
                icon._auraActive = false
                icon._auraUnit = nil
                InitBuffVisibility(icon, entry._blizzChild)
            end
        end
    end

    -- Update click-to-cast secure attributes for essential/utility icons.
    -- AcquireIcon sets attrs per-icon, but this catches any pending updates
    -- (e.g., from combat-deferred rebuilds via PLAYER_REGEN_ENABLED).
    if viewerType == "essential" or viewerType == "utility" then
        for _, icon in ipairs(pool) do
            if icon._pendingSecureUpdate then
                UpdateIconSecureAttributes(icon, icon._spellEntry, viewerType)
            end
        end
    end

    iconPools[viewerType] = pool
    ns.CDMSpellData:InvalidateChildMap()  -- New icons may need fresh child map

    -- Immediately update cooldown state so icons reflect correct
    -- desaturation/stack text without waiting for the next ticker.
    self:UpdateCooldownsForType(viewerType)

    return pool
end


---------------------------------------------------------------------------
-- VISIBILITY FILTERS (Phase B.3)
-- Container-level filters that override display-mode visibility based on
-- runtime state. Enabled per-container via settings; all default to off so
-- existing containers behave identically to pre-filter builds.
---------------------------------------------------------------------------

-- Returns true if any visibility filter wants the icon hidden.
local function ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
    if not containerDB then return false end

    if containerDB.showOnlyInCombat and not inCombat then
        return true
    end

    if containerDB.showOnlyOnCooldown then
        local effectiveOnCD = isOnCD
        -- hideGCD: treat pure-GCD as not-on-cooldown for visibility purposes
        if effectiveOnCD and containerDB.hideGCD and icon._isOnGCD
           and not icon._auraActive then
            local dur = icon._lastDuration or 0
            if dur <= 1.5 then effectiveOnCD = false end
        end
        if not effectiveOnCD then return true end
    end

    if containerDB.showOnlyWhenOffCooldown and isOnCD then
        return true
    end

    if containerDB.showOnlyWhenActive and not icon._auraActive then
        return true
    end

    if containerDB.hideNonUsable then
        if entry.type == "item" then
            local ok, count = pcall(C_Item.GetItemCount, entry.id, false, false)
            if ok and (not count or count <= 0) then return true end
        elseif entry.type == "trinket" or entry.type == "slot" then
            if not GetInventoryItemID("player", entry.id) then return true end
        else
            local sid = icon._runtimeSpellID or entry.spellID or entry.id
            if sid then
                -- "Non-usable" includes "player doesn't know this spell at
                -- all" (cross-class entries on a Warrior viewing a Priest
                -- profile's Dispell CDs bar). C_Spell.IsSpellUsable alone
                -- isn't enough — for unknown spells it returns nil, not
                -- false, so a strict `usable == false` check lets cross-
                -- class entries through. Delegate to CDMSpellData:IsSpellKnown
                -- so override-chain and CDM-viewer fallbacks recognize
                -- talent / hero-talent / alternate-ID variants that the
                -- base IsPlayerSpell / IsSpellKnownOrOverridesKnown checks
                -- miss when an entry was added under a different spec.
                local spellData = ns.CDMSpellData
                if spellData and type(spellData.IsSpellKnown) == "function"
                   and not spellData:IsSpellKnown(sid) then
                    return true
                end
                if C_Spell and C_Spell.IsSpellUsable then
                    local ok, usable = pcall(C_Spell.IsSpellUsable, sid)
                    if ok and usable == false then return true end
                end
            end
        end
    end

    return false
end

-- Exposed so LayoutContainer can drop filtered icons at layout time
-- (dynamicLayout = true/nil), letting row width / centering math
-- collapse around missing items instead of leaving a gap.
CDMIcons.ComputeFilterHides = ComputeFilterHides

-- Per-container dirty set. When the runtime visibility update detects an
-- icon's filter verdict has flipped versus the last layout pass (e.g.
-- Mana Tea becoming usable mid-combat with hideNonUsable enabled), it
-- marks the container here. After the per-icon loop in UpdateAllCooldowns
-- / UpdateCooldownOnly we drain the set and call LayoutContainer for each
-- entry so the bar collapses or expands around the slot. With
-- clickableIcons = false, ShouldDeferContainerLayoutInCombat permits the
-- relayout to run in combat instead of waiting for PLAYER_REGEN_ENABLED.
local _layoutNeedsRefresh = {}

local function MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
    if not (entry and entry.viewerType) then return end
    if not containerDB or containerDB.dynamicLayout == false then return end
    local previously = icon._lastLayoutFilterHidden
    -- Only react to flips on icons LayoutContainer actually filter-checked.
    -- Hidden-override drops, missing-entry skips, and static-layout icons
    -- leave _lastLayoutFilterHidden as nil and don't participate.
    if previously == nil then return end
    if filterHidesNow ~= previously then
        _layoutNeedsRefresh[entry.viewerType] = true
    end
end

local function DrainLayoutDirty()
    if next(_layoutNeedsRefresh) == nil then return end
    local force = _G.QUI_ForceLayoutContainer
    if not force then
        wipe(_layoutNeedsRefresh)
        return
    end
    for trackerKey in pairs(_layoutNeedsRefresh) do
        force(trackerKey)
    end
    wipe(_layoutNeedsRefresh)
end

local function GetIconRowOpacity(icon)
    local opacity = icon and icon._rowOpacity
    if opacity == nil then
        return 1
    end
    return opacity
end

local function SetIconRowAlpha(icon, multiplier)
    if not icon then return end
    icon:SetAlpha(GetIconRowOpacity(icon) * (multiplier or 1))
end

-- Apply visibility state respecting dynamicLayout.
-- dynamicLayout = true/nil (default): Hide/Show — bar collapses around hidden icons.
-- dynamicLayout = false:              SetAlpha(0) — slot reserved, icon invisible.
-- Note: static layout (dynamicLayout = false) should not coexist with
-- clickableIcons on the same container — SecureActionButton children
-- cannot be Show/Hide'd in combat. The composer enforces this coupling.
local function ApplyIconVisibility(icon, shouldShow, dynamicLayout)
    if dynamicLayout == false then
        if not icon:IsShown() then icon:Show() end
        icon:SetAlpha(shouldShow and GetIconRowOpacity(icon) or 0)
    else
        if shouldShow then
            if not icon:IsShown() then icon:Show() end
            SetIconRowAlpha(icon)
        else
            if icon:IsShown() then icon:Hide() end
        end
    end
end

local function ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
    if not entry then return nil, "cooldown" end

    local containerDB = ncdm and (ncdm[entry.viewerType] or (ncdmContainers and ncdmContainers[entry.viewerType]))
    local cType = containerDB and containerDB.containerType
    if not cType then
        local vt = entry.viewerType
        cType = (vt == "buff" or vt == "trackedBar") and "aura" or "cooldown"
    end

    return containerDB, cType
end

local function PrepareCooldownUpdateBatch()
    local editMode = Helpers.IsEditModeActive()
        or Helpers.IsLayoutModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())

    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    _hoistedNcdm = ncdm
    _batchTime = GetTime()

    local swipeMod = ns._OwnedSwipe
    local swipeSettings = swipeMod and swipeMod.GetSettings and swipeMod.GetSettings()
    _showGCDSwipe = swipeSettings and swipeSettings.showGCDSwipe or false
    _showBuffSwipe = swipeSettings and (swipeSettings.showBuffSwipe ~= false) or false

    return editMode, ncdm, ncdm and ncdm.containers, InCombatLockdown()
end

local function UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
    local isHiddenOverride = spellOvr and spellOvr.hidden

    if isHiddenOverride then
        if icon:IsShown() then icon:Hide() end
        SyncCooldownBling(icon)
        return
    end

    if editMode then
        icon:SetAlpha(1)
        icon:Show()
        SyncCooldownBling(icon)
        return
    end

    local isOnCD = icon._hasCooldownActive or false
    if not isOnCD then
        local dur = icon._lastDuration or 0
        local start = icon._lastStart or 0
        if dur > 1.5 and start > 0 then
            local remaining = (start + dur) - _batchTime
            if remaining > 0 then
                isOnCD = true
            end
        end
    end

    if not isOnCD and entry.hasCharges then
        local spellID = icon._runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
        if spellID then
            local ci = TickCacheGetCharges(spellID)
            if ci then
                local current = SafeToNumber(ci.currentCharges, nil)
                local maxC = SafeToNumber(ci.maxCharges, nil)
                if current and maxC and current < maxC then
                    isOnCD = true
                end
            end
        end
    end

    local effectiveMode = containerDB and containerDB.iconDisplayMode or "always"
    if effectiveMode == "combat" then
        effectiveMode = inCombat and "always" or "active"
    end

    local shouldShow
    if effectiveMode == "always" then
        shouldShow = true
    elseif effectiveMode == "active" then
        if isOnCD then
            shouldShow = true
        else
            local keepForGlow = false
            if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
            end
            shouldShow = keepForGlow
        end
    else
        shouldShow = false
    end

    -- Compute filter unconditionally (not gated on shouldShow) so the
    -- mismatch detector sees the latest verdict even when display mode
    -- has already hidden the icon.
    local filterHidesNow = ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
    if filterHidesNow then shouldShow = false end
    MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)

    ApplyIconVisibility(icon, shouldShow, containerDB and containerDB.dynamicLayout)
    SyncCooldownBling(icon)
end

---------------------------------------------------------------------------
-- UPDATE ALL COOLDOWNS
---------------------------------------------------------------------------
function CDMIcons:UpdateAllCooldowns(keepTickCaches)
    -- Wipe per-tick caches: each batch starts fresh so every spellID
    -- is queried at most once via TickCacheGetCharges/TickCacheGetCooldown.
    WipeUpdateTickCaches()
    _tickCooldownStats.updateBatches = _tickCooldownStats.updateBatches + 1
    _tickCooldownStats.fullUpdateBatches = _tickCooldownStats.fullUpdateBatches + 1

    -- Child map is invalidated by aura/structural event subscribers via
    -- CDMSpellData:InvalidateChildMap(). RebuildChildMap is a no-op when clean.

    local editMode = Helpers.IsEditModeActive()
        or Helpers.IsLayoutModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())

    -- Hoist DB lookups above the loop (avoids 4 table hops per icon).
    -- Also set file-scoped _hoistedNcdm so UpdateIconCooldown can read it
    -- without re-walking the chain for every icon.
    local _ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    _hoistedNcdm = _ncdm  -- consumed by UpdateIconCooldown
    _batchTime = GetTime()  -- consumed by UpdateIconCooldown + visibility loop
    -- Hoist GCD swipe setting so per-icon code can check it without DB lookups.
    local _swipeMod = ns._OwnedSwipe
    local _swipeSettings = _swipeMod and _swipeMod.GetSettings and _swipeMod.GetSettings()
    _showGCDSwipe = _swipeSettings and _swipeSettings.showGCDSwipe or false
    _showBuffSwipe = _swipeSettings and (_swipeSettings.showBuffSwipe ~= false) or false
    local _ncdmContainers = _ncdm and _ncdm.containers
    local inCombat = InCombatLockdown()

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            _tickCooldownStats.iconsProcessed = _tickCooldownStats.iconsProcessed + 1
            local entry = icon._spellEntry
            -- Update cooldown/aura state BEFORE visibility so _auraActive,
            -- _lastDuration, etc. are fresh for Show/Hide decisions.
            -- pcall only needed during combat (secret values from Blizzard
            -- frames) — skip overhead during OOC for ~50% less pcall cost.
            if inCombat then
                pcall(UpdateIconCooldown, icon)
            else
                UpdateIconCooldown(icon)
            end

            -- Per-spell hidden override: always hide regardless of display mode
            local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
            local isHiddenOverride = spellOvr and spellOvr.hidden

            if entry then
                -- Visibility based on container type + display mode
                local containerDB = _ncdm and (_ncdm[entry.viewerType] or (_ncdmContainers and _ncdmContainers[entry.viewerType]))
                local cType = containerDB and containerDB.containerType
                if not cType then
                    -- Built-in buff and trackedBar are aura containers even without
                    -- an explicit containerType (they predate the Composer).
                    local vt = entry.viewerType
                    cType = (vt == "buff" or vt == "trackedBar") and "aura" or "cooldown"
                end
                local displayMode = containerDB and containerDB.iconDisplayMode or "always"

                if isHiddenOverride then
                    -- Per-spell hidden override: always hide owned entries
                    if icon:IsShown() then icon:Hide() end
                elseif editMode then
                    icon:SetAlpha(1)
                    icon:Show()
                elseif cType == "aura" or cType == "auraBar" then
                    -- Aura containers: visibility depends on display mode + aura state
                    local isActive = icon._auraActive
                    local effectiveMode = displayMode
                    if effectiveMode == "combat" then
                        effectiveMode = inCombat and "always" or "active"
                    end

                    if effectiveMode == "always" then
                        local rowOpacity = icon._rowOpacity or 1
                        if isActive then
                            icon:SetAlpha(rowOpacity)
                        else
                            -- Desaturate placeholder when aura is absent
                            icon:SetAlpha(rowOpacity * 0.3)
                            if icon.Icon and icon.Icon.SetDesaturated then
                                icon.Icon:SetDesaturated(true)
                            end
                        end
                        if not icon:IsShown() then icon:Show() end
                    elseif effectiveMode == "active" then
                        if isActive then
                            local rowOpacity = icon._rowOpacity or 1
                            icon:SetAlpha(rowOpacity)
                            if not icon:IsShown() then icon:Show() end
                        else
                            if icon:IsShown() then icon:Hide() end
                        end
                    end

                    -- Clear desaturation when aura is active
                    if isActive and icon.Icon and icon.Icon.SetDesaturated then
                        icon.Icon:SetDesaturated(false)
                    end
                else
                    -- Cooldown containers: visibility depends on display mode.
                    -- _hasCooldownActive is set when a DurationObject was applied
                    -- (works even when numeric start/dur are secret in combat).
                    local isOnCD = icon._hasCooldownActive or false
                    if not isOnCD then
                        local dur = icon._lastDuration or 0
                        local start = icon._lastStart or 0
                        if dur > 1.5 and start > 0 then
                            local remaining = (start + dur) - _batchTime
                            if remaining > 0 then
                                isOnCD = true
                            end
                        end
                    end
                    -- Also check charge-based cooldowns (per-tick cached)
                    if not isOnCD and entry.hasCharges then
                        local spellID = icon._runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
                        if spellID then
                            local ci = TickCacheGetCharges(spellID)
                            if ci then
                                local current = SafeToNumber(ci.currentCharges, nil)
                                local maxC = SafeToNumber(ci.maxCharges, nil)
                                if current and maxC and current < maxC then
                                    isOnCD = true
                                end
                            end
                        end
                    end

                    local effectiveMode = displayMode
                    if effectiveMode == "combat" then
                        effectiveMode = inCombat and "always" or "active"
                    end

                    if effectiveMode == "always" then
                        if not icon:IsShown() then icon:Show() end
                    elseif effectiveMode == "active" then
                        if isOnCD then
                            if not icon:IsShown() then icon:Show() end
                        else
                            -- Keep proc-ready icons visible in active mode, not just
                            -- procOnUsable overrides. Blizzard CDM can raise overlay
                            -- glows for off-cooldown spells that should still appear.
                            local keepForGlow = false
                            if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                                keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
                            end
                            if keepForGlow then
                                local wasHidden = not icon:IsShown()
                                if wasHidden then
                                    icon:Show()
                                end
                                if ns._OwnedGlows and ns._OwnedGlows.SyncGlowForIcon then
                                    ns._OwnedGlows.SyncGlowForIcon(icon)
                                end
                            elseif icon:IsShown() then
                                if ns._OwnedGlows and ns._OwnedGlows.StopGlow then
                                    ns._OwnedGlows.StopGlow(icon)
                                end
                                icon:Hide()
                            end
                        end
                    end

                    -- Container-level visibility filters (hideNonUsable,
                    -- showOnly* etc). Computed unconditionally so the
                    -- dirty-tracker sees the verdict even when the display
                    -- mode block above has already hidden the icon. If the
                    -- filter flips versus the last layout pass, the bar is
                    -- relayouted at the end of the per-icon loop.
                    local filterHidesNow = ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
                    if filterHidesNow and icon:IsShown() then
                        icon:Hide()
                    end
                    MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)

                    -- Grey out when linked debuff/buff not active
                    -- greyOutInactive = my debuffs on target, greyOutInactiveBuffs = buffs on player
                    local greyOutDebuffs = containerDB and containerDB.greyOutInactive
                    local greyOutBuffs = containerDB and containerDB.greyOutInactiveBuffs
                    local shouldGreyOut = false
                    if (greyOutDebuffs or greyOutBuffs) and icon.Icon and icon.Icon.SetDesaturated then
                        -- Only apply to spells that have aura tracking (linked auras,
                        -- global ability→aura mapping, or detected via ResolveAuraState).
                        local hasAuraLink = entry.linkedSpellIDs
                            or (icon._spellEntry and icon._spellEntry.linkedSpellIDs)
                            or (ns.CDMSpellData and ns.CDMSpellData._abilityToAuraSpellID
                                and ns.CDMSpellData._abilityToAuraSpellID[entry.id])
                            or icon._auraActive ~= nil
                        if hasAuraLink then
                            -- Resolve spell name for aura lookups
                            local spellName = entry.name
                            if not spellName then
                                local sid = icon._runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
                                if sid then
                                    local info = C_Spell.GetSpellInfo(sid)
                                    spellName = info and info.name
                                end
                            end

                            -- Debuff grey-out: requires valid attackable target.
                            -- Uses HARMFUL filter to find debuff on target, then
                            -- checks isFromPlayerOrPlayerPet for ownership.
                            -- Classify spell as debuff/buff once via WoW API.
                            -- IsHarmfulSpell → targets enemies (debuff spell)
                            -- IsHelpfulSpell → targets self/allies (buff spell)
                            if not icon._greyType and spellName then
                                local harmOk, isHarm = pcall(function()
                                    if C_Spell and C_Spell.IsSpellHarmful then return C_Spell.IsSpellHarmful(spellName) end
                                    if IsHarmfulSpell then return IsHarmfulSpell(spellName) end
                                end)
                                local helpOk, isHelp = pcall(function()
                                    if C_Spell and C_Spell.IsSpellHelpful then return C_Spell.IsSpellHelpful(spellName) end
                                    if IsHelpfulSpell then return IsHelpfulSpell(spellName) end
                                end)
                                if harmOk and isHarm then
                                    icon._greyType = "debuff"
                                elseif helpOk and isHelp then
                                    icon._greyType = "buff"
                                end
                            end

                            -- Debuff grey-out: requires valid attackable target.
                            -- Uses _auraActive (combat-safe, driven by hook
                            -- cache from CDM viewer children which only track
                            -- the player's own spells).
                            if greyOutDebuffs and icon._greyType == "debuff" then
                                local hasTarget = UnitExists("target")
                                    and not UnitIsDead("target")
                                    and UnitCanAttack("player", "target")
                                if hasTarget and not icon._auraActive then
                                    shouldGreyOut = true
                                end
                            end
                            -- Buff grey-out: same _auraActive approach.
                            if not shouldGreyOut and greyOutBuffs
                               and icon._greyType == "buff" then
                                if not icon._auraActive then
                                    shouldGreyOut = true
                                end
                            end
                        end
                    end
                    if shouldGreyOut then
                        if not icon._greyedOut then
                            -- Dim children instead of the frame itself so
                            -- GameTooltip:SetOwner still works (WoW hides
                            -- tooltips when the owner's effective alpha is
                            -- below ~0.5).
                            if icon.Icon then icon.Icon:SetAlpha(0.4) end
                            if icon.Cooldown then icon.Cooldown:SetAlpha(0.4) end
                            if icon.Border then icon.Border:SetAlpha(0.4) end
                            if icon.DurationText then icon.DurationText:SetAlpha(0.4) end
                            if icon.StackText then icon.StackText:SetAlpha(0.4) end
                            if not icon._cdDesaturated then
                                icon.Icon:SetDesaturated(true)
                            end
                            icon._greyedOut = true
                        end
                    elseif icon._greyedOut then
                        if icon.Icon then icon.Icon:SetAlpha(1) end
                        if icon.Cooldown then icon.Cooldown:SetAlpha(1) end
                        if icon.Border then icon.Border:SetAlpha(1) end
                        if icon.DurationText then icon.DurationText:SetAlpha(1) end
                        if icon.StackText then icon.StackText:SetAlpha(1) end
                        if icon.Icon and icon.Icon.SetDesaturated and not icon._cdDesaturated then
                            icon.Icon:SetDesaturated(false)
                        end
                        icon._greyedOut = nil
                    end
                end
                SyncCooldownBling(icon)
            end
        end
    end

    -- After the per-icon visibility loop, relayout any container whose
    -- filter verdict flipped since the last layout pass.
    DrainLayoutDirty()

    if not keepTickCaches then
        WipeUpdateTickCaches()
    end
end

function CDMIcons:UpdateCooldownOnly(keepTickCaches)
    WipeUpdateTickCaches()
    _tickCooldownStats.updateBatches = _tickCooldownStats.updateBatches + 1
    _tickCooldownStats.cooldownOnlyBatches = _tickCooldownStats.cooldownOnlyBatches + 1

    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon._spellEntry
            if entry then
                local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
                if cType ~= "aura" and cType ~= "auraBar" then
                    _tickCooldownStats.iconsProcessed = _tickCooldownStats.iconsProcessed + 1
                    if inCombat then
                        pcall(UpdateIconCooldown, icon)
                    else
                        UpdateIconCooldown(icon)
                    end
                    UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
                end
            end
        end
    end

    -- After the per-icon visibility loop, relayout any container whose
    -- filter verdict flipped since the last layout pass.
    DrainLayoutDirty()

    if not keepTickCaches then
        WipeUpdateTickCaches()
    end
end

function CDMIcons:UpdateCooldownsForType(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        for _, icon in ipairs(pool) do
            UpdateIconCooldown(icon)
        end
    end
end

-- DEBUG: /cdmicondebug — toggle per-tick icon state dump.
---------------------------------------------------------------------------
SLASH_QUI_CDMICONDEBUG1 = "/cdmicondebug"
SlashCmdList["QUI_CDMICONDEBUG"] = function(msg)
    local filter = msg and strtrim(msg) or ""
    if filter == "" then
        _G.QUI_CDM_ICON_DEBUG = not _G.QUI_CDM_ICON_DEBUG
        print("|cff34D399[CDM-IconDebug]|r", _G.QUI_CDM_ICON_DEBUG and "ON (all icons)" or "OFF")
        return
    end
    _G.QUI_CDM_ICON_DEBUG = filter
    print("|cff34D399[CDM-IconDebug]|r ON - filter:", filter)
end

local function ShouldDebugIcon(icon)
    local dbg = _G.QUI_CDM_ICON_DEBUG
    if not dbg then return false end
    local entry = icon and icon._spellEntry
    if not entry then
        return false
    end
    if dbg == true then return true end
    local filter = tostring(dbg):lower()
    local name = entry and entry.name and tostring(entry.name):lower() or ""
    local sid = icon and icon._runtimeSpellID and tostring(icon._runtimeSpellID) or ""
    local eid = entry and entry.id and tostring(entry.id) or ""
    return name:find(filter, 1, true) ~= nil
        or sid == filter
        or eid == filter
end

DebugIconSwipe = function(icon, ...)
    if not ShouldDebugIcon(icon) then return end
    print("|cff34D399[CDM-IconSwipe]|r", ...)
end

DumpDebugIcon = function(icon)
    if not ShouldDebugIcon(icon) then return end
    local Helpers = ns.Helpers
    local entry = icon and icon._spellEntry
    if not entry then return end
    local P = "|cff34D399[CDM-IconDbg]|r"
    print(P, entry.name or "?", "viewerType=", tostring(entry.viewerType),
        "spellID=", tostring(entry.spellID), "entry.id=", tostring(entry.id))
    print(P, "  shown=", tostring(icon:IsShown()),
        "auraActive=", tostring(icon._auraActive),
        "isTotemInstance=", tostring(icon._isTotemInstance),
        "entry._totemSlot=", tostring(entry._totemSlot),
        "icon._totemSlot=", tostring(icon._totemSlot),
        "instanceKey=", tostring(entry._instanceKey))
    if icon.Icon and icon.Icon.GetTexture then
        local okTex, tex = pcall(icon.Icon.GetTexture, icon.Icon)
        print(P, "  iconTexture=", okTex and tostring(tex) or "err")
    end
    if icon.StackText and icon.StackText.GetText then
        local okStack, stack = pcall(icon.StackText.GetText, icon.StackText)
        print(P, "  stackText=", okStack and tostring(Helpers.SafeValue(stack, "secret")) or "err")
    end
    if icon.DurationText and icon.DurationText.GetText then
        local okDur, dur = pcall(icon.DurationText.GetText, icon.DurationText)
        print(P, "  durationText=", okDur and tostring(Helpers.SafeValue(dur, "secret")) or "err")
    end
    local blz = entry._blizzChild
    if blz then
        print(P, "  blizzChild layoutIndex=",
            tostring(Helpers.SafeValue(rawget(blz, "layoutIndex"), "secret")),
            "prefSlot=", tostring(Helpers.SafeValue(rawget(blz, "preferredTotemUpdateSlot"), "secret")),
            "auraInstanceID=", tostring(Helpers.SafeValue(rawget(blz, "auraInstanceID"), "secret")))
        if blz.GetSpellID then
            local ok, gsid = pcall(blz.GetSpellID, blz)
            print(P, "  blizzChild:GetSpellID()=", ok and Helpers.SafeValue(gsid, "secret") or "err")
        end
    else
        print(P, "  blizzChild=nil")
    end
    local blzBar = entry._blizzBarChild
    if blzBar then
        print(P, "  blizzBarChild layoutIndex=",
            tostring(Helpers.SafeValue(rawget(blzBar, "layoutIndex"), "secret")),
            "prefSlot=", tostring(Helpers.SafeValue(rawget(blzBar, "preferredTotemUpdateSlot"), "secret")),
            "auraInstanceID=", tostring(Helpers.SafeValue(rawget(blzBar, "auraInstanceID"), "secret")))
        if blzBar.GetSpellID then
            local ok, gsid = pcall(blzBar.GetSpellID, blzBar)
            print(P, "  blizzBarChild:GetSpellID()=", ok and Helpers.SafeValue(gsid, "secret") or "err")
        end
    else
        print(P, "  blizzBarChild=nil")
    end
end

-- The 500ms update ticker has been removed — event-driven coalescing
-- (SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_CHARGES, BAG_UPDATE_COOLDOWN,
-- UNIT_AURA) handles all cooldown/aura state changes.  A one-shot
-- catch-up fires on PLAYER_REGEN_ENABLED below.
function CDMIcons:StartUpdateTicker() end  -- no-op (kept for API compat)
function CDMIcons:StopUpdateTicker() end   -- no-op

---------------------------------------------------------------------------
-- CONFIGURE ICON (public wrapper)
---------------------------------------------------------------------------
CDMIcons.ConfigureIcon = ConfigureIcon
CDMIcons.UpdateIconCooldown = UpdateIconCooldown
CDMIcons.ApplyTexCoord = ApplyTexCoord
CDMIcons.UpdateIconSecureAttributes = UpdateIconSecureAttributes

---------------------------------------------------------------------------
-- CUSTOM ENTRY MANAGEMENT (backward-compatible API surface)
-- These methods are called by the options panel via ns.CustomCDM
---------------------------------------------------------------------------
function CustomCDM:GetEntryName(entry)
    if not entry then return "Unknown" end
    if entry.type == "macro" then
        return entry.macroName or "Macro"
    end
    if entry.type == "trinket" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            return C_Item.GetItemNameByID(itemID) or "Trinket (Slot " .. tostring(entry.id) .. ")"
        end
        return "Trinket (Slot " .. tostring(entry.id) .. ")"
    end
    if entry.type == "item" then
        return C_Item.GetItemNameByID(entry.id) or "Item #" .. tostring(entry.id)
    end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.id)
    return info and info.name or "Spell #" .. tostring(entry.id)
end

function CustomCDM:AddEntry(trackerKey, entryType, entryID)
    if entryType == "macro" then
        -- entryID is the macro name (string)
        if not entryID or type(entryID) ~= "string" or entryID == "" then return false end
        local macroIndex = GetMacroIndexByName(entryID)
        if not macroIndex or macroIndex == 0 then return false end
    else
        if not entryID or type(entryID) ~= "number" then return false end
    end
    if entryType ~= "spell" and entryType ~= "item" and entryType ~= "trinket" and entryType ~= "macro" then return false end

    -- Resolve the active profile/spec-aware bucket so the options UI, runtime
    -- renderer, and mutations all operate on the same saved table.
    local customData = GetCustomData(trackerKey)
    if not customData then return false end
    if customData.enabled == nil then customData.enabled = true end
    if customData.placement ~= "before" and customData.placement ~= "after" then
        customData.placement = "after"
    end
    if type(customData.entries) ~= "table" then
        customData.entries = {}
    end

    -- Duplicate check
    for _, entry in ipairs(customData.entries) do
        if entryType == "macro" then
            if entry.type == "macro" and entry.macroName == entryID then
                return false
            end
        else
            if entry.type == entryType and entry.id == entryID then
                return false
            end
        end
    end

    local newEntry
    if entryType == "macro" then
        newEntry = { macroName = entryID, type = "macro", enabled = true }
    else
        newEntry = { id = entryID, type = entryType, enabled = true }
    end
    customData.entries[#customData.entries + 1] = newEntry

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    return true
end

function CustomCDM:RemoveEntry(trackerKey, entryIndex)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries then return end
    if entryIndex < 1 or entryIndex > #customData.entries then return end

    table.remove(customData.entries, entryIndex)
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:SetEntryEnabled(trackerKey, entryIndex, enabled)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries or not customData.entries[entryIndex] then return end

    customData.entries[entryIndex].enabled = enabled
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:SetEntryPosition(trackerKey, entryIndex, position)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries or not customData.entries[entryIndex] then return false end

    if position ~= nil then
        position = tonumber(position)
        if not position or position < 1 then
            return false
        end
        position = math.floor(position + 0.5)
    end

    customData.entries[entryIndex].position = position
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    return true
end

function CustomCDM:MoveEntry(trackerKey, fromIndex, direction)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries then return end

    local entries = customData.entries
    local toIndex = fromIndex + direction
    if toIndex < 1 or toIndex > #entries then return end

    entries[fromIndex], entries[toIndex] = entries[toIndex], entries[fromIndex]
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end

function CustomCDM:TransferEntry(fromTrackerKey, entryIndex, toTrackerKey)
    local fromData = GetCustomData(fromTrackerKey)
    if not fromData or not fromData.entries then return end
    if entryIndex < 1 or entryIndex > #fromData.entries then return end

    local entry = fromData.entries[entryIndex]

    local toData = GetCustomData(toTrackerKey)
    if not toData then return end
    if not toData.entries then toData.entries = {} end

    -- Duplicate check in destination
    for _, existing in ipairs(toData.entries) do
        if entry.type == "macro" then
            if existing.type == "macro" and existing.macroName == entry.macroName then return end
        else
            if existing.type == entry.type and existing.id == entry.id then return end
        end
    end

    table.remove(fromData.entries, entryIndex)
    toData.entries[#toData.entries + 1] = entry

    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end


-- Legacy compat: GetIcons returns the pool for a viewer name.
-- Return empty for unknown viewer names so external callers cannot adopt and
-- reposition addon-owned icons onto the Blizzard viewers.
function CustomCDM:GetIcons(viewerName)
    -- Only return icons when asked for addon-owned container names.
    if viewerName == "QUI_EssentialContainer" then
        return iconPools["essential"] or {}
    elseif viewerName == "QUI_UtilityContainer" then
        return iconPools["utility"] or {}
    end
    return {}
end

function CustomCDM:StartUpdateTicker() CDMIcons:StartUpdateTicker() end
function CustomCDM:StopUpdateTicker() CDMIcons:StopUpdateTicker() end
function CustomCDM:UpdateAllCooldowns() CDMIcons:UpdateAllCooldowns() end

---------------------------------------------------------------------------
-- RANGE INDICATOR
-- Tints CDM icon textures red when the spell/item is out of range,
-- matching action-bar behavior. Uses C_Spell.IsSpellInRange for spells.
-- Polled at 250ms (no "player moved" event) + instant on target change.
---------------------------------------------------------------------------
local RANGE_POLL_INTERVAL_COMBAT = 0.75
local RANGE_POLL_INTERVAL_IDLE = 2.0   -- relaxed OOC (range matters less)
local rangePollElapsed = 0
local rangePollInCombat = false

-- Resolve effective unit for range checks: hard target > soft enemy.
-- Blizzard's IsActionInRange handles soft targeting on the C side; we
-- replicate the same priority for C_Spell.IsSpellInRange.
local function GetRangeUnit()
    if UnitExists("target") then return "target" end
    if UnitExists("softenemy") then return "softenemy" end
    return nil
end

-- Safe wrapper: C_Spell.IsSpellInRange can return secret values in Midnight.
-- Calls pcall directly (no closure allocation).
local function SafeIsSpellInRange(spellID, unit)
    if not spellID or not unit or not C_Spell or not C_Spell.IsSpellInRange then return nil end
    local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
    if not ok then return nil end
    if inRange == false then return false end
    if inRange == true then return true end
    return nil
end

-- Safe wrapper: C_Spell.IsSpellUsable can return secret values in Midnight.
-- Calls pcall directly (no closure allocation).
local function SafeIsSpellUsable(spellID)
    if not spellID or not C_Spell or not C_Spell.IsSpellUsable then return true, false end
    local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, spellID)
    if not ok then return true, false end  -- Secret value: assume usable
    -- Convert potential secret booleans to real booleans
    return usable and true or false, noMana and true or false
end

-- Per-cycle dedup caches: avoid calling the same C_Spell API for the same
-- spellID when multiple icons track the same ability.
local _rangeCycleCache = {}     -- [spellID] = true/false/"nil" (string "nil" for actual nil results)
local _hasRangeCycleCache = {}  -- [spellID] = true/false
local _usableCycleCache = {}    -- [spellID] = true/false

-- Reset icon to normal visual state (clear any tinting)
local function ResetIconVisuals(icon)
    icon.Icon:SetVertexColor(1, 1, 1, 1)
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
end

local function UpdateIconVisualState(icon, cachedDB)
    if not icon or not icon._spellEntry then return end
    local entry = icon._spellEntry
    local viewerType = entry.viewerType
    if not viewerType then return end

    local settings = cachedDB and cachedDB[viewerType] or GetTrackerSettings(viewerType)
    if not settings then
        if icon._rangeTinted or icon._usabilityTinted then
            icon._lastVisualState = nil
            ResetIconVisuals(icon)
        end
        return
    end

    local rangeEnabled = settings.rangeIndicator
    local usabilityEnabled = settings.usabilityIndicator

    -- Nothing enabled — reset and bail
    if not rangeEnabled and not usabilityEnabled then
        if icon._rangeTinted or icon._usabilityTinted then
            icon._lastVisualState = nil
            ResetIconVisuals(icon)
        end
        return
    end

    -- Skip buff viewer icons
    if viewerType == "buff" then return end

    -- Skip items/trinkets (self-use, no range/usability concept)
    if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then return end

    -- Resolve current spell ID (prefer cached override from cooldown update cycle
    -- to avoid redundant GetOverrideSpell API calls during range polling)
    local spellID = entry.spellID or entry.id
    if icon._cachedOverrideID then
        spellID = icon._cachedOverrideID
    elseif C_Spell and C_Spell.GetOverrideSpell then
        local currentOverride = TickCacheGetOverrideSpell(entry.spellID or entry.id)
        if currentOverride then spellID = currentOverride end
    end
    if not spellID then return end

    ---------------------------------------------------------------------------
    -- Compute desired visual state (API calls use per-cycle dedup caches)
    ---------------------------------------------------------------------------
    local newVisualState = "normal"

    -- Priority 1: Out of range (red tint) — only when attackable unit exists
    -- Respects soft targeting: hard target > soft enemy.
    local rangeUnit = rangeEnabled and GetRangeUnit() or nil
    if rangeUnit then
        -- Per-cycle dedup: skip redundant C_Spell API calls for shared spellIDs
        local hasRange = _hasRangeCycleCache[spellID]
        if hasRange == nil then
            hasRange = (not C_Spell.SpellHasRange) or C_Spell.SpellHasRange(spellID)
            _hasRangeCycleCache[spellID] = hasRange and true or false
        end
        if hasRange then
            local cached = _rangeCycleCache[spellID]
            local inRange
            if cached ~= nil then
                inRange = cached ~= "nil" and cached or nil
            else
                inRange = SafeIsSpellInRange(spellID, rangeUnit)
                _rangeCycleCache[spellID] = inRange == nil and "nil" or inRange
            end
            if inRange == false then
                newVisualState = "oor"
            end
        end
    end

    -- Priority 2: Unusable / resource-starved (darken) — only if not already OOR
    if newVisualState == "normal" and usabilityEnabled then
        -- Per-cycle dedup: reuse result for shared spellIDs
        local isUsable = _usableCycleCache[spellID]
        if isUsable == nil then
            isUsable = SafeIsSpellUsable(spellID)
            _usableCycleCache[spellID] = isUsable
        end
        if not isUsable then
            newVisualState = "unusable"
        end
    end

    ---------------------------------------------------------------------------
    -- State-change gating: skip SetVertexColor if visual state unchanged.
    -- Self-heal: if state is "unusable" but tint was stripped (e.g. by an
    -- icon rebuild or texture update), reapply the vertex color.
    ---------------------------------------------------------------------------
    if icon._lastVisualState == newVisualState then
        if newVisualState == "unusable" and not icon._usabilityTinted and not icon._cdDesaturated then
            icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
            icon._usabilityTinted = true
        end
        return
    end
    icon._lastVisualState = newVisualState

    ---------------------------------------------------------------------------
    -- Apply the computed visual state
    ---------------------------------------------------------------------------
    if newVisualState == "oor" then
        -- Clear usability darkening if switching to range tint
        if icon._usabilityTinted then
            icon._usabilityTinted = nil
        end
        local c = settings.rangeColor
        local r = c and c[1] or 0.8
        local g = c and c[2] or 0.1
        local b = c and c[3] or 0.1
        local a = c and c[4] or 1
        icon.Icon:SetVertexColor(r, g, b, a)
        icon._rangeTinted = true
        return
    end

    -- If was range-tinted but now in range, clear it
    if icon._rangeTinted then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon._rangeTinted = nil
    end

    if newVisualState == "unusable" then
        -- Don't override cooldown desaturation — it takes visual priority.
        -- When the CD ends, desaturation clears and the next range poll
        -- applies usability tint.
        if icon._cdDesaturated then
            -- Reset _lastVisualState so the state-change gate fires again
            -- once desaturation clears and the tint can actually apply.
            icon._lastVisualState = nil
            return
        end
        icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
        icon._usabilityTinted = true
        return
    end

    -- If was usability-tinted but now usable, clear it
    if icon._usabilityTinted then
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        icon._usabilityTinted = nil
    end
end

function CDMIcons:UpdateAllIconRanges()
    -- Wipe per-cycle dedup caches so each poll starts fresh
    wipe(_rangeCycleCache)
    wipe(_hasRangeCycleCache)
    wipe(_usableCycleCache)
    -- Hoist DB lookup above the loop (avoids repeated GetDB per icon)
    local db = GetDB()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            UpdateIconVisualState(icon, db)
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING: Update cooldowns on relevant events
---------------------------------------------------------------------------
local cdEventFrame = CreateFrame("Frame")
cdEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cdEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
cdEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
cdEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
cdEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cdEventFrame:RegisterEvent("UPDATE_MACROS")
cdEventFrame:RegisterEvent("SPELLS_CHANGED")
cdEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
cdEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
cdEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
-- Server-side cooldown table hotfix. User /cdm edits route through
-- EventRegistry's "CooldownViewerSettings.OnDataChanged" callback (see
-- registration below) — they are NOT the same event.
cdEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
-- UNIT_AURA handled by centralized dispatcher subscription (below)

-- Frame-based coalescing for cooldown/aura events. Pure cooldown events use a
-- lighter icon pass; aura and structural events upgrade the pending batch to a
-- full refresh. Avoid C_Timer here: raid combat can schedule this path
-- continuously, and timer objects become pure churn.
local CDM_MIN_UPDATE_INTERVAL_IDLE = 0.05
local CDM_MIN_UPDATE_INTERVAL_COMBAT = 0.20
local CDM_MIN_UPDATE_INTERVAL_RAID_COMBAT = 0.30
local _lastCDMUpdateTime = 0
local CDM_UPDATE_COOLDOWN = "cooldown"
local CDM_UPDATE_FULL = "full"

local cdmUpdateFrame = CreateFrame("Frame")
local _cdmUpdatePending = false
local _cdmUpdateElapsed = 0
local _cdmUpdateDelay = CDM_MIN_UPDATE_INTERVAL_IDLE
local _cdmUpdateMode = CDM_UPDATE_COOLDOWN

-- Bars are aura-state driven (active/inactive transitions). Gate UpdateOwnedBars
-- behind a dirty flag so pure cooldown-event flurries (SPELL_UPDATE_COOLDOWN
-- fires constantly in raid) don't walk the bar pool on every coalesce tick.
-- Flag is raised only by aura/full-refresh paths; cleared when UpdateOwnedBars
-- runs.
local _barsDirty = false

local function _CDMUpdateCallback()
    _cdmUpdatePending = false
    local mode = _cdmUpdateMode or CDM_UPDATE_COOLDOWN
    _cdmUpdateMode = CDM_UPDATE_COOLDOWN
    _lastCDMUpdateTime = GetTime()

    if mode == CDM_UPDATE_FULL then
        CDMIcons:UpdateAllCooldowns(true)
        if _barsDirty and ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
            _barsDirty = false
            ns.CDMBars:UpdateOwnedBars()
        end
    else
        CDMIcons:UpdateCooldownOnly(true)
    end

    WipeUpdateTickCaches()
end

local function CDMUpdateOnUpdate(self, elapsed)
    _cdmUpdateElapsed = _cdmUpdateElapsed + elapsed
    if _cdmUpdateElapsed < _cdmUpdateDelay then return end
    self:SetScript("OnUpdate", nil)
    _CDMUpdateCallback()
end

local function GetCDMUpdateDelay(fast)
    if not InCombatLockdown() then
        return fast and CDM_MIN_UPDATE_INTERVAL_IDLE or CDM_MIN_UPDATE_INTERVAL_IDLE
    end
    if IsInRaid and IsInRaid() then
        return CDM_MIN_UPDATE_INTERVAL_RAID_COMBAT
    end
    return CDM_MIN_UPDATE_INTERVAL_COMBAT
end

local function ScheduleCDMUpdate(fast, mode)
    mode = (mode == CDM_UPDATE_FULL) and CDM_UPDATE_FULL or CDM_UPDATE_COOLDOWN
    _tickCooldownStats.updateRequests = _tickCooldownStats.updateRequests + 1
    if fast then
        _tickCooldownStats.updateFastRequests = _tickCooldownStats.updateFastRequests + 1
    end
    local delay = GetCDMUpdateDelay(fast)

    if _cdmUpdatePending then
        if mode == CDM_UPDATE_FULL then
            _cdmUpdateMode = CDM_UPDATE_FULL
        end
        _tickCooldownStats.updateCoalesced = _tickCooldownStats.updateCoalesced + 1
        if delay < _cdmUpdateDelay then
            _cdmUpdateDelay = delay
        end
        return
end

    _cdmUpdatePending = true
    _cdmUpdateElapsed = 0
    _cdmUpdateDelay = delay
    _cdmUpdateMode = mode
    cdmUpdateFrame:SetScript("OnUpdate", CDMUpdateOnUpdate)
end

-- Combat safety ticker: periodic fallback update during combat.
-- DurationObject sources may resolve late (viewer hook delays); a
-- low-frequency ticker ensures icons recover even if the initial
-- event-driven update failed due to secret values. Interval is 1s
-- because the event path (ScheduleCDMUpdate) already coalesces quickly
-- enough — this ticker is a fallback, not the primary update path.
-- A shorter interval compounds with event-driven rebuilds and was
-- measurably contributing to raid-combat stutters.
local safetyTickFrame = CreateFrame("Frame")
local SAFETY_TICK_INTERVAL = 1.0
local safetyTickElapsed = 0
local function SafetyTickOnUpdate(self, elapsed)
    safetyTickElapsed = safetyTickElapsed + elapsed
    if safetyTickElapsed < SAFETY_TICK_INTERVAL then return end
    safetyTickElapsed = 0
    -- Dirty-gate: if the event-driven path ran within the last interval,
    -- the state is already fresh and this tick would be redundant work.
    -- Safety tick is a fallback for late-resolving DurationObjects, not a
    -- primary update path — skipping when recent is safe.
    if GetTime() - _lastCDMUpdateTime < SAFETY_TICK_INTERVAL then return end
    if _barsDirty then
        CDMIcons:UpdateAllCooldowns(true)
    else
        CDMIcons:UpdateCooldownOnly(true)
    end
    if _barsDirty and ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
        _barsDirty = false
        ns.CDMBars:UpdateOwnedBars()  -- safety ticker, don't clear oocInactive
    end
    WipeUpdateTickCaches()
end

cdEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        CDMIcons:UpdateAllIconRanges()
        -- Target debuffs (e.g. Reaper's Mark) need a CDM refresh when target changes
        ns.CDMSpellData:InvalidateChildMap()
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "PLAYER_SOFT_ENEMY_CHANGED" then
        CDMIcons:UpdateAllIconRanges()
        ns.CDMSpellData:InvalidateChildMap()
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Trinket slots 13-14: refresh textures and cooldowns immediately
        if arg1 == 13 or arg1 == 14 then
            ClearUpdateTickCaches()
            ns.CDMSpellData:InvalidateChildMap()
            CDMIcons:UpdateAllCooldowns()
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        ClearUpdateTickCaches()
        rangePollInCombat = true
        rangePollElapsed = 0  -- reset so combat interval kicks in immediately
        safetyTickElapsed = 0
        safetyTickFrame:SetScript("OnUpdate", SafetyTickOnUpdate)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        rangePollInCombat = false
        safetyTickFrame:SetScript("OnUpdate", nil)
        ClearUpdateTickCaches()
        -- One-shot catch-up: refresh all cooldowns after combat ends
        ns.CDMSpellData:InvalidateChildMap()
        _barsDirty = true
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "UPDATE_MACROS" then
        InvalidateMacroCache()
        return
    end
    if event == "SPELLS_CHANGED" then
        -- Talent/spec change: spell icons may have changed.
        ClearUpdateTickCaches()
        ns.CDMSpellData:InvalidateChildMap()
        wipe(_textureCycleCache)
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        -- Server-side cooldown table changed. Drop the cached child map so
        -- the next lookup walks fresh viewer children.
        ns.CDMSpellData:InvalidateChildMap()
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    -- Coalesce cooldown events via the reusable update frame.
    ScheduleCDMUpdate(nil, CDM_UPDATE_COOLDOWN)
end)

-- User /cdm spell add/remove. Blizzard's standalone CooldownManager UI
-- routes mutations through CooldownViewerSettingsDataProvider, which fires
-- EventRegistry's "CooldownViewerSettings.OnDataChanged" callback (NOT a
-- Frame event). Drop the child map and refresh so downstream code picks
-- up the new viewer composition without waiting for an unrelated event
-- to dirty the cache.
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback(
        "CooldownViewerSettings.OnDataChanged",
        function()
            ns.CDMSpellData:InvalidateChildMap()
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        end,
        "QUI_CDMIcons")
end

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Icons", frame = cdEventFrame }

-- Subscribe to centralized aura dispatcher for prompt icon updates.
-- Player auras via "player" filter (avoids callback for all 20+ raid units).
-- Target debuffs via "all" filter (no "target" filter in the dispatcher).
-- Aura events set _barsDirty so UpdateOwnedBars (aura-state driven) runs next
-- coalesce tick. Pure cooldown events (SPELL_UPDATE_COOLDOWN path at
-- cdEventFrame:OnEvent) deliberately do NOT set the flag — bar fill is driven
-- by barTimerGroup independently of ScheduleCDMUpdate.
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
        ns.CDMSpellData:InvalidateChildMap()
        _barsDirty = true
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
    end)
    ns.AuraEvents:Subscribe("all", function(unit, updateInfo)
        if unit == "target" then
            ns.CDMSpellData:InvalidateChildMap()
            _barsDirty = true
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        end
    end)
end

-- Visual state polling: 250ms OnUpdate for range + usability checks.
-- Only active when at least one tracker has rangeIndicator or usabilityIndicator.
local function RangePollOnUpdate(self, elapsed)
    rangePollElapsed = rangePollElapsed + elapsed
    local interval = rangePollInCombat and RANGE_POLL_INTERVAL_COMBAT or RANGE_POLL_INTERVAL_IDLE
    if rangePollElapsed < interval then return end
    rangePollElapsed = 0

    -- Skip when all viewers are hidden (HUD visibility, mouseover mode, etc.)
    local essViewer = _G["EssentialCooldownViewer"]
    local utiViewer = _G["UtilityCooldownViewer"]
    if not ((essViewer and essViewer:IsShown()) or (utiViewer and utiViewer:IsShown())) then return end

    CDMIcons:UpdateAllIconRanges()
end

local rangePollActive = false

--- Call after settings change to start/stop the range poll OnUpdate.
function CDMIcons:SyncRangePoll()
    local db = GetDB()
    local anyEnabled = db
        and ((db.essential and (db.essential.rangeIndicator or db.essential.usabilityIndicator))
          or (db.utility and (db.utility.rangeIndicator or db.utility.usabilityIndicator)))
    if anyEnabled and not rangePollActive then
        rangePollActive = true
        rangePollElapsed = 0
        cdEventFrame:SetScript("OnUpdate", RangePollOnUpdate)
    elseif not anyEnabled and rangePollActive then
        rangePollActive = false
        cdEventFrame:SetScript("OnUpdate", nil)
    end
end

-- Start disabled — SyncRangePoll is called from Refresh/init paths
cdEventFrame:SetScript("OnUpdate", nil)
