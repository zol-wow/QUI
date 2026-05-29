-- cdm_spelldata.lua
-- Consolidated CDM module. Former file chunks remain scoped to preserve Lua 5.1 local limits.

do
-- Inlined from cdm_aura_catalog.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Aura Catalog
--
-- Pure helpers for catalog-provided aura links. CDMSpellData owns entry
-- assembly; this module owns ability->aura display remaps and linked aura
-- ID attachment rules derived from the Blizzard catalog maps.
---------------------------------------------------------------------------

local CDMAuraCatalog = {}
ns.CDMAuraCatalog = CDMAuraCatalog

local ipairs = ipairs
local select = select
local type = type

local issecretvalue = issecretvalue or function() return false end

local function IsUsableID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue(id) then return false end
    return id > 0
end

function CDMAuraCatalog.HasDirectAuraChild(mirror, spellID)
    if not (mirror and mirror.GetDirectCooldownIDForViewer and IsUsableID(spellID)) then
        return false
    end
    return mirror.GetDirectCooldownIDForViewer(spellID, "buff")
        or mirror.GetDirectCooldownIDForViewer(spellID, "trackedBar")
end

function CDMAuraCatalog.ResolveEntryAuraDisplay(entryID, abilityToAuraSpellID, mirror)
    if not IsUsableID(entryID) then
        return entryID, false
    end

    local mappedID = abilityToAuraSpellID and abilityToAuraSpellID[entryID]
    if IsUsableID(mappedID)
        and not CDMAuraCatalog.HasDirectAuraChild(mirror, entryID) then
        return mappedID, true
    end

    return entryID, false
end

function CDMAuraCatalog.AttachLinkedAuraIDs(resolved, auraIDsForSpell, getAuraIDsForSpell, ...)
    if not resolved then return end

    local out, seen
    local function appendForSpellID(spellID)
        if not IsUsableID(spellID) then return end

        local ids
        if type(getAuraIDsForSpell) == "function" then
            ids = getAuraIDsForSpell(spellID)
        elseif auraIDsForSpell then
            ids = auraIDsForSpell[spellID]
        end
        if type(ids) ~= "table" then return end

        if not out then
            out = {}
            seen = {}
        end
        for _, auraID in ipairs(ids) do
            if IsUsableID(auraID) and not seen[auraID] then
                seen[auraID] = true
                out[#out + 1] = auraID
            end
        end
    end

    for i = 1, select("#", ...) do
        appendForSpellID(select(i, ...))
    end

    if out and #out > 0 then
        resolved.linkedSpellIDs = out
    end
end
end

do
-- Inlined from cdm_aura_runtime.lua
local _, ns = ...

---------------------------------------------------------------------------
-- CDM Aura Runtime
--
-- Runtime aura-state interface. CDMSpellData currently provides the adapter
-- implementation because it owns the UNIT_AURA capture indexes and scratch
-- helpers; callers consume this module instead of treating SpellData as a
-- parallel runtime truth source.
---------------------------------------------------------------------------

local CDMAuraRuntime = {}
ns.CDMAuraRuntime = CDMAuraRuntime

local resolveState
local getApplications
local getCapturedAura
local resolveAbilityAuraSpellID

function CDMAuraRuntime.SetResolver(callback)
    resolveState = callback
end

function CDMAuraRuntime.ResolveState(params)
    if resolveState then
        return resolveState(params)
    end
    return nil
end

function CDMAuraRuntime.SetApplicationsGetter(callback)
    getApplications = callback
end

function CDMAuraRuntime.GetApplications(unit, auraInstanceID)
    if getApplications then
        return getApplications(unit, auraInstanceID)
    end
    return nil
end

function CDMAuraRuntime.SetCapturedAuraGetter(callback)
    getCapturedAura = callback
end

function CDMAuraRuntime.GetCapturedAuraForLookup(...)
    if getCapturedAura then
        return getCapturedAura(...)
    end
    return nil
end

function CDMAuraRuntime.SetAbilityAuraSpellIDResolver(callback)
    resolveAbilityAuraSpellID = callback
end

function CDMAuraRuntime.ResolveAbilityAuraSpellID(spellID)
    if resolveAbilityAuraSpellID then
        return resolveAbilityAuraSpellID(spellID)
    end
    return spellID, false
end

function CDMAuraRuntime.HasAbilityAuraMapping(spellID)
    local _, remapped = CDMAuraRuntime.ResolveAbilityAuraSpellID(spellID)
    return remapped == true
end
end

do
-- Inlined from cdm_spelldata.lua
--[[
    QUI CDM Spell Data

    Essential/Utility/Buff: observes hidden Blizzard CDM viewers and exports
    spell lists. QUI reads the spell list from hidden Blizzard icons,
    then renders with addon-owned frames.

    All three viewers are hidden (alpha=0, mouse disabled). Blizzard children
    remain in those viewers and feed the mirror; QUI renders addon-owned
    containers from mirrored state and direct API reads.

    Initialization is driven externally by cdm_containers.lua calling
    CDMSpellData:Initialize() — no self-bootstrapping event frame.
]]

local _, ns = ...
local Helpers = ns.Helpers
local Sources = ns.CDMSources
local Shared = ns.CDMShared
local GetTime = GetTime

local function IsCDMRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

---------------------------------------------------------------------------
-- COOLDOWN VIEWER CVAR
-- Forced to 1 unconditionally so Blizzard's CDM data feed runs whether
-- QUI's CDM is enabled (so cdm_blizz_mirror has children to hook) or
-- disabled (so the user can see Blizzard's UI directly). Visual
-- suppression of Blizzard's UI is handled separately by the mirror
-- module's Suppress/Unsuppress, gated on QUI_IsCDMMasterEnabled.
-- Deferred to OOC if in combat — SetCVar fires Blizzard's shown-state
-- refresh synchronously, and that path can compare secret charge values
-- while addon execution is tainted by QUI.
---------------------------------------------------------------------------
local cooldownViewerCVarFrame = CreateFrame("Frame")
local pendingCooldownViewerCVarSync = false

local function IsCooldownViewerCVarEnabled()
    if GetCVarBool then
        local value = GetCVarBool("cooldownViewerEnabled")
        if value ~= nil then
            return value and true or false
        end
    end

    if GetCVar then
        local value = GetCVar("cooldownViewerEnabled")
        return tostring(value) == "1"
    end

    return nil
end

local function SyncCooldownViewerCVarToMasterToggle()
    if InCombatLockdown and InCombatLockdown() then
        pendingCooldownViewerCVarSync = true
        cooldownViewerCVarFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    pendingCooldownViewerCVarSync = false
    cooldownViewerCVarFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")

    -- QUI CDM enabled → Blizzard CDM data feed must be ON (CVar 1) so the
    -- Blizzard mirror (cdm_blizz_mirror.lua) has children to hook. Visuals
    -- are suppressed separately by HideBlizzardViewers below. When QUI's
    -- CDM is off, leave Blizzard CDM enabled (CVar 1) so the user can use
    -- it directly; suppression is reverted by ShowBlizzardViewers.
    local target = 1
    local current = IsCooldownViewerCVarEnabled()
    if current ~= nil and ((target == 0 and current == false) or (target == 1 and current == true)) then
        return true
    end

    if SetCVar then
        SetCVar("cooldownViewerEnabled", target)
    end

    -- After CVar settles, sync visual suppression to the master toggle.
    -- mirror.SyncSuppressionToMaster() reads QUI_IsCDMMasterEnabled and
    -- applies SuppressViewers / UnsuppressViewers accordingly.
    if ns.CDMBlizzMirror and ns.CDMBlizzMirror.SyncSuppressionToMaster then
        ns.CDMBlizzMirror.SyncSuppressionToMaster()
    end
    return true
end

cooldownViewerCVarFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" and pendingCooldownViewerCVarSync then
        SyncCooldownViewerCVarToMasterToggle()
    end
end)

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMSpellData = {}
CDMSpellData.SyncCooldownViewerCVar = SyncCooldownViewerCVarToMasterToggle

-- Zone transition flag — set true on PLAYER_ENTERING_WORLD, cleared after
-- 2s. Suppresses SPELLS_CHANGED dormant checks and Phase 3 permanent
-- deletion while WoW APIs (IsSpellKnown, C_CooldownViewer, spellbook) are
-- returning stale/incomplete data.
local _inZoneTransition = false
-- Set true when a SPELLS_CHANGED is suppressed because _inZoneTransition is
-- active. Drained when the zone-transition window closes (the 2s timer on
-- PLAYER_ENTERING_WORLD), so a reconcile dropped during the window is re-run
-- once the APIs settle instead of being lost until /reload.
local _spellsChangedDuringZoneTransition = false

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local function IsBuiltinContainerKey(containerKey)
    if Shared and Shared.IsBuiltinContainerKey then
        return Shared.IsBuiltinContainerKey(containerKey)
    end
    return Shared and Shared.GetBuiltinContainerEntryKind
        and Shared.GetBuiltinContainerEntryKind(containerKey) ~= nil
        or false
end

local function GetBuiltinContainerKeys()
    if Shared and Shared.BUILTIN_CONTAINER_KEYS then
        return Shared.BUILTIN_CONTAINER_KEYS
    end
    return {}
end

local function GetBuiltinContainerEntryKind(containerKey)
    if Shared and Shared.GetBuiltinContainerEntryKind then
        return Shared.GetBuiltinContainerEntryKind(containerKey)
    end
    return nil
end

local function IsBuiltinAuraContainerKey(containerKey)
    return GetBuiltinContainerEntryKind(containerKey) == "aura"
end

local function IsAuraMirrorCategory(category)
    if Shared and Shared.IsAuraMirrorCategory then
        return Shared.IsAuraMirrorCategory(category)
    end
    return GetBuiltinContainerEntryKind(category) == "aura"
end

local function IsCooldownMirrorCategory(category)
    if Shared and Shared.IsCooldownMirrorCategory then
        return Shared.IsCooldownMirrorCategory(category)
    end
    return GetBuiltinContainerEntryKind(category) == "cooldown"
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local spellLists = {
    essential = {},
    utility   = {},
    buff      = {},
}
local runtimeEventFrame = nil
local initialized = false
local FireChangeCallback

-- Per-batch memo caches for ResolveOwnedEntry candidate scoring.
-- Wiped at the start of each BuildSpellListFromOwned call so all owned
-- entries in one batch share the same spellID→icon and lsid→active lookups.
-- Runtime aura resolution intentionally does not cache Blizzard query
-- results. Aura state can change inside the same combat tick, and stale
-- negatives were hiding newly applied icons/stacks before the next rescan.
local STACK_SEARCH_UNITS = { "player", "pet" }
local SELF_AURA_CAPTURE_LOOKUP_UNITS = { "player", "pet" }
-- Target captures are source-filtered before storage; see
-- CapturePayloadAllowedForUnit.
local AURA_CAPTURE_LOOKUP_UNITS = { "player", "pet", "target" }

---------------------------------------------------------------------------
-- EVENT-PAYLOAD AURA CAPTURE
-- WoW 12.0.5+ restricts direct spell/name aura query functions
-- (GetAuraDataBySpellName, GetPlayerAuraBySpellID) during combat. The
-- AuraData delivered through UNIT_AURA's addedAuras payload carries the
-- auraInstanceID, so we capture it at apply time and use it as the source
-- of truth for duration resolution while restricted-scope lookups are
-- active.
--
-- The auraInstanceID is documented NeverSecret even though the surrounding
-- AuraData payload is ConditionalSecretContents. It can be stored, keyed, and
-- compared safely, and it is forwarded to C-side sinks
-- (C_UnitAuras.GetAuraDuration, C_UnitAuras.GetAuraDataByAuraInstanceID).
--
-- Eviction strategy is event-driven. The `removedAuraInstanceIDs` payload
-- field is documented `NeverSecretContents = true`, and auraInstanceID itself
-- is NeverSecret. Any non-empty
-- `removedAuraInstanceIDs` for a unit is treated as a "something on this unit
-- just died" trigger: walk the unit's cache and validate each entry by
-- forwarding its stored instID to GetAuraDataByAuraInstanceID — nil response
-- → evict by Lua identity. Full UNIT_AURA updates may rescan that unit, but
-- combat/zone/instance/PvP boundaries do not clear or rebuild this cache.
---------------------------------------------------------------------------
local _capturedAuraBySpellID = {}    -- [spellID]      -> {auraInstanceID, unit, spellID, name, filter}
local _capturedAuraByName    = {}    -- [name:lower()] -> same entry
local _capturedAuraByUnitSpellID = {} -- [unit][spellID]      -> same entry
local _capturedAuraByUnitName    = {} -- [unit][name:lower()] -> same entry
local TARGET_CAPTURED_AURA_FILTERS = { HELPFUL = true, HARMFUL = true }
local DEFAULT_CAPTURED_AURA_FILTERS = {
    player = "HELPFUL",
    pet = "HELPFUL",
    target = TARGET_CAPTURED_AURA_FILTERS,
}

local function IsUsableTableKey(key)
    -- Truthy check (not `==`) is secret-safe: it's a C-level type-tag
    -- test, no value comparison. Secret values are typically truthy
    -- (non-nil / non-false), so the explicit IsSecretValue check
    -- catches them before any caller uses the key.
    if not key then return false end
    if issecretvalue and issecretvalue(key) then return false end
    return true
end

local function IsUsableSpellIDKey(spellID)
    return type(spellID) == "number"
        and IsUsableTableKey(spellID)
end

local function IsUsableAuraName(name)
    -- Cannot compare with "" in Lua: secret strings taint on `==`. Trust
    -- callers to treat empty strings as "no useful name" downstream.
    return type(name) == "string"
end

local function GetCleanAuraSpellID(auraData)
    if not auraData then return nil end
    local sid = auraData.spellId
    -- Truthy fallback (not `==`) — sid may be a secret value here, in
    -- which case `sid == nil` would error. `not sid` is a C-level
    -- type-tag test and is secret-safe; if sid is a secret, it's truthy
    -- so we skip the fallback (the secret value will get filtered by
    -- IsUsableSpellIDKey → IsUsableTableKey → IsSecretValue check).
    if not sid then
        sid = auraData.spellID
    end
    return IsUsableSpellIDKey(sid) and sid or nil
end

local function GetCleanAuraName(auraData)
    if not auraData then return nil end
    local name = auraData.name
    -- Secret strings would crash any subsequent `~= ""` or `:lower()`
    -- call. Return nil rather than propagate the secret.
    if issecretvalue and issecretvalue(name) then return nil end
    return IsUsableAuraName(name) and name or nil
end

local function GetCleanAuraIcon(auraData)
    if not auraData then return nil end
    -- AuraData.icon can be a secret number for restricted auras in combat.
    -- Callers compare with `==` (texture-equality validation), which taints
    -- on secret values, so filter to non-secret only — matches the
    -- secret-filter convention of GetCleanAuraSpellID / GetCleanAuraName.
    -- Truthy `if icon and not issecret` (not `~= nil`) is secret-safe.
    local icon = auraData.icon
    if icon and not (issecretvalue and issecretvalue(icon)) then
        return icon
    end
    icon = auraData.iconID
    if icon and not (issecretvalue and issecretvalue(icon)) then
        return icon
    end
    return nil
end

local function GetCleanAuraInstanceID(auraData)
    if not auraData then return nil end
    return auraData.auraInstanceID
end

-- Returns the raw auraInstanceID. This field is NeverSecret; callers can
-- compare it, key by it, or forward it to C-side sinks.
-- Returns nil only when the field doesn't exist.
local function GetRawAuraInstanceID(auraData)
    if not auraData then return nil end
    return auraData.auraInstanceID
end

local function GetCleanAuraApplications(auraData)
    if not auraData then return nil end
    return auraData.applications
end

local function GetDisplayableAuraApplications(auraData)
    local apps = GetCleanAuraApplications(auraData)
    if apps == nil then return nil end
    local appType = type(apps)
    if appType == "number" then
        return apps > 1 and apps or nil
    end
    if appType == "string" then
        if apps == "" or apps == "0" or apps == "1" then
            return nil
        end
        return apps
    end
    return nil
end

local function IsStrictOwnedAuraSource(auraData)
    if not auraData then return false end
    return Helpers.IsAuraOwnedByPlayerOrPet(auraData, true) == true
end

local function IsDefaultCapturedUnit(unit)
    return unit == "player" or unit == "pet"
end

local function GetCapturedUnitMap(root, unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    local map = root[unit]
    if not map then
        map = {}
        root[unit] = map
    end
    return map
end

local function AuraInstancePassesFilter(unit, auraInstanceID, filter)
    if not (Sources and Sources.QueryAuraFilteredOutByInstanceID) then
        return nil
    end
    if type(unit) ~= "string" or unit == "" or type(filter) ~= "string" then
        return nil
    end
    if type(auraInstanceID) ~= "number" or not IsUsableTableKey(auraInstanceID) then
        return nil
    end

    local isFiltered = Sources.QueryAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if type(isFiltered) == "boolean" then
        return isFiltered == false
    end
    return nil
end

local function TargetAuraMatchesPlayerFilter(auraData, filter)
    if not auraData then return false end
    local instID = GetCleanAuraInstanceID(auraData)
    if instID then
        local passes = AuraInstancePassesFilter("target", instID, filter or "HARMFUL|PLAYER")
        if passes ~= nil then return passes end
    end
    return IsStrictOwnedAuraSource(auraData)
end

local function NormalizeCapturedAuraFilter(filter)
    if filter == "HELPFUL" or filter == "HARMFUL" then
        return filter
    end
    return nil
end

local function ResolveCapturedAuraFilter(unit, ad, instID, explicitFilter)
    local filter = NormalizeCapturedAuraFilter(explicitFilter)
    if filter then return filter end

    if ad then
local okH = true; local isHelpful = ad.isHelpful
        if isHelpful == true then return "HELPFUL" end
local okR = true; local isHarmful = ad.isHarmful
        if isHarmful == true then return "HARMFUL" end
    end

    if AuraInstancePassesFilter(unit, instID, "HELPFUL") == true then
        return "HELPFUL"
    end
    if AuraInstancePassesFilter(unit, instID, "HARMFUL") == true then
        return "HARMFUL"
    end
    return nil
end

local function TargetPlayerFilterForCapture(auraFilter)
    if auraFilter == "HELPFUL" then return "HELPFUL|PLAYER" end
    if auraFilter == "HARMFUL" then return "HARMFUL|PLAYER" end
    return nil
end

local function CapturePayloadAllowedForUnit(unit, instID, auraFilter)
    if unit ~= "target" then return true end
    local playerFilter = TargetPlayerFilterForCapture(auraFilter)
    if not playerFilter then return false end
    return AuraInstancePassesFilter(unit, instID, playerFilter) == true
end

local function CapturedAuraMatchesFilter(entry, allowedFiltersByUnit)
    if not entry then return false end
    if allowedFiltersByUnit == false then return true end

    local unit = entry.unit
    local allowed = allowedFiltersByUnit and allowedFiltersByUnit[unit]
    if allowed == nil then
        allowed = DEFAULT_CAPTURED_AURA_FILTERS[unit]
    end
    if allowed == nil or allowed == true then return true end

    local filter = entry.filter
    if type(allowed) == "table" then
        return filter ~= nil and allowed[filter] == true
    end
    return filter == allowed
end

---------------------------------------------------------------------------
-- CAST → AURA CORRELATION
--
-- Bridges the active-aura index for auras whose addedAuras payload arrives
-- after a player cast. UNIT_SPELLCAST_SUCCEEDED carries a clean cast spellID;
-- if a player HELPFUL aura lands within CAST_CORRELATION_WINDOW seconds,
-- synthesize a runtime-only active-aura entry keyed by that cast spellID so
-- configured cast-ID trackers can resolve the current auraInstanceID even
-- when the applied aura's spellID/name differs from the cast/cooldown ID.
---------------------------------------------------------------------------
local CAST_CORRELATION_WINDOW = 0.1

local _recentCasts = {}              -- list of { spellID, time }, pruned

local function ClearDeprecatedLearnedCastToAuraDB()
    local QUI = ns.Addon
    if not QUI or not QUI.db or not QUI.db.global then return nil end
    if QUI.db.global.cdmLearnedCastToAura ~= nil then
        QUI.db.global.cdmLearnedCastToAura = nil
    end
end

local function PruneRecentCasts(now)
    local cutoff = now - CAST_CORRELATION_WINDOW
    while _recentCasts[1] and _recentCasts[1].time < cutoff do
        table.remove(_recentCasts, 1)
    end
end

local function RecordPlayerCast(spellID)
    if not IsUsableSpellIDKey(spellID) then return end
    local now = GetTime()
    PruneRecentCasts(now)
    _recentCasts[#_recentCasts + 1] = { spellID = spellID, time = now }
end

local function FindCorrelatedCast(now)
    PruneRecentCasts(now)
    local last = _recentCasts[#_recentCasts]
    if last then return last.spellID end
    return nil
end

local function StoreCapturedSpellKey(unit, spellID, entry)
    if not IsUsableSpellIDKey(spellID) then return end
    local unitMap = GetCapturedUnitMap(_capturedAuraByUnitSpellID, unit)
    if unitMap then
        unitMap[spellID] = entry
    end
    if IsDefaultCapturedUnit(unit) then
        _capturedAuraBySpellID[spellID] = entry
    end
end

local function StoreCapturedNameKey(unit, nameKey, entry)
    if not IsUsableTableKey(nameKey) then return end
    local unitMap = GetCapturedUnitMap(_capturedAuraByUnitName, unit)
    if unitMap then
        unitMap[nameKey] = entry
    end
    if IsDefaultCapturedUnit(unit) then
        _capturedAuraByName[nameKey] = entry
    end
end

local function CaptureAuraFromPayload(unit, ad, allowCastCorrelation, explicitFilter)
    if not ad then return end
    -- auraInstanceID is NeverSecret, so it can be compared and keyed safely.
    local instID = GetRawAuraInstanceID(ad)
    if not instID then return end

    local sid = GetCleanAuraSpellID(ad)
    local nameRaw = GetCleanAuraName(ad)
    local name, nameKey
local okName = true; local cleanName, cleanNameKey = (function()
        if type(nameRaw) == "string" and nameRaw ~= "" then
            return nameRaw, nameRaw:lower()
        end
        return nil, nil
    end)()
    if cleanName and IsUsableTableKey(cleanNameKey) then
        name = cleanName
        nameKey = cleanNameKey
    end

    local auraFilter = ResolveCapturedAuraFilter(unit, ad, instID, explicitFilter)
    if not CapturePayloadAllowedForUnit(unit, instID, auraFilter) then
        return
    end

    -- Cast→aura correlation. UNIT_SPELLCAST_SUCCEEDED only fires on us.
    -- Store a secondary runtime key under the recent cast spellID. The
    -- authoritative keys remain the aura's own spellID/name when present;
    -- this cast key exists only to cover cast-ID vs aura-ID mismatches on
    -- non-mirrored custom entries in combat.
    local castSID
    if allowCastCorrelation == nil then
        allowCastCorrelation = unit == "player" and auraFilter == "HELPFUL"
    end
    if allowCastCorrelation then
        castSID = FindCorrelatedCast(GetTime())
    end

    -- Without a usable key (sid, name, or correlated castSID), the
    -- entry can't be looked up. Skip rather than build an entry no one
    -- can find.
    if not sid and not name and not castSID then return end

    local entry = {
        auraInstanceID = instID,
        unit = unit,
        spellID = sid or castSID,
        name = name,
        filter = auraFilter,
    }
    if sid then
        StoreCapturedSpellKey(unit, sid, entry)
    end
    if nameKey then
        StoreCapturedNameKey(unit, nameKey, entry)
    end
    -- Synthesize a capture entry under the cast spellID when the cast ID
    -- differs from the aura ID. Keep an existing cast-key entry stable until
    -- it is evicted by the corresponding removedAuraInstanceIDs payload.
    if castSID and castSID ~= sid and not _capturedAuraBySpellID[castSID] then
        StoreCapturedSpellKey(unit, castSID, entry)
    end
end

-- Drop every captured entry whose .unit field matches `unit`. This only
-- compares the (non-secret) "player"/"pet"/"target" string, so it is safe
-- in combat. The auraInstanceID stored on each entry is never inspected.
local function ReleaseCapturedAurasForUnit(unit)
    if type(unit) ~= "string" or unit == "" then return end
    for k, entry in pairs(_capturedAuraBySpellID) do
        if entry and entry.unit == unit then
            _capturedAuraBySpellID[k] = nil
        end
    end
    for k, entry in pairs(_capturedAuraByName) do
        if entry and entry.unit == unit then
            _capturedAuraByName[k] = nil
        end
    end
    local unitSpellMap = _capturedAuraByUnitSpellID[unit]
    if unitSpellMap then wipe(unitSpellMap) end
    local unitNameMap = _capturedAuraByUnitName[unit]
    if unitNameMap then wipe(unitNameMap) end
end

-- Identity-based eviction for the lazy path. Called by tryCapturedAura
-- when a captured entry is discovered to be dead at lookup time. We have
-- the entry reference, so we can walk forward maps and clear by `v ==
-- entry` (Lua table identity, not auraInstanceID equality).
local function ReleaseCapturedEntry(entry)
    if not entry then return end
    for k, v in pairs(_capturedAuraBySpellID) do
        if v == entry then _capturedAuraBySpellID[k] = nil end
    end
    for k, v in pairs(_capturedAuraByName) do
        if v == entry then _capturedAuraByName[k] = nil end
    end
    for _, map in pairs(_capturedAuraByUnitSpellID) do
        for k, v in pairs(map) do
            if v == entry then map[k] = nil end
        end
    end
    for _, map in pairs(_capturedAuraByUnitName) do
        for k, v in pairs(map) do
            if v == entry then map[k] = nil end
        end
    end
end

local function ReleaseCapturedAurasByInstanceIDsForUnit(unit, auraInstanceIDs)
    if type(unit) ~= "string" or unit == "" then return false end
    if type(auraInstanceIDs) ~= "table" then return false end

    local removed = {}
    local hasRemoved = false
    for _, auraInstanceID in ipairs(auraInstanceIDs) do
        if auraInstanceID ~= nil then
            removed[auraInstanceID] = true
            hasRemoved = true
        end
    end
    if not hasRemoved then return false end

    local released = false
    local visited = {}
    local function probe(map)
        if not map then return end
        for _, entry in pairs(map) do
            if entry
               and entry.unit == unit
               and not visited[entry]
               and entry.auraInstanceID ~= nil
               and removed[entry.auraInstanceID] then
                visited[entry] = true
                ReleaseCapturedEntry(entry)
                released = true
            end
        end
    end
    probe(_capturedAuraByUnitSpellID[unit])
    probe(_capturedAuraByUnitName[unit])
    return released
end

-- Eager eviction triggered by UNIT_AURA's `removedAuraInstanceIDs` payload.
-- Walks every cached entry on `unit` and forwards its stored auraInstanceID
-- to GetAuraDataByAuraInstanceID; nil response means the instance is gone.
-- The stored instID is NeverSecret. Eviction is by Lua table identity via
-- ReleaseCapturedEntry. Inlined pcall avoids a forward reference to
-- QueryAuraData, which is declared later in the file.
local function EvictDeadCacheEntriesForUnit(unit)
    if type(unit) ~= "string" or unit == "" then return end
    if not (Sources and Sources.QueryAuraDataByAuraInstanceID) then return end

    local visited = {}
    local function probe(map)
        if not map then return end
        for _, entry in pairs(map) do
            if entry and not visited[entry] and entry.auraInstanceID then
                visited[entry] = true
                local data = Sources.QueryAuraDataByAuraInstanceID(unit, entry.auraInstanceID)
                if not data then
                    ReleaseCapturedEntry(entry)
                end
            end
        end
    end
    probe(_capturedAuraByUnitSpellID[unit])
    probe(_capturedAuraByUnitName[unit])
end

-- Full rescan via AuraUtil.ForEachAura. Used only on UNIT_AURA isFullUpdate
-- (which carries no addedAuras list — it's a "rescan everything" signal).
--
-- In combat, some packed payload fields can be secret; auraInstanceID is
-- NeverSecret and is captured directly.
--
-- usePackedAura=true (5th arg) is required: without it, Blizzard's helper
-- calls AuraUtil.UnpackAuraData on each aura, whose final expression is
-- unpack(auraData.points or {}). When points is a secret value (which the
-- `or {}` doesn't catch — only nil), unpack(secret) errors. Receiving the
-- packed table directly skips that, and CaptureAuraFromPayload is already
-- secret-safe on every field it reads.
local function RescanCapturedAurasForUnit(unit)
    if not (AuraUtil and AuraUtil.ForEachAura) then return end
    if unit == "target" then
        ReleaseCapturedAurasForUnit(unit)
        return
    end
    ReleaseCapturedAurasForUnit(unit)
    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(ad)
        CaptureAuraFromPayload(unit, ad, nil, "HELPFUL")
        return false  -- continue iterating
    end, true)
    AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(ad)
        CaptureAuraFromPayload(unit, ad, false, "HARMFUL")
        return false
    end, true)
end

local function NotifyAuraConsumers(unit, updateInfo)
    local mirror = ns.CDMBlizzMirror
    if mirror and mirror.HandleUnitAuraChanged then
        mirror.HandleUnitAuraChanged(unit, updateInfo)
    end
    local icons = ns.CDMIcons
    if icons and icons.HandleRuntimeRefresh then
        icons.HandleRuntimeRefresh("UNIT_AURA", unit, updateInfo)
    end
    local glows = ns._OwnedGlows
    if glows and glows.HandleUnitAuraChanged then
        glows.HandleUnitAuraChanged(unit, updateInfo)
    end
end

local auraCaptureFrame = CreateFrame("Frame")
local function AuraCaptureFrameOnEvent(self, event, ...)
    if not IsCDMRuntimeEnabled() then
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Args: (unit, castGUID, spellID, castBarID). Filtered to player
        -- via RegisterUnitEvent; explicit unit check is belt-and-suspenders.
        local unit, _, spellID = ...
        if unit == "player" then
            RecordPlayerCast(spellID)
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        ReleaseCapturedAurasForUnit("target")
        NotifyAuraConsumers("target", nil)
        return
    end
    if event ~= "UNIT_AURA" then return end
    local unit, updateInfo = ...
    if not updateInfo or updateInfo.isFullUpdate then
        -- isFullUpdate carries no aura list; it's a "rescan everything"
        -- signal. Walk the live aura state directly to repopulate the
        -- active-aura index.
        RescanCapturedAurasForUnit(unit)
        NotifyAuraConsumers(unit, updateInfo)
        return
    end
    if updateInfo.addedAuras then
        for _, ad in ipairs(updateInfo.addedAuras) do
            CaptureAuraFromPayload(unit, ad)
        end
    end
    -- Eager cache eviction: any non-empty removedAuraInstanceIDs means at
    -- least one aura on `unit` just expired or was dispelled. Walk the
    -- unit's cache and drop dead entries immediately so the next bar/icon
    -- update sees an accurate state instead of waiting for a lazy lookup
    -- (which has its own combat-side fallback hazards in
    -- ResolveAuraInstanceDurationState). updatedAuraInstanceIDs is still
    -- ignored — duration changes don't affect cache liveness.
    if updateInfo.removedAuraInstanceIDs
        and #updateInfo.removedAuraInstanceIDs > 0 then
        if unit == "target" then
            ReleaseCapturedAurasByInstanceIDsForUnit(unit, updateInfo.removedAuraInstanceIDs)
        else
            EvictDeadCacheEntriesForUnit(unit)
        end
    end
    NotifyAuraConsumers(unit, updateInfo)
end

local function RegisterAuraCaptureFrame()
    auraCaptureFrame:SetScript("OnEvent", AuraCaptureFrameOnEvent)
    auraCaptureFrame:RegisterUnitEvent("UNIT_AURA", "player", "pet", "target")
    auraCaptureFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    auraCaptureFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
end

RegisterAuraCaptureFrame()

function CDMSpellData:DisableRuntime()
    initialized = false
    pendingCooldownViewerCVarSync = false
    cooldownViewerCVarFrame:UnregisterAllEvents()
    auraCaptureFrame:UnregisterAllEvents()
    auraCaptureFrame:SetScript("OnEvent", nil)
    if runtimeEventFrame then
        runtimeEventFrame:UnregisterAllEvents()
        runtimeEventFrame:SetScript("OnEvent", nil)
        runtimeEventFrame = nil
    end
end

local function GetCapturedAuraForLookup(spellIDs, entryName, preferredUnits, allowGlobalFallback, allowedFiltersByUnit)
    if preferredUnits then
        for unitIdx = 1, #preferredUnits do
            local unit = preferredUnits[unitIdx]
            local spellMap = _capturedAuraByUnitSpellID[unit]
            if spellMap and spellIDs then
                for i = 1, #spellIDs do
                    local sid = spellIDs[i]
                    if IsUsableTableKey(sid) then
                        local entry = spellMap[sid]
                        if entry and entry.auraInstanceID
                           and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                            return entry
                        end
                    end
                end
            end
            local nameMap = _capturedAuraByUnitName[unit]
            if nameMap and type(entryName) == "string" then
local okName = true; local nameKey = (function()
                    if entryName ~= "" then
                        return entryName:lower()
                    end
                    return nil
                end)()
                if IsUsableTableKey(nameKey) then
                    local entry = nameMap[nameKey]
                    if entry and entry.auraInstanceID
                       and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                        return entry
                    end
                end
            end
        end
    end

    if allowGlobalFallback == false then
        return nil
    end

    if spellIDs then
        for i = 1, #spellIDs do
            local sid = spellIDs[i]
            if IsUsableTableKey(sid) then
                local entry = _capturedAuraBySpellID[sid]
                if entry and entry.auraInstanceID
                   and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                    return entry
                end
            end
        end
    end
    if type(entryName) == "string" then
local okName = true; local nameKey = (function()
            if entryName ~= "" then
                return entryName:lower()
            end
            return nil
        end)()
        if IsUsableTableKey(nameKey) then
            local entry = _capturedAuraByName[nameKey]
            if entry and entry.auraInstanceID
               and CapturedAuraMatchesFilter(entry, allowedFiltersByUnit) then
                return entry
            end
        end
    end
    return nil
end

-- Live passthroughs through CDMSources. No caching: each call is a live read.
-- Forward auraInstanceIDs straight through to the C-side sink.
local function QueryAuraData(unit, instanceID)
    if not instanceID then return nil end
    return Sources and Sources.QueryAuraDataByAuraInstanceID
        and Sources.QueryAuraDataByAuraInstanceID(unit, instanceID)
end

local function QueryAuraDuration(unit, instanceID)
    if not instanceID or not (Sources and Sources.QueryAuraDuration) then return nil end
    return Sources.QueryAuraDuration(unit, instanceID)
end

local function IsOwnedAuraData(auraData)
    return auraData
        and Helpers
        and Helpers.IsAuraOwnedByPlayerOrPet
        and Helpers.IsAuraOwnedByPlayerOrPet(auraData, true) == true
end

local function ResolveMirrorAuraUnit(m)
    local auraUnit = m and m.auraUnit
    if type(auraUnit) == "string" and auraUnit ~= "" then
        return auraUnit
    end
    if m and m.selfAura == false then
        return "target"
    end
    return "player"
end

local function ResolveOwnedTargetMirrorAuraData(m, auraUnit)
    local auraData = m and type(m.auraData) == "table" and m.auraData or nil
    if IsOwnedAuraData(auraData) then
        return auraData
    end
    local auraInstanceID = m and m.auraInstanceID
    if not (auraUnit == "target" and auraInstanceID and Sources and Sources.QueryAuraDataByAuraInstanceID) then
        return nil
    end

    local queried = QueryAuraData(auraUnit, auraInstanceID)
    if IsOwnedAuraData(queried) then
        return queried
    end
    return nil
end

local function DecodePotentialSecretBoolean(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if value == nil then return nil end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function QueryAuraHasExpirationTime(unit, instanceID)
    if not instanceID or not (Sources and Sources.QueryAuraHasExpirationTime) then return nil end
    if InCombatLockdown() then return nil end
    return DecodePotentialSecretBoolean(Sources.QueryAuraHasExpirationTime(unit, instanceID))
end

local function GetReadableAuraDurationState(auraData)
    if not auraData then return nil end
    local duration = auraData.duration
    if issecretvalue and issecretvalue(duration) then
        return nil
    end
    if duration == nil then
        return false
    end
    if type(duration) ~= "number" then
        return nil
    end
    if InCombatLockdown() then
        return nil
    end
local okCompare = true; local hasNoDuration = duration <= 0
    if not okCompare then
        return nil
    end
    if hasNoDuration then
        return false
    end
    return true
end

local function ApplyAuraExpirationState(result, auraUnit, auraInstanceID, auraData)
    local hasExpiration = QueryAuraHasExpirationTime(auraUnit, auraInstanceID)
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

local function FilterWantsToken(filter, token)
    return type(filter) == "string"
        and type(token) == "string"
        and filter:find(token, 1, true) ~= nil
end

local function AuraDataMatchesFilter(unit, auraData, filter, filterWasApplied)
    if not auraData then return false end
    if type(filter) ~= "string" or filter == "" then
        return true
    end
    if filterWasApplied then
        return true
    end

    local instID = GetCleanAuraInstanceID(auraData)
    if FilterWantsToken(filter, "HELPFUL") then
local okH = true; local helpful = auraData.isHelpful
        if helpful == true then return true end
        if helpful == false then return false end
        local passes = AuraInstancePassesFilter(unit, instID, "HELPFUL")
        if passes ~= nil then return passes end
local okR = true; local harmful = auraData.isHarmful
        if harmful == true then return false end
        return false
    end

    if FilterWantsToken(filter, "HARMFUL") then
local okR = true; local harmful = auraData.isHarmful
        if harmful == true then
            if FilterWantsToken(filter, "PLAYER") then
                if unit == "target" then
                    return TargetAuraMatchesPlayerFilter(auraData, filter)
                end
                return IsStrictOwnedAuraSource(auraData)
            end
            return true
        end
        if harmful == false then return false end
        local passes = AuraInstancePassesFilter(unit, instID, filter)
        if passes ~= nil then return passes end
local okH = true; local helpful = auraData.isHelpful
        if helpful == true then return false end
        return false
    end

    return true
end

local function QueryUnitAuraBySpellID(unit, spellID, filter)
    if not unit or not spellID then
        return nil
    end

    local hasFilter = type(filter) == "string" and filter ~= ""

    -- C_UnitAuras.GetUnitAuraBySpellID(unit, spellID) is the canonical entry
    -- point. It takes no filter; spellID unambiguously identifies the aura.
    -- SecretWhenUnitAuraRestricted = true: returns AuraData (possibly with
    -- secret fields like spellId; auraInstanceID is NeverSecret) in combat — never nil for
    -- combat-restriction reasons. AuraDataMatchesFilter validates the
    -- HARMFUL / HELPFUL classification via the (non-secret) isHarmful /
    -- isHelpful fields and PLAYER ownership via isFromPlayerOrPlayerPet.
    if Sources and Sources.QueryUnitAuraBySpellID then
        local auraData = Sources.QueryUnitAuraBySpellID(unit, spellID)
        if AuraDataMatchesFilter(unit, auraData, filter, not hasFilter) then
            return auraData
        end
    end

    if unit == "player"
        and (not filter or filter == "HELPFUL")
        and Sources and Sources.QueryPlayerAuraBySpellID then
        local auraData = Sources.QueryPlayerAuraBySpellID(spellID)
        if AuraDataMatchesFilter(unit, auraData, filter, false) then
            return auraData
        end
    end

    return nil
end

local function IsUsableResolvedAuraData(auraUnit, auraData)
    if not auraData then return false end
    if IsSelfUnit(auraUnit) then
        return true
    end
    return IsAuraOwnedByPlayerOrPet(auraData, true)
end

local function ResolveAuraInstanceDurationState(result, auraUnit, auraInstanceID, auraData)
    if not auraUnit or not auraInstanceID then
        return false, nil
    end

    local hasExpiration = ApplyAuraExpirationState(result, auraUnit, auraInstanceID, auraData)
    if hasExpiration == false then
        return true, nil
    end

    local durObj = QueryAuraDuration(auraUnit, auraInstanceID)
    if durObj then
        return true, durObj
    end

    if InCombatLockdown() then
        -- In combat, both QueryAuraHasExpirationTime (bails on lockdown) and
        -- QueryAuraDuration can transiently return nil for live auras with
        -- restricted-scope payloads — a nil return is NOT proof the aura is
        -- gone. Returning `false, nil` from this defensive fallback caused
        -- the resolver to flip the icon's `_auraActive`/`_lastAuraDurObj` to
        -- nil mid-combat, gating off pandemic glow for any aura whose
        -- duration query had a transient miss between UNIT_AURA ticks.
        --
        -- Liveness in combat is owned by eager eviction in
        -- AuraCaptureFrameOnEvent (driven by removedAuraInstanceIDs), which
        -- walks the unit's cache on every aura-removal payload and drops
        -- entries whose stored instID no longer resolves via
        -- GetAuraDataByAuraInstanceID. Genuinely-expired auras get evicted
        -- there, so by the time tryCapturedAura runs the cache reflects
        -- reality — there's nothing to defensively probe at this point.
        --
        -- Mark this as unknown so icon code can preserve an existing
        -- DurationObject only for the transient combat-miss case, not for
        -- a confirmed durationless aura.
        result.durationStateUnknown = true
        return true, nil
    end

    return hasExpiration ~= nil, nil
end

local function GetAuraApplications(unit, auraInstanceID)
    if not unit or not auraInstanceID or not (Sources and Sources.QueryAuraApplicationDisplayCount) then
        return false, nil
    end
    -- minDisplayCount = 1: abilities that count from a single application (e.g.
    -- Reaper's Mark) must show their stack. The C sink returns "" below this and
    -- a secret string when the unit's auras are restricted -- forwarded verbatim,
    -- never Lua-compared.
    local stacks = Sources.QueryAuraApplicationDisplayCount(unit, auraInstanceID, 1, 99)
    if (issecretvalue and issecretvalue(stacks))
        or (type(stacks) == "string" and stacks ~= "" and stacks ~= "0") then
        return true, stacks
    end
    return false, nil
end

local function GetOwnedTargetFilter(filter)
    local base = filter or "HARMFUL"
    if FilterWantsToken(base, "PLAYER") then
        return base
    end
    return base .. "|PLAYER"
end

local function IsUsableTargetAuraData(auraData, filter)
    if not auraData then return false end
    return TargetAuraMatchesPlayerFilter(auraData, filter or "HARMFUL|PLAYER")
end

local function ScanOwnedTargetAuraBySpellID(spellID, filter)
    if not IsUsableSpellIDKey(spellID) then return nil end
    -- Combat bail: walking target HARMFUL slots in combat would compare
    -- ad.spellId (secret in combat for target debuffs) which taints. The
    -- Blizzard CDM mirror (cdm_blizz_mirror.lua) covers the in-combat case
    -- for spells that have a viewer child; non-mirrored spells fall back
    -- to OOC behavior only.
    if InCombatLockdown() then return nil end
    local scanFilter = GetOwnedTargetFilter(filter)
    if Sources and Sources.QueryUnitAuras then
        local auras = Sources.QueryUnitAuras("target", scanFilter, 40)
        if auras then
            for i = 1, #auras do
                local auraData = auras[i]
                if auraData
                   and GetCleanAuraSpellID(auraData) == spellID
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
               and GetCleanAuraSpellID(auraData) == spellID
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
    if not IsUsableAuraName(spellName) then return nil end
    if InCombatLockdown() then return nil end
    local scanFilter = GetOwnedTargetFilter(filter)
    -- auraData.name can be a secret string in restricted-execution paths
    -- (e.g., Lua-side secure-template handlers like TargetUnit). Comparing
    -- a secret string to spellName with `==` faults, so skip per-aura
    -- entries whose name is secret — they can't be matched by name and
    -- the higher-level FindOwnedTargetAuraByName already tried the
    -- secret-safe GetAuraDataBySpellName API path before falling here.
    local function NameMatches(auraData)
        local rawName = auraData.name
        if rawName == nil then return false end
        if issecretvalue and issecretvalue(rawName) then return false end
        if type(rawName) ~= "string" then return false end
        return rawName == spellName
    end
    if Sources and Sources.QueryUnitAuras then
        local auras = Sources.QueryUnitAuras("target", scanFilter, 40)
        if auras then
            for i = 1, #auras do
                local auraData = auras[i]
                if auraData
                   and NameMatches(auraData)
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
               and NameMatches(auraData)
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

    -- Combat target-aura lookup is owned by the Blizzard CDM mirror
    -- (cdm_blizz_mirror.lua) and consumed in resolver Phase 3.0. This
    -- function is the OOC fallback for spells the mirror doesn't have,
    -- and for slot-walk last resort.
    local directFilter = GetOwnedTargetFilter(filter)
    local ad = QueryUnitAuraBySpellID("target", spellID, directFilter)
    if ad then return ad end

    return ScanOwnedTargetAuraBySpellID(spellID, filter)
end

local function FindOwnedTargetAuraByName(spellName, filter)
    if not IsUsableAuraName(spellName) then return nil end

    if Sources and Sources.QueryAuraDataBySpellName then
        local directFilter = GetOwnedTargetFilter(filter)
        local ad = Sources.QueryAuraDataBySpellName("target", spellName, directFilter)
        if GetCleanAuraInstanceID(ad) and IsUsableTargetAuraData(ad, directFilter) then
            return ad
        end
    end

    return ScanOwnedTargetAuraByName(spellName, filter)
end


local function SafeMaybeNumber(value)
    return type(value) == "number" and value or tonumber(value)
end

-- Slot-driven totem detection. State is sourced exclusively from
-- GetTotemInfo / GetTotemDuration; no Blizzard viewer children are
-- consulted any more.
local function ResolveVirtualAuraState(explicitSlot)
    local slot = SafeMaybeNumber(explicitSlot)
    local state = { slot = slot }

    if slot and GetTotemInfo then
local tok = true; local _, totemName, _, _, totemIcon = GetTotemInfo(slot)
        if tok then
            state.totemName = totemName
            state.totemIcon = totemIcon
        end
    end

    if slot and GetTotemDuration then
        local durObj = GetTotemDuration(slot)
        if durObj and type(durObj) ~= "number" then
            -- Totem-slot strategy: do not branch on secret booleans from slot APIs.
            -- If the slot resolves and yields a DurationObject, treat that object as
            -- the authoritative active-state source.
            state.isActive = true
            state.auraUnit = "player"
            state.durObj = durObj
            state.isTotemInstance = true
            return state
        end
    end

    return state
end

---------------------------------------------------------------------------
-- UNIFIED AURA DETECTION
-- Single detection path shared by both icons (cdm_icon_renderer.lua) and bars
-- (cdm_bar_renderer.lua).  Returns all data both consumers need for display.
-- Result table is module-level, wiped each call (safe because icons and
-- bars process frames sequentially within a single UpdateAll cycle).
---------------------------------------------------------------------------
local _auraResult = {
    isActive = false,
    auraInstanceID = nil,
    auraUnit = "player",
    durObj = nil,
    auraData = nil,
    count = nil,
    resolvedAuraSpellID = nil,
    hasExpirationTime = nil,
    hideDurationText = nil,
    durationStateUnknown = nil,
    totemSlot = nil,
    totemName = nil,
    totemIcon = nil,
    isTotemInstance = false,
}

local _auraCountResult = {
    value = nil,
    sinkText = nil,
    shown = false,
    source = nil,
}
_auraResult.count = _auraCountResult

local function IsSecretCountValue(value)
    return issecretvalue and issecretvalue(value) or false
end

local function SafeCountNumber(value)
    if value == nil or IsSecretCountValue(value) then
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

local function SetAuraCount(result, value, source, shown)
    local count = result and result.count
    if not count then return end

    count.value = nil
    count.sinkText = nil
    count.shown = false
    count.source = nil

    if shown == false or value == nil then
        return
    end

    count.value = SafeCountNumber(value)
    count.sinkText = value
    count.shown = true
    count.source = source
end

local function WipeAuraResult()
    _auraResult.isActive = false
    _auraResult.auraInstanceID = nil
    _auraResult.auraUnit = "player"
    _auraResult.durObj = nil
    _auraCountResult.value = nil
    _auraCountResult.sinkText = nil
    _auraCountResult.shown = false
    _auraCountResult.source = nil
    _auraResult.auraData = nil
    _auraResult.resolvedAuraSpellID = nil
    _auraResult.hasExpirationTime = nil
    _auraResult.hideDurationText = nil
    _auraResult.durationStateUnknown = nil
    _auraResult.totemSlot = nil
    _auraResult.totemName = nil
    _auraResult.totemIcon = nil
    _auraResult.isTotemInstance = false
end

local function SetResolvedAuraSpellID(result, auraData, fallbackID)
    if not result then return end
    local sid = GetCleanAuraSpellID(auraData)
    if not IsUsableTableKey(sid) then
        sid = fallbackID
    end
    if IsUsableTableKey(sid) then
        result.resolvedAuraSpellID = sid
    end
end

-- Aura-debug helpers (ShouldDebugAuraState, AuraStateDebug,
-- FormatAuraMirrorState) live in the load-on-demand debug addon. The
-- placeholders below are rebound by cdm_debug.lua's BindAll() when loaded.
local ShouldDebugAuraState = function() return false end
local AuraStateDebug       = function() end
local FormatAuraMirrorState = function() return "nil" end
local FormatIDList         = function() return "nil" end

---------------------------------------------------------------------------
-- Runtime aura resolver scratch state.
--
-- The runtime aura resolver used to declare ~20 nested closures per call. In raid
-- combat that produced multi-MB/s of transient closure garbage and dominated
-- GC churn. The scratch struct + pooled tables below let all the per-call
-- helpers run as file-scope functions, reading and writing shared state by
-- field instead of by upvalue capture. Aura resolution is not re-entrant
-- within a single tick (icons are processed sequentially), so a singleton
-- scratch is safe.
--
-- Pool semantics: cooldownLinkedAuraIDs / mirrorRestrictedAuraIDs are lazy
-- in the original code — non-nil only after the first add. The pooled
-- versions are always allocated; the corresponding scratch field is left
-- nil until an add aliases it to the pool. Body code can then keep the
-- existing `if s.X then ... end` checks.
---------------------------------------------------------------------------
local _resolveAuraScratch = {
    -- Inputs (set per call from params)
    spellID = nil, entrySpellID = nil, entryID = nil, entryName = nil,
    entryIsAura = false, entryTexture = nil, viewerType = nil,
    blizzardMirrorCooldownID = nil, blizzardMirrorCategory = nil,
    debugAura = false, isBuiltinAuraViewer = false,

    -- Phase 0 derived
    mirror = nil, viewerCat = nil,
    isBuiltinAuraCat = false, isBuiltinCooldownCat = false,

    -- Cross-phase: cooldown linked-aura mode
    cooldownLinkedAuraIDs = nil, cooldownLinkedAuraIDSet = nil,
    cooldownLinkedAuraModeKnown = false,
    cooldownLinkedAuraModeAllowsAura = false,

    -- Cross-phase: mirror restriction
    mirrorRestrictedAuraIDs = nil, mirrorRestrictedAuraIDSet = nil,
    mirrorRestrictsAuraFallbacks = false,
    mirrorRestrictedAuraRequiresExactSpellID = false,
    mirrorRestrictedAuraAllowsCapturedName = false,
    mirrorRestrictedAuraUnit = nil,

    -- Phase 0 aura branch: match recording
    auraMirrorMatched = false, auraMirrorMatchedState = nil,
    auraMirrorMatchedCat = nil, auraMirrorMatchedID = nil,

    -- Phase 3 candidate building
    hasCooldownAuraID = false,
}

-- Pooled tables. Always allocated; wiped at each call's start.
local _scratchCooldownLinkedAuraIDs    = {}
local _scratchCooldownLinkedAuraIDSet  = {}
local _scratchMirrorRestrictedAuraIDs  = {}
local _scratchMirrorRestrictedAuraIDSet = {}
local _scratchSeenMirrorIDs = {}
local _scratchCandidateIDs  = {}
local _scratchCandidateSeen = {}
local _scratchProbeIDs      = {}
local _scratchProbeSeen     = {}

local function WipeResolveAuraScratch()
    local s = _resolveAuraScratch
    s.spellID = nil; s.entrySpellID = nil; s.entryID = nil; s.entryName = nil
    s.entryIsAura = false; s.entryTexture = nil; s.viewerType = nil
    s.blizzardMirrorCooldownID = nil; s.blizzardMirrorCategory = nil
    s.debugAura = false; s.isBuiltinAuraViewer = false
    s.mirror = nil; s.viewerCat = nil
    s.isBuiltinAuraCat = false; s.isBuiltinCooldownCat = false
    s.cooldownLinkedAuraIDs = nil; s.cooldownLinkedAuraIDSet = nil
    s.cooldownLinkedAuraModeKnown = false
    s.cooldownLinkedAuraModeAllowsAura = false
    s.mirrorRestrictedAuraIDs = nil; s.mirrorRestrictedAuraIDSet = nil
    s.mirrorRestrictsAuraFallbacks = false
    s.mirrorRestrictedAuraRequiresExactSpellID = false
    s.mirrorRestrictedAuraAllowsCapturedName = false
    s.mirrorRestrictedAuraUnit = nil
    s.auraMirrorMatched = false; s.auraMirrorMatchedState = nil
    s.auraMirrorMatchedCat = nil; s.auraMirrorMatchedID = nil
    s.hasCooldownAuraID = false
    wipe(_scratchCooldownLinkedAuraIDs)
    wipe(_scratchCooldownLinkedAuraIDSet)
    wipe(_scratchMirrorRestrictedAuraIDs)
    wipe(_scratchMirrorRestrictedAuraIDSet)
    wipe(_scratchSeenMirrorIDs)
    wipe(_scratchCandidateIDs)
    wipe(_scratchCandidateSeen)
    wipe(_scratchProbeIDs)
    wipe(_scratchProbeSeen)
end

local _AURA_VIEWER_CAT_BUFF_FIRST = { "buff", "trackedBar" }

-- Category A: cross-phase linked-aura helpers.
local function ResolveAuraRememberCooldownLinkedAuraID(id)
    if not IsUsableTableKey(id) then return end
    local s = _resolveAuraScratch
    if not s.cooldownLinkedAuraIDs then
        s.cooldownLinkedAuraIDs = _scratchCooldownLinkedAuraIDs
        s.cooldownLinkedAuraIDSet = _scratchCooldownLinkedAuraIDSet
    end
    if s.cooldownLinkedAuraIDSet[id] then return end
    s.cooldownLinkedAuraIDSet[id] = true
    s.cooldownLinkedAuraIDs[#s.cooldownLinkedAuraIDs + 1] = id
end

local function ResolveAuraRememberCooldownLinkedAuraIDs(linkedIDs)
    if type(linkedIDs) ~= "table" then return end
    for _, linkedID in ipairs(linkedIDs) do
        ResolveAuraRememberCooldownLinkedAuraID(linkedID)
    end
end

local function ResolveAuraRememberCooldownInfoLinkedAuraIDs(info)
    if not info or info.hasAura == false then return end
    ResolveAuraRememberCooldownLinkedAuraIDs(info.linkedSpellIDs)
end

local function ResolveAuraRememberCooldownLinkedAuraMode(state)
    if not state then return end
    if state.wasSetFromAura ~= nil
        or state.wasSetFromCooldown ~= nil
        or state.wasSetFromCharges ~= nil then
        local s = _resolveAuraScratch
        s.cooldownLinkedAuraModeKnown = true
        s.cooldownLinkedAuraModeAllowsAura = state.wasSetFromAura == true
    end
end

local function ResolveAuraCooldownLinkedAuraFallbackAllowed()
    local s = _resolveAuraScratch
    return s.cooldownLinkedAuraModeKnown and s.cooldownLinkedAuraModeAllowsAura
end

-- Category B (Phase 0 aura branch): mirror-match recording, aura state
-- lookup, and apply helpers.
local function ResolveAuraRememberMirrorMatch(m, cat, tryID)
    if not m then return end
    local s = _resolveAuraScratch
    s.auraMirrorMatched = true
    if not s.auraMirrorMatchedState then
        s.auraMirrorMatchedState = m
        s.auraMirrorMatchedCat = cat
        s.auraMirrorMatchedID = tryID
    end
end

local function ResolveAuraHasActiveDuration(m)
    -- Packed mirror state (PackState) exposes aura activity via
    -- auraInstanceID + auraDurObj, NOT flat isActive/durObj (those were
    -- removed). Matches the migrated ResolveAuraTrySiblingMirror check so a
    -- buff/trackedBar mirror state ranks as "active with a countdown."
    return m and m.auraInstanceID and m.auraDurObj
end

local function ResolveAuraLookupAuraState(tryID)
    if not tryID then return nil, nil end
    local s = _resolveAuraScratch
    local mirror = s.mirror
    if not mirror then return nil, nil end
    local getAuraState = mirror.GetDirectMirroredStateForViewer
        or mirror.GetMirroredStateForViewer
    local viewerCat = s.viewerCat
    if s.isBuiltinAuraCat and mirror.GetMirroredStateForViewer then
        local primary = getAuraState(tryID, viewerCat)
        local fallbackCat = (viewerCat == "buff") and "trackedBar" or "buff"
        local fallback = getAuraState(tryID, fallbackCat)
        ResolveAuraRememberMirrorMatch(primary, viewerCat, tryID)
        ResolveAuraRememberMirrorMatch(fallback, fallbackCat, tryID)
        if s.debugAura then
            AuraStateDebug(s.debugAura, "phase0-aura-pool",
                "tryID=", tryID,
                "primary=", FormatAuraMirrorState(primary),
                "fallback=", FormatAuraMirrorState(fallback))
        end
        if ResolveAuraHasActiveDuration(primary) then return primary, viewerCat end
        if ResolveAuraHasActiveDuration(fallback) then return fallback, fallbackCat end
        if primary then return primary, viewerCat end
        if fallback then return fallback, fallbackCat end
        return nil, nil
    end
    if mirror.GetMirroredStateForViewer then
        local m = getAuraState(tryID, "buff")
        local fallback = getAuraState(tryID, "trackedBar")
        ResolveAuraRememberMirrorMatch(m, "buff", tryID)
        ResolveAuraRememberMirrorMatch(fallback, "trackedBar", tryID)
        if s.debugAura then
            AuraStateDebug(s.debugAura, "phase0-aura-pool",
                "tryID=", tryID,
                "primary=", FormatAuraMirrorState(m),
                "fallback=", FormatAuraMirrorState(fallback))
        end
        if ResolveAuraHasActiveDuration(m) then return m, "buff" end
        if ResolveAuraHasActiveDuration(fallback) then return fallback, "trackedBar" end
        if m then return m, "buff" end
        if fallback then return fallback, "trackedBar" end
    end
    return nil, nil
end

local function ResolveAuraApplyMirrorState(m, hostCat, tryID, phaseName)
    -- Active-with-duration is signalled by auraInstanceID + auraDurObj on the
    -- packed state (PackState no longer emits isActive/durObj). Without this an
    -- aura entry whose only backing cdID lives in the sibling viewer (buff
    -- entry, trackedBar mirror) could find the state but never surface it.
    if not (m and m.auraInstanceID and m.auraDurObj) then return false end
    local s = _resolveAuraScratch
    local r = _auraResult
    local auraUnit = ResolveMirrorAuraUnit(m)
    local targetAuraData
    if auraUnit == "target" then
        -- The mirror capture path already applied the player-owned target
        -- aura filter; live auraData is optional enrichment and may be hidden.
        targetAuraData = ResolveOwnedTargetMirrorAuraData(m, auraUnit)
        if not targetAuraData then
            AuraStateDebug(s.debugAura, (phaseName or "phase0-aura") .. "-owner-unreadable",
                "spellID=", tryID, "hostCat=", hostCat,
                "selfAura=", tostring(m.selfAura),
                "cdID=", m.cooldownID, "epoch=", m.mirrorEpoch)
        end
    end
    AuraStateDebug(s.debugAura, phaseName or "phase0-aura",
        "spellID=", tryID, "hostCat=", hostCat,
        "selfAura=", tostring(m.selfAura),
        "cdID=", m.cooldownID, "epoch=", m.mirrorEpoch,
        "durObj=", m.auraDurObj and "yes" or "nil")
    r.isActive = true
    r.durObj = m.auraDurObj
    -- Aura's destination unit comes from the cdID's own selfAura field, not
    -- the host viewer cat. Empirically buff cat carries selfAura=false
    -- target-side entries (Virulent Plague, Dread Plague), so cat-derived
    -- unit assignment misroutes those to "player".
    r.auraUnit = auraUnit
    r.auraInstanceID = m.auraInstanceID
    r.auraData = targetAuraData or (type(m.auraData) == "table" and m.auraData or nil)
    local auraStackText = m.auraStackText
    if auraStackText ~= nil or IsSecretCountValue(auraStackText) then
        if not IsSecretCountValue(m.auraStackTextShown) and m.auraStackTextShown == false then
            SetAuraCount(r, nil, m.auraStackTextSource or "Applications", false)
        else
            SetAuraCount(r, auraStackText, m.auraStackTextSource or "Applications", true)
        end
    elseif not IsSecretCountValue(m.stackTextShown) and m.stackTextShown == false then
        SetAuraCount(r, nil, m.stackTextSource or "mirror-text", false)
    else
        local stackText = m.stackText
        if stackText ~= nil or IsSecretCountValue(stackText) then
            SetAuraCount(r, stackText, m.stackTextSource or "mirror-text", true)
        end
    end
    if not r.count.shown then
        local gotApps, apps = GetAuraApplications(r.auraUnit, r.auraInstanceID)
        if gotApps then
            SetAuraCount(r, apps, "display-count", true)
        end
    end
    SetResolvedAuraSpellID(r, nil, tryID)
    return true
end

local function ResolveAuraTryAuraEntry(tryID)
    if not tryID then return false end
    local m, hostCat = ResolveAuraLookupAuraState(tryID)
    -- m.isActive without m.durObj is a valid mirror state: VerifyStateFreshness
    -- promotes permanent auras (stances, forms, durationless buffs) to
    -- isActive=true with durObj=nil after GetAuraDataByAuraInstanceID confirms
    -- presence on the unit. ApplyAuraStateToIcon treats active+durObj=nil as
    -- "show without countdown swipe."
    return ResolveAuraApplyMirrorState(m, hostCat, tryID, "phase0-aura")
end

local function ResolveAuraAddMirrorID(id)
    if not IsUsableTableKey(id) or _scratchSeenMirrorIDs[id] then return end
    local s = _resolveAuraScratch
    _scratchSeenMirrorIDs[id] = true
    if not s.mirrorRestrictedAuraIDs then
        s.mirrorRestrictedAuraIDs = _scratchMirrorRestrictedAuraIDs
        s.mirrorRestrictedAuraIDSet = _scratchMirrorRestrictedAuraIDSet
    end
    s.mirrorRestrictedAuraIDSet[id] = true
    s.mirrorRestrictedAuraIDs[#s.mirrorRestrictedAuraIDs + 1] = id
end

local function ResolveAuraRememberActiveCooldownChildExactAuraIDs(state)
    if not state or DecodePotentialSecretBoolean(state.childIsActive) ~= true then return end
    local s = _resolveAuraScratch
    ResolveAuraAddMirrorID(state.overrideTooltipSpellID)
    ResolveAuraAddMirrorID(state.overrideSpellID)
    ResolveAuraAddMirrorID(state.spellID)
    ResolveAuraAddMirrorID(s.spellID)
    ResolveAuraAddMirrorID(s.entrySpellID)
    ResolveAuraAddMirrorID(s.entryID)
    if s.mirrorRestrictedAuraIDs and #s.mirrorRestrictedAuraIDs > 0 then
        s.mirrorRestrictsAuraFallbacks = true
        s.mirrorRestrictedAuraRequiresExactSpellID = true
        s.mirrorRestrictedAuraAllowsCapturedName = true
    end
end

-- Category B (Phase 0 cooldown branch): cooldown info lookup, linked / sibling
-- aura helpers.
local function ResolveAuraLookupCooldownInfo(tryID)
    if not tryID then return nil end
    local s = _resolveAuraScratch
    local mirror = s.mirror
    if not mirror then return nil end
    local viewerCat = s.viewerCat
    if s.isBuiltinCooldownCat and mirror.GetCooldownInfoForViewer then
        if viewerCat == "essential" then
            return mirror.GetCooldownInfoForViewer(tryID, "essential")
                or mirror.GetCooldownInfoForViewer(tryID, "utility")
        end
        return mirror.GetCooldownInfoForViewer(tryID, "utility")
            or mirror.GetCooldownInfoForViewer(tryID, "essential")
    end
    if mirror.FindCooldownInfo then
        return mirror.FindCooldownInfo(tryID)
    end
    return nil
end

local function ResolveAuraTryParentLinkedAura(tryID)
    if not tryID then return false end
    local s = _resolveAuraScratch
    local info = ResolveAuraLookupCooldownInfo(tryID)
    ResolveAuraRememberCooldownInfoLinkedAuraIDs(info)
    -- Validated linkedSpellIDs: the parent cooldown's hasAura flag is NOT a
    -- prerequisite (and may be secret in combat). The junk filter is the
    -- per-link validation below -- a linked ID only counts when it resolves to
    -- a real aura-viewer mirror child carrying live aura state, so an unrelated
    -- entry in linkedSpellIDs (which has no backing aura child) is ignored.
    if not info or type(info.linkedSpellIDs) ~= "table" then return false end
    local mirror = s.mirror
    if not mirror.GetMirroredStateForViewer then return false end
    local getAuraState = mirror.GetDirectMirroredStateForViewer
        or mirror.GetMirroredStateForViewer
    local r = _auraResult
    -- Linked aura lookup: probe both aura categories without ranking on the
    -- parent cooldown's selfAura. The linked aura cdID's OWN info.selfAura
    -- tells us where the aura sits at runtime. Packed state signals activity
    -- via auraInstanceID + auraDurObj (PackState), not the removed
    -- isActive/durObj -- and that presence IS the junk-link filter.
    for _, linkedID in ipairs(info.linkedSpellIDs) do
        local lm, hostCat
        for _, cat in ipairs(_AURA_VIEWER_CAT_BUFF_FIRST) do
            local probe = getAuraState(linkedID, cat)
            if probe and probe.auraInstanceID and probe.auraDurObj then
                lm, hostCat = probe, cat
                break
            end
        end
        if lm then
            AuraStateDebug(s.debugAura, "phase0-cd-linked-aura",
                "spellID=", tryID, "linkedID=", linkedID,
                "hostCat=", hostCat,
                "linkedSelfAura=", tostring(lm.selfAura),
                "cdID=", lm.cooldownID, "epoch=", lm.mirrorEpoch)
            r.isActive = true
            r.durObj = lm.auraDurObj
            r.auraInstanceID = lm.auraInstanceID
            r.auraUnit = lm.auraUnit
                or ((lm.selfAura == false) and "target" or "player")
            SetResolvedAuraSpellID(r, nil, linkedID)
            return true
        end
    end
    return false
end

local function ResolveAuraAddProbeID(id)
    if not IsUsableTableKey(id) or _scratchProbeSeen[id] then return end
    _scratchProbeSeen[id] = true
    _scratchProbeIDs[#_scratchProbeIDs + 1] = id
end

local function ResolveAuraAddInfoProbeIDs(info)
    if not info then return end
    ResolveAuraAddProbeID(info.overrideTooltipSpellID)
    ResolveAuraAddProbeID(info.overrideSpellID)
    ResolveAuraAddProbeID(info.spellID)
end

local function ResolveAuraTrySiblingMirror()
    local s = _resolveAuraScratch
    local mirror = s.mirror
    if not mirror or not mirror.GetMirroredStateForViewer then return false end
    local getAuraState = mirror.GetDirectMirroredStateForViewer
        or mirror.GetMirroredStateForViewer
    wipe(_scratchProbeIDs)
    wipe(_scratchProbeSeen)
    ResolveAuraAddProbeID(s.spellID)
    ResolveAuraAddProbeID(s.entrySpellID)
    ResolveAuraAddProbeID(s.entryID)
    ResolveAuraAddInfoProbeIDs(ResolveAuraLookupCooldownInfo(s.spellID))
    ResolveAuraAddInfoProbeIDs(ResolveAuraLookupCooldownInfo(s.entrySpellID))
    ResolveAuraAddInfoProbeIDs(ResolveAuraLookupCooldownInfo(s.entryID))

    local r = _auraResult
    for _, tryID in ipairs(_scratchProbeIDs) do
        for _, cat in ipairs(_AURA_VIEWER_CAT_BUFF_FIRST) do
            local lm = getAuraState(tryID, cat)
            -- Phase 1 removed the flat isActive / durObj fields from mirror
            -- state. Aura activity is now signalled by the presence of
            -- auraInstanceID + auraDurObj on the packed state; if both are
            -- present, an event-driven capture (UNIT_AURA / SCFDO aura
            -- branch / aura-related-child) stamped them and the aura is on
            -- the unit. Without this update the cooldown-side sibling
            -- lookup is orphaned for every CD+aura entry (DK Anti-Magic
            -- Shell, etc.) — the cooldown icon never receives the aura
            -- overlay because lm.isActive / lm.durObj are perpetually nil
            -- on the new state shape.
            if lm and lm.auraInstanceID and lm.auraDurObj then
                local resolvedID = lm.overrideTooltipSpellID
                    or lm.overrideSpellID
                    or tryID
                    or lm.spellID
                AuraStateDebug(s.debugAura, "phase0-cd-sibling-aura",
                    "spellID=", tryID,
                    "hostCat=", cat,
                    "linkedSelfAura=", tostring(lm.selfAura),
                    "cdID=", lm.cooldownID,
                    "epoch=", lm.mirrorEpoch,
                    "resolvedID=", resolvedID)
                r.isActive = true
                r.durObj = lm.auraDurObj
                r.auraUnit = lm.auraUnit
                    or ((lm.selfAura == false) and "target" or "player")
                SetResolvedAuraSpellID(r, nil, resolvedID)
                return true
            end
        end
    end
    return false
end

-- Category C: Phase 3 candidate building.
local _abilityToAuraSpellID
local _auraIDsForSpell
local ResolveAuraDisplaySpellID

local function ResolveAuraAppendID(id)
    if not IsUsableTableKey(id) or _scratchCandidateSeen[id] then return end
    _scratchCandidateSeen[id] = true
    _scratchCandidateIDs[#_scratchCandidateIDs + 1] = id
end

local function ResolveAuraAppendCooldownAuraIDFor(id)
    if not (Sources and Sources.QueryCooldownAuraBySpellID) then return end
    if not IsUsableTableKey(id) then return end
    local passiveAuraID = Sources.QueryCooldownAuraBySpellID(id)
    if IsUsableTableKey(passiveAuraID) then
        _resolveAuraScratch.hasCooldownAuraID = true
        ResolveAuraAppendID(passiveAuraID)
    end
end

local function ResolveAuraAppendMappedAuraIDs(id)
    if not IsUsableTableKey(id) then return end
    local auraIDs
    if CDMSpellData.GetAuraIDsForSpell then
        auraIDs = CDMSpellData:GetAuraIDsForSpell(id)
    elseif _auraIDsForSpell then
        auraIDs = _auraIDsForSpell[id]
    end
    if not auraIDs then return end
    for _, aid in ipairs(auraIDs) do
        ResolveAuraAppendID(aid)
    end
end

-- Captured-aura attempt. Returns (didMatch, newAuraInstID, newAuraUnit);
-- caller updates outer isActive/childAuraInstID/auraUnit on hit and
-- r.* fields are written here.
local function CapturedAuraNameMatchesEntry(captured)
    local s = _resolveAuraScratch
    local entryName = s.entryName
    local capturedName = captured and captured.name
    if issecretvalue and (issecretvalue(entryName) or issecretvalue(capturedName)) then
        return false
    end
    if type(entryName) ~= "string" or entryName == "" then return false end
    if type(capturedName) ~= "string" or capturedName == "" then return false end
    return capturedName:lower() == entryName:lower()
end

local function ResolveAuraTryCaptured(preferredUnits, allowGlobalFallback, phaseName)
    local s = _resolveAuraScratch
    local capturedName =
        (s.mirrorRestrictsAuraFallbacks and not s.mirrorRestrictedAuraAllowsCapturedName)
        and nil or s.entryName
    local captured = GetCapturedAuraForLookup(_scratchCandidateIDs, capturedName,
        preferredUnits, allowGlobalFallback)
    if not (captured and captured.auraInstanceID) then
        return false
    end
    if s.mirrorRestrictsAuraFallbacks
       and (not captured.spellID or not s.mirrorRestrictedAuraIDSet[captured.spellID]) then
        local capturedUnit = captured.unit or "player"
        local capturedData = QueryAuraData(capturedUnit, captured.auraInstanceID)
        if s.mirrorRestrictedAuraRequiresExactSpellID then
            local capturedSpellID = captured.spellID or GetCleanAuraSpellID(capturedData)
            if capturedSpellID and s.mirrorRestrictedAuraIDSet[capturedSpellID] then
                captured.spellID = capturedSpellID
                if s.debugAura then
                    AuraStateDebug(s.debugAura, phaseName .. "-accept-strict",
                        "capturedSpellID=", capturedSpellID,
                        "allowed=", FormatIDList(s.mirrorRestrictedAuraIDs))
                end
            elseif s.mirrorRestrictedAuraAllowsCapturedName
                and CapturedAuraNameMatchesEntry(captured) then
                if s.debugAura then
                    AuraStateDebug(s.debugAura, phaseName .. "-accept-name",
                        "capturedSpellID=", capturedSpellID,
                        "allowed=", FormatIDList(s.mirrorRestrictedAuraIDs))
                end
            else
                if s.debugAura then
                    AuraStateDebug(s.debugAura, phaseName .. "-reject-strict",
                        "capturedSpellID=", capturedSpellID,
                        "allowed=", FormatIDList(s.mirrorRestrictedAuraIDs))
                end
                return false
            end
        else
            local capturedIcon = GetCleanAuraIcon(capturedData)
            if not (s.entryTexture and capturedIcon and capturedIcon == s.entryTexture) then
                if s.debugAura then
                    AuraStateDebug(s.debugAura, phaseName .. "-reject",
                        "capturedSpellID=", captured.spellID,
                        "allowed=", FormatIDList(s.mirrorRestrictedAuraIDs),
                        "capturedIcon=", capturedIcon,
                        "entryIcon=", s.entryTexture)
                end
                return false
            end
            if s.debugAura then
                AuraStateDebug(s.debugAura, phaseName .. "-accept-icon",
                    "capturedSpellID=", captured.spellID,
                    "allowed=", FormatIDList(s.mirrorRestrictedAuraIDs),
                    "icon=", capturedIcon)
            end
        end
    end

    -- Validate through auraInstanceID-only DurationObject APIs.
    -- Spell/name/AuraData lookup APIs can be restricted in combat, while
    -- GetAuraDuration accepts the instance ID from UNIT_AURA.
    local capturedUnit = captured.unit or "player"
    local r = _auraResult
    local alive, durObj = ResolveAuraInstanceDurationState(r,
        capturedUnit, captured.auraInstanceID, nil)
    if alive then
        AuraStateDebug(s.debugAura, phaseName,
            "spellID=", captured.spellID,
            "inst=", captured.auraInstanceID,
            "unit=", capturedUnit)
        r.durObj = durObj
        SetResolvedAuraSpellID(r, nil, captured.spellID)
        return true, captured.auraInstanceID, capturedUnit
    end

    -- Lazy eviction: aura is gone. We hold the entry reference, so clear by
    -- Lua identity (works regardless of whether instID is secret).
    ReleaseCapturedEntry(captured)
    return false
end

local function ResolveAuraRuntimeStateImpl(params)
    WipeAuraResult()
    WipeResolveAuraScratch()
    local r = _auraResult
    local s = _resolveAuraScratch

    local spellID = params.spellID
    if not spellID then return r end

    local entrySpellID = params.entrySpellID
    local entryID = params.entryID
    local entryName = params.entryName
    local entryKind = params.entryKind
    local entryIsAura = params.entryIsAura == true or entryKind == "aura"
    local entryTexture = params.entryTexture
    local viewerType = params.viewerType
    local blizzardMirrorCooldownID = params.blizzardMirrorCooldownID
    local blizzardMirrorCategory = params.blizzardMirrorCategory
    local debugAura = ShouldDebugAuraState(entryName, spellID, entryID)
    local isBuiltinAuraViewer = IsBuiltinAuraContainerKey(viewerType)

    -- Publish call inputs to the scratch struct so file-scope helpers can
    -- read them without upvalue capture. See the scratch declaration above
    -- ResolveAuraRememberCooldownLinkedAuraID for the migration rationale.
    s.spellID = spellID
    s.entrySpellID = entrySpellID
    s.entryID = entryID
    s.entryName = entryName
    s.entryIsAura = entryIsAura
    s.entryTexture = entryTexture
    s.viewerType = viewerType
    s.blizzardMirrorCooldownID = blizzardMirrorCooldownID
    s.blizzardMirrorCategory = blizzardMirrorCategory
    s.debugAura = debugAura
    s.isBuiltinAuraViewer = isBuiltinAuraViewer

    AuraStateDebug(debugAura,
        "begin",
        "name=", entryName or "?",
        "spellID=", spellID,
        "entrySpellID=", entrySpellID,
        "entryID=", entryID,
        "viewerType=", viewerType)

    -- Cross-phase mirrorRestricted* / cooldownLinked* fields live on the
    -- scratch struct (s.X). Helpers ResolveAuraRememberCooldownLinkedAuraID,
    -- ResolveAuraRememberCooldownLinkedAuraMode, etc. read/write them via s.

    -----------------------------------------------------------------------
    -- Phase 0: Blizzard child mirror — driven by entry.viewerType when it
    -- maps to a Blizzard category, with custom-bar fallbacks.
    --
    -- Per the CooldownViewer documentation, every Blizzard-known cooldown
    -- maps to exactly one cooldownID inside one viewer category (essential,
    -- utility, buff, trackedBar). The child for that cooldownID owns the
    -- live durObj, isActive, and CooldownViewerCooldown info (hasAura,
    -- selfAura, linkedSpellIDs).
    --
    -- Built-in QUI containers carry a viewerType matching the Blizzard
    -- category, so we look up that viewer first, then the sibling viewer in
    -- the same backing pool. Custom QUI bars carry a
    -- QUI-side identifier — for those we probe categories in priority
    -- order:
    --   * Aura entry on a custom bar → buff first, then trackedBar.
    --     built-in BuffIcon/BuffBar entries may use either aura viewer.
    --   * Cooldown entry on a custom bar → essential first, then utility;
    --     built-in essential/utility entries may use either cooldown viewer;
    --     aura state is accepted only from direct BuffIcon/BuffBar children.
    --
    -- Gated on entry.type. Only spell-like entries can resolve to a
    -- Blizzard CDM child — item/trinket/slot/totem live in different
    -- subsystems (inventory cooldowns, totem slots) and must not consult
    -- the mirror, since their entry.id is an itemID / slotID and would
    -- only ever produce spurious matches against unrelated spellIDs.
    -- Macro entries get their resolved spellID/itemID from upstream
    -- before the runtime aura resolver runs, so they skip Phase 0 too — the macro
    -- target's Phase 0 lookup happens via its concrete entry shape.
    -----------------------------------------------------------------------
    local entryType = params.entryType
    local mirrorEligibleType = entryType == nil
        or entryType == "spell"
        or entryType == "aura"
    do
        local mirror = mirrorEligibleType and ns.CDMBlizzMirror or nil
        if mirror then
            local viewerCat = viewerType
            local isBuiltinAuraCat     = IsAuraMirrorCategory(viewerCat)
            local isBuiltinCooldownCat = IsCooldownMirrorCategory(viewerCat)

            -- Publish derived Phase-0 state for the file-scope helpers
            -- (ResolveAuraTryAuraEntry, ResolveAuraTryParentLinkedAura, etc.).
            s.mirror = mirror
            s.viewerCat = viewerCat
            s.isBuiltinAuraCat = isBuiltinAuraCat
            s.isBuiltinCooldownCat = isBuiltinCooldownCat

            -- AURA-KIND ENTRY -------------------------------------------------
            -- Built-in aura container: use the BuffIcon/BuffBar backing pool,
            -- preferring the entry's own viewer first.
            -- Custom bar (or unknown viewerType): probe both aura viewers.
            if entryIsAura then
                if blizzardMirrorCooldownID and mirror.GetStateByCooldownID then
                    local backedState = mirror.GetStateByCooldownID(
                        blizzardMirrorCooldownID,
                        blizzardMirrorCategory)
                    local backedCat = backedState and backedState.viewerCategory
                    if IsAuraMirrorCategory(backedCat) then
                        local backedID = backedState.overrideTooltipSpellID
                        local linkedIDs = backedState.linkedSpellIDs
                        if not IsUsableTableKey(backedID) and type(linkedIDs) == "table" then
                            for _, linkedID in ipairs(linkedIDs) do
                                if IsUsableTableKey(linkedID) then
                                    backedID = linkedID
                                    break
                                end
                            end
                        end
                        ResolveAuraRememberMirrorMatch(backedState, backedCat, backedID or spellID)
                        if debugAura then
                            AuraStateDebug(debugAura, "phase0-mirror-child",
                                "cdID=", blizzardMirrorCooldownID,
                                "state=", FormatAuraMirrorState(backedState))
                        end
                    end
                end
                if ResolveAuraTryAuraEntry(spellID)
                   or ResolveAuraTryAuraEntry(entrySpellID)
                   or ResolveAuraTryAuraEntry(entryID) then
                    return r
                end
                if s.auraMirrorMatched then
                    -- ResolveAuraAddMirrorID lazy-aliases s.mirrorRestrictedAuraIDs/
                    -- AuraIDSet to the pooled scratch tables on first valid add,
                    -- so callers below can keep using "if s.X then" as a "any
                    -- restriction recorded?" check.
                    local matchedState = s.auraMirrorMatchedState
                    ResolveAuraAddMirrorID(matchedState and matchedState.overrideTooltipSpellID)
                    local linkedIDs = matchedState and matchedState.linkedSpellIDs
                    if type(linkedIDs) == "table" then
                        for _, linkedID in ipairs(linkedIDs) do
                            ResolveAuraAddMirrorID(linkedID)
                        end
                    end
                    ResolveAuraAddMirrorID(matchedState and matchedState.overrideSpellID)
                    ResolveAuraAddMirrorID(matchedState and matchedState.spellID)
                    ResolveAuraAddMirrorID(s.auraMirrorMatchedID)
                    s.mirrorRestrictsAuraFallbacks =
                        (s.mirrorRestrictedAuraIDs and #s.mirrorRestrictedAuraIDs > 0) or false
                    if not s.mirrorRestrictsAuraFallbacks then
                        s.mirrorRestrictedAuraIDs = nil
                        s.mirrorRestrictedAuraIDSet = nil
                        s.mirrorRestrictedAuraUnit = nil
                    elseif matchedState and ResolveMirrorAuraUnit(matchedState) == "target" then
                        s.mirrorRestrictedAuraUnit = "target"
                    end
                    if debugAura then
                        AuraStateDebug(debugAura, "phase0-aura-mirror-inactive",
                            "tryID=", s.auraMirrorMatchedID,
                            "hostCat=", s.auraMirrorMatchedCat,
                            "state=", FormatAuraMirrorState(matchedState),
                            "restrictIDs=", FormatIDList(s.mirrorRestrictedAuraIDs))
                    end
                end
            end

            -- COOLDOWN-KIND ENTRY WITH AURA OVERLAY ---------------------------
            -- Built-in cooldown container: use the essential/utility backing
            --   pool, preferring the entry's own viewer first.
            -- Custom bar / unknown: FindCooldownInfo (essential->utility).
            -- If info.hasAura, only accept linked aura state when that
            -- linked ID resolves to a direct BuffIcon/BuffBar child.
            if not entryIsAura then
                if blizzardMirrorCooldownID and mirror.GetStateByCooldownID then
                    local backedState = mirror.GetStateByCooldownID(
                        blizzardMirrorCooldownID,
                        blizzardMirrorCategory)
                    local backedCat = backedState and backedState.viewerCategory
                    if IsCooldownMirrorCategory(backedCat) then
                        ResolveAuraRememberCooldownInfoLinkedAuraIDs(backedState)
                        ResolveAuraRememberCooldownLinkedAuraMode(backedState)
                        if DecodePotentialSecretBoolean(backedState.hasAura) == false then
                            ResolveAuraRememberActiveCooldownChildExactAuraIDs(backedState)
                        end
                        if debugAura then
                            AuraStateDebug(debugAura, "phase0-cd-backed-child",
                                "cdID=", blizzardMirrorCooldownID,
                                "state=", FormatAuraMirrorState(backedState),
                                "fromAura=", tostring(backedState.wasSetFromAura),
                                "fromCooldown=", tostring(backedState.wasSetFromCooldown),
                                "fromCharges=", tostring(backedState.wasSetFromCharges))
                        end
                    end
                end
                if ResolveAuraTryParentLinkedAura(spellID)
                   or ResolveAuraTryParentLinkedAura(entrySpellID)
                   or ResolveAuraTryParentLinkedAura(entryID)
                   or ResolveAuraTrySiblingMirror() then
                    return r
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 1: Resolve aura spell ID
    -----------------------------------------------------------------------
    local auraSpellID = spellID
    if ResolveAuraDisplaySpellID then
        local mappedAuraID, remapped = ResolveAuraDisplaySpellID(auraSpellID)
        if remapped == true then
            auraSpellID = mappedAuraID
        end
    end

    -----------------------------------------------------------------------
    -- Phase 2: Slot-driven totem resolution + direct aura query
    -- Blizzard CDM viewer children are no longer consulted. Totem-instance
    -- callers pass params.totemSlot directly; everything else queries the
    -- aura via C_UnitAuras.GetUnitAuraBySpellID when available.
    -----------------------------------------------------------------------
    local explicitTotemSlot = params.totemSlot
    local disableLooseVisibilityFallback = params.disableLooseVisibilityFallback

    if explicitTotemSlot then
        local virtualState = ResolveVirtualAuraState(explicitTotemSlot)
        if virtualState.slot then
            r.totemSlot = virtualState.slot
            r.totemName = virtualState.totemName
            r.totemIcon = virtualState.totemIcon
            r.isTotemInstance = true
            if virtualState.isActive then
                r.isActive = true
                r.auraUnit = virtualState.auraUnit or "player"
                r.durObj = virtualState.durObj
                return r
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 3: Build candidate aura IDs.
    -----------------------------------------------------------------------
    local isActive = false
    local childAuraInstID = nil
    local childAuraSource = nil
    local auraUnit = "player"
    local directAuraActiveUnit = nil
    local directAuraActivePhase = nil
    -- candidateIDs / seenIDs / hasCooldownAuraID used to be function-local with
    -- per-call append/appendCooldownAuraIDFor/appendMappedAuraIDs closures.
    -- They now live in the pooled scratch (_scratchCandidateIDs +
    -- _scratchCandidateSeen) and on s.hasCooldownAuraID, written by file-scope
    -- helpers ResolveAuraAppendID / ResolveAuraAppendCooldownAuraIDFor /
    -- ResolveAuraAppendMappedAuraIDs.

    -- Build the candidate aura ID list. For cooldown entries, prefer
    -- Blizzard's action-button association first: GetCooldownAuraBySpellID
    -- returns the passive aura spellID Blizzard expects callers to feed to
    -- GetPlayerAuraBySpellID. Aura entries already resolve to their aura ID
    -- at build time, so their direct/catalog IDs remain authoritative.
    if not entryIsAura
       and not s.mirrorRestrictsAuraFallbacks
       and s.cooldownLinkedAuraIDs
       and ResolveAuraCooldownLinkedAuraFallbackAllowed()
       and #s.cooldownLinkedAuraIDs > 0 then
        s.mirrorRestrictedAuraIDs = s.cooldownLinkedAuraIDs
        s.mirrorRestrictedAuraIDSet = s.cooldownLinkedAuraIDSet
        s.mirrorRestrictsAuraFallbacks = true
        s.mirrorRestrictedAuraRequiresExactSpellID = true
        if debugAura then
            AuraStateDebug(debugAura, "phase0-cd-linked-aura-inactive",
                "restrictIDs=", FormatIDList(s.mirrorRestrictedAuraIDs),
                "modeKnown=", tostring(s.cooldownLinkedAuraModeKnown),
                "modeAura=", tostring(s.cooldownLinkedAuraModeAllowsAura))
        end
    end
    if s.mirrorRestrictedAuraIDs then
        for _, id in ipairs(s.mirrorRestrictedAuraIDs) do
            ResolveAuraAppendID(id)
        end
    elseif entryIsAura and isBuiltinAuraViewer then
        -- Built-in BuffIcon/BuffBar entries represent one configured aura
        -- slot. Do not let catalog siblings keep this slot active after
        -- the configured aura falls off; sibling auras have their own slots.
        ResolveAuraAppendID(auraSpellID)
        ResolveAuraAppendID(entrySpellID)
    else
        if not entryIsAura then
            ResolveAuraAppendCooldownAuraIDFor(auraSpellID)
            ResolveAuraAppendCooldownAuraIDFor(entrySpellID)
            ResolveAuraAppendCooldownAuraIDFor(entryID)
        end
        ResolveAuraAppendID(auraSpellID)
        ResolveAuraAppendID(entrySpellID)
        ResolveAuraAppendID(entryID)
        if entryIsAura or not s.hasCooldownAuraID then
            ResolveAuraAppendMappedAuraIDs(auraSpellID)
            ResolveAuraAppendMappedAuraIDs(entrySpellID)
            ResolveAuraAppendMappedAuraIDs(entryID)
        end
        if entryIsAura then
            ResolveAuraAppendCooldownAuraIDFor(auraSpellID)
            ResolveAuraAppendCooldownAuraIDFor(entrySpellID)
            ResolveAuraAppendCooldownAuraIDFor(entryID)
        end
    end

    -----------------------------------------------------------------------
    -- Cooldown-entry short-circuit. The mirror match was attempted in
    -- Phase 0 (above) using the entry's explicit viewerType; if it didn't
    -- find an active aura there, continue only when that cooldown has
    -- explicit linked aura IDs from its Blizzard info. Otherwise skip the
    -- API fallback chain — those phases match against a candidate ID list
    -- polluted by GetCooldownAuraBySpellID, which can resolve to unrelated
    -- spells (Outbreak -> "Skyfury"). Aura-kind entries continue through
    -- the API fallback chain for legacy aura tracking that lives outside
    -- any Blizzard CDM viewer.
    -----------------------------------------------------------------------
    if not entryIsAura and not s.mirrorRestrictsAuraFallbacks then
        AuraStateDebug(debugAura, "cooldown-no-mirror", "skip-api-fallbacks")
        return r
    end

    -----------------------------------------------------------------------
    -- Phase 3.1: Combat player/pet aura data from UNIT_AURA.
    -- During combat, the captured player AuraData payload is the most
    -- reliable source of the auraInstanceID. Direct spell/name query APIs
    -- remain below as fallbacks when the capture cache misses.
    -----------------------------------------------------------------------
    if InCombatLockdown() then
        local matched, newInstID, newUnit = ResolveAuraTryCaptured(
            SELF_AURA_CAPTURE_LOOKUP_UNITS, false,
            "phase3.1-event-self-captured")
        if matched then
            isActive = true
            childAuraInstID = newInstID
            auraUnit = newUnit
        end
    end

    -----------------------------------------------------------------------
    -- Phase 3.2: Direct aura query via C_UnitAuras.GetUnitAuraBySpellID
    -- -> auraInstanceID -> GetAuraDuration. This covers out-of-combat
    -- lookups and combat fallback when no UNIT_AURA payload was captured.
    -- GetAuraDuration provides the C-side DurationObject for display.
    -----------------------------------------------------------------------
    if not isActive then
        for _, tryID in ipairs(_scratchCandidateIDs) do
            if childAuraInstID then break end
            if s.mirrorRestrictedAuraUnit ~= "target" then
                for unitIdx = 1, #STACK_SEARCH_UNITS do
                    if childAuraInstID then break end
                    local unitID = STACK_SEARCH_UNITS[unitIdx]
                    local ad = QueryUnitAuraBySpellID(unitID, tryID, "HELPFUL")
                    if ad then
                        local instID = GetCleanAuraInstanceID(ad)
                        if instID then
                            childAuraInstID = instID
                            auraUnit = unitID
                            r.auraData = not InCombatLockdown() and ad or nil
                            SetResolvedAuraSpellID(r, ad, tryID)
                        elseif IsSelfUnit(unitID) and not directAuraActiveUnit then
                            directAuraActiveUnit = unitID
                            directAuraActivePhase = "phase3.2-player-active-no-inst"
                            SetResolvedAuraSpellID(r, ad, tryID)
                        end
                    end
                end
            end
            if not childAuraInstID then
                local targetAura = FindOwnedTargetAuraBySpellID(tryID, "HARMFUL")
                local targetInstID = GetCleanAuraInstanceID(targetAura)
                if targetInstID then
                    childAuraInstID = targetInstID
                    auraUnit = "target"
                    r.auraData = not InCombatLockdown() and targetAura or nil
                    SetResolvedAuraSpellID(r, targetAura, tryID)
                end
            end
        end
    end

    if childAuraInstID then
        local alive, durObj = ResolveAuraInstanceDurationState(r, auraUnit, childAuraInstID, r.auraData)
        if alive or r.auraData then
            AuraStateDebug(debugAura, "phase3.2-duration", "unit=", auraUnit, "inst=", childAuraInstID)
            isActive = true
            r.durObj = durObj
        end
    end

    if not isActive
        and childAuraInstID
        and not InCombatLockdown()
        and Sources and Sources.QueryAuraDataByAuraInstanceID then
        local vdata = QueryAuraData(auraUnit, childAuraInstID)
        if IsUsableResolvedAuraData(auraUnit, vdata) then
            AuraStateDebug(debugAura, "phase3.2-inst", "unit=", auraUnit, "inst=", childAuraInstID)
            isActive = true
            r.auraData = vdata
            SetResolvedAuraSpellID(r, vdata, nil)
            local _, durObj = ResolveAuraInstanceDurationState(r, auraUnit, childAuraInstID, vdata)
            r.durObj = durObj
        end
    end

    -----------------------------------------------------------------------
    -- Phase 3.4: Event-payload captured auraInstanceID fallback
    -- Direct spell/name query APIs can be restricted during combat. If
    -- Phase 3.1 did not catch a self aura and Phase 3.2 did not resolve
    -- anything, use the captured UNIT_AURA index across player/pet.
    -- Target auras are owned by the Blizzard CDM mirror (Phase 3.0).
    -----------------------------------------------------------------------
    if not isActive and s.mirrorRestrictedAuraUnit ~= "target" then
        local matched, newInstID, newUnit = ResolveAuraTryCaptured(
            AURA_CAPTURE_LOOKUP_UNITS, nil,
            "phase3.4-event-captured")
        if matched then
            isActive = true
            childAuraInstID = newInstID
            auraUnit = newUnit
        end
    end

    if not isActive and directAuraActiveUnit then
        AuraStateDebug(debugAura, directAuraActivePhase or "phase3.2-active-no-inst",
            "unit=", directAuraActiveUnit)
        isActive = true
        auraUnit = directAuraActiveUnit
    end

    -----------------------------------------------------------------------
    -- Phase 3.5: Cooldown viewer passive aura spellID
    -- GetCooldownAuraBySpellID returns the associated passive/aura spellID,
    -- not AuraData. Resolve that spellID through the same unit aura lookup
    -- wrapper, then feed its auraInstanceID into the DurationObject path.
    -----------------------------------------------------------------------
    if not isActive
        and not s.mirrorRestrictsAuraFallbacks
        and Sources
        and Sources.QueryCooldownAuraBySpellID then
        for tryIdx = 1, 3 do
            if isActive then break end
            local tryID = tryIdx == 1 and auraSpellID
                or tryIdx == 2 and entrySpellID or entryID
            if tryID then
                local passiveAuraID = Sources.QueryCooldownAuraBySpellID(tryID)
                if IsUsableTableKey(passiveAuraID) then
                    for unitIdx = 1, #STACK_SEARCH_UNITS do
                        if isActive then break end
                        local unitID = STACK_SEARCH_UNITS[unitIdx]
                        local ad = QueryUnitAuraBySpellID(unitID, passiveAuraID, "HELPFUL")
                        local instID = GetCleanAuraInstanceID(ad)
                        if instID then
                            AuraStateDebug(debugAura, "phase3.5-cooldown-aura",
                                "tryID=", tryID, "auraID=", passiveAuraID,
                                "inst=", instID, "unit=", unitID)
                            isActive = true
                            childAuraInstID = instID
                            auraUnit = unitID
                            r.auraData = not InCombatLockdown() and ad or nil
                            SetResolvedAuraSpellID(r, ad, passiveAuraID)
                        elseif ad and IsSelfUnit(unitID) then
                            AuraStateDebug(debugAura, "phase3.5-cooldown-aura-active-no-inst",
                                "tryID=", tryID, "auraID=", passiveAuraID, "unit=", unitID)
                            isActive = true
                            auraUnit = unitID
                            SetResolvedAuraSpellID(r, ad, passiveAuraID)
                        end
                    end
                    if not isActive then
                        local targetAura = FindOwnedTargetAuraBySpellID(passiveAuraID, "HARMFUL")
                        local targetInstID = GetCleanAuraInstanceID(targetAura)
                        if targetInstID then
                            AuraStateDebug(debugAura, "phase3.5-target-cooldown-aura",
                                "tryID=", tryID, "auraID=", passiveAuraID,
                                "inst=", targetInstID)
                            isActive = true
                            childAuraInstID = targetInstID
                            auraUnit = "target"
                            r.auraData = not InCombatLockdown() and targetAura or nil
                            SetResolvedAuraSpellID(r, targetAura, passiveAuraID)
                        end
                    end
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- Phase 4: API fallbacks (unified OOC/combat)
    -- Spell-ID lookup prefers GetUnitAuraBySpellID. Name lookup remains a
    -- fallback for older/mismatched entries and is guarded by pcall.
    -- In combat, isHelpful may be secret — allow when not false.
    -----------------------------------------------------------------------
    -- 1. Player aura by spell ID (helpful only)
    -- GetPlayerAuraBySpellID returns ANY aura on the player with that spellID
    -- regardless of caster. Drop the strict ownership check for player-unit
    -- queries: the aura is by definition on the player. In combat, ad fields
    -- like sourceUnit / isFromPlayerOrPlayerPet may be restricted, so
    -- player-unit queries go straight to the auraInstanceID DurationObject
    -- path.
    if not isActive and s.mirrorRestrictedAuraUnit ~= "target" then
        for _, tryID in ipairs(_scratchCandidateIDs) do
            if isActive then break end
            if tryID then
                local ad = QueryUnitAuraBySpellID("player", tryID, "HELPFUL")
                local instID = GetCleanAuraInstanceID(ad)
                if instID then
                    AuraStateDebug(debugAura, "phase4-player-id", "tryID=", tryID, "inst=", instID)
                    isActive = true
                    childAuraInstID = instID
                    auraUnit = "player"
                    r.auraData = not InCombatLockdown() and ad or nil
                    SetResolvedAuraSpellID(r, ad, tryID)
                elseif ad then
                    AuraStateDebug(debugAura, "phase4-player-id-active-no-inst", "tryID=", tryID)
                    isActive = true
                    auraUnit = "player"
                    SetResolvedAuraSpellID(r, ad, tryID)
                end
            end
        end
    end
    -- 2. Player buff by name. Same reasoning as 4.1: trust the player-unit
    -- query, drop the strict ownership check whose secret-field gates fail
    -- in combat.
    if not isActive
        and s.mirrorRestrictedAuraUnit ~= "target"
        and not s.mirrorRestrictsAuraFallbacks
        and entryName and entryName ~= ""
        and Sources and Sources.QueryAuraDataBySpellName then
        local ad = Sources.QueryAuraDataBySpellName("player", entryName, "HELPFUL")
        -- Same reasoning as Phase 4.1: trust the player-unit query, drop
        -- the strict ownership check whose secret-field gates fail in combat.
        local instID = GetCleanAuraInstanceID(ad)
        if instID then
            AuraStateDebug(debugAura, "phase4-player-name", "inst=", instID)
            isActive = true
            childAuraInstID = instID
            auraUnit = "player"
            r.auraData = not InCombatLockdown() and ad or nil
            SetResolvedAuraSpellID(r, ad, nil)
        elseif ad then
            AuraStateDebug(debugAura, "phase4-player-name-active-no-inst")
            isActive = true
            auraUnit = "player"
            SetResolvedAuraSpellID(r, ad, nil)
        end
    end
    -- 3. Pet buff by name
    if not isActive
        and s.mirrorRestrictedAuraUnit ~= "target"
        and not s.mirrorRestrictsAuraFallbacks
        and entryName and entryName ~= ""
        and Sources and Sources.QueryAuraDataBySpellName then
        local ad = Sources.QueryAuraDataBySpellName("pet", entryName, "HELPFUL")
        local instID = GetCleanAuraInstanceID(ad)
        if instID and IsAuraOwnedByPlayerOrPet(ad, true) then
            AuraStateDebug(debugAura, "phase4-pet-name", "inst=", instID)
            isActive = true
            childAuraInstID = instID
            auraUnit = "pet"
            r.auraData = not InCombatLockdown() and ad or nil
            SetResolvedAuraSpellID(r, ad, nil)
        end
    end
    -- 4. Target debuff by name
    if not isActive
        and not s.mirrorRestrictsAuraFallbacks
        and entryName and entryName ~= ""
        and Sources and Sources.QueryAuraDataBySpellName then
        local ad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
        local instID = GetCleanAuraInstanceID(ad)
        if instID then
            AuraStateDebug(debugAura, "phase4-target-harmful", "inst=", instID)
            isActive = true
            childAuraInstID = instID
            auraUnit = "target"
            r.auraData = not InCombatLockdown() and ad or nil
            SetResolvedAuraSpellID(r, ad, nil)
        end
    end
    -- 5. Validate child auraInstanceID via GetAuraDataByAuraInstanceID
    if not isActive and childAuraInstID then
        if IsSelfUnit(auraUnit) then
            local alive, durObj = ResolveAuraInstanceDurationState(r, auraUnit, childAuraInstID, r.auraData)
            if alive then
                AuraStateDebug(debugAura, "phase5-validate-inst", "unit=", auraUnit, "inst=", childAuraInstID)
                isActive = true
                r.durObj = durObj
            end
        elseif not InCombatLockdown() and Sources and Sources.QueryAuraDataByAuraInstanceID then
            local vdata = QueryAuraData(auraUnit, childAuraInstID)
            if IsUsableResolvedAuraData(auraUnit, vdata) then
                AuraStateDebug(debugAura, "phase5-validate-inst", "unit=", auraUnit, "inst=", childAuraInstID)
                isActive = true
                r.auraData = vdata
                SetResolvedAuraSpellID(r, vdata, nil)
            end
        end
    end
    -- Viewer-child visibility fallbacks (formerly Phases 5b/6) and their
    -- companion phases 7 (dynamic child scan) and 8 (non-slot totem) were
    -- retired with the cdm_spelldata viewer-scanning strip. Phase 2's
    -- C_UnitAuras.GetUnitAuraBySpellID query covers the same lookup space.
    -- Totem state now flows only through the slot-driven Phase 2 path
    -- driven by callers that pass params.totemSlot explicitly.

    -----------------------------------------------------------------------
    -- Post-detection: name-based aura fallback
    -----------------------------------------------------------------------
    -- If active but no auraInstanceID, try name-based lookups.
    -- Reject foreign-source hits so we don't pull duration/stack info from
    -- a class-mate's aura on us.
    if isActive
        and not childAuraInstID
        and not s.mirrorRestrictsAuraFallbacks
        and entryName and entryName ~= "" then
        if Sources and Sources.QueryAuraDataBySpellName then
            local tad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
            local tadInstID = GetCleanAuraInstanceID(tad)
            if tadInstID then
                childAuraInstID = tadInstID
                auraUnit = "target"
                SetResolvedAuraSpellID(r, tad, nil)
            end
            if not childAuraInstID then
                local pad = Sources.QueryAuraDataBySpellName("player", entryName, "HELPFUL")
                local padInstID = GetCleanAuraInstanceID(pad)
                if padInstID and IsAuraOwnedByPlayerOrPet(pad, true) then
                    childAuraInstID = padInstID
                    auraUnit = "player"
                    SetResolvedAuraSpellID(r, pad, nil)
                end
            end
        end
        if not childAuraInstID then
            for _, tryID in ipairs(_scratchCandidateIDs) do
                if childAuraInstID then break end
                if tryID then
                    local ad = QueryUnitAuraBySpellID("player", tryID, "HELPFUL")
                    local instID = GetCleanAuraInstanceID(ad)
                    if instID then
                        childAuraInstID = instID
                        auraUnit = "player"
                        SetResolvedAuraSpellID(r, ad, tryID)
                    end
                end
            end
        end
    end

    -- Get DurationObject from auraInstanceID
    if isActive and childAuraInstID and not r.durObj then
        local durationAuraData = r.auraData
        if not durationAuraData
            and not InCombatLockdown()
            and Sources and Sources.QueryAuraDataByAuraInstanceID then
            local vdata = QueryAuraData(auraUnit, childAuraInstID)
            if IsUsableResolvedAuraData(auraUnit, vdata) then
                durationAuraData = vdata
                r.auraData = vdata
                SetResolvedAuraSpellID(r, vdata, nil)
            end
        end
        local hasExpiration = ApplyAuraExpirationState(r, auraUnit, childAuraInstID, durationAuraData)
        if hasExpiration ~= false then
            local durObj = QueryAuraDuration(auraUnit, childAuraInstID)
            if durObj then
                r.durObj = durObj
            elseif InCombatLockdown() and hasExpiration == nil then
                r.durationStateUnknown = true
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
        if not appsResolved
            and childAuraInstID
            and not InCombatLockdown()
            and IsSelfUnit(auraUnit)
            and r.auraData then
            local directApps = GetDisplayableAuraApplications(r.auraData)
            if IsUsableResolvedAuraData(auraUnit, r.auraData) and directApps ~= nil then
                apps = directApps
                stackSource = "resolved-data"
                appsResolved = true
            end
        end
        if not appsResolved
            and childAuraInstID
            and not InCombatLockdown()
            and IsSelfUnit(auraUnit)
            and Sources and Sources.QueryAuraDataByAuraInstanceID then
            local instData = QueryAuraData(auraUnit, childAuraInstID)
            local instApps = GetDisplayableAuraApplications(instData)
            if IsUsableResolvedAuraData(auraUnit, instData) and instApps ~= nil then
                apps = instApps
                stackSource = "instance-data"
                appsResolved = true
            end
        end
        if not appsResolved
            and not childAuraInstID
            and not s.mirrorRestrictsAuraFallbacks
            and entryName and entryName ~= ""
            and Sources and Sources.QueryAuraDataBySpellName then
            for i = 1, #STACK_SEARCH_UNITS do
                local stackUnit = STACK_SEARCH_UNITS[i]
                if not appsResolved then
                    local nad = Sources.QueryAuraDataBySpellName(stackUnit, entryName, "HELPFUL")
                    local nadApps = GetDisplayableAuraApplications(nad)
                    if nad and nadApps ~= nil and IsUsableResolvedAuraData(stackUnit, nad) then
                        apps = nadApps
                        stackSource = "name-" .. stackUnit
                        appsResolved = true
                    end
                end
            end
            if not appsResolved then
                local tad = FindOwnedTargetAuraByName(entryName, "HARMFUL")
                local tadInstID = GetRawAuraInstanceID(tad)
                local gotApps, tadApps = GetAuraApplications("target", tadInstID)
                if gotApps then
                    apps = tadApps
                    stackSource = "display-count"
                    appsResolved = true
                end
            end
        end
        SetAuraCount(r, apps, stackSource, appsResolved and apps ~= nil)
        if debugAura then
            local appsLog = IsSecretCountValue(apps) and "<secret>" or apps
            AuraStateDebug(debugAura, "count",
                "shown=", tostring(_auraCountResult.shown == true),
                "source=", stackSource or "nil",
                "value=", appsLog)
        end
    end

    r.isActive = isActive
    r.auraInstanceID = childAuraInstID
    r.auraUnit = auraUnit
    if isActive and not r.resolvedAuraSpellID then
        SetResolvedAuraSpellID(r, r.auraData, auraSpellID)
    end
    AuraStateDebug(debugAura, "end", "active=", isActive, "unit=", auraUnit,
        "inst=", childAuraInstID, "hasExp=", r.hasExpirationTime,
        "hideDur=", r.hideDurationText)
    return r
end

if ns.CDMAuraRuntime and ns.CDMAuraRuntime.SetResolver then
    ns.CDMAuraRuntime.SetResolver(ResolveAuraRuntimeStateImpl)
end

---------------------------------------------------------------------------
-- FORCE LOAD CDM: Ensure Blizzard_CooldownManager addon is loaded
-- TAINT SAFETY: Previous approach called the Blizzard CDM settings frame's
-- :Show() from addon code (via C_Timer.After). Despite the deferral,
-- C_Timer callbacks still run in addon (insecure) execution context.
-- Blizzard's OnShow handler populates module-level tables
-- (wasOnGCDLookup, etc.) which become permanently tainted. Later, when
-- the viewer refreshes from a protected context (e.g. cutscene exit →
-- SetAttribute → Show), those tables are forbidden → "attempted to index
-- a forbidden table".
-- Fix: just ensure the addon is loaded via C_AddOns.LoadAddOn and let
-- Blizzard initialize viewers naturally via events.
---------------------------------------------------------------------------
local function ForceLoadCDM()
    if InCombatLockdown() and not ns._inInitSafeWindow then return end
    -- Ensure the Blizzard addon is loaded (no-op if already loaded)
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_CooldownManager")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_CooldownManager")
    end
end

---------------------------------------------------------------------------
-- UPDATE CVar: keep Blizzard's hidden data source available.
---------------------------------------------------------------------------
local function UpdateCooldownViewerCVar()
    SyncCooldownViewerCVarToMasterToggle()
end

---------------------------------------------------------------------------
-- OWNED SPELL LIST: Snapshot + Build from DB
-- Phase A CDM Overhaul: own spell lists directly instead of mirroring
---------------------------------------------------------------------------

-- DB access for owned spell data
local function GetNcdmDB()
    if Shared and Shared.GetNcdmDB then
        local ncdm = Shared.GetNcdmDB()
        if ncdm then return ncdm end
    end

    local QUICore = ns.Addon
    return QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
end

local function GetContainerDB(containerKey)
    if Shared and Shared.GetContainerDB then
        local containerDB = Shared.GetContainerDB(containerKey)
        if containerDB then return containerDB end
    end

    local ncdm = GetNcdmDB()
    if not ncdm then return nil end
    if ncdm[containerKey] then
        return ncdm[containerKey]
    end
    if ncdm.containers and ncdm.containers[containerKey] then
        return ncdm.containers[containerKey]
    end
    return nil
end

-- Normalize legacy entries: convert raw spellID numbers to entry objects
-- and infer entry.type when missing. Item IDs and spell IDs share a single
-- numeric namespace from QUI's perspective (no overlap is enforced), so
-- resolve item-first via the source facade — that lookup is
-- fast and only succeeds for real items. Anything that doesn't look like
-- an item falls back to "spell". This matches the composer's
-- ResolveEntryType helper so entries that round-tripped through the DB
-- without an explicit type land in the same bucket they would have if
-- AddItem / AddSpell had been called originally.
local function NormalizeOwnedEntry(entry)
    if type(entry) == "number" then
        return { type = "spell", id = entry }
    end
    if type(entry) == "table" and entry.id then
        if not entry.type then
            local resolvedType = "spell"
            if type(entry.id) == "number" and Sources and Sources.QueryItemInfoInstant then
                local itemID = Sources.QueryItemInfoInstant(entry.id)
                if itemID then
                    resolvedType = "item"
                end
            end
            entry.type = resolvedType
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

-- Check if a spell is currently known/learned by the player.
-- IsSpellKnown covers class/spec spells; IsPlayerSpell covers talent-
-- granted spells; the override-spell check picks up talent/hero-talent
-- IDs that the base APIs don't recognize but whose current override is
-- known.
local WoW_IsSpellKnown = IsSpellKnown
local WoW_IsPlayerSpell = IsPlayerSpell
local function IsSpellKnownByPlayer(spellID)
    if not spellID then return false end
    if WoW_IsSpellKnown and WoW_IsSpellKnown(spellID) then return true end
    if WoW_IsPlayerSpell and WoW_IsPlayerSpell(spellID) then return true end
    local overrideID = Sources and Sources.QueryOverrideSpell and Sources.QueryOverrideSpell(spellID)
    if overrideID and overrideID ~= spellID then
        if WoW_IsSpellKnown and WoW_IsSpellKnown(overrideID) then return true end
        if WoW_IsPlayerSpell and WoW_IsPlayerSpell(overrideID) then return true end
    end
    -- The CDM picker prefers overrideSpellID (e.g. Death Charge 444347) but
    -- only the base ability (Death's Advance 48265) is in the spellbook, so
    -- the input ID won't be IsSpellKnown — back-resolve via GetBaseSpell.
    local baseID = Sources and Sources.QueryBaseSpell and Sources.QueryBaseSpell(spellID)
    if baseID and baseID ~= spellID then
        if WoW_IsSpellKnown and WoW_IsSpellKnown(baseID) then return true end
        if WoW_IsPlayerSpell and WoW_IsPlayerSpell(baseID) then return true end
    end
    return false
end


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
-- Built from the composer-provided catalog maps so runtime combat lookup
-- does not depend on direct player aura probes.
_abilityToAuraSpellID = {}
-- Multi-aura mapping: spellID → array of aura spellIDs from the CDM
-- catalog. Built from BuffIcon/BuffBar categories so aura state is sourced
-- from Blizzard's aura viewers, not from cooldown-viewer aliases.
-- Consumed by CDMResolvers.ResolveAuraActiveState and runtime aura Phase 3.
_auraIDsForSpell = {}

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
--   4. Built-in cooldown-only viewers (essential/utility) → cooldown
--   5. Custom-bar / unknown viewerType: consult Blizzard CDM mirror.
--      TrackedBuff (cat 2) / TrackedBar (cat 3) → aura
--      Essential (cat 0) / Utility (cat 1) → cooldown
--   6. Default cooldown (spell unknown to Blizzard CDM)
--
-- The Composer's tab-of-origin is authoritative: Passives/Buffs stamp
-- kind="aura"; All Cooldowns/Items stamp kind="cooldown". Falling through
-- to step 5 happens for the Composer's `cdm_spells` and `by_spell_id`
-- tabs on custom-bar containers — those tabs aren't kind-explicit, so we
-- defer to Blizzard's own classification via the mirror's viewerCategory.
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

    local impliedKind = GetBuiltinContainerEntryKind(viewerType)
    if impliedKind then
        return impliedKind
    end

    -- Custom-bar / unknown viewerType: consult Blizzard CDM mirror.
    -- This catches Composer adds via the cdm_spells / by_spell_id tabs
    -- (which don't pre-stamp kind from a tab contract) and stamps the
    -- entry with the kind Blizzard's own CDM viewer would imply. Cooldown
    -- viewers (essential/utility) take priority over aura viewers — a
    -- spell that lives in BOTH (a cooldown that has a tracked self-buff
    -- overlay) is fundamentally a cooldown for kind-classification.
    local mirror = ns.CDMBlizzMirror
    if mirror and mirror.GetCooldownIDForViewer and entry.id then
        if mirror.GetCooldownIDForViewer(entry.id, "essential")
           or mirror.GetCooldownIDForViewer(entry.id, "utility") then
            return "cooldown"
        end
        if mirror.GetCooldownIDForViewer(entry.id, "buff")
           or mirror.GetCooldownIDForViewer(entry.id, "trackedBar") then
            return "aura"
        end
    end

    return "cooldown"
end

local function IsAuraEntry(entry, viewerType)
    return ResolveEntryKind(entry, viewerType) == "aura"
end

-- Forward declaration for the spell→cooldownID rebuilder defined below.
local RebuildSpellToCooldownID

ResolveAuraDisplaySpellID = function(entryID)
    if RebuildSpellToCooldownID and not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end

    local AuraCatalog = ns.CDMAuraCatalog
    if AuraCatalog and AuraCatalog.ResolveEntryAuraDisplay then
        return AuraCatalog.ResolveEntryAuraDisplay(
            entryID, _abilityToAuraSpellID, ns.CDMBlizzMirror)
    end

    return entryID, false
end

if ns.CDMAuraRuntime and ns.CDMAuraRuntime.SetAbilityAuraSpellIDResolver then
    ns.CDMAuraRuntime.SetAbilityAuraSpellIDResolver(ResolveAuraDisplaySpellID)
end

local function AttachCatalogAuraIDs(resolved, ...)
    local AuraCatalog = ns.CDMAuraCatalog
    if AuraCatalog and AuraCatalog.AttachLinkedAuraIDs then
        AuraCatalog.AttachLinkedAuraIDs(resolved, _auraIDsForSpell, function(spellID)
            return CDMSpellData:GetAuraIDsForSpell(spellID)
        end, ...)
    end
end

-- Resolve a single owned entry to a spell data table compatible with
-- the existing icon/bar building pipeline.
local function ResolveOwnedEntry(entry, containerKey, index)
    if not entry or not entry.id then return nil end

    local resolved = {
        name = "",
        isAura = false,
        hasCharges = false,
        layoutIndex = index or 9999,
        viewerType = containerKey,
        _isOwnedEntry = true,
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
            local auraDisplayID, remapped = ResolveAuraDisplaySpellID(entry.id)
            if remapped then
                displayID = auraDisplayID
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
        if not isAuraEntry and Sources and Sources.QueryOverrideSpell then
            local overrideID = Sources.QueryOverrideSpell(displayID)
            if overrideID and overrideID ~= displayID then
                resolved.overrideSpellID = overrideID
            else
                resolved.overrideSpellID = displayID
            end
        else
            resolved.overrideSpellID = displayID
        end

        AttachCatalogAuraIDs(resolved, displayID, resolved.overrideSpellID, entry.id)

        -- Get spell name: try the resolved display/aura ID first, then fall back to
        -- the original entry ID. This handles cases where the CDM maps an ability to
        -- an aura/debuff spell ID whose GetSpellInfo returns no name (e.g. target
        -- debuffs that use internal rank IDs not exposed via C_Spell, or CD-only
        -- entries like Call Dreadstalkers where the aura ID lookup yields nothing).
        --
        -- Route through ns._GetCachedSpellName (cdm_icon_renderer.lua) so the in-combat
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
        if resolved.name == "" then
            local storedName = entry.name
            if type(storedName) == "string"
               and storedName ~= "" then
                resolved.name = storedName
            end
        end
        -- Check for multi-charge spells (runtime + SavedVariables fallback)
        if Sources and Sources.QuerySpellCharges then
            local checkID = resolved.overrideSpellID or displayID
            local ci, queryOk = Sources.QuerySpellCharges(checkID)
            local apiReadable = false
            if queryOk then
                if ci then
                    local maxC = ci.maxCharges
                    if maxC then
                        apiReadable = true
                        -- Any spell the charge API reports for (maxCharges >= 1)
                        -- is a charge-system spell. The single-charge case
                        -- includes the shared brez pool in raids/M+
                        -- (Rebirth/Raise Ally/Intercession) — the cooldown
                        -- shown is the recharge timer, so the icon must stay
                        -- saturated while a charge is available. Downstream
                        -- cdInfo.isActive gates actual usability.
                        if maxC >= 1 then
                            resolved.hasCharges = true
                        end
                    end
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
                local _dbgMaxC = ci and tostring(ci.maxCharges) or "nil"
                local _dbgCurC = ci and tostring(ci.currentCharges) or "nil"
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
        local itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        resolved.id = itemID
        resolved.itemID = itemID
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
        if itemName then
            resolved.name = itemName
        end

    elseif entry.type == "slot" then
        resolved.id = entry.id
        local itemID = Sources and Sources.QueryInventoryItemID
            and Sources.QueryInventoryItemID("player", entry.id)
        if itemID then
            -- Store resolved item ID for texture/tooltip but NOT as spellID
            resolved.itemID = itemID
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            if itemName then
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
                    local itemID = Sources and Sources.QueryItemInfoInstant
                        and Sources.QueryItemInfoInstant(itemLink)
                    if itemID then
                        resolved.spellID = itemID
                        resolved.overrideSpellID = itemID
                    end
                end
            end
        end
    end

    return resolved
end

-- BuildAuraInstanceKey produces a stable per-entry instance key. String
-- concatenation avoids the string.format parser cost on this hot path; the
-- ":entry:1" suffix must stay byte-identical to what the renderers compare.
local function BuildAuraInstanceKey(containerKey)
    return (containerKey or "aura") .. ":entry:1"
end

-- ExpandResolvedAuraEntry: previously fanned a resolved aura entry into
-- one virtual entry per active totem slot when `_isTotemBacked` was set.
-- That flag is no longer assigned anywhere, so the function reduces to
-- stamping a stable instance key and returning the entry as a single-
-- element list.
local function ExpandResolvedAuraEntry(containerKey, resolved)
    if resolved then
        resolved._instanceKey = BuildAuraInstanceKey(containerKey)
    end
    return { resolved }
end

-- SnapshotBlizzardCDM: First-time capture of Blizzard viewer spells into
-- ownedSpells. The actual C_CooldownViewer reads now live in
-- ns.CDMComposer.SeedFromBlizzard so cdm_spelldata stays free of
-- Blizzard CDM viewer references; this entrypoint delegates to that path.
function CDMSpellData:SnapshotBlizzardCDM(containerKey)
    if InCombatLockdown() and not ns._inInitSafeWindow then
        return false
    end
    if not IsBuiltinContainerKey(containerKey) then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end

    -- Only snapshot if ownedSpells == nil (first time)
    if db.ownedSpells ~= nil then return false end

    local composer = ns.CDMComposer
    if not (composer and composer.SeedFromBlizzard) then return false end

    local seeded, seedReady = composer.SeedFromBlizzard(containerKey)
    if not seeded or not seedReady then return false end

    db.ownedSpells = seeded
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

    -- Ensure ability-to-aura and family-membership maps are populated for
    -- accurate aura spellID resolution.
    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end

    -- Wipe per-batch memo caches so a stale aura-active result from the
    -- previous batch can't persist across buff-data-changed dispatches.
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
                        resolved._instanceKey = BuildAuraInstanceKey(containerKey)
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

    if _G.QUI_CDM_TOTEM_DEBUG then
        print("|cffFF8800[Totem]|r", "BuildSpellListFromOwned container=", containerKey, "result=", #result)
    end
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

-- The per-character Blizzard CDM catalog (_spellToCooldownID + family
-- membership maps) is populated. Class-aware aura cleanup gates on this so it
-- never shelves auras before the catalog has been walked — which would
-- false-positive every aura as "foreign" during early load.
local function CDMCatalogReady()
    if not next(_spellToCooldownID) then
        if RebuildSpellToCooldownID then
            RebuildSpellToCooldownID()
        end
    end
    return next(_spellToCooldownID) ~= nil
end

local function GetDormancyActiveEntries(db)
    if type(db) ~= "table" then return nil end
    if db.containerType == "customBar" then
        return db.entries
    end
    return db.ownedSpells
end

local CDM_COOLDOWN_CATEGORIES = { 0, 1 }
local CDM_AURA_CATEGORIES = { 2, 3 }

local function CooldownInfoMatchesSpellID(info, spellID)
    if type(info) ~= "table" or type(spellID) ~= "number" then return false end
    if info.spellID == spellID
        or info.overrideSpellID == spellID
        or info.overrideTooltipSpellID == spellID then
        return true
    end
    if type(info.linkedSpellIDs) == "table" then
        for _, linkedID in ipairs(info.linkedSpellIDs) do
            if linkedID == spellID then return true end
        end
    end
    return false
end

local function GetCooldownViewerKnownStateForSpell(spellID, family)
    local catalog = ns.CDMCatalog
    if type(spellID) ~= "number"
        or not (catalog and catalog.GetCategorySet and catalog.GetCooldownInfo) then
        return nil
    end

    local categories = (family == "aura" or family == "auraBar")
        and CDM_AURA_CATEGORIES
        or CDM_COOLDOWN_CATEGORIES
    local sawMatch = false
    for _, category in ipairs(categories) do
        local cooldownIDs = catalog.GetCategorySet(category, true)
        if type(cooldownIDs) == "table" then
            for _, cooldownID in ipairs(cooldownIDs) do
                local info = catalog.GetCooldownInfo(cooldownID)
                if CooldownInfoMatchesSpellID(info, spellID) then
                    sawMatch = true
                    if info.isKnown == true then
                        return true
                    end
                end
            end
        end
    end
    if sawMatch then return false end
    return nil
end

-- Sort returning dormant spells by saved slot, then by dormant sequence for
-- deterministic same-slot restores. Module-local (closes over nothing) so the
-- dormant pass does not allocate a fresh comparator closure each call.
local function CompareDormantReturning(a, b)
    if a.slot ~= b.slot then
        return a.slot < b.slot
    end
    if a.seq ~= b.seq then
        return a.seq < b.seq
    end
    return a.id < b.id
end

function CDMSpellData:CheckDormantSpells(containerKey, restoreOnly)
    local db = GetContainerDB(containerKey)
    if not db then
        return
    end

    local activeEntries = GetDormancyActiveEntries(db)
    if type(activeEntries) ~= "table" then
        return
    end

    local ownedSpells = NormalizeOwnedSpells(activeEntries)

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

    -- Phase 0 (aura restore): resurrect dormant aura entries that belong to
    -- THIS character's CDM aura family. A buff aura ID is a passive presence
    -- indicator, not a cast ability that "comes and goes" with talents, so a
    -- same-class aura should never stay dormant. Foreign-class auras (another
    -- class's tracked buffs left in a shared AceDB profile) are the exception:
    -- they stay dormant and get pruned by Phase 3. Class is decided via the
    -- per-character Blizzard CDM catalog. Before the catalog is populated we
    -- can't tell foreign from own, so fall back to the legacy blanket restore
    -- to avoid stranding legitimate auras during early load.
    if IsBuiltinAuraContainerKey(containerKey)
        and next(db.dormantSpells) then
        local catalogReady = CDMCatalogReady()
        for sid, savedData in pairs(db.dormantSpells) do
            local pickerKnown
            if type(savedData) == "table" then
                pickerKnown = savedData.pickerKnown
            end
            local shouldRestore = pickerKnown == false
                and GetCooldownViewerKnownStateForSpell(sid, "aura") == true
            if pickerKnown ~= false then
                shouldRestore = (not catalogReady) or self:IsSpellInCDMCategory(sid, "aura")
            end
            if shouldRestore then
                local restoredRow
                if type(savedData) == "table" then
                    restoredRow = savedData.row
                end
                activeEntries[#activeEntries + 1] = {
                    type = "spell",
                    id = sid,
                    row = restoredRow,
                    kind = "aura",
                }
                -- Setting an existing key to nil mid-traversal is permitted.
                db.dormantSpells[sid] = nil
            end
        end
    end

    -- Phase 1: Move spells that don't belong to this character to dormant.
    -- Skipped when restoreOnly is true — recovery handlers should only
    -- rescue spells from dormant, not risk marking more spells dormant
    -- while APIs may still be settling after a zone transition.
    --
    -- Cooldown entries are judged by the spellbook (IsSpellKnownByPlayer).
    -- Aura entries can't be: buff/aura spell IDs are rarely in the spellbook
    -- (the buff ID and the cast ability ID usually differ). They are judged
    -- by the per-character Blizzard CDM catalog instead — an aura absent from
    -- THIS character's aura family is foreign (e.g. another class's tracked
    -- buff left behind in a shared AceDB profile) and is shelved. The catalog
    -- gate means a legitimate same-class aura that simply isn't applied right
    -- now is kept (the runtime resolver shows it inactive); only genuinely
    -- foreign auras are removed, and only once the catalog has been walked.
    if not restoreOnly then
        local toRemove = {}  -- indices to remove (descending order)
        local catalogReady = CDMCatalogReady()
        for i, entry in ipairs(ownedSpells) do
            if entry and entry.id and entry.type == "spell" then
                local shouldShelve
                if IsAuraEntry(entry, containerKey) then
                    shouldShelve = catalogReady
                        and not self:IsSpellInCDMCategory(entry.id, "aura")
                else
                    shouldShelve = not IsSpellKnownByPlayer(entry.id)
                end
                if shouldShelve then
                    -- Save slot position AND row assignment so both are restored
                    db._dormantSequence = (db._dormantSequence or 0) + 1
                    db.dormantSpells[entry.id] = {
                        slot = i,
                        row = entry.row,
                        kind = entry.kind,
                        seq = db._dormantSequence,
                    }
                    toRemove[#toRemove + 1] = i
                end
            end
        end
        -- Remove from active entries in reverse order to preserve indices
        for j = #toRemove, 1, -1 do
            table.remove(activeEntries, toRemove[j])
        end
    end

    -- Phase 2: Re-insert returning dormant spells at saved positions
    local returning = {}
    for sid, savedData in pairs(db.dormantSpells) do
        if IsSpellKnownByPlayer(sid) then
            -- Support both legacy (number) and new (table) dormant format
            local savedSlot, savedRow, savedSeq, savedKind
            if type(savedData) == "table" then
                savedSlot = savedData.slot or 9999
                savedRow = savedData.row
                savedSeq = savedData.seq or savedSlot
                savedKind = savedData.kind
            else
                savedSlot = savedData or 9999
                savedSeq = savedSlot
            end
            returning[#returning + 1] = {
                id = sid,
                slot = savedSlot,
                row = savedRow,
                seq = savedSeq,
                kind = savedKind,
            }
        end
    end
    -- Sort by saved slot, then by dormant sequence for deterministic same-slot restores.
    table.sort(returning, CompareDormantReturning)
    for _, info in ipairs(returning) do
        db.dormantSpells[info.id] = nil  -- remove from dormant
        local insertAt = math.min(info.slot, #activeEntries + 1)
        local restored = { type = "spell", id = info.id, row = info.row }
        if info.kind == "aura" or info.kind == "cooldown" then
            restored.kind = info.kind
        else
            restored.kind = ResolveEntryKind(restored, containerKey)
        end
        table.insert(activeEntries, insertAt, restored)
    end

    -- Phase 3: Clean obsolete dormant spells no longer in the CDM system.
    -- Skip during zone transitions — spellbook + composer APIs return
    -- incomplete data while transitioning, which would permanently delete
    -- valid dormant spells with no recovery path.
    if not restoreOnly and not _inZoneTransition then
        local allCDMSpells = {}
        local composer = ns.CDMComposer
        if composer and composer.CollectKnownCDMSpellIDs then
            composer.CollectKnownCDMSpellIDs(allCDMSpells)
        end
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
local okT = true; local numTabs = C_SpellBook.GetNumSpellBookSkillLines()
            if numTabs then
                for tab = 1, numTabs do
local okL = true; local sli = C_SpellBook.GetSpellBookSkillLineInfo(tab)
                    if sli then
                        local offset = sli.itemIndexOffset or 0
                        for i = 1, (sli.numSpellBookItems or 0) do
local okI = true; local ii = C_SpellBook.GetSpellBookItemInfo(offset + i, Enum.SpellBookSpellBank.Player)
                            if ii and ii.spellID then allCDMSpells[ii.spellID] = true end
                        end
                    end
                end
            end
        end
        -- Don't permanently delete unless we collected at least one
        -- "still existing" spellID. Without that signal we can't tell
        -- "spell rotated out" from "API returned no data this frame."
        if next(allCDMSpells) then
            for sid in pairs(db.dormantSpells) do
                if not allCDMSpells[sid] then
                    db.dormantSpells[sid] = nil
                end
            end
        end
    end

    -- Summary
    local finalOwned = type(activeEntries) == "table" and #activeEntries or 0
    local finalDormant = 0
    if type(db.dormantSpells) == "table" then
        for _ in pairs(db.dormantSpells) do finalDormant = finalDormant + 1 end
    end
end

-- CheckAllDormantSpells: Run dormant check on all container keys.
-- restoreOnly: when true, only Phase 2 (restore) runs — no new dormanting
-- or permanent deletion. Used by recovery handlers.
function CDMSpellData:CheckAllDormantSpells(restoreOnly)
    local containerKeys = GetBuiltinContainerKeys()
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

-- Spell→cooldownID lookup across all four CDM categories. The
-- composer owns the C_CooldownViewer reads; spelldata only delegates
-- so the maps stay populated for runtime classification.
RebuildSpellToCooldownID = function()
    ClearDeprecatedLearnedCastToAuraDB()
    wipe(_spellToCooldownID)
    wipe(_spellInCDMCooldowns)
    wipe(_spellInCDMAuras)
    wipe(_abilityToAuraSpellID)
    wipe(_auraIDsForSpell)
    local composer = ns.CDMComposer
    if composer and composer.RebuildBlizzardCatalogMaps then
        composer.RebuildBlizzardCatalogMaps(
            _spellToCooldownID, _spellInCDMCooldowns,
            _spellInCDMAuras, _abilityToAuraSpellID,
            _auraIDsForSpell)
    end
end

---------------------------------------------------------------------------
-- DYNAMIC SPELL RECONCILIATION
-- Two-pass approach: preserve existing tracked spells (maintain user ordering),
-- then append newly discovered spells at the end.
---------------------------------------------------------------------------


-- Shared reconcile tail. CheckAllDormantSpells shelves/restores spells for
-- the active character, ReconcileAllContainers rebuilds the spellID maps, and
-- FireChangeCallback refreshes display after any dormant cleanup. Callers must
-- invoke this inside their own combat-lockdown guard.
local function RunReconcileSequence()
    CDMSpellData:CheckAllDormantSpells()
    CDMSpellData:ReconcileAllContainers()
    if FireChangeCallback then
        FireChangeCallback()
    end
end

-- Cold-load single-trigger entry point. Called from cdm_blizz_mirror.lua's
-- deferred PLAYER_LOGIN callback (after the mirror's Walk has settled
-- against post-customization data). Runs the same reconcile work the
-- SPELLS_CHANGED debounce does, but synchronously so the single trigger
-- can sequence Walk -> catalog rebuild -> entry reconcile -> change
-- callback in one pass without intermediate UI flicker.
function CDMSpellData:RunColdLoadReconcile()
    if not IsCDMRuntimeEnabled() then return end
    if InCombatLockdown() then
        -- Bail; cold-load-into-combat is rare. Once combat ends, post-grace
        -- SPELLS_CHANGED / data_loaded events fire normal reconcile.
        return
    end
    -- Cold-load ordering contract: the catalog must be fresh before the
    -- dormant check, so rebuild explicitly here ahead of the shared tail.
    if RebuildSpellToCooldownID then
        RebuildSpellToCooldownID()
    end
    RunReconcileSequence()
end

function CDMSpellData:ReconcileAllContainers()
    if InCombatLockdown() then
        return
    end

    -- Rebuild spellID maps. No spell is auto-added at the per-container level;
    -- the user owns the curated list via the Composer and CheckAllDormantSpells
    -- handles spec-switch cleanup separately.
    RebuildSpellToCooldownID()
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
    -- overwrites Composer edits with stale spec-scoped data.
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
    local specID = GetCurrentSpecID()
    if not specID then
        local class
        if UnitClass then
            local _
            _, class = UnitClass("player")
        end
        return class or "UNKNOWN"
    end
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
local function GetMutableEntryList(db, containerKey, createIfMissing, specKey)
    if not db then return nil end
    if db.specSpecific then
        if specKey == false then
            local field = GetEntryListField(db)
            if createIfMissing and db[field] == nil then db[field] = {} end
            return db[field]
        end
        return GetSpecEntryList(containerKey, specKey, createIfMissing)
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
    local pickerKnown = entry.isKnown
    entry.isKnown = nil

    -- Within-container dedup — prevent adding duplicates. customBar
    -- entries are already typed as {type,id}; ownedSpells may have the
    -- older {id=N} shape which NormalizeOwnedEntry handles.
    for _, existing in ipairs(list) do
        local norm = NormalizeOwnedEntry(existing)
        local existingID = norm and norm.id
        local entryID = entry.id
        if norm and norm.type == "item" and entry.type == "item" then
            existingID = (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(existingID)) or existingID
            entryID = (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(entryID)) or entryID
        end
        if norm and norm.type == entry.type and existingID == entryID then
            return false  -- already exists
        end
    end

    if entry.type == "spell" and type(entry.id) == "number"
        and type(db.dormantSpells) == "table" and db.dormantSpells[entry.id] then
        return false
    end

    local forceDormantFromPicker = pickerKnown == false
    if entry.type == "spell" and type(entry.id) == "number"
        and (forceDormantFromPicker or not IsAuraEntry(entry, containerKey)) then
        local isKnown
        if pickerKnown ~= nil then
            isKnown = (pickerKnown == true)
        else
            isKnown = IsSpellKnownByPlayer(entry.id)
        end
        if not isKnown then
            if type(db.dormantSpells) ~= "table" then
                db.dormantSpells = {}
            end
            db._dormantSequence = (db._dormantSequence or 0) + 1
            db.dormantSpells[entry.id] = {
                slot = #list + 1,
                row = entry.row,
                kind = entry.kind,
                pickerKnown = pickerKnown,
                seq = db._dormantSequence,
            }
            FireChangeCallback()
            return true
        end
    end

    list[#list + 1] = entry
    FireChangeCallback()
    return true
end

function CDMSpellData:RemoveEntry(containerKey, index, specKey)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end
    local list = GetMutableEntryList(db, containerKey, false, specKey)
    if type(list) ~= "table" then return false end
    if type(index) ~= "number" then return false end
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

function CDMSpellData:ReorderEntry(containerKey, fromIndex, toIndex, specKey)
    if CombatGuard() then return false end

    local db = GetContainerDB(containerKey)
    if not db then return false end
    local list = GetMutableEntryList(db, containerKey, false, specKey)
    if type(list) ~= "table" then return false end
    if type(fromIndex) ~= "number" or type(toIndex) ~= "number" then return false end

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

    -- Cross-family kind rewrite for item-type entries. Spells/macros are
    -- restricted to same-family moves by SIBLING_TYPES; this branch only
    -- fires for item/trinket/slot.
    if entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
        and Shared and Shared.GetBuiltinContainerEntryKind then
        local destKind = Shared.GetBuiltinContainerEntryKind(toKey)
        if destKind == "aura" then
            entry.kind = "aura"
            -- displayMode is inert on built-in aura containers; clear it
            -- so the field doesn't linger if the user later moves back.
            entry.displayMode = nil
        elseif destKind == "cooldown" then
            entry.kind = "cooldown"
        end
        -- destKind == nil means custom container; leave entry.kind alone
        -- (custom items default to cooldown via AddItem; preserve current).
    end

    if toDB.ownedSpells == nil then
        toDB.ownedSpells = {}
    end
    toDB.ownedSpells[#toDB.ownedSpells + 1] = entry

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
    local list = GetMutableEntryList(db, containerKey, true)
    if type(list) ~= "table" then return false end
    db.dormantSpells[spellID] = nil
    -- Support both legacy (number) and new (table) dormant format
    local savedSlot, savedRow, savedKind
    if type(savedData) == "table" then
        savedSlot = savedData.slot or 9999
        savedRow = savedData.row
        savedKind = savedData.kind
    else
        savedSlot = savedData or 9999
    end
    local insertAt = math.min(savedSlot, #list + 1)
    local restored = { type = "spell", id = spellID, row = savedRow }
    if savedKind == "aura" or savedKind == "cooldown" then
        restored.kind = savedKind
    else
        restored.kind = ResolveEntryKind(restored, containerKey)
    end
    table.insert(list, insertAt, restored)
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
function CDMSpellData:AddSpell(containerKey, spellID, kind, row, isKnown)
    return self:AddEntry(containerKey, { type = "spell", id = spellID, kind = kind, row = row, isKnown = isKnown })
end

function CDMSpellData:AddItem(containerKey, itemID, row, kind)
    return self:AddEntry(containerKey, {
        type = "item",
        id = itemID,
        kind = kind or "cooldown",
        row = row,
    })
end

function CDMSpellData:AddTrinketSlot(containerKey, slotID, row, kind)
    return self:AddEntry(containerKey, {
        type = "slot",
        id = slotID,
        kind = kind or "cooldown",
        row = row,
    })
end


-- Returns the aura spellID for an item if Blizzard's cooldown viewer or the
-- runtime scanner already knows about it; nil if the aura would only be
-- discovered at first-use. Used by composer UI to surface "no known aura
-- yet" hints without gating UX on resolvability.
function CDMSpellData:HasResolvableAuraForItem(itemID)
    if type(itemID) ~= "number" or itemID <= 0 then return nil end
    if not Sources then return nil end

    -- Some items (e.g., Engineering trinkets) map item -> use-spell -> aura.
    -- Walk the same path the runtime uses in ResolveAuraActiveState.
    -- QueryItemSpell returns (spellName, spellID), so capture the second value.
    local useSpellID
    if Sources.QueryItemSpell then
        local _, sid = Sources.QueryItemSpell(itemID)
        useSpellID = sid
    end

    if useSpellID and Sources.QueryCooldownAuraBySpellID then
        local auraID = Sources.QueryCooldownAuraBySpellID(useSpellID)
        if type(auraID) == "number" and auraID > 0 then
            return auraID
        end
    end

    -- Runtime scanner may have cached an aura mapping for this item.
    -- GetScannedItemInfo returns a table with buffSpellID when known.
    local scanner = _G.QUI and _G.QUI.SpellScanner
    if scanner and scanner.GetScannedItemInfo then
        local info = scanner.GetScannedItemInfo(itemID)
        if info and type(info.buffSpellID) == "number" and info.buffSpellID > 0 then
            return info.buffSpellID
        end
    end

    return nil
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

    local ownedSet = {}
    if db and type(db.ownedSpells) == "table" then
        for _, entry in ipairs(db.ownedSpells) do
            local normalized = NormalizeOwnedEntry(entry)
            if normalized and normalized.type == "spell" and normalized.id then
                ownedSet[normalized.id] = true
                local oid = Sources and Sources.QueryOverrideSpell
                    and Sources.QueryOverrideSpell(normalized.id)
                if oid and oid ~= normalized.id then
                    ownedSet[oid] = true
                end
            end
        end
    end
    if db and type(db.dormantSpells) == "table" then
        for sid in pairs(db.dormantSpells) do
            if type(sid) == "number" then
                ownedSet[sid] = true
            end
        end
    end

    local containerType = db and db.containerType
    if not containerType then
        local ncdm = GetNcdmDB()
        if ncdm and ncdm.containers and ncdm.containers[containerKey] then
            containerType = ncdm.containers[containerKey].containerType
        end
    end

    local composer = ns.CDMComposer
    if composer and composer.GetAvailableSpellsForContainer then
        return composer.GetAvailableSpellsForContainer(containerKey, containerType, ownedSet, _cdIDToCorrectSID)
    end
    return {}
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
local numTabs = C_SpellBook.GetNumSpellBookSkillLines()
        if numTabs then
            for tab = 1, numTabs do
local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
                if skillLineInfo and skillLineInfo.name ~= GENERAL then
                    local offset = skillLineInfo.itemIndexOffset or 0
                    local numEntries = skillLineInfo.numSpellBookItems or 0
                    for i = 1, numEntries do
                        local slotIndex = offset + i
local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)
                        if itemInfo and itemInfo.spellID and not itemInfo.isPassive and not itemInfo.isOffSpec then
                            local sid = itemInfo.spellID
                            if not seen[sid] then
                                seen[sid] = true
                                -- Check base cooldown (ms) for sorting/display
                                local baseCDms = 0
                                if Sources and Sources.QuerySpellBaseCooldown then
                                    local ms = Sources.QuerySpellBaseCooldown(sid)
                                    if ms then baseCDms = ms or 0 end
                                end
                                if baseCDms <= 1500 and Sources and Sources.QuerySpellCharges then
                                    local ci = Sources.QuerySpellCharges(sid)
                                    if ci then
                                        local maxC = ci.maxCharges or 0
                                        if maxC > 1 then baseCDms = 2000 end
                                    end
                                end
                                local name, icon
                                local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                                if spellInfo then
                                    name = spellInfo.name
                                    icon = spellInfo.iconID
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
                    local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                    if spellInfo then
                        rName = spellInfo.name
                        rIcon = spellInfo.iconID
                    end
                    if rName then
                        local baseCDms = 0
                        if Sources and Sources.QuerySpellBaseCooldown then
                            local ms = Sources.QuerySpellBaseCooldown(sid)
                            if ms then baseCDms = ms or 0 end
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
        local sid = GetCleanAuraSpellID(auraData)
        if sid == nil or seen[sid] then return false end
        seen[sid] = true
        local name = GetCleanAuraName(auraData)
        local icon = auraData.icon or 0
        local duration = auraData.duration or 0
        result[#result + 1] = {
            spellID = sid,
            name = name or "",
            icon = icon or 0,
            duration = duration or 0,
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

local numTabs = C_SpellBook.GetNumSpellBookSkillLines()
    if not numTabs then return result end

    for tab = 1, numTabs do
local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
        if skillLineInfo and skillLineInfo.name ~= GENERAL then
            local offset = skillLineInfo.itemIndexOffset or 0
            local numEntries = skillLineInfo.numSpellBookItems or 0
            for i = 1, numEntries do
                local slotIndex = offset + i
local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)
                if itemInfo and itemInfo.spellID and itemInfo.isPassive and not itemInfo.isOffSpec then
                    local sid = itemInfo.spellID
                    if not seen[sid] then
                        seen[sid] = true
                        local name, icon
                        local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                        if spellInfo then
                            name = spellInfo.name
                            icon = spellInfo.iconID
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

local function GetItemProfessionQualityRank(itemInfo)
    if not itemInfo or not (Sources and Sources.QueryItemProfessionQualityInfo) then
        return 0
    end

    local info = Sources.QueryItemProfessionQualityInfo(itemInfo)
    if issecretvalue and issecretvalue(info) then return 0 end
    if type(info) ~= "table" then return 0 end
    local quality = info.quality
    if issecretvalue and issecretvalue(quality) then return 0 end
    if type(quality) == "number" then return quality end
    return 0
end

local function SortBagItemsByProfessionQuality(items)
    if type(items) ~= "table" or #items <= 1 then return end
    table.sort(items, function(a, b)
        local aq = (type(a) == "table" and a._professionQualityRank) or 0
        local bq = (type(b) == "table" and b._professionQualityRank) or 0
        if aq ~= bq then return aq > bq end
        local ao = (type(a) == "table" and a._bagOrder) or 0
        local bo = (type(b) == "table" and b._bagOrder) or 0
        return ao < bo
    end)
end

function CDMSpellData:GetUsableItems()
    local result = {}

    -- Scan equipped trinkets (slots 13 and 14)
    for _, slotID in ipairs({ 13, 14 }) do
        local itemID = Sources and Sources.QueryInventoryItemID
            and Sources.QueryInventoryItemID("player", slotID)
        if itemID then
            local name, icon
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            if itemName then name = itemName end
            local itemIcon = Sources and Sources.QueryItemIconByID and Sources.QueryItemIconByID(itemID)
            if itemIcon then icon = itemIcon end

            -- Check if trinket has an on-use spell
            local hasSpell = false
            if Sources and Sources.QueryItemSpell then
                local spellName = Sources.QueryItemSpell(itemID)
                if spellName then hasSpell = true end
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

    -- Scan bags for items with on-use spells.
    -- De-dupe by itemID — multiple stacks of the same consumable would
    -- otherwise produce one Items-tab entry per stack. When the same
    -- itemID appears multiple times, keep the variant with the highest
    -- profession quality rank (relevant for crafted items where
    -- different stacks can have different quality tiers).
    local bagItems = {}
    local seenItemIDs = {}
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
local numSlots = C_Container.GetContainerNumSlots(bag)
            if numSlots then
                for slot = 1, numSlots do
local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
                    if containerInfo and containerInfo.itemID then
                        local itemID = containerInfo.itemID
                        -- Check for on-use spell
                        if Sources and Sources.QueryItemSpell then
                            local spellName = Sources.QueryItemSpell(itemID)
                            if spellName then
                                local name = containerInfo.itemName or ""
                                local icon = containerInfo.iconFileID or 0
                                local qualityLookup = itemID
                                local hyperlink = containerInfo.hyperlink
                                if hyperlink and not (issecretvalue and issecretvalue(hyperlink)) then
                                    qualityLookup = hyperlink
                                end
                                local qualityRank = GetItemProfessionQualityRank(qualityLookup)
                                local existingIdx = seenItemIDs[itemID]
                                if existingIdx then
                                    local existing = bagItems[existingIdx]
                                    local existingRank = existing and existing._professionQualityRank
                                    if qualityRank ~= nil
                                        and (existingRank == nil or qualityRank > existingRank) then
                                        existing.name = name
                                        existing.icon = icon
                                        existing._professionQualityRank = qualityRank
                                    end
                                else
                                    bagItems[#bagItems + 1] = {
                                        type = "item",
                                        id = itemID,
                                        itemID = itemID,
                                        name = name,
                                        icon = icon,
                                        slotID = nil,
                                        _bagOrder = #bagItems + 1,
                                        _professionQualityRank = qualityRank,
                                    }
                                    seenItemIDs[itemID] = #bagItems
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    SortBagItemsByProfessionQuality(bagItems)
    for _, item in ipairs(bagItems) do
        item._bagOrder = nil
        item._professionQualityRank = nil
        result[#result + 1] = item
    end

    return result
end


---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

-- GetSpellList: Routing function — owned path if snapshotted, scan fallback
function CDMSpellData:GetSpellList(viewerType)
    local db = GetContainerDB(viewerType)
    -- customBar containers source entries exclusively from db.entries via the
    -- icon renderer's custom-bar branch. A stale db.ownedSpells (left behind
    -- by a legacy migration or a stray MoveEntryBetweenContainers write)
    -- would otherwise feed BuildSpellListFromOwned here AND db.entries would
    -- feed the customBar loop in BuildIcons — runtime renders the sum.
    if db and db.containerType == "customBar" then
        return {}
    end
    local hasOwned = db and db.ownedSpells ~= nil
    if hasOwned then
        -- Owned path: build from DB
        local result = self:BuildSpellListFromOwned(viewerType)
        return result
    end
    -- Fallback: existing scan-based approach (backward compat)
    -- Custom containers with no ownedSpells yet return empty
    if not IsBuiltinContainerKey(viewerType) then
        return {}
    end
    local list = spellLists[viewerType] or {}
    return list
end

function CDMSpellData:UpdateCVar()
    UpdateCooldownViewerCVar()
end

function CDMSpellData:InvalidateLearnedCache()
    InvalidateLearnedCooldownsCache()
end

-- Aggregate cache stats for /qui cdm_cache status (read by QUI_Debug memaudit probes).
function CDMSpellData:GetCacheStats()
    local function size(t)
        if type(t) ~= "table" then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
    local function capturedStats()
        local seenEntries = {}
        local seenUnits = {}
        local entryCount = 0
        local unitCount = 0

        local function addEntry(entry)
            if type(entry) == "table" and not seenEntries[entry] then
                seenEntries[entry] = true
                entryCount = entryCount + 1
            end
        end

        local function addUnit(unit)
            if unit and not seenUnits[unit] then
                seenUnits[unit] = true
                unitCount = unitCount + 1
            end
        end

        for _, entry in pairs(_capturedAuraBySpellID) do
            addEntry(entry)
            addUnit(entry and entry.unit)
        end
        for _, entry in pairs(_capturedAuraByName) do
            addEntry(entry)
            addUnit(entry and entry.unit)
        end
        for unit, map in pairs(_capturedAuraByUnitSpellID) do
            addUnit(unit)
            for _, entry in pairs(map) do
                addEntry(entry)
                addUnit(entry and entry.unit)
            end
        end
        for unit, map in pairs(_capturedAuraByUnitName) do
            addUnit(unit)
            for _, entry in pairs(map) do
                addEntry(entry)
                addUnit(entry and entry.unit)
            end
        end

        return entryCount, unitCount
    end
    local learnedSize = 0
    if type(learnedCooldownsCache) == "table" then
        learnedSize = #learnedCooldownsCache
    end
    local capturedAuraEntries, capturedAuraUnits = capturedStats()
    return {
        capturedAuraEntries = capturedAuraEntries,
        capturedAuraUnits   = capturedAuraUnits,
        capturedAuraSpellKeys = size(_capturedAuraBySpellID),
        capturedAuraNameKeys  = size(_capturedAuraByName),
        learnedDirty        = learnedCooldownsCacheDirty and true or false,
        learnedSize         = learnedSize,
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
        end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZE: Called by cdm_containers.lua Initialize() to bootstrap
-- spell data scanning. Replaces the self-bootstrapping event frame.
---------------------------------------------------------------------------
function CDMSpellData:Initialize()
    ClearDeprecatedLearnedCastToAuraDB()

    if not IsCDMRuntimeEnabled() then
        return
    end

    RegisterAuraCaptureFrame()
    SyncCooldownViewerCVarToMasterToggle()

    ForceLoadCDM()
    -- Deferred init: edit-mode callbacks + reconciliation. The legacy scan
    -- of Blizzard CDM viewer children was retired with the cdm_spelldata
    -- strip; owned spell lists come from composer entries on demand.
    C_Timer.After(0.5, function()
        if not IsCDMRuntimeEnabled() then return end
        UpdateCooldownViewerCVar()
        RegisterEditModeCallbacks()
        initialized = true
        if not InCombatLockdown() then
            CDMSpellData:ReconcileAllContainers()
        end
    end)
    -- Register runtime events
    local _spellsChangedToken = 0
    local _cdmViewerReconcileToken = 0
    local _cooldownViewerRebuildPending = false
    local eventFrame = CreateFrame("Frame")
    runtimeEventFrame = eventFrame
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
    eventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event, arg)
        if not IsCDMRuntimeEnabled() then
            self:UnregisterAllEvents()
            return
        end

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
            -- incorrectly marked dormant. PLAYER_ENTERING_WORLD already
            -- holds these checks until APIs stabilise.
            if _inZoneTransition then
                -- Record that a reconcile is owed: the 2s PLAYER_ENTERING_WORLD
                -- timer drains this once the APIs settle, so this SPELLS_CHANGED
                -- is not lost if no further one fires after the window closes.
                _spellsChangedDuringZoneTransition = true
                return
            end
            -- Cold-load grace: PLAYER_LOGIN's deferred callback runs the
            -- reconcile once after CDM settles; intermediate SPELLS_CHANGED
            -- bursts during the grace window are absorbed.
            if ns._cdmColdLoadActive then
                return
            end
            -- Debounce dormant/reconcile — SPELLS_CHANGED fires multiple times
            -- during talent swaps; collapse into a single deferred rebuild.
            _spellsChangedToken = _spellsChangedToken + 1
            local token = _spellsChangedToken
            C_Timer.After(0.3, function()
                if not IsCDMRuntimeEnabled() then return end
                if token ~= _spellsChangedToken then
                    return
                end
                if not InCombatLockdown() then
                    -- Notify containers to refresh display after dormant cleanup
                    -- removed stale spells from ownedSpells.
                    RunReconcileSequence()
                end
            end)
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            -- Trinket changes: reconcile to pick up new trinket slots
            if not InCombatLockdown() then
                CDMSpellData:ReconcileAllContainers()
            end
        elseif event == "COOLDOWN_VIEWER_DATA_LOADED"
            or event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
            or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
            if InCombatLockdown() then
                _cooldownViewerRebuildPending = true
                return
            end
            -- Cold-load grace: PLAYER_LOGIN's deferred callback owns the
            -- initial reconcile. data_loaded bursts during the grace window
            -- (the cooldown viewer's own settle-in events) get absorbed.
            if ns._cdmColdLoadActive then
                return
            end
            RebuildSpellToCooldownID()
            FireChangeCallback()
            -- Cold-login catalog-staleness fix.
            --
            -- On cold-login, catalog entries are first built at PEW from
            -- whatever C_CooldownViewer.GetCooldownViewerCooldownInfo()
            -- returns at that moment — which is nil before
            -- IsCooldownViewerAvailable() returns true. Without a
            -- subsequent rebuild against the now-loaded table, the
            -- _cdIDByCatSpell[category] maps in cdm_blizz_mirror stay
            -- missing entries (e.g. Death's Advance 444347 -> essential
            -- cdID 27920), so the cross-category resolver in
            -- ResolveBlizzardMirrorIdentityState returns nil and the
            -- affected icon stays unbound from its Blizzard mirror,
            -- falling into the (unreliable) FWD path.
            --
            -- Mirror the SPELLS_CHANGED debounce shape so a burst of
            -- OVERRIDE_UPDATED events during proc storms collapses into
            -- a single reconcile. PLAYER_SPECIALIZATION_CHANGED was
            -- previously the only path that triggered this reconcile,
            -- which is why spec swap was the only way to fix the bug
            -- short of /reload.
            _cdmViewerReconcileToken = _cdmViewerReconcileToken + 1
            local token = _cdmViewerReconcileToken
            C_Timer.After(0.5, function()
                if not IsCDMRuntimeEnabled() then return end
                if token ~= _cdmViewerReconcileToken then return end
                if not InCombatLockdown() then
                    CDMSpellData:CheckAllDormantSpells()
                    CDMSpellData:ReconcileAllContainers()
                    FireChangeCallback()
                end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if _cooldownViewerRebuildPending then
                _cooldownViewerRebuildPending = false
                RebuildSpellToCooldownID()
                FireChangeCallback()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Suppress SPELLS_CHANGED dormant checks during zone transitions.
            -- APIs are stale for ~1-2s after entering a new zone/instance.
            _inZoneTransition = true
            C_Timer.After(2.0, function()
                _inZoneTransition = false
                -- Drain a SPELLS_CHANGED that was suppressed while the window
                -- was open. The APIs have settled now, so run the reconcile the
                -- SPELLS_CHANGED handler would have run; otherwise it is lost
                -- (the display stays stale) until the next SPELLS_CHANGED or a
                -- /reload. Combat-guarded like the SPELLS_CHANGED debounce.
                if _spellsChangedDuringZoneTransition then
                    _spellsChangedDuringZoneTransition = false
                    if IsCDMRuntimeEnabled() and not InCombatLockdown()
                        and not ns._cdmColdLoadActive then
                        RunReconcileSequence()
                    end
                end
            end)
            C_Timer.After(1.0, function()
                if not IsCDMRuntimeEnabled() then return end
                if not initialized then
                    -- Blizzard_CooldownManager may have loaded before us
                    ForceLoadCDM()
                    C_Timer.After(0.5, function()
                        if not IsCDMRuntimeEnabled() then return end
                        UpdateCooldownViewerCVar()
                        RegisterEditModeCallbacks()
                        initialized = true
                    end)
                end
            end)
        end
    end)

    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_SpellData", frame = eventFrame }
end

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------
-- Returns the catalog aura spellIDs associated with `spellID`.
-- Aura-instance correlation is runtime-only; stale learned SavedVariable
-- data is cleared during map rebuild and must not contribute links.
function CDMSpellData:GetAuraIDsForSpell(spellID)
    if not spellID then return nil end
    if not next(_spellToCooldownID) then
        RebuildSpellToCooldownID()
    end
    return _auraIDsForSpell[spellID]
end
CDMSpellData.ResolveEntryKind = ResolveEntryKind
CDMSpellData.IsAuraEntry = IsAuraEntry
CDMSpellData.GetContainerDB = GetContainerDB
CDMSpellData.GetEntryListField = GetEntryListField
CDMSpellData.GetCapturedAuraForLookup = GetCapturedAuraForLookup
if ns.CDMAuraRuntime then
    if ns.CDMAuraRuntime.SetApplicationsGetter then
        ns.CDMAuraRuntime.SetApplicationsGetter(GetAuraApplications)
    end
    if ns.CDMAuraRuntime.SetCapturedAuraGetter then
        ns.CDMAuraRuntime.SetCapturedAuraGetter(GetCapturedAuraForLookup)
    end
end

--- Resolve the live spell ID from a Blizzard viewer child, falling back to
--- entry IDs. Used by both icons (tooltips) and bars (name text). Live aura
--- spellID resolution (Roll the Bones cycling, etc.) flows through the
--- caller via C_UnitAuras.GetAuraDataBySpellID.
--- @param entry table  The resolved owned-spell entry.
--- @return number|nil spellID  The current spell ID, or nil.
function CDMSpellData:ResolveDisplaySpellID(entry)
    return entry and (entry.overrideSpellID or entry.spellID or entry.id)
end

--- Resolve the display name for an entry from the spell info source on the
--- entry's own spell ID, falling back to entry.name.
--- @param entry table  The resolved owned-spell entry.
--- @return string name
function CDMSpellData:ResolveDisplayName(entry)
    if entry and entry.isAura then
        local sid = self:ResolveDisplaySpellID(entry)
        if sid then
            -- FontString:SetText handles secret values natively; the source
            -- facade guards the lookup itself.
            local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
            if info and info.name then return info.name end
        end
    end
    return (entry and entry.name) or ""
end

ns.CDMSpellData = CDMSpellData

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING (rebound by cdm_debug.lua's BindAll())
---------------------------------------------------------------------------
function CDMSpellData._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        ShouldDebugAuraState  = d.ShouldAura            or ShouldDebugAuraState
        AuraStateDebug        = d.Aura                  or AuraStateDebug
        FormatAuraMirrorState = d.FormatAuraMirrorState or FormatAuraMirrorState
        FormatIDList          = d.FormatIDList          or FormatIDList
    end
end
end
