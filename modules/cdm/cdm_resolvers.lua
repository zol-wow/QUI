-- cdm_resolvers.lua
-- Pure resolution layer for the QUI CDM owned engine.
-- Functions in this file MUST NOT write to frames; they compute and return values.
-- Runtime query wrappers live here because both resolvers and the icon factory's
-- UpdateIconCooldown driver depend on the same source facade calls.

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local Shared = ns.CDMShared

local CDMResolvers = {}
ns.CDMResolvers = CDMResolvers
local Scheduler = ns.CDMScheduler
local Sources = ns.CDMSources

---------------------------------------------------------------------------
-- Event bus
--
-- Synchronous dispatch with a per-call snapshot of the subscriber list. The
-- snapshot is intentional: it freezes which handlers fire for the current
-- publish so that subscribing during dispatch doesn't include the new
-- handler in the in-flight event (verified by tests/cdm_bus_test.lua).
-- Subscribers run in the resolver's tick. Events carry IDs only; subscribers
-- pull fresh state through the runtime query wrappers. See spec:
-- docs/superpowers/specs/2026-05-05-cdm-blizzard-child-decoupling-design.md
---------------------------------------------------------------------------
local _subscribers = {} -- [eventName] = { handler1, handler2, ... }

local function publish(eventName, ...)
    if Scheduler and Scheduler.Publish then
        Scheduler.Publish(eventName, ...)
        return
    end

    local list = _subscribers[eventName]
    if not list then return end
    local n = #list
    if n == 0 then return end
    local snapshot = {}
    for i = 1, n do snapshot[i] = list[i] end
    for i = 1, n do
        xpcall(snapshot[i], geterrorhandler(), eventName, ...)
    end
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

---------------------------------------------------------------------------
-- Catalog publication
--
-- Publishes CDM:CATALOG_REBUILT on lifecycle events. Combat-deferred:
-- TRAIT_TREE_CHANGED fires inside combat, so rebuild waits for
-- PLAYER_REGEN_ENABLED. Aura instance IDs re-randomize on encounter/M+/PvP
-- starts, so those are also rebuild triggers.
---------------------------------------------------------------------------
local _busEventFrame = CreateFrame("Frame")
local _rebuildPending = false

local function RebuildCatalog()
    if InCombatLockdown() then
        _rebuildPending = true
        return
    end
    _rebuildPending = false
    CDMResolvers._catalogVersion = (CDMResolvers._catalogVersion or 0) + 1
    publish("CDM:CATALOG_REBUILT")
end

CDMResolvers._RebuildCatalog = RebuildCatalog

_busEventFrame:RegisterEvent("PLAYER_LOGIN")
_busEventFrame:RegisterEvent("TRAIT_TREE_CHANGED")
_busEventFrame:RegisterEvent("SPELLS_CHANGED")
_busEventFrame:RegisterEvent("ENCOUNTER_START")
_busEventFrame:RegisterEvent("CHALLENGE_MODE_START")
_busEventFrame:RegisterEvent("PVP_MATCH_ACTIVE")
_busEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_busEventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_ENABLED" then
        if _rebuildPending then RebuildCatalog() end
        return
    end
    RebuildCatalog()
end)

---------------------------------------------------------------------------
-- Runtime delta publication
--
-- The resolver owns cooldown/charge runtime event registration and publishes
-- CDM:* events when state changes. Consumers subscribe to the bus and pull
-- fresh state via the runtime query wrappers. UNIT_AURA is handled by
-- cdm_spelldata.lua because its batched payload is the source of truth.
---------------------------------------------------------------------------
local _runtimeFrame = CreateFrame("Frame")
_runtimeFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_runtimeFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
_runtimeFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_runtimeFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
_runtimeFrame:SetScript("OnEvent", function(_, evt, arg1, arg2, arg3)
    if evt == "SPELL_UPDATE_COOLDOWN" then
        -- arg1 is Blizzard's spellID hint (may be nil for "update all").
        -- Subscriber chooses per-spell fast-path vs global walk.
        publish("CDM:COOLDOWN_CHANGED", arg1, arg2, "refresh")
    elseif evt == "SPELL_UPDATE_CHARGES" then
        publish("CDM:CHARGES_CHANGED", arg1)
    elseif evt == "UNIT_SPELLCAST_START" then
        if arg1 == "player" then
            publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_start")
        end
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_succeeded")
        end
    end
end)

-- Forward reference to ns.CDMIcons. Bound by _FinalizeImports() at the
-- end of cdm_icons.lua's load. Cannot be `local CDMIcons = ns.CDMIcons`
-- here because cdm_resolvers.lua loads before cdm_icons.lua per cdm.xml.
local CDMIcons

local function IsSafeNumeric(val)
    return Shared and Shared.IsSafeNumeric(val) or type(val) == "number"
end

local function SafeBoolean(val)
    if Shared and Shared.SafeBoolean then
        return Shared.SafeBoolean(val)
    end
    if type(val) == "boolean" then
        return val
    end
    return nil
end

local function GetAuraDataInstanceID(auraData)
    if not auraData then return nil end
local ok = true; local instID = auraData.auraInstanceID
    if not ok then return nil end
    return instID
end

local GCD_MAX_DURATION = 1.75
local GCD_SPELL_ID = 61304

---------------------------------------------------------------------------
-- RUNTIME RESOLUTION QUERIES
-- These functions used to keep short-lived per-tick caches. They now query
-- Blizzard C APIs fresh on every call; the exported names are kept stable for
-- the existing icon/bar resolver call sites.
---------------------------------------------------------------------------
-- Persistent multi-charge spell cache (survives combat/reload via SavedVariables).
-- Populated OOC when GetSpellCharges returns readable values; consulted in combat
-- when secret values block runtime detection.
local function GetChargeMetadataDB()
    local db = QUI and QUI.db and QUI.db.global
    if not db then return nil end
    if not db.cdmChargeSpells then db.cdmChargeSpells = {} end
    return db.cdmChargeSpells
end
CDMResolvers.GetChargeMetadataDB = GetChargeMetadataDB  -- consumed by cdm_icons.lua via upvalue alias

local WipeTable = wipe
if not WipeTable then
    WipeTable = function(tbl)
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end
end

local NIL_SENTINEL = {}
local _runtimeQueryBatchDepth = 0
local _runtimeCooldownCache = {}
local _runtimeChargeCache = {}
local _runtimeDurationCache = {}
local _runtimeGCDDurationCache = {}
local _runtimeChargeDurationCache = {}
local _runtimeOverrideCache = {}
local _runtimeDisplayCountCache = {}
local _runtimeSpellCountCache = {}
local _runtimeQueryStats = {
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

do
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_queryCacheBatches", counter = true, fn = function() return _runtimeQueryStats.batches end }
    mp[#mp + 1] = { name = "CDM_queryCacheSource", counter = true, fn = function()
        return _runtimeQueryStats.cooldownSource
            + _runtimeQueryStats.chargeSource
            + _runtimeQueryStats.durationSource
            + _runtimeQueryStats.chargeDurationSource
            + _runtimeQueryStats.overrideSource
            + _runtimeQueryStats.displayCountSource
            + _runtimeQueryStats.spellCountSource
    end }
    mp[#mp + 1] = { name = "CDM_queryCacheHits", counter = true, fn = function()
        return _runtimeQueryStats.cooldownHits
            + _runtimeQueryStats.chargeHits
            + _runtimeQueryStats.durationHits
            + _runtimeQueryStats.chargeDurationHits
            + _runtimeQueryStats.overrideHits
            + _runtimeQueryStats.displayCountHits
            + _runtimeQueryStats.spellCountHits
    end }
end

local function ClearRuntimeQueryCaches()
    WipeTable(_runtimeCooldownCache)
    WipeTable(_runtimeChargeCache)
    WipeTable(_runtimeDurationCache)
    WipeTable(_runtimeGCDDurationCache)
    WipeTable(_runtimeChargeDurationCache)
    WipeTable(_runtimeOverrideCache)
    WipeTable(_runtimeDisplayCountCache)
    WipeTable(_runtimeSpellCountCache)
end

function CDMResolvers.BeginRuntimeQueryBatch()
    if _runtimeQueryBatchDepth == 0 then
        ClearRuntimeQueryCaches()
        _runtimeQueryStats.batches = _runtimeQueryStats.batches + 1
    end
    _runtimeQueryBatchDepth = _runtimeQueryBatchDepth + 1
end

function CDMResolvers.EndRuntimeQueryBatch()
    if _runtimeQueryBatchDepth <= 0 then
        ClearRuntimeQueryCaches()
        _runtimeQueryBatchDepth = 0
        return
    end

    _runtimeQueryBatchDepth = _runtimeQueryBatchDepth - 1
    if _runtimeQueryBatchDepth == 0 then
        ClearRuntimeQueryCaches()
    end
end

function CDMResolvers.ResetRuntimeQueryBatch()
    _runtimeQueryBatchDepth = 0
    ClearRuntimeQueryCaches()
end

local function ReadRuntimeCache(cache, key, hitStat)
    if _runtimeQueryBatchDepth <= 0 then return nil, false end
    local cached = cache[key]
    if cached ~= nil then
        _runtimeQueryStats[hitStat] = _runtimeQueryStats[hitStat] + 1
        if cached == NIL_SENTINEL then
            return nil, true
        end
        return cached, true
    end
    return nil, false
end

local function StoreRuntimeCache(cache, key, value, sourceStat)
    if _runtimeQueryBatchDepth <= 0 then return value end
    cache[key] = value == nil and NIL_SENTINEL or value
    _runtimeQueryStats[sourceStat] = _runtimeQueryStats[sourceStat] + 1
    return value
end

-- Source-facade passthroughs. Calls remain live reads outside an explicit
-- runtime batch. CDM icon/bar refresh passes open a short batch so repeated
-- reads of C APIs that allocate result tables share one payload per spell.
function CDMResolvers.QueryCharges(spellID)
    if not spellID then return nil end
    local cached, found = ReadRuntimeCache(_runtimeChargeCache, spellID, "chargeHits")
    if found then return cached end

    local chargeInfo = nil
    if Sources and Sources.QuerySpellCharges then
        chargeInfo = Sources.QuerySpellCharges(spellID)
    end
    -- Persist multi-charge detection OOC for combat fallback.
    -- Also clean up stale cache entries when API returns no charges or <= 1.
    if not InCombatLockdown() then
        if chargeInfo then
            local maxC = chargeInfo.maxCharges
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
    return StoreRuntimeCache(_runtimeChargeCache, spellID, chargeInfo, "chargeSource")
end

function CDMResolvers.QueryCooldown(spellID)
    if not spellID then return nil end
    local cached, found = ReadRuntimeCache(_runtimeCooldownCache, spellID, "cooldownHits")
    if found then return cached end

    local info
    if Sources and Sources.QuerySpellCooldown then
        info = Sources.QuerySpellCooldown(spellID)
    end
    return StoreRuntimeCache(_runtimeCooldownCache, spellID, info, "cooldownSource")
end

local function QueryCooldownDuration(spellID, ignoreGCD)
    if not spellID then return nil end
    local cache = ignoreGCD and _runtimeDurationCache or _runtimeGCDDurationCache
    local cached, found = ReadRuntimeCache(cache, spellID, "durationHits")
    if found then return cached end

    local durObj
    if Sources and Sources.QuerySpellCooldownDuration then
        durObj = Sources.QuerySpellCooldownDuration(spellID, ignoreGCD and true or false)
    end
    return StoreRuntimeCache(cache, spellID, durObj, "durationSource")
end

function CDMResolvers.QueryDuration(spellID)
    if not spellID then return nil end
    -- ignoreGCD=true: return the spell's own cooldown DurationObject
    -- even during the GCD, so the icon swipe tracks the spell's real
    -- cooldown instead of the 1.5s GCD sweep that masks it.
    return QueryCooldownDuration(spellID, true)
end

function CDMResolvers.QueryChargeDuration(spellID)
    if not spellID then return nil end
    local cached, found = ReadRuntimeCache(_runtimeChargeDurationCache, spellID, "chargeDurationHits")
    if found then return cached end

    local durObj
    if Sources and Sources.QuerySpellChargeDuration then
        durObj = Sources.QuerySpellChargeDuration(spellID)
    end
    return StoreRuntimeCache(_runtimeChargeDurationCache, spellID, durObj, "chargeDurationSource")
end

function CDMResolvers.QueryOverrideSpell(spellID)
    if not spellID then return nil end
    local cached, found = ReadRuntimeCache(_runtimeOverrideCache, spellID, "overrideHits")
    if found then return cached end

    local overrideID
    if Sources and Sources.QueryOverrideSpell then
        overrideID = Sources.QueryOverrideSpell(spellID)
    end
    return StoreRuntimeCache(_runtimeOverrideCache, spellID, overrideID, "overrideSource")
end

function CDMResolvers.QueryDisplayCount(spellID)
    if not spellID then return nil end
    local cached, found = ReadRuntimeCache(_runtimeDisplayCountCache, spellID, "displayCountHits")
    if found then return cached end

    local count
    if Sources and Sources.QuerySpellDisplayCount then
        count = Sources.QuerySpellDisplayCount(spellID)
    end
    return StoreRuntimeCache(_runtimeDisplayCountCache, spellID, count, "displayCountSource")
end

function CDMResolvers.QuerySpellCount(spellID)
    if not spellID then return nil end
    local cached, found = ReadRuntimeCache(_runtimeSpellCountCache, spellID, "spellCountHits")
    if found then return cached end

    local count
    if Sources and Sources.QuerySpellCount then
        count = Sources.QuerySpellCount(spellID)
    end
    return StoreRuntimeCache(_runtimeSpellCountCache, spellID, count, "spellCountSource")
end

-- Upvalue aliases so resolver functions below can call QueryX(spellID)
-- bare instead of CDMResolvers.QueryX(spellID). Must come after the
-- function definitions above; the QueryX getters are attached to CDMResolvers
-- (not file-scoped locals) so without these aliases the bare references
-- earlier in the file resolve to nil globals.
local QueryCharges        = CDMResolvers.QueryCharges
local QueryCooldown       = CDMResolvers.QueryCooldown
local QueryDuration       = CDMResolvers.QueryDuration
local QueryChargeDuration = CDMResolvers.QueryChargeDuration
local QueryOverrideSpell  = CDMResolvers.QueryOverrideSpell
local QueryDisplayCount   = CDMResolvers.QueryDisplayCount
local QuerySpellCount     = CDMResolvers.QuerySpellCount


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

    local itemSpellID = CDMIcons.GetItemUseSpellID(itemID)
    local keySource = slotID and (tostring(slotID) .. ":" .. tostring(itemID)) or tostring(itemID)
    return itemID, slotID, itemSpellID, keySource
end

function CDMResolvers.ResolveEntryItemID(entry)
    if not entry then return nil end
    if entry.type == "item" then
        return entry.id
    elseif entry.type == "trinket" or entry.type == "slot" then
        if Sources and Sources.QueryInventoryItemID then
            return Sources.QueryInventoryItemID("player", entry.id)
        end
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
    local info
    if Sources and Sources.QuerySpellInfo then
        info = Sources.QuerySpellInfo(spellID)
    end
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
        local itemID
        if Sources and Sources.QueryItemInfoInstant then
            itemID = Sources.QueryItemInfoInstant(itemLink)
        end
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
        -- Trinket/slot entries store the equipment slot number (13/14), not the item ID.
        -- Resolve to the actual equipped item ID before looking up the icon.
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
            _, _, _, _, icon = Sources.QueryItemInfoInstant(entry.id)
        end
        return icon
    end
    return CDMResolvers.GetSpellTexture(entry.overrideSpellID or entry.id)
end

---------------------------------------------------------------------------
-- CLASSIFICATION
-- (IsSafeNumeric/SafeBoolean local helpers and GCD_MAX_DURATION are
--  declared at the top of this file so runtime query
--  functions earlier in the file can also use them.)
---------------------------------------------------------------------------

local function GetTrustedIsOnGCD(spellID)
    if Helpers.IsSecretValue and Helpers.IsSecretValue(spellID) then
        return nil
    end
    if CDMIcons and CDMIcons._trustIsOnGCDForBatch == true then
        local trusted = CDMIcons._trustedGCDSpellState and spellID and CDMIcons._trustedGCDSpellState[spellID]
        if type(trusted) == "boolean" then
            return trusted
        end
    end
    return nil
end

local function GetCooldownInfoBoolean(info, key)
    if not info or not CDMIcons or not CDMIcons.GetCooldownInfoField then
        return nil
    end
    local value, isSecret = CDMIcons.GetCooldownInfoField(info, key)
    if isSecret then
        return nil
    end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function GetCurrentIsOnGCD(spellID, info)
    local trusted = GetTrustedIsOnGCD(spellID)
    if trusted ~= nil then
        return trusted
    end
    return GetCooldownInfoBoolean(info, "isOnGCD")
end

local function QueryGCDDurationObject(spellID)
    local durObj = nil
    if spellID then
        durObj = QueryCooldownDuration(spellID, false)
    end
    if not durObj and spellID ~= GCD_SPELL_ID then
        durObj = QueryCooldownDuration(GCD_SPELL_ID, false)
    end
    return durObj
end

local function QuerySpellUsableState(spellID)
    if not spellID or not (Sources and Sources.QuerySpellUsable) then
        return nil
    end
    local usable = Sources.QuerySpellUsable(spellID)
    if Helpers and Helpers.SafeValue then
        usable = Helpers.SafeValue(usable, nil)
    end
    if type(usable) ~= "boolean" then
        usable = nil
    end
    return usable
end

local function ClassifyMirrorDurationMode(durObjSource)
    if durObjSource == "aura-duration"
        or durObjSource == "aura-child"
        or durObjSource == "aura-child-frame"
        or durObjSource == "aura-related-child" then
        return "aura"
    end
    if durObjSource == "spell-charge"
        or durObjSource == "resource-duration" then
        return "charge"
    end
    if durObjSource == "gcd-duration" then
        return "gcd-only"
    end
    return "cooldown"
end

local function BuildMirrorDurationSourceKey(mode, sourceCooldownID, sourceSpellID, mirrorEpoch)
    if mode == "gcd-only" then
        return sourceSpellID
    end
    return "mirror:" .. tostring(sourceCooldownID) .. ":" .. tostring(mirrorEpoch)
end

local function IsSupportedMirrorMode(mode)
    return mode == "aura"
        or mode == "cooldown"
        or mode == "charge"
        or mode == "item-cooldown"
        or mode == "gcd-only"
        or mode == "inactive"
end

local function IsChargeSpellNotRecharging(spellID, entry)
    local ci = QueryCharges(spellID)
    if not ci then
        return false
    end
    if SafeBoolean(ci.isActive) ~= false then
        return false
    end
    local maxCharges = ci.maxCharges
    return (entry and entry.hasCharges == true)
        or (IsSafeNumeric(maxCharges) and maxCharges > 1)
end

local function IconHasRealCooldownProof(icon)
    if not icon then
        return false
    end
    return icon._hasRealCooldownActive == true
        or icon._showingRealCooldownSwipe == true
        or icon._resolvedCooldownMode == "cooldown"
        or icon._resolvedCooldownMode == "charge"
        or icon._resolvedCooldownMode == "item-cooldown"
end

local function IsRealCooldownDurationMode(mode)
    return mode == "cooldown"
        or mode == "charge"
        or mode == "item-cooldown"
end

local function GetPreservedRealDurationObject(icon)
    if not icon or not icon._lastDurObj then
        return nil
    end

    local key = icon._lastDurObjKey
    if type(key) ~= "string" then
        return nil
    end

    local mode, sourceID = key:match("^([^:]+):(.+)$")
    if not IsRealCooldownDurationMode(mode) then
        return nil
    end

    return icon._lastDurObj, mode, sourceID
end

local function ShouldTreatLiveDurationAsGCD(spellID, entry, icon, cdInfo, currentOnGCD, spellUsable)
    if currentOnGCD ~= true then
        return false
    end
    if IsChargeSpellNotRecharging(spellID, entry) then
        return true
    end
    if spellUsable == true then
        return true
    end
    if IconHasRealCooldownProof(icon) then
        return false
    end
    if CDMIcons and CDMIcons.IsCooldownInfoRealCooldown then
        local realCooldown = CDMIcons.IsCooldownInfoRealCooldown(cdInfo)
        if realCooldown == true then
            return false
        elseif realCooldown == false then
            return true
        end
    end
    -- State truly unknown from cdInfo. We have currentOnGCD == true and no
    -- prior proof of a real CD (IconHasRealCooldownProof returned false).
    -- Per the directive: trust isOnGCD == true → GCD swipe. The catalog
    -- heuristic SpellHasBaseCooldownLongerThanGCD answers "could this spell
    -- ever have a real CD," not "is it on a real CD right now," and was
    -- misclassifying GCD pulses on spells that have a base CD entry.
    return true
end

function CDMResolvers.ClassifySpellCooldownState(spellID, info)
    if not info and spellID then
        info = QueryCooldown(spellID)
    end

    local active = CDMIcons.IsCooldownInfoActive(info)
    local realActive = CDMIcons.IsCooldownInfoRealCooldown(info)
    local onGCD = false
    local currentOnGCD = GetCurrentIsOnGCD(spellID, info)
    if currentOnGCD == true then
        onGCD = true
    end

    -- When IsCooldownInfoRealCooldown couldn't decide (start/duration secret
    -- or otherwise ambiguous), trust isOnGCD as the definitive signal per
    -- the directive: active + isOnGCD==false is a real cooldown; active +
    -- isOnGCD==true is a GCD swipe. The catalog heuristic
    -- (SpellHasBaseCooldownLongerThanGCD) is banned because it answers a
    -- category question, not a state question.
    if realActive == nil and active == true then
        local onGCD, onGCDSecret = CDMIcons.GetCooldownInfoField(info, "isOnGCD")
        if onGCDSecret ~= true and type(onGCD) == "boolean" then
            realActive = (onGCD == false)
        end
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

    if icon._auraActive or CDMResolvers.IsAuraEntry(entry) then
        return false
    end

    if apiIsActive == false then
        return false
    end

    if apiIsActive == true
       and (icon._hasRealCooldownActive == true or icon._showingRealCooldownSwipe == true) then
        return true
    end

    local chargeInfo = runtimeSpellID and QueryCharges(runtimeSpellID)
    local maxCharges = chargeInfo and chargeInfo.maxCharges
    if maxCharges and maxCharges > 1 then
        return blizzRealCooldownActive == true
            or durObj ~= nil
    end

    if blizzRealCooldownActive then
        return true
    end

    if durObj and apiIsActive == true then
        -- Trust isOnGCD as the per-event signal: apiIsActive == true with
        -- isOnGCD == false is a real cooldown swipe; isOnGCD == true is a
        -- GCD pulse. Catalog inference (SpellHasBaseCooldownLongerThanGCD)
        -- is banned — it answers "could this spell ever have a CD," not
        -- "is it on a real CD right now."
        local resolvedSpellID = runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
        if resolvedSpellID then
            local cdInfo = QueryCooldown(resolvedSpellID)
            if cdInfo then
                local onGCD, onGCDSecret = CDMIcons.GetCooldownInfoField(cdInfo, "isOnGCD")
                if onGCDSecret ~= true and onGCD == false then
                    return true
                end
            end
        end
    end

    if IsSafeNumeric(icon and icon._lastStart) and IsSafeNumeric(icon and icon._lastDuration)
        and icon._lastStart > 0 and icon._lastDuration > GCD_MAX_DURATION then
        return true
    end

    if IsSafeNumeric(duration) and duration > GCD_MAX_DURATION then
        return true
    end

    local lastDuration = icon._lastDuration
    if IsSafeNumeric(lastDuration) and lastDuration > GCD_MAX_DURATION then
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

    local overrideID = QueryOverrideSpell(spellID)
    if overrideID and overrideID ~= spellID then
        active, start, duration, activeType = CDMIcons.GetSpellCastInfo(overrideID)
        if active then return active, start, duration, activeType end
        active, start, duration, activeType = CDMIcons.GetSpellChannelInfo(overrideID)
        if active then return active, start, duration, activeType end
        active, start, duration, activeType = CDMIcons.GetSpellBuffInfo(overrideID, icon, entry)
        if active then return active, start, duration, activeType end
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
    local runtimeStore = ns.CDMRuntimeStore
    local storedState = runtimeStore and runtimeStore.GetFrameState
        and runtimeStore.GetFrameState(icon)
    if storedState and storedState.mode then
        if storedState.mode == "charge" then
            state.hasCharges = true
            state.rechargeActive = storedState.active == true
            state.isOnCooldown = storedState.active == true
            return state
        elseif storedState.mode == "cooldown" or storedState.mode == "item-cooldown" then
            state.isOnCooldown = storedState.active == true
            return state
        elseif storedState.mode == "inactive" then
            state.isOnCooldown = false
        end
    end

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
        local ci = QueryCharges(spellID)
        if ci then
            local maxC = ci.maxCharges
            if maxC and maxC > 1 then
                state.hasCharges = true
            end
        end

        if state.hasCharges then
            local cdInfo = QueryCooldown(spellID)
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
            local dur = IsSafeNumeric(icon._lastDuration) and icon._lastDuration or 0
            local start = IsSafeNumeric(icon._lastStart) and icon._lastStart or 0
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

local QueryDuration       = CDMResolvers.QueryDuration
local QueryChargeDuration = CDMResolvers.QueryChargeDuration
local QueryOverrideSpell  = CDMResolvers.QueryOverrideSpell

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

local PLAYER_AURA_CAPTURE_LOOKUP_UNITS = { "player", "pet" }

local function QueryCapturedPlayerAuraDuration(spellID, name)
    if not InCombatLockdown()
       or not (Sources and Sources.QueryAuraDuration) then
        return nil
    end

    local CDMSpellData = ns.CDMSpellData
    if not (CDMSpellData and CDMSpellData.GetCapturedAuraForLookup) then
        return nil
    end

    local lookupIDs = {}
    local seen = {}
    local function addLookup(id)
        if not id then return end
        if seen[id] then return end
        seen[id] = true
        lookupIDs[#lookupIDs + 1] = id
    end

    if CDMSpellData.GetAuraIDsForSpell and spellID then
        local catalogIDs = CDMSpellData:GetAuraIDsForSpell(spellID)
        if catalogIDs then
            for _, auraID in ipairs(catalogIDs) do
                addLookup(auraID)
            end
        end
    end
    addLookup(spellID)

    local captured = CDMSpellData.GetCapturedAuraForLookup(
        lookupIDs, name, PLAYER_AURA_CAPTURE_LOOKUP_UNITS, false)
    local auraInstanceID = captured and captured.auraInstanceID
    if not auraInstanceID then
        return nil
    end

    return Sources.QueryAuraDuration(captured.unit or "player", auraInstanceID)
end

local function QueryPlayerAuraDurationBySpellID(rawSpellID, name)
    if not rawSpellID or not (Sources and Sources.QueryAuraDuration) then
        return nil
    end

    local capturedDurObj = QueryCapturedPlayerAuraDuration(rawSpellID, name)
    if capturedDurObj then
        return capturedDurObj
    end

    local function queryAuraData(auraSpellID)
        if not auraSpellID then return nil end
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
        if not auraInstanceID then return nil end

        return Sources.QueryAuraDuration("player", auraInstanceID)
    end

    if Sources.QueryCooldownAuraBySpellID then
        local auraSpellID = Sources.QueryCooldownAuraBySpellID(rawSpellID)
        if auraSpellID then
            local durObj = queryDuration(auraSpellID)
            if durObj then
                return durObj
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

    local capturedDurObj = QueryCapturedPlayerAuraDuration(nil, name)
    if capturedDurObj then
        return capturedDurObj
    end

    if not Sources.QueryAuraDataBySpellName then
        return nil
    end

    local auraData = Sources.QueryAuraDataBySpellName("player", name, "HELPFUL")
    if not auraData then
        return nil
    end

    local auraInstanceID = GetAuraDataInstanceID(auraData)
    if not auraInstanceID then return nil end

    return Sources.QueryAuraDuration("player", auraInstanceID)
end

local WoW_IsSecretValue = issecretvalue

local function ResolverIsSecretValue(value)
    if Helpers and Helpers.IsSecretValue then
        return Helpers.IsSecretValue(value)
    end
    if WoW_IsSecretValue then
        return WoW_IsSecretValue(value)
    end
    return false
end

local function IsUsableMirrorID(value)
    if ResolverIsSecretValue(value) then return false end
    return type(value) == "number" and value > 0
end

local function NormalizeMirrorCategory(category)
    if ResolverIsSecretValue(category) or type(category) ~= "string" then
        return nil
    end
    if category == "essential"
        or category == "utility"
        or category == "buff"
        or category == "trackedBar" then
        return category
    end
    return nil
end

local function IsAuraMirrorCategory(category)
    category = NormalizeMirrorCategory(category)
    return category == "buff" or category == "trackedBar"
end

local function IsCooldownMirrorCategory(category)
    category = NormalizeMirrorCategory(category)
    return category == "essential" or category == "utility"
end

local function ResolveEntryMirrorCategory(entry)
    if not entry then return nil end
    return NormalizeMirrorCategory(entry.blizzardMirrorCategory)
        or NormalizeMirrorCategory(entry.viewerCategory)
        or NormalizeMirrorCategory(entry.viewerType)
end

local function SafeEntryField(entry, key)
    local value = entry and entry[key]
    if ResolverIsSecretValue(value) then return nil end
    return value
end

local function GetMirrorCategoryCandidates(viewerCategory, strictAuraBinding)
    if viewerCategory == "essential" then
        return "essential", "utility"
    elseif viewerCategory == "utility" then
        return "utility", "essential"
    elseif viewerCategory == "buff" then
        return "buff", "trackedBar"
    elseif viewerCategory == "trackedBar" then
        return "trackedBar", "buff"
    elseif strictAuraBinding then
        return "buff", "trackedBar"
    else
        return "essential", "utility"
    end
end

local function MirrorCategoryMatchesEntry(actualCategory, viewerCategory, strictAuraBinding)
    actualCategory = NormalizeMirrorCategory(actualCategory)
    if not actualCategory then return false end
    if IsCooldownMirrorCategory(viewerCategory) then
        return IsCooldownMirrorCategory(actualCategory)
    end
    if IsAuraMirrorCategory(viewerCategory) then
        return IsAuraMirrorCategory(actualCategory)
    end
    if strictAuraBinding then
        return IsAuraMirrorCategory(actualCategory)
    end
    return IsCooldownMirrorCategory(actualCategory)
end

local function MirrorIdentityStateAccepted(mirror, cooldownID, category, viewerCategory, strictAuraBinding)
    local state
    if mirror.GetStateByCooldownID then
        state = mirror.GetStateByCooldownID(cooldownID, category)
        if not state then return nil, nil end
    end

    local actualCategory = NormalizeMirrorCategory(state and state.viewerCategory) or category
    if not MirrorCategoryMatchesEntry(actualCategory, viewerCategory, strictAuraBinding) then
        return nil, nil
    end

    if mirror.HasChildForCooldownID
        and not mirror.HasChildForCooldownID(cooldownID, actualCategory) then
        return nil, nil
    end

    return actualCategory, state
end

local function ResolveMirrorIDInCategory(mirror, id, category, viewerCategory, strictAuraBinding)
    if not IsUsableMirrorID(id) then return nil, nil, nil end

    local cooldownID
    if strictAuraBinding and IsAuraMirrorCategory(category) then
        if not mirror.GetDirectCooldownIDForViewer then return nil, nil, nil end
        cooldownID = mirror.GetDirectCooldownIDForViewer(id, category)
    else
        if not mirror.GetCooldownIDForViewer then return nil, nil, nil end
        cooldownID = mirror.GetCooldownIDForViewer(id, category)
    end

    if not IsUsableMirrorID(cooldownID) then return nil, nil, nil end

    local acceptedCategory, state = MirrorIdentityStateAccepted(
        mirror, cooldownID, category, viewerCategory, strictAuraBinding)
    if acceptedCategory then
        return cooldownID, acceptedCategory, state
    end

    return nil, nil, nil
end

local function ResolveMirrorIDAndOverrideInCategory(mirror, id, category, viewerCategory, strictAuraBinding)
    local cooldownID, acceptedCategory, state = ResolveMirrorIDInCategory(
        mirror, id, category, viewerCategory, strictAuraBinding)
    if cooldownID then
        return cooldownID, acceptedCategory, state
    end

    if not IsUsableMirrorID(id) then return nil, nil, nil end
    local overrideID = QueryOverrideSpell(id)
    if overrideID == id then return nil, nil, nil end

    return ResolveMirrorIDInCategory(
        mirror, overrideID, category, viewerCategory, strictAuraBinding)
end

local function ResolveMirrorEntryInCategory(mirror, entry, category, viewerCategory, strictAuraBinding)
    local cooldownID, acceptedCategory, state = ResolveMirrorIDAndOverrideInCategory(
        mirror, entry.overrideSpellID, category, viewerCategory, strictAuraBinding)
    if cooldownID then
        return cooldownID, acceptedCategory, state
    end

    cooldownID, acceptedCategory, state = ResolveMirrorIDAndOverrideInCategory(
        mirror, entry.spellID, category, viewerCategory, strictAuraBinding)
    if cooldownID then
        return cooldownID, acceptedCategory, state
    end

    cooldownID, acceptedCategory, state = ResolveMirrorIDAndOverrideInCategory(
        mirror, entry.id, category, viewerCategory, strictAuraBinding)
    if cooldownID then
        return cooldownID, acceptedCategory, state
    end

    if not strictAuraBinding and type(entry.linkedSpellIDs) == "table" then
        for _, linkedID in ipairs(entry.linkedSpellIDs) do
            cooldownID, acceptedCategory, state = ResolveMirrorIDAndOverrideInCategory(
                mirror, linkedID, category, viewerCategory, strictAuraBinding)
            if cooldownID then
                return cooldownID, acceptedCategory, state
            end
        end
    end

    return nil, nil, nil
end

function CDMResolvers.ResolveBlizzardMirrorIdentity(entry)
    local mirror = ns.CDMBlizzMirror
    if not (entry and mirror) then return nil, nil, nil end

    local entryType = SafeEntryField(entry, "type")
    if entryType
        and entryType ~= "spell"
        and entryType ~= "aura"
        and entryType ~= "cooldown" then
        return nil, nil, nil
    end

    local viewerCategory = ResolveEntryMirrorCategory(entry)
    local entryKind = SafeEntryField(entry, "kind")
    local entryIsAura = SafeEntryField(entry, "isAura")
    local strictAuraBinding = entryKind == "aura"
        or entryType == "aura"
        or entryIsAura == true
        or IsAuraMirrorCategory(viewerCategory)
    local category1, category2 = GetMirrorCategoryCandidates(viewerCategory, strictAuraBinding)

    local explicitCooldownID = entry.cooldownID
    if IsUsableMirrorID(explicitCooldownID) and mirror.GetStateByCooldownID then
        local acceptedCategory, state = MirrorIdentityStateAccepted(
            mirror, explicitCooldownID, category1, viewerCategory, strictAuraBinding)
        if acceptedCategory then
            return explicitCooldownID, acceptedCategory, state
        end
        if category2 then
            acceptedCategory, state = MirrorIdentityStateAccepted(
                mirror, explicitCooldownID, category2, viewerCategory, strictAuraBinding)
            if acceptedCategory then
                return explicitCooldownID, acceptedCategory, state
            end
        end
    end

    local cooldownID, acceptedCategory, state = ResolveMirrorEntryInCategory(
        mirror, entry, category1, viewerCategory, strictAuraBinding)
    if cooldownID then
        return cooldownID, acceptedCategory, state
    end

    if category2 then
        cooldownID, acceptedCategory, state = ResolveMirrorEntryInCategory(
            mirror, entry, category2, viewerCategory, strictAuraBinding)
        if cooldownID then
            return cooldownID, acceptedCategory, state
        end
    end

    return nil, nil, nil
end

local function SafeMirrorString(value)
    if ResolverIsSecretValue(value) or type(value) ~= "string" then
        return nil
    end
    return value
end

local function SafeMirrorCountNumber(value)
    if value == nil or ResolverIsSecretValue(value) then
        return nil
    end
    local valueType = type(value)
    if valueType == "number" then
        return value
    end
    if valueType == "string" then
        return tonumber(value)
    end
    return nil
end

-- Singleton scratch tables for mirror payload generation. Both ResolveAuraState's
-- closure-heavy churn and BuildMirrorRenderPayload's fresh-table-per-call pattern
-- dominated combat GC. ResolveAuraState was fixed in 2026-05-11; this scratch
-- pair fixes the mirror payload side.
--
-- Callers MUST treat these as consume-immediately. The shared retention sites
-- (cdm_icons.lua's ApplyMirrorPayloadToIcon and cdm_bars.lua's
-- BuildBarAuraResultFromMirrorPayload) copy count fields out into per-icon /
-- per-bar tables — they no longer alias the singleton.
local _mirrorPayloadScratch = {
    mirrorBacked = true,
    state = nil, active = false, mode = nil, sourceID = nil,
    cooldownID = nil, category = nil, spellID = nil, auraInstanceID = nil,
    durObj = nil, durationStateUnknown = nil, auraUnit = nil,
    totemSlot = nil, totemName = nil, totemIcon = nil, isTotemInstance = false,
    count = nil, hasExpirationTime = nil, hideDurationText = nil,
}
local _mirrorCountScratch = {
    value = nil, sinkText = nil, shown = false, source = nil,
}

local function WipeMirrorPayloadScratch()
    local p = _mirrorPayloadScratch
    p.state = nil; p.active = false; p.mode = nil; p.sourceID = nil
    p.cooldownID = nil; p.category = nil; p.spellID = nil; p.auraInstanceID = nil
    p.durObj = nil; p.durationStateUnknown = nil; p.auraUnit = nil
    p.totemSlot = nil; p.totemName = nil; p.totemIcon = nil
    p.isTotemInstance = false
    p.count = nil
    p.hasExpirationTime = nil; p.hideDurationText = nil
end

local function BuildMirrorCountPayload(m)
    if not m then return nil end
    local c = _mirrorCountScratch
    c.value = nil; c.sinkText = nil; c.shown = false; c.source = nil

    local shown = SafeBoolean(m.stackTextShown)
    local source = SafeMirrorString(m.stackTextSource) or "mirror-text"
    if shown == false then
        c.shown = false
        c.source = source
        return c
    end

    local stackText = m.stackText
    if stackText ~= nil or ResolverIsSecretValue(stackText) then
        c.value = SafeMirrorCountNumber(stackText)
        c.sinkText = stackText
        c.shown = true
        c.source = source
        return c
    end

    return nil
end

local function ResolveMirrorPayloadMode(m, active)
    if active ~= true then
        return "inactive"
    end

    local mode = SafeMirrorString(m and m.resolvedMode)
    if not IsSupportedMirrorMode(mode) or mode == "inactive" then
        mode = ClassifyMirrorDurationMode(m and m.durObjSource)
    end
    if not IsSupportedMirrorMode(mode) or mode == "inactive" then
        mode = "cooldown"
    end
    return mode
end

local function BuildMirrorRenderPayload(m, fallbackCooldownID, fallbackCategory, fallbackSpellID)
    if not m then return nil end

    local active = SafeBoolean(m.isActive)
    if active == nil and m.durObj then
        active = true
    end
    active = active == true

    local sourceCooldownID = m.cooldownID or fallbackCooldownID or fallbackSpellID
    local sourceSpellID = m.overrideSpellID or m.spellID or fallbackSpellID
    local mode = ResolveMirrorPayloadMode(m, active)
    local sourceKey = BuildMirrorDurationSourceKey(
        mode, sourceCooldownID, sourceSpellID, m.mirrorEpoch)
    local selfAura = SafeBoolean(m.selfAura)
    local auraUnit = SafeMirrorString(m.auraUnit)
        or ((selfAura == false) and "target" or "player")

    WipeMirrorPayloadScratch()
    local payload = _mirrorPayloadScratch
    payload.mirrorBacked = true
    payload.state = m
    payload.active = active
    payload.mode = mode
    payload.sourceID = sourceKey
    payload.cooldownID = sourceCooldownID
    payload.category = NormalizeMirrorCategory(m.viewerCategory) or fallbackCategory
    payload.spellID = sourceSpellID
    payload.auraInstanceID = m.auraInstanceID
    payload.durObj = m.durObj
    payload.durationStateUnknown = m.durationStateUnknown
    payload.auraUnit = auraUnit
    payload.totemSlot = m.totemSlot
    payload.totemName = m.totemName
    payload.totemIcon = m.totemIcon
    payload.isTotemInstance = m.totemSlot and true or false
    payload.count = BuildMirrorCountPayload(m)

    if active and mode == "aura" and not m.durObj then
        payload.hasExpirationTime = false
        payload.hideDurationText = true
    end

    return payload
end

local function EntryMirrorBindingIsStrictAura(entry, viewerCategory)
    if not entry then return false end
    local entryKind = SafeEntryField(entry, "kind")
    local entryType = SafeEntryField(entry, "type")
    local entryIsAura = SafeEntryField(entry, "isAura")
    return entryKind == "aura"
        or entryType == "aura"
        or entryIsAura == true
        or IsAuraMirrorCategory(viewerCategory)
end

function CDMResolvers.ResolveMirrorRenderPayloadForEntry(entry, explicitCooldownID, explicitCategory, fallbackSpellID)
    local mirror = ns.CDMBlizzMirror
    if not (entry and mirror) then
        return nil
    end

    local entryType = SafeEntryField(entry, "type")
    if entryType
        and entryType ~= "spell"
        and entryType ~= "aura"
        and entryType ~= "cooldown" then
        return nil
    end

    local viewerCategory = ResolveEntryMirrorCategory(entry)
    local strictAuraBinding = EntryMirrorBindingIsStrictAura(entry, viewerCategory)
    local explicitCat = NormalizeMirrorCategory(explicitCategory)

    if IsUsableMirrorID(explicitCooldownID) and mirror.GetStateByCooldownID then
        local acceptedCategory, state = MirrorIdentityStateAccepted(
            mirror, explicitCooldownID, explicitCat, viewerCategory, strictAuraBinding)
        if acceptedCategory and state then
            return BuildMirrorRenderPayload(
                state, explicitCooldownID, acceptedCategory, fallbackSpellID)
        end
    end

    local cooldownID, category, state = CDMResolvers.ResolveBlizzardMirrorIdentity(entry)
    if cooldownID and state then
        return BuildMirrorRenderPayload(state, cooldownID, category, fallbackSpellID)
    end

    if not strictAuraBinding and Sources and Sources.QueryMirroredCooldownState and fallbackSpellID then
        local m = Sources.QueryMirroredCooldownState(fallbackSpellID, entry.viewerType)
        if m then
            return BuildMirrorRenderPayload(
                m,
                m.cooldownID or fallbackSpellID,
                NormalizeMirrorCategory(m.viewerCategory) or viewerCategory,
                fallbackSpellID)
        end
    end

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
    p.entryKind = entry.kind
    p.entryType = entry.type
    p.entryIsAura = auraEntry
    p.entryTexture = CDMResolvers.GetEntryTexture(entry)
    p.viewerType = entry.viewerType
    p.totemSlot = CDMIcons.IsTotemSlotEntry(entry) and entry._totemSlot or nil
    p.disableLooseVisibilityFallback = true
    p.blizzardMirrorCooldownID = icon._blizzMirrorCooldownID
    p.blizzardMirrorCategory = icon._blizzMirrorCategory

    return CDMSpellData:ResolveAuraState(p)
end

function CDMResolvers.ResolveAuraDurationObjectForIcon(icon, entry, sid)
    return CDMIcons.ApplyAuraStateToIcon(icon, entry, sid, CDMResolvers.ResolveAuraStateForIcon(icon, entry, sid))
end

function CDMResolvers.ResolveItemAuraDurationObject(icon, entry, itemID, itemSpellID)
    if not (icon and entry and itemID) then
        return nil, false, nil
    end

    local function trySpellID(rawSpellID, sourceKey)
        local durObj = QueryPlayerAuraDurationBySpellID(rawSpellID, entry.name)
        if durObj then
            local sourceID = "item-aura-spell:" .. tostring(itemID) .. ":" .. sourceKey
            icon._auraActive = true
            icon._auraUnit = "player"
            icon._totemSlot = entry._totemSlot or nil
            icon._isTotemInstance = nil
            icon._lastAuraDurObj = durObj
            icon._lastAuraSourceID = sourceID
            -- Item-applied auras live on the player and are helpful by
            -- convention (use-effect buffs from trinkets/potions).
            icon._auraIsHarmful = false
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
        icon._auraIsHarmful = false
        return durObj, true, sourceID
    end

    return nil, false, nil
end

function CDMResolvers.ResolveItemDurationObjectForIcon(icon, entry)
    local itemID, slotID, itemSpellID, keySource = CDMResolvers.ResolveItemCooldownIdentity(entry)
    if not itemID then return nil, "inactive", nil, nil, nil, nil end

    if itemSpellID then
        local cdInfo = QueryCooldown(itemSpellID)
        local cdInfoActive = cdInfo and CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
        if cdInfoActive == true and GetCurrentIsOnGCD(itemSpellID, cdInfo) ~= true then
            local durObj = QueryDuration(itemSpellID)
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

    local entryIsAura = CDMResolvers.IsAuraEntry(entry)
    local sid = icon._runtimeSpellID
        or entry.overrideSpellID or entry.spellID or entry.id
    if sid and not entryIsAura then
        sid = QueryOverrideSpell(sid) or sid
    end
    local itemID, itemSpellID
    if CDMResolvers.IsItemLikeEntry(entry) then
        itemID, _, itemSpellID = CDMResolvers.ResolveItemCooldownIdentity(entry)
        if itemSpellID then
            sid = itemSpellID
        end
    end

    -- Swipe priority for icon cooldown entries: aura → charge/recharge → cd
    -- → gcd. Two paths enforce this single rule:
    --   * Mirror-backed icons:  the mirror's SelectDurationForState
    --     (cdm_blizz_mirror.lua:277) picks lanes in this order, and
    --     BuildMirrorRenderPayload carries the resolved mode out via this
    --     short-circuit. When an aura is up the payload arrives with
    --     mode == "aura" and the aura swipe wins automatically.
    --   * Non-mirror icons:     the explicit ResolveAuraDurationObjectForIcon
    --     check below enforces the same rule for entries with no Blizzard
    --     CDM mirror.
    -- Future change: if you reorder one path, reorder the other in lockstep.
    local mirrorPayload = CDMResolvers.ResolveMirrorRenderPayloadForEntry(
        entry,
        icon._blizzMirrorCooldownID,
        icon._blizzMirrorCategory,
        sid)
    if mirrorPayload then
        return mirrorPayload.durObj,
            mirrorPayload.mode,
            mirrorPayload.sourceID,
            nil,
            nil,
            mirrorPayload.spellID,
            true,
            mirrorPayload
    end

    -- 1. Aura up on player → aura DurObj. Use the same ResolveAuraState path
    -- as UpdateIconCooldown so the event-driven CooldownFrame binding and the
    -- per-icon active-state update cannot disagree in combat. Non-mirror
    -- branch of the priority rule — see comment above the mirror short-circuit.
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
    if entryIsAura or not sid then
        return nil, "inactive", nil
    end

    -- Keep GCD as an explicit lowest-priority duration candidate. Some
    -- CooldownInfo payloads report isOnGCD=true while isActive=false; using
    -- isActive as the gate drops the GCD swipe even though usability is in
    -- the GCD window. Aura, charge, and real cooldown lanes below still win.
    local gcdCdInfo = QueryCooldown(sid)
    local currentOnGCD = GetCurrentIsOnGCD(sid, gcdCdInfo)
    local gcdDurObj
    if currentOnGCD == true and CDMIcons.IsGCDSwipeEnabled() then
        gcdDurObj = QueryGCDDurationObject(sid)
    end

    -- 2. Charge spell mid-recharge → recharge DurObj.
    do
        local ci = QueryCharges(sid)
        local maxCharges = ci and ci.maxCharges
        local chargeActive = ci and SafeBoolean(ci.isActive)
        local isChargeSpell = entry.hasCharges or (maxCharges and maxCharges > 1)
        if isChargeSpell and chargeActive == true then
            local chargeDur = QueryChargeDuration(sid)
            if chargeDur then
                local serial = CDMIcons._chargeDurationObjectSerial or 0
                return chargeDur, "charge", tostring(sid) .. ":" .. tostring(serial)
            end
        end
    end

    -- 3. Spell cooldown active → spell DurObj. A trusted
    -- SPELL_UPDATE_COOLDOWN snapshot, or live isOnGCD when no snapshot is
    -- available, distinguishes real CD from GCD overlay.
    -- Two distinct queries:
    --   real CD branch:   GetSpellCooldownDuration(sid, true)  via QueryDuration
    --                     — returns the spell's own CD, ignoring the GCD that
    --                     would otherwise mask it during the first 1.5s
    --                     after a cast.
    --   gcd-only branch:  GetSpellCooldownDuration(sid, false) — bypass the
    --                     ignoreGCD flag so the API returns the GCD's own
    --                     1.5s DurationObject, which is what we render as
    --                     the GCD swipe overlay. Querying via the cache
    --                     (which forces ignoreGCD=true) would return nil
    --                     for spells with no real CD currently active.
    do
        local cdInfo = gcdCdInfo or QueryCooldown(sid)
        local cdInfoActive = cdInfo and CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
        if cdInfoActive == true then
            local cdInfoOnGCD = GetCurrentIsOnGCD(sid, cdInfo)
            local durObj = QueryDuration(sid)
            local spellUsable = QuerySpellUsableState(sid)
            local durationIsGCD = ShouldTreatLiveDurationAsGCD(
                sid, entry, icon, cdInfo, cdInfoOnGCD, spellUsable)
            if durObj and not durationIsGCD and spellUsable ~= true then
                return durObj, "cooldown", sid
            end
            if cdInfoOnGCD == true then
                if not durationIsGCD and spellUsable ~= true then
                    local preservedDur, preservedMode, preservedSourceID = GetPreservedRealDurationObject(icon)
                    if preservedDur then
                        return preservedDur, preservedMode, preservedSourceID
                    end
                end
                if CDMIcons.IsGCDSwipeEnabled() then
                    local gcdDur = QueryGCDDurationObject(sid)
                    if gcdDur then
                        return gcdDur, "gcd-only", sid
                    end
                    if durObj and durationIsGCD then
                        return durObj, "gcd-only", sid
                    end
                end
            end
        end
    end

    if gcdDurObj then
        return gcdDurObj, "gcd-only", sid
    end

    return nil, "inactive", nil
end

---------------------------------------------------------------------------
-- DEFERRED IMPORT BINDING
-- Called from the tail of cdm_icons.lua once ns.CDMIcons is fully populated.
-- Reassigns the file-level upvalues; every function defined in this file
-- closes over those upvalues, so they all see the late-bound values.
---------------------------------------------------------------------------
function CDMResolvers._FinalizeImports(icons)
    CDMIcons = icons
end
