--[[
    QUI CDM Icon Renderer

    Applies resolved cooldown/aura state to addon-owned icon frames and owns
    icon runtime refresh, stack text, range tint, and CustomCDM compatibility.
    Frame lifecycle and pooling live in cdm_icon_factory.lua.
]]

local _, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = ns.LSM
local Shared = ns.CDMShared

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMIcons = {}
ns.CDMIcons = CDMIcons
---@type fun(...)
CDMIcons.ChargeDebug = function() end
---@type fun(...)
CDMIcons.DebugStackText = function() end
---@type fun(...)
CDMIcons.DebugSpellEvent = function() end
---@type fun(...)
CDMIcons.DebugIconEvent = function() end
---@type fun(...)
CDMIcons.DebugEntryBuild = function() end
---@type fun(...)
CDMIcons.DebugLayoutFilter = function() end
---@type fun(...)
CDMIcons.EventTracePrint = function() end
CDMIcons.EventTraceAuraInfo = function() return nil end

---------------------------------------------------------------------------
-- IMPORTS
---------------------------------------------------------------------------
local Resolvers = ns.CDMResolvers
local RuntimeQueries = ns.CDMRuntimeQueries
local Sources = ns.CDMSources
local QueryCharges = RuntimeQueries.QueryCharges
local QueryCooldown = RuntimeQueries.QueryCooldown
local QueryDuration = RuntimeQueries.QueryDuration
local QueryOverrideSpell = RuntimeQueries.QueryOverrideSpell
local QueryDisplayCount = RuntimeQueries.QueryDisplayCount
local QuerySpellCount = RuntimeQueries.QuerySpellCount
local _textureCycleCache = Resolvers._textureCycleCache
local GetSpellTexture = Resolvers.GetSpellTexture
local ResolveMacro = Resolvers.ResolveMacro
local GetEntryTexture = Resolvers.GetEntryTexture
local IsAuraEntry = Resolvers.IsAuraEntry
local ResolveAuraActiveState = Resolvers.ResolveAuraActiveState
local GetChargeMetadataDB = RuntimeQueries.GetChargeMetadataDB

local durationBindingStats = { keyBuilds = 0, keyCacheHits = 0, resolvedStateReuses = 0 }
local fullUpdateScheduleStats = {
    total = 0,
    request = 0,
    mirrorFallback = 0,
    runtime = 0,
    deferred = 0,
    hotfix = 0,
    other = 0,
}

do
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_durationBindingKeys", counter = true, fn = function() return durationBindingStats.keyBuilds end }
    mp[#mp + 1] = { name = "CDM_durationBindingKeyCacheHits", counter = true, fn = function() return durationBindingStats.keyCacheHits end }
    mp[#mp + 1] = { name = "CDM_applyResolvedStateReuses", counter = true, fn = function() return durationBindingStats.resolvedStateReuses end }
    mp[#mp + 1] = { name = "CDM_fullUpdateSchedules", counter = true, fn = function() return fullUpdateScheduleStats.total end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleRequest", counter = true, fn = function() return fullUpdateScheduleStats.request end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleMirrorFallback", counter = true, fn = function() return fullUpdateScheduleStats.mirrorFallback end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleRuntime", counter = true, fn = function() return fullUpdateScheduleStats.runtime end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleDeferred", counter = true, fn = function() return fullUpdateScheduleStats.deferred end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleHotfix", counter = true, fn = function() return fullUpdateScheduleStats.hotfix end }
    mp[#mp + 1] = { name = "CDM_fullUpdateScheduleOther", counter = true, fn = function() return fullUpdateScheduleStats.other end }
end

local function GetBuiltinContainerType(containerKey)
    return Shared and Shared.GetBuiltinContainerType
        and Shared.GetBuiltinContainerType(containerKey)
        or nil
end

local function GetBuiltinContainerEntryKind(containerKey)
    return Shared and Shared.GetBuiltinContainerEntryKind
        and Shared.GetBuiltinContainerEntryKind(containerKey)
        or nil
end

local function IsBuiltinCooldownContainerKey(containerKey)
    if Shared and Shared.IsBuiltinCooldownContainerKey then
        return Shared.IsBuiltinCooldownContainerKey(containerKey)
    end
    return GetBuiltinContainerEntryKind(containerKey) == "cooldown"
end

local function IsBuiltinAuraContainerKey(containerKey)
    if Shared and Shared.IsBuiltinAuraContainerKey then
        return Shared.IsBuiltinAuraContainerKey(containerKey)
    end
    return GetBuiltinContainerEntryKind(containerKey) == "aura"
end

local function IsCustomBarContainer(containerDB)
    return Shared and Shared.IsCustomBarContainer
        and Shared.IsCustomBarContainer(containerDB)
        or false
end

local function GetCustomBarVisibilityMode(containerDB)
    return Shared and Shared.GetCustomBarVisibilityMode
        and Shared.GetCustomBarVisibilityMode(containerDB)
        or "always"
end

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local CDMCooldown = ns.CDMCooldown or {}
ns.CDMCooldown = CDMCooldown

function CDMIcons:IsRuntimeEnabled()
    return not Shared or Shared.IsRuntimeEnabled()
end

-- CustomCDM exposed on CDMIcons for engine access (provider wires to ns.CustomCDM)
local CustomCDM = {}
CDMIcons.CustomCDM = CustomCDM

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local CreateFrame = CreateFrame
local GetTime = GetTime
local wipe = wipe
local select = select
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local C_StringUtil = C_StringUtil
local issecretvalue = issecretvalue

local function IsSafeNumeric(val)
    if issecretvalue and issecretvalue(val) then return false end
    return Shared and Shared.IsSafeNumeric(val) or type(val) == "number"
end

local _resolverRuntimePolicy = {}

local function SafeBoolean(val)
    if issecretvalue and issecretvalue(val) then
        return nil
    end
    if Shared and Shared.SafeBoolean then
        return Shared.SafeBoolean(val)
    end
    if type(val) == "boolean" then
        return val
    end
    return nil
end

local function SafeRuntimeString(val)
    if issecretvalue and issecretvalue(val) then
        return nil
    end
    if type(val) == "string" and val ~= "" then
        return val
    end
    return nil
end

function _resolverRuntimePolicy.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
    if ns.CDMRenderers and ns.CDMRenderers.ApplyDurationObjectCooldown then
        return ns.CDMRenderers.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
    end

    if not cd or not durObj or not cd.SetCooldownFromDurationObject then
        return false
    end

    if clearWhenZero == nil then
        clearWhenZero = true
    end

local applied = true; cd.SetCooldownFromDurationObject(cd, durObj, clearWhenZero)
    if reverse ~= nil and cd.SetReverse then
        cd.SetReverse(cd, reverse and true or false)
    end
    return applied and true or false
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
local DEFAULT_ICON_SIZE = 39
local BASE_CROP = 0.08
local ICON_FRAME_LEVEL_OFFSET = 1
local COOLDOWN_FRAME_LEVEL_OFFSET = 1
local TEXT_OVERLAY_FRAME_LEVEL_OFFSET = 6
local COOLDOWN_EXPIRY_REFRESH_FUDGE = 0.2
local COOLDOWN_EXPIRY_RESCHEDULE_EPSILON = 0.1

---------------------------------------------------------------------------
-- POOL STATE ALIASES
-- iconPools and recyclePool live in cdm_icon_factory.lua; aliased here as
-- upvalues so direct references in this file resolve without a mass rewrite.
---------------------------------------------------------------------------
local iconPools   = ns.CDMIconFactory._iconPools
local recyclePool = ns.CDMIconFactory._recyclePool
local Factory = ns.CDMIconFactory
local SyncCooldownBling  = Factory.SyncCooldownBling
local UpdateIconCooldown
local UpdateIconSecureAttributes
local SetStackTextWritesForBatch
local SyncSpellRangeChecks
local DisableSpellRangeChecks
local GetTrackerSettings
local stackPolicy
local GetAuraApplicationsForSpell
local customBarPolicy
local refreshBatch
local refreshWalker
local itemVisualPolicy
local ApplyVisibleMirrorStackTextIfNeeded
local GetCachedMirrorStateForIcon
local RefreshCachedMirrorStateForIcon

local cooldownPolicy = ns.CDMIconCooldownPolicy and ns.CDMIconCooldownPolicy.Create({
    getMirror = function()
        return ns.CDMBlizzMirror
    end,
    getCachedMirrorStateForIcon = function(icon)
        return GetCachedMirrorStateForIcon and GetCachedMirrorStateForIcon(icon) or nil
    end,
    refreshCachedMirrorStateForIcon = function(icon)
        return RefreshCachedMirrorStateForIcon and RefreshCachedMirrorStateForIcon(icon) or nil
    end,
    queryCooldown = function(spellID, owner)
        return QueryCooldown and QueryCooldown(spellID, owner) or nil
    end,
    queryOverrideSpell = function(spellID)
        return QueryOverrideSpell and QueryOverrideSpell(spellID) or nil
    end,
})

local function CreateIconRefreshBatch()
    local module = ns.CDMIconRefreshBatch
    if not (module and module.Create) then return nil end
    return module.Create({
        getMemProbes = function()
            local mp = ns._memprobes or {}
            ns._memprobes = mp
            return mp
        end,
        isEditModeActive = function()
            return Helpers.IsEditModeActive()
        end,
        isLayoutModeActive = function()
            return Helpers.IsLayoutModeActive()
        end,
        isGlobalEditModeActive = function()
            return _G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive()
        end,
        getNCDM = function()
            return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
        end,
        getTime = function()
            return GetTime()
        end,
        isInCombat = function()
            return InCombatLockdown()
        end,
        refreshSwipeBatchSettings = function()
            return _resolverRuntimePolicy.RefreshSwipeBatchSettings()
        end,
        beginRuntimeQueryBatch = function()
            if RuntimeQueries and RuntimeQueries.BeginRuntimeQueryBatch then
                RuntimeQueries.BeginRuntimeQueryBatch()
            end
        end,
        endRuntimeQueryBatch = function()
            if RuntimeQueries and RuntimeQueries.EndRuntimeQueryBatch then
                RuntimeQueries.EndRuntimeQueryBatch()
            end
        end,
        setStackTextWrites = function(enabled)
            if SetStackTextWritesForBatch then
                SetStackTextWritesForBatch(enabled)
            end
        end,
    })
end

refreshBatch = CreateIconRefreshBatch()

_resolverRuntimePolicy.eventProfileStats = {}
_resolverRuntimePolicy.eventProfileLast = {
    time = GetTime and GetTime() or 0,
    counts = {},
    ms = {},
}

function CDMIcons.RecordEventProfile(event, elapsedMS)
    if not event then return end
    local stats = _resolverRuntimePolicy.eventProfileStats[event]
    if not stats then
        stats = { calls = 0, ms = 0 }
        _resolverRuntimePolicy.eventProfileStats[event] = stats
    end
    stats.calls = stats.calls + 1
    stats.ms = stats.ms + (elapsedMS or 0)
end

function CDMIcons.SnapshotEventProfile(limit)
    local now = GetTime and GetTime() or 0
    local last = _resolverRuntimePolicy.eventProfileLast
    local elapsed = now - (last.time or now)
    if elapsed <= 0 then elapsed = 1 end

    local rows = {}
    for event, stats in pairs(_resolverRuntimePolicy.eventProfileStats) do
        local prevCalls = last.counts[event] or 0
        local prevMS = last.ms[event] or 0
        local calls = (stats.calls or 0) - prevCalls
        local ms = (stats.ms or 0) - prevMS
        if calls > 0 or ms > 0 then
            rows[#rows + 1] = {
                event = event,
                calls = calls,
                ms = ms,
                callsPerSec = calls / elapsed,
                msPerSec = ms / elapsed,
            }
        end
        last.counts[event] = stats.calls or 0
        last.ms[event] = stats.ms or 0
    end
    last.time = now

    table.sort(rows, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        return a.calls > b.calls
    end)
    limit = limit or 5
    while #rows > limit do
        rows[#rows] = nil
    end
    return rows, elapsed
end

---------------------------------------------------------------------------
-- DEBUG: Charge/stack transform debugging.
-- Enable via:  /run QUI_CDM_CHARGE_DEBUG = true
-- Disable via: /run QUI_CDM_CHARGE_DEBUG = false
-- Optionally filter to a specific spell name:
--   /run QUI_CDM_CHARGE_DEBUG = "Holy Bulwark"
-- Implementation lives in the load-on-demand debug addon. The placeholder
-- below is rebound by cdm_debug.lua's BindAll() when loaded.
---------------------------------------------------------------------------
---@type fun(...)
local ChargeDebug = function() end
CDMIcons._ShouldDebugBlizzEntry = function() return false end
CDMIcons._FormatMirrorState     = function() return "nil" end
---@type fun(...)
CDMIcons._DebugBlizzEntry       = function() end

---------------------------------------------------------------------------
-- DYNAMIC CHILD LOOKUP: Scan ALL viewer children to find the one with
-- auraInstanceID matching a tracked spell.  Blizzard recycles children
-- across auras, so the child→spell assignment changes at runtime.
-- Child lookup infrastructure lives in cdm_spelldata.lua (shared by icons + bars).
---------------------------------------------------------------------------
local function IsTotemSlotEntry(entry)
    return entry and entry._isTotemInstance and entry._totemSlot ~= nil
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
-- PROFESSION QUALITY OVERLAY
-- Renders a crafted/reagent quality badge atop item/trinket/slot icons when
-- the container opts in via showProfessionQuality.
---------------------------------------------------------------------------
local function CreateIconItemVisualPolicy()
    local module = ns.CDMIconItemVisualPolicy
    if not (module and module.Create) then return nil end
    return module.Create({
        getNCDM = function()
            return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
        end,
        resolveBestOwnedItemVariant = function(itemID)
            return (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(itemID)) or itemID
        end,
        queryInventoryItemLink = function(unit, slotID)
            return Sources and Sources.QueryInventoryItemLink and Sources.QueryInventoryItemLink(unit, slotID)
        end,
        queryInventoryItemID = function(unit, slotID)
            return Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID(unit, slotID)
        end,
        queryItemIconByID = function(itemID)
            return Sources and Sources.QueryItemIconByID and Sources.QueryItemIconByID(itemID)
        end,
        queryItemInfoInstant = function(itemID)
            if Sources and Sources.QueryItemInfoInstant then
                return Sources.QueryItemInfoInstant(itemID)
            end
        end,
        updateSecureAttributes = function(icon, entry, viewerType)
            if UpdateIconSecureAttributes then
                UpdateIconSecureAttributes(icon, entry, viewerType)
            end
        end,
    })
end

itemVisualPolicy = CreateIconItemVisualPolicy()

local function ClearIconProfessionQuality(icon)
    if itemVisualPolicy then
        itemVisualPolicy:ClearProfessionQuality(icon)
    end
end

local function UpdateIconProfessionQuality(icon)
    if itemVisualPolicy then
        itemVisualPolicy:UpdateProfessionQuality(icon)
    end
end

local function QueryItemVisualTexture(itemID)
    if itemVisualPolicy then
        return itemVisualPolicy:GetItemTexture(itemID)
    end
    if Sources and Sources.QueryItemIconByID then
        local texture = Sources.QueryItemIconByID(itemID)
        if texture then return texture end
    end
    if Sources and Sources.QueryItemInfoInstant then
        local _, _, _, _, texture = Sources.QueryItemInfoInstant(itemID)
        return texture
    end
    return nil
end
---------------------------------------------------------------------------
-- ITEM COOLDOWN RESOLUTION
---------------------------------------------------------------------------

local function GetItemCooldown(itemID)
    if not itemID or not (Sources and Sources.QueryItemCooldown) then return nil, nil, nil end
    return Sources.QueryItemCooldown(itemID)
end

local function GetSlotCooldown(slotID)
    if not slotID or not GetInventoryItemCooldown then return nil, nil, nil end
    local ok, startTime, duration, enabled = pcall(GetInventoryItemCooldown, "player", slotID)
    if not ok then return nil, nil, nil end
    return startTime, duration, enabled
end

function _resolverRuntimePolicy.MarkGCDSwipe(icon)
    if cooldownPolicy then
        cooldownPolicy:MarkGCDSwipe(icon)
    end
end

function _resolverRuntimePolicy.ClearGCDSwipe(icon)
    if cooldownPolicy then
        cooldownPolicy:ClearGCDSwipe(icon)
    end
end

-- Expose inventory cooldown adapters for cdm_resolvers.lua + cdm_bar_renderer.lua.
CDMCooldown.GetItemCooldown = GetItemCooldown
CDMCooldown.GetSlotCooldown = GetSlotCooldown

---------------------------------------------------------------------------
-- SWIPE STYLING
---------------------------------------------------------------------------

-- Re-apply QUI swipe styling to the addon-owned CooldownFrame.
local function ReapplySwipeStyle(cd, icon)
    if not cd then return end
    if cd.SetSwipeTexture then
        cd.SetSwipeTexture(cd, "Interface\\Buttons\\WHITE8X8")
    end
    local CooldownSwipe = ns._OwnedSwipe or (QUI and QUI.CooldownSwipe)
    if CooldownSwipe and CooldownSwipe.ApplyToIcon then
        CooldownSwipe.ApplyToIcon(icon)
    end
    if _resolverRuntimePolicy.ApplyCustomBarSwipeStyle then
        _resolverRuntimePolicy.ApplyCustomBarSwipeStyle(icon)
    end
end

local function IsGCDSwipeEnabled()
    local swipe = ns._OwnedSwipe
    local settings = swipe and swipe.GetSettings and swipe.GetSettings()
    return settings and settings.showGCDSwipe == true
end
CDMIcons.IsGCDSwipeEnabled = IsGCDSwipeEnabled

local function GetAuraDataInstanceID(auraData)
    if not auraData then return nil end
    return auraData.auraInstanceID
end

local function GetAuraDisplaySourceID(r, fallbackID)
    if not r then return fallbackID end
    local sourceID = r.auraInstanceID or r.totemSlot
    return sourceID or fallbackID
end

local function ClearPandemicStateForIcon(icon)
    if not icon then return end
    icon._blizzPandemicActive = nil
    icon._blizzPandemicStateKnown = nil

    local glows = ns._OwnedGlows
    if glows and glows.ClearPandemicState then
        glows.ClearPandemicState(icon)
    elseif icon.PandemicGlow then
        icon.PandemicGlow:SetAlpha(0)
    end
end

local function ClearAuraStateForIcon(icon, entry)
    if not icon then return end
    local hadAuraState = icon._auraActive == true
        or icon._lastAuraDurObj ~= nil
        or icon._blizzPandemicStateKnown == true
        or icon.PandemicGlow ~= nil
    icon._auraActive = false
    icon._auraUnit = nil
    icon._auraInstanceID = nil
    icon._totemSlot = entry and entry._totemSlot or nil
    icon._isTotemInstance = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
    icon._activeAuraSpellID = nil
    icon._auraIsHarmful = nil
    if hadAuraState then
        ClearPandemicStateForIcon(icon)
    end
end

local function ApplyAuraStateToIcon(icon, entry, sid, r)
    if not r then
        ClearAuraStateForIcon(icon, entry)
        return nil, false, nil
    end

    local auraActive = r.auraActive
    if auraActive == nil then
        auraActive = r.isActive
    end

    if auraActive then
        local sourceID = GetAuraDisplaySourceID(r, sid)
        icon._auraActive = true
        icon._auraUnit = r.auraUnit
        icon._auraInstanceID = r.auraInstanceID
        icon._totemSlot = r.totemSlot or entry._totemSlot or nil
        icon._isTotemInstance = r.isTotemInstance and true or nil
        icon._activeAuraSpellID = r.resolvedAuraSpellID
        if not icon._activeAuraSpellID and r.auraData then
            local sid2 = r.auraData.spellId
            if type(sid2) == "number" and sid2 > 0 then
                icon._activeAuraSpellID = sid2
            end
        end
        if not icon._activeAuraSpellID and sid then
            icon._activeAuraSpellID = sid
        end

        -- Capture aura type (harmful vs helpful) for pandemic glow gating.
        -- isHarmful is treated as non-secret in this codebase (see
        -- cdm_spelldata.lua's GetUnitAuraBySpellID comment). When auraData
        -- is nil under combat lockdown, preserve any prior value rather
        -- than clobbering — the type doesn't change for a given aura
        -- instance.
        if r.auraData then
            local harmful = r.auraData.isHarmful
            if type(harmful) == "boolean" then
                icon._auraIsHarmful = harmful and true or false
            end
        end

        if r.durObj then
            icon._lastAuraDurObj = r.durObj
            icon._lastAuraSourceID = sourceID
            return r.durObj, true, sourceID
        end

        if r.durationStateUnknown and icon._lastAuraDurObj then
            return icon._lastAuraDurObj, true, icon._lastAuraSourceID or sourceID
        end

        icon._lastAuraDurObj = nil
        icon._lastAuraSourceID = sourceID
        return nil, true, sourceID
    end

    ClearAuraStateForIcon(icon, entry)
    return nil, false, nil
end

local function ApplyMirrorPayloadToIcon(icon, entry, sid, payload)
    if not (icon and payload and payload.mirrorBacked == true) then
        return
    end

    if payload.mode == "aura" then
        local r = icon._mirrorAuraResult
        if not r then
            r = {}
            icon._mirrorAuraResult = r
        end
        r.isActive = payload.active == true
        r.auraActive = payload.auraActive
        if r.auraActive == nil then
            r.auraActive = payload.active == true
        end
        r.auraInstanceID = payload.auraInstanceID
        r.auraUnit = payload.auraUnit
        r.durObj = payload.durObj
        r.auraData = payload.auraData
        -- payload.count is a singleton scratch (BuildMirrorCountPayload pool),
        -- not safe to alias across calls — copy fields into a per-icon table.
        local rc = r.count
        if not rc then
            rc = {}
            r.count = rc
        end
        local pc = payload.count
        if pc then
            rc.value = pc.value
            rc.sinkText = pc.sinkText
            rc.shown = pc.shown
            rc.source = pc.source
        else
            rc.value = nil
            rc.sinkText = nil
            rc.shown = false
            rc.source = nil
        end
        r.resolvedAuraSpellID = payload.spellID
        r.hasExpirationTime = payload.hasExpirationTime
        r.hideDurationText = payload.hideDurationText
        r.durationStateUnknown = payload.durationStateUnknown
        r.totemSlot = payload.totemSlot
        r.totemName = payload.totemName
        r.totemIcon = payload.totemIcon
        r.isTotemInstance = payload.isTotemInstance and true or false
        ApplyAuraStateToIcon(icon, entry, sid, r)
    else
        ClearAuraStateForIcon(icon, entry)
    end
end

---------------------------------------------------------------------------
-- ResolveIconStackText: kind-dispatched stack/charge text resolver.
-- Returns (text, source) where:
--   text   = string for FontString:SetText (may be secret in combat — DO
--            NOT compare in Lua, only forward to SetText)
--   source = "Applications" | "ChargeCount" | nil (informational; drives
--            styling decisions equivalent to the legacy hook source)
-- Aura-kind: stacks via the CDMAuraRuntime application getter, which wraps
-- C_UnitAuras.GetAuraApplicationDisplayCount with IsSecretValue-aware caching.
-- Cooldown-kind: mirror-backed icons trust Blizzard's charge-count fields
-- as authoritative. Non-mirrored multi-charge fallback still uses
-- C_Spell.GetSpellDisplayCount, gated by cached maxCharges > 1.
---------------------------------------------------------------------------
function _resolverRuntimePolicy.ResolveIconStackText(icon)
    if stackPolicy then
        return stackPolicy:ResolveIconStackText(icon)
    end
    return nil
end

function _resolverRuntimePolicy.ResolveMirrorStackText(icon)
    if stackPolicy then
        return stackPolicy:ResolveMirrorStackText(icon)
    end
    return nil
end

local function ResolveTrackerSettingsNow(viewerType)
    if type(GetTrackerSettings) == "function" then
        return GetTrackerSettings(viewerType)
    end
    local db = GetDB and GetDB()
    if not db or not viewerType then return nil end
    return db[viewerType] or (db.containers and db.containers[viewerType]) or nil
end

local function IsCustomBarSettingsNow(settings)
    return IsCustomBarContainer(settings)
end

-- For a multi-charge spell where the recharge IS the cooldown (DK Death
-- Charge is the reference case), the resolver classifies mode=cooldown
-- both at 1+ charges (recharge rolling, spell castable) and at 0 charges
-- (real cooldown, spell uncastable). cdInfo.isActive on
-- C_Spell.GetSpellCooldown distinguishes them:
--   false → 1+ charges available → saturated
--   true  → all charges spent     → desaturated
-- cdInfo.isActive is NeverSecret (see cdm_blizz_mirror.lua:300), so a
-- direct Lua comparison is safe; no curve indirection needed. Returns
-- true when this gate decided the spell should stay saturated.
local function ChargeSpellShouldStaySaturated(icon, entry)
    local sid = icon and icon._runtimeSpellID
    if not sid and entry then
        sid = entry.spellID or entry.overrideSpellID or entry.id
    end
    if not sid then return false end
    local cdInfo = QueryCooldown(sid)
    if not cdInfo then return false end
    return cdInfo.isActive == false
end

-- Step curve mapping the real-CD-only remaining-percent to a desaturation
-- amount for Texture:SetDesaturation: 0% remaining (real CD done / GCD-only /
-- ready) -> 0 (saturated/bright); any positive remaining (real CD rolling) ->
-- 1 (desaturated/dark). The near-instant 0..0.02 ramp keeps the snap crisp.
-- Built once and reused; the DurationObject supplies the live timing C-side.
local _cooldownDesatCurve = nil   -- nil = unbuilt, false = CurveUtil unavailable
local function GetCooldownDesatCurve()
    if _cooldownDesatCurve ~= nil then
        return _cooldownDesatCurve or nil
    end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then
        _cooldownDesatCurve = false
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    curve:AddPoint(-1.0, 0)  -- expired / negative percent -> bright
    curve:AddPoint(0.0, 0)   -- 0% remaining -> bright
    curve:AddPoint(0.02, 1)  -- any meaningful remaining -> dark
    curve:AddPoint(1.0, 1)   -- full -> dark
    _cooldownDesatCurve = curve
    return curve
end

local function ApplyCooldownDesaturation(icon, entry, settings, resolvedMode, resolvedSpellID, resolvedDurObj)
    if not icon or not entry or not icon.Icon or not icon.Icon.SetDesaturated then
        return
    end

    settings = settings or ResolveTrackerSettingsNow(entry.viewerType)
    resolvedMode = resolvedMode or icon._resolvedCooldownMode

    local showOnlyCooldownMode = settings and settings.showOnlyOnCooldown == true
    local customBar = IsCustomBarSettingsNow(settings)
    local auraBlocks = (icon._auraActive or (customBar and icon._customBarActive))
        and not icon._desaturateIgnoreAura
        and not showOnlyCooldownMode

    local shouldDesaturate = settings and settings.desaturateOnCooldown
    local desatOverride = icon._spellOverrideDesaturate
    if desatOverride == true then
        shouldDesaturate = true
    elseif desatOverride == false then
        shouldDesaturate = false
    end

    local hasRealCD = icon._hasCooldownActive == true
        and resolvedMode ~= "aura"
        and resolvedMode ~= "gcd-only"
        and resolvedMode ~= "inactive"

    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(entry.name, "DESAT result: hasRealCD=", hasRealCD,
            "_hasCooldownActive=", icon._hasCooldownActive,
            "mode=", tostring(resolvedMode),
            "entryHasCharges=", entry.hasCharges,
            "viewerType=", entry.viewerType)
    end

    -- Charge spells: stay saturated while at least one charge is available.
    -- Matches Blizzard CooldownViewer CheckCacheCooldownValuesFromCharges,
    -- which sets cooldownDesaturated=false AND claims the visual data source
    -- (wasSetFromCharges) exactly when the charge cooldown is rolling and
    -- currentCharges > 0 — so its spell-cooldown desaturation branch never
    -- runs. wasSetFromCharges is a NeverSecret mirror flag, the authoritative
    -- secret-safe "≥1 charge banked" signal (currentCharges itself is secret
    -- in combat and cannot be compared in Lua). It is the only correct signal
    -- for spells like Putrefy whose recharge reports
    -- GetSpellCooldown().isActive == true throughout, even with charges
    -- available. The cdInfo.isActive == false fallback in
    -- ChargeSpellShouldStaySaturated still covers non-mirrored charge spells
    -- and the brez pool / DK Death Charge case (isActive == false while a
    -- charge remains).
    if shouldDesaturate then
        local mirrorState = _resolverRuntimePolicy.GetIconMirrorState
            and _resolverRuntimePolicy.GetIconMirrorState(icon)
        if mirrorState and SafeBoolean(mirrorState.wasSetFromCharges) == true then
            shouldDesaturate = false
        elseif (entry.hasCharges == true or entry.charges == true)
            and ChargeSpellShouldStaySaturated(icon, entry) then
            shouldDesaturate = false
        end
    end

    -- Desaturation gate: range and usability tints are independent visual
    -- layers and must not factor in here (range red on top of a
    -- desaturated icon is the intended composite).
    local gatesAllowCooldownDesat = entry.viewerType ~= "buff"
        and not auraBlocks
        and shouldDesaturate

    -- _cdDesaturated is the ownership flag the range/usability grey-out reads
    -- (UpdateIconRangeUsability, ~cdm_icon_renderer.lua:9790/9801): it means
    -- "cooldown-desat owns the desaturation channel, don't stomp it". Track the
    -- resolved mode here exactly as the pre-curve code did so that coordination
    -- is byte-for-byte unchanged; only the VISUAL saturation moves to the live
    -- curve drive below.
    icon._cdDesaturated = (gatesAllowCooldownDesat and hasRealCD) and true or nil

    if not gatesAllowCooldownDesat then
        icon.Icon:SetDesaturated(false)
        return
    end

    -- Live, secret-safe saturation drive. resolvedMode is Lua-decoded and only
    -- re-decided on the next SPELL_UPDATE_COOLDOWN, so a mode-gated
    -- SetDesaturated lagged the real-CD->GCD transition by up to a GCD (the
    -- icon stayed dark for seconds after the real cooldown ended -- see the
    -- ApplyResolvedCooldown call site). Instead bind the real-CD-only
    -- (ignoreGCD) DurationObject through a step curve straight into
    -- SetDesaturation: dark while the real CD rolls, bright the instant it
    -- reaches zero, re-sampled C-side every frame with the secret value never
    -- read in Lua. GCD-only / ready periods report zero real-CD remaining ->
    -- 0 -> bright. Falls back to the mode-based boolean only when the
    -- DurationObject or CurveUtil is unavailable.
    local realCdDur = resolvedMode == "item-cooldown" and resolvedDurObj or nil
    if not realCdDur and resolvedSpellID and Sources and Sources.QuerySpellCooldownDuration then
        realCdDur = Sources.QuerySpellCooldownDuration(resolvedSpellID, true)
    end
    local curve = realCdDur and GetCooldownDesatCurve()
    if realCdDur and curve and realCdDur.EvaluateRemainingPercent
        and icon.Icon.SetDesaturation then
        icon.Icon:SetDesaturation(realCdDur:EvaluateRemainingPercent(curve))
        return
    end

    -- Fallback: mode-based boolean (pre-curve behavior).
    icon.Icon:SetDesaturated(hasRealCD == true)
end

local GetRecentCastAliasForEntry
local RecordRecentPlayerSpellCast
local ApplyResolvedCooldown

local function CancelCooldownExpiryRefresh(icon)
    if not icon then return end

    local timer = icon._cooldownExpiryTimer
    if timer and timer.Cancel then
        timer.Cancel(timer)
    end
    icon._cooldownExpiryTimer = nil
    icon._cooldownExpiryTimerKey = nil
    icon._cooldownExpiryAt = nil
end
local function ScheduleCooldownExpiryRefreshAt(icon, key, expiresAt)
    if not icon or not key or not C_Timer then return end
    if not GetTime or not IsSafeNumeric(expiresAt) then return end
    if not (C_Timer.NewTimer or C_Timer.After) then return end

    local delta = icon._cooldownExpiryAt and (icon._cooldownExpiryAt - expiresAt) or nil
    if delta and delta < 0 then delta = -delta end
    if icon._cooldownExpiryTimerKey == key
       and delta
       and delta <= COOLDOWN_EXPIRY_RESCHEDULE_EPSILON then
        return
    end

    local existing = icon._cooldownExpiryTimer
    if existing and existing.Cancel then
        existing.Cancel(existing)
    end

    local delay = expiresAt - GetTime()
    if delay < 0 then delay = 0 end
    delay = delay + COOLDOWN_EXPIRY_REFRESH_FUDGE

    icon._cooldownExpiryTimerKey = key
    icon._cooldownExpiryAt = expiresAt

    local function refresh()
        if icon._cooldownExpiryTimerKey ~= key
           or icon._cooldownExpiryAt ~= expiresAt then
            return
        end
        icon._cooldownExpiryTimer = nil
        icon._cooldownExpiryTimerKey = nil
        icon._cooldownExpiryAt = nil
        -- Re-resolve this icon after its scheduled cooldown expiry. Runtime
        -- spell queries are fresh; the invalidation call is now compatibility.
        if ApplyResolvedCooldown then
            ApplyResolvedCooldown(icon)
        end
    end

    if C_Timer.NewTimer then
        icon._cooldownExpiryTimer = C_Timer.NewTimer(delay, refresh)
    elseif C_Timer.After then
        icon._cooldownExpiryTimer = nil
        C_Timer.After(delay, refresh)
    end
end

local function ScheduleCooldownExpiryRefresh(icon, key, cdInfo)
    if not icon or not key or not cdInfo or not C_Timer then return end
    if not GetTime then return end

    -- cdInfo.startTime / cdInfo.duration may be secret whenever the Blizzard
    -- CDM data feed is active (CVar=1) — combat lockdown is not a tight enough
    -- proxy because tainted execution can persist across UNIT_AURA / event
    -- coalesce edges OOC. Skip scheduling and let event-driven refresh
    -- (SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_USABLE) handle completion. The
    -- C-side DurationObject still drives the visible swipe; this Lua timer
    -- is just a fast-path for clearing _hasCooldownActive after expiry.
    local getCooldownInfoField = Resolvers and Resolvers.GetCooldownInfoField
    if not getCooldownInfoField then return end

    local start = getCooldownInfoField(cdInfo, "startTime")
    if start == nil then
        start = getCooldownInfoField(cdInfo, "start")
    end
    local duration = getCooldownInfoField(cdInfo, "duration")
    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then
        if icon._cooldownExpiryTimerKey and icon._cooldownExpiryTimerKey ~= key then
            CancelCooldownExpiryRefresh(icon)
        end
        return
    end
    if type(start) ~= "number" or type(duration) ~= "number" then
        if icon._cooldownExpiryTimerKey and icon._cooldownExpiryTimerKey ~= key then
            CancelCooldownExpiryRefresh(icon)
        end
        return
    end
    if start <= 0 or duration <= 0 then
        CancelCooldownExpiryRefresh(icon)
        return
    end

    ScheduleCooldownExpiryRefreshAt(icon, key, start + duration)
end

function _resolverRuntimePolicy.GetIconMirrorState(icon)
    return cooldownPolicy and cooldownPolicy:GetIconMirrorState(icon) or nil
end

function _resolverRuntimePolicy.MirrorStateIsActive(state)
    return cooldownPolicy and cooldownPolicy:MirrorStateIsActive(state) or false
end

function _resolverRuntimePolicy.ClearIconChargeMirrorCycle(icon)
    if cooldownPolicy then
        cooldownPolicy:ClearIconChargeMirrorCycle(icon)
    end
end

function _resolverRuntimePolicy.RememberIconChargeMirrorCycle(icon, runtimeSpellID)
    if cooldownPolicy then
        cooldownPolicy:RememberIconChargeMirrorCycle(icon, runtimeSpellID)
    end
end

function _resolverRuntimePolicy.UpdateIconChargeMirrorCycle(icon, mode, runtimeSpellID, hasCharges)
    if cooldownPolicy then
        cooldownPolicy:UpdateIconChargeMirrorCycle(icon, mode, runtimeSpellID, hasCharges)
    end
end

function _resolverRuntimePolicy.MirrorPayloadHasChargeState(mirrorPayload)
    return cooldownPolicy and cooldownPolicy:MirrorPayloadHasChargeState(mirrorPayload) or false
end

function _resolverRuntimePolicy.MirrorPayloadMatchesRecentChargeCycle(icon, mirrorPayload)
    return cooldownPolicy
        and cooldownPolicy:MirrorPayloadMatchesRecentChargeCycle(icon, mirrorPayload)
        or false
end

function _resolverRuntimePolicy.IsRealCooldownDurationMode(mode)
    return mode == "cooldown"
        or mode == "item-cooldown"
end

local function BuildDurationBindingKey(mode, sourceID)
    local sourceType = type(sourceID)
    if (sourceType == "number" or sourceType == "string")
        and type(mode) == "string"
        and not (issecretvalue and issecretvalue(sourceID))
        and (mode == "gcd-only" or _resolverRuntimePolicy.IsRealCooldownDurationMode(mode)) then
        local cache = _resolverRuntimePolicy.durationBindingKeyCache
        if not cache then
            cache = {}
            _resolverRuntimePolicy.durationBindingKeyCache = cache
        end
        local modeCache = cache[mode]
        if not modeCache then
            modeCache = {}
            cache[mode] = modeCache
        end
        local typeCache = modeCache[sourceType]
        if not typeCache then
            typeCache = {}
            modeCache[sourceType] = typeCache
        end
        local key = typeCache[sourceID]
        if key then
            durationBindingStats.keyCacheHits = durationBindingStats.keyCacheHits + 1
            return key
        end
        key = mode .. ":" .. tostring(sourceID)
        typeCache[sourceID] = key
        durationBindingStats.keyBuilds = durationBindingStats.keyBuilds + 1
        return key
    end

    durationBindingStats.keyBuilds = durationBindingStats.keyBuilds + 1
    return mode .. ":" .. tostring(sourceID)
end

function _resolverRuntimePolicy.ClearDurationBindingKeyCache()
    _resolverRuntimePolicy.durationBindingKeyCache = nil
end

local function DurationBindingSourceCanCompare(sourceID)
    return not (issecretvalue and issecretvalue(sourceID))
end

function _resolverRuntimePolicy.DurationBindingSourcesMatch(left, right)
    if not DurationBindingSourceCanCompare(left)
        or not DurationBindingSourceCanCompare(right) then
        return false
    end

    local leftType = type(left)
    local rightType = type(right)
    if leftType == rightType then
        return left == right
    end
    if leftType == "number" and rightType == "string" then
        return tonumber(right) == left
    end
    if leftType == "string" and rightType == "number" then
        return tonumber(left) == right
    end
    return false
end

function _resolverRuntimePolicy.DurationBindingFieldMatches(icon, mode, sourceID)
    return icon
        and icon._lastResolvedMode == mode
        and _resolverRuntimePolicy.DurationBindingSourcesMatch(icon._lastResolvedSourceID, sourceID)
end

function _resolverRuntimePolicy.DurationBindingLegacyKeyMatches(icon, mode, sourceID)
    local key = icon and icon._lastDurObjKey
    if type(key) ~= "string" or type(mode) ~= "string" then return false end
    if not DurationBindingSourceCanCompare(sourceID) then return false end

    local modeLength = #mode
    local sourceStart = modeLength + 2
    if key:byte(modeLength + 1) ~= 58 then return false end
    if key:find(mode, 1, true) ~= 1 then return false end

    local sourceType = type(sourceID)
    if sourceType == "string" then
        if key:find(sourceID, sourceStart, true) ~= sourceStart then return false end
        if sourceStart + #sourceID - 1 ~= #key then return false end
    elseif sourceType == "number" then
        local numericSource = tonumber(key:sub(sourceStart))
        if numericSource ~= sourceID then return false end
    else
        return false
    end

    icon._lastResolvedMode = mode
    icon._lastResolvedSourceID = sourceID
    return true
end

local function DurationBindingMatches(icon, mode, sourceID, durObj, mirrorBackedDuration)
    if not icon then return false end

    local sameBinding = _resolverRuntimePolicy.DurationBindingFieldMatches(icon, mode, sourceID)
        or _resolverRuntimePolicy.DurationBindingLegacyKeyMatches(icon, mode, sourceID)

    if not sameBinding then return false end
    if mode == "aura" then
        return durObj == icon._lastDurObj
    end
    if mode == "gcd-only" and mirrorBackedDuration == true then
        if issecretvalue and (issecretvalue(durObj) or issecretvalue(icon._lastDurObj)) then
            return false
        end
        return durObj == icon._lastDurObj
    end
    return true
end

local function GetDurationBindingKey(icon, mode, sourceID)
    local key = icon and icon._lastDurObjKey
    if type(key) == "string"
        and (_resolverRuntimePolicy.DurationBindingFieldMatches(icon, mode, sourceID)
            or _resolverRuntimePolicy.DurationBindingLegacyKeyMatches(icon, mode, sourceID)) then
        return key
    end
    return BuildDurationBindingKey(mode, sourceID)
end

local _iconCooldownStateContextOptions = {
    mirrorIdentityPolicy = "frame-or-entry",
}

local function NormalizeIconMirrorCategory(category)
    if Shared and Shared.NormalizeMirrorCategory then
        return Shared.NormalizeMirrorCategory(category)
    end
    if category == "essential"
        or category == "utility"
        or category == "buff"
        or category == "trackedBar" then
        return category
    end
    return nil
end

local function ResolveIconMirrorCategory(icon)
    local entry = icon and icon._spellEntry
    return NormalizeIconMirrorCategory(icon and icon._blizzMirrorCategory)
        or NormalizeIconMirrorCategory(entry and entry.blizzardMirrorCategory)
        or NormalizeIconMirrorCategory(entry and entry.viewerCategory)
        or NormalizeIconMirrorCategory(entry and entry.viewerType)
end

local function StoreCachedMirrorStateForIcon(icon, cooldownID, category, state)
    if not icon then return end
    if state and cooldownID and category then
        local epoch = state.mirrorEpoch
        icon._blizzMirrorState = state
        icon._blizzMirrorStateCooldownID = cooldownID
        icon._blizzMirrorStateCategory = category
        if icon._blizzMirrorSourceCooldownID ~= cooldownID
            or icon._blizzMirrorSourceEpoch ~= epoch then
            icon._blizzMirrorSourceID = "mirror:" .. tostring(cooldownID) .. ":" .. tostring(epoch)
            icon._blizzMirrorSourceCooldownID = cooldownID
            icon._blizzMirrorSourceEpoch = epoch
        end
    else
        icon._blizzMirrorState = nil
        icon._blizzMirrorStateCooldownID = nil
        icon._blizzMirrorStateCategory = nil
        icon._blizzMirrorSourceID = nil
        icon._blizzMirrorSourceCooldownID = nil
        icon._blizzMirrorSourceEpoch = nil
    end
end

GetCachedMirrorStateForIcon = function(icon)
    if not icon then return nil end
    local cooldownID = icon._blizzMirrorCooldownID
    local category = ResolveIconMirrorCategory(icon)
    if not (cooldownID and category) then return nil end

    if icon._blizzMirrorStateCooldownID == cooldownID
        and icon._blizzMirrorStateCategory == category then
        return icon._blizzMirrorState
    end
    return nil
end

RefreshCachedMirrorStateForIcon = function(icon)
    if not icon then return nil end
    local cooldownID = icon._blizzMirrorCooldownID
    local category = ResolveIconMirrorCategory(icon)
    if not (cooldownID and category) then return nil end

    local mirror = ns.CDMBlizzMirror
    if mirror and mirror.GetStateByCooldownID then
        local state = mirror.GetStateByCooldownID(cooldownID, category)
        StoreCachedMirrorStateForIcon(icon, cooldownID, category, state)
        return state
    end

    return GetCachedMirrorStateForIcon(icon)
end

local function BuildIconCooldownStateContext(icon, entry, runtimeSpellID, useBuffSwipe, skipAuraPhase, totemSlot)
    local builder = Resolvers and Resolvers.BuildCooldownStateContext
    if not builder then return nil end

    local options = _iconCooldownStateContextOptions
    options.containerKey = entry and entry.viewerType
    options.totemSlot = totemSlot or (icon and icon._totemSlot)
    options.useBuffSwipe = useBuffSwipe
    options.skipAuraPhase = skipAuraPhase == true
    options.showGCDSwipe = IsGCDSwipeEnabled()
    options.lastChargeMirrorCooldownID = icon and icon._lastChargeMirrorCooldownID
    options.lastChargeMirrorCategory = icon and icon._lastChargeMirrorCategory
    options.lastChargeRuntimeSpellID = icon and icon._lastChargeRuntimeSpellID
    local cachedMirrorState = GetCachedMirrorStateForIcon(icon)
    options.cachedMirrorState = cachedMirrorState
    options.cachedMirrorSourceID = cachedMirrorState and icon and icon._blizzMirrorSourceID or nil
    return builder(icon, entry, runtimeSpellID, options)
end

function _resolverRuntimePolicy.ResolvedAuraStateIsActive(state)
    if not state then return false end
    if state.auraActive ~= nil then
        return state.auraActive == true
    end
    return state.isActive == true
end

function _resolverRuntimePolicy.ResolveResolvedStateForIcon(icon, entry, runtimeSpellID, useBuffSwipe, skipAuraPhase)
    if not (Resolvers.ResolveCooldownState and icon and entry) then
        return nil
    end

    local totemSlot = icon._totemSlot
    if IsTotemSlotEntry(entry) then
        totemSlot = entry._totemSlot
    end

    local context = BuildIconCooldownStateContext(
        icon, entry, runtimeSpellID, useBuffSwipe, skipAuraPhase, totemSlot)
    if not context then return nil end

    return Resolvers.ResolveCooldownState(context)
end

function _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, runtimeSpellID, useBuffSwipe)
    local state = _resolverRuntimePolicy.ResolveResolvedStateForIcon(icon, entry, runtimeSpellID, useBuffSwipe, false)
    if not state then return nil end
    if state.auraResolved == true or state.mode == "aura" or state.auraActive ~= nil then
        return state
    end
    return nil
end

function _resolverRuntimePolicy.StoreIconRuntimeState(icon, mode, sourceID, spellID, durObj,
                                                       resolvedStart, resolvedDuration, cdActive,
                                                       hasNumericCooldown, rechargeActive,
                                                       hasCharges, hasChargesRemaining,
                                                       mirrorBackedDuration, mirrorPayload,
                                                       resolvedState)
    local store = ns.CDMRuntimeStore
    if not (store and store.SetIconState) then return end

    local state = _resolverRuntimePolicy.iconRuntimeStateScratch
    if not state then
        state = {}
        _resolverRuntimePolicy.iconRuntimeStateScratch = state
    end

    state.mode = mode
    state.sourceID = sourceID
    state.spellID = spellID
    state.durObj = durObj
    state.start = resolvedStart
    state.duration = resolvedDuration
    state.active = cdActive
    state.numericCooldownActive = hasNumericCooldown
    state.isOnCooldown = cdActive
    state.rechargeActive = rechargeActive == true
    state.hasCharges = hasCharges == true
    state.hasChargesRemaining = hasChargesRemaining == true
    state.gcdOnly = mode == "gcd-only"
    state.key = nil
    state.mirrorBacked = mirrorBackedDuration == true
    state.mirrorState = mirrorPayload and mirrorPayload.state or nil
    state.mirrorCooldownID = resolvedState and resolvedState.mirrorCooldownID or nil
    state.mirrorCategory = resolvedState and resolvedState.mirrorCategory or nil
    state.auraActive = resolvedState and resolvedState.auraActive or nil
    state.auraInstanceID = resolvedState and resolvedState.auraInstanceID or nil
    state.auraUnit = resolvedState and resolvedState.auraUnit or nil
    state.resolvedAuraSpellID = resolvedState and resolvedState.resolvedAuraSpellID or nil
    state.hasExpirationTime = resolvedState and resolvedState.hasExpirationTime or nil
    state.hideDurationText = resolvedState and resolvedState.hideDurationText or nil
    state.durationStateUnknown = resolvedState and resolvedState.durationStateUnknown or nil
    state.countValue = resolvedState and resolvedState.countValue or nil
    state.countSinkText = resolvedState and resolvedState.countSinkText or nil
    state.countShown = resolvedState and resolvedState.countShown == true or false
    state.countSource = resolvedState and resolvedState.countSource or nil
    state.countMirrorBacked = resolvedState and resolvedState.countMirrorBacked or nil

    store.SetIconState(icon, state)
end

local function ClearIconDurationBinding(icon, addonCD)
    icon._lastDurObjKey = nil
    icon._lastDurObj = nil
    icon._lastResolvedMode = nil
    icon._lastResolvedSourceID = nil
    icon._lastResolvedSpellID = nil
    CancelCooldownExpiryRefresh(icon)
    if addonCD then
        if ns.CDMRenderers and ns.CDMRenderers.ClearCooldown then
            ns.CDMRenderers.ClearCooldown(addonCD, false)
        else
            if addonCD.SetReverse then
                addonCD.SetReverse(addonCD, false)
            end
            addonCD:Clear()
        end
    end
end

-- Mirrored aura icons must render the exact cooldownID mirror state already
-- synchronized onto the icon; generic aura resolution can match another unit.
local function ApplySyncedMirrorAuraCooldown(icon, entry)
    local addonCD = icon and icon.Cooldown
    if not (icon and entry and addonCD) then return false end

    local active = icon._auraActive == true
    local durObj = active and icon._lastAuraDurObj or nil
    local mode = active and "aura" or "inactive"
    local sourceID = icon._lastAuraSourceID
    local spellID = icon._activeAuraSpellID
        or icon._runtimeSpellID
        or entry.overrideSpellID
        or entry.spellID
        or entry.id

    icon._resolvedCooldownMode = mode
    icon._hasCooldownActive = false
    icon._hasRealCooldownActive = false
    ApplyCooldownDesaturation(icon, entry, nil, mode)

    local resolvedState = _resolverRuntimePolicy.syncedMirrorAuraStateScratch
    if not resolvedState then
        resolvedState = {}
        _resolverRuntimePolicy.syncedMirrorAuraStateScratch = resolvedState
    end
    resolvedState.mode = mode
    resolvedState.sourceID = sourceID
    resolvedState.spellID = spellID
    resolvedState.durObj = durObj
    resolvedState.auraActive = active
    resolvedState.auraInstanceID = icon._auraInstanceID
    resolvedState.auraUnit = icon._auraUnit
    resolvedState.resolvedAuraSpellID = spellID
    resolvedState.hasRenderableCooldown = durObj ~= nil
    resolvedState.durationStateUnknown = nil
    resolvedState.countValue = nil
    resolvedState.countSinkText = nil
    resolvedState.countShown = nil
    resolvedState.countSource = nil
    resolvedState.countMirrorBacked = nil
    _resolverRuntimePolicy.StoreIconRuntimeState(
        icon, mode, sourceID, spellID, durObj,
        nil, nil, false, false, false, false, false,
        true, nil, resolvedState)

    if not durObj then
        if icon._lastDurObjKey ~= nil
            or icon._lastDurObj ~= nil
            or icon._lastResolvedMode ~= nil then
            ClearIconDurationBinding(icon, addonCD)
        else
            CancelCooldownExpiryRefresh(icon)
        end
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
        icon._showingRealCooldownSwipe = nil
        ReapplySwipeStyle(addonCD, icon)
        return false
    end

    if DurationBindingMatches(icon, mode, sourceID, durObj, true) then
        icon._lastResolvedMode = mode
        icon._lastResolvedSourceID = sourceID
        icon._lastResolvedSpellID = spellID
        icon._showingRealCooldownSwipe = true
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
        ReapplySwipeStyle(addonCD, icon)
        return true
    end

    local key = BuildDurationBindingKey(mode, sourceID)
    icon._lastDurObjKey = key
    icon._lastDurObj = durObj
    icon._lastResolvedMode = mode
    icon._lastResolvedSourceID = sourceID
    icon._lastResolvedSpellID = spellID

    local applied = _resolverRuntimePolicy.ApplyDurationObjectCooldown(addonCD, durObj, true, true)
    if not applied then
        ClearIconDurationBinding(icon, nil)
        return false
    end

    CancelCooldownExpiryRefresh(icon)
    icon._showingRealCooldownSwipe = true
    _resolverRuntimePolicy.ClearGCDSwipe(icon)
    ReapplySwipeStyle(addonCD, icon)
    return true
end

-- Single-writer cooldown apply: ask the resolver, bind icon.Cooldown to the
-- returned DurationObject. Item entries may fall back to SetCooldown only
-- with verified non-secret numeric item timing. SetCooldownFromDurationObject
-- creates a live C-side binding; numeric item fallback gets a one-shot expiry
-- refresh through this same writer. Flags are derived from the classifier —
-- no Blizzard frame state mirroring.
-- See docs/blizzard/cdm-api-reference.md for the cooldown setter policy.
ApplyResolvedCooldown = function(icon, preResolvedState)
    local addonCD = icon and icon.Cooldown
    if not addonCD then return false end

    local entry = icon._spellEntry
    local useBuffSwipe = _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
    local skipAuraPhase = _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry)
    local measure = ns.MemAuditProfilerMeasure
    local stateContext
    local resolvedState = preResolvedState
    if resolvedState then
        durationBindingStats.resolvedStateReuses = durationBindingStats.resolvedStateReuses + 1
    else
        if measure then
            stateContext = measure(
                "CDM_applyBuildContext",
                BuildIconCooldownStateContext,
                icon, entry, icon._runtimeSpellID, useBuffSwipe, skipAuraPhase)
        else
            stateContext = BuildIconCooldownStateContext(
                icon, entry, icon._runtimeSpellID, useBuffSwipe, skipAuraPhase)
        end
        if not stateContext then return false end

        if measure then
            resolvedState = measure("CDM_applyResolveState", Resolvers.ResolveCooldownState, stateContext)
        else
            resolvedState = Resolvers.ResolveCooldownState(stateContext)
        end
    end
    if not resolvedState then return false end
    local entryIsAura = entry and IsAuraEntry(entry)
    local itemEntryForCooldown = entry
        and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
    if resolvedState
       and resolvedState.hasRenderableCooldown ~= true
       and not entryIsAura
       and not itemEntryForCooldown then
        local aliasID = GetRecentCastAliasForEntry(entry)
        local runtimeSpellID = stateContext and stateContext.runtimeSpellID or icon._runtimeSpellID
        if aliasID and aliasID ~= runtimeSpellID then
            local aliasContext
            if measure then
                aliasContext = measure(
                    "CDM_applyBuildContext",
                    BuildIconCooldownStateContext,
                    icon, entry, aliasID, useBuffSwipe, skipAuraPhase)
            else
                aliasContext = BuildIconCooldownStateContext(
                    icon, entry, aliasID, useBuffSwipe, skipAuraPhase)
            end
            local aliasState
            if aliasContext and measure then
                aliasState = measure("CDM_applyResolveState", Resolvers.ResolveCooldownState, aliasContext)
            elseif aliasContext then
                aliasState = Resolvers.ResolveCooldownState(aliasContext)
            end
            if aliasState and aliasState.hasRenderableCooldown == true then
                resolvedState = aliasState
                icon._runtimeSpellID = aliasID
            end
        end
    end
    local durObj = resolvedState.durObj
    local mode = resolvedState.mode
    local sourceID = resolvedState.sourceID
    local resolvedStart = resolvedState.start
    local resolvedDuration = resolvedState.duration
    local resolvedSpellID = resolvedState.spellID
    local mirrorBackedDuration = resolvedState.mirrorBacked == true
    local mirrorPayload = mirrorBackedDuration and resolvedState or nil
    icon._resolvedCooldownMode = mode
    icon._itemAuraCooldownActive = nil
    icon._itemAuraCooldownDurObj = nil

    local sid = resolvedSpellID
    if not sid and entry and not itemEntryForCooldown then
        sid = icon._runtimeSpellID
            or entry.overrideSpellID or entry.spellID or entry.id
    end
    if sid and not entryIsAura then
        sid = QueryOverrideSpell(sid) or sid
    end
    if mirrorBackedDuration == true then
        ApplyMirrorPayloadToIcon(icon, entry, sid or resolvedSpellID, mirrorPayload)
    elseif resolvedState.auraResolved == true then
        local auraDur, auraActive, auraSourceID =
            ApplyAuraStateToIcon(icon, entry, sid or resolvedSpellID, resolvedState)
        if mode == "aura" then
            durObj = auraDur
            sourceID = auraSourceID or sourceID
            resolvedState.durObj = durObj
            resolvedState.sourceID = sourceID
            if auraActive ~= true then
                mode = "inactive"
                resolvedState.mode = mode
                icon._resolvedCooldownMode = mode
            end
        end
    elseif mode ~= "aura" then
        ClearAuraStateForIcon(icon, entry)
    end

    local entryHasCharges = entry and (entry.hasCharges == true or entry.charges == true) or false
    _resolverRuntimePolicy.UpdateIconChargeMirrorCycle(icon, mode, sid or resolvedSpellID, entryHasCharges)

    local cdActive = mode ~= "inactive" and resolvedState.isOnCooldown == true
    local resolvedCdInfo = resolvedState.cooldownInfo
    local _dbgIsActive = resolvedState.cooldownInfoActive
    local _dbgIsOnGCD = resolvedState.cooldownInfoOnGCD

    -- Diagnostic: log every isActive/isOnGCD transition for icons whose
    -- name matches CDMIcons._desatTraceName. Set via /cdmdebug spell <name> trace.
    if CDMIcons._desatTraceName and entry and entry.name == CDMIcons._desatTraceName then
        local prevActive = icon._desatTracePrev
        if prevActive ~= cdActive then
            icon._desatTracePrev = cdActive
            print(string.format(
                "|cffff8800[desat]|r %s sid=%s cd.isActive=%s cd.isOnGCD=%s -> cdActive=%s",
                tostring(entry.name), tostring(sid),
                tostring(_dbgIsActive), tostring(_dbgIsOnGCD),
                tostring(cdActive)))
        end
    end
    icon._hasCooldownActive = cdActive
    icon._hasRealCooldownActive = cdActive
    -- Resolver is the single writer of desaturation. Saturation is driven by
    -- the real-CD-only (ignoreGCD) DurationObject through a step curve into
    -- SetDesaturation (see ApplyCooldownDesaturation): dark while the real CD
    -- rolls, bright the instant it reaches zero -- re-sampled C-side, so no
    -- lag and no dependence on the Lua-decoded mode. gcd-only / ready periods
    -- report zero real-CD remaining and render bright. The resolved (override-
    -- aware) sid is threaded so override-cooldown spells (e.g. Guardian
    -- Incarnation) query the spellID that actually carries the real cooldown.
    ApplyCooldownDesaturation(icon, entry, nil, mode, sid or resolvedSpellID, durObj)

    local hasNumericCooldown = resolvedState.numericCooldownActive == true
    local keySource = sourceID
    local hasCharges = resolvedState.hasCharges == true
    local rechargeActive = resolvedState.rechargeActive == true
    local hasChargesRemaining = resolvedState.hasChargesRemaining == true
    local hasRenderableCooldown = resolvedState.hasRenderableCooldown
    if hasRenderableCooldown == nil then
        hasRenderableCooldown = durObj ~= nil or hasNumericCooldown == true
    end
    if measure then
        measure(
            "CDM_applyStoreState",
            _resolverRuntimePolicy.StoreIconRuntimeState,
            icon, mode, sourceID, sid or resolvedSpellID, durObj,
            resolvedStart, resolvedDuration, cdActive, hasNumericCooldown,
            rechargeActive, hasCharges, hasChargesRemaining,
            mirrorBackedDuration, mirrorPayload, resolvedState)
    else
        _resolverRuntimePolicy.StoreIconRuntimeState(
            icon, mode, sourceID, sid or resolvedSpellID, durObj,
            resolvedStart, resolvedDuration, cdActive, hasNumericCooldown,
            rechargeActive, hasCharges, hasChargesRemaining,
            mirrorBackedDuration, mirrorPayload, resolvedState)
    end

    local stackTextWritesAllowed = CDMIcons.ShouldAllowStackTextWrites
        and CDMIcons.ShouldAllowStackTextWrites() == true
    if not stackTextWritesAllowed and ApplyVisibleMirrorStackTextIfNeeded then
        ApplyVisibleMirrorStackTextIfNeeded(icon, entry)
    end

    if hasRenderableCooldown ~= true or mode == "inactive" then
        CancelCooldownExpiryRefresh(icon)
        if mode == "aura"
           and InCombatLockdown()
           and icon._lastAuraDurObj
           and DurationBindingMatches(icon, mode, keySource, durObj, mirrorBackedDuration)
        then
            icon._showingRealCooldownSwipe = true
            _resolverRuntimePolicy.ClearGCDSwipe(icon)
            return true
        end
        if mode == "aura" then
            icon._lastDurObjKey = nil
            icon._lastDurObj = nil
            icon._lastResolvedMode = nil
            icon._lastResolvedSourceID = nil
            icon._lastResolvedSpellID = nil
            if ns.CDMRenderers and ns.CDMRenderers.ClearCooldown then
                ns.CDMRenderers.ClearCooldown(addonCD, false)
            else
                if addonCD.SetReverse then
                    addonCD.SetReverse(addonCD, false)
                end
                addonCD:Clear()
            end
            _resolverRuntimePolicy.ClearGCDSwipe(icon)
            icon._showingRealCooldownSwipe = nil
            return false
        end
        if icon._lastDurObjKey ~= nil then
            icon._lastDurObjKey = nil
            icon._lastDurObj = nil
            icon._lastResolvedMode = nil
            icon._lastResolvedSourceID = nil
            icon._lastResolvedSpellID = nil
            if ns.CDMRenderers and ns.CDMRenderers.ClearCooldown then
                ns.CDMRenderers.ClearCooldown(addonCD, false)
            else
                if addonCD.SetReverse then
                    addonCD.SetReverse(addonCD, false)
                end
                addonCD:Clear()
            end
        end
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
        icon._showingRealCooldownSwipe = nil
        return false
    end

    -- Dedupe: only re-bind when the source DurObj changes (mode swap, override
    -- swap, aura→CD transition, etc.). Re-binding on every event restarts the
    -- C-side sweep + countdown text — visible as text vanishing briefly.
    -- Aura mode also compares the DurationObject userdata identity: aura
    -- refreshes retain the same auraInstanceID (so the key is stable) but
    -- C_UnitAuras.GetAuraDuration returns a new userdata wrapper, which is
    -- our refresh signal. Same C-userdata identity check the bar path uses
    -- in cdm_bar_renderer.lua — safe in combat, no secret values.
    local shouldScheduleExpiry = (mode == "aura" and hasNumericCooldown == true)
        or (cdActive == true
            and (resolvedCdInfo ~= nil or hasNumericCooldown)
            and (mode == "cooldown" or mode == "item-cooldown"))
    local sameDurationBinding = DurationBindingMatches(icon, mode, keySource, durObj, mirrorBackedDuration)
    if sameDurationBinding then
        if shouldScheduleExpiry then
            local key = GetDurationBindingKey(icon, mode, keySource)
            if resolvedCdInfo then
                ScheduleCooldownExpiryRefresh(icon, key, resolvedCdInfo)
            else
                ScheduleCooldownExpiryRefreshAt(icon, key, resolvedStart + resolvedDuration)
            end
        else
            CancelCooldownExpiryRefresh(icon)
        end
        if mode == "aura" or mode == "cooldown" or mode == "item-cooldown" then
            icon._lastResolvedMode = mode
            icon._lastResolvedSourceID = sourceID
            icon._lastResolvedSpellID = sid or resolvedSpellID
            icon._showingRealCooldownSwipe = true
            _resolverRuntimePolicy.ClearGCDSwipe(icon)
        elseif mode == "gcd-only" then
            _resolverRuntimePolicy.MarkGCDSwipe(icon)
        end
        if measure then
            measure("CDM_applySwipeStyle", ReapplySwipeStyle, addonCD, icon)
        else
            ReapplySwipeStyle(addonCD, icon)
        end
        return true
    end
    local key = BuildDurationBindingKey(mode, keySource)
    icon._lastDurObjKey = key
    icon._lastDurObj = durObj
    icon._lastResolvedMode = mode
    icon._lastResolvedSourceID = sourceID
    icon._lastResolvedSpellID = sid or resolvedSpellID

    local applied
    if durObj then
        if measure then
            applied = measure(
                "CDM_applyCooldownFrame",
                _resolverRuntimePolicy.ApplyDurationObjectCooldown,
                addonCD, durObj, true, mode == "aura")
        else
            applied = _resolverRuntimePolicy.ApplyDurationObjectCooldown(addonCD, durObj, true, mode == "aura")
        end
    elseif hasNumericCooldown then
        if ns.CDMRenderers and ns.CDMRenderers.ApplyNumericCooldown then
            if measure then
                applied = measure(
                    "CDM_applyCooldownFrame",
                    ns.CDMRenderers.ApplyNumericCooldown,
                    addonCD, resolvedStart, resolvedDuration, mode == "aura")
            else
                applied = ns.CDMRenderers.ApplyNumericCooldown(addonCD, resolvedStart, resolvedDuration, mode == "aura")
            end
        end
    end
    if not applied then
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
        CancelCooldownExpiryRefresh(icon)
        return false
    end

    if shouldScheduleExpiry then
        if resolvedCdInfo then
            ScheduleCooldownExpiryRefresh(icon, key, resolvedCdInfo)
        else
            ScheduleCooldownExpiryRefreshAt(icon, key, resolvedStart + resolvedDuration)
        end
    else
        CancelCooldownExpiryRefresh(icon)
    end

    if mode == "aura" or mode == "cooldown" or mode == "item-cooldown" then
        icon._showingRealCooldownSwipe = true
        _resolverRuntimePolicy.ClearGCDSwipe(icon)
    elseif mode == "gcd-only" then
        icon._showingRealCooldownSwipe = nil
        _resolverRuntimePolicy.MarkGCDSwipe(icon)
    end
    if measure then
        measure("CDM_applySwipeStyle", ReapplySwipeStyle, addonCD, icon)
    else
        ReapplySwipeStyle(addonCD, icon)
    end

    return true
end

local function UnmirrorBlizzCooldown(icon)
    if not icon then return end
    icon._blizzCooldown = nil
    icon._auraActive = nil
    icon._auraUnit = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
    icon._activeAuraSpellID = nil
end
CDMIcons.ApplyResolvedCooldown = function(icon) return ApplyResolvedCooldown(icon) end

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
    if stackPolicy then
        return stackPolicy:TextHasDisplay(text)
    end
    return text ~= nil
end
function _resolverRuntimePolicy.ValueIsPresent(value)
    if stackPolicy then
        return stackPolicy:ValueIsPresent(value)
    end
    return value ~= nil
end

function _resolverRuntimePolicy.ValueIsMissing(value)
    return stackPolicy and stackPolicy:ValueIsMissing(value)
        or not _resolverRuntimePolicy.ValueIsPresent(value)
end

local function ClearIconStackText(icon)
    if stackPolicy then
        stackPolicy:Clear(icon)
    elseif icon and icon.StackText then
        icon.StackText.SetText(icon.StackText, "")
        icon.StackText.Hide(icon.StackText)
        icon._stackTextSource = nil
    end
end

-- Persistent spell-name cache. C_Spell.GetSpellInfo can return a secret
-- value in info.name during combat, and a secret name silently breaks
-- GetAuraDataBySpellName downstream. Resolve OOC and cache per-spell so
-- subsequent in-combat rebuilds (BuildSpellEntryFromCustom fired by the
-- filter-flip relayout when hideNonUsable's verdict crosses 0/1 stacks)
-- read a clean string instead of a fresh, possibly-secret one. Cache
-- entries are stable across the session — spell names don't mutate.
local _spellNameCache = {}

-- Returns ONLY clean (non-secret) names so the cache value is safe to
-- compare against "" downstream (cdm_bar_renderer.lua, cdm_frame_writes.lua, profile_io.lua
-- all do `entry.name ~= ""`). Skips GetSpellInfo entirely in combat —
-- info.name there could be secret, and we don't want a secret leaking
-- onto entry.name and tainting unrelated comparison sites.
local function GetCachedSpellName(spellID)
    if not spellID then return nil end
    local cached = _spellNameCache[spellID]
    if cached then return cached end
    if InCombatLockdown() then return nil end
    if not (Sources and Sources.QuerySpellInfo) then return nil end
    local info = Sources.QuerySpellInfo(spellID)
    if not info then return nil end
    local name = info.name
    if name == nil then return nil end
    _spellNameCache[spellID] = name
    return name
end

local _recentCastSpellByName = {}
local RECENT_CAST_ALIAS_TTL = 600

local function NormalizeSpellAliasName(name)
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    return string.lower(name)
end

local function GetSpellNameForAlias(spellID)
    if not spellID then return nil end
    local cached = GetCachedSpellName(spellID)
    if cached then return cached end
    if Sources and Sources.QuerySpellName then
        local name = Sources.QuerySpellName(spellID)
        if name and not (issecretvalue and issecretvalue(name)) then
            return name
        end
    end
    if not (Sources and Sources.QuerySpellInfo) then return nil end
    local info = Sources.QuerySpellInfo(spellID)
    local name = info and info.name
    if name and not (issecretvalue and issecretvalue(name)) then
        return name
    end
    return nil
end

RecordRecentPlayerSpellCast = function(spellID)
    if not spellID then return end
    local key = NormalizeSpellAliasName(GetSpellNameForAlias(spellID))
    if not key then return end
    _recentCastSpellByName[key] = {
        spellID = spellID,
        time = GetTime(),
    }
end

GetRecentCastAliasForEntry = function(entry)
    if not entry then return nil end
    local key = NormalizeSpellAliasName(entry.name)
    if not key then
        key = NormalizeSpellAliasName(GetSpellNameForAlias(entry.spellID or entry.overrideSpellID or entry.id))
    end
    local rec = key and _recentCastSpellByName[key]
    if not rec then return nil end
    if (GetTime() - (rec.time or 0)) > RECENT_CAST_ALIAS_TTL then
        _recentCastSpellByName[key] = nil
        return nil
    end
    return rec.spellID
end

-- Shared with cdm_spelldata.lua's ResolveOwnedEntry so harvested spell
-- entries (essential/utility/buff ownedSpells) and Composer-built custom
-- entries draw from the same cache.
ns._GetCachedSpellName = GetCachedSpellName

stackPolicy = ns.CDMIconStackPolicy and ns.CDMIconStackPolicy.Create({
    getSink = function()
        return ns.CDMIconStackText
    end,
    getSources = function()
        return Sources
    end,
    getAuraRuntime = function()
        return ns.CDMAuraRuntime
    end,
    getMirror = function()
        return ns.CDMBlizzMirror
    end,
    getCachedMirrorStateForIcon = function(icon)
        return GetCachedMirrorStateForIcon and GetCachedMirrorStateForIcon(icon) or nil
    end,
    refreshCachedMirrorStateForIcon = function(icon)
        return RefreshCachedMirrorStateForIcon and RefreshCachedMirrorStateForIcon(icon) or nil
    end,
    safeBoolean = SafeBoolean,
    isAuraEntry = IsAuraEntry,
    isBuiltinAuraContainerKey = IsBuiltinAuraContainerKey,
    isTotemSlotEntry = IsTotemSlotEntry,
    resolveAuraActiveState = function(entry)
        return ResolveAuraActiveState(entry)
    end,
    resolveMirrorIdentityState = function(entry)
        return Resolvers and Resolvers.ResolveBlizzardMirrorIdentityState
            and Resolvers.ResolveBlizzardMirrorIdentityState(entry)
            or nil
    end,
    getChargeMetadataDB = function()
        return GetChargeMetadataDB and GetChargeMetadataDB() or nil
    end,
    queryOverrideSpell = function(spellID)
        return QueryOverrideSpell and QueryOverrideSpell(spellID) or nil
    end,
    queryDisplayCount = function(spellID, owner)
        if QueryDisplayCount then
            return QueryDisplayCount(spellID, owner)
        end
        return nil
    end,
    querySpellCount = function(spellID, owner)
        if QuerySpellCount then
            return QuerySpellCount(spellID, owner)
        end
        return nil
    end,
    getEntryTexture = function(entry)
        return GetEntryTexture and GetEntryTexture(entry) or nil
    end,
    getAuraDataInstanceID = GetAuraDataInstanceID,
    getCachedSpellName = GetCachedSpellName,
    getTrackerSettings = function(viewerType)
        return GetTrackerSettings and GetTrackerSettings(viewerType) or nil
    end,
    debugStackText = function(icon, op, value, reason)
        return CDMIcons.DebugStackText(icon, op, value, reason)
    end,
    chargeDebug = ChargeDebug,
})

function _resolverRuntimePolicy.GetAuraApplicationsFromData(auraData, unit, source)
    if stackPolicy then
        return stackPolicy:GetAuraApplicationsFromData(auraData, unit, source)
    end
    return nil
end

function _resolverRuntimePolicy.GetAuraApplicationsForInstance(unit, auraInstanceID, source, minApplications)
    if stackPolicy then
        return stackPolicy:GetAuraApplicationsForInstance(unit, auraInstanceID, source, minApplications)
    end
    return nil
end

function _resolverRuntimePolicy.TryAuraApplicationsBySpellID(auraID, source)
    if stackPolicy then
        return stackPolicy:TryAuraApplicationsBySpellID(auraID, source)
    end
    return nil
end

function _resolverRuntimePolicy.TryLinkedAuraApplications(linkedSpellIDs, entry, icon, seenIDs, source)
    if stackPolicy then
        return stackPolicy:TryLinkedAuraApplications(linkedSpellIDs, entry, icon, seenIDs, source)
    end
    return nil
end

function _resolverRuntimePolicy.GetSpellCountForEntry(spellID, entry, icon)
    if stackPolicy then
        return stackPolicy:GetSpellCountForEntry(spellID, entry, icon)
    end
    return nil
end

function _resolverRuntimePolicy.ResolveAuraApplicationsForEntry(spellID, entry, icon)
    if stackPolicy then
        return stackPolicy:ResolveAuraApplicationsForEntry(spellID, entry, icon)
    end
    return nil
end

GetAuraApplicationsForSpell = function(spellID, entryOrName, icon)
    if stackPolicy then
        return stackPolicy:GetAuraApplicationsForSpell(spellID, entryOrName, icon)
    end
    return nil
end

local function ApplyAuraCountText(icon, count, showZero, preserveWhenMissing)
    if stackPolicy then
        stackPolicy:ApplyAuraCountText(icon, count, showZero, preserveWhenMissing)
    end
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
    if icon.GetFrameLevel then
        local baselineLevel = icon:GetFrameLevel() + TEXT_OVERLAY_FRAME_LEVEL_OFFSET
        if not requiredLevel or requiredLevel < baselineLevel then
            requiredLevel = baselineLevel
        end
    end

    if requiredLevel and icon.TextOverlay:GetFrameLevel() < requiredLevel then
        icon.TextOverlay:SetFrameLevel(requiredLevel)
    end

    SyncClickButtonFrameLevel(icon)
end

local function NormalizeIconFrameLevels(icon)
    if not icon then return end

    local parent = icon.GetParent and icon:GetParent()
    if parent and parent.GetFrameLevel and icon.GetFrameLevel and icon.SetFrameLevel then
        local requiredIconLevel = parent:GetFrameLevel() + ICON_FRAME_LEVEL_OFFSET
        if icon:GetFrameLevel() < requiredIconLevel then
            icon:SetFrameLevel(requiredIconLevel)
        end
    end

    if icon.Cooldown and icon.GetFrameLevel
        and icon.Cooldown.GetFrameLevel and icon.Cooldown.SetFrameLevel then
        local requiredCooldownLevel = icon:GetFrameLevel() + COOLDOWN_FRAME_LEVEL_OFFSET
        if icon.Cooldown:GetFrameLevel() < requiredCooldownLevel then
            icon.Cooldown:SetFrameLevel(requiredCooldownLevel)
        end
    end

    CDMIcons:EnsureTextOverlayLevel(icon)
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
        GameTooltip.Hide(GameTooltip)
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
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "CDM_macroCache", tbl = _macroCache } end

local function InvalidateMacroCache()
    wipe(_macroCache)
end

local function FindMacroForSpell(spellID, overrideSpellID)
    if not spellID and not overrideSpellID then return nil end

    -- Check session cache (keyed on primary spellID)
    local cacheKey = spellID or overrideSpellID
    local cached = _macroCache[cacheKey]
    if cached ~= nil then return cached or nil end

    -- Build lowercase spell name set for matching
    local names = {}
    if spellID and Sources and Sources.QuerySpellInfo then
        local info = Sources.QuerySpellInfo(spellID)
        local name = info and info.name
        if type(name) == "string" then names[name:lower()] = true end
    end
    if overrideSpellID and overrideSpellID ~= spellID and Sources and Sources.QuerySpellInfo then
        local info = Sources.QuerySpellInfo(overrideSpellID)
        local name = info and info.name
        if type(name) == "string" then names[name:lower()] = true end
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
                -- Skip if the macro's tooltip names a spell that's not in `names`.
                if (not tooltipSpell) or names[tooltipSpell] then
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
UpdateIconSecureAttributes = function(icon, entry, viewerType)
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

    -- Built-in containers live at ncdm[viewerType]; custom bars live at
    -- ncdm.containers[viewerType]. GetTrackerSettings handles both.
    local viewerDB = GetTrackerSettings and GetTrackerSettings(viewerType)

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
        local itemID = entry.itemID
        if not itemID and Sources and Sources.QueryInventoryItemID then
            itemID = Sources.QueryInventoryItemID("player", entry.id)
        end
        if itemID then
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
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
        local itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
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
            local spellInfo = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(spellID)
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

local function RefreshItemIconVisuals(icon, entry, itemID)
    return itemVisualPolicy and itemVisualPolicy:RefreshItemVisuals(icon, entry, itemID) or false
end

local function RefreshInventoryItemVisuals(icon, entry, itemID)
    return itemVisualPolicy and itemVisualPolicy:RefreshInventoryItemVisuals(icon, entry, itemID) or false
end

---------------------------------------------------------------------------
-- ICON CONFIGURATION
-- Applies size, border, zoom, texcoord, text styling to an icon.
---------------------------------------------------------------------------
local BLIZZ_ICON_CHROME_ATLASES = {
    ["UI-HUD-CoolDownManager-IconOverlay"] = true,
    ["UI-CooldownManager-OORshadow"] = true,
}

local function IsIconChromeTexture(region)
    if not (region and region.GetAtlas) then return false end
    local atlas = region:GetAtlas()
    return atlas and BLIZZ_ICON_CHROME_ATLASES[atlas] or false
end

local function BuildTexCoord(zoom, aspectRatioCrop)
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

    return left, right, top, bottom
end

local function ApplyTexCoordToTexture(texture, left, right, top, bottom)
    if not (texture and texture.SetTexCoord) then return end
    if IsIconChromeTexture(texture) then return end
    texture.SetTexCoord(texture, left, right, top, bottom)
end

local function ApplyTexCoordToTarget(target, left, right, top, bottom, visited)
    if not target then return end
    visited = visited or {}
    if visited[target] then return end
    visited[target] = true

    local objType
    if target.GetObjectType then
        objType = target:GetObjectType()
    end
    if objType == "Texture" then
        ApplyTexCoordToTexture(target, left, right, top, bottom)
        return
    end

    if target.Icon and target.Icon ~= target then
        ApplyTexCoordToTarget(target.Icon, left, right, top, bottom, visited)
    end
    if target.IconTexture and target.IconTexture ~= target then
        ApplyTexCoordToTarget(target.IconTexture, left, right, top, bottom, visited)
    end
    if target.Texture and target.Texture ~= target then
        ApplyTexCoordToTarget(target.Texture, left, right, top, bottom, visited)
    end

    if target.GetRegions then
        local regions = { target:GetRegions() }
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                ApplyTexCoordToTexture(region, left, right, top, bottom)
            end
        end
    end

    if target.GetChildren then
        local children = { target:GetChildren() }
        for _, child in ipairs(children) do
            local childType
            if child and child.GetObjectType then
                childType = child:GetObjectType()
            end
            if childType ~= "Cooldown" then
                ApplyTexCoordToTarget(child, left, right, top, bottom, visited)
            end
        end
    end
end

local function ApplyTexCoord(icon, zoom, aspectRatioCrop)
    if not icon then return end
    local left, right, top, bottom = BuildTexCoord(zoom, aspectRatioCrop)

    ApplyTexCoordToTarget(icon.Icon, left, right, top, bottom)
end

local function ConfigureIcon(icon, rowConfig)
    if not icon or not rowConfig then return end
    icon._rowConfig = rowConfig

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
    NormalizeIconFrameLevels(icon)

    -- Border
    local borderSize = rowConfig.borderSize or 0
    if borderSize > 0 then
        local bs = (QUICore and QUICore.Pixels) and QUICore:Pixels(borderSize, icon) or borderSize
        -- Resolve the per-row icon border via the central source enum
        -- (inherit/theme/class/custom). rowConfig carries borderColorSource +
        -- borderColor forwarded from the live per-row settings.
        local br, bg, bb, ba = Helpers.GetSkinBorderColor(rowConfig, "")

        icon.Border:SetColorTexture(br, bg, bb, ba)
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
    local durationFont = generalFont
    local stackFont = generalFont
    if LSM and rowConfig.durationFont and rowConfig.durationFont ~= "" then
        durationFont = LSM:Fetch("font", rowConfig.durationFont) or durationFont
    end
    if LSM and rowConfig.stackFont and rowConfig.stackFont ~= "" then
        stackFont = LSM:Fetch("font", rowConfig.stackFont) or stackFont
    end

    local durationSize = rowConfig.durationSize or 14
    local hideDurationText = rowConfig.hideDurationText
    if durationSize > 0 and not hideDurationText then
        local dtc = rowConfig.durationTextColor or {1, 1, 1, 1}
        local dAnchor = rowConfig.durationAnchor or "CENTER"
        local dox = rowConfig.durationOffsetX or 0
        local doy = rowConfig.durationOffsetY or 0

        -- Helper: style any FontString regions inside a Cooldown frame.
        -- Blizzard-mirrored icons use QUI's native icon.Cooldown.
        local function styleDurationFontString(region)
            if not (region and region.GetObjectType and region:GetObjectType() == "FontString") then return end
            region:SetFont(durationFont, durationSize, generalOutline)
            region:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
            region:Show()

;(function()
                region:ClearAllPoints()
                region:SetPoint(dAnchor, icon, dAnchor, dox, doy)
                region:SetDrawLayer("OVERLAY", 7)
            end)()
        end

        local function styleCDFontStrings(cd)
            if not cd then return end
            if cd.SetHideCountdownNumbers then
                cd.SetHideCountdownNumbers(cd, false)
            end
            if cd.GetCountdownFontString then
                styleDurationFontString(cd:GetCountdownFontString())
            end
            local regions = { cd:GetRegions() }
            for _, region in ipairs(regions) do
                styleDurationFontString(region)
            end
        end

        -- Style QUI's native cooldown text
        styleCDFontStrings(icon.Cooldown)

        -- Also style our DurationText
        icon.DurationText:SetFont(durationFont, durationSize, generalOutline)
        icon.DurationText:SetTextColor(dtc[1], dtc[2], dtc[3], dtc[4] or 1)
        icon.DurationText:ClearAllPoints()
        icon.DurationText:SetPoint(dAnchor, icon, dAnchor, dox, doy)
        icon.DurationText:Show()
    elseif hideDurationText then
        -- Helper: hide FontStrings inside a Cooldown frame
        local function hideDurationFontString(region)
            if region and region.GetObjectType
               and region:GetObjectType() == "FontString"
               and region.Hide then
                region:Hide()
            end
        end

        local function hideCDFontStrings(cd)
            if not cd then return end
            if cd.SetHideCountdownNumbers then
                cd.SetHideCountdownNumbers(cd, true)
            end
            if cd.GetCountdownFontString then
                hideDurationFontString(cd:GetCountdownFontString())
            end
            local regions = { cd:GetRegions() }
            for _, region in ipairs(regions) do
                hideDurationFontString(region)
            end
        end
        hideCDFontStrings(icon.Cooldown)
        icon.DurationText:Hide()
    end

    -- Stack text styling
    local stackSize = rowConfig.stackSize or 14
    local hideStackText = rowConfig.hideStackText
    if stackSize > 0 and not hideStackText then
        local stc = rowConfig.stackTextColor or {1, 1, 1, 1}
        local sAnchor = rowConfig.stackAnchor or "BOTTOMRIGHT"
        local sox = rowConfig.stackOffsetX or 0
        local soy = rowConfig.stackOffsetY or 0

        icon.StackText:SetFont(stackFont, stackSize, generalOutline)
        icon.StackText:SetTextColor(stc[1], stc[2], stc[3], stc[4] or 1)
        icon.StackText:ClearAllPoints()
        icon.StackText:SetPoint(sAnchor, icon, sAnchor, sox, soy)
        icon.StackText:SetDrawLayer("OVERLAY", 7)

    elseif hideStackText then
        icon.StackText:Hide()
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

        -- hideDurationText: per-spell duration text visibility override.
        -- true  → force-hide on this spell only
        -- false → force-show (overrides a row-level Hide Duration Text)
        -- nil   → inherit row default
        if spellOvr.hideDurationText == true then
            local function hideDurationForCooldown(cd)
                if not cd then return end
                if cd.SetHideCountdownNumbers then
                    cd.SetHideCountdownNumbers(cd, true)
                end
                local regions = { cd:GetRegions() }
                for _, region in ipairs(regions) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:Hide()
                    end
                end
            end
            hideDurationForCooldown(icon.Cooldown)
            icon.DurationText:Hide()
        elseif spellOvr.hideDurationText == false then
            if icon.Cooldown and icon.Cooldown.SetHideCountdownNumbers then
                icon.Cooldown.SetHideCountdownNumbers(icon.Cooldown, false)
            end
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
function GetTrackerSettings(viewerType)
    if Shared and Shared.GetContainerDB then
        local containerDB = Shared.GetContainerDB(viewerType)
        if containerDB then return containerDB end
    end

    local db = GetDB()
    if not db or not viewerType then return nil end
    if db[viewerType] then return db[viewerType] end
    return db.containers and db.containers[viewerType] or nil
end

customBarPolicy = ns.CDMIconCustomBarPolicy and ns.CDMIconCustomBarPolicy.Create({
    getSources = function()
        return Sources
    end,
    getSpellData = function()
        return ns.CDMSpellData
    end,
    getGlowLib = function()
        return LCG
    end,
    getTime = function()
        return GetTime()
    end,
    getTrackerSettings = function(viewerType)
        return GetTrackerSettings and GetTrackerSettings(viewerType) or nil
    end,
    isCustomBarContainer = IsCustomBarContainer,
    getCustomBarVisibilityMode = GetCustomBarVisibilityMode,
    resolveMacro = function(entry)
        return ResolveMacro(entry)
    end,
    resolveSpellActiveState = function(spellID, icon, entry)
        return Resolvers and Resolvers.ResolveSpellActiveState
            and Resolvers.ResolveSpellActiveState(spellID, icon, entry)
            or false
    end,
    resolveCooldownActivityState = function(icon, entry, containerDB, now)
        return _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, containerDB, now)
    end,
    reapplySwipeStyle = function(cooldown, icon)
        return ReapplySwipeStyle(cooldown, icon)
    end,
    isPlayerInCombat = function()
        return UnitAffectingCombat and UnitAffectingCombat("player") or false
    end,
    debugIconEvent = function(...)
        return CDMIcons.DebugIconEvent and CDMIcons.DebugIconEvent(...)
    end,
    after = function(delay, callback)
        if C_Timer and C_Timer.After then
            return C_Timer.After(delay, callback)
        end
        callback()
    end,
})

function _resolverRuntimePolicy.ResolveItemActiveState(itemID, icon, entry)
    return customBarPolicy
        and customBarPolicy:ResolveItemActiveState(itemID, icon, entry)
        or false
end

function _resolverRuntimePolicy.CooldownHasVisualPriority(icon, entry, containerDB, now)
    return customBarPolicy
        and customBarPolicy:CooldownHasVisualPriority(icon, entry, containerDB, now)
        or false
end

function _resolverRuntimePolicy.ResolveCustomBarActiveState(entry, icon, now)
    return customBarPolicy
        and customBarPolicy:ResolveActiveState(entry, icon, now)
        or false
end

function _resolverRuntimePolicy.ResolveCustomBarCooldownState(entry, icon, containerDB, now)
    return customBarPolicy
        and customBarPolicy:ResolveCooldownState(entry, icon, containerDB, now)
        or nil
end

function _resolverRuntimePolicy.ResolveCustomBarUsability(entry, containerDB, cooldownState)
    return not customBarPolicy
        or customBarPolicy:ResolveUsability(entry, containerDB, cooldownState)
end

function _resolverRuntimePolicy.ComputeCustomBarVisibility(icon, entry, containerDB, now)
    return customBarPolicy
        and customBarPolicy:ComputeVisibility(icon, entry, containerDB, now)
        or {
            baseVisible = true,
            layoutVisible = true,
            renderVisible = true,
            isActive = false,
            isUsable = true,
            isOnCooldown = false,
            rechargeActive = false,
            hasChargesRemaining = false,
            visibilityMode = "always",
        }
end

function _resolverRuntimePolicy.StartCustomBarActiveGlow(icon, containerDB)
    if customBarPolicy then
        customBarPolicy:StartActiveGlow(icon, containerDB)
    end
end

function _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
    if customBarPolicy then
        customBarPolicy:StopActiveGlow(icon)
    end
end

function _resolverRuntimePolicy.ApplyCustomBarSwipeStyle(icon, containerDB, cooldownState)
    if customBarPolicy then
        customBarPolicy:ApplySwipeStyle(icon, containerDB, cooldownState)
    end
end

function _resolverRuntimePolicy.ApplyCustomBarActiveState(icon, entry, containerDB)
    if customBarPolicy then
        customBarPolicy:ApplyActiveState(icon, entry, containerDB)
    end
end

function _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
    if customBarPolicy then
        customBarPolicy:ApplyActiveGlow(icon, containerDB, visibility)
    end
end

function _resolverRuntimePolicy.ShouldHideIconStackText(icon, containerDB)
    return stackPolicy and stackPolicy:ShouldHideIconStackText(icon, containerDB) or false
end

-- CDMIcons.DebugStackText is rebound by the load-on-demand debug addon.

function _resolverRuntimePolicy.ShowIconStackText(icon, value, containerDB, reason)
    if stackPolicy then
        stackPolicy:ShowIconStackText(icon, value, containerDB, reason)
    end
end

function _resolverRuntimePolicy.HideIconStackText(icon, reason)
    if stackPolicy then
        stackPolicy:HideIconStackText(icon, reason)
    end
end

local function GetRefreshBatchTime()
    if refreshBatch then
        return refreshBatch:GetTime()
    end
    return GetTime and GetTime() or 0
end

-- _showGCDSwipe is hoisted once per batch from swipe module settings.
-- When true, GCD-only cooldowns are allowed through to the CooldownFrame
-- instead of being cleared, so the GCD swipe animation can render.
local _showGCDSwipe = false
-- _showBuffSwipe is hoisted once per batch from swipe module settings.
-- _showCooldownIconAuraPhase controls whether cooldown-kind icons can enter
-- aura phase before charge/cooldown phase.
local _showBuffSwipe = true
local _showCooldownIconAuraPhase = true

function _resolverRuntimePolicy.RefreshSwipeBatchSettings()
    local swipeMod = ns._OwnedSwipe
    local swipeSettings = swipeMod and swipeMod.GetSettings and swipeMod.GetSettings()
    _showGCDSwipe = swipeSettings and swipeSettings.showGCDSwipe or false
    _showBuffSwipe = swipeSettings and (swipeSettings.showBuffSwipe ~= false) or false
    if swipeSettings then
        _showCooldownIconAuraPhase = swipeSettings.showCooldownIconAuraPhase ~= false
    else
        _showCooldownIconAuraPhase = true
    end
end

function _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry)
    if not entry then return false end
    if IsAuraEntry(entry) then return false end
    return _showCooldownIconAuraPhase == false
end

function _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
    if not entry then return false end
    if not _showBuffSwipe then return false end
    if _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry) then
        return false
    end
    local settings = ResolveTrackerSettingsNow(entry and entry.viewerType)
    if settings and settings.showOnlyOnCooldown == true then
        return false
    end
    if IsCustomBarContainer(settings) then
        if settings.showActiveState == false then
            return false
        end
    end
    return true
end

function _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, containerDB, now)
    local runtimeStore = ns.CDMRuntimeStore
    local storedState = runtimeStore and runtimeStore.GetFrameState
        and runtimeStore.GetFrameState(icon)
    local fromResolved = storedState
        and Resolvers
        and Resolvers.ResolveCooldownActivityStateFromResolvedState
        and Resolvers.ResolveCooldownActivityStateFromResolvedState(entry, storedState)
    if fromResolved then
        return fromResolved
    end

    local resolver = Resolvers and Resolvers.ResolveCooldownActivityState
    if not resolver then return nil end
    local options = _resolverRuntimePolicy
    options.useBuffSwipe = _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
    options.skipAuraPhase = _resolverRuntimePolicy.ShouldSkipAuraPhaseForCooldownIcon(icon, entry)
    options.showGCDSwipe = IsGCDSwipeEnabled()
    return resolver(icon, entry, containerDB, now, options)
end

function _resolverRuntimePolicy.ApplyMirrorStackText(icon, mirrorState, showZero)
    return stackPolicy and stackPolicy:ApplyMirrorStackText(icon, mirrorState, showZero) or false
end

function _resolverRuntimePolicy.DebugBlizzSyncSnapshot(enabled, icon, entry, mirrorState, resolvedState,
                                                       active, mirrorActive, fallbackFoundAura,
                                                       durObj, durObjSource)
    if not enabled or not icon then return end

    local function debugSafeShown(frame)
        if frame and frame.IsShown then
            return frame:IsShown() and true or false
        end
        return nil
    end

    local function debugSafeAlpha(frame)
        if frame and frame.GetAlpha then
            return frame:GetAlpha()
        end
        return nil
    end

    local signature = table.concat({
        tostring(active == true),
        tostring(mirrorActive == true),
        tostring(mirrorState and mirrorState.durObj and true or false),
        tostring(mirrorState and mirrorState.hasAuraInstanceID == true),
        tostring(mirrorState and mirrorState.auraUnit),
        tostring(resolvedState and resolvedState.isActive == true),
        tostring(resolvedState and resolvedState.durObj and true or false),
        tostring(resolvedState and resolvedState.auraInstanceID and true or false),
        tostring(resolvedState and resolvedState.auraUnit),
        tostring(resolvedState and resolvedState.durationStateUnknown == true),
        tostring(fallbackFoundAura == true),
        tostring(durObj and true or false),
        tostring(durObjSource),
        tostring(debugSafeShown(icon)),
        tostring(debugSafeAlpha(icon)),
    }, "|")

    if icon._lastBlizzSyncTraceSig == signature then return end
    icon._lastBlizzSyncTraceSig = signature

    CDMIcons._DebugBlizzEntry(enabled, entry, "state-sync-trace",
        "active=", tostring(active == true),
        "mirrorActive=", tostring(mirrorActive == true),
        "mirrorDur=", tostring(mirrorState and mirrorState.durObj and true or false),
        "mirrorInst=", tostring(mirrorState and mirrorState.hasAuraInstanceID == true),
        "mirrorUnit=", tostring(mirrorState and mirrorState.auraUnit),
        "resolverActive=", tostring(resolvedState and resolvedState.isActive == true),
        "resolverDur=", tostring(resolvedState and resolvedState.durObj and true or false),
        "resolverInst=", tostring(resolvedState and resolvedState.auraInstanceID and true or false),
        "resolverUnit=", tostring(resolvedState and resolvedState.auraUnit),
        "unknown=", tostring(resolvedState and resolvedState.durationStateUnknown == true),
        "fallbackAura=", tostring(fallbackFoundAura == true),
        "durObj=", tostring(durObj and true or false),
        "durObjSource=", tostring(durObjSource),
        "hostShown=", tostring(debugSafeShown(icon)),
        "hostAlpha=", tostring(debugSafeAlpha(icon)),
        CDMIcons._FormatMirrorState(mirrorState))
end

function _resolverRuntimePolicy.SyncBlizzMirrorIconState(icon)
    local entry = icon and icon._spellEntry
    local cooldownID = icon and icon._blizzMirrorCooldownID
    if not (entry and cooldownID) then return false end

    local runtimeSid = entry.spellID or entry.overrideSpellID or entry.id
    if runtimeSid and not IsAuraEntry(entry) then
        local ovId = QueryOverrideSpell(runtimeSid)
        if ovId then runtimeSid = ovId end
    end
    icon._runtimeSpellID = runtimeSid
    local debugBlizz
    if _G.QUI_CDM_BLIZZ_DEBUG or _G.QUI_CDM_ICON_DEBUG then
        debugBlizz = CDMIcons._ShouldDebugBlizzEntry(entry, {
            runtimeSid,
            entry.spellID,
            entry.overrideSpellID,
            entry.id,
        })
    end

    local m = GetCachedMirrorStateForIcon(icon)
    if not m then
        m = RefreshCachedMirrorStateForIcon(icon)
    end
    if not m then
        if debugBlizz then
            CDMIcons._DebugBlizzEntry(debugBlizz, entry, "state-sync-missing", "cdID=", tostring(cooldownID))
        end
        return false
    end

    local isAuraBacked = IsAuraEntry(entry)
        or m.viewerCategory == "buff"
        or m.viewerCategory == "trackedBar"
    if not isAuraBacked then
        if debugBlizz then
            CDMIcons._DebugBlizzEntry(debugBlizz, entry, "state-sync-skip-cooldown", CDMIcons._FormatMirrorState(m))
        end
        return false
    end

    local r = runtimeSid and _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, runtimeSid, true) or nil

    -- Mirror is authoritative for Blizzard-mirrored icons. `m` is the mirror
    -- state for the exact cdID this icon is bound to.
    -- Resolved aura facts can still come from a different cdID when
    -- spellID->cdID maps collide. Trusting them for this icon's display
    -- would let an unrelated aura's state, including its durObj, leak onto
    -- this icon. Use the exact mirror state for rendering.
    local mirrorActive = (m.auraInstanceID and true or false)
        or SafeBoolean(m.childIsActive) == true
        or (m.totemSlot and true or false)
        or (m.auraDurObj and true or false)
        or (m.totemDurObj and true or false)
    local selfAura = SafeBoolean(m.selfAura)
    local auraUnit = SafeRuntimeString(m.auraUnit)
        or ((selfAura == false) and "target" or "player")

    local mirrorMod = ns.CDMBlizzMirror
    if _G.QUI_CDM_TAINT_DEBUG and mirrorMod and mirrorMod.TaintLog then
        mirrorMod.TaintLog("Sync.in",
            "cdID", cooldownID,
            "runtimeSid", runtimeSid,
            "m.childIsActive", m.childIsActive,
            "m.selfAura", m.selfAura,
            "m.hasAura", m.hasAura,
            "m.spellID", m.spellID,
            "m.overrideTooltipSpellID", m.overrideTooltipSpellID,
            "m.auraDurObj", m.auraDurObj,
            "m.hasAuraInstanceID", m.hasAuraInstanceID,
            "m.auraUnit", m.auraUnit,
            "r.isActive", r and r.isActive,
            "r.auraActive", r and r.auraActive,
            "r.durObj", r and r.durObj,
            "r.auraInstanceID", r and r.auraInstanceID,
            "r.auraUnit", r and r.auraUnit,
            "r.durationStateUnknown", r and r.durationStateUnknown,
            "m.viewerCategory", m.viewerCategory,
            "auraUnit", auraUnit,
            "mirrorActive", mirrorActive)
    end

    -- Aura duration is owned by the mirror. Prefer the Blizzard child
    -- DurationObject when it exists; UNIT_AURA duration objects are the
    -- fallback. Icon sync is a pure consumer: if no aura duration is known,
    -- render the active aura without a swipe and wait for the next stamp.
    local durObj = m.auraDurObj
    local durObjSource = durObj and (m.auraDurObjSource or "mirror") or nil
    local fallbackFoundAura = false
    local fallbackInstID

    -- Activeness is "is the aura on the unit", NOT "do we have a swipe
    -- duration". A durationless aura (form, stance, permanent buff) is
    -- active without a durObj, so the icon should display without a countdown.
    local active = mirrorActive or fallbackFoundAura or (durObj and true or false)
    _resolverRuntimePolicy.DebugBlizzSyncSnapshot(debugBlizz, icon, entry, m, r, active, mirrorActive,
        fallbackFoundAura, durObj, durObjSource)
    local priorActive = icon._auraActive == true
    local priorEpoch = icon._lastBlizzSwipeEpoch
    local priorHadAuraDurObj = icon._lastAuraDurObj and true or false
    icon._auraActive = active
    icon._auraUnit = auraUnit
    icon._auraInstanceID = active and m.auraInstanceID or nil
    icon._totemSlot = entry._totemSlot or nil
    icon._isTotemInstance = nil

    if _G.QUI_CDM_TAINT_DEBUG and ns.CDMBlizzMirror and ns.CDMBlizzMirror.TaintLog then
        ns.CDMBlizzMirror.TaintLog("Sync.out",
            "cdID", cooldownID,
            "active", active,
            "mirrorActive", mirrorActive,
            "fallbackFoundAura", fallbackFoundAura,
            "durObjSource", durObjSource,
            "durObj", durObj,
            "fallbackInstID", fallbackInstID)
    end

    if active then
        icon._lastAuraDurObj = durObj
        icon._lastAuraSourceID = (durObjSource or "mirror")
            .. ":" .. tostring(cooldownID)
            .. ":" .. tostring(m.mirrorEpoch or 0)
        icon._activeAuraSpellID = m.overrideTooltipSpellID or runtimeSid
        icon._auraIsHarmful = (auraUnit == "target") and true or false
    else
        icon._lastAuraDurObj = nil
        icon._lastAuraSourceID = nil
        icon._activeAuraSpellID = nil
        icon._auraIsHarmful = nil
    end

    local priorPandemicKnown = icon._blizzPandemicStateKnown == true
    local priorPandemicActive = icon._blizzPandemicActive == true
    if m.pandemicStateKnown == true then
        icon._blizzPandemicActive = m.pandemicActive == true
        icon._blizzPandemicStateKnown = true
    else
        icon._blizzPandemicActive = nil
        icon._blizzPandemicStateKnown = nil
    end
    if priorPandemicKnown ~= (icon._blizzPandemicStateKnown == true)
        or priorPandemicActive ~= (icon._blizzPandemicActive == true) then
        local glows = ns._OwnedGlows
        if glows and glows.UpdatePandemicGlow then
            glows.UpdatePandemicGlow(icon)
        end
    end

    local mirrorStackApplied = _resolverRuntimePolicy.ApplyMirrorStackText(icon, m, entry.hasCharges)
    if active then
        if not mirrorStackApplied and SafeBoolean(m.stackTextShown) == false then
            ClearIconStackText(icon)
            icon._lastMirrorStackTextEpoch = m.stackTextEpoch
        elseif not mirrorStackApplied
            and IsAuraEntry(entry)
            and _resolverRuntimePolicy.ResolvedAuraStateIsActive(r) and not r.isTotemInstance then
            local preserveMissingCount = InCombatLockdown()
            ApplyAuraCountText(icon, r.count, entry.hasCharges, preserveMissingCount)
            icon._lastMirrorStackTextEpoch = m.stackTextEpoch
        elseif not mirrorStackApplied and not InCombatLockdown() then
            ClearIconStackText(icon)
        end
    else
        if not mirrorStackApplied then
            ClearIconStackText(icon)
        end
        if icon.Icon then
            local baseTex = GetEntryTexture(entry) or GetSpellTexture(runtimeSid)
            icon._desiredTexture = nil
            if baseTex and baseTex ~= icon._lastTexture then
                icon.Icon.SetTexture(icon.Icon, baseTex)
                icon._lastTexture = baseTex
            end
        end
    end

    local epoch = m.mirrorEpoch or 0
    local mirrorActiveDur = active and durObj
    local newSrcCat   = mirrorActiveDur and (durObjSource or "mirror") or nil
    local newSrcCDID  = mirrorActiveDur and cooldownID or nil
    local newSrcEpoch = mirrorActiveDur and epoch or nil
    local priorSrcCat   = icon._lastMirrorNativeAuraSourceCat
    local priorSrcCDID  = icon._lastMirrorNativeAuraSourceCDID
    local priorSrcEpoch = icon._lastMirrorNativeAuraSourceEpoch
    icon._lastMirrorNativeAuraSourceCat   = newSrcCat
    icon._lastMirrorNativeAuraSourceCDID  = newSrcCDID
    icon._lastMirrorNativeAuraSourceEpoch = newSrcEpoch
    icon._mirrorNativeDurObjApplied = nil

    icon._lastBlizzSwipeEpoch = epoch
    if priorActive ~= active
       and entry.viewerType == "buff"
       and _resolverRuntimePolicy.RequestBuffIconLayoutRefresh then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end
    local durationSourceChanged = priorSrcCat ~= newSrcCat
        or priorSrcCDID ~= newSrcCDID
        or priorSrcEpoch ~= newSrcEpoch
        or priorHadAuraDurObj ~= (durObj and true or false)
    if debugBlizz and (priorActive ~= active or priorEpoch ~= epoch or durationSourceChanged) then
        CDMIcons._DebugBlizzEntry(debugBlizz, entry, "state-sync",
            CDMIcons._FormatMirrorState(m),
            "runtimeSid=", tostring(runtimeSid),
            "durObjSource=", tostring(durObjSource),
            "fallbackInstID=", tostring(fallbackInstID),
            "source=", tostring(icon._lastAuraSourceID),
            "durationSourceChanged=", tostring(durationSourceChanged))
    end
    return priorActive ~= active or priorEpoch ~= epoch or durationSourceChanged
end

-- Set an item-type icon to the inactive state without consulting the
-- use-cooldown resolver. Symmetric to ClearItemBarInactive in
-- cdm_bar_renderer.lua. Called when kind="aura" (built-in buff/trackedBar
-- containers) or displayMode="auraOnly" (custom containers) and the item's
-- buff is not currently active.
local function ClearItemIconInactive(icon, entry, itemID)
    ClearAuraStateForIcon(icon, entry)
    icon._resolvedCooldownMode = "inactive"
    icon._hasCooldownActive = false
    icon._hasRealCooldownActive = false
    ApplyCooldownDesaturation(icon, entry, nil, "inactive")
    _resolverRuntimePolicy.StoreIconRuntimeState(
        icon, "inactive", nil,
        itemID or (entry and (entry.id or entry.spellID)),
        nil, nil, nil, false, false, false, false, false,
        false, nil, nil)
end

local function UpdateIconCooldownOwned(icon)
    if not icon or not icon._spellEntry then return end
    -- Blizzard-mirrored aura icons render with QUI-native widgets from the
    -- exact cID mirror. The Blizzard child stays in its own viewer.
    if icon._blizzMirrorCooldownID and IsAuraEntry(icon._spellEntry) then
        local entry = icon._spellEntry
        local refreshSwipe = _resolverRuntimePolicy.SyncBlizzMirrorIconState(icon)
        local resolvedSwipe = ApplySyncedMirrorAuraCooldown(icon, entry) == true
        if refreshSwipe or resolvedSwipe then
            local swipe = ns._OwnedSwipe
            if swipe and swipe.ApplyToIcon then
                swipe.ApplyToIcon(icon)
            end
        end
        return
    end

    local entry = icon._spellEntry
    local stackTextWritesAllowed = CDMIcons.ShouldAllowStackTextWrites and CDMIcons.ShouldAllowStackTextWrites() == true
    local auraCountAppliedThisTick = false
    local preResolvedCooldownState = nil

    -- Runtime override: resolve from the base spell each tick so dynamic
    -- transforms are always current. Shared across all paths in this function.
    local _runtimeSid = entry.spellID or entry.overrideSpellID or entry.id
    if _runtimeSid and not IsAuraEntry(entry) then
        local ovId = QueryOverrideSpell(_runtimeSid)
        if ovId then _runtimeSid = ovId end
    end
    icon._runtimeSpellID = _runtimeSid

    local macroResolvedID, macroResolvedType, macroFallbackTex
    if entry.type == "macro" then
        macroResolvedID, macroResolvedType, macroFallbackTex = ResolveMacro(entry)
        if macroResolvedID and macroResolvedType == "spell" then
            _runtimeSid = macroResolvedID
            icon._runtimeSpellID = macroResolvedID
        end
    end

    do
        if IsAuraEntry(entry) then
            local auraSpellID = _runtimeSid
            if not auraSpellID then
                return
            end

            local r = _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, auraSpellID, true)
            if not r then
                -- For item-type entries with kind="aura" (items placed in
                -- built-in buff/trackedBar containers), the aura-facts
                -- resolver returns nil when the item's buff is not active.
                -- Explicitly store the inactive state so the icon correctly
                -- reflects that the buff is absent rather than silently
                -- keeping whatever state it last had.
                if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then
                    local _auraNilItemID
                    if entry.type == "slot" or entry.type == "trinket" then
                        _auraNilItemID = Sources and Sources.QueryInventoryItemID
                            and Sources.QueryInventoryItemID("player", entry.id)
                    else
                        _auraNilItemID = (Sources and Sources.QueryBestOwnedItemVariant
                            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
                    end
                    ClearItemIconInactive(icon, entry, _auraNilItemID)
                end
                return
            end
            icon._totemSlot = entry._totemSlot or nil

            if _resolverRuntimePolicy.ResolvedAuraStateIsActive(r) then
                ApplyAuraStateToIcon(icon, entry, auraSpellID, r)

                if r.isTotemInstance then
                    ClearIconStackText(icon)
                else
                    ApplyAuraCountText(icon, r.count, entry.hasCharges, InCombatLockdown())
                end

                if icon.Icon then
                    local mirrored = false
                    if r.isTotemInstance then
                        if r.totemIcon then
                            icon._totemIconCache = r.totemIcon
                        end
                        local totemTex = r.totemIcon or icon._totemIconCache
                        if totemTex then
                            icon._desiredTexture = nil
                            icon.Icon.SetTexture(icon.Icon, totemTex)
                            icon._lastTexture = totemTex
                            mirrored = true
                        end
                    end
                    if not mirrored and not r.isTotemInstance then
                        local auraIcon = r.auraData and r.auraData.icon
                        if auraIcon then
                            icon._desiredTexture = nil
                            icon.Icon.SetTexture(icon.Icon, auraIcon)
                            icon._lastTexture = nil
                            mirrored = true
                        end
                        if not mirrored then
                            local texID = GetSpellTexture(r.resolvedAuraSpellID or auraSpellID)
                            if texID and texID ~= icon._lastTexture then
                                icon.Icon:SetTexture(texID)
                                icon._lastTexture = texID
                            end
                        end
                    end
                end

                ApplyResolvedCooldown(icon, r)
                ReapplySwipeStyle(icon.Cooldown, icon)
                return
            else
                local wasAuraActive = icon._auraActive
                ApplyAuraStateToIcon(icon, entry, auraSpellID, r)

                if icon.Icon then
                    local baseTex = GetEntryTexture(entry) or GetSpellTexture(auraSpellID)
                    icon._desiredTexture = nil
                    if baseTex and baseTex ~= icon._lastTexture then
                        icon.Icon.SetTexture(icon.Icon, baseTex)
                        icon._lastTexture = baseTex
                    end
                end

                ClearIconStackText(icon)
                if wasAuraActive then
                    ApplyResolvedCooldown(icon, r)
                end
                return
            end
        end
    end

    if entry.type == "macro" then
        local newTex
        if macroResolvedID then
            if macroResolvedType == "item" then
                newTex = QueryItemVisualTexture(macroResolvedID)
            else
                newTex = GetSpellTexture(macroResolvedID)
            end
        else
            newTex = macroFallbackTex
        end
        if newTex and icon.Icon and newTex ~= icon._lastTexture then
            icon.Icon:SetTexture(newTex)
            icon._lastTexture = newTex
            UpdateIconProfessionQuality(icon)
        end
    elseif entry.type == "trinket" or entry.type == "slot" then
        local slotID = entry.id
        local itemID
        if Sources and Sources.QueryInventoryItemID then
            itemID = Sources.QueryInventoryItemID("player", slotID)
        end
        if itemID and icon.Icon then
            RefreshInventoryItemVisuals(icon, entry, itemID)
        end
        if stackTextWritesAllowed then
            _resolverRuntimePolicy.HideIconStackText(icon, "slot-clear")
        end
    elseif entry.type == "item" then
        local itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        RefreshItemIconVisuals(icon, entry, itemID)
        if stackTextWritesAllowed and Sources and Sources.QueryItemCount then
            local containerDB = GetTrackerSettings(entry.viewerType)
            local includeUses = containerDB and containerDB.showItemCharges == true
            local count = Sources.QueryItemCount(itemID, false, includeUses, true)
            local baseCount
            if includeUses then
                baseCount = Sources.QueryItemCount(itemID, false, false, true)
            end
            if issecretvalue and issecretvalue(count) then
                _resolverRuntimePolicy.ShowIconStackText(icon, count, containerDB, "item-count")
            elseif IsSafeNumeric(count) then
                local stackColor = icon._rowConfig and icon._rowConfig.stackTextColor or {1, 1, 1, 1}
                local numericCount = count
                if numericCount > 1 then
                    if icon.StackText.SetTextColor then
                        icon.StackText:SetTextColor(stackColor[1], stackColor[2], stackColor[3], stackColor[4] or 1)
                    end
                    _resolverRuntimePolicy.ShowIconStackText(icon, tostring(numericCount), containerDB, "item-count")
                elseif numericCount == 1 then
                    _resolverRuntimePolicy.HideIconStackText(icon, "item-count-one")
                elseif includeUses
                    and (issecretvalue and issecretvalue(baseCount)
                        or (IsSafeNumeric(baseCount) and baseCount > 0)) then
                    _resolverRuntimePolicy.HideIconStackText(icon, "item-count-no-uses")
                else
                    if icon.StackText.SetTextColor then
                        icon.StackText:SetTextColor((stackColor[1] or 1) * 0.5, (stackColor[2] or 1) * 0.5, (stackColor[3] or 1) * 0.5, stackColor[4] or 1)
                    end
                    _resolverRuntimePolicy.ShowIconStackText(icon, "0", containerDB, "item-count-zero")
                end
            elseif includeUses
                and (issecretvalue and issecretvalue(baseCount)
                    or (IsSafeNumeric(baseCount) and baseCount > 0)) then
                _resolverRuntimePolicy.HideIconStackText(icon, "item-count-no-uses")
            else
                _resolverRuntimePolicy.ShowIconStackText(icon, "0", containerDB, "item-count-fallback")
            end
        end
    else
        local _chargedAuraActive = false
        local _chargedTotemTexture = nil
        local useBuffSwipe = _resolverRuntimePolicy.ShouldUseBuffSwipeForIcon(icon, entry)
        if useBuffSwipe then
            local _cBaseID = _runtimeSid
            local r = _resolverRuntimePolicy.ResolveAuraFactsForIcon(icon, entry, _cBaseID, true)
            preResolvedCooldownState = r
            if _resolverRuntimePolicy.ResolvedAuraStateIsActive(r) then
                ApplyAuraStateToIcon(icon, entry, _cBaseID, r)
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
                if icon.Cooldown and r.durObj then
                    _chargedAuraActive = true
                    ReapplySwipeStyle(icon.Cooldown, icon)
                end
                local mirrorStackHasState = false
                if icon._blizzMirrorCooldownID and _resolverRuntimePolicy.ResolveMirrorStackText then
                    local _, _, _, _, mirrorHasState =
                        _resolverRuntimePolicy.ResolveMirrorStackText(icon)
                    mirrorStackHasState = mirrorHasState == true
                end
                if not entry.hasCharges and not IsTotemSlotEntry(entry) and not mirrorStackHasState then
                    local count = r.count
                    auraCountAppliedThisTick = count and count.shown == true or false
                    ApplyAuraCountText(icon, r.count, false, InCombatLockdown())
                end
            elseif r then
                local wasAuraActive = icon._auraActive
                ApplyAuraStateToIcon(icon, entry, _cBaseID, r)
                if wasAuraActive and icon.Cooldown then
                    ReapplySwipeStyle(icon.Cooldown, icon)
                end
            end
        elseif icon._auraActive then
            ClearAuraStateForIcon(icon, entry)
            if icon.Cooldown then ReapplySwipeStyle(icon.Cooldown, icon) end
        end

        if icon.Icon and _chargedAuraActive and _chargedTotemTexture then
            icon._desiredTexture = nil
            icon.Icon.SetTexture(icon.Icon, _chargedTotemTexture)
            icon._lastTexture = _chargedTotemTexture
        elseif icon.Icon and not entry.isAura then
            local texID = GetSpellTexture(_runtimeSid)
            if texID and icon._desiredTexture ~= texID then
                icon._desiredTexture = texID
                icon.Icon.SetTexture(icon.Icon, texID)
            end
        elseif icon.Icon then
            icon._desiredTexture = nil
        end
    end

    -- For aura-kind entries (items in built-in buff/trackedBar containers)
    -- and for entries with displayMode="auraOnly" (custom containers, item
    -- types only), do NOT fall through to the cooldown resolver when the
    -- item's buff is inactive — go inactive instead.
    -- Mirrors UpdateItemBarCooldown's ClearItemBarInactive gate in
    -- cdm_bar_renderer.lua.
    if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then
        local _coerceItemID
        if entry.type == "slot" or entry.type == "trinket" then
            _coerceItemID = Sources and Sources.QueryInventoryItemID
                and Sources.QueryInventoryItemID("player", entry.id)
        else
            _coerceItemID = (Sources and Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
        end
        local _isAuraKind = entry.kind == "aura"
        local _coerceContainerDB = GetTrackerSettings(entry.viewerType)
        local _isCustom = IsCustomBarContainer(_coerceContainerDB)
        local _isAuraOnlyOverride = _isCustom
            and entry.displayMode == "auraOnly"
        if _isAuraKind or _isAuraOnlyOverride then
            -- Check whether the item's buff is currently active.
            local _auraIsActive = false
            if Sources and Sources.QueryScannedItemAuraInfo and _coerceItemID then
                local scanned = Sources.QueryScannedItemAuraInfo(_coerceItemID)
                if scanned and scanned.active == true then
                    local readableDuration = type(scanned.duration) == "number"
                        and scanned.duration or nil
                    local readableExpiration = type(scanned.expiration) == "number"
                        and scanned.expiration or nil
                    if readableDuration and readableDuration > 0
                       and readableExpiration
                       and (readableExpiration - GetTime()) > 0 then
                        _auraIsActive = true
                    end
                end
            end
            if not _auraIsActive then
                ClearItemIconInactive(icon, entry, _coerceItemID)
                return
            end
        end
    end

    local resolvedApplied = ApplyResolvedCooldown(icon, preResolvedCooldownState) == true
    local resolvedState = ns.CDMRuntimeStore and ns.CDMRuntimeStore.GetFrameState
        and ns.CDMRuntimeStore.GetFrameState(icon) or nil
    local startTime = resolvedState and resolvedState.start
    local duration = resolvedState and resolvedState.duration
    local durObj = resolvedState and resolvedState.durObj
    local resolvedMode = resolvedState and resolvedState.mode or icon._resolvedCooldownMode
    local resolvedActive = resolvedState and resolvedState.active == true
        or icon._hasCooldownActive == true
    local runtimeHasCharges = entry.hasCharges == true
        or (resolvedState and resolvedState.hasCharges == true)

    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
        CDMIcons.DebugIconEvent(icon, "resolve",
            "sid=", tostring(_runtimeSid),
            "mode=", tostring(resolvedMode),
            "start=", tostring(startTime),
            "duration=", tostring(duration),
            "durObj=", durObj and "yes" or "no",
            "active=", tostring(resolvedActive),
            "hasCharges=", tostring(runtimeHasCharges),
            "entryHasCharges=", tostring(entry.hasCharges),
            "kind=", tostring(entry.kind),
            "type=", tostring(entry.type))
    end

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
    if not startTime and not duration then
        icon._lastStart = 0
        icon._lastDuration = 0
    end

    if icon.Cooldown then
        local realCooldownActive = icon._hasCooldownActive == true
            and _resolverRuntimePolicy.IsRealCooldownDurationMode(resolvedMode)
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "classify",
                "real=", tostring(realCooldownActive),
                "gcdOnly=", tostring(resolvedMode == "gcd-only"),
                "resolvedActive=", tostring(resolvedActive),
                "durObj=", durObj and "yes" or "no")
        end

        local prevGCD = icon._wasShowingGCDSwipe or false
        local curGCD = icon._showingGCDSwipe or false
        local prevActive = icon._wasResolvedCooldownActive
        local curActive = icon._hasCooldownActive == true
        if resolvedApplied or prevGCD ~= curGCD or prevActive ~= curActive then
            icon._wasShowingGCDSwipe = curGCD
            icon._wasResolvedCooldownActive = curActive
            ReapplySwipeStyle(icon.Cooldown, icon)
        end

        if _resolverRuntimePolicy.IsRealCooldownDurationMode(resolvedMode) and icon._usabilityTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._usabilityTinted = nil
            icon._lastVisualState = nil
        end
    end

    do
        local containerDB = GetTrackerSettings(entry.viewerType)
        if IsCustomBarContainer(containerDB) then
            _resolverRuntimePolicy.ApplyCustomBarActiveState(icon, entry, containerDB)
        else
            icon._customBarActive = nil
            _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
        end
    end

    local _cachedChargeInfo = nil
    local _cachedChargeInfoQueried = false

    local _stackTextResolved = false
    local _stackVal
    local _stackSource
    local _stackMirrorBacked = false
    local _stackMirrorEmpty = false
    local _stackMirrorHidden = false

    if stackTextWritesAllowed and entry.type == "spell" and _resolverRuntimePolicy.ResolveIconStackText then
        _stackVal, _stackSource, _stackMirrorBacked, _stackMirrorHidden = _resolverRuntimePolicy.ResolveIconStackText(icon)
        _stackTextResolved = true
        if _stackMirrorBacked and _resolverRuntimePolicy.ValueIsMissing(_stackVal) then
            _stackMirrorEmpty = true
            if (_stackMirrorHidden and (runtimeHasCharges or not auraCountAppliedThisTick))
               or ((not _stackMirrorHidden) and not auraCountAppliedThisTick and not runtimeHasCharges) then
                _resolverRuntimePolicy.HideIconStackText(icon, _stackMirrorHidden and "mirror-stack-hidden" or "mirror-stack-empty")
                icon._stackTextSource = nil
            end
        end
    end

    local _chargeCountForwarded = false
    local _allowChargeCountForwarder = not _stackMirrorBacked
        or (runtimeHasCharges and _stackMirrorEmpty and not _stackMirrorHidden and not InCombatLockdown())
    if stackTextWritesAllowed and entry.type == "spell" and _allowChargeCountForwarder then
        local chargeQueryID = _runtimeSid
        local baseSid = entry.spellID or entry.id
        if chargeQueryID and not _cachedChargeInfoQueried then
            _cachedChargeInfo = QueryCharges(chargeQueryID)
            _cachedChargeInfoQueried = true
        end
        local ci = _cachedChargeInfo
        local ciMax = ci and ci.maxCharges
        local ciMaxIsMulti = IsSafeNumeric(ciMax) and ciMax > 1
        if (not ciMaxIsMulti)
            and baseSid
            and baseSid ~= chargeQueryID then
            local bci = QueryCharges(baseSid)
            local bciMax = bci and bci.maxCharges
            if IsSafeNumeric(bciMax) and bciMax > 1 then
                ci = bci
                ciMax = bciMax
                ciMaxIsMulti = true
                chargeQueryID = baseSid
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "FWD base fallback: baseSid=", baseSid,
                        "maxCharges=", bciMax, "currentCharges=", bci.currentCharges)
                end
            end
        end
        if (not ciMaxIsMulti)
            and entry.overrideSpellID
            and entry.overrideSpellID ~= chargeQueryID
            and entry.overrideSpellID ~= baseSid then
            local oci = QueryCharges(entry.overrideSpellID)
            local ociMax = oci and oci.maxCharges
            if IsSafeNumeric(ociMax) and ociMax > 1 then
                ci = oci
                ciMax = ociMax
                ciMaxIsMulti = true
                chargeQueryID = entry.overrideSpellID
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "FWD override fallback: overrideSpellID=", entry.overrideSpellID,
                        "maxCharges=", ociMax, "currentCharges=", oci.currentCharges)
                end
            end
        end
        if ci and (ciMaxIsMulti or runtimeHasCharges) then
            local ccc = ci.currentCharges
            local cccIsSecret = issecretvalue and issecretvalue(ccc)
            if _G.QUI_CDM_CHARGE_DEBUG then
                local _dbgCccSource = (cccIsSecret or ccc ~= nil) and "api" or nil
                ChargeDebug(entry.name, "FWD path: baseSid=", baseSid,
                    "runtimeSid=", _runtimeSid,
                    "chargeQueryID=", chargeQueryID,
                    "maxCharges=", ciMax, "currentCharges=", ci.currentCharges,
                    "ccc=", ccc, "cccSource=", _dbgCccSource or "nil",
                    "hasCharges=", runtimeHasCharges,
                    "entryHasCharges=", entry.hasCharges,
                    "overrideSpellID=", entry.overrideSpellID)
            end
            if (cccIsSecret or ccc ~= nil) and stackTextWritesAllowed then
                _resolverRuntimePolicy.ShowIconStackText(icon, ccc, GetTrackerSettings(entry.viewerType), "fwd-charge-count")
                _chargeCountForwarded = true
            end
        end
    end

    if _G.QUI_CDM_CHARGE_DEBUG and _chargeCountForwarded then
        ChargeDebug(entry.name, "SKIP API path: chargeCountForwarded=", _chargeCountForwarded)
    end
    -- Item stack text was already set above; only spell entries need work here.
    if not _chargeCountForwarded and stackTextWritesAllowed and entry.type == "spell" then
            local spellID = _runtimeSid
            local stackVal = _stackVal
            local stackSource = _stackSource
            local stackMirrorBacked = _stackMirrorBacked
            local stackMirrorEmpty = _stackMirrorEmpty
            local stackMirrorHidden = _stackMirrorHidden

            if not _stackTextResolved and _resolverRuntimePolicy.ResolveIconStackText then
                stackVal, stackSource, stackMirrorBacked, stackMirrorHidden = _resolverRuntimePolicy.ResolveIconStackText(icon)
            end

            local cachedMaxCharges = _cachedChargeInfo and _cachedChargeInfo.maxCharges
            local isMultiCharge = IsSafeNumeric(cachedMaxCharges) and cachedMaxCharges > 1
            local allowAPIStackFallback = not stackMirrorBacked or (not stackMirrorHidden and not InCombatLockdown())

            if stackMirrorBacked and _resolverRuntimePolicy.ValueIsMissing(stackVal) and (stackMirrorHidden or not runtimeHasCharges) then
                if not stackMirrorEmpty then
                    stackMirrorEmpty = true
                    _resolverRuntimePolicy.HideIconStackText(icon, stackMirrorHidden and "mirror-stack-hidden" or "mirror-stack-empty")
                    icon._stackTextSource = nil
                end
            elseif allowAPIStackFallback
                and _resolverRuntimePolicy.ValueIsMissing(stackVal)
                and (isMultiCharge or runtimeHasCharges) then
                local ccc = _cachedChargeInfo and _cachedChargeInfo.currentCharges
                local cccIsSecret = issecretvalue and issecretvalue(ccc)
                if cccIsSecret or ccc ~= nil then
                    stackVal = ccc
                    stackSource = "spell-charge-count"
                elseif spellID then
                    stackVal = QueryDisplayCount(spellID)
                    if _resolverRuntimePolicy.ValueIsPresent(stackVal) then
                        stackSource = "spell-display-count"
                    end
                end
                if _G.QUI_CDM_CHARGE_DEBUG then
                    local dbgChargeInfo = _cachedChargeInfo or {}
                    ChargeDebug(entry.name, "API path: spellID=", spellID,
                        "maxCharges=", dbgChargeInfo.maxCharges,
                        "currentCharges=", dbgChargeInfo.currentCharges,
                        "displayCount=", stackVal, "isMultiCharge=", isMultiCharge)
                end
            elseif _resolverRuntimePolicy.ValueIsMissing(stackVal) then
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry.name, "no stack text: spellID=", spellID,
                        "mirrorBacked=", tostring(stackMirrorBacked),
                        "isMultiCharge=", tostring(isMultiCharge))
                end
            end

            if _resolverRuntimePolicy.ValueIsPresent(stackVal) then
                if isMultiCharge then
                    _resolverRuntimePolicy.ShowIconStackText(icon, stackVal, GetTrackerSettings(entry.viewerType), "api-charge-count")
                    if stackMirrorBacked then
                        icon._lastMirrorStackTextEpoch = icon.stackTextEpoch
                    end
                else
                    local displayText
                    if issecretvalue and issecretvalue(stackVal) then
                        displayText = stackVal
                    elseif type(stackVal) == "number" then
                        if stackSource == "ChargeCount" or stackSource == "spell-charge-count" then
                            displayText = tostring(stackVal)
                        else
                            displayText = C_StringUtil.TruncateWhenZero(stackVal)
                        end
                    else
                        displayText = stackVal
                    end
                    local hasText = stackMirrorBacked or HookTextHasDisplay(displayText)
                    if hasText then
                        _resolverRuntimePolicy.ShowIconStackText(icon, displayText, GetTrackerSettings(entry.viewerType), stackSource or "api-aura-stack")
                        if stackMirrorBacked then
                            icon._lastMirrorStackTextEpoch = icon.stackTextEpoch
                        end
                    else
                        _resolverRuntimePolicy.HideIconStackText(icon, "api-aura-stack-empty")
                    end
                end
            elseif stackMirrorEmpty then
                -- Mirror-backed icons with no mirror stack text and no charge fallback stay empty.
                if runtimeHasCharges then
                    _resolverRuntimePolicy.HideIconStackText(icon, stackMirrorHidden and "mirror-stack-hidden" or "charge-count-empty")
                    icon._stackTextSource = nil
                end
            elseif not InCombatLockdown() and not runtimeHasCharges then
                _resolverRuntimePolicy.HideIconStackText(icon, "api-stack-nil")
            end
        elseif entry.type == "trinket" or entry.type == "slot" then
            local stackVal
            local stackSource
            if resolvedMode == "aura" and icon._auraActive == true then
                if resolvedState and resolvedState.countShown == true then
                    stackVal = resolvedState.countSinkText
                    if _resolverRuntimePolicy.ValueIsMissing(stackVal) then
                        stackVal = resolvedState.countValue
                    end
                    stackSource = resolvedState.countSource
                end
                if _resolverRuntimePolicy.ValueIsMissing(stackVal)
                   and _resolverRuntimePolicy.GetAuraApplicationsForInstance then
                    stackVal, stackSource = _resolverRuntimePolicy.GetAuraApplicationsForInstance(
                        icon._auraUnit or (resolvedState and resolvedState.auraUnit) or "player",
                        icon._auraInstanceID or (resolvedState and resolvedState.auraInstanceID),
                        "item-aura-stack",
                        2)
                end
            end

            if _resolverRuntimePolicy.ValueIsPresent(stackVal) then
                local displayText
                if issecretvalue and issecretvalue(stackVal) then
                    displayText = stackVal
                elseif type(stackVal) == "number" then
                    displayText = C_StringUtil.TruncateWhenZero(stackVal)
                else
                    displayText = stackVal
                end
                local hasText = HookTextHasDisplay(displayText)
                if hasText then
                    _resolverRuntimePolicy.ShowIconStackText(icon, displayText, GetTrackerSettings(entry.viewerType), stackSource or "item-aura-stack")
                else
                    _resolverRuntimePolicy.HideIconStackText(icon, "item-aura-stack-empty")
                end
            elseif not InCombatLockdown() then
                _resolverRuntimePolicy.HideIconStackText(icon, "item-aura-stack-nil")
            end
        elseif entry.type ~= "item" then
            -- Item entries set their bag-count badge above (item-count /
            -- item-count-zero / item-count-fallback writes). Falling
            -- through to the harvested-aura fallback would call
            -- HideIconStackText("harvested-stack-nil") for items — their
            -- itemID-as-spellID never resolves an aura — silently
            -- clobbering the count immediately after it was shown.
            -- Macro/spell entries still need this branch: macro entries
            -- in aura-family containers rely on this path to clear; spell
            -- entries are the primary use. Slot/trinket entries use their
            -- active item aura instance above so the equipment slot number
            -- is never treated as a spell/count source.
            local stackVal = GetAuraApplicationsForSpell(_runtimeSid, entry, icon)
            if _resolverRuntimePolicy.ValueIsPresent(stackVal) then
                local displayText
                if issecretvalue and issecretvalue(stackVal) then
                    displayText = stackVal
                elseif type(stackVal) == "number" then
                    displayText = C_StringUtil.TruncateWhenZero(stackVal)
                else
                    displayText = stackVal
                end
                local hasText = HookTextHasDisplay(displayText)
                if hasText then
                    _resolverRuntimePolicy.ShowIconStackText(icon, displayText, GetTrackerSettings(entry.viewerType), "harvested-aura-stack")
                else
                    _resolverRuntimePolicy.HideIconStackText(icon, "harvested-aura-stack-empty")
                end
            elseif not InCombatLockdown() then
                _resolverRuntimePolicy.HideIconStackText(icon, "harvested-stack-nil")
            end
    end

    if icon._lastVisualState == "unusable"
       and not icon._usabilityTinted
       and not _resolverRuntimePolicy.CooldownHasVisualPriority(icon, entry, GetTrackerSettings(entry.viewerType), GetRefreshBatchTime()) then
        icon.Icon:SetVertexColor(0.4, 0.4, 0.4, 1)
        icon._usabilityTinted = true
    end
end

UpdateIconCooldown = function(icon)
    if RuntimeQueries and RuntimeQueries.WithRuntimeQueryOwner then
        return RuntimeQueries.WithRuntimeQueryOwner(icon, UpdateIconCooldownOwned, icon)
    end
    return UpdateIconCooldownOwned(icon)
end

---------------------------------------------------------------------------
-- IsCustomBarEntryUsableOnCurrentClass: cross-class filter for the
-- customBar build-time render path.  A QUI profile is often shared across
-- multiple classes; entries added on one class persist in db.entries and
-- would otherwise spawn runtime icons for spells the current character
-- cannot cast.
--
-- Mirrors the composer's IsEntryUsableOnCurrentPlayer predicate so the
-- two views agree on which entries are "for this character":
--   * non-spell types (item/macro/slot)     → always pass (not class-bound)
--   * aura-kind spell entries               → always pass (buff IDs aren't
--                                              in the spellbook; runtime
--                                              aura resolution decides)
--   * cooldown-kind spell entries           → IsSpellKnown gate
---------------------------------------------------------------------------
local function IsCustomBarEntryUsableOnCurrentClass(entry)
    if type(entry) ~= "table" then return true end
    if entry.type ~= "spell" then return true end
    if type(entry.id) ~= "number" then return true end
    if entry.kind == "aura" then return true end
    local spellData = ns.CDMSpellData
    if not spellData or type(spellData.IsSpellKnown) ~= "function" then
        return true
    end
    return spellData:IsSpellKnown(entry.id) == true
end

---------------------------------------------------------------------------
-- Build a spellEntry record from a user-curated custom entry.
-- Used by both legacy essential/utility custom merges (Phase G) and
-- Phase B.3 custom-container rendering (customBar / user-created cooldown).
-- Returns a fully-populated spellEntry or nil if the entry is unusable.
---------------------------------------------------------------------------
local function BuildSpellEntryFromCustom(entry, idx, viewerType)
    if type(entry) ~= "table" or entry.id == nil then return nil end
    local isSpellType = (entry.type ~= "item" and entry.type ~= "trinket" and entry.type ~= "slot")
    -- Forward the entry's stamped kind onto the synthesized spellEntry so
    -- downstream IsAuraEntry / visibility / ID-correction code branches per
    -- entry instead of per container. Falls through to viewerType-based
    -- classification when the legacy entry lacks an explicit kind.
    local kind = entry.kind
    if not (kind == "aura" or kind == "cooldown") then
        if not isSpellType then
            kind = "cooldown"
        else
            local impliedKind = Shared and Shared.GetContainerEntryKind
                and Shared.GetContainerEntryKind(viewerType)
                or GetBuiltinContainerEntryKind(viewerType)
            if impliedKind then
                kind = impliedKind
            else
                local CDMSpellData = ns.CDMSpellData
                kind = (CDMSpellData and CDMSpellData.ResolveEntryKind
                    and CDMSpellData.ResolveEntryKind(entry, viewerType)) or "cooldown"
            end
        end
    end
    local isAuraEntry = (kind == "aura")
    local itemID = (entry.type == "item")
        and ((Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id)
        or nil
    local spellEntry = {
        spellID = isSpellType and entry.id or nil,
        overrideSpellID = isSpellType and entry.id or nil,
        name = "",
        isAura = isAuraEntry or false,
        kind = kind,
        layoutIndex = 99000 + (idx or 0),
        viewerType = viewerType,
        type = entry.type,
        id = itemID or entry.id,
        itemID = itemID,
        _isCustomEntry = true,
        _sourceSpecID = entry._sourceSpecID,
    }
    if entry.type == "macro" then
        spellEntry.macroName = entry.macroName
        spellEntry.name = entry.macroName or ""
        local resolvedID = ResolveMacro(spellEntry)
        if resolvedID then
            spellEntry.spellID = resolvedID
            spellEntry.overrideSpellID = resolvedID
        end
    elseif entry.type == "trinket" or entry.type == "slot" then
        local itemID = Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID("player", entry.id)
        if itemID then
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            spellEntry.name = itemName or ""
        end
    elseif entry.type == "item" then
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(spellEntry.id)
        spellEntry.name = itemName or ""
    else
        local storedName = entry.name
        if type(storedName) == "string" and true and storedName ~= "" then
            spellEntry.name = storedName
        else
            spellEntry.name = GetCachedSpellName(entry.id) or ""
        end
    end
    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugEntryBuild then
        CDMIcons.DebugEntryBuild(entry, spellEntry, viewerType)
    end
    return spellEntry
end

local function AppendSignaturePart(parts, value)
    parts[#parts + 1] = tostring(value == nil and "" or value)
end

local function AppendEntrySignature(parts, prefix, entry, idx)
    AppendSignaturePart(parts, prefix)
    AppendSignaturePart(parts, idx)
    if type(entry) ~= "table" then
        AppendSignaturePart(parts, "nil")
        return
    end
    AppendSignaturePart(parts, entry.type or "spell")
    AppendSignaturePart(parts, entry.kind)
    AppendSignaturePart(parts, entry.id)
    AppendSignaturePart(parts, entry.spellID)
    AppendSignaturePart(parts, entry.overrideSpellID)
    AppendSignaturePart(parts, "linked")
    local linkedSpellIDs = entry.linkedSpellIDs
    if type(linkedSpellIDs) == "table" then
        AppendSignaturePart(parts, #linkedSpellIDs)
        for linkedIdx, linkedID in ipairs(linkedSpellIDs) do
            AppendSignaturePart(parts, linkedIdx)
            if issecretvalue and issecretvalue(linkedID) then
                AppendSignaturePart(parts, "secret")
            else
                AppendSignaturePart(parts, linkedID)
            end
        end
    else
        AppendSignaturePart(parts, "none")
    end
    AppendSignaturePart(parts, entry.isAura and 1 or 0)
    AppendSignaturePart(parts, entry.enabled == false and 0 or 1)
    AppendSignaturePart(parts, entry.position)
    AppendSignaturePart(parts, entry.row)
    AppendSignaturePart(parts, entry._assignedRow)
    AppendSignaturePart(parts, entry._instanceKey)
    AppendSignaturePart(parts, entry._sourceSpecID)
end

local function AppendEntryListSignature(parts, prefix, list)
    if type(list) ~= "table" then
        AppendSignaturePart(parts, prefix)
        AppendSignaturePart(parts, "none")
        return
    end
    AppendSignaturePart(parts, prefix)
    AppendSignaturePart(parts, #list)
    for idx, entry in ipairs(list) do
        AppendEntrySignature(parts, prefix, entry, idx)
    end
end

local function BuildIconListSignature(viewerType, container, spellData)
    local parts = {}
    AppendSignaturePart(parts, viewerType)
    AppendEntryListSignature(parts, "harvested", spellData)

    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    local cDB = ncdm and ncdm.containers and ncdm.containers[viewerType]
    if cDB and cDB.builtIn == false then
        AppendSignaturePart(parts, "container")
        AppendSignaturePart(parts, cDB.specSpecific and 1 or 0)
        local entryList
        if cDB.specSpecific and ns.CDMSpellData and ns.CDMSpellData.GetSpecEntries then
            entryList = ns.CDMSpellData:GetSpecEntries(viewerType)
        end
        if type(entryList) ~= "table" then
            entryList = cDB.entries
        end
        AppendEntryListSignature(parts, "containerEntries", entryList)
        if type(entryList) == "table" then
            local spellDataAPI = ns.CDMSpellData
            local AuraRuntime = ns.CDMAuraRuntime
            for idx, entry in ipairs(entryList) do
                AppendSignaturePart(parts, "AppendCustomRuntimeEntrySignature")
                AppendSignaturePart(parts, idx)
                if type(entry) ~= "table" then
                    AppendSignaturePart(parts, "nil")
                else
                    local resolvedKind = entry.kind
                    if not (resolvedKind == "aura" or resolvedKind == "cooldown") then
                        resolvedKind = spellDataAPI and spellDataAPI.ResolveEntryKind
                            and spellDataAPI.ResolveEntryKind(entry, viewerType)
                            or ""
                    end
                    AppendSignaturePart(parts, resolvedKind)

                    local mappedID, remapped
                    if AuraRuntime and AuraRuntime.ResolveAbilityAuraSpellID then
                        mappedID, remapped = AuraRuntime.ResolveAbilityAuraSpellID(entry.id)
                    end
                    if issecretvalue and issecretvalue(mappedID) then
                        AppendSignaturePart(parts, "secret")
                    else
                        AppendSignaturePart(parts, mappedID)
                    end
                    AppendSignaturePart(parts, remapped and 1 or 0)

                    local auraIDs = spellDataAPI and spellDataAPI.GetAuraIDsForSpell
                        and spellDataAPI:GetAuraIDsForSpell(entry.id)
                    AppendSignaturePart(parts, "runtimeAuraIDs")
                    if type(auraIDs) == "table" then
                        AppendSignaturePart(parts, #auraIDs)
                        for auraIdx, auraID in ipairs(auraIDs) do
                            AppendSignaturePart(parts, auraIdx)
                            if issecretvalue and issecretvalue(auraID) then
                                AppendSignaturePart(parts, "secret")
                            else
                                AppendSignaturePart(parts, auraID)
                            end
                        end
                    else
                        AppendSignaturePart(parts, "none")
                    end
                end
            end
        end
        -- IsCustomBarEntryUsableOnCurrentClass verdicts can flip across
        -- a respec (talent-gated spells appear/disappear from the
        -- spellbook). Class doesn't change in-session, but specID does;
        -- stamp it so the pool rebuilds when SPELLS_CHANGED fires after
        -- a spec swap and known-spell state shifts.
        local specID = GetSpecialization and GetSpecialization()
        AppendSignaturePart(parts, "spec")
        AppendSignaturePart(parts, specID or "")
    end

    if IsBuiltinCooldownContainerKey(viewerType) then
        local customData = GetCustomData(viewerType)
        AppendSignaturePart(parts, "legacyCustom")
        AppendSignaturePart(parts, customData and customData.enabled and 1 or 0)
        AppendSignaturePart(parts, customData and customData.placement or "")
        AppendEntryListSignature(parts, "legacyEntries", customData and customData.entries)
    end

    return table.concat(parts, "|")
end

local function PoolMatchesContainer(pool, container)
    if not pool or not container or #pool == 0 then return false end
    for _, icon in ipairs(pool) do
        if icon and icon.GetParent and icon:GetParent() ~= container then
            return false
        end
    end
    return true
end

local _customPositionedScratch = {}
local _customUnpositionedScratch = {}

---------------------------------------------------------------------------
-- BUILD ICONS: Create icons from harvested spell data + custom entries
---------------------------------------------------------------------------
function CDMIcons:BuildIcons(viewerType, container)
    if not container then return {} end

    local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList(viewerType) or {}
    local signature = BuildIconListSignature(viewerType, container, spellData)
    local pool = Factory:GetIconPool(viewerType)
    local reusePool = pool
        and container._lastBuildSignature == signature
        and container._lastBuildPool == pool
        and PoolMatchesContainer(pool, container)

    if not reusePool then
        pool = Factory:ClearPool(viewerType)
        pool = Factory:EnsurePool(viewerType)

        -- Create icons from harvested spell data
        for _, entry in ipairs(spellData) do
            local icon = Factory:AcquireIcon(container, entry)
            pool[#pool + 1] = icon
        end

        -- Phase B.3: Custom containers (non-built-in) render their own entries.
        -- Covers customBar containers (migrated from legacy trackers) and any
        -- user-created cooldown / aura container from the Composer.  Entries
        -- live on the container itself under `entries`, or under a per-spec
        -- table in db.global.ncdm.specTrackerSpells when specSpecific is set.
        do
            local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
            local cDB = ncdm and ncdm.containers and ncdm.containers[viewerType]
            if cDB and cDB.builtIn == false then
                local entryList
                if cDB.specSpecific and ns.CDMSpellData and ns.CDMSpellData.GetSpecEntries then
                    entryList = ns.CDMSpellData:GetSpecEntries(viewerType)
                end
                if type(entryList) ~= "table" then
                    entryList = cDB.entries
                end
                if type(entryList) == "table" then
                    for idx, entry in ipairs(entryList) do
                        if entry and entry.enabled ~= false
                            and IsCustomBarEntryUsableOnCurrentClass(entry) then
                            local spellEntry = BuildSpellEntryFromCustom(entry, idx, viewerType)
                            if spellEntry then
                                local icon = Factory:AcquireIcon(container, spellEntry)
                                pool[#pool + 1] = icon
                            end
                        end
                    end
                end
            end
        end

        -- Merge custom entries for built-in cooldown containers.
        if IsBuiltinCooldownContainerKey(viewerType) then
            local customData = GetCustomData(viewerType)
            if customData and customData.enabled and customData.entries then
                local placement = customData.placement or "after"

                -- Separate positioned and unpositioned custom entries
                local positioned = _customPositionedScratch
                local unpositioned = _customUnpositionedScratch
                wipe(positioned)
                wipe(unpositioned)
                for idx, entry in ipairs(customData.entries) do
                    if entry.enabled ~= false then
                        local spellEntry = BuildSpellEntryFromCustom(entry, idx, viewerType)
                        if spellEntry then
                            if entry.position and entry.position > 0 then
                                positioned[#positioned + 1] = { entry = spellEntry, position = entry.position, origIndex = idx }
                            else
                                unpositioned[#unpositioned + 1] = spellEntry
                            end
                        end
                    end
                end

                -- Insert unpositioned entries (before or after harvested icons)
                if #unpositioned > 0 then
                    if placement == "before" then
                        local prefixCount = #unpositioned
                        for i = #pool, 1, -1 do
                            pool[i + prefixCount] = pool[i]
                        end
                        for i, entry in ipairs(unpositioned) do
                            pool[i] = Factory:AcquireIcon(container, entry)
                        end
                    else
                        for _, entry in ipairs(unpositioned) do
                            local icon = Factory:AcquireIcon(container, entry)
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
                    local icon = Factory:AcquireIcon(container, item.entry)
                    local insertAt = math.min(item.position, #pool + 1)
                    table.insert(pool, insertAt, icon)
                end
                wipe(positioned)
                wipe(unpositioned)
            end
        end
    end

    container._lastBuildSignature = signature
    container._lastBuildPool = pool

    -- Initialize owned icons: configure addon CD and mark aura containers
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry then
            local containerDB = GetTrackerSettings(entry.viewerType)
            local tooltipContext = containerDB and containerDB.tooltipContext
            if IsCustomBarContainer(containerDB) then
                tooltipContext = tooltipContext or "customTrackers"
            end
            icon._quiTooltipContext = tooltipContext or "cdm"
            icon.__quiTooltipContext = icon._quiTooltipContext
            icon.__customTrackerIcon = icon._quiTooltipContext == "customTrackers" or nil

            local addonCD = icon.Cooldown
            if addonCD then
                addonCD:SetDrawSwipe(true)
                addonCD:SetHideCountdownNumbers(false)
                addonCD:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                addonCD:SetSwipeColor(0, 0, 0, 0.8)
                addonCD:Show()
            end
            -- Mark aura entries so visibility handling works correctly
            if IsAuraEntry(entry) then
                icon._auraActive = false  -- will be set true by UpdateIconCooldown when aura present
                icon._auraUnit = nil
            end
        end
    end

    -- Buff icons are aura containers, but the active state must still
    -- come from UpdateIconCooldown/runtime aura resolution. Pre-marking them
    -- active here makes empty rows render as active-looking.
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry and entry.viewerType == "buff" then
            icon._auraActive = false
            icon._auraUnit = nil
        end
    end

    -- Update click-to-cast secure attributes for cooldown icons.
    -- AcquireIcon sets attrs per-icon for fresh acquisitions; when the pool
    -- is reused (signature match), AcquireIcon is skipped — so a
    -- clickableIcons toggle on essential/utility would otherwise not take
    -- effect until /reload. Run a full pass on reuse, and a pending-only
    -- pass otherwise to catch combat-deferred rebuilds via PLAYER_REGEN_ENABLED.
    if reusePool then
        for _, icon in ipairs(pool) do
            local entry = icon._spellEntry
            if entry and entry.viewerType ~= "buff" then
                UpdateIconSecureAttributes(icon, entry, entry.viewerType or viewerType)
            end
        end
    else
        for _, icon in ipairs(pool) do
            if icon._pendingSecureUpdate then
                local entry = icon._spellEntry
                if entry and entry.viewerType ~= "buff" then
                    UpdateIconSecureAttributes(icon, entry, entry.viewerType or viewerType)
                end
            end
        end
    end

    iconPools[viewerType] = pool

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

local visibilityPolicy = ns.CDMIconVisibilityPolicy and ns.CDMIconVisibilityPolicy.Create({
    isCustomBarContainer = function(containerDB)
        return IsCustomBarContainer(containerDB)
    end,
    computeCustomBarVisibility = function(icon, entry, containerDB)
        return _resolverRuntimePolicy.ComputeCustomBarVisibility(icon, entry, containerDB, GetTime())
    end,
    resolveCooldownActivityState = function(icon, entry, containerDB)
        return _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, containerDB, GetTime())
    end,
    queryItemCount = function(...)
        return Sources and Sources.QueryItemCount and Sources.QueryItemCount(...)
    end,
    queryInventoryItemID = function(...)
        return Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID(...)
    end,
    queryItemSpell = function(...)
        return Sources and Sources.QueryItemSpell and Sources.QueryItemSpell(...)
    end,
    querySpellUsable = function(...)
        return Sources and Sources.QuerySpellUsable and Sources.QuerySpellUsable(...)
    end,
    isSpellKnown = function(spellID)
        local spellData = ns.CDMSpellData
        if spellData and type(spellData.IsSpellKnown) == "function" then
            return spellData:IsSpellKnown(spellID) == true
        end
        return nil
    end,
    debugLayoutFilter = function(icon, filterHides, containerDB, isOnCD)
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugLayoutFilter then
            CDMIcons.DebugLayoutFilter(icon, filterHides, containerDB, isOnCD)
        end
    end,
    isHiddenByAnchor = function(anchorKey)
        return _G.QUI_IsFrameHiddenByAnchor and _G.QUI_IsFrameHiddenByAnchor(anchorKey)
    end,
    getContainer = function(containerKey)
        return ns.CDMContainers and ns.CDMContainers.GetContainer
            and ns.CDMContainers.GetContainer(containerKey)
    end,
    scheduleAfter = function(delay, callback)
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, callback)
        end
    end,
    onBuffLayoutReady = function()
        if ns.CDMBuffLayout and ns.CDMBuffLayout.OnLayoutReady then
            ns.CDMBuffLayout:OnLayoutReady()
        end
    end,
    forceLayoutContainer = function(trackerKey)
        if _G.QUI_ForceLayoutContainer then
            _G.QUI_ForceLayoutContainer(trackerKey)
        end
    end,
})

local function ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
    return visibilityPolicy and visibilityPolicy:ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
        or false
end

function CDMIcons.ShouldContainerLayoutPlaceIcon(icon, entry, containerDB, inCombat)
    return not visibilityPolicy
        or visibilityPolicy:ShouldPlaceLayoutIcon(icon, entry, containerDB, inCombat)
end

function _resolverRuntimePolicy.WakeBuffIconContainer()
    if visibilityPolicy then
        visibilityPolicy:WakeBuffIconContainer()
    end
end

function _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    if visibilityPolicy then
        visibilityPolicy:RequestBuffIconLayoutRefresh()
    end
end

local function MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
    if visibilityPolicy then
        visibilityPolicy:MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
    end
end

local function DrainLayoutDirty()
    if visibilityPolicy then
        visibilityPolicy:DrainLayoutDirty()
    end
end

local function ApplyIconVisibility(icon, shouldShow, dynamicLayout)
    if visibilityPolicy then
        visibilityPolicy:ApplyIconVisibility(icon, shouldShow, dynamicLayout)
    end
end

local function ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
    if not entry then return nil, "cooldown" end

    local containerDB = ncdm and (ncdm[entry.viewerType] or (ncdmContainers and ncdmContainers[entry.viewerType]))
    local cType = containerDB and containerDB.containerType
    if not cType then
        local vt = entry.viewerType
        cType = Shared and Shared.GetContainerType
            and Shared.GetContainerType(vt, containerDB)
            or GetBuiltinContainerType(vt)
            or "cooldown"
    end

    return containerDB, cType
end

local function PrepareCooldownUpdateBatch()
    if refreshBatch then
        return refreshBatch:Prepare()
    end

    local editMode = Helpers.IsEditModeActive()
        or Helpers.IsLayoutModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    _resolverRuntimePolicy.RefreshSwipeBatchSettings()
    return editMode, ncdm, ncdm and ncdm.containers, InCombatLockdown()
end

local function BeginIconRefreshBatch(reason)
    if refreshBatch then
        refreshBatch:Begin(reason)
    elseif RuntimeQueries and RuntimeQueries.BeginRuntimeQueryBatch then
        RuntimeQueries.BeginRuntimeQueryBatch()
    end
end

local function EndIconRefreshBatch()
    if refreshBatch then
        refreshBatch:End()
    elseif RuntimeQueries and RuntimeQueries.EndRuntimeQueryBatch then
        RuntimeQueries.EndRuntimeQueryBatch()
    end
end

local function SetRefreshBatchStackTextWrites(enabled)
    if refreshBatch then
        refreshBatch:SetStackTextWrites(enabled)
    elseif SetStackTextWritesForBatch then
        SetStackTextWritesForBatch(enabled)
    end
end

local function ConsumeStackTextWriteRequest()
    return refreshBatch and refreshBatch:ConsumeStackTextWriteRequest() or false
end

local function RequestStackTextUpdate()
    if refreshBatch then
        refreshBatch:RequestStackTextUpdate()
    end
end

local function UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
    local isHiddenOverride = spellOvr and spellOvr.hidden

    if isHiddenOverride then
        if icon:IsShown() then icon:Hide() end
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "hidden-override",
                "auraActive=", tostring(icon._auraActive == true),
                "shown=", tostring(icon:IsShown()))
        end
        SyncCooldownBling(icon)
        return
    end

    if editMode then
        icon:SetAlpha(1)
        icon:Show()
        SyncCooldownBling(icon)
        return
    end

    local entryIsAura = IsAuraEntry(entry)
    if IsCustomBarContainer(containerDB) then
        local visibility = _resolverRuntimePolicy.ComputeCustomBarVisibility(icon, entry, containerDB, GetRefreshBatchTime())
        local effectiveMode = containerDB and containerDB.iconDisplayMode or "always"
        if effectiveMode == "combat" then
            effectiveMode = (UnitAffectingCombat and UnitAffectingCombat("player")) and "always" or "active"
        end

        local shouldShow = visibility.renderVisible
        if effectiveMode == "active" and not visibility.isOnCooldown and not visibility.rechargeActive then
            local keepForGlow = false
            if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
            end
            shouldShow = shouldShow and keepForGlow
        elseif effectiveMode ~= "always" and effectiveMode ~= "active" then
            shouldShow = false
        end

        local filterHidesNow = not visibility.layoutVisible
        MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
        ApplyIconVisibility(icon, shouldShow, containerDB.dynamicLayout == true)
        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "show",
                "shouldShow=", tostring(shouldShow),
                "shown=", tostring(icon:IsShown()),
                "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                "effectiveMode=", tostring(effectiveMode),
                "filterHidden=", tostring(filterHidesNow),
                "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
        end
        _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
        SyncCooldownBling(icon)
        return
    end

    if entryIsAura then
        local isActive = icon._auraActive == true
        local effectiveMode = containerDB and containerDB.iconDisplayMode or "always"
        if effectiveMode == "combat" then
            effectiveMode = inCombat and "always" or "active"
        end

        if effectiveMode == "always" then
            ApplyIconVisibility(icon, true, containerDB and containerDB.dynamicLayout)
        elseif effectiveMode == "active" then
            if isActive then
                ApplyIconVisibility(icon, true, containerDB and containerDB.dynamicLayout)
            else
                if icon:IsShown() then icon:Hide() end
            end
        else
            if icon:IsShown() then icon:Hide() end
        end

        if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
            CDMIcons.DebugIconEvent(icon, "aura-show",
                "active=", tostring(isActive),
                "shown=", tostring(icon:IsShown()),
                "effectiveMode=", tostring(effectiveMode),
                "containerType=", tostring(containerDB and containerDB.containerType))
        end
        SyncCooldownBling(icon)
        return
    end

    local cooldownState = _resolverRuntimePolicy.ResolveIconCooldownActivityState(
        icon, entry, containerDB, GetRefreshBatchTime())
    local isOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

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
    -- mismatch detector sees the latest verdict even when display mode has
    -- already hidden the icon.
    local filterHidesNow = ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
    if filterHidesNow then shouldShow = false end
    MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)

    ApplyIconVisibility(icon, shouldShow, containerDB and containerDB.dynamicLayout)
    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
        CDMIcons.DebugIconEvent(icon, "show",
            "shouldShow=", tostring(shouldShow),
            "shown=", tostring(icon:IsShown()),
            "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
            "displayMode=", tostring(containerDB and containerDB.iconDisplayMode),
            "effectiveMode=", tostring(effectiveMode),
            "filterHidden=", tostring(filterHidesNow),
            "isOnCD=", tostring(isOnCD),
            "isOnCooldown=", tostring(cooldownState and cooldownState.isOnCooldown),
            "rechargeActive=", tostring(cooldownState and cooldownState.rechargeActive),
            "hasChargesRemaining=", tostring(cooldownState and cooldownState.hasChargesRemaining),
            "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
    end
    SyncCooldownBling(icon)
end

local function RefreshAllIcon(icon, context)
    context = context or {}
    local entry = icon and icon._spellEntry
    local wasAuraActive = icon and icon._auraActive == true

    -- Update cooldown/aura state before visibility so resolved runtime facts
    -- are fresh for Show/Hide decisions.
    UpdateIconCooldown(icon)

    if entry and entry.viewerType == "buff"
       and wasAuraActive ~= (icon._auraActive == true) then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end

    local editMode = context.editMode
    local ncdm = context.ncdm
    local ncdmContainers = context.ncdmContainers
    local inCombat = context.inCombat

    -- Per-spell hidden override: always hide regardless of display mode.
    local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
    local isHiddenOverride = spellOvr and spellOvr.hidden

    if entry then
        -- Visibility branches per entry kind (aura vs cooldown). Container
        -- shape (icon vs bar) is decoupled — a cooldown entry on a bar-shaped
        -- container takes the cooldown branch, aura entries on an icon-shaped
        -- container take the aura branch.
        local containerDB = ncdm
            and (ncdm[entry.viewerType] or (ncdmContainers and ncdmContainers[entry.viewerType]))
        local displayMode = containerDB and containerDB.iconDisplayMode or "always"
        local entryIsAura = IsAuraEntry(entry)

        if isHiddenOverride then
            if icon:IsShown() then icon:Hide() end
        elseif editMode then
            icon:SetAlpha(1)
            icon:Show()
        elseif entryIsAura then
            local isActive = icon._auraActive
            local effectiveMode = displayMode
            if effectiveMode == "combat" then
                effectiveMode = inCombat and "always" or "active"
            end

            if IsCustomBarContainer(containerDB) then
                local visibility = _resolverRuntimePolicy.ComputeCustomBarVisibility(
                    icon, entry, containerDB, GetRefreshBatchTime())
                local shouldShow = visibility.renderVisible
                if effectiveMode == "active" and not isActive then
                    local keepForGlow = false
                    if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                        keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
                    end
                    shouldShow = shouldShow and keepForGlow
                elseif effectiveMode ~= "always" and effectiveMode ~= "active" then
                    shouldShow = false
                end

                local filterHidesNow = not visibility.layoutVisible
                MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
                ApplyIconVisibility(icon, shouldShow, containerDB.dynamicLayout == true)
                if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                    CDMIcons.DebugIconEvent(icon, "show",
                        "shouldShow=", tostring(shouldShow),
                        "shown=", tostring(icon:IsShown()),
                        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                        "displayMode=", tostring(displayMode),
                        "effectiveMode=", tostring(effectiveMode),
                        "filterHidden=", tostring(filterHidesNow),
                        "auraActive=", tostring(isActive),
                        "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                end
                _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
                SyncCooldownBling(icon)
            else
                if effectiveMode == "always" then
                    local rowOpacity = icon._rowOpacity or 1
                    icon:SetAlpha(rowOpacity)
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
            end
        else
            local cooldownState = _resolverRuntimePolicy.ResolveIconCooldownActivityState(
                icon, entry, containerDB, GetRefreshBatchTime())
            local isOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

            local effectiveMode = displayMode
            if effectiveMode == "combat" then
                effectiveMode = (UnitAffectingCombat and UnitAffectingCombat("player")) and "always" or "active"
            end

            if IsCustomBarContainer(containerDB) then
                local visibility = _resolverRuntimePolicy.ComputeCustomBarVisibility(
                    icon, entry, containerDB, GetRefreshBatchTime())
                local shouldShow = visibility.renderVisible
                if effectiveMode == "active" and not visibility.isOnCooldown and not visibility.rechargeActive then
                    local keepForGlow = false
                    if ns._OwnedGlows and ns._OwnedGlows.ShouldIconGlow then
                        keepForGlow = ns._OwnedGlows.ShouldIconGlow(icon)
                    end
                    shouldShow = shouldShow and keepForGlow
                elseif effectiveMode ~= "always" and effectiveMode ~= "active" then
                    shouldShow = false
                end

                local filterHidesNow = not visibility.layoutVisible
                MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
                ApplyIconVisibility(icon, shouldShow, containerDB.dynamicLayout == true)
                if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                    CDMIcons.DebugIconEvent(icon, "show",
                        "shouldShow=", tostring(shouldShow),
                        "shown=", tostring(icon:IsShown()),
                        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                        "effectiveMode=", tostring(effectiveMode),
                        "filterHidden=", tostring(filterHidesNow),
                        "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                end
                _resolverRuntimePolicy.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
                SyncCooldownBling(icon)
            else
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

                local filterHidesNow = ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
                if filterHidesNow then shouldShow = false end
                MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)
                ApplyIconVisibility(icon, shouldShow, containerDB and containerDB.dynamicLayout)
                if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
                    CDMIcons.DebugIconEvent(icon, "show",
                        "shouldShow=", tostring(shouldShow),
                        "shown=", tostring(icon:IsShown()),
                        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                        "effectiveMode=", tostring(effectiveMode),
                        "filterHidden=", tostring(filterHidesNow),
                        "isOnCD=", tostring(isOnCD),
                        "isOnCooldown=", tostring(cooldownState and cooldownState.isOnCooldown),
                        "rechargeActive=", tostring(cooldownState and cooldownState.rechargeActive),
                        "hasChargesRemaining=", tostring(cooldownState and cooldownState.hasChargesRemaining),
                        "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                end
            end

            local greyOutDebuffs = containerDB and containerDB.greyOutInactive
            local greyOutBuffs = containerDB and containerDB.greyOutInactiveBuffs
            local shouldGreyOut = false
            if (greyOutDebuffs or greyOutBuffs) and icon.Icon and icon.Icon.SetDesaturated then
                local hasAbilityAuraMapping = false
                local AuraRuntime = ns.CDMAuraRuntime
                if AuraRuntime and AuraRuntime.HasAbilityAuraMapping then
                    hasAbilityAuraMapping = AuraRuntime.HasAbilityAuraMapping(entry.id)
                end
                local hasAuraLink = entry.linkedSpellIDs
                    or (icon._spellEntry and icon._spellEntry.linkedSpellIDs)
                    or hasAbilityAuraMapping
                    or icon._auraActive ~= nil
                if hasAuraLink then
                    local spellName = entry.name
                    if not spellName then
                        local sid = icon._runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
                        if sid then
                            local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
                            spellName = info and info.name
                        end
                    end

                    if not icon._greyType and spellName then
                        local isHarm = Sources and Sources.QuerySpellHarmful and Sources.QuerySpellHarmful(spellName)
                        local isHelp = Sources and Sources.QuerySpellHelpful and Sources.QuerySpellHelpful(spellName)
                        if isHarm then
                            icon._greyType = "debuff"
                        elseif isHelp then
                            icon._greyType = "buff"
                        end
                    end

                    if greyOutDebuffs and icon._greyType == "debuff" then
                        local hasTarget = UnitExists("target")
                            and not UnitIsDead("target")
                            and UnitCanAttack("player", "target")
                        if hasTarget and not icon._auraActive then
                            shouldGreyOut = true
                        end
                    end
                    if not shouldGreyOut and greyOutBuffs and icon._greyType == "buff" then
                        if not icon._auraActive then
                            shouldGreyOut = true
                        end
                    end
                end
            end
            if shouldGreyOut then
                if not icon._greyedOut then
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

ApplyVisibleMirrorStackTextIfNeeded = function(icon, entry)
    if not (icon and entry and icon._blizzMirrorCooldownID and icon._blizzMirrorCategory) then
        return false
    end
    if IsAuraEntry(entry) then
        return false
    end
    if not _resolverRuntimePolicy.ApplyMirrorStackText then
        return false
    end
    if _resolverRuntimePolicy.ShouldHideIconStackText(icon, GetTrackerSettings(entry.viewerType)) then
        return false
    end

    local mirrorState = GetCachedMirrorStateForIcon(icon)
        or RefreshCachedMirrorStateForIcon(icon)
    if not mirrorState then
        return false
    end

    if _resolverRuntimePolicy.ResolveMirrorStackText then
        local mirrorText, _, mirrorBacked, mirrorHidden =
            _resolverRuntimePolicy.ResolveMirrorStackText(icon)
        if mirrorBacked
            and mirrorHidden == true
            and _resolverRuntimePolicy.ValueIsMissing(mirrorText) then
            ClearIconStackText(icon, "mirror-stack-hidden")
            icon._lastMirrorStackTextEpoch = mirrorState.stackTextEpoch
            return true
        end
    end

    local stackShown = icon.StackText and icon.StackText.IsShown and icon.StackText:IsShown() == true
    local stackEpoch = mirrorState.stackTextEpoch
    if stackShown and (stackEpoch == nil or icon._lastMirrorStackTextEpoch == stackEpoch) then
        return false
    end

    return _resolverRuntimePolicy.ApplyMirrorStackText(icon, mirrorState, entry.hasCharges) == true
end

local function UpdateCooldownOnlyIcon(icon, entry)
    if icon._blizzMirrorCooldownID and not IsAuraEntry(entry) then
        if CDMIcons.ShouldAllowStackTextWrites and CDMIcons.ShouldAllowStackTextWrites() == true then
            UpdateIconCooldown(icon)
            return
        end
        ApplyResolvedCooldown(icon)
        SyncCooldownBling(icon)
        return
    end
    UpdateIconCooldown(icon)
end

local function CreateIconRefreshWalker()
    local module = ns.CDMIconRefreshWalker
    if not (module and module.Create) then return nil end
    return module.Create({
        getIconPools = function()
            return iconPools
        end,
        refreshAllIcon = RefreshAllIcon,
        resolveContainerDBAndType = ResolveContainerDBAndType,
        refreshCooldownOnlyIcon = UpdateCooldownOnlyIcon,
        updateIconVisibility = UpdateCooldownContainerVisibility,
        refreshTypeIcon = function(icon)
            UpdateIconCooldown(icon)
        end,
    })
end

local function GetIconRefreshWalker()
    if not refreshWalker then
        refreshWalker = CreateIconRefreshWalker()
    end
    return refreshWalker
end

---------------------------------------------------------------------------
-- UPDATE ALL COOLDOWNS
---------------------------------------------------------------------------
function CDMIcons:UpdateAllCooldowns()
    local editMode, _ncdm, _ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    SetRefreshBatchStackTextWrites(true)
    BeginIconRefreshBatch("updateAll")

    local context = {
        editMode = editMode,
        ncdm = _ncdm,
        ncdmContainers = _ncdmContainers,
        inCombat = inCombat,
    }
    local walker = GetIconRefreshWalker()
    if walker then
        walker:RefreshAll(context)
    else
        for _, pool in pairs(iconPools) do
            for _, icon in ipairs(pool) do
                RefreshAllIcon(icon, context)
            end
        end
    end

    -- After the per-icon visibility loop, relayout any container whose
    -- filter verdict flipped since the last layout pass.
    SetRefreshBatchStackTextWrites(false)
    SyncSpellRangeChecks()
    EndIconRefreshBatch()
    DrainLayoutDirty()
end

function CDMIcons:UpdateCooldownOnly()
    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    local allowStackTextWrites = ConsumeStackTextWriteRequest()
    SetRefreshBatchStackTextWrites(allowStackTextWrites)
    BeginIconRefreshBatch("cooldownOnly")

    local context = {
        editMode = editMode,
        ncdm = ncdm,
        ncdmContainers = ncdmContainers,
        inCombat = inCombat,
    }
    local walker = GetIconRefreshWalker()
    if walker then
        walker:RefreshCooldownOnly(context)
    else
        for _, pool in pairs(iconPools) do
            for _, icon in ipairs(pool) do
                local entry = icon._spellEntry
                if entry then
                    local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" then
                        UpdateCooldownOnlyIcon(icon, entry)
                        UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
                    end
                end
            end
        end
    end

    -- After the per-icon visibility loop, relayout any container whose
    -- filter verdict flipped since the last layout pass.
    SetRefreshBatchStackTextWrites(false)
    EndIconRefreshBatch()
    DrainLayoutDirty()
end

function CDMIcons:UpdateCooldownsForType(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        PrepareCooldownUpdateBatch()
        SetRefreshBatchStackTextWrites(true)
        BeginIconRefreshBatch("type")
        local walker = GetIconRefreshWalker()
        if walker then
            walker:RefreshType(viewerType)
        else
            for _, icon in ipairs(pool) do
                UpdateIconCooldown(icon)
            end
        end
        SetRefreshBatchStackTextWrites(false)
        SyncSpellRangeChecks()
        EndIconRefreshBatch()
    end
end

function CDMIcons:UpdateRuntimeForType(viewerType)
    local pool = iconPools[viewerType]
    if not pool then return end

    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    SetRefreshBatchStackTextWrites(true)
    BeginIconRefreshBatch("typeRuntime")

    local context = {
        editMode = editMode,
        ncdm = ncdm,
        ncdmContainers = ncdmContainers,
        inCombat = inCombat,
    }
    local walker = GetIconRefreshWalker()
    if walker and walker.RefreshRuntimeType then
        walker:RefreshRuntimeType(viewerType, context)
    else
        for _, icon in ipairs(pool) do
            local entry = icon._spellEntry
            if entry then
                local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
                if cType ~= "aura" and cType ~= "auraBar" then
                    UpdateCooldownOnlyIcon(icon, entry)
                    UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
                end
            end
        end
    end

    SetRefreshBatchStackTextWrites(false)
    SyncSpellRangeChecks()
    EndIconRefreshBatch()
    DrainLayoutDirty()
end

function CDMIcons.OnContainerIconPlaced(icon, rowConfig)
    if not icon then return end
    ConfigureIcon(icon, rowConfig)
    BeginIconRefreshBatch("placed")
    UpdateIconCooldown(icon)
    EndIconRefreshBatch()
end

function CDMIcons.OnIconRowConfigApplied(icon, rowConfig)
    ConfigureIcon(icon, rowConfig)
end

function CDMIcons.OnFactoryIconCreated(icon, entry)
    if not icon then return end
    UpdateIconProfessionQuality(icon)
end

function CDMIcons.OnFactoryIconAcquired(icon, entry, reused)
    if not icon then return end
    if reused then
        CancelCooldownExpiryRefresh(icon)
        _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
        UpdateIconProfessionQuality(icon)
    end
    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(entry and entry.name, "ACQUIRE",
            reused and "reused" or "new",
            "viewerType=", entry and entry.viewerType)
    end
    if entry and entry.viewerType ~= "buff" then
        UpdateIconSecureAttributes(icon, entry, entry.viewerType)
    end
    if CDMIcons.EventTraceMaybeProbeIcon then
        CDMIcons.EventTraceMaybeProbeIcon(icon)
    end
end

function CDMIcons.OnFactoryIconReleased(icon)
    if not icon then return end
    local entry = icon._spellEntry
    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(entry and entry.name, "RELEASE",
            "viewerType=", entry and entry.viewerType,
            "shown=", icon.IsShown and icon:IsShown())
    end
    CancelCooldownExpiryRefresh(icon)
    if ns.CDMRuntimeStore and ns.CDMRuntimeStore.ClearFrame then
        ns.CDMRuntimeStore.ClearFrame(icon)
    end
    UnmirrorBlizzCooldown(icon)
    if ns._OwnedGlows and ns._OwnedGlows.ClearPandemicState then
        ns._OwnedGlows.ClearPandemicState(icon)
    end
    -- Keybind and rotation-helper overlays are parented to pooled icons.
    -- Clear them before the factory recycles the frame into another viewer.
    if _G.QUI_ClearKeybindIconState then
        _G.QUI_ClearKeybindIconState(icon)
    end
    _resolverRuntimePolicy.StopCustomBarActiveGlow(icon)
    ClearIconProfessionQuality(icon)
    if icon.clickButton and not InCombatLockdown() then
        ClearClickButtonAttributes(icon.clickButton)
        icon.clickButton:Hide()
    end
end

function CDMIcons.OnContainerIconInteractionRestored(icon, viewerType)
    if not icon then return end
    UpdateIconSecureAttributes(icon, icon._spellEntry, viewerType)
end

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
        local itemID = Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID("player", entry.id)
        if itemID then
            local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(itemID)
            return itemName or "Trinket (Slot " .. tostring(entry.id) .. ")"
        end
        return "Trinket (Slot " .. tostring(entry.id) .. ")"
    end
    if entry.type == "item" then
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(entry.id)
        return itemName or "Item #" .. tostring(entry.id)
    end
    local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(entry.id)
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

function CustomCDM:UpdateAllCooldowns() CDMIcons:UpdateAllCooldowns() end

---------------------------------------------------------------------------
-- RANGE INDICATOR
-- Tints CDM icon textures red when the spell/item is out of range,
-- matching action-bar behavior. Uses C_Spell.IsSpellInRange for spells.
-- Event-driven only; no periodic range/usability OnUpdate is installed.
---------------------------------------------------------------------------
local rangePolicy = ns.CDMIconRangePolicy and ns.CDMIconRangePolicy.Create({
    getDB = GetDB,
    resolveSettings = function(viewerType, cachedDB)
        return (cachedDB and (cachedDB[viewerType] or (cachedDB.containers and cachedDB.containers[viewerType])))
            or GetTrackerSettings(viewerType)
    end,
    querySpellInRange = function(...)
        return Sources and Sources.QuerySpellInRange and Sources.QuerySpellInRange(...)
    end,
    querySpellUsable = function(...)
        return Sources and Sources.QuerySpellUsable and Sources.QuerySpellUsable(...)
    end,
    querySpellHasRange = function(...)
        return Sources and Sources.QuerySpellHasRange and Sources.QuerySpellHasRange(...)
    end,
    enableSpellRangeCheck = function(...)
        return Sources and Sources.EnableSpellRangeCheck and Sources.EnableSpellRangeCheck(...)
    end,
    cooldownHasVisualPriority = function(icon, entry, settings)
        return _resolverRuntimePolicy.CooldownHasVisualPriority(icon, entry, settings, GetTime())
    end,
    resolveCooldownActivityState = function(icon, entry, settings)
        return _resolverRuntimePolicy.ResolveIconCooldownActivityState(icon, entry, settings, GetTime())
    end,
    isAuraEntry = function(entry)
        return IsAuraEntry and IsAuraEntry(entry)
    end,
})

SetStackTextWritesForBatch = function(enabled)
    if rangePolicy then
        rangePolicy:SetStackTextWritesForBatch(enabled)
    end
end

function CDMIcons.ShouldAllowStackTextWrites()
    return rangePolicy and rangePolicy:ShouldAllowStackTextWrites() or false
end

function _resolverRuntimePolicy.IconNeedsUsabilityVisualRefresh(icon, cachedDB)
    return rangePolicy and rangePolicy:IconNeedsUsabilityVisualRefresh(icon, cachedDB) or false
end

function _resolverRuntimePolicy.UpdateIconRangesForUsabilityEvent()
    if rangePolicy then
        rangePolicy:UpdateIconRangesForUsabilityEvent(iconPools)
    end
end

function CDMIcons:UpdateAllIconRanges()
    if rangePolicy then
        rangePolicy:UpdateAllIconRanges(iconPools)
    end
end

SyncSpellRangeChecks = function()
    if rangePolicy then
        rangePolicy:SyncSpellRangeChecks(iconPools)
    end
end

DisableSpellRangeChecks = function()
    if rangePolicy then
        rangePolicy:DisableSpellRangeChecks()
    end
end

local function UpdateIconsForSpellRangeEvent(spellIdentifier, isInRange, checksRange)
    if rangePolicy then
        rangePolicy:UpdateIconsForSpellRangeEvent(iconPools, spellIdentifier, isInRange, checksRange)
    end
end

local function GetItemIDForEntry(entry)
    if not entry then return nil end
    local entryType = entry.type
    if entryType == "item" then
        return (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
    end
    if (entryType == "trinket" or entryType == "slot")
        and Sources and Sources.QueryInventoryItemID then
        return Sources.QueryInventoryItemID("player", entry.id)
    end
    return nil
end

---------------------------------------------------------------------------
-- EVENT HANDLING: Update cooldowns on relevant events
---------------------------------------------------------------------------
local cdEventFrame = CreateFrame("Frame")
cdEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
cdEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
cdEventFrame:RegisterEvent("ITEM_COUNT_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
cdEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
cdEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cdEventFrame:RegisterEvent("UPDATE_MACROS")
cdEventFrame:RegisterEvent("SPELLS_CHANGED")
cdEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
cdEventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
cdEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
cdEventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
-- Server-side cooldown table hotfix. User /cdm composer edits flow through
-- the resolver bus CATALOG_REBUILT path, not this event.
cdEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
-- SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_CHARGES / SPELL_UPDATE_USES,
-- UNIT_SPELLCAST_START, and
-- UNIT_SPELLCAST_SUCCEEDED are owned by cdm_resolvers.lua, which publishes
-- CDM:COOLDOWN_CHANGED / CDM:CHARGES_CHANGED. UNIT_AURA is owned by
-- cdm_spelldata.lua so the full batched aura payload is processed before
-- icons/bars refresh.

local CDM_UPDATE_COOLDOWN = "cooldown"
local CDM_UPDATE_FULL = "full"
local updateScheduler

-- Frame-based coalescing for cooldown/aura events lives in the private icon
-- update scheduler. CDMIcons keeps only a narrow scheduling adapter here.
local function CreateIconUpdateScheduler()
    local module = ns.CDMIconUpdateScheduler
    if not (module and module.Create) then return nil end
    return module.Create({
        isRuntimeEnabled = function()
            return CDMIcons:IsRuntimeEnabled()
        end,
        getTime = function()
            return GetTime()
        end,
        isInCombat = function()
            return InCombatLockdown()
        end,
        isInRaid = function()
            return IsInRaid and IsInRaid()
        end,
        getScheduler = function()
            return ns.CDMScheduler
        end,
        updateAllCooldowns = function()
            CDMIcons:UpdateAllCooldowns()
        end,
        updateCooldownOnly = function()
            CDMIcons:UpdateCooldownOnly()
        end,
        getBars = function()
            return ns.CDMBars
        end,
    })
end

updateScheduler = CreateIconUpdateScheduler()

local function NoteFullUpdateSchedule(reason)
    fullUpdateScheduleStats.total = fullUpdateScheduleStats.total + 1
    if reason == "request" then
        fullUpdateScheduleStats.request = fullUpdateScheduleStats.request + 1
    elseif reason == "mirrorFallback" then
        fullUpdateScheduleStats.mirrorFallback = fullUpdateScheduleStats.mirrorFallback + 1
    elseif reason == "runtime" then
        fullUpdateScheduleStats.runtime = fullUpdateScheduleStats.runtime + 1
    elseif reason == "deferred" then
        fullUpdateScheduleStats.deferred = fullUpdateScheduleStats.deferred + 1
    elseif reason == "hotfix" then
        fullUpdateScheduleStats.hotfix = fullUpdateScheduleStats.hotfix + 1
    else
        fullUpdateScheduleStats.other = fullUpdateScheduleStats.other + 1
    end
end

local function ScheduleCDMUpdate(fast, mode, reason)
    if mode == CDM_UPDATE_FULL then
        NoteFullUpdateSchedule(reason)
    end
    if updateScheduler then
        updateScheduler:Schedule(fast, mode)
    end
end

local function GetCDMUpdateDelay(fast, mode)
    if updateScheduler then
        return updateScheduler:GetDelay(fast, mode)
    end
    if fast then
        return 0
    end
    return 0.05
end

local function RunDirtyBarUpdate()
    if updateScheduler then
        updateScheduler:RunDirtyBarUpdate()
    end
end

function _resolverRuntimePolicy.RefreshIndexedMirrorIcon(icon, editMode, ncdm, ncdmContainers, inCombat)
    local entry = icon and icon._spellEntry
    if not entry then return false end

    local wasAuraActive = icon._auraActive == true
    UpdateIconCooldown(icon)
    if entry.viewerType == "buff"
        and wasAuraActive ~= (icon._auraActive == true) then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end

    local containerDB = ncdm and (ncdm[entry.viewerType]
        or (ncdmContainers and ncdmContainers[entry.viewerType]))
    UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    return true
end

-- Scoping rule for event-driven broad resolves: every event that triggers
-- a broad re-resolve walks ONLY the icons whose state can be affected by
-- what that event reports on. Sweeping every icon on every event propagates
-- transient API inconsistencies (e.g., C_Spell.GetSpellCooldown briefly
-- returning isActive=false isOnGCD=nil mid-GCD, surfaced via /cdmdebug spell events)
-- into icons that should not be touched, producing visible cooldown-swipe
-- flicker on unrelated cooldown-only spells. Three scoped variants cover
-- the three event families:
--   * Aura  — UNIT_AURA pipeline
--   * Item  — BAG_UPDATE_COOLDOWN, BAG_UPDATE_DELAYED, ITEM_COUNT_CHANGED,
--             PLAYER_EQUIPMENT_CHANGED (trinket slots)
--   * Spell — CDM:COOLDOWN_CHANGED broad fallback, UNIT_SPELLCAST_SUCCEEDED,
--             CDM:CHARGES_CHANGED
--
-- The three scopes are mutually exclusive per entry: an entry is aura, item,
-- or spell. There is no unscoped "walk all" helper — that anti-pattern was
-- removed so all future event handlers have to declare what they affect.
--
-- Pipeline follow-up: ideally these helpers wouldn't iterate icons at all —
-- events would refresh the relevant pipeline state (mirror cache, bag CD
-- cache, etc.) once and icons would re-resolve via subscription. Today the
-- only state→icon notification is a direct walk, so we scope the walk by
-- entry shape instead.

-- Aura-delta scope: UNIT_AURA pipeline. An aura delta is structurally
-- relevant ONLY to aura-kind entries or cooldown-kind entries that are
-- currently in an aura-active state. Cooldown-only icons (Death Coil, any
-- spell with no aura tracking) are owned by SPELL_UPDATE_COOLDOWN /
-- SPELL_UPDATE_USABLE / cast events.
function _resolverRuntimePolicy.ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
    if not (icon and entry) then return false end

    if icon._blizzMirrorCooldownID and IsAuraEntry(entry) then
        return _resolverRuntimePolicy.RefreshIndexedMirrorIcon(
            icon, editMode, ncdm, ncdmContainers, inCombat)
    end

    local wasAuraActive = icon._auraActive == true
    ApplyResolvedCooldown(icon)

    local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
    if IsAuraEntry(entry) or cType == "aura" or cType == "auraBar" then
        UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    end

    if entry.viewerType == "buff"
       and wasAuraActive ~= (icon._auraActive == true)
       and _resolverRuntimePolicy.RequestBuffIconLayoutRefresh then
        _resolverRuntimePolicy.RequestBuffIconLayoutRefresh()
    end

    return true
end

-- EventTrace* helpers are provided by the load-on-demand debug addon. Runtime
-- event classification, scoped walks, and combat queues live in
-- CDMIconRuntimeRefresh; CDMIcons supplies renderer mutations as callbacks.

cdEventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    local profileStart = debugprofilestop and debugprofilestop()
    -- arg4 is forwarded for the event trace only — SPELL_UPDATE_COOLDOWN
    -- carries (spellID, baseSpellID, category, startRecoveryCategory) per
    -- SpellBookDocumentation.lua:859. The runtime refresh path stays on
    -- the 3-arg shape; only the debug trace needs startRecoveryCategory
    -- (133 = GCD) to filter out GCD-only fires.
    CDMIcons.EventTracePrint("frame-pre", event, arg1, arg2, arg3, arg4)
    _resolverRuntimePolicy.HandleRuntimeRefresh(event, arg1, arg2, arg3, self)
    CDMIcons.EventTracePrint("frame-post", event, arg1, arg2, arg3, arg4)
    if profileStart and debugprofilestop then
        CDMIcons.RecordEventProfile(event, debugprofilestop() - profileStart)
    else
        CDMIcons.RecordEventProfile(event, 0)
    end
end)

-- /cdm spell add/remove now flows through the composer-driven CATALOG_REBUILT
-- bus event subscribed below; QUI no longer listens for Blizzard's standalone
-- CooldownManager settings callback because that path is unrelated to the
-- composer's owned catalog.

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Icons", frame = cdEventFrame }

-- Exporters for /qui cdm_cache reset / status.
function CDMIcons:ClearTextureCycleCache()
    wipe(_textureCycleCache)
end

function CDMIcons:RequestFullUpdate()
    if not CDMIcons:IsRuntimeEnabled() then return end
    if updateScheduler then
        updateScheduler:SetBarsDirty(true)
    end
    ScheduleCDMUpdate(true, CDM_UPDATE_FULL, "request")
end

do
    local mirrorController = ns.CDMIconMirrorIndex and ns.CDMIconMirrorIndex.Create({
        isRuntimeEnabled = function()
            return CDMIcons:IsRuntimeEnabled()
        end,
        getCombatDelay = function()
            return GetCDMUpdateDelay(nil, CDM_UPDATE_COOLDOWN)
        end,
        requestFullRefresh = function()
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL, "mirrorFallback")
        end,
        getMirrorStateByCooldownID = function(cooldownID, category)
            local mirror = ns.CDMBlizzMirror
            return mirror and mirror.GetStateByCooldownID
                and mirror.GetStateByCooldownID(cooldownID, category)
                or nil
        end,
        storeMirrorStateForIcon = StoreCachedMirrorStateForIcon,
        prepareBatch = PrepareCooldownUpdateBatch,
        setStackTextWrites = SetRefreshBatchStackTextWrites,
        beginBatch = function()
            BeginIconRefreshBatch("mirror")
        end,
        endBatch = EndIconRefreshBatch,
        drainLayoutDirty = DrainLayoutDirty,
        refreshIcon = function(icon, editMode, ncdm, ncdmContainers, inCombat)
            return _resolverRuntimePolicy.RefreshIndexedMirrorIcon(
                icon, editMode, ncdm, ncdmContainers, inCombat)
        end,
        onBound = function(icon)
            if icon._rowConfig then
                ConfigureIcon(icon, icon._rowConfig)
            end

            local entry = icon._spellEntry
            if not entry or IsAuraEntry(entry) or not _resolverRuntimePolicy.ResolveIconStackText then return end
            local stackText, stackSource, mirrorBacked = _resolverRuntimePolicy.ResolveIconStackText(icon)
            if not mirrorBacked then return end
            if _resolverRuntimePolicy.ValueIsPresent(stackText) then
                local settings = GetTrackerSettings
                    and GetTrackerSettings(entry.viewerType)
                    or nil
                _resolverRuntimePolicy.ShowIconStackText(
                    icon, stackText, settings, stackSource or "mirror-bind-stack")
                icon._lastMirrorStackTextEpoch = icon.stackTextEpoch
            else
                ClearIconStackText(icon, "mirror-bind-empty")
            end
        end,
    })

    function CDMIcons.RebuildBlizzMirrorIconIndex()
        if mirrorController then
            mirrorController:Rebuild(iconPools)
        end
    end

    function CDMIcons.OnFactoryMirrorBound(icon, cooldownID, category)
        if mirrorController then
            mirrorController:BindIcon(icon, cooldownID, category)
        end
    end

    function CDMIcons.OnFactoryMirrorUnbound(icon)
        if mirrorController then
            mirrorController:UnbindIcon(icon)
        end
    end

    function CDMIcons:RequestMirrorTextRefresh(cooldownID, category)
        if mirrorController then
            mirrorController:RequestRefresh(cooldownID, category)
        end
    end

    function CDMIcons:GetCacheStats()
        local n = 0
        for _ in pairs(_textureCycleCache) do n = n + 1 end
        local activePools = 0
        local activeIcons = 0
        for _, pool in pairs(iconPools) do
            activePools = activePools + 1
            activeIcons = activeIcons + #pool
        end
        local mirrorIndexKeys, mirrorIndexIcons = 0, 0
        local mirrorRefreshStats = { targeted = 0, fallback = 0, maxBatch = 0 }
        local mirrorRefreshPending = false
        local mirrorRefreshPendingKeys = 0
        if mirrorController then
            mirrorIndexKeys, mirrorIndexIcons = mirrorController:Count()
            mirrorRefreshStats = mirrorController:GetStats()
            mirrorRefreshPending = mirrorController:IsRefreshPending()
            mirrorRefreshPendingKeys = mirrorController:PendingKeyCount()
        end
        local updateStats = updateScheduler and updateScheduler:GetStats() or {}
        local iconEventProfileTop, iconEventProfileWindow = CDMIcons.SnapshotEventProfile(5)
        return {
            textureCycleCache = n,
            activeIconPools    = activePools,
            activeIcons        = activeIcons,
            recycleIcons       = #recyclePool,
            barsDirty         = updateStats.barsDirty == true,
            updatePending     = updateStats.updatePending == true,
            mirrorIndexKeys    = mirrorIndexKeys,
            mirrorIndexIcons   = mirrorIndexIcons,
            mirrorRefreshPending = mirrorRefreshPending,
            mirrorRefreshPendingKeys = mirrorRefreshPendingKeys,
            mirrorRefreshTargeted = mirrorRefreshStats.targeted,
            mirrorRefreshFallback = mirrorRefreshStats.fallback,
            mirrorRefreshMaxBatch = mirrorRefreshStats.maxBatch,
            iconEventProfileTop = iconEventProfileTop,
            iconEventProfileWindow = iconEventProfileWindow,
        }
    end
end

-- Bus subscribers — replace direct Blizzard events.
-- The resolver owns runtime event registration and publishes CDM:* events
-- when state changes. We subscribe and call the same render functions the
-- old direct path called.
--
-- Aura events set the scheduler's bar-dirty flag only when a matching icon/bar may have changed.
-- Pure cooldown events deliberately do NOT set the flag — bar fill is driven
-- by barTimerGroup independently of ScheduleCDMUpdate.
local runtimeRefresh
do
    runtimeRefresh = ns.CDMIconRuntimeRefresh and ns.CDMIconRuntimeRefresh.Create({
        isRuntimeEnabled = function()
            return CDMIcons:IsRuntimeEnabled()
        end,
        getIconPools = function()
            return iconPools
        end,
        isSecretValue = function(value)
            return issecretvalue and issecretvalue(value) or false
        end,
        eventTracePrint = function(...)
            return CDMIcons.EventTracePrint(...)
        end,
        eventTraceAuraInfo = function(unit, updateInfo)
            return CDMIcons.EventTraceAuraInfo(unit, updateInfo)
        end,
        setBarsDirty = function(dirty)
            if updateScheduler then
                updateScheduler:SetBarsDirty(dirty == true)
            end
        end,
        scheduleFullUpdate = function()
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL, "runtime")
        end,
        scheduleUpdate = function(fast, mode, reason)
            ScheduleCDMUpdate(fast, mode, reason or "runtime")
        end,
        prepareBatch = PrepareCooldownUpdateBatch,
        beginBatch = function(reason)
            BeginIconRefreshBatch(reason)
        end,
        endBatch = EndIconRefreshBatch,
        setStackTextWrites = SetRefreshBatchStackTextWrites,
        applyResolvedCooldown = ApplyResolvedCooldown,
        updateIconCooldown = UpdateIconCooldown,
        applyAuraScopedResolvedCooldown = function(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
            return _resolverRuntimePolicy.ApplyAuraScopedResolvedCooldown(
                icon, entry, editMode, ncdm, ncdmContainers, inCombat)
        end,
        resolveContainerDBAndType = ResolveContainerDBAndType,
        updateContainerVisibility = UpdateCooldownContainerVisibility,
        syncCooldownBling = SyncCooldownBling,
        drainLayoutDirty = DrainLayoutDirty,
        isAuraEntry = function(entry)
            return IsAuraEntry and IsAuraEntry(entry)
        end,
        getMirrorStateByCooldownID = function(cooldownID, category)
            local mirror = ns.CDMBlizzMirror
            return mirror and mirror.GetStateByCooldownID
                and mirror.GetStateByCooldownID(cooldownID, category)
        end,
        markBarsForAuraRefresh = function(unit, updateInfo)
            local bars = ns.CDMBars
            return bars and bars.MarkAuraRefresh
                and bars:MarkAuraRefresh(unit, updateInfo)
                or false
        end,
        getItemIDForEntry = GetItemIDForEntry,
        queryItemSpell = function(itemID)
            if Sources and Sources.QueryItemSpell then
                return Sources.QueryItemSpell(itemID)
            end
        end,
        queryCooldownAuraBySpellID = function(spellID)
            if Sources and Sources.QueryCooldownAuraBySpellID then
                return Sources.QueryCooldownAuraBySpellID(spellID)
            end
        end,
        clearDurationBinding = function(icon)
            icon._lastDurObjKey = nil
            icon._lastDurObj = nil
            icon._lastResolvedMode = nil
            icon._lastResolvedSourceID = nil
            icon._lastResolvedSpellID = nil
        end,
        updateIconRangesForUsabilityEvent = function()
            _resolverRuntimePolicy.UpdateIconRangesForUsabilityEvent()
        end,
        requestStackTextUpdate = function()
            RequestStackTextUpdate()
        end,
        noteChargeDurationObjectsUpdated = function()
            if RuntimeQueries and RuntimeQueries.NoteChargeDurationObjectsUpdated then
                RuntimeQueries.NoteChargeDurationObjectsUpdated()
            end
        end,
        recordRecentPlayerSpellCast = function(spellID)
            if RecordRecentPlayerSpellCast then
                RecordRecentPlayerSpellCast(spellID)
            end
        end,
        getHighlighter = function()
            return ns._OwnedHighlighter
        end,
        runDirtyBarUpdate = RunDirtyBarUpdate,
        onRuntimeDisabled = function(frame)
            frame = frame or cdEventFrame
            if frame and frame.SetScript then
                frame:SetScript("OnUpdate", nil)
            end
            if updateScheduler then
                updateScheduler:Cancel()
            end
            DisableSpellRangeChecks()
        end,
        updateAllIconRanges = function()
            CDMIcons:UpdateAllIconRanges()
        end,
        chargeDebug = function(...)
            if _G.QUI_CDM_CHARGE_DEBUG then
                ChargeDebug(...)
            end
        end,
        invalidateMacroCache = InvalidateMacroCache,
        updateIconsForSpellRangeEvent = UpdateIconsForSpellRangeEvent,
        clearTextureCycleCache = function()
            wipe(_textureCycleCache)
        end,
        clearDurationBindingKeyCache = function()
            _resolverRuntimePolicy.ClearDurationBindingKeyCache()
        end,
        clearStableCaches = function()
            if RuntimeQueries and RuntimeQueries.ClearStableCaches then
                RuntimeQueries.ClearStableCaches()
            end
        end,
        isPlayerInCombat = function()
            return InCombatLockdown and InCombatLockdown() or false
        end,
        getCombatQueueDelay = function()
            return updateScheduler and updateScheduler:GetCombatQueueDelay() or 0.3
        end,
    })

    function _resolverRuntimePolicy.HandleRuntimeRefresh(event, arg1, arg2, arg3, frame)
        if runtimeRefresh then
            return runtimeRefresh:Handle(event, arg1, arg2, arg3, frame)
        end
    end
end

function CDMIcons.HandleRuntimeRefresh(event, arg1, arg2, arg3)
    return _resolverRuntimePolicy.HandleRuntimeRefresh(event, arg1, arg2, arg3)
end

local function OnCDMCooldownChanged(_, spellID, baseSpellID, kind)
    if runtimeRefresh then
        return runtimeRefresh:HandleCooldownChanged(_, spellID, baseSpellID, kind)
    end
end

local function OnCDMChargesChanged(_, spellID)
    if runtimeRefresh then
        return runtimeRefresh:HandleChargesChanged(_, spellID)
    end
end

ns.CDMResolvers.Subscribe("CDM:COOLDOWN_CHANGED", OnCDMCooldownChanged)
ns.CDMResolvers.Subscribe("CDM:CHARGES_CHANGED", OnCDMChargesChanged)

-- The event frame never owns a periodic visual poller.
cdEventFrame:SetScript("OnUpdate", nil)

function CDMIcons:DisableRuntime()
    cdEventFrame:UnregisterAllEvents()
    cdEventFrame:SetScript("OnEvent", nil)
    cdEventFrame:SetScript("OnUpdate", nil)
    if updateScheduler then
        updateScheduler:Cancel()
        updateScheduler:SetBarsDirty(false)
    end
    DisableSpellRangeChecks()
end

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING
-- ChargeDebug is a placeholder until the load-on-demand debug addon rebinds it
-- via BindAll(). Hot-path callers keep their existing `ChargeDebug(...)`
-- upvalue calls.
---------------------------------------------------------------------------
function CDMIcons._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        ChargeDebug           = d.Charge or ChargeDebug
        CDMIcons._ShouldDebugBlizzEntry = d.ShouldBlizz or CDMIcons._ShouldDebugBlizzEntry
        CDMIcons._FormatMirrorState     = d.FormatMirrorState or CDMIcons._FormatMirrorState
        CDMIcons._DebugBlizzEntry       = d.Blizz or CDMIcons._DebugBlizzEntry
    end
end
