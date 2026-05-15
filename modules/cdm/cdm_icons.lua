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
local Shared = ns.CDMShared

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMIcons = {}
ns.CDMIcons = CDMIcons
CDMIcons.ChargeDebug = function() end
CDMIcons.DebugStackText = function() end
CDMIcons.DebugSpellEvent = function() end
CDMIcons.DebugIconEvent = function() end
CDMIcons.DebugEntryBuild = function() end
CDMIcons.DebugLayoutFilter = function() end
CDMIcons.EventTracePrint = function() end
CDMIcons.EventTraceAuraInfo = function() return nil end

---------------------------------------------------------------------------
-- IMPORTS
---------------------------------------------------------------------------
local Resolvers = ns.CDMResolvers
local Sources = ns.CDMSources
local QueryCharges = Resolvers.QueryCharges
local QueryCooldown = Resolvers.QueryCooldown
local QueryDuration = Resolvers.QueryDuration
local QueryChargeDuration = Resolvers.QueryChargeDuration
local QueryOverrideSpell = Resolvers.QueryOverrideSpell
local QueryDisplayCount = Resolvers.QueryDisplayCount
local QuerySpellCount = Resolvers.QuerySpellCount
local _textureCycleCache = Resolvers._textureCycleCache
local GetSpellTexture = Resolvers.GetSpellTexture
local ResolveMacro = Resolvers.ResolveMacro
local GetEntryTexture = Resolvers.GetEntryTexture
local HasRealCooldownState = Resolvers.HasRealCooldownState
local ResolveAuraStateForIcon = Resolvers.ResolveAuraStateForIcon
local ResolveAuraDurationObjectForIcon = Resolvers.ResolveAuraDurationObjectForIcon
local IsAuraEntry = Resolvers.IsAuraEntry
local GetChargeMetadataDB = Resolvers.GetChargeMetadataDB
local BeginRuntimeQueryBatch = Resolvers.BeginRuntimeQueryBatch
local EndRuntimeQueryBatch = Resolvers.EndRuntimeQueryBatch

local function BeginResolverQueryBatch()
    if BeginRuntimeQueryBatch then
        BeginRuntimeQueryBatch()
    end
end

local function EndResolverQueryBatch()
    if EndRuntimeQueryBatch then
        EndRuntimeQueryBatch()
    end
end

---------------------------------------------------------------------------
-- COMPAT SHIMS
-- Resolver functions forwarded onto CDMIcons so callers in containers,
-- bars, and cdm_resolvers.lua itself can reach them via CDMIcons.X.
-- cdm_resolvers.lua loads before this file (cdm.xml ordering).
---------------------------------------------------------------------------
CDMIcons.IsItemLikeEntry = ns.CDMResolvers.IsItemLikeEntry
CDMIcons.ResolveItemCooldownIdentity = ns.CDMResolvers.ResolveItemCooldownIdentity
CDMIcons.ResolveEntryItemID = ns.CDMResolvers.ResolveEntryItemID
CDMIcons.ClassifySpellCooldownState = ns.CDMResolvers.ClassifySpellCooldownState
CDMIcons.ResolveSpellActiveState = ns.CDMResolvers.ResolveSpellActiveState
CDMIcons.ResolveCooldownActivityState = ns.CDMResolvers.ResolveCooldownActivityState
CDMIcons.ResolveIconDurationObject = ns.CDMResolvers.ResolveIconDurationObject

-- Factory delegation: callers in cdm_containers.lua + self use
-- CDMIcons:AcquireIcon / CDMIcons:ReleaseIcon; the real impl is in
-- cdm_icon_factory.lua (loads before this file via cdm.xml ordering).
function CDMIcons:AcquireIcon(...)
    return ns.CDMIconFactory.AcquireIcon(ns.CDMIconFactory, ...)
end

function CDMIcons:ReleaseIcon(...)
    return ns.CDMIconFactory.ReleaseIcon(ns.CDMIconFactory, ...)
end

CDMIcons._LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
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
local format = format
local InCombatLockdown = InCombatLockdown
local C_StringUtil = C_StringUtil
local issecretvalue = issecretvalue

local function IsSafeNumeric(val)
    return Shared and Shared.IsSafeNumeric(val) or type(val) == "number"
end
CDMIcons.IsSafeNumeric = IsSafeNumeric

local function SafeBoolean(val)
    if Shared and Shared.SafeBoolean then
        return Shared.SafeBoolean(val)
    end
    if type(val) == "boolean" then
        return val
    end
    return nil
end

function CDMIcons.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
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
local GCD_SPELL_ID = 61304
local GCD_MAX_DURATION = 1.75
CDMIcons.COOLDOWN_EXPIRY_REFRESH_FUDGE = 0.2
CDMIcons.COOLDOWN_EXPIRY_RESCHEDULE_EPSILON = 0.1

function CDMIcons.GetCooldownInfoField(info, key)
    -- Returns (value, isSecret). Combat-restricted fields (startTime,
    -- duration, timeUntilEndOfStartRecovery, activeCategory) may be secret
    -- when the Blizzard CDM data feed is active. Callers should forward
    -- the raw value to C-side sinks (SetCooldownFromDurationObject etc.)
    -- and gate any Lua-side compare/branch on the secret flag —
    -- `value > 0` faults on a secret number even when `type(value)` is
    -- "number", because secret numbers are typed but unsafe to compare.
    if not info then return nil, false end
    local v = info[key]
    if v == nil then return nil, false end
    if issecretvalue and issecretvalue(v) then
        return v, true
    end
    return v, false
end

function CDMIcons.GetCooldownInfoStartDuration(info)
    local start, startSecret = CDMIcons.GetCooldownInfoField(info, "startTime")
    if start == nil and not startSecret then
        start, startSecret = CDMIcons.GetCooldownInfoField(info, "start")
    end
    local duration, durationSecret = CDMIcons.GetCooldownInfoField(info, "duration")
    return start, duration, startSecret or durationSecret
end

function CDMIcons.IsCooldownInfoActive(info)
    -- cdInfo.isActive is a non-secret boolean per API contract. Trust it
    -- exclusively. The legacy start/duration fallback was removed because
    -- those fields can be secret in combat and comparing them in Lua
    -- (start > 0) taints. If isActive isn't a boolean, the cooldown's
    -- state is unknown — return nil so callers fall back to event-driven
    -- refresh.
    local active = CDMIcons.GetCooldownInfoField(info, "isActive")
    if type(active) == "boolean" then
        return active
    end
    return nil
end

function CDMIcons.IsCooldownInfoRealCooldown(info)
    if not info then return false end

    local active = CDMIcons.IsCooldownInfoActive(info)
    if active == false then
        return false
    end

    local enabled = CDMIcons.GetCooldownInfoField(info, "isEnabled")
    if enabled == false then
        return false
    end

    local start, duration, timingSecret = CDMIcons.GetCooldownInfoStartDuration(info)
    if not timingSecret and IsSafeNumeric(duration) then
        if duration <= GCD_MAX_DURATION then
            return false
        end
        if IsSafeNumeric(start) and start <= 0 then
            return false
        end
        if active == true then
            return true
        end
    end

    local activeCategory, categorySecret = CDMIcons.GetCooldownInfoField(info, "activeCategory")
    -- Check secret before the `~= nil` test so a secret category (which
    -- can compare against nil safely but not deduce an "unknown" branch)
    -- doesn't get treated as a real cooldown by accident.
    if categorySecret then
        return nil
    end
    if activeCategory ~= nil then
        return true
    end

    local startRecovery, recoverySecret = CDMIcons.GetCooldownInfoField(info, "timeUntilEndOfStartRecovery")
    if not recoverySecret and IsSafeNumeric(startRecovery) and startRecovery > 0 then
        return false
    elseif startRecovery ~= nil and not timingSecret and not recoverySecret then
        return false
    end
    if recoverySecret or timingSecret then
        return nil
    end

    -- No active cooldown category, no readable >GCD duration, and no secret
    -- timing means the duration came from GCD, resource recovery, spell hold,
    -- or other non-cooldown logic.
    return false
end

---------------------------------------------------------------------------
-- POOL STATE ALIASES
-- iconPools and recyclePool live in cdm_icon_factory.lua; aliased here as
-- upvalues so direct references in this file resolve without a mass rewrite.
---------------------------------------------------------------------------
local iconPools   = ns.CDMIconFactory._iconPools
local recyclePool = ns.CDMIconFactory._recyclePool
local Factory = ns.CDMIconFactory
local SyncCooldownBling  = Factory.SyncCooldownBling
local UpdateIconCooldown = Factory.UpdateIconCooldown
local SetStackTextWritesForBatch
local SyncSpellRangeChecks
local DisableSpellRangeChecks

CDMIcons._mirrorIconsByCategory = {}
CDMIcons._pendingMirrorRefreshByCategory = {}
CDMIcons._mirrorRefreshPending = false
CDMIcons._mirrorRefreshStats = {
    targeted = 0,
    fallback = 0,
    maxBatch = 0,
}
CDMIcons._eventProfileStats = {}
CDMIcons._eventProfileLast = {
    time = GetTime and GetTime() or 0,
    counts = {},
    ms = {},
}

function CDMIcons.RecordEventProfile(event, elapsedMS)
    if not event then return end
    local stats = CDMIcons._eventProfileStats[event]
    if not stats then
        stats = { calls = 0, ms = 0 }
        CDMIcons._eventProfileStats[event] = stats
    end
    stats.calls = stats.calls + 1
    stats.ms = stats.ms + (elapsedMS or 0)
end

function CDMIcons.SnapshotEventProfile(limit)
    local now = GetTime and GetTime() or 0
    local last = CDMIcons._eventProfileLast
    local elapsed = now - (last.time or now)
    if elapsed <= 0 then elapsed = 1 end

    local rows = {}
    for event, stats in pairs(CDMIcons._eventProfileStats) do
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
local ChargeDebug = function() end

---------------------------------------------------------------------------
-- DYNAMIC CHILD LOOKUP: Scan ALL viewer children to find the one with
-- auraInstanceID matching a tracked spell.  Blizzard recycles children
-- across auras, so the child→spell assignment changes at runtime.
-- Child lookup infrastructure lives in cdm_spelldata.lua (shared by icons + bars).
---------------------------------------------------------------------------
local function IsTotemSlotEntry(entry)
    return entry and entry._isTotemInstance and entry._totemSlot ~= nil
end
CDMIcons.IsTotemSlotEntry = IsTotemSlotEntry

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
local function GetProfessionQualityInfoForItem(itemIDOrLink)
    if not itemIDOrLink or not C_TradeSkillUI then return nil end
    if C_TradeSkillUI.GetItemReagentQualityInfo then
        local info = C_TradeSkillUI.GetItemReagentQualityInfo(itemIDOrLink)
        if info then return info end
    end
    if C_TradeSkillUI.GetItemCraftedQualityInfo then
        return C_TradeSkillUI.GetItemCraftedQualityInfo(itemIDOrLink)
    end
    return nil
end

local function ClearIconProfessionQuality(icon)
    if icon and icon._professionQualityOverlay then
        icon._professionQualityOverlay:Hide()
    end
end

local function UpdateIconProfessionQuality(icon)
    if not icon or not icon._spellEntry then
        ClearIconProfessionQuality(icon)
        return
    end
    local entry = icon._spellEntry
    local etype = entry.type
    if etype ~= "item" and etype ~= "trinket" and etype ~= "slot" then
        ClearIconProfessionQuality(icon)
        return
    end

    local ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    local vt = entry.viewerType
    local containerDB = ncdm and vt and (ncdm[vt] or (ncdm.containers and ncdm.containers[vt]))
    if containerDB and containerDB.showProfessionQuality == false then
        ClearIconProfessionQuality(icon)
        return
    end

    local lookupID
    if etype == "item" then
        lookupID = entry.id
    else
        if Sources and Sources.QueryInventoryItemLink then
            lookupID = Sources.QueryInventoryItemLink("player", entry.id)
        end
        if not lookupID and Sources and Sources.QueryInventoryItemID then
            lookupID = Sources.QueryInventoryItemID("player", entry.id)
        end
    end

    local qualityInfo = lookupID and GetProfessionQualityInfoForItem(lookupID)
    local atlas = qualityInfo and qualityInfo.iconInventory
    if not atlas then
        ClearIconProfessionQuality(icon)
        return
    end

    local overlay = icon._professionQualityOverlay
    if not overlay then
        overlay = icon:CreateTexture(nil, "ARTWORK", nil, 7)
        overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 2)
        icon._professionQualityOverlay = overlay
    end
    overlay:SetAtlas(atlas, (TextureKitConstants and TextureKitConstants.UseAtlasSize) or true)
    overlay:Show()
end
CDMIcons.ClearIconProfessionQuality = ClearIconProfessionQuality
CDMIcons.UpdateIconProfessionQuality = UpdateIconProfessionQuality

---------------------------------------------------------------------------
-- COOLDOWN RESOLUTION
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
-- readable numeric values plus any DurationObject fallback. Secret numbers
-- (combat / Blizzard CDM data feed) skip the numeric branch — DurationObject
-- is the authoritative input for C-side rendering when values are secret.
local function AccumulateCooldown(st, dur, info, bestStart, bestDur, bestDurObj)
    local durObj = ExtractCooldownDurObj(info)
    if durObj and not bestDurObj then
        bestDurObj = durObj
    end
    if issecretvalue and (issecretvalue(st) or issecretvalue(dur)) then
        if durObj and not bestDurObj then
            bestDurObj = durObj
        end
        return bestStart, bestDur, bestDurObj
    end
    if IsSafeNumeric(st) and IsSafeNumeric(dur) and dur > 0 then
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
    return bestStart, bestDur, bestDurObj
end

local function GetBestSpellCooldown(spellID)
    if not spellID then return nil, nil, nil, false, false end

    local bestStart, bestDuration = nil, nil
    local bestDurObj = nil
    local isActive = false
    local realCooldownActive = false
    local durationObjectEligible = false

    -- Check primary spell with a fresh C_Spell query.
    local cdInfo = QueryCooldown(spellID)
    local cdActive = false
    local cdRealUnknown = false
    if cdInfo then
        local realActive
        cdActive, realActive = CDMIcons.ClassifySpellCooldownState(spellID, cdInfo)
        if cdActive == true then
            isActive = true
            durationObjectEligible = true
        end
        if cdActive == true and realActive == false then
            bestStart, bestDuration, bestDurObj =
                AccumulateCooldown(cdInfo.startTime, cdInfo.duration, cdInfo,
                    bestStart, bestDuration, bestDurObj)
        end
        if realActive ~= false then
            if realActive == true then
                realCooldownActive = true
                isActive = true
            else
                cdRealUnknown = true
            end
            bestStart, bestDuration, bestDurObj =
                AccumulateCooldown(cdInfo.startTime, cdInfo.duration, cdInfo,
                    bestStart, bestDuration, bestDurObj)
        end
    end
    local chargeInfo = QueryCharges(spellID)
    local chargeBased = false
    if chargeInfo then
        local maxCharges = chargeInfo.maxCharges
        chargeBased = maxCharges and maxCharges > 1
        -- It means the recharge UI should run, not that all charges are gone.
        local chargeActive = SafeBoolean(chargeInfo.isActive) == true
        if chargeActive then
            isActive = true
            realCooldownActive = true
            bestStart, bestDuration, bestDurObj =
                AccumulateCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo,
                    bestStart, bestDuration, bestDurObj)
        end
    end
    if cdActive == true and cdRealUnknown and not chargeBased then
        -- Trust Blizzard's per-event signal: active + isOnGCD==false is a
        -- real cooldown; isOnGCD==true is a GCD pulse. Catalog-based
        -- inference (SpellHasBaseCooldownLongerThanGCD) is banned because
        -- it answers a category question, not a state question, and
        -- mis-classifies GCD pulses on spells that have a base CD entry.
        local onGCD, onGCDSecret = CDMIcons.GetCooldownInfoField(cdInfo, "isOnGCD")
        if onGCDSecret ~= true and onGCD == false then
            realCooldownActive = true
        end
    end

    -- Check override spell (no table allocation; just a second ID).
    do
        local overrideID = QueryOverrideSpell(spellID)
        if overrideID and overrideID ~= spellID then
            cdInfo = QueryCooldown(overrideID)
            local overrideCdActive = false
            local overrideCdRealUnknown = false
            if cdInfo then
                local realActive
                overrideCdActive, realActive = CDMIcons.ClassifySpellCooldownState(overrideID, cdInfo)
                if overrideCdActive == true then
                    isActive = true
                    durationObjectEligible = true
                end
                if overrideCdActive == true and realActive == false then
                    bestStart, bestDuration, bestDurObj =
                        AccumulateCooldown(cdInfo.startTime, cdInfo.duration, cdInfo,
                            bestStart, bestDuration, bestDurObj)
                end
                if realActive ~= false then
                    if realActive == true then
                        realCooldownActive = true
                        isActive = true
                    else
                        overrideCdRealUnknown = true
                    end
                    bestStart, bestDuration, bestDurObj =
                        AccumulateCooldown(cdInfo.startTime, cdInfo.duration, cdInfo,
                            bestStart, bestDuration, bestDurObj)
                end
            end
            chargeInfo = QueryCharges(overrideID)
            local overrideChargeBased = false
            if chargeInfo then
                local maxCharges = chargeInfo.maxCharges
                overrideChargeBased = maxCharges and maxCharges > 1
                local chargeActive2 = SafeBoolean(chargeInfo.isActive) == true
                if chargeActive2 then
                    isActive = true
                    realCooldownActive = true
                    bestStart, bestDuration, bestDurObj =
                        AccumulateCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo,
                            bestStart, bestDuration, bestDurObj)
                end
            end
            if overrideCdActive == true and overrideCdRealUnknown and not overrideChargeBased then
                -- See sibling block above for the spellID variant.
                -- cdInfo here is the override's cdInfo from QueryCooldown(overrideID).
                local onGCD, onGCDSecret = CDMIcons.GetCooldownInfoField(cdInfo, "isOnGCD")
                if onGCDSecret ~= true and onGCD == false then
                    realCooldownActive = true
                end
            end
        end
    end

    -- DurationObject APIs (12.0+, secret-safe). These are the only
    -- authoritative spell timing source we forward to owned cooldowns.
    -- Gate queries behind real cooldown/recharge state. isActive is already
    -- the non-secret "Blizzard would render cooldown UI" signal; isOnGCD and
    -- the later usability split keep GCD/resource states from becoming real
    -- cooldown swipes. Some overridden CDM spellIDs expose only a 1.5s
    -- numeric cooldown table while GetSpellCooldownDuration(spell, true)
    -- still returns the real cooldown DurationObject. Let that object prove
    -- real cooldown state instead of blocking the query on the numeric table.
    if not bestDurObj and (realCooldownActive or durationObjectEligible) then
        -- Check charge duration FIRST — for charged spells, the charge
        -- recharge DurationObject is what we want to display, not the
        -- spell's own cooldown DurationObject (which may be a shorter
        -- per-use CD or GCD).  GetSpellChargeDuration returns the
        -- recharge timer DurationObject, secret-safe for combat.
        bestDurObj = QueryChargeDuration(spellID)
        if not bestDurObj then
            local overrideID = QueryOverrideSpell(spellID)
            if overrideID and true and overrideID ~= spellID then
                bestDurObj = QueryChargeDuration(overrideID)
            end
        end
        if bestDurObj then
            isActive = true
            realCooldownActive = true
        end
    end

    if not bestDurObj and (realCooldownActive or durationObjectEligible) then
        -- Fall back to spell cooldown duration for non-charged spells.
        bestDurObj = QueryDuration(spellID)
        if not bestDurObj then
            local overrideID = QueryOverrideSpell(spellID)
            if overrideID and true and overrideID ~= spellID then
                bestDurObj = QueryDuration(overrideID)
            end
        end
        if bestDurObj then
            isActive = true
            realCooldownActive = true
        end
    end
    -- Discard DurationObjects extracted from cdInfo when no source confirms
    -- a real cooldown.  12.0.5+ cooldown info tables may carry zero-span
    -- or non-cooldown DurationObjects for ready/resource-wait states.
    if not realCooldownActive then
        bestDurObj = nil
    end

    if bestDurObj then
        return nil, nil, bestDurObj, isActive, realCooldownActive
    end

    -- Some normal spells still expose only readable numeric cooldown timing
    -- here while the newer isActive flag is absent/false. Custom CDM bars do
    -- not have a Blizzard viewer child to mirror from, so dropping this safe
    -- payload makes non-charged custom entries disappear under "show only on
    -- cooldown" while charged entries keep working. The duration > GCD guard
    -- already proves this is a real cooldown, so set realCooldownActive=true.
    -- Secret numeric values can't enter the SetCooldown fallback path
    -- (12.0.5+ rejects them from tainted code), so bail to the (nil, nil)
    -- return when they're secret — caller treats as "no cooldown data".
    local secretNumeric = issecretvalue
        and (issecretvalue(bestStart) or issecretvalue(bestDuration))
    if not secretNumeric
       and IsSafeNumeric(bestStart) and IsSafeNumeric(bestDuration)
       and bestStart > 0 and bestDuration > GCD_MAX_DURATION
       and (bestStart + bestDuration) > GetTime()
    then
        return bestStart, bestDuration, nil, true, true
    end

    if not secretNumeric
       and isActive == true
       and IsSafeNumeric(bestStart) and IsSafeNumeric(bestDuration)
       and bestStart > 0 and bestDuration > 0
    then
        return bestStart, bestDuration, nil, true, false
    end

    return nil, nil, nil, isActive, realCooldownActive
end

-- Item cooldown resolution
function CDMIcons.GetItemUseSpellID(itemID)
    if not itemID then return nil end

    if Sources and Sources.QueryItemSpell then
        local _, spellID = Sources.QueryItemSpell(itemID)
        if spellID then
            return spellID
        end
    end

    if Sources and Sources.QueryFirstTriggeredSpellForItem then
        local itemQuality
        if Sources.QueryItemQualityByID then
            local quality = Sources.QueryItemQualityByID(itemID)
            if quality ~= nil then
                itemQuality = quality
            end
        end

        local spellID = Sources.QueryFirstTriggeredSpellForItem(itemID, itemQuality)
        if spellID then
            return spellID
        end
    end

    return nil
end

function CDMIcons.GetRawItemUseSpellIDForAuraQuery(itemID)
    if not itemID then return nil end

    if Sources and Sources.QueryItemSpell then
        local _, spellID = Sources.QueryItemSpell(itemID)
        if spellID then
            return spellID
        end
    end

    if Sources and Sources.QueryFirstTriggeredSpellForItem then
        local itemQuality
        if Sources.QueryItemQualityByID then
            local quality = Sources.QueryItemQualityByID(itemID)
            if quality ~= nil then
                itemQuality = quality
            end
        end

        local spellID = Sources.QueryFirstTriggeredSpellForItem(itemID, itemQuality)
        if spellID then
            return spellID
        end
    end

    return nil
end

local function GetItemCooldown(itemID)
    if not itemID or not (Sources and Sources.QueryItemCooldown) then return nil, nil, nil end
    local startTime, duration, enabled = Sources.QueryItemCooldown(itemID)
    if type(startTime) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return nil, nil, nil
    end
    if enabled == 0 or enabled == false then
        return nil, nil, nil
    end
    return startTime, duration, nil
end

local function GetSlotCooldown(slotID)
    if not slotID or not GetInventoryItemCooldown then return nil, nil, nil end
local ok = true; local startTime, duration, enabled = GetInventoryItemCooldown("player", slotID)
    if not ok then return nil, nil, nil end
    if type(startTime) ~= "number" or type(duration) ~= "number" then
        return nil, nil, nil
    end
    if enabled ~= 1 or duration <= 1.5 then
        return nil, nil, nil
    end
    return startTime, duration, nil
end

function CDMIcons.MarkGCDSwipe(icon)
    if not icon then return end
    icon._showingGCDSwipe = true
    icon._showingRealCooldownSwipe = nil
end

function CDMIcons.ClearGCDSwipe(icon)
    if not icon then return end
    icon._showingGCDSwipe = nil
end

-- Expose for external use (cdm_icon_factory.lua imports these as upvalues;
-- cdm_resolvers.lua + cdm_bars.lua call GetItemCooldown/GetSlotCooldown via
-- CDMIcons.X / CDMCooldown.X)
CDMIcons.GetBestSpellCooldown = GetBestSpellCooldown
CDMCooldown.GetItemCooldown = GetItemCooldown
CDMCooldown.GetSlotCooldown = GetSlotCooldown
CDMIcons.GetItemCooldown = GetItemCooldown
CDMIcons.GetSlotCooldown = GetSlotCooldown

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
    if CDMIcons.ApplyCustomBarSwipeStyle then
        CDMIcons.ApplyCustomBarSwipeStyle(icon)
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

---------------------------------------------------------------------------
-- IsAuraCurrentlyActive: detect whether an entry's associated aura is
-- currently up on the player or its target. Returns (isActive, auraUnit,
-- auraInstanceID). Used by cdm_effects.lua and aura stack text resolution.
---------------------------------------------------------------------------
local function IsAuraCurrentlyActive(entry)
    if not entry then return false, nil, nil end

    local sid = entry.overrideSpellID or entry.spellID or entry.id
    if not sid then
        return false, nil, nil
    end

    -- Step C: captured-aura cache (combat-safe, encounter-safe).
    -- Encounter/M+/PvP starts wipe this cache so stale instIDs don't leak.
    -- Lookup IDs combine the entry's own IDs AND every linked aura ID
    -- the CDM catalog associates with this spell — captured payloads are
    -- keyed by the actual aura's spellID, which often differs from the
    -- cast/ability ID the user added. Without the catalog IDs, the
    -- captured cache silently misses every cast-vs-aura ID mismatch in
    -- combat (when GetPlayerAuraBySpellID's restriction kicks in).
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.GetCapturedAuraForLookup then
        local lookupIDs = {}
        local seenLookup = {}
        local function addLookup(id)
            if not id or seenLookup[id] then return end
            seenLookup[id] = true
            lookupIDs[#lookupIDs + 1] = id
        end
        local function addMappedLookups(id)
            if not (id and CDMSpellData.GetAuraIDsForSpell) then return end
            local mappedIDs = CDMSpellData:GetAuraIDsForSpell(id)
            if mappedIDs then
                for _, aid in ipairs(mappedIDs) do addLookup(aid) end
            end
        end
        addLookup(sid)
        addLookup(entry.spellID)
        addLookup(entry.id)
        addMappedLookups(sid)
        addMappedLookups(entry.spellID)
        addMappedLookups(entry.id)
        local captured = CDMSpellData.GetCapturedAuraForLookup(lookupIDs, entry.name)
        if captured and captured.auraInstanceID then
            return true, captured.unit or "player", captured.auraInstanceID
        end
    end

    -- Step D: direct player aura query fallback. In combat the captured
    -- UNIT_AURA payload above is the authoritative source; direct spell
    -- lookups can be restricted and may miss auras that are otherwise
    -- visible through the event payload. If a direct query succeeds, the
    -- returned AuraData's existence is enough to classify the icon as an
    -- aura; auraInstanceID is forwarded to downstream C-side consumers.
    --
    -- Prefer GetUnitAuraBySpellID when present. The OOC ownership check
    -- (IsAuraOwnedByPlayerOrPet) is removed because reading sourceUnit /
    -- isFromPlayerOrPlayerPet in Lua fails in combat where those fields are
    -- secret, so the check would silently reject every in-combat hit.
    if Sources and (Sources.QueryUnitAuraBySpellID or Sources.QueryPlayerAuraBySpellID) then
        local seen = {}
        local function tryQuery(id)
            if not id or seen[id] then return nil end
            seen[id] = true
            if Sources.QueryUnitAuraBySpellID then
                local ad = Sources.QueryUnitAuraBySpellID("player", id)
                if ad then return ad end
            end
            if Sources.QueryPlayerAuraBySpellID then
                local ad = Sources.QueryPlayerAuraBySpellID(id)
                if ad then return ad end
            end
            return nil
        end
        -- Try the cast/configured IDs first; some player auras are returned
        -- directly by that ID. Mapped aura IDs remain the fallback for
        -- cast->aura mismatches.
        local ad1 = tryQuery(sid)
        if ad1 then return true, "player", GetAuraDataInstanceID(ad1) end
        local ad2 = tryQuery(entry.spellID)
        if ad2 then return true, "player", GetAuraDataInstanceID(ad2) end
        local ad3 = tryQuery(entry.id)
        if ad3 then return true, "player", GetAuraDataInstanceID(ad3) end
        local CDMSpellData = ns.CDMSpellData
        if CDMSpellData and CDMSpellData.GetAuraIDsForSpell then
            local function tryMappedIDs(id)
                if not id then return false end
                local mappedIDs = CDMSpellData:GetAuraIDsForSpell(id)
                if mappedIDs then
                    for _, aid in ipairs(mappedIDs) do
                        local ad = tryQuery(aid)
                        if ad then return true, "player", GetAuraDataInstanceID(ad) end
                    end
                end
                return false
            end
            local active, unit, instID = tryMappedIDs(sid)
            if active then return active, unit, instID end
            active, unit, instID = tryMappedIDs(entry.spellID)
            if active then return active, unit, instID end
            active, unit, instID = tryMappedIDs(entry.id)
            if active then return active, unit, instID end
        end
        -- tryQuery de-duplicates, so all direct IDs have already had a
        -- chance before mapped-ID fallback above.
    end
    -- Name fallback for cast-id vs aura-id mismatches that share names
    -- and aren't in the CDM catalog (rare).
    if entry.name and entry.name ~= ""
        and Sources and Sources.QueryAuraDataBySpellName then
        local ad = Sources.QueryAuraDataBySpellName("player", entry.name, "HELPFUL")
        if ad then
            return true, "player", GetAuraDataInstanceID(ad)
        end
    end

    return false, nil, nil
end

CDMIcons.IsAuraCurrentlyActive = IsAuraCurrentlyActive

local function GetAuraDisplaySourceID(r, fallbackID)
    if not r then return fallbackID end
    local sourceID = r.auraInstanceID or r.totemSlot
    return sourceID or fallbackID
end

local function ClearAuraStateForIcon(icon, entry)
    if not icon then return end
    icon._auraActive = false
    icon._auraUnit = nil
    icon._auraInstanceID = nil
    icon._totemSlot = entry and entry._totemSlot or nil
    icon._isTotemInstance = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
    icon._activeAuraSpellID = nil
    icon._auraIsHarmful = nil
end
CDMIcons.ClearAuraStateForIcon = ClearAuraStateForIcon

local function ApplyAuraStateToIcon(icon, entry, sid, r)
    if not r then
        ClearAuraStateForIcon(icon, entry)
        return nil, false, nil
    end

    if r.isActive then
        local sourceID = GetAuraDisplaySourceID(r, sid)
        icon._auraActive = true
        icon._auraUnit = r.auraUnit
        icon._auraInstanceID = r.auraInstanceID
        icon._totemSlot = r.totemSlot or entry._totemSlot or nil
        icon._isTotemInstance = r.isTotemInstance and true or nil
        icon._activeAuraSpellID = r.resolvedAuraSpellID
        if not icon._activeAuraSpellID and r.auraData then
            local sid2 = r.auraData.spellId
            sid2 = Helpers and Helpers.SafeValue and Helpers.SafeValue(sid2, nil) or sid2
            if not ((Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(sid2))
                or (issecretvalue and issecretvalue(sid2))) then
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
            harmful = Helpers and Helpers.SafeValue and Helpers.SafeValue(harmful, nil) or harmful
            if (Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(harmful))
                or (issecretvalue and issecretvalue(harmful)) then
                harmful = nil
            end
            if harmful ~= nil then
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
CDMIcons.ApplyAuraStateToIcon = ApplyAuraStateToIcon

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
-- Aura-kind: stacks via C_UnitAuras.GetAuraApplicationDisplayCount (via
-- ns.CDMSpellData.GetAuraApplications, which already wraps it with
-- IsSecretValue-aware caching).
-- Cooldown-kind: mirror text first, then Blizzard's cached cast-count fields
-- or C_Spell.GetSpellCastCount (via QuerySpellCount). Multi-charge fallback
-- still uses C_Spell.GetSpellDisplayCount, gated by cached maxCharges > 1.
---------------------------------------------------------------------------
local GetAuraApplicationsForSpell

local function ValueExists(value)
    return value and true or false
end

local function ResolveMirrorStackText(icon)
    local mirror = ns.CDMBlizzMirror
    local cooldownID = icon and icon._blizzMirrorCooldownID
    if cooldownID == nil then
        return nil, nil, false
    end
    if not (mirror and mirror.GetStateByCooldownID) then
        return nil, nil, true
    end

    local m = mirror.GetStateByCooldownID(cooldownID, icon._blizzMirrorCategory)
    if not m then
        return nil, nil, true
    end

    local stackText = m.stackText
    if m.stackTextShown ~= false and ValueExists(stackText) then
        return stackText, m.stackTextSource or "Applications", true
    end

    local countText = m.cooldownChargesCount
    if ValueExists(countText)
        and (m.cooldownChargesShown == true or m.chargeCountFrameShown == true) then
        return countText, "ChargeCount", true
    end

    if m.stackTextShown == false then
        return nil, m.stackTextSource, true
    end

    return nil, m.stackTextSource, true
end

function CDMIcons.ResolveIconStackText(icon)
    if not icon or not icon._spellEntry then
        return nil, nil
    end
    local entry = icon._spellEntry

    -- Aura-kind path
    if IsAuraEntry(entry) then
        local active, auraUnit, instID = IsAuraCurrentlyActive(entry)
        if active and instID and ns.CDMSpellData and ns.CDMSpellData.GetAuraApplications then
            local resolved, stacks = ns.CDMSpellData.GetAuraApplications(auraUnit or "player", instID)
            if resolved and stacks ~= nil then
                return stacks, "Applications"
            end
        end
        return nil, nil
    end

    -- Cooldown-kind path: only spells known to have multiple charges get text.
    local sid = icon._runtimeSpellID
        or (entry.overrideSpellID or entry.spellID or entry.id)
    if not sid then
        return nil, nil
    end
    local overrideID = QueryOverrideSpell(sid)
    if overrideID then sid = overrideID end

    local mirrorText, mirrorSource, mirrorBacked = ResolveMirrorStackText(icon)
    if ValueExists(mirrorText) then
        return mirrorText, mirrorSource, true
    end
    if mirrorBacked then
        local spellCount, countSource
        if CDMIcons.GetSpellCountForEntry then
            spellCount, countSource = CDMIcons.GetSpellCountForEntry(sid, entry, icon)
        end
        if CDMIcons.ValueIsPresent(spellCount) then
            return spellCount, countSource or "spell-count", true
        end
        return nil, mirrorSource, true
    end

    local svDB = GetChargeMetadataDB()
    local maxC = svDB and svDB[sid]
    if not maxC or maxC <= 1 then
        return nil, nil
    end

    local text = QueryDisplayCount(sid)
    if text == nil then return nil, nil end
    return text, "ChargeCount"
end

local function ResolveTrackerSettingsNow(viewerType)
    if type(GetTrackerSettings) == "function" then
        return GetTrackerSettings(viewerType)
    end
    local db = GetDB and GetDB()
    if not db or not viewerType then return nil end
    return db[viewerType] or (db.containers and db.containers[viewerType]) or nil
end
CDMIcons.ResolveTrackerSettingsNow = ResolveTrackerSettingsNow

local function IsCustomBarSettingsNow(settings)
    if CDMIcons.IsCustomBarContainer then
        return CDMIcons.IsCustomBarContainer(settings)
    end
    return type(settings) == "table" and settings.containerType == "customBar"
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

local function ApplyCooldownDesaturation(icon, entry, settings, resolvedMode)
    if not icon or not entry or not icon.Icon or not icon.Icon.SetDesaturated then
        return
    end

    settings = settings or ResolveTrackerSettingsNow(entry.viewerType)

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

    if customBar
       and settings.noDesaturateWithCharges
       and shouldDesaturate then
        local cooldownState = CDMIcons.ResolveCooldownActivityState
            and CDMIcons.ResolveCooldownActivityState(icon, entry, settings, GetTime())
        if cooldownState
           and (entry.hasCharges or cooldownState.hasCharges)
           and cooldownState.rechargeActive
           and cooldownState.hasChargesRemaining then
            shouldDesaturate = false
        end
    end

    resolvedMode = resolvedMode or icon._resolvedCooldownMode
    local hasRealCD = icon._hasCooldownActive == true
        and resolvedMode ~= "aura"
        and resolvedMode ~= "gcd-only"
        and resolvedMode ~= "inactive"

    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(entry.name, "DESAT result: hasRealCD=", hasRealCD,
            "_hasCooldownActive=", icon._hasCooldownActive,
            "mode=", tostring(resolvedMode),
            "hasCharges=", entry.hasCharges,
            "viewerType=", entry.viewerType)
    end

    if entry.viewerType ~= "buff"
       and not auraBlocks
       and not icon._rangeTinted
       and shouldDesaturate
       and hasRealCD then
        if icon._usabilityTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._usabilityTinted = nil
            icon._lastVisualState = nil
        end
        icon.Icon:SetDesaturated(true)
        icon._cdDesaturated = true
    else
        icon.Icon:SetDesaturated(false)
        icon._cdDesaturated = nil
    end
end
CDMIcons.ApplyCooldownDesaturation = ApplyCooldownDesaturation

local function ReleaseCooldownDesaturation(icon)
    if not icon then return end
    if icon._cdDesaturated
       and icon.Icon
       and icon.Icon.SetDesaturated then
        icon.Icon:SetDesaturated(false)
    end
    icon._cdDesaturated = nil
end

local function GetIconCooldownIdentifier(icon)
    local entry = icon and icon._spellEntry
    if not entry then return nil end
    -- Resolve from BASE spell at runtime so dynamic transforms are current
    local base = entry.spellID or entry.id
    if base then
        local ovId = QueryOverrideSpell(base)
        if ovId then return ovId end
    end
    return base
end

function CDMIcons.CaptureTrustedGCDStateForIcon(icon, spellState, stamp)
    if not icon or not icon._spellEntry then return false end

    local sid = GetIconCooldownIdentifier(icon)
    sid = Helpers.SafeValue and Helpers.SafeValue(sid, nil) or sid
    local prev = icon._isOnGCD

    if not sid or not QueryCooldown then
        if prev ~= nil then
            icon._isOnGCD = nil
            icon._isOnGCDTrustedAt = nil
            return true
        end
        icon._isOnGCD = nil
        icon._isOnGCDTrustedAt = nil
        return false
    end

    local trusted = spellState[sid]
    if trusted == nil then
        local cdInfo = QueryCooldown(sid)
        local onGCD = cdInfo and cdInfo.isOnGCD
        if type(onGCD) == "boolean" then
            trusted = onGCD
        end
        if trusted ~= nil then
            spellState[sid] = trusted
        end
    end

    if type(trusted) == "boolean" then
        icon._isOnGCD = trusted
        icon._isOnGCDTrustedAt = stamp
        return prev ~= trusted
    end

    icon._isOnGCD = nil
    icon._isOnGCDTrustedAt = nil
    return prev ~= nil
end

function CDMIcons.CaptureTrustedGCDState()
    if not QueryCooldown then
        return false
    end

    local spellState = CDMIcons._trustedGCDSpellState or {}
    wipe(spellState)
    CDMIcons._trustedGCDSpellState = spellState
    local stamp = GetTime()
    CDMIcons._trustedGCDStamp = stamp

    local anyChanged = false
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMIcons.CaptureTrustedGCDStateForIcon(icon, spellState, stamp) then
                anyChanged = true
            end
        end
    end
    return anyChanged
end

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
CDMIcons.CancelCooldownExpiryRefresh = CancelCooldownExpiryRefresh

local function ScheduleCooldownExpiryRefreshAt(icon, key, expiresAt)
    if not icon or not key or not C_Timer then return end
    if not GetTime or not IsSafeNumeric(expiresAt) then return end
    if not (C_Timer.NewTimer or C_Timer.After) then return end

    local delta = icon._cooldownExpiryAt and (icon._cooldownExpiryAt - expiresAt) or nil
    if delta and delta < 0 then delta = -delta end
    if icon._cooldownExpiryTimerKey == key
       and delta
       and delta <= CDMIcons.COOLDOWN_EXPIRY_RESCHEDULE_EPSILON then
        return
    end

    local existing = icon._cooldownExpiryTimer
    if existing and existing.Cancel then
        existing.Cancel(existing)
    end

    local delay = expiresAt - GetTime()
    if delay < 0 then delay = 0 end
    delay = delay + CDMIcons.COOLDOWN_EXPIRY_REFRESH_FUDGE

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
    local start = CDMIcons.GetCooldownInfoField(cdInfo, "startTime")
    if start == nil then
        start = CDMIcons.GetCooldownInfoField(cdInfo, "start")
    end
    local duration = CDMIcons.GetCooldownInfoField(cdInfo, "duration")
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

-- Single-writer cooldown apply: ask the resolver, bind icon.Cooldown to the
-- returned DurationObject. Item entries may fall back to SetCooldown only
-- with verified non-secret numeric item timing. SetCooldownFromDurationObject
-- creates a live C-side binding; numeric item fallback gets a one-shot expiry
-- refresh through this same writer. Flags are derived from the classifier —
-- no Blizzard frame state mirroring.
ApplyResolvedCooldown = function(icon)
    local addonCD = icon and icon.Cooldown
    if not addonCD then return false end

    local durObj, mode, sourceID, resolvedStart, resolvedDuration, resolvedSpellID, mirrorBackedDuration, mirrorPayload =
        CDMIcons.ResolveIconDurationObject(icon)
    icon._resolvedCooldownMode = mode

    -- "Real CD active" desaturation gate. The only Lua decision inputs here
    -- are readable cooldown booleans. Charge counts are restricted during
    -- combat, so charged spells never consult currentCharges. A charged
    -- spell's SpellChargeInfo.isActive selects the recharge DurObj in the
    -- resolver; desaturation follows SpellCooldownInfo.isActive only after the
    -- resolver has classified the duration as a real cooldown/recharge.
    local entry = icon._spellEntry
    local entryIsAura = entry and IsAuraEntry(entry)
    local itemEntryForCooldown = entry
        and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
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
    end
    local cdActive = false
    local resolvedCdInfo = nil
    local _dbgIsActive, _dbgIsOnGCD = nil, nil
    local _dbgChargeActive, _dbgChargeMax = nil, nil
    if entry and sid then
        local ci = QueryCharges(sid)
        if ci then
            _dbgChargeActive = tostring(ci.isActive)
            _dbgChargeMax = tostring(ci.maxCharges)
        end
    end
    local numericCooldownActive = IsSafeNumeric(resolvedStart)
        and IsSafeNumeric(resolvedDuration)
        and resolvedStart > 0
        and resolvedDuration > GCD_MAX_DURATION
        and (resolvedStart + resolvedDuration) > GetTime()
    if mode == "item-cooldown" and numericCooldownActive then
        cdActive = true
    end
    local mirrorCooldownActive = mode == "cooldown"
        and durObj
        and type(sourceID) == "string"
        and sourceID:sub(1, 7) == "mirror:"
    -- No "transient mirror gap" preservation: cdInfo.isActive / isOnGCD are
    -- authoritative per the directive (see feedback_blizz_cd_state_signals).
    -- If the resolver returns a different mode this pass, that's the truth;
    -- don't override it from stale state.
    local mirrorBackedRealMode = mirrorBackedDuration == true
        and (mode == "cooldown"
            or mode == "charge"
            or mode == "item-cooldown")
    -- cdInfo.isActive is authoritative (feedback_blizz_cd_state_signals).
    -- The Blizzard mirror reports a cooldownID as active when a proc fires
    -- (mirror cooldownID 27927 for Festering Strike showed isActive on the
    -- proc-substitute's behalf), but the underlying spell's cdInfo.isActive
    -- correctly returns false once the proc is no longer holding the slot.
    -- Without this override the icon stayed mode=cooldown / desaturated for
    -- 12+ seconds during a proc window, and procOnUsable glows were
    -- suppressed because IsSpellCastable checks icon._hasCooldownActive.
    -- Skip when numericCooldownActive (item path) to preserve the
    -- numeric-driven item-cooldown classification.
    if mirrorBackedRealMode
       and not numericCooldownActive
       and sid
       and not entryIsAura then
        local cdInfo = QueryCooldown(sid)
        if cdInfo then
            resolvedCdInfo = cdInfo
            local cdInfoActive = CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
            if cdInfoActive == false then
                mode = "inactive"
                sourceID = nil
                icon._resolvedCooldownMode = mode
                mirrorCooldownActive = false
                mirrorBackedRealMode = false
            else
                -- isActive=true + isOnGCD=true means the visible swipe is
                -- a GCD pulse, not a real CD (feedback_blizz_cd_state_signals).
                -- We release the cooldown-active flag so desaturation lifts
                -- and procOnUsable glows can fire, but we DO NOT flip the
                -- resolved mode to gcd-only. The mirror still has the real
                -- CD's durObj bound; forcing mode=gcd-only here would re-key
                -- the dedupe (cooldown→gcd-only) and re-style the cooldown
                -- frame as a GCD swipe while it's still bound to the real
                -- CD durObj — the visible result is the swipe vanishing for
                -- the brief window until the mirror's own state catches up
                -- and emits a real gcd-only durObj. Let the mirror handle the
                -- mode/durObj transition; we just gate the side effects
                -- (desat, _hasCooldownActive) on cdInfo authority.
                local cdInfoOnGCD, cdInfoOnGCDSecret =
                    CDMIcons.GetCooldownInfoField(cdInfo, "isOnGCD")
                if not cdInfoOnGCDSecret and cdInfoOnGCD == true then
                    mirrorCooldownActive = false
                    mirrorBackedRealMode = false
                end
            end
        end
    end
    if mirrorBackedDuration == true then
        cdActive = mirrorBackedRealMode
    elseif sid and not entryIsAura then
        local cdInfo = resolvedCdInfo or QueryCooldown(sid)
        if cdInfo then
            resolvedCdInfo = cdInfo
            local cdInfoActive = CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
            local cdInfoOnGCD = nil
            if CDMIcons._trustIsOnGCDForBatch == true then
                local trustedSid = Helpers.SafeValue and Helpers.SafeValue(sid, nil) or sid
                local trusted = trustedSid and CDMIcons._trustedGCDSpellState and CDMIcons._trustedGCDSpellState[trustedSid]
                if type(trusted) == "boolean" then
                    cdInfoOnGCD = trusted
                end
            end
            if cdInfoOnGCD == nil then
                local liveOnGCD, liveOnGCDSecret = CDMIcons.GetCooldownInfoField(cdInfo, "isOnGCD")
                if not liveOnGCDSecret and type(liveOnGCD) == "boolean" then
                    cdInfoOnGCD = liveOnGCD
                end
            end
            _dbgIsActive = cdInfoActive
            _dbgIsOnGCD = cdInfoOnGCD
            local cooldownModeActive = mode == "cooldown"
                or mode == "charge"
                or mode == "item-cooldown"
            local spellUsable = nil
            if mode == "cooldown" and not mirrorCooldownActive then
                spellUsable = QuerySpellUsableState(sid)
            end
            local nonCooldownUsabilityState = mode == "cooldown"
                and not mirrorCooldownActive
                and spellUsable == true
            if mirrorCooldownActive
                or ((cdInfoActive == true)
                    and cooldownModeActive
                    and not nonCooldownUsabilityState) then
                cdActive = true
            end
        end
    end
    if mirrorCooldownActive and not resolvedCdInfo then
        cdActive = true
    end
    -- Diagnostic: log every isActive/isOnGCD transition for icons whose
    -- name matches CDMIcons._desatTraceName. Set via /cdmtrace <spell name>.
    if CDMIcons._desatTraceName and entry and entry.name == CDMIcons._desatTraceName then
        local prevActive = icon._desatTracePrev
        if prevActive ~= cdActive then
            icon._desatTracePrev = cdActive
            print(string.format(
                "|cffff8800[desat]|r %s sid=%s cd.isActive=%s cd.isOnGCD=%s charges.isActive=%s maxCharges=%s -> cdActive=%s",
                tostring(entry.name), tostring(sid),
                tostring(_dbgIsActive), tostring(_dbgIsOnGCD),
                tostring(_dbgChargeActive), tostring(_dbgChargeMax),
                tostring(cdActive)))
        end
    end
    icon._hasCooldownActive = cdActive
    icon._hasRealCooldownActive = cdActive
    -- Resolver is the single writer of desaturation. Action depends on
    -- the resolved mode (ApplyCooldownDesaturation's hasRealCD gate at
    -- cdm_icons.lua:1217-1220 makes the call):
    --   * real-CD modes (cooldown / charge / item-cooldown) → desat ON
    --   * aura / inactive / gcd-only                        → desat OFF
    -- gcd-only means the visible swipe is a GCD, not a real CD
    -- (feedback_blizz_cd_state_signals). If the resolver returns gcd-only
    -- the real CD is either over or shorter than the remaining GCD, so the
    -- spell is effectively usable and the icon must not be desaturated.
    -- Without this call the prior real-CD desat=true persists through the
    -- entire GCD-after-CD-end chain (mode stays gcd-only until GCDs stop),
    -- leaving the icon greyed out for seconds after the real CD ended.
    ApplyCooldownDesaturation(icon, entry, nil, mode)

    local hasNumericCooldown = mode == "item-cooldown" and numericCooldownActive
    local keySource = sourceID
    local key = mode .. ":" .. tostring(keySource)
    if ns.CDMRuntimeStore and ns.CDMRuntimeStore.SetIconState then
        ns.CDMRuntimeStore.SetIconState(icon, {
            mode = mode,
            sourceID = sourceID,
            spellID = sid or resolvedSpellID,
            durObj = durObj,
            start = resolvedStart,
            duration = resolvedDuration,
            active = cdActive,
            numericCooldownActive = hasNumericCooldown,
            key = key,
            mirrorBacked = mirrorBackedDuration == true,
            mirrorState = mirrorPayload and mirrorPayload.state or nil,
        })
    end

    if (not durObj and not hasNumericCooldown) or mode == "inactive" then
        CancelCooldownExpiryRefresh(icon)
        if mode == "aura"
           and InCombatLockdown()
           and icon._lastAuraDurObj
           and icon._lastDurObjKey == key
        then
            icon._showingRealCooldownSwipe = true
            CDMIcons.ClearGCDSwipe(icon)
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
            CDMIcons.ClearGCDSwipe(icon)
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
        CDMIcons.ClearGCDSwipe(icon)
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
    -- in cdm_bars.lua — safe in combat, no secret values.
    local shouldScheduleExpiry = cdActive == true
        and (resolvedCdInfo ~= nil or hasNumericCooldown)
        and (mode == "cooldown" or mode == "charge" or mode == "item-cooldown")
    if icon._lastDurObjKey == key
       and (mode ~= "aura" or durObj == icon._lastDurObj) then
        if shouldScheduleExpiry then
            if resolvedCdInfo then
                ScheduleCooldownExpiryRefresh(icon, key, resolvedCdInfo)
            else
                ScheduleCooldownExpiryRefreshAt(icon, key, resolvedStart + resolvedDuration)
            end
        else
            CancelCooldownExpiryRefresh(icon)
        end
        if mode == "aura" or mode == "charge" or mode == "cooldown" or mode == "item-cooldown" then
            icon._lastResolvedMode = mode
            icon._lastResolvedSourceID = sourceID
            icon._lastResolvedSpellID = sid or resolvedSpellID
            icon._showingRealCooldownSwipe = true
            CDMIcons.ClearGCDSwipe(icon)
        elseif mode == "gcd-only" then
            CDMIcons.MarkGCDSwipe(icon)
        end
        ReapplySwipeStyle(addonCD, icon)
        return true
    end
    icon._lastDurObjKey = key
    icon._lastDurObj = durObj
    icon._lastResolvedMode = mode
    icon._lastResolvedSourceID = sourceID
    icon._lastResolvedSpellID = sid or resolvedSpellID

    local applied
    if durObj then
        applied = CDMIcons.ApplyDurationObjectCooldown(addonCD, durObj, true, mode == "aura")
    elseif hasNumericCooldown then
        if ns.CDMRenderers and ns.CDMRenderers.ApplyNumericCooldown then
            applied = ns.CDMRenderers.ApplyNumericCooldown(addonCD, resolvedStart, resolvedDuration, false)
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

    if mode == "aura" or mode == "charge" or mode == "cooldown" or mode == "item-cooldown" then
        icon._showingRealCooldownSwipe = true
        CDMIcons.ClearGCDSwipe(icon)
    elseif mode == "gcd-only" then
        icon._showingRealCooldownSwipe = nil
        CDMIcons.MarkGCDSwipe(icon)
    end
    ReapplySwipeStyle(addonCD, icon)

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
CDMIcons.UnmirrorBlizzCooldown = UnmirrorBlizzCooldown
CDMIcons.ApplyResolvedCooldown = function(icon) return ApplyResolvedCooldown(icon) end
CDMIcons.ReapplySwipeStyle = function(cd, icon) return ReapplySwipeStyle(cd, icon) end

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
    -- Only the nil check is taint-safe. Strings flowing through here can be
    -- secret values from Blizzard CDM children (now active for the mirror's
    -- data feed), so a Lua-side `text ~= ""` compare taints. Treat any non-
    -- nil value as "has display" — downstream SetText accepts secret
    -- strings and renders empty values as no-op visually, so the
    -- show-vs-hide decision is correct in practice.
    return text ~= nil
end
CDMIcons.HookTextHasDisplay = HookTextHasDisplay  -- consumed by cdm_icon_factory.lua via _FinalizeImports

function CDMIcons.ValueIsPresent(value)
    return value ~= nil
end

function CDMIcons.ValueIsMissing(value)
    return not CDMIcons.ValueIsPresent(value)
end

local function GetDisplayableAuraApplicationsFromData(auraData)
    if not auraData then return nil end

    local apps = auraData.applications
    if apps == nil then return nil end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(apps) then
        return nil
    end
    if issecretvalue and issecretvalue(apps) then
        return nil
    end

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

local GetTrackerSettings

local function ClearIconStackText(icon)
    if not icon or not icon.StackText then return end
    icon.StackText.SetText(icon.StackText, "")
    icon.StackText.Hide(icon.StackText)
    icon._stackTextSource = nil
end
CDMIcons.ClearIconStackText = ClearIconStackText

-- Per-icon aura-applications fallback for cooldown-container icons.
-- Returns the raw applications value (may be secret in combat) for
-- C-side forwarding, or nil when no eligible aura is present.
--
-- Resolution order:
--  1. Direct lookup with the supplied spellID.
--  2. _abilityToAuraSpellID mapping (buff-category base → linked aura).
--  3. Spell-name fallback via C_UnitAuras.GetAuraDataBySpellName. Required
--     for entries added via the cooldown-category CDM picker (e.g. Mana
--     Tea added on Utility) — those carry the cast/cooldown spellID,
--     which doesn't match the actual buff aura ID, and the ability→aura
--     map is built only from buff-category cdInfo so the cooldown cast ID
--     isn't a key. Spell names are stable across ID variants.
--  4. Full CDM aura resolver fallback for buff/debuff-category mappings
--     and live Blizzard cooldown-viewer children.
--
-- spellName is the entry's pre-resolved name (set OOC at icon build
-- time). Passing it in avoids a per-tick C_Spell.GetSpellInfo call,
-- which can return secret-value name fields in combat — that breaks
-- the GetAuraDataBySpellName fallback exactly when stacks are most
-- likely to flip (mid-fight). Falls back to GetSpellInfo OOC only.

-- Persistent spell-name cache. C_Spell.GetSpellInfo can return a secret
-- value in info.name during combat, and a secret name silently breaks
-- GetAuraDataBySpellName downstream. Resolve OOC and cache per-spell so
-- subsequent in-combat rebuilds (BuildSpellEntryFromCustom fired by the
-- filter-flip relayout when hideNonUsable's verdict crosses 0/1 stacks)
-- read a clean string instead of a fresh, possibly-secret one. Cache
-- entries are stable across the session — spell names don't mutate.
local _spellNameCache = {}
CDMIcons._recentCastSpellByName = CDMIcons._recentCastSpellByName or {}
CDMIcons._recentCastAliasTTL = 600

-- Returns ONLY clean (non-secret) names so the cache value is safe to
-- compare against "" downstream (cdm_bars.lua, cdm_effects.lua, profile_io.lua
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

function CDMIcons.GetSpellNameForAlias(spellID)
    if not spellID then return nil end
    local cached = GetCachedSpellName(spellID)
    if cached then return cached end
    if Sources and Sources.QuerySpellName then
        local name = Sources.QuerySpellName(spellID)
        if name then return name end
    end
    if not (Sources and Sources.QuerySpellInfo) then return nil end
    local info = Sources.QuerySpellInfo(spellID)
    if info and info.name then
        return info.name
    end
    return nil
end

function CDMIcons.NormalizeSpellAliasName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return string.lower(name)
end

function CDMIcons.RecordRecentPlayerSpellCast(spellID)
    if not spellID then return end
    local spellName = CDMIcons.GetSpellNameForAlias(spellID)
    local key = CDMIcons.NormalizeSpellAliasName(spellName)
    if not key then return end
    CDMIcons._recentCastSpellByName[key] = {
        spellID = spellID,
        time = GetTime(),
    }
    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugSpellEvent then
        CDMIcons.DebugSpellEvent(spellID, spellName, "spellcast", "recordedAlias=", key)
    end
end

function CDMIcons.GetRecentCastAliasForEntry(entry)
    if not entry then return nil end
    local key = CDMIcons.NormalizeSpellAliasName(entry.name)
    if not key then
        key = CDMIcons.NormalizeSpellAliasName(CDMIcons.GetSpellNameForAlias(entry.spellID or entry.overrideSpellID or entry.id))
    end
    local rec = key and CDMIcons._recentCastSpellByName[key]
    if not rec then return nil end
    if (GetTime() - (rec.time or 0)) > CDMIcons._recentCastAliasTTL then
        CDMIcons._recentCastSpellByName[key] = nil
        return nil
    end
    return rec.spellID
end

-- Shared with cdm_spelldata.lua's ResolveOwnedEntry so harvested spell
-- entries (essential/utility/buff ownedSpells) and Composer-built custom
-- entries draw from the same cache.
ns._GetCachedSpellName = GetCachedSpellName

function CDMIcons._GetAuraApplicationsFromData(auraData, unit, source)
    if not auraData then return nil end

    local apps = GetDisplayableAuraApplicationsFromData(auraData)
    if CDMIcons.ValueIsPresent(apps) then
        return apps, source
    end

    local auraInstanceID = GetAuraDataInstanceID(auraData)
    if auraInstanceID and Sources and Sources.QueryAuraApplicationDisplayCount then
        local stacks = Sources.QueryAuraApplicationDisplayCount(unit or "player", auraInstanceID, 2, 99)
        if stacks ~= nil then
            return stacks, "display-count"
        end
    end

    return nil
end

function CDMIcons._TryAuraApplicationsBySpellID(auraID, source)
    if auraID == nil or not Sources then return nil end

    local function queryPlayerAuraData(spellID)
        if not spellID then return nil end
        if Sources.QueryUnitAuraBySpellID then
            local auraData = Sources.QueryUnitAuraBySpellID("player", spellID)
            if auraData then return auraData end
        end
        if Sources.QueryPlayerAuraBySpellID then
            local auraData = Sources.QueryPlayerAuraBySpellID(spellID)
            if auraData then return auraData end
        end
        return nil
    end

    if Sources.QueryCooldownAuraBySpellID then
        local passiveAuraID = Sources.QueryCooldownAuraBySpellID(auraID)
        if passiveAuraID then
            local auraData = queryPlayerAuraData(passiveAuraID)
            if auraData then
                local apps, appSource = CDMIcons._GetAuraApplicationsFromData(
                    auraData, "player", (source or "spell") .. "-cooldown-aura")
                if CDMIcons.ValueIsPresent(apps) then
                    return apps, appSource
                end
            end
        end
    end

    local auraData = queryPlayerAuraData(auraID)
    if auraData then
        local apps, appSource = CDMIcons._GetAuraApplicationsFromData(
            auraData, "player", (source or "spell") .. "-player-spell")
        if CDMIcons.ValueIsPresent(apps) then
            return apps, appSource
        end
    end

    return nil
end

function CDMIcons._TryLinkedAuraApplications(linkedSpellIDs, entry, icon, seenIDs, source)
    if type(linkedSpellIDs) ~= "table" or not Helpers.CanAccessTable(linkedSpellIDs) then
        return nil
    end

    for _, linkedID in ipairs(linkedSpellIDs) do
        local queryID = linkedID
        local auraID = type(linkedID) == "number" and linkedID or nil

        if queryID and (not auraID or (auraID > 0 and not seenIDs[auraID])) then
            if auraID then
                seenIDs[auraID] = true
            end

            local apps, appSource = CDMIcons._TryAuraApplicationsBySpellID(queryID, source or "linked")
            if CDMIcons.ValueIsPresent(apps) then
                if _G.QUI_CDM_CHARGE_DEBUG then
                    ChargeDebug(entry and entry.name, "AURA linked stack",
                        "auraID=", auraID or "dynamic", "source=", appSource or "nil")
                end
                return apps, appSource
            end

            if auraID then
                apps, appSource = CDMIcons._ResolveAuraApplicationsForEntry(auraID, entry, icon)
                if CDMIcons.ValueIsPresent(apps) then
                    if _G.QUI_CDM_CHARGE_DEBUG then
                        ChargeDebug(entry and entry.name, "AURA linked resolve",
                            "auraID=", auraID, "source=", appSource or "nil")
                    end
                    return apps, appSource or (source or "linked")
                end
            end
        end
    end

    return nil
end

local function TryActionButtonSpellCount(spellID, seenIDs)
    if type(spellID) ~= "number" then return nil end
    if seenIDs[spellID] then return nil end
    seenIDs[spellID] = true

    local spellCount = QuerySpellCount and QuerySpellCount(spellID)
    if CDMIcons.ValueIsMissing(spellCount) then return nil end

    if (Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(spellCount))
        or (issecretvalue and issecretvalue(spellCount)) then
        return spellCount, "spell-cast-count"
    end

    if type(spellCount) ~= "number" then return nil end
    if spellCount <= 0 then return nil end

    local displayText = spellCount
    if C_StringUtil and C_StringUtil.TruncateWhenZero then
        displayText = C_StringUtil.TruncateWhenZero(spellCount)
    end
    if not HookTextHasDisplay(displayText) then
        return nil
    end
    return spellCount, "spell-cast-count"
end

function CDMIcons.GetSpellCountForEntry(spellID, entry, icon)
    local seenIDs = icon and icon._spellCountSeenIDs or {}
    if icon then icon._spellCountSeenIDs = seenIDs end
    wipe(seenIDs)

    local function tryID(id)
        local count, source = TryActionButtonSpellCount(id, seenIDs)
        if CDMIcons.ValueIsPresent(count) then return count, source end

        if type(id) == "number" then
            local overrideID = QueryOverrideSpell(id)
            count, source = TryActionButtonSpellCount(overrideID, seenIDs)
            if CDMIcons.ValueIsPresent(count) then return count, source end
        end
        return nil
    end

    local count, source = tryID(spellID)
    if CDMIcons.ValueIsPresent(count) then return count, source end

    if entry then
        count, source = tryID(entry.overrideSpellID)
        if CDMIcons.ValueIsPresent(count) then return count, source end
        count, source = tryID(entry.spellID)
        if CDMIcons.ValueIsPresent(count) then return count, source end
        count, source = tryID(entry.id)
        if CDMIcons.ValueIsPresent(count) then return count, source end
    end

    return nil
end

function CDMIcons._ResolveAuraApplicationsForEntry(spellID, entry, icon)
    if not (spellID and entry and ns.CDMSpellData and ns.CDMSpellData.ResolveAuraState) then
        return nil
    end

    local p = icon and icon._stackAuraParams or {}
    if icon then icon._stackAuraParams = p end
    p.spellID = spellID
    p.entrySpellID = entry.spellID
    p.entryID = entry.id
    p.entryName = entry.name
    p.entryKind = entry.kind
    p.entryType = entry.type
    p.entryIsAura = IsAuraEntry(entry)
    p.entryTexture = GetEntryTexture and GetEntryTexture(entry) or nil
    p.viewerType = entry.viewerType
    p.totemSlot = IsTotemSlotEntry(entry) and entry._totemSlot or nil
    p.disableLooseVisibilityFallback = true

    local r = ns.CDMSpellData:ResolveAuraState(p)
    if not r then
        return nil
    end

    if r.isActive and not r.isTotemInstance then
        local count = r.count
        if count and count.shown == true and CDMIcons.ValueIsPresent(count.sinkText) then
            return count.sinkText, count.source
        end
        if count and count.shown == true and CDMIcons.ValueIsPresent(count.value) then
            return count.value, count.source
        end
        return CDMIcons._GetAuraApplicationsFromData(r.auraData, r.auraUnit, "resolved-data")
    end

    return nil
end

GetAuraApplicationsForSpell = function(spellID, entryOrName, icon)
    local entry = type(entryOrName) == "table" and entryOrName or nil
    local spellName = entry and entry.name or entryOrName
    if CDMIcons.ValueIsMissing(spellID) or not Sources then
        return nil
    end

    if entry and not IsAuraEntry(entry) then
        local spellCount, countSource = CDMIcons.GetSpellCountForEntry(spellID, entry, icon)
        if CDMIcons.ValueIsPresent(spellCount) then
            return spellCount, countSource
        end
    end

    local seenIDs = icon and icon._stackAuraSeenIDs or {}
    if icon then icon._stackAuraSeenIDs = seenIDs end
    wipe(seenIDs)
    seenIDs[spellID] = true

    local directApps, directSource = CDMIcons._TryAuraApplicationsBySpellID(spellID, "spell")
    if CDMIcons.ValueIsPresent(directApps) then
        return directApps, directSource
    end

    local auraID = spellID
    if ns.CDMSpellData and ns.CDMSpellData._abilityToAuraSpellID then
        local mapped = ns.CDMSpellData._abilityToAuraSpellID[auraID]
        if mapped then auraID = mapped end
    end
    if auraID and not seenIDs[auraID] then
        seenIDs[auraID] = true
        local mappedApps, mappedSource = CDMIcons._TryAuraApplicationsBySpellID(auraID, "mapped")
        if CDMIcons.ValueIsPresent(mappedApps) then
            return mappedApps, mappedSource
        end
    end

    if not (entry and (entry.viewerType == "buff" or entry.viewerType == "trackedBar")) then
        local linkedApps, linkedSource = CDMIcons._TryLinkedAuraApplications(
            entry and entry.linkedSpellIDs, entry, icon, seenIDs, "entry-linked")
        if CDMIcons.ValueIsPresent(linkedApps) then return linkedApps, linkedSource end
    end

    if not Sources.QueryAuraDataBySpellName then
        return CDMIcons._ResolveAuraApplicationsForEntry(spellID, entry, icon)
    end

    -- Resolve a name and forward it transiently. Caller-supplied spellName
    -- and GetCachedSpellName are both clean strings (or nil), so the `==""`
    -- comparison below is safe. Only the final fresh-from-GetSpellInfo
    -- branch can produce a secret value, and that secret is passed straight
    -- through to GetAuraDataBySpellName via pcall — never compared, never
    -- stored. C-side handles secrets natively.
    local nameToUse = spellName
    if nameToUse == nil or nameToUse == "" then
        nameToUse = GetCachedSpellName(spellID)
    end
    if (nameToUse == nil or nameToUse == "") and Sources.QuerySpellInfo then
        local info = Sources.QuerySpellInfo(spellID)
        if info then
            nameToUse = info.name  -- may be secret in combat — forwarded only
        end
    end
    if CDMIcons.ValueIsPresent(nameToUse) then
        local nad = Sources.QueryAuraDataBySpellName("player", nameToUse, "HELPFUL")
        if nad then
            local apps, source = CDMIcons._GetAuraApplicationsFromData(nad, "player", "name-player")
            if CDMIcons.ValueIsPresent(apps) then return apps, source end
        end
    end

    local resolvedApps, resolvedSource = CDMIcons._ResolveAuraApplicationsForEntry(spellID, entry, icon)
    if CDMIcons.ValueIsPresent(resolvedApps) then
        return resolvedApps, resolvedSource
    end

    return nil
end
CDMIcons.GetAuraApplicationsForSpell = GetAuraApplicationsForSpell

local function ApplyAuraCountText(icon, count, showZero, preserveWhenMissing)
    if not icon or not icon.StackText then return end

    if not count or count.shown ~= true then
        if not preserveWhenMissing then
            ClearIconStackText(icon)
        end
        return
    end

    local entry = icon._spellEntry
    local stackSettings = CDMIcons.GetTrackerSettings
        and CDMIcons.GetTrackerSettings(entry and entry.viewerType)
        or nil
    if CDMIcons.ShouldHideIconStackText
       and CDMIcons.ShouldHideIconStackText(icon, stackSettings) then
        ClearIconStackText(icon)
        return
    end

    local stackValue = count.sinkText
    if stackValue == nil then
        stackValue = count.value
    end

    if CDMIcons.ValueIsMissing(stackValue) then
        if not preserveWhenMissing then
            ClearIconStackText(icon)
        end
        return
    end

    if count.sinkText ~= nil or showZero then
        icon.StackText.SetText(icon.StackText, stackValue)
        icon.StackText.Show(icon.StackText)
        icon._stackTextSource = count.source or "Applications"
        return
    end

    local displayText = stackValue
    if type(stackValue) == "number" and C_StringUtil and C_StringUtil.TruncateWhenZero then
        displayText = C_StringUtil.TruncateWhenZero(stackValue)
    end

    if HookTextHasDisplay(displayText) then
        icon.StackText.SetText(icon.StackText, displayText)
        icon.StackText.Show(icon.StackText)
        icon._stackTextSource = count.source or "Applications"
    else
        ClearIconStackText(icon)
    end
end
CDMIcons.ApplyAuraCountText = ApplyAuraCountText

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
CDMIcons.ClearClickButtonAttributes = ClearClickButtonAttributes

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
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(entry.id)
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
local ok = true; local atlas = region.GetAtlas(region)
    return ok and atlas and BLIZZ_ICON_CHROME_ATLASES[atlas] or false
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
local ok = true; local kind = target.GetObjectType(target)
        if ok then objType = kind end
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
local ok = true; local regions = { target:GetRegions() }
        if regions then
            for _, region in ipairs(regions) do
                if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                    ApplyTexCoordToTexture(region, left, right, top, bottom)
                end
            end
        end
    end

    if target.GetChildren then
local ok = true; local children = { target:GetChildren() }
        if children then
            for _, child in ipairs(children) do
                local childType
                if child and child.GetObjectType then
local okType = true; local kind = child.GetObjectType(child)
                    if okType then childType = kind end
                end
                if childType ~= "Cooldown" then
                    ApplyTexCoordToTarget(child, left, right, top, bottom, visited)
                end
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
local ok = true; local regions = { cd:GetRegions() }
            if regions then
                for _, region in ipairs(regions) do
                    styleDurationFontString(region)
                end
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
local ok = true; local regions = { cd:GetRegions() }
            if regions then
                for _, region in ipairs(regions) do
                    hideDurationFontString(region)
                end
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

        -- showDurationText: per-spell duration text visibility override
        if spellOvr.showDurationText == false then
            local function hideDurationForCooldown(cd)
                if not cd then return end
                if cd.SetHideCountdownNumbers then
                    cd.SetHideCountdownNumbers(cd, true)
                end
local ok = true; local regions = { cd:GetRegions() }
                if regions then
                    for _, region in ipairs(regions) do
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            region:Hide()
                        end
                    end
                end
            end
            hideDurationForCooldown(icon.Cooldown)
            icon.DurationText:Hide()
        elseif spellOvr.showDurationText == true then
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
    local db = GetDB()
    if not db or not viewerType then return nil end
    -- Built-in containers (essential, utility, buff, trackedBar) live at the
    -- top level; custom containers (user-created, legacy-migrated customBar)
    -- live under db.containers. Check both so range/usability tints apply
    -- uniformly across all container types.
    if db[viewerType] then return db[viewerType] end
    return db.containers and db.containers[viewerType] or nil
end
CDMIcons.GetTrackerSettings = GetTrackerSettings

function CDMIcons.IsCustomBarContainer(containerDB)
    return type(containerDB) == "table" and containerDB.containerType == "customBar"
end

function CDMIcons.NormalizeCustomBarVisibilityFlags(containerDB)
    if not CDMIcons.IsCustomBarContainer(containerDB) then return "always" end

    if containerDB.desaturateOnCooldown == nil then
        containerDB.desaturateOnCooldown = true
    end

    local mode = "always"
    if containerDB.showOnlyOnCooldown then
        mode = "onCooldown"
        containerDB.showOnlyWhenActive = false
        containerDB.showOnlyWhenOffCooldown = false
    elseif containerDB.showOnlyWhenActive then
        mode = "active"
        containerDB.showOnlyWhenOffCooldown = false
    elseif containerDB.showOnlyWhenOffCooldown then
        mode = "offCooldown"
    end

    containerDB.visibilityMode = mode

    if mode ~= "onCooldown" then
        containerDB.noDesaturateWithCharges = false
    end

    if containerDB.dynamicLayout == nil then
        containerDB.dynamicLayout = false
    end
    if containerDB.dynamicLayout and containerDB.clickableIcons then
        containerDB.clickableIcons = false
    end

    containerDB.tooltipContext = containerDB.tooltipContext or "customTrackers"
    containerDB.keybindContext = containerDB.keybindContext or "customTrackers"

    return mode
end

function CDMIcons.GetCustomBarVisibilityMode(containerDB)
    if not CDMIcons.IsCustomBarContainer(containerDB) then return "always" end
    return CDMIcons.NormalizeCustomBarVisibilityFlags(containerDB)
end

function CDMIcons.GetSpellCastInfo(spellID)
    if not spellID or not UnitCastingInfo then return false end
    local _, _, _, startMS, endMS, _, _, _, castSpellID = UnitCastingInfo("player")
    if castSpellID and castSpellID == spellID and startMS and endMS then
        return true, startMS / 1000, (endMS - startMS) / 1000, "cast"
    end
    return false
end

function CDMIcons.GetSpellChannelInfo(spellID)
    if not spellID or not UnitChannelInfo then return false end
    local _, _, _, startMS, endMS, _, _, channelSpellID = UnitChannelInfo("player")
    if channelSpellID and channelSpellID == spellID and startMS and endMS then
        return true, startMS / 1000, (endMS - startMS) / 1000, "channel"
    end
    return false
end

function CDMIcons.GetSpellBuffInfo(spellID, icon, entry)
    if not spellID then return false end

    local scanner = QUI and QUI.SpellScanner
    if scanner and scanner.IsSpellActive then
        local active, expiration, duration = scanner.IsSpellActive(spellID)
        if active then
            if IsSafeNumeric(expiration) and IsSafeNumeric(duration) then
                return true, expiration - duration, duration, "buff"
            end
            return true, nil, nil, "buff"
        end
        if InCombatLockdown() then
            return false
        end
    elseif InCombatLockdown() then
        return false
    end

    if Sources and Sources.QueryPlayerAuraBySpellID then
        local auraData = Sources.QueryPlayerAuraBySpellID(spellID)
        if auraData then
            local expiration = auraData.expirationTime
            local duration = auraData.duration
            if IsSafeNumeric(expiration) and IsSafeNumeric(duration) then
                return true, expiration - duration, duration, "buff"
            end
            return true, nil, nil, "buff"
        end
    end

    if icon and icon._auraActive then
        return true, nil, nil, "buff"
    end

    return false
end

function CDMIcons.ResolveItemActiveState(itemID, icon, entry)
    if not itemID or not (Sources and Sources.QueryItemSpell) then return false end
    local _, itemSpellID = Sources.QueryItemSpell(itemID)
    if itemSpellID then
        return CDMIcons.ResolveSpellActiveState(itemSpellID, icon, entry)
    end
    return false
end

function CDMIcons.ResolveEntryRuntimeSpellID(icon, entry)
    return (icon and icon._runtimeSpellID)
        or (entry and (entry.spellID or entry.overrideSpellID or entry.id))
end

function CDMIcons.CooldownHasVisualPriority(icon, entry, containerDB, now)
    if not icon or not entry then return false end
    if icon._cdDesaturated or icon._hasCooldownActive or icon._showingRealCooldownSwipe then
        return true
    end

    local state = CDMIcons.ResolveCooldownActivityState(icon, entry, containerDB, now or GetTime())
    return state and state.isOnCooldown == true
end

function CDMIcons.ResolveCustomBarActiveState(entry, icon, now)
    local containerDB = GetTrackerSettings(entry and entry.viewerType)
    if not CDMIcons.IsCustomBarContainer(containerDB) then
        return icon and icon._auraActive or false
    end
    if containerDB.showActiveState == false then
        return false
    end

    if entry.type == "macro" then
        local resolvedID, resolvedType = ResolveMacro(entry)
        if resolvedID then
            if resolvedType == "item" then
                return CDMIcons.ResolveItemActiveState(resolvedID, icon, entry)
            end
            return CDMIcons.ResolveSpellActiveState(resolvedID, icon, entry)
        end
        return false
    end

    if CDMIcons.IsItemLikeEntry(entry) then
        local itemID = CDMIcons.ResolveEntryItemID(entry)
        if itemID then
            return CDMIcons.ResolveItemActiveState(itemID, icon, entry)
        end
        return false
    end

    local spellID = icon and icon._runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id
    return CDMIcons.ResolveSpellActiveState(spellID, icon, entry)
end

function CDMIcons.ResolveCustomBarCooldownState(entry, icon, containerDB, now)
    return CDMIcons.ResolveCooldownActivityState(icon, entry, containerDB, now)
end

function CDMIcons.ResolveCustomBarUsability(entry, containerDB, cooldownState)
    if not entry then return true end

    if entry.type == "macro" then
        local resolvedID, resolvedType = ResolveMacro(entry)
        if not resolvedID then return true end
        if resolvedType == "item" then
            return CDMIcons.ResolveCustomBarUsability({ type = "item", id = resolvedID }, containerDB, cooldownState)
        end
        return CDMIcons.ResolveCustomBarUsability({ type = "spell", id = resolvedID, spellID = resolvedID }, containerDB, cooldownState)
    end

    if entry.type == "item" then
        if Sources and Sources.QueryItemInfoInstant and Enum and Enum.ItemClass then
            local instantItemID, instantItemType, instantItemSubType, instantEquipLoc, instantIcon, classID =
                Sources.QueryItemInfoInstant(entry.id)
            if instantItemID and (classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon) then
                local equipped = Sources.QueryIsEquippedItem and Sources.QueryIsEquippedItem(entry.id)
                if equipped ~= nil then
                    return equipped == true
                end
            end
        end
        if Sources and Sources.QueryItemCount then
            local count = Sources.QueryItemCount(entry.id, false, containerDB and containerDB.showItemCharges == true, true)
            return count and count > 0
        end
        return true
    elseif entry.type == "trinket" or entry.type == "slot" then
        local equippedItemID = Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID("player", entry.id)
        if not equippedItemID then return false end
        -- Trinket slots (13/14) track the slot rather than a specific item, so
        -- a passive stat-stick with no on-use would otherwise report usable
        -- and sit visible forever under hideNonUsable. Mirrors the legacy-
        -- container check in ComputeFilterHides so custom containers honor
        -- hideNonUsable for passive trinkets too.
        if entry.id == 13 or entry.id == 14 then
            local spellName = Sources and Sources.QueryItemSpell and Sources.QueryItemSpell(equippedItemID)
            if not spellName then return false end
        end
        return true
    end

    local sid = entry.spellID or entry.overrideSpellID or entry.id
    if sid then
        local spellData = ns.CDMSpellData
        if spellData and type(spellData.IsSpellKnown) == "function"
           and not spellData:IsSpellKnown(sid) then
            return false
        end
        -- C_Spell.IsSpellUsable can report false while a known spell is on
        -- cooldown. For custom bars that combine Hide Non-Usable with Show
        -- Only On Cooldown, treating that as unusable hides the exact spells
        -- the user wants to see. Unknown spells were rejected above; active
        -- cooldown/recharge means the entry is valid and should pass this
        -- filter.
        if cooldownState and (cooldownState.isOnCooldown or cooldownState.rechargeActive) then
            return true
        end
        if Sources and Sources.QuerySpellUsable then
            local usable = Helpers.SafeValue(Sources.QuerySpellUsable(sid), nil)
            if usable == false then return false end
        end
    end

    return true
end

function CDMIcons.ComputeCustomBarVisibility(icon, entry, containerDB, now)
    local cooldown = CDMIcons.ResolveCustomBarCooldownState(entry, icon, containerDB, now)
    local isActive = (icon and icon._customBarActive) or (icon and icon._auraActive) or false
    local usable = CDMIcons.ResolveCustomBarUsability(entry, containerDB, cooldown)
    local baseVisible = usable or not (containerDB and containerDB.hideNonUsable)
    local mode = CDMIcons.GetCustomBarVisibilityMode(containerDB)
    local layoutVisible = baseVisible

    if layoutVisible then
        if mode == "onCooldown" then
            layoutVisible = cooldown.isOnCooldown or cooldown.rechargeActive
        elseif mode == "active" then
            layoutVisible = isActive
        elseif mode == "offCooldown" then
            layoutVisible = (not cooldown.isOnCooldown)
                and (not isActive or cooldown.hasChargesRemaining)
        end
    end

    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    local combatVisible = not (containerDB and containerDB.showOnlyInCombat) or inCombat

    if _G.QUI_CDM_ICON_DEBUG and CDMIcons.DebugIconEvent then
        CDMIcons.DebugIconEvent(icon, "visibility",
            "mode=", mode,
            "layout=", tostring((layoutVisible and true) or false),
            "render=", tostring(((layoutVisible and combatVisible) and true) or false),
            "base=", tostring((baseVisible and true) or false),
            "usable=", tostring((usable and true) or false),
            "onCD=", tostring((cooldown.isOnCooldown and true) or false),
            "recharge=", tostring((cooldown.rechargeActive and true) or false),
            "active=", tostring((isActive and true) or false),
            "gcdOnly=", tostring(cooldown.gcdOnly and true or false),
            "hideNonUsable=", tostring(containerDB and containerDB.hideNonUsable),
            "showOnlyOnCooldown=", tostring(containerDB and containerDB.showOnlyOnCooldown))
    end
    return {
        baseVisible = baseVisible,
        layoutVisible = layoutVisible and true or false,
        renderVisible = layoutVisible and combatVisible and true or false,
        isActive = isActive and true or false,
        isUsable = usable and true or false,
        isOnCooldown = cooldown.isOnCooldown and true or false,
        rechargeActive = cooldown.rechargeActive and true or false,
        hasChargesRemaining = cooldown.hasChargesRemaining and true or false,
        visibilityMode = mode,
    }
end

function CDMIcons.StartCustomBarActiveGlow(icon, containerDB)
    if not icon or not CDMIcons._LCG or not containerDB or containerDB.activeGlowEnabled == false then return end
    if icon._customBarActiveGlowShown or icon._customBarActiveGlowPending then return end
    local width, height = icon:GetSize()
    if not width or not height or width < 10 or height < 10 then return end

    local glowType = containerDB.activeGlowType or "Pixel Glow"
    local color = containerDB.activeGlowColor or {1, 0.85, 0.3, 1}
    local lines = containerDB.activeGlowLines or 8
    local frequency = containerDB.activeGlowFrequency or 0.25
    local thickness = containerDB.activeGlowThickness or 2
    local scale = containerDB.activeGlowScale or 1.0

    if glowType == "Proc Glow" then
        local duration = 1.0 / ((frequency or 0.25) * 4)
        duration = math.max(0.5, math.min(2.0, duration))
        if icon.Border and icon.Border.IsShown and icon.Border:IsShown() then
            icon._customBarBorderWasShown = true
            icon.Border:Hide()
        end
        if icon.Icon and icon.CreateMaskTexture then
            if not icon._customBarProcGlowMask then
                icon._customBarProcGlowMask = icon:CreateMaskTexture()
                icon._customBarProcGlowMask:SetTexture("Interface\\AddOns\\QUI\\assets\\iconskin\\ProcGlowMask")
                icon._customBarProcGlowMask:SetAllPoints(icon.Icon)
            end
            icon.Icon.AddMaskTexture(icon.Icon, icon._customBarProcGlowMask)
        end
        icon._customBarActiveGlowPending = true
        C_Timer.After(0, function()
            icon._customBarActiveGlowPending = nil
            if not icon or not icon:IsShown() or icon._customBarActiveGlowShown or not icon._customBarActive then return end
            CDMIcons._LCG.ProcGlow_Start(icon, {
                color = color,
                duration = duration,
                startAnim = true,
                key = "_QUIActiveGlow",
            })
            icon._customBarActiveGlowShown = true
            icon._customBarActiveGlowType = glowType
        end)
    elseif glowType == "Autocast Shine" then
        CDMIcons._LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, "_QUIActiveGlow")
        icon._customBarActiveGlowShown = true
        icon._customBarActiveGlowType = glowType
    else
        CDMIcons._LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, "_QUIActiveGlow")
        icon._customBarActiveGlowShown = true
        icon._customBarActiveGlowType = "Pixel Glow"
    end
end

function CDMIcons.StopCustomBarActiveGlow(icon)
    if not icon or not CDMIcons._LCG then return end
    icon._customBarActiveGlowPending = nil
    local glowWasShown = icon._customBarActiveGlowShown

    local glowType = icon._customBarActiveGlowType or "Pixel Glow"
    if glowWasShown and glowType == "Proc Glow" then
        CDMIcons._LCG.ProcGlow_Stop(icon, "_QUIActiveGlow")
    elseif glowWasShown and glowType == "Autocast Shine" then
        CDMIcons._LCG.AutoCastGlow_Stop(icon, "_QUIActiveGlow")
    elseif glowWasShown then
        CDMIcons._LCG.PixelGlow_Stop(icon, "_QUIActiveGlow")
    end
    if icon.Icon and icon._customBarProcGlowMask then
        icon.Icon.RemoveMaskTexture(icon.Icon, icon._customBarProcGlowMask)
    end
    if icon._customBarBorderWasShown and icon.Border then
        icon.Border:Show()
    end
    icon._customBarBorderWasShown = nil
    icon._customBarActiveGlowShown = nil
    icon._customBarActiveGlowType = nil
end

function CDMIcons.ApplyCustomBarSwipeStyle(icon, containerDB, cooldownState)
    if not icon or not icon.Cooldown or not icon._spellEntry then return end
    local entry = icon._spellEntry
    containerDB = containerDB or GetTrackerSettings(entry.viewerType)
    if not CDMIcons.IsCustomBarContainer(containerDB) then return end

    cooldownState = cooldownState or CDMIcons.ResolveCustomBarCooldownState(entry, icon, containerDB, GetTime())
    local showRecharge = cooldownState and cooldownState.rechargeActive and containerDB.showRechargeSwipe == true
    if cooldownState and (cooldownState.hasCharges or cooldownState.rechargeActive) then
        icon.Cooldown:SetDrawSwipe(showRecharge)
        icon.Cooldown:SetDrawEdge(false)
        if showRecharge then
            icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
            icon.Cooldown:SetSwipeColor(0, 0, 0, 0.6)
        else
            icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
        end
    elseif not icon._customBarActive then
        icon.Cooldown:SetDrawSwipe(false)
        icon.Cooldown:SetDrawEdge(false)
        icon.Cooldown:SetSwipeColor(0, 0, 0, 0)
    end
end

function CDMIcons.ApplyCustomBarActiveState(icon, entry, containerDB)
    if not icon or not entry or not CDMIcons.IsCustomBarContainer(containerDB) then return end

    local wasActive = icon._customBarActive
    local wasActiveType = icon._customBarActiveType
    local active, startTime, duration, activeType = CDMIcons.ResolveCustomBarActiveState(entry, icon, GetTime())
    icon._customBarActive = active and true or false
    icon._customBarActiveType = activeType
    icon._customBarActiveStart = startTime
    icon._customBarActiveDuration = duration

    if icon.Cooldown
       and (wasActive ~= icon._customBarActive or wasActiveType ~= icon._customBarActiveType) then
        ReapplySwipeStyle(icon.Cooldown, icon)
    end

    if CDMIcons.ApplyCustomBarSwipeStyle then
        CDMIcons.ApplyCustomBarSwipeStyle(icon, containerDB)
    end
end

function CDMIcons.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
    if visibility and visibility.renderVisible and visibility.isActive
       and visibility.visibilityMode ~= "onCooldown" then
        CDMIcons.StartCustomBarActiveGlow(icon, containerDB)
    else
        CDMIcons.StopCustomBarActiveGlow(icon)
    end
end

function CDMIcons.ShouldHideIconStackText(icon, containerDB)
    local row = icon and icon._rowConfig
    if row and row.hideStackText == true then return true end
    return containerDB and containerDB.hideStackText == true
end

-- CDMIcons.DebugStackText is rebound by the load-on-demand debug addon.

function CDMIcons.ShowIconStackText(icon, value, containerDB, reason)
    if not icon or not icon.StackText then return end
    if CDMIcons.ShouldHideIconStackText(icon, containerDB) then
        CDMIcons.DebugStackText(icon, "hide", value, reason or "setting-hide-stack-text")
        icon.StackText.SetText(icon.StackText, "")
        icon.StackText.Hide(icon.StackText)
        return
    end
    local setErr
    local setOk
setOk = true; setErr = icon.StackText.SetText(icon.StackText, value)
    if not setOk and icon.StackText.SetFormattedText then
setOk = true; setErr = icon.StackText.SetFormattedText(icon.StackText, "%s", value)
    end
    local showOk = false
    local showErr
    if setOk then
showOk = true; showErr = icon.StackText.Show(icon.StackText)
    end
    if _G.QUI_CDM_CHARGE_DEBUG then
        CDMIcons.DebugStackText(icon, setOk and "show" or "show-failed", value, reason)
        ChargeDebug(icon._spellEntry and icon._spellEntry.name,
            "STACKTEXT apply", "reason=", reason or "nil",
            "setOk=", tostring(setOk), "setErr=", tostring(setErr),
            "showOk=", tostring(showOk), "showErr=", tostring(showErr))
    end
end

function CDMIcons.HideIconStackText(icon, reason)
    if not icon or not icon.StackText then return end
    CDMIcons.DebugStackText(icon, "hide", nil, reason)
    icon.StackText.SetText(icon.StackText, "")
    icon.StackText.Hide(icon.StackText)
end

-- _hoistedNcdm is set once per UpdateAllCooldowns batch (avoids 4 table
-- hops per icon).  Local to file scope so UpdateIconCooldown can read it.
local _hoistedNcdm = nil
CDMIcons._hoistedNcdm = nil   -- kept in sync at every write site below
-- _batchTime is set once per UpdateAllCooldowns batch so per-icon code
-- can read GetTime() without crossing the C boundary for every icon.
local _batchTime = 0
CDMIcons._batchTime = 0       -- kept in sync at every write site below
-- _showGCDSwipe is hoisted once per batch from swipe module settings.
-- When true, GCD-only cooldowns are allowed through to the CooldownFrame
-- instead of being cleared, so the GCD swipe animation can render.
local _showGCDSwipe = false
-- _showBuffSwipe is hoisted once per batch from swipe module settings.
-- _showCooldownIconAuraPhase controls whether cooldown-kind icons can enter
-- aura phase before charge/cooldown phase.
local _showBuffSwipe = true
local _showCooldownIconAuraPhase = true

CDMIcons._trustIsOnGCDForBatch = false
CDMIcons._pendingTrustIsOnGCD = false

function CDMIcons.RefreshSwipeBatchSettings()
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

function CDMIcons.ShouldSkipAuraPhaseForCooldownIcon(icon, entry)
    if not entry then return false end
    if IsAuraEntry(entry) then return false end
    return _showCooldownIconAuraPhase == false
end

function CDMIcons.ShouldUseBuffSwipeForIcon(icon, entry)
    if not entry then return false end
    if not _showBuffSwipe then return false end
    if CDMIcons.ShouldSkipAuraPhaseForCooldownIcon(icon, entry) then
        return false
    end
    local settings = ResolveTrackerSettingsNow(entry and entry.viewerType)
    if settings and settings.showOnlyOnCooldown == true then
        return false
    end
    if CDMIcons.IsCustomBarContainer(settings) then
        if settings.showActiveState == false then
            return false
        end
    end
    return true
end

---------------------------------------------------------------------------
-- ICON POOL MANAGEMENT
---------------------------------------------------------------------------
local function CreateIconPool()
    return {}
end

function CDMIcons:GetIconPool(viewerType)
    return iconPools[viewerType] or {}
end

function CDMIcons:ForEachIcon(callback)
    if not callback then return end
    for viewerType, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            callback(icon, viewerType)
        end
    end
end

function CDMIcons.GetMirrorIconSet(category, cooldownID, create)
    if not (category and cooldownID) then return nil end
    local byCategory = CDMIcons._mirrorIconsByCategory[category]
    if not byCategory then
        if not create then return nil end
        byCategory = {}
        CDMIcons._mirrorIconsByCategory[category] = byCategory
    end

    local iconSet = byCategory[cooldownID]
    if not iconSet then
        if not create then return nil end
        iconSet = setmetatable({}, { __mode = "k" })
        byCategory[cooldownID] = iconSet
    end
    return iconSet
end

function CDMIcons.UnregisterBlizzMirrorIcon(icon)
    if not icon then return end
    local category = icon._blizzMirrorIndexCategory
    local cooldownID = icon._blizzMirrorIndexCooldownID
    if category and cooldownID then
        local iconSet = CDMIcons.GetMirrorIconSet(category, cooldownID, false)
        if iconSet then
            iconSet[icon] = nil
        end
    end
    icon._blizzMirrorIndexCategory = nil
    icon._blizzMirrorIndexCooldownID = nil
end

function CDMIcons.RegisterBlizzMirrorIcon(icon, cooldownID, category)
    if not (icon and cooldownID and category) then return end
    if icon._blizzMirrorIndexCooldownID ~= nil
        or icon._blizzMirrorIndexCategory ~= nil then
        CDMIcons.UnregisterBlizzMirrorIcon(icon)
    end

    local iconSet = CDMIcons.GetMirrorIconSet(category, cooldownID, true)
    iconSet[icon] = true
    icon._blizzMirrorIndexCategory = category
    icon._blizzMirrorIndexCooldownID = cooldownID
end

function CDMIcons.RebuildBlizzMirrorIconIndex()
    wipe(CDMIcons._mirrorIconsByCategory)
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon and icon._blizzMirrorCooldownID and icon._blizzMirrorCategory then
                CDMIcons.RegisterBlizzMirrorIcon(icon,
                    icon._blizzMirrorCooldownID,
                    icon._blizzMirrorCategory)
            end
        end
    end
end

--- Ensure an icon pool exists for the given container key (Phase G).
function CDMIcons:EnsurePool(viewerType)
    if not iconPools[viewerType] then
        iconPools[viewerType] = CreateIconPool()
    end
end

function CDMIcons:ClearPool(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        for _, icon in ipairs(pool) do
            self:ReleaseIcon(icon)
        end
        wipe(pool)
    else
        iconPools[viewerType] = CreateIconPool()
    end
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
        elseif viewerType == "buff" or viewerType == "trackedBar" then
            kind = "aura"
        else
            local CDMSpellData = ns.CDMSpellData
            kind = (CDMSpellData and CDMSpellData.ResolveEntryKind
                and CDMSpellData.ResolveEntryKind(entry, viewerType)) or "cooldown"
        end
    end
    local isAuraEntry = (kind == "aura")
    local spellEntry = {
        spellID = isSpellType and entry.id or nil,
        overrideSpellID = isSpellType and entry.id or nil,
        name = "",
        isAura = isAuraEntry or false,
        kind = kind,
        layoutIndex = 99000 + (idx or 0),
        viewerType = viewerType,
        type = entry.type,
        id = entry.id,
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
        local itemName = Sources and Sources.QueryItemNameByID and Sources.QueryItemNameByID(entry.id)
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
    end

    if viewerType == "essential" or viewerType == "utility" then
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

CDMIcons.BuildIconListSignature = BuildIconListSignature

local _customPositionedScratch = {}
local _customUnpositionedScratch = {}

---------------------------------------------------------------------------
-- BUILD ICONS: Create icons from harvested spell data + custom entries
---------------------------------------------------------------------------
function CDMIcons:BuildIcons(viewerType, container)
    if not container then return {} end

    local spellData = ns.CDMSpellData and ns.CDMSpellData:GetSpellList(viewerType) or {}
    local signature = BuildIconListSignature(viewerType, container, spellData)
    local pool = iconPools[viewerType]
    local reusePool = pool
        and container._lastBuildSignature == signature
        and container._lastBuildPool == pool
        and PoolMatchesContainer(pool, container)

    if not reusePool then
        -- Release old icons
        self:ClearPool(viewerType)

        pool = iconPools[viewerType]
        if not pool then
            pool = CreateIconPool()
            iconPools[viewerType] = pool
        end

        -- Create icons from harvested spell data
        for _, entry in ipairs(spellData) do
            local icon = self:AcquireIcon(container, entry)
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
                        if entry and entry.enabled ~= false then
                            local spellEntry = BuildSpellEntryFromCustom(entry, idx, viewerType)
                            if spellEntry then
                                local icon = self:AcquireIcon(container, spellEntry)
                                pool[#pool + 1] = icon
                            end
                        end
                    end
                end
            end
        end

        -- Merge custom entries (essential and utility only)
        if viewerType == "essential" or viewerType == "utility" then
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
                            pool[i] = self:AcquireIcon(container, entry)
                        end
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
            if CDMIcons.IsCustomBarContainer(containerDB) then
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
    -- come from UpdateIconCooldown/ResolveAuraState. Pre-marking them
    -- active here makes empty rows render as active-looking.
    for _, icon in ipairs(pool) do
        local entry = icon._spellEntry
        if entry and entry.viewerType == "buff" then
            icon._auraActive = false
            icon._auraUnit = nil
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

    if CDMIcons.IsCustomBarContainer(containerDB) then
        local visibility = CDMIcons.ComputeCustomBarVisibility(icon, entry, containerDB, GetTime())
        return not visibility.layoutVisible
    end

    local cooldownState = CDMIcons.ResolveCooldownActivityState(icon, entry, containerDB, GetTime())
    local effectiveOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

    if containerDB.showOnlyInCombat and not inCombat then
        return true
    end

    if containerDB.showOnlyOnCooldown then
        if not effectiveOnCD then return true end
    end

    if containerDB.showOnlyWhenOffCooldown and effectiveOnCD then
        return true
    end

    if containerDB.showOnlyWhenActive and not icon._auraActive then
        return true
    end

    if containerDB.hideNonUsable then
        if entry.type == "item" then
            local count = Sources and Sources.QueryItemCount and Sources.QueryItemCount(entry.id, false, false, nil)
            if (not count or count <= 0) then return true end
        elseif entry.type == "trinket" or entry.type == "slot" then
            local equippedItemID = Sources and Sources.QueryInventoryItemID and Sources.QueryInventoryItemID("player", entry.id)
            if not equippedItemID then return true end
            -- Trinket slots (13/14): also hide passive trinkets — those without
            -- an on-use spell — under hideNonUsable. The slot is tracked rather
            -- than a specific item, so a stat-stick equipped in slot 13 would
            -- otherwise sit visible forever with nothing to display.
            if entry.id == 13 or entry.id == 14 then
                local spellName = Sources and Sources.QueryItemSpell and Sources.QueryItemSpell(equippedItemID)
                if not spellName then return true end
            end
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
                if Sources and Sources.QuerySpellUsable then
                    local usable = Helpers.SafeValue(Sources.QuerySpellUsable(sid), nil)
                    if usable == false then return true end
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

-- Per-container dirty set. When the runtime visibility update detects that an
-- icon's filter verdict has flipped versus the last layout pass (e.g. mana-tea
-- becoming usable mid-combat with hideNonUsable enabled), it marks the
-- container here. After the per-icon loop in UpdateAllCooldowns /
-- UpdateCooldownOnly we drain the set and call LayoutContainer for each entry
-- so the bar collapses or expands around the slot. With clickableIcons = false,
-- ShouldDeferContainerLayoutInCombat now permits the relayout to run in
-- combat instead of waiting for PLAYER_REGEN_ENABLED.
local _layoutNeedsRefresh = {}
local _buffIconLayoutRefreshPending = false

function CDMIcons.WakeBuffIconContainer()
    if _G.QUI_IsFrameHiddenByAnchor and _G.QUI_IsFrameHiddenByAnchor("buffIcon") then
        return
    end

    local container = ns.CDMContainers and ns.CDMContainers.GetContainer
        and ns.CDMContainers.GetContainer("buff")
    if container and container.Show then
        container:Show()
    end
end

local function RequestBuffIconLayoutRefresh()
    CDMIcons.WakeBuffIconContainer()
    if _buffIconLayoutRefreshPending then return end
    _buffIconLayoutRefreshPending = true
    C_Timer.After(0, function()
        _buffIconLayoutRefreshPending = false
        CDMIcons.WakeBuffIconContainer()
        if ns.CDMBuffLayout and ns.CDMBuffLayout.OnLayoutReady then
            ns.CDMBuffLayout:OnLayoutReady()
        end
    end)
end
CDMIcons.RequestBuffIconLayoutRefresh = RequestBuffIconLayoutRefresh

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

-- Re-entry guard. force(trackerKey) → QUI_ForceLayoutContainer →
-- ns.CDMIcons:UpdateAllCooldowns() → DrainLayoutDirty recursively. Bailing
-- the inner call prevents infinite recursion when the per-icon visibility
-- verdict diverges from LayoutContainer's (each pass re-marks the same
-- container, never settles). _DRAIN_MAX_ROUNDS caps the bounded outer loop
-- so a runaway oscillation can't burn the watchdog budget.
local _drainingLayoutDirty = false
local _DRAIN_MAX_ROUNDS = 3

local function DrainLayoutDirty()
    if _drainingLayoutDirty then return end
    if next(_layoutNeedsRefresh) == nil then return end
    _drainingLayoutDirty = true
    local force = _G.QUI_ForceLayoutContainer
    if not force then
        wipe(_layoutNeedsRefresh)
        _drainingLayoutDirty = false
        return
    end
    local toProcess = {}
    for round = 1, _DRAIN_MAX_ROUNDS do
        if next(_layoutNeedsRefresh) == nil then break end
        wipe(toProcess)
        for trackerKey in pairs(_layoutNeedsRefresh) do
            toProcess[#toProcess + 1] = trackerKey
        end
        wipe(_layoutNeedsRefresh)
        for _, trackerKey in ipairs(toProcess) do
            force(trackerKey)
        end
    end
    wipe(_layoutNeedsRefresh)
    _drainingLayoutDirty = false
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
    _hoistedNcdm = ncdm;  CDMIcons._hoistedNcdm = ncdm
    _batchTime = GetTime(); CDMIcons._batchTime = _batchTime

    CDMIcons.RefreshSwipeBatchSettings()

    return editMode, ncdm, ncdm and ncdm.containers, InCombatLockdown()
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
    if CDMIcons.IsCustomBarContainer(containerDB) then
        local visibility = CDMIcons.ComputeCustomBarVisibility(icon, entry, containerDB, _batchTime)
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
        CDMIcons.ApplyCustomBarActiveGlow(icon, containerDB, visibility)
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
            SetIconRowAlpha(icon)
            if not icon:IsShown() then icon:Show() end
        elseif effectiveMode == "active" then
            if isActive then
                SetIconRowAlpha(icon)
                if not icon:IsShown() then icon:Show() end
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

    local cooldownState = CDMIcons.ResolveCooldownActivityState(icon, entry, containerDB, _batchTime)
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
    SyncCooldownBling(icon)
end

---------------------------------------------------------------------------
-- UPDATE ALL COOLDOWNS
---------------------------------------------------------------------------
function CDMIcons:UpdateAllCooldowns()
    local editMode = Helpers.IsEditModeActive()
        or Helpers.IsLayoutModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())

    -- Hoist DB lookups above the loop (avoids 4 table hops per icon).
    -- Also set file-scoped _hoistedNcdm so UpdateIconCooldown can read it
    -- without re-walking the chain for every icon.
    local _ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    _hoistedNcdm = _ncdm;  CDMIcons._hoistedNcdm = _ncdm  -- consumed by UpdateIconCooldown
    _batchTime = GetTime(); CDMIcons._batchTime = _batchTime  -- consumed by UpdateIconCooldown + visibility loop
    -- Hoist GCD swipe setting so per-icon code can check it without DB lookups.
    CDMIcons.RefreshSwipeBatchSettings()
    local _ncdmContainers = _ncdm and _ncdm.containers
    local inCombat = InCombatLockdown()
    SetStackTextWritesForBatch(true)
    BeginResolverQueryBatch()

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon._spellEntry
            local wasAuraActive = icon._auraActive == true
            -- Update cooldown/aura state BEFORE visibility so _auraActive,
            -- _lastDuration, etc. are fresh for Show/Hide decisions.
            -- pcall only needed during combat (secret values from Blizzard
            -- frames) — skip overhead during OOC for ~50% less pcall cost.
            if inCombat then
                UpdateIconCooldown(icon)
            else
                UpdateIconCooldown(icon)
            end
            if entry and entry.viewerType == "buff"
               and wasAuraActive ~= (icon._auraActive == true) then
                RequestBuffIconLayoutRefresh()
            end

            -- Per-spell hidden override: always hide regardless of display mode
            local spellOvr = (not editMode) and GetIconSpellOverride(icon) or nil
            local isHiddenOverride = spellOvr and spellOvr.hidden

            if entry then
                -- Visibility branches per entry kind (aura vs cooldown). Container
                -- shape (icon vs bar) is decoupled — a cooldown entry on a bar-
                -- shaped container takes the cooldown branch, aura entries on an
                -- icon-shaped container take the aura branch.
                local containerDB = _ncdm and (_ncdm[entry.viewerType] or (_ncdmContainers and _ncdmContainers[entry.viewerType]))
                local displayMode = containerDB and containerDB.iconDisplayMode or "always"
                local entryIsAura = IsAuraEntry(entry)

                if isHiddenOverride then
                    -- Per-spell hidden override: always hide owned entries
                    if icon:IsShown() then icon:Hide() end
                elseif editMode then
                    icon:SetAlpha(1)
                    icon:Show()
                elseif entryIsAura then
                    -- Aura entries: visibility depends on display mode + aura state.
                    -- Custom-bar containers route through the same layout
                    -- machinery as cooldown entries (ComputeCustomBarVisibility,
                    -- ApplyIconVisibility, dynamicLayout, MarkLayoutDirtyOnFilterFlip)
                    -- because their layout/positioning pipeline lives there.
                    -- ComputeCustomBarVisibility already factors icon._auraActive
                    -- into its isActive/layoutVisible decision (see line ~2994).
                    -- Built-in TrackedBuff/trackedBar containers use the simpler
                    -- alpha+Show/Hide path below.
                    local isActive = icon._auraActive
                    local effectiveMode = displayMode
                    if effectiveMode == "combat" then
                        effectiveMode = inCombat and "always" or "active"
                    end

                    if CDMIcons.IsCustomBarContainer(containerDB) then
                        local visibility = CDMIcons.ComputeCustomBarVisibility(icon, entry, containerDB, _batchTime)
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
                                "effectiveMode=", tostring(effectiveMode),
                                "filterHidden=", tostring(filterHidesNow),
                                "auraActive=", tostring(isActive),
                                "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                        end
                        CDMIcons.ApplyCustomBarActiveGlow(icon, containerDB, visibility)

                        -- Desaturation is owned by the resolver; aura entries
                        -- have no cooldown/usability concept so this branch
                        -- never needs to drive SetDesaturated.

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
                    -- Cooldown containers: visibility depends on display mode.
                    -- _hasCooldownActive is set when a DurationObject was applied
                    -- (works even when numeric start/dur are secret in combat).
                    local cooldownState = CDMIcons.ResolveCooldownActivityState(icon, entry, containerDB, _batchTime)
                    local isOnCD = cooldownState.isOnCooldown or cooldownState.rechargeActive

                    local effectiveMode = displayMode
                    if effectiveMode == "combat" then
                        effectiveMode = (UnitAffectingCombat and UnitAffectingCombat("player")) and "always" or "active"
                    end

                    if CDMIcons.IsCustomBarContainer(containerDB) then
                        local visibility = CDMIcons.ComputeCustomBarVisibility(icon, entry, containerDB, _batchTime)
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
                        CDMIcons.ApplyCustomBarActiveGlow(icon, containerDB, visibility)

                        -- Desaturation owned by the resolver
                        -- (ApplyResolvedCooldown). Custom-bar active state
                        -- already feeds the resolver's auraBlocks check via
                        -- icon._customBarActive, so this branch must not
                        -- write SetDesaturated.

                        SyncCooldownBling(icon)
                    else

                    -- Compute desired visibility from display mode
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

                    -- Phase B.3: overlay container-level visibility filters.
                    -- Filter computed unconditionally so the dirty-tracker sees
                    -- the verdict even when display mode already hides the icon.
                    local filterHidesNow = ComputeFilterHides(icon, entry, containerDB, inCombat, isOnCD)
                    if filterHidesNow then shouldShow = false end
                    MarkLayoutDirtyOnFilterFlip(icon, entry, containerDB, filterHidesNow)

                    ApplyIconVisibility(icon, shouldShow, containerDB and containerDB.dynamicLayout)
                    end

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
                                    local info = Sources and Sources.QuerySpellInfo and Sources.QuerySpellInfo(sid)
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
                                local isHarm = Sources and Sources.QuerySpellHarmful and Sources.QuerySpellHarmful(spellName)
                                local isHelp = Sources and Sources.QuerySpellHelpful and Sources.QuerySpellHelpful(spellName)
                                if isHarm then
                                    icon._greyType = "debuff"
                                elseif isHelp then
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
    SetStackTextWritesForBatch(false)
    SyncSpellRangeChecks()
    EndResolverQueryBatch()
    DrainLayoutDirty()
end

local function UpdateCooldownOnlyIcon(icon, entry)
    if icon._blizzMirrorCooldownID and not IsAuraEntry(entry) then
        ApplyResolvedCooldown(icon)
        SyncCooldownBling(icon)
        return
    end
    UpdateIconCooldown(icon)
end

function CDMIcons:UpdateCooldownOnly()
    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    local allowStackTextWrites = CDMIcons._pendingStackTextUpdate == true
    CDMIcons._pendingStackTextUpdate = nil
    SetStackTextWritesForBatch(allowStackTextWrites)
    BeginResolverQueryBatch()

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

    -- After the per-icon visibility loop, relayout any container whose
    -- filter verdict flipped since the last layout pass.
    SetStackTextWritesForBatch(false)
    EndResolverQueryBatch()
    DrainLayoutDirty()
end

function CDMIcons:UpdateCooldownsForType(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        local _ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
        _hoistedNcdm = _ncdm;  CDMIcons._hoistedNcdm = _ncdm
        _batchTime = GetTime(); CDMIcons._batchTime = _batchTime
        CDMIcons.RefreshSwipeBatchSettings()
        SetStackTextWritesForBatch(true)
        BeginResolverQueryBatch()
        for _, icon in ipairs(pool) do
            UpdateIconCooldown(icon)
        end
        SetStackTextWritesForBatch(false)
        SyncSpellRangeChecks()
        EndResolverQueryBatch()
    end
end

---------------------------------------------------------------------------
-- CONFIGURE ICON (public wrapper)
---------------------------------------------------------------------------
CDMIcons.ConfigureIcon = ConfigureIcon
function CDMIcons.UpdateIconCooldown(icon)
    BeginResolverQueryBatch()
    UpdateIconCooldown(icon)
    EndResolverQueryBatch()
end
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
    if not spellID or not unit or not (Sources and Sources.QuerySpellInRange) then return nil end
    local inRange = Helpers.SafeValue(Sources.QuerySpellInRange(spellID, unit), nil)
    if inRange == false then return false end
    if inRange == true then return true end
    return nil
end

-- Safe wrapper: C_Spell.IsSpellUsable can return secret values in Midnight.
-- Calls pcall directly (no closure allocation).
local function SafeIsSpellUsable(spellID)
    if not spellID or not (Sources and Sources.QuerySpellUsable) then return true, false end
    local usable, noMana = Sources.QuerySpellUsable(spellID)
    usable = Helpers.SafeValue(usable, nil)
    noMana = Helpers.SafeValue(noMana, nil)
    if usable == false then return false, noMana == true end
    if usable == true then return true, noMana == true end
    return true, noMana == true
end

-- Per-cycle dedup caches: avoid calling the same C_Spell API for the same
-- spellID when multiple icons track the same ability.
local _rangeCycleCache = {}     -- [spellID] = true/false/"nil" (string "nil" for actual nil results)
local _hasRangeCycleCache = {}  -- [spellID] = true/false
local _usableCycleCache = {}    -- [spellID] = true/false
local _enabledRangeSpellChecks = {}
local _desiredRangeSpellChecks = {}
local _stackTextWritesForBatch = false

SetStackTextWritesForBatch = function(enabled)
    _stackTextWritesForBatch = enabled == true
    CDMIcons._allowStackTextWritesForBatch = _stackTextWritesForBatch
end

function CDMIcons.ShouldAllowStackTextWrites()
    return _stackTextWritesForBatch == true
end

local function NormalizeSpellIdentifier(value)
    if value == nil then return nil end
    if Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    if Helpers and Helpers.SafeValue then
        value = Helpers.SafeValue(value, nil)
    end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return value
    end
    return nil
end

local function SpellIdentifiersMatch(a, b)
    a = NormalizeSpellIdentifier(a)
    b = NormalizeSpellIdentifier(b)
    if a == nil or b == nil then return false end
    return a == b or tostring(a) == tostring(b)
end

local function GetIconRangeSpellID(icon, entry)
    entry = entry or (icon and icon._spellEntry)
    if not entry then return nil end
    return NormalizeSpellIdentifier(icon and icon._runtimeSpellID or entry.spellID or entry.id)
end

-- Reset icon to normal visual state (clear any tinting)
local function ResetIconVisuals(icon)
    icon.Icon:SetVertexColor(1, 1, 1, 1)
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
end

local function UpdateIconVisualState(icon, cachedDB, rangeEventSpellID, rangeEventInRange, rangeEventChecksRange)
    if not icon or not icon._spellEntry then return end
    local entry = icon._spellEntry
    local viewerType = entry.viewerType
    if not viewerType then return end

    local settings = (cachedDB and (cachedDB[viewerType] or (cachedDB.containers and cachedDB.containers[viewerType])))
        or GetTrackerSettings(viewerType)
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

    -- Reuse the override resolved during the last cooldown update cycle.
    -- _runtimeSpellID is written by UpdateIconCooldown on every cooldown
    -- event (cdm_icon_factory.lua), so any override change has already
    -- propagated by the time event-driven range/usability refreshes run.
    local spellID = GetIconRangeSpellID(icon, entry)
    if not spellID then return end

    ---------------------------------------------------------------------------
    -- Compute desired visual state (API calls use per-cycle dedup caches)
    ---------------------------------------------------------------------------
    local newVisualState = "normal"
    local cooldownVisualPriority = false

    -- Priority 1: Out of range (red tint) — only when attackable unit exists
    -- Respects soft targeting: hard target > soft enemy.
    local rangeUnit = rangeEnabled and GetRangeUnit() or nil
    if rangeUnit then
        local hasRange
        local inRange
        if rangeEventSpellID ~= nil then
            hasRange = rangeEventChecksRange == true
            inRange = hasRange and (rangeEventInRange == true) or nil
        else
            -- Per-cycle dedup: skip redundant C_Spell API calls for shared spellIDs
            hasRange = _hasRangeCycleCache[spellID]
            if hasRange == nil then
                hasRange = Sources and Sources.QuerySpellHasRange and Sources.QuerySpellHasRange(spellID)
                hasRange = Helpers.SafeValue(hasRange, nil)
                if hasRange == nil then hasRange = true end
                _hasRangeCycleCache[spellID] = hasRange and true or false
            end
            if hasRange then
                local cached = _rangeCycleCache[spellID]
                if cached ~= nil then
                    inRange = cached ~= "nil" and cached or nil
                else
                    inRange = SafeIsSpellInRange(spellID, rangeUnit)
                    _rangeCycleCache[spellID] = inRange == nil and "nil" or inRange
                end
            end
        end
        if hasRange then
            if inRange == false then
                newVisualState = "oor"
            end
        end
    end

    -- Cooldown desaturation owns the neutral/gray visual before usability.
    -- Range stays above it because red communicates target context.
    if newVisualState == "normal" then
        cooldownVisualPriority = CDMIcons.CooldownHasVisualPriority(icon, entry, settings, GetTime())
        if cooldownVisualPriority and icon._usabilityTinted then
            icon.Icon:SetVertexColor(1, 1, 1, 1)
            icon._usabilityTinted = nil
            icon._lastVisualState = nil
        end
    end

    -- Last priority: unusable / resource-starved (darken).
    if newVisualState == "normal" and usabilityEnabled and not cooldownVisualPriority then
        -- Per-cycle dedup: reuse result for shared spellIDs
        local isUsable = _usableCycleCache[spellID]
        if isUsable == nil then
            isUsable = SafeIsSpellUsable(spellID)
            _usableCycleCache[spellID] = isUsable
        end
        if not isUsable then
            local chargeState = CDMIcons.ResolveCooldownActivityState(icon, entry, settings, GetTime())
            if chargeState.hasCharges and chargeState.isOnCooldown ~= true then
                isUsable = true
            end
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
        if newVisualState == "unusable" and not icon._usabilityTinted and not icon._cdDesaturated and not cooldownVisualPriority then
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
        -- When the CD ends, desaturation clears and the next visual event
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

function CDMIcons.IconNeedsUsabilityVisualRefresh(icon, cachedDB)
    local entry = icon and icon._spellEntry
    if not entry then return false end
    if IsAuraEntry and IsAuraEntry(entry) then return false end
    if entry.kind == "aura" or entry.kind == "auraBar" then return false end
    if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then return false end

    if icon._rangeTinted or icon._usabilityTinted then
        return true
    end

    local viewerType = entry.viewerType
    if not viewerType or viewerType == "buff" then return false end

    local settings = (cachedDB and (cachedDB[viewerType] or (cachedDB.containers and cachedDB.containers[viewerType])))
        or GetTrackerSettings(viewerType)
    return settings and settings.usabilityIndicator or false
end

function CDMIcons.UpdateIconRangesForUsabilityEvent()
    wipe(_rangeCycleCache)
    wipe(_hasRangeCycleCache)
    wipe(_usableCycleCache)
    local db = GetDB()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMIcons.IconNeedsUsabilityVisualRefresh(icon, db) then
                UpdateIconVisualState(icon, db)
            end
        end
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

SyncSpellRangeChecks = function()
    wipe(_desiredRangeSpellChecks)
    local db = GetDB()

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry and entry.viewerType and entry.viewerType ~= "buff"
                and entry.type ~= "item" and entry.type ~= "trinket" and entry.type ~= "slot" then
                local settings = db and (db[entry.viewerType] or (db.containers and db.containers[entry.viewerType]))
                    or GetTrackerSettings(entry.viewerType)
                if settings and settings.rangeIndicator then
                    local spellID = GetIconRangeSpellID(icon, entry)
                    if spellID then
                        _desiredRangeSpellChecks[spellID] = true
                    end
                end
            end
        end
    end

    if not (Sources and Sources.EnableSpellRangeCheck) then
        wipe(_enabledRangeSpellChecks)
        return
    end

    for spellID in pairs(_enabledRangeSpellChecks) do
        if not _desiredRangeSpellChecks[spellID] then
            Sources.EnableSpellRangeCheck(spellID, false)
            _enabledRangeSpellChecks[spellID] = nil
        end
    end

    for spellID in pairs(_desiredRangeSpellChecks) do
        if not _enabledRangeSpellChecks[spellID] then
            if Sources.EnableSpellRangeCheck(spellID, true) then
                _enabledRangeSpellChecks[spellID] = true
            end
        end
    end
end

DisableSpellRangeChecks = function()
    if Sources and Sources.EnableSpellRangeCheck then
        for spellID in pairs(_enabledRangeSpellChecks) do
            Sources.EnableSpellRangeCheck(spellID, false)
        end
    end
    wipe(_enabledRangeSpellChecks)
    wipe(_desiredRangeSpellChecks)
end

local function UpdateIconsForSpellRangeEvent(spellIdentifier, isInRange, checksRange)
    local eventSpellID = NormalizeSpellIdentifier(spellIdentifier)
    if not eventSpellID then return end

    local db = GetDB()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry and SpellIdentifiersMatch(eventSpellID, GetIconRangeSpellID(icon, entry)) then
                local settings = db and (db[entry.viewerType] or (db.containers and db.containers[entry.viewerType]))
                    or GetTrackerSettings(entry.viewerType)
                if settings and settings.rangeIndicator and checksRange == true and isInRange == false
                    and icon.Icon and icon.Icon.SetVertexColor then
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
                    icon._lastVisualState = "oor"
                else
                    UpdateIconVisualState(icon, db, eventSpellID, isInRange == true, checksRange == true)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HANDLING: Update cooldowns on relevant events
---------------------------------------------------------------------------
local cdEventFrame = CreateFrame("Frame")
cdEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
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
-- SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_CHARGES, UNIT_SPELLCAST_START, and
-- UNIT_SPELLCAST_SUCCEEDED are owned by cdm_resolvers.lua, which publishes
-- CDM:COOLDOWN_CHANGED / CDM:CHARGES_CHANGED. UNIT_AURA is owned by
-- cdm_spelldata.lua so the full batched aura payload is processed before
-- icons/bars refresh.

-- Frame-based coalescing for cooldown/aura events. Pure cooldown events use a
-- lighter icon pass; aura and structural events upgrade the pending batch to a
-- full refresh. Avoid C_Timer here: raid combat can schedule this path
-- continuously, and timer objects become pure churn.
local CDM_MIN_UPDATE_INTERVAL_IDLE = 0.05
local CDM_MIN_UPDATE_INTERVAL_COMBAT = 0.20
local CDM_MIN_UPDATE_INTERVAL_RAID_COMBAT = 0.30
local CDM_FAST_UPDATE_INTERVAL = 0
local CDM_FAST_FULL_UPDATE_INTERVAL = CDM_MIN_UPDATE_INTERVAL_IDLE
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

local function RunDirtyBarUpdate()
    if _barsDirty and ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
        _barsDirty = false
        ns.CDMBars:UpdateOwnedBars()
    end
end

local function _CDMUpdateCallback(modeOverride, trustOverride)
    _cdmUpdatePending = false
    local mode = modeOverride or _cdmUpdateMode or CDM_UPDATE_COOLDOWN
    _cdmUpdateMode = CDM_UPDATE_COOLDOWN
    local trustIsOnGCD
    if trustOverride ~= nil then
        trustIsOnGCD = trustOverride == true
    else
        trustIsOnGCD = CDMIcons._pendingTrustIsOnGCD == true
    end
    CDMIcons._pendingTrustIsOnGCD = false

    if not CDMIcons:IsRuntimeEnabled() then
        return
    end

    _lastCDMUpdateTime = GetTime()
    CDMIcons._trustIsOnGCDForBatch = trustIsOnGCD

    if mode == CDM_UPDATE_FULL then
        CDMIcons:UpdateAllCooldowns()
    else
        CDMIcons:UpdateCooldownOnly()
    end
    RunDirtyBarUpdate()

    CDMIcons._trustIsOnGCDForBatch = false
end

local function CDMUpdateOnUpdate(self, elapsed)
    _cdmUpdateElapsed = _cdmUpdateElapsed + elapsed
    if _cdmUpdateElapsed < _cdmUpdateDelay then return end
    self:SetScript("OnUpdate", nil)
    _CDMUpdateCallback()
end

local function GetCDMUpdateDelay(fast, mode)
    if fast then
        if mode == CDM_UPDATE_COOLDOWN then
            return CDM_FAST_UPDATE_INTERVAL
        end
        return CDM_FAST_FULL_UPDATE_INTERVAL
    end
    if not InCombatLockdown() then
        return CDM_MIN_UPDATE_INTERVAL_IDLE
    end
    if IsInRaid and IsInRaid() then
        return CDM_MIN_UPDATE_INTERVAL_RAID_COMBAT
    end
    return CDM_MIN_UPDATE_INTERVAL_COMBAT
end

local function RegisterCDMSchedulerHandler()
    local scheduler = ns.CDMScheduler
    if not (scheduler and scheduler.SetRuntimeUpdateHandler) then return end
    scheduler.SetRuntimeUpdateHandler({
        run = _CDMUpdateCallback,
        getDelay = GetCDMUpdateDelay,
        isEnabled = function()
            return CDMIcons:IsRuntimeEnabled()
        end,
        onCancel = function()
            _cdmUpdatePending = false
            CDMIcons._pendingTrustIsOnGCD = false
        end,
    })
end

RegisterCDMSchedulerHandler()

local function ScheduleCDMUpdate(fast, mode, trustIsOnGCD)
    if not CDMIcons:IsRuntimeEnabled() then
        cdmUpdateFrame:SetScript("OnUpdate", nil)
        if ns.CDMScheduler and ns.CDMScheduler.CancelRuntimeUpdate then
            ns.CDMScheduler.CancelRuntimeUpdate()
        end
        _cdmUpdatePending = false
        CDMIcons._pendingTrustIsOnGCD = false
        return
    end

    mode = (mode == CDM_UPDATE_FULL) and CDM_UPDATE_FULL or CDM_UPDATE_COOLDOWN

    if ns.CDMScheduler and ns.CDMScheduler.ScheduleRuntimeUpdate then
        ns.CDMScheduler.ScheduleRuntimeUpdate(fast, mode, trustIsOnGCD)
        return
    end

    local delay = GetCDMUpdateDelay(fast, mode)

    if _cdmUpdatePending then
        if mode == CDM_UPDATE_FULL then
            _cdmUpdateMode = CDM_UPDATE_FULL
        end
        if trustIsOnGCD then
            CDMIcons._pendingTrustIsOnGCD = true
        end
        if delay < _cdmUpdateDelay then
            _cdmUpdateDelay = delay
        end
        return
end

    _cdmUpdatePending = true
    _cdmUpdateElapsed = 0
    _cdmUpdateDelay = delay
    _cdmUpdateMode = mode
    CDMIcons._pendingTrustIsOnGCD = trustIsOnGCD == true
    cdmUpdateFrame:SetScript("OnUpdate", CDMUpdateOnUpdate)
end

function CDMIcons.CountPendingMirrorRefreshKeys(pendingByCategory)
    local count = 0
    for _, byCooldownID in pairs(pendingByCategory) do
        for _ in pairs(byCooldownID) do
            count = count + 1
        end
    end
    return count
end

function CDMIcons.RefreshIndexedMirrorIcon(icon, editMode, ncdm, ncdmContainers, inCombat)
    local entry = icon and icon._spellEntry
    if not entry then return false end

    local wasAuraActive = icon._auraActive == true
    UpdateIconCooldown(icon)
    if entry.viewerType == "buff"
        and wasAuraActive ~= (icon._auraActive == true) then
        RequestBuffIconLayoutRefresh()
    end

    local containerDB = ncdm and (ncdm[entry.viewerType]
        or (ncdmContainers and ncdmContainers[entry.viewerType]))
    UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    return true
end

function CDMIcons.DrainMirrorTextRefreshQueue()
    CDMIcons._mirrorRefreshPending = false
    local pendingByCategory = CDMIcons._pendingMirrorRefreshByCategory
    CDMIcons._pendingMirrorRefreshByCategory = {}

    local batchKeys = CDMIcons.CountPendingMirrorRefreshKeys(pendingByCategory)
    if batchKeys == 0 then return end

    if batchKeys > CDMIcons._mirrorRefreshStats.maxBatch then
        CDMIcons._mirrorRefreshStats.maxBatch = batchKeys
    end
    CDMIcons._mirrorRefreshStats.targeted = CDMIcons._mirrorRefreshStats.targeted + batchKeys

    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    local refreshed = 0

    SetStackTextWritesForBatch(true)
    BeginResolverQueryBatch()
    for category, byCooldownID in pairs(pendingByCategory) do
        for cooldownID in pairs(byCooldownID) do
            local iconSet = CDMIcons.GetMirrorIconSet(category, cooldownID, false)
            if iconSet then
                for icon in pairs(iconSet) do
                    if icon
                        and icon._blizzMirrorCooldownID == cooldownID
                        and icon._blizzMirrorCategory == category
                        and CDMIcons.RefreshIndexedMirrorIcon(icon, editMode, ncdm, ncdmContainers, inCombat) then
                        refreshed = refreshed + 1
                    end
                end
            end
        end
    end
    SetStackTextWritesForBatch(false)
    EndResolverQueryBatch()

    if refreshed > 0 then
        DrainLayoutDirty()
    end
end

function CDMIcons:RequestMirrorTextRefresh(cooldownID, category)
    if not CDMIcons:IsRuntimeEnabled() then return end

    if not (cooldownID and category) then
        CDMIcons._mirrorRefreshStats.fallback = CDMIcons._mirrorRefreshStats.fallback + 1
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end

    local byCooldownID = CDMIcons._pendingMirrorRefreshByCategory[category]
    if not byCooldownID then
        byCooldownID = {}
        CDMIcons._pendingMirrorRefreshByCategory[category] = byCooldownID
    end
    byCooldownID[cooldownID] = true

    if CDMIcons._mirrorRefreshPending then return end
    if not (C_Timer and C_Timer.After) then
        CDMIcons.DrainMirrorTextRefreshQueue()
        return
    end

    CDMIcons._mirrorRefreshPending = true
    C_Timer.After(0, CDMIcons.DrainMirrorTextRefreshQueue)
end

-- Scoping rule for event-driven broad resolves: every event that triggers
-- a broad re-resolve walks ONLY the icons whose state can be affected by
-- what that event reports on. Sweeping every icon on every event propagates
-- transient API inconsistencies (e.g., C_Spell.GetSpellCooldown briefly
-- returning isActive=false isOnGCD=nil mid-GCD, surfaced via /cdmevents)
-- into icons that should not be touched, producing visible cooldown-swipe
-- flicker on unrelated cooldown-only spells. Three scoped variants cover
-- the three event families:
--   * Aura  — UNIT_AURA pipeline
--   * Item  — BAG_UPDATE_COOLDOWN, PLAYER_EQUIPMENT_CHANGED (trinket slots)
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
function CDMIcons.ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
    if not (icon and entry) then return false end

    local wasAuraActive = icon._auraActive == true
    ApplyResolvedCooldown(icon)

    local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
    if IsAuraEntry(entry) or cType == "aura" or cType == "auraBar" then
        UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
    end

    if entry.viewerType == "buff"
       and wasAuraActive ~= (icon._auraActive == true)
       and CDMIcons.RequestBuffIconLayoutRefresh then
        CDMIcons.RequestBuffIconLayoutRefresh()
    end

    return true
end

local function ApplyResolvedCooldownForAuraScope()
    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    BeginResolverQueryBatch()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry then
                local entryIsAura = IsAuraEntry and IsAuraEntry(entry)
                local iconAuraActive = icon._auraActive == true
                if entryIsAura or iconAuraActive then
                    CDMIcons.ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
                end
            end
        end
    end
    EndResolverQueryBatch()
end

-- Item-cooldown scope: BAG_UPDATE_COOLDOWN and PLAYER_EQUIPMENT_CHANGED.
-- A bag-cooldown event signals item cooldown change (potions, consumables,
-- on-equip CDs) — only item-backed entries are structurally affected. The
-- equipment-changed branch is already gated to trinket slots 13/14, which
-- are also item-backed. Spell-only entries are not affected by either event.
local function ApplyResolvedCooldownForItemScope()
    BeginResolverQueryBatch()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry then
                local entryType = entry.type
                local entryIsItem = entryType == "item"
                    or entryType == "trinket"
                    or entryType == "slot"
                if entryIsItem then
                    ApplyResolvedCooldown(icon)
                end
            end
        end
    end
    EndResolverQueryBatch()
end

-- Spell-cooldown scope: CDM:COOLDOWN_CHANGED broad fallback (GCD pulse /
-- gcdChanged / no per-spell payload), UNIT_SPELLCAST_SUCCEEDED on player,
-- CDM:CHARGES_CHANGED. A spell-cooldown event affects icons whose entry
-- is spell-shaped — NOT aura-kind (those are owned by UNIT_AURA) and NOT
-- item-backed (those are owned by BAG_UPDATE_COOLDOWN /
-- PLAYER_EQUIPMENT_CHANGED). The exclusion is intentional: cross-scope
-- sweeps were the original source of cooldown-swipe flicker on cooldown-
-- only spells when an aura churned anywhere on the player.
local function ApplyResolvedCooldownForSpellScope()
    BeginResolverQueryBatch()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry then
                local entryIsAura = IsAuraEntry and IsAuraEntry(entry)
                local entryType = entry.type
                local entryIsItem = entryType == "item"
                    or entryType == "trinket"
                    or entryType == "slot"
                if not entryIsAura and not entryIsItem then
                    ApplyResolvedCooldown(icon)
                end
            end
        end
    end
    EndResolverQueryBatch()
end

-- Cast events start a new GCD pulse for every visible icon. The dedupe
-- key for "gcd-only" is stable across pulses (same spellID), so without
-- this invalidation back-to-back casts of the same spell skip the rebind
-- and the C-side cooldown frame stays on the previous (already-expired)
-- pulse's timer. Real-cooldown / aura bindings keep their dedupe — their
-- keys stay distinct across pulses (real CDs are long-lived; auras use
-- DurationObject userdata identity to detect refresh).
local function InvalidateGCDOnlyBindings()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local lk = icon._lastDurObjKey
            if lk and lk:sub(1, 9) == "gcd-only:" then
                icon._lastDurObjKey = nil
                icon._lastDurObj = nil
            end
        end
    end
end

local function InvalidateSpellCooldownBinding(spellID)
    spellID = Helpers.SafeValue and Helpers.SafeValue(spellID, nil) or spellID
    if not spellID then return end
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            local lk = icon and icon._lastDurObjKey
            if entry and lk then
                local base = entry.spellID or entry.id
                local override = entry.overrideSpellID
                local runtime = Helpers.SafeValue and Helpers.SafeValue(icon._runtimeSpellID, nil) or icon._runtimeSpellID
                if base == spellID or override == spellID or runtime == spellID then
                    local isCooldownKey = lk:sub(1, 9) == "cooldown:"
                        or lk:sub(1, 7) == "charge:"
                        or lk:sub(1, 9) == "gcd-only:"
                        or lk:sub(1, 14) == "item-cooldown:"
                    if isCooldownKey then
                        icon._lastDurObjKey = nil
                        icon._lastDurObj = nil
                    end
                end
            end
        end
    end
end

-- SPELL_UPDATE_COOLDOWN payload: { spellID, baseSpellID, category, startRecoveryCategory }.
-- When spellID is non-nil, only one spell changed — re-resolve icons whose base
-- matches spellID or baseSpellID instead of walking every icon. baseSpellID is set
-- by Blizzard when spellID is an override, so checking both covers base-keyed and
-- override-keyed icons without reading override state in Lua.
local function ApplyResolvedCooldownForSpellID(eventSpellID, eventBaseSpellID)
    if not eventSpellID and not eventBaseSpellID then return end
    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    BeginResolverQueryBatch()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry then
                local base = entry.spellID or entry.id
                if base and (base == eventSpellID or base == eventBaseSpellID) then
                    local _, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
                    if IsAuraEntry(entry) or cType == "aura" or cType == "auraBar" then
                        CDMIcons.ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
                    else
                        ApplyResolvedCooldown(icon)
                    end
                end
            end
        end
    end
    EndResolverQueryBatch()
end

local function ApplyResolvedCooldownForAuraInstances(unit, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return nil end

    local ids = CDMIcons._auraDeltaInstanceIDs
    if not ids then
        ids = {}
        CDMIcons._auraDeltaInstanceIDs = ids
    else
        wipe(ids)
    end
    local hasIDs = false

    local spellIDs = CDMIcons._auraDeltaSpellIDs
    if not spellIDs then
        spellIDs = {}
        CDMIcons._auraDeltaSpellIDs = spellIDs
    else
        wipe(spellIDs)
    end
    local hasSpellIDs = false

    local function addAuraSpellID(rawID)
        local normalized = NormalizeSpellIdentifier(rawID)
        if normalized == nil then return end
        spellIDs[normalized] = true
        spellIDs[tostring(normalized)] = true
        if type(normalized) == "string" then
            local numeric = tonumber(normalized)
            if numeric then spellIDs[numeric] = true end
        end
        hasSpellIDs = true
    end

    local function spellSetHas(rawID)
        local normalized = NormalizeSpellIdentifier(rawID)
        if normalized == nil then return false end
        if spellIDs[normalized] == true or spellIDs[tostring(normalized)] == true then
            return true
        end
        if type(normalized) == "string" then
            local numeric = tonumber(normalized)
            return numeric and spellIDs[numeric] == true or false
        end
        return false
    end

    local function iconMatchesAuraSpellIDs(icon, entry)
        if not hasSpellIDs or not entry then return false end
        if spellSetHas(icon and icon._runtimeSpellID) then return true end
        if spellSetHas(entry.overrideSpellID) then return true end
        if spellSetHas(entry.spellID) then return true end
        if spellSetHas(entry.id) then return true end
        local linked = entry.linkedSpellIDs
        if type(linked) == "table" then
            for _, linkedID in ipairs(linked) do
                if spellSetHas(linkedID) then return true end
            end
        end
        return false
    end

    if updateInfo.addedAuras then
        for _, auraData in ipairs(updateInfo.addedAuras) do
            local auraInstanceID = auraData and auraData.auraInstanceID
            if auraInstanceID ~= nil then
                ids[auraInstanceID] = true
                hasIDs = true
            end
            if auraData then
                addAuraSpellID(auraData.spellId)
                addAuraSpellID(auraData.spellID)
            end
        end
    end
    if updateInfo.updatedAuraInstanceIDs then
        for _, auraInstanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
            if auraInstanceID ~= nil then
                ids[auraInstanceID] = true
                hasIDs = true
            end
        end
    end
    if updateInfo.removedAuraInstanceIDs then
        for _, auraInstanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            if auraInstanceID ~= nil then
                ids[auraInstanceID] = true
                hasIDs = true
            end
        end
    end

    if not hasIDs and not hasSpellIDs then return 0 end

    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    local refreshed = 0
    BeginResolverQueryBatch()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            local iconAuraInstanceID = icon and icon._auraInstanceID
            local matches = iconAuraInstanceID
                and ids[iconAuraInstanceID]
                and (not unit or icon._auraUnit == unit)
            if not matches and icon and icon._blizzMirrorCooldownID then
                local mirror = ns.CDMBlizzMirror
                local state = mirror and mirror.GetStateByCooldownID
                    and mirror.GetStateByCooldownID(icon._blizzMirrorCooldownID, icon._blizzMirrorCategory)
                local mirrorAuraInstanceID = state and state.auraInstanceID
                matches = mirrorAuraInstanceID
                    and ids[mirrorAuraInstanceID]
                    and (not unit or state.auraUnit == unit or icon._auraUnit == unit)
            end
            if not matches and iconMatchesAuraSpellIDs(icon, entry) then
                matches = true
            end
            if matches and entry then
                CDMIcons.ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombat)
                refreshed = refreshed + 1
            end
        end
    end
    EndResolverQueryBatch()

    return refreshed
end

function CDMIcons.IconNeedsUsabilityCooldownRefresh(icon)
    local entry = icon and icon._spellEntry
    if not entry then return false end
    if IsAuraEntry and IsAuraEntry(entry) then return false end
    if entry.kind == "aura" or entry.kind == "auraBar" then return false end
    if entry.type == "item" or entry.type == "trinket" or entry.type == "slot" then return false end
    if icon._hasCooldownActive == true or icon._hasRealCooldownActive == true then return true end
    if icon._showingRealCooldownSwipe or icon._showingGCDSwipe then return true end
    if icon._lastDurObjKey ~= nil or icon._cooldownExpiryTimerKey ~= nil then return true end
    if icon._isOnGCD ~= nil or icon._cdDesaturated then return true end
    return false
end

function CDMIcons.ApplyResolvedCooldownForUsabilityEvent()
    local spellState = CDMIcons._trustedGCDSpellState or {}
    wipe(spellState)
    CDMIcons._trustedGCDSpellState = spellState
    local stamp = GetTime()
    CDMIcons._trustedGCDStamp = stamp

    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    local previousTrust = CDMIcons._trustIsOnGCDForBatch
    CDMIcons._trustIsOnGCDForBatch = true

    local refreshed = 0
    BeginResolverQueryBatch()
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry and CDMIcons.IconNeedsUsabilityCooldownRefresh(icon) then
                CDMIcons.CaptureTrustedGCDStateForIcon(icon, spellState, stamp)
                ApplyResolvedCooldown(icon)

                local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
                if cType ~= "aura" and cType ~= "auraBar" then
                    UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
                end
                refreshed = refreshed + 1
            end
        end
    end
    EndResolverQueryBatch()

    CDMIcons._trustIsOnGCDForBatch = previousTrust
    if refreshed > 0 then
        DrainLayoutDirty()
    end
    return refreshed
end

local function RefreshCooldownVisualsForSpellID(eventSpellID, eventBaseSpellID)
    if not eventSpellID and not eventBaseSpellID then return false end

    local editMode, ncdm, ncdmContainers, inCombat = PrepareCooldownUpdateBatch()
    local refreshed = false

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry then
                local base = entry.spellID or entry.id
                if base and (base == eventSpellID or base == eventBaseSpellID) then
                    local containerDB, cType = ResolveContainerDBAndType(entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" then
                        UpdateCooldownContainerVisibility(icon, entry, containerDB, editMode, inCombat)
                        refreshed = true
                    end
                end
            end
        end
    end

    if refreshed then
        DrainLayoutDirty()
    end

    return refreshed
end
CDMIcons.RefreshCooldownVisualsForSpellID = RefreshCooldownVisualsForSpellID

function CDMIcons.NoteChargeDurationObjectsUpdated()
    CDMIcons._chargeDurationObjectSerial = (CDMIcons._chargeDurationObjectSerial or 0) + 1
end

-- EventTrace* helpers are provided by the load-on-demand debug addon.

function CDMIcons.EventFrameOnEvent(self, event, arg1, arg2, arg3)
    if not CDMIcons:IsRuntimeEnabled() then
        self:SetScript("OnUpdate", nil)
        cdmUpdateFrame:SetScript("OnUpdate", nil)
        if ns.CDMScheduler and ns.CDMScheduler.CancelRuntimeUpdate then
            ns.CDMScheduler.CancelRuntimeUpdate()
        end
        DisableSpellRangeChecks()
        _cdmUpdatePending = false
        return
    end

    if event == "UNIT_SPELLCAST_STOP"
       or event == "UNIT_SPELLCAST_CHANNEL_START"
       or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if arg1 == "player" then
            ScheduleCDMUpdate(true, CDM_UPDATE_COOLDOWN)
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        if _G.QUI_CDM_CHARGE_DEBUG then
            ChargeDebug(nil, "EVENT", event, "full-refresh")
        end
        CDMIcons:UpdateAllIconRanges()
        -- Target debuffs (e.g. Reaper's Mark) need a CDM refresh when target changes
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "PLAYER_SOFT_ENEMY_CHANGED" then
        if _G.QUI_CDM_CHARGE_DEBUG then
            ChargeDebug(nil, "EVENT", event, "full-refresh")
        end
        CDMIcons:UpdateAllIconRanges()
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Trinket slots 13-14: refresh textures and cooldowns immediately.
        -- Only item-backed entries can be affected by an equipment swap;
        -- spell-only entries stay out of this pipeline.
        if arg1 == 13 or arg1 == 14 then
            ApplyResolvedCooldownForItemScope()
            CDMIcons:UpdateAllCooldowns()
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        return
    end
    if event == "UPDATE_MACROS" then
        InvalidateMacroCache()
        return
    end
    if event == "SPELL_RANGE_CHECK_UPDATE" then
        UpdateIconsForSpellRangeEvent(arg1, arg2, arg3)
        return
    end
    if event == "SPELL_UPDATE_USABLE" then
        -- SPELL_UPDATE_USABLE has no spell payload and also fires at cooldown
        -- completion. Only icons with stale active cooldown/GCD state need a
        -- resolver pass; idle icons only participate if range/usability tinting
        -- is enabled or currently applied.
        CDMIcons.ApplyResolvedCooldownForUsabilityEvent()
        CDMIcons.UpdateIconRangesForUsabilityEvent()
        return
    end
    if event == "SPELLS_CHANGED" then
        -- Talent/spec change: spell icons may have changed.
        wipe(_textureCycleCache)
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        -- Server-side cooldown table changed; trigger a full re-resolve.
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        -- Both events carry a non-nil spellID (Nilable=false in the live FrameXML
        -- payload). At most one spell's cooldown state can be affected by a proc,
        -- so re-resolve only matching icons instead of triggering a full batch.
        -- cdm_effects.lua's dedicated handler owns the visual glow side.
        if arg1 then
            ApplyResolvedCooldownForSpellID(arg1, nil)
        end
        return
    end
    if event == "BAG_UPDATE_COOLDOWN" then
        -- Coalesce cooldown events via the reusable update frame.
        -- Bag cooldown changes are item-state only — potions, consumables,
        -- on-equip item CDs. Spell-only entries are not affected; staying
        -- out of this pipeline keeps API-flicker on spell cdInfo from
        -- driving spurious mode transitions on cooldown-only icons.
        ScheduleCDMUpdate(nil, CDM_UPDATE_COOLDOWN, false)
        ApplyResolvedCooldownForItemScope()
        return
    end
end

cdEventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    local profileStart = debugprofilestop and debugprofilestop()
    CDMIcons.EventTracePrint("frame-pre", event, arg1, arg2, arg3)
    CDMIcons.EventFrameOnEvent(self, event, arg1, arg2, arg3)
    CDMIcons.EventTracePrint("frame-post", event, arg1, arg2, arg3)
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
    _barsDirty = true
    ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
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
    local mirrorIndexKeys = 0
    local mirrorIndexIcons = 0
    for _, byCooldownID in pairs(CDMIcons._mirrorIconsByCategory) do
        for _, iconSet in pairs(byCooldownID) do
            mirrorIndexKeys = mirrorIndexKeys + 1
            for icon in pairs(iconSet) do
                if icon then
                    mirrorIndexIcons = mirrorIndexIcons + 1
                end
            end
        end
    end
    local schedulerPending = ns.CDMScheduler
        and ns.CDMScheduler.IsRuntimeUpdatePending
        and ns.CDMScheduler.IsRuntimeUpdatePending()
    local iconEventProfileTop, iconEventProfileWindow = CDMIcons.SnapshotEventProfile(5)
    return {
        textureCycleCache = n,
        activeIconPools    = activePools,
        activeIcons        = activeIcons,
        recycleIcons       = #recyclePool,
        barsDirty         = _barsDirty and true or false,
        updatePending     = (schedulerPending ~= nil and schedulerPending) or (_cdmUpdatePending and true or false),
        mirrorIndexKeys    = mirrorIndexKeys,
        mirrorIndexIcons   = mirrorIndexIcons,
        mirrorRefreshPending = CDMIcons._mirrorRefreshPending and true or false,
        mirrorRefreshPendingKeys = CDMIcons.CountPendingMirrorRefreshKeys(CDMIcons._pendingMirrorRefreshByCategory),
        mirrorRefreshTargeted = CDMIcons._mirrorRefreshStats.targeted,
        mirrorRefreshFallback = CDMIcons._mirrorRefreshStats.fallback,
        mirrorRefreshMaxBatch = CDMIcons._mirrorRefreshStats.maxBatch,
        iconEventProfileTop = iconEventProfileTop,
        iconEventProfileWindow = iconEventProfileWindow,
    }
end

-- Bus subscribers — replace direct Blizzard events.
-- The resolver owns runtime event registration and publishes CDM:* events
-- when state changes. We subscribe and call the same render functions the
-- old direct path called.
--
-- Aura events set _barsDirty only when a matching icon/bar may have changed.
-- Pure cooldown events deliberately do NOT set the flag — bar fill is driven
-- by barTimerGroup independently of ScheduleCDMUpdate.
local function HandleCDMAuraRefresh(unit, updateInfo)
    if not CDMIcons:IsRuntimeEnabled() then return end
    CDMIcons.EventTracePrint("aura-pre", "UNIT_AURA", unit, nil, nil,
        CDMIcons.EventTraceAuraInfo(updateInfo))

    -- UNIT_AURA scoping per the API contract (UnitAuraUpdateInfo in
    -- tests/api-docs/blizzard/UnitConstantsDocumentation.lua):
    --
    --   * isFullUpdate = true  → no instance lists; consumer MUST rescan
    --                            (here: full ScheduleCDMUpdate + aura-scope
    --                            refresh). This is the only case that walks
    --                            every icon.
    --   * isFullUpdate = false → addedAuras / updatedAuraInstanceIDs /
    --                            removedAuraInstanceIDs are authoritative
    --                            and complete. Walk only icons keyed by
    --                            those instance IDs. The "no match → fall
    --                            back to full refresh" defensive sweep is
    --                            removed: it produced a UpdateAllCooldowns
    --                            storm during combat (most player auras —
    --                            rune CDs, hidden state auras, talent
    --                            procs — aren't tracked, so refreshed=0
    --                            on nearly every player UNIT_AURA pulse).
    if not updateInfo or updateInfo.isFullUpdate then
        _barsDirty = true
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        ApplyResolvedCooldownForAuraScope()
    else
        local refreshed = ApplyResolvedCooldownForAuraInstances(unit, updateInfo)
        if refreshed > 0 then
            _barsDirty = true
            RunDirtyBarUpdate()
        end
    end

    CDMIcons.EventTracePrint("aura-post", "UNIT_AURA", unit, nil, nil,
        CDMIcons.EventTraceAuraInfo(updateInfo))
end

function CDMIcons.HandleUnitAuraChanged(unit, updateInfo)
    HandleCDMAuraRefresh(unit, updateInfo)
end

local function OnCDMCooldownChanged(_, spellID, baseSpellID, kind)
    if not CDMIcons:IsRuntimeEnabled() then return end
    if kind == "refresh" then
        -- Pre-cutover SPELL_UPDATE_COOLDOWN path. Per-spell fast-path when
        -- arg1 is a non-nil non-GCD spellID; otherwise full walk. The
        -- pre-cutover code also forced full walk when CaptureTrustedGCDState
        -- reported gcdChanged; preserve that here.
        local gcdChanged = CDMIcons.CaptureTrustedGCDState()
        ScheduleCDMUpdate(nil, CDM_UPDATE_COOLDOWN, true)
        CDMIcons._trustIsOnGCDForBatch = true
        if spellID and spellID ~= GCD_SPELL_ID and not gcdChanged then
            ApplyResolvedCooldownForSpellID(spellID, baseSpellID)
            RefreshCooldownVisualsForSpellID(spellID, baseSpellID)
        else
            InvalidateGCDOnlyBindings()
            -- Broad walk: arg1 was nil ("update all"), GCD pulse, or
            -- gcdChanged. Multiple spell IDs may have changed cooldown
            -- state and there is no per-spell payload. Scope to spell-
            -- shaped entries; aura and item entries don't react to spell
            -- cooldown events.
            ApplyResolvedCooldownForSpellScope()
        end
        CDMIcons._trustIsOnGCDForBatch = false
    elseif kind == "cast_start" then
        -- Pre-cutover UNIT_SPELLCAST_START on player: ScheduleCDMUpdate only.
        ScheduleCDMUpdate(true, CDM_UPDATE_COOLDOWN)
    elseif kind == "cast_succeeded" then
        -- UNIT_SPELLCAST_SUCCEEDED on player: refresh recent-cast tracking,
        -- invalidate the GCD-only binding cache, re-resolve cooldown state
        -- across icons, and dispatch to the cooldown highlighter so its
        -- visual feedback fires for the spell the player just cast.
        CDMIcons.RecordRecentPlayerSpellCast(spellID)
        InvalidateGCDOnlyBindings()
        InvalidateSpellCooldownBinding(spellID)
        ApplyResolvedCooldownForSpellScope()
        ScheduleCDMUpdate(true, CDM_UPDATE_COOLDOWN)
        local Highlighter = ns._OwnedHighlighter
        if Highlighter and Highlighter.OnPlayerCastSucceeded then
            Highlighter.OnPlayerCastSucceeded(spellID)
        end
    end
end

local function OnCDMChargesChanged(_, spellID)
    if not CDMIcons:IsRuntimeEnabled() then return end
    CDMIcons.NoteChargeDurationObjectsUpdated()
    CDMIcons._pendingStackTextUpdate = true
    ScheduleCDMUpdate(nil, CDM_UPDATE_COOLDOWN, false)
    if spellID then
        ApplyResolvedCooldownForSpellID(spellID, nil)
    else
        ApplyResolvedCooldownForSpellScope()
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
    cdmUpdateFrame:SetScript("OnUpdate", nil)
    if ns.CDMScheduler and ns.CDMScheduler.CancelRuntimeUpdate then
        ns.CDMScheduler.CancelRuntimeUpdate()
    end
    DisableSpellRangeChecks()
    _cdmUpdatePending = false
    _barsDirty = false
end

---------------------------------------------------------------------------
-- LATE-BIND CROSS-FILE IMPORTS
-- cdm_resolvers.lua and cdm_icon_factory.lua load before this file (per
-- cdm.xml) and cannot capture ns.CDMIcons at their own load time. They
-- declare the upvalues uninitialized; here we hand them the populated
-- CDMIcons table after every `CDMIcons.X = X` exposure above has run.
---------------------------------------------------------------------------
ns.CDMResolvers._FinalizeImports(CDMIcons)
ns.CDMIconFactory._FinalizeImports(CDMIcons)

---------------------------------------------------------------------------
-- DEBUG IMPORT BINDING
-- ChargeDebug is a placeholder until the load-on-demand debug addon rebinds it
-- via BindAll(). Hot-path callers keep their existing `ChargeDebug(...)`
-- upvalue calls.
---------------------------------------------------------------------------
function CDMIcons._BindDebugImports()
    local d = ns.CDMDebug
    if d then
        ChargeDebug = d.Charge or ChargeDebug
    end
end
