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

---------------------------------------------------------------------------
-- IMPORTS
---------------------------------------------------------------------------
local Resolvers = ns.CDMResolvers
local TickCacheGetCharges = Resolvers.TickCacheGetCharges
local TickCacheGetCooldown = Resolvers.TickCacheGetCooldown
local TickCacheGetDuration = Resolvers.TickCacheGetDuration
local TickCacheGetChargeDuration = Resolvers.TickCacheGetChargeDuration
local TickCacheGetOverrideSpell = Resolvers.TickCacheGetOverrideSpell
local TickCacheGetDisplayCount = Resolvers.TickCacheGetDisplayCount
local BeginUpdateTickCaches = Resolvers.BeginUpdateTickCaches
local ClearUpdateTickCaches = Resolvers.ClearUpdateTickCaches
local _tickCooldownStats = Resolvers._stats
local _textureCycleCache = Resolvers._textureCycleCache
local GetSpellTexture = Resolvers.GetSpellTexture
local ResolveMacro = Resolvers.ResolveMacro
local GetEntryTexture = Resolvers.GetEntryTexture
local HasRealCooldownState = Resolvers.HasRealCooldownState
local ResolveAuraStateForIcon = Resolvers.ResolveAuraStateForIcon
local ResolveAuraDurationObjectForIcon = Resolvers.ResolveAuraDurationObjectForIcon
local IsAuraEntry = Resolvers.IsAuraEntry
local GetChargeMetadataDB = Resolvers.GetChargeMetadataDB

---------------------------------------------------------------------------
-- COMPAT SHIMS
-- Resolver functions forwarded onto CDMIcons so callers in containers,
-- bars, and cdm_resolvers.lua itself can reach them via CDMIcons.X.
-- cdm_resolvers.lua loads before this file (owned.xml ordering).
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
-- cdm_icon_factory.lua (loads after this file via owned.xml ordering).
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
    local checker = _G.QUI_IsCDMMasterEnabled
    return type(checker) ~= "function" or checker()
end

-- CustomCDM exposed on CDMIcons for engine access (provider wires to ns.CustomCDM)
local CustomCDM = {}
CDMIcons.CustomCDM = CustomCDM

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
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
local C_StringUtil = C_StringUtil
local issecretvalue = issecretvalue
local DebugIconSwipe

local function IsSafeNumeric(val)
    if IsSecretValue(val) then return false end
    return type(val) == "number"
end
CDMIcons.IsSafeNumeric = IsSafeNumeric

local function SafeBoolean(val)
    if IsSecretValue(val) then return nil end
    if type(val) == "boolean" then return val end
    return nil
end

function CDMIcons.ApplyDurationObjectCooldown(cd, durObj, clearWhenZero, reverse)
    if not cd or not durObj or not cd.SetCooldownFromDurationObject then
        return false
    end

    if clearWhenZero == nil then
        clearWhenZero = true
    end

    local applied = pcall(cd.SetCooldownFromDurationObject, cd, durObj, clearWhenZero)
    if applied and reverse ~= nil and cd.SetReverse then
        pcall(cd.SetReverse, cd, reverse and true or false)
    end
    return applied and true or false
end

local function UsesAPIAuraStackText(entry)
    return IsAuraEntry(entry)
end

-- True when the actual Blizzard child lives in a buff viewer.  Used to
-- route stack-text handling through the API hook path even when the QUI
-- container is cooldown-typed: Blizzard's buff viewer doesn't drive
-- ChargeCount/Applications reliably through the cooldown-viewer path, so
-- stacks for spells like Mana Tea blank out on custom cooldown containers if
-- we don't detect this case independently of container type.
local function IsBuffViewerChild(blizzChild)
    if not blizzChild or not blizzChild.viewerFrame then return false end
    local buffViewer = _G["BuffIconCooldownViewer"]
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    return blizzChild.viewerFrame == buffViewer or blizzChild.viewerFrame == buffBarViewer
end

-- True when the entry's stack text should come from the buff-viewer hook
-- path rather than the cooldown-viewer charge hook path. Either an
-- aura/auraBar container or a cooldown container backed by a buff-viewer
-- child qualifies.
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
local ICON_FRAME_LEVEL_OFFSET = 1
local COOLDOWN_FRAME_LEVEL_OFFSET = 1
local TEXT_OVERLAY_FRAME_LEVEL_OFFSET = 6
local NATIVE_STACK_FRAME_LEVEL_OFFSET = 1
local GCD_SPELL_ID = 61304
local GCD_MAX_DURATION = 1.75
CDMIcons.COOLDOWN_EXPIRY_REFRESH_FUDGE = 0.2
CDMIcons.COOLDOWN_EXPIRY_RESCHEDULE_EPSILON = 0.1

function CDMIcons.GetCooldownInfoField(info, key)
    if not info then return nil, false end
    local value = info[key]
    if IsSecretValue(value) then
        return nil, true
    end
    return value, false
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
    -- Modern spell/action cooldown APIs expose isActive as a non-secret
    -- boolean: true means Blizzard's UI should render a cooldown display.
    -- Keep the older timing fallback for nil/older payloads only.
    local active, activeSecret = CDMIcons.GetCooldownInfoField(info, "isActive")
    if type(active) == "boolean" then
        return active
    end

    local start, duration, timingSecret = CDMIcons.GetCooldownInfoStartDuration(info)
    if type(start) == "number" and type(duration) == "number" then
        return start > 0 and duration > 0
    end

    if activeSecret or timingSecret then
        return nil
    end
    return false
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
    if type(duration) == "number" then
        if duration <= GCD_MAX_DURATION then
            return false
        end
        if type(start) == "number" and start <= 0 then
            return false
        end
        if active == true then
            return true
        end
    end

    local activeCategory, categorySecret = CDMIcons.GetCooldownInfoField(info, "activeCategory")
    if activeCategory ~= nil then
        return true
    end
    if categorySecret then
        return nil
    end

    local startRecovery, recoverySecret = CDMIcons.GetCooldownInfoField(info, "timeUntilEndOfStartRecovery")
    if type(startRecovery) == "number" and startRecovery > 0 then
        return false
    elseif startRecovery ~= nil and not timingSecret then
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
local MirrorBlizzCooldown = Factory.MirrorBlizzCooldown
local UpdateIconCooldown = Factory.UpdateIconCooldown

-- TAINT SAFETY: Blizzard Icon texture hook state tracked in a weak-keyed table.
-- Maps Blizzard child Icon regions → { icon = quiIcon } so the SetTexture hook
-- can mirror texture changes to the addon-owned icon without reading restricted
-- frames during combat.
local blizzTexState = setmetatable({}, { __mode = "k" })

-- Minimal state for hooked Blizzard stack/charge frames.
-- Maps _blizzChild → state table with these fields:
--   icon          (single-subscriber, for buff-viewer API hook path)
--   blizzChild    (back-reference)
--   auraText      (last hook-driven text, for IsHookStackActive)
--   auraHooked    (buff-viewer SetText hook installed)
--   subscribers   (weak set of icons sharing this child — multi-subscriber
--                  fan-out for cooldown-viewer ChargeCount/Applications)
--   subsHooked    (cooldown-viewer SetText hook installed)
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
        or tag == "DESAT charged check:" or tag == "DESAT result:"
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
CDMIcons.ChargeDebug = ChargeDebug

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

local DumpDebugIcon

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
        lookupID = (GetInventoryItemLink and GetInventoryItemLink("player", entry.id))
            or (GetInventoryItemID and GetInventoryItemID("player", entry.id))
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
-- into the best safe numeric values plus a DurationObject.  Do not store
-- secret numeric values in Lua state.
local function AccumulateCooldown(st, dur, info, bestStart, bestDur, bestDurObj)
    local durObj = ExtractCooldownDurObj(info)
    if IsSecretValue(st) or IsSecretValue(dur) then
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
    return bestStart, bestDur, bestDurObj
end

local function GetBestSpellCooldown(spellID)
    if not spellID then return nil, nil, nil, false, false end

    local bestStart, bestDuration = nil, nil
    local bestDurObj = nil
    local isActive = false
    local realCooldownActive = false

    -- Check primary spell (per-tick cached)
    local cdInfo = TickCacheGetCooldown(spellID)
    local cdActive = false
    local cdRealUnknown = false
    if cdInfo then
        local realActive
        cdActive, realActive = CDMIcons.ClassifySpellCooldownState(spellID, cdInfo)
        if cdActive == true then
            isActive = true
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
    local chargeInfo = TickCacheGetCharges(spellID)
    local chargeBased = false
    if chargeInfo then
        local maxCharges = SafeToNumber(chargeInfo.maxCharges, nil)
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
    if cdActive == true and cdRealUnknown and not chargeBased
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD(spellID) then
        realCooldownActive = true
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
            local overrideCdActive = false
            local overrideCdRealUnknown = false
            if cdInfo then
                local realActive
                overrideCdActive, realActive = CDMIcons.ClassifySpellCooldownState(overrideID, cdInfo)
                if overrideCdActive == true then
                    isActive = true
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
            chargeInfo = TickCacheGetCharges(overrideID)
            local overrideChargeBased = false
            if chargeInfo then
                local maxCharges = SafeToNumber(chargeInfo.maxCharges, nil)
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
            if overrideCdActive == true and overrideCdRealUnknown and not overrideChargeBased
               and CDMIcons.SpellHasBaseCooldownLongerThanGCD
               and CDMIcons.SpellHasBaseCooldownLongerThanGCD(overrideID) then
                realCooldownActive = true
            end
        end
    end

    -- DurationObject APIs (12.0+, secret-safe). These are the only
    -- authoritative spell timing source we forward to owned cooldowns.
    -- Gate queries behind real cooldown/recharge state. isActive is already
    -- the non-secret "Blizzard would render cooldown UI" signal; isOnGCD and
    -- the later usability split keep GCD/resource states from becoming real
    -- cooldown swipes.
    if not bestDurObj and realCooldownActive then
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
        if bestDurObj then
            isActive = true
            realCooldownActive = true
        end
    end

    if not bestDurObj and realCooldownActive then
        -- Fall back to spell cooldown duration (non-charged spells, per-tick cached)
        bestDurObj = TickCacheGetDuration(spellID)
        if not bestDurObj and C_Spell.GetOverrideSpell then
            local overrideID = TickCacheGetOverrideSpell(spellID)
            if overrideID and not IsSecretValue(overrideID) and overrideID ~= spellID then
                bestDurObj = TickCacheGetDuration(overrideID)
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
    if IsSafeNumeric(bestStart) and IsSafeNumeric(bestDuration)
       and bestStart > 0 and bestDuration > GCD_MAX_DURATION
       and (bestStart + bestDuration) > GetTime()
    then
        return bestStart, bestDuration, nil, true, true
    end

    if isActive == true
       and IsSafeNumeric(bestStart) and IsSafeNumeric(bestDuration)
       and bestStart > 0 and bestDuration > 0
    then
        return bestStart, bestDuration, nil, true, false
    end

    return nil, nil, nil, isActive, realCooldownActive
end

-- Item cooldown resolution
function CDMIcons.GetItemUseSpellID(itemID)
    if not itemID or not C_Item then return nil end

    if C_Item.GetItemSpell then
        local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
        if ok and spellID and not IsSecretValue(spellID) then
            return spellID
        end
    end

    if C_Item.GetFirstTriggeredSpellForItem then
        local itemQuality
        if C_Item.GetItemQualityByID then
            local okQuality, quality = pcall(C_Item.GetItemQualityByID, itemID)
            if okQuality and quality ~= nil then
                itemQuality = quality
            end
        end

        local ok, spellID
        if itemQuality ~= nil then
            ok, spellID = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID, itemQuality)
        else
            ok, spellID = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID)
        end
        if ok and spellID and not IsSecretValue(spellID) then
            return spellID
        end
    end

    return nil
end

function CDMIcons.GetRawItemUseSpellIDForAuraQuery(itemID)
    if not itemID or not C_Item then return nil end

    if C_Item.GetItemSpell then
        local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
        if ok and spellID then
            return spellID
        end
    end

    if C_Item.GetFirstTriggeredSpellForItem then
        local itemQuality
        if C_Item.GetItemQualityByID then
            local okQuality, quality = pcall(C_Item.GetItemQualityByID, itemID)
            if okQuality and quality ~= nil then
                itemQuality = quality
            end
        end

        local ok, spellID
        if itemQuality ~= nil then
            ok, spellID = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID, itemQuality)
        else
            ok, spellID = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID)
        end
        if ok and spellID then
            return spellID
        end
    end

    return nil
end

local function GetItemCooldown(itemID)
    if not itemID or not C_Item or not C_Item.GetItemCooldown then return nil, nil, nil end
    local ok, startTime, duration, enabled = pcall(C_Item.GetItemCooldown, itemID)
    if not ok then return nil, nil, nil end
    if IsSecretValue(startTime) or IsSecretValue(duration) or IsSecretValue(enabled) then
        -- Secret values can no longer be forwarded via SetCooldown (12.0.5+).
        -- Item entries can still use their use-spell DurationObject when
        -- available; this numeric fallback is deliberately non-secret only.
        return nil, nil, nil
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) or duration <= 0 then
        return nil, nil, nil
    end
    if enabled == 0 or enabled == false then
        return nil, nil, nil
    end
    return startTime, duration, nil
end

local function GetSlotCooldown(slotID)
    if not slotID or not GetInventoryItemCooldown then return nil, nil, nil end
    local ok, startTime, duration, enabled = pcall(GetInventoryItemCooldown, "player", slotID)
    if not ok then return nil, nil, nil end
    if IsSecretValue(startTime) or IsSecretValue(duration) or IsSecretValue(enabled) then
        return nil, nil, nil
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) then
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

function CDMIcons.SpellHasBaseCooldownLongerThanGCD(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellBaseCooldown) then
        return false
    end
    local ok, cooldownMS = pcall(C_Spell.GetSpellBaseCooldown, spellID)
    if not ok or not IsSafeNumeric(cooldownMS) then
        return false
    end
    return (cooldownMS / 1000) > GCD_MAX_DURATION
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
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    local CooldownSwipe = QUI.CooldownSwipe
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

---------------------------------------------------------------------------
-- IsAuraCurrentlyActive: detect whether an entry's associated aura is
-- currently up on the player or its target. Returns (isActive, auraUnit,
-- auraInstanceID). Used by swipe.lua and aura stack text resolution.
--
-- isActive may be true with auraInstanceID == nil — this happens when
-- Blizzard's wasSetFromAura flag is set on the viewer child but the
-- auraInstanceID is secret/redacted (common for target debuffs in combat
-- per WoW 12.0.5+). In that case visual mode classification still works
-- correctly (swipe color = "aura"). Cooldown-frame ownership stays in
-- ResolveAuraDurationObjectForIcon + ApplyResolvedCooldown.
---------------------------------------------------------------------------
local function IsAuraCurrentlyActive(entry)
    if not entry then return false, nil, nil end

    -- Step B: Blizzard's wasSetFromAura property on the viewer child.
    -- Combat-safe (set by Blizzard internally).
    local blizzChild = entry._blizzChild
    local wasSetFromAura = blizzChild
        and type(blizzChild.wasSetFromAura) == "boolean"
        and blizzChild.wasSetFromAura
    if wasSetFromAura then
        local instID = blizzChild.auraInstanceID
        if instID then
            -- Forward instID directly even if secret. C-side consumers
            -- (C_UnitAuras.GetAuraDuration, GetAuraApplicationDisplayCount)
            -- accept secret values transparently; we never compare or
            -- arithmetic on instID in Lua, only use it as a table key
            -- (works by reference) and pass it to C-side APIs.
            return true, "player", instID
        end
        -- wasSetFromAura true but instID is genuinely nil — keep walking
        -- to look for one via the captured-aura cache. (We still know the
        -- aura is active, so the final fallback below returns true even
        -- if no instID surfaces.)
    end

    local sid = entry.overrideSpellID or entry.spellID or entry.id
    if not sid then
        return false, nil, nil
    end

    -- Step C: captured-aura cache (combat-safe, encounter-safe).
    -- Encounter/M+/PvP starts wipe this cache so stale instIDs don't leak.
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.GetCapturedAuraForLookup then
        local lookupIDs = { sid }
        if entry.spellID and entry.spellID ~= sid then
            lookupIDs[#lookupIDs+1] = entry.spellID
        end
        if entry.id and entry.id ~= sid and entry.id ~= entry.spellID then
            lookupIDs[#lookupIDs+1] = entry.id
        end
        local captured = CDMSpellData.GetCapturedAuraForLookup(lookupIDs, entry.name)
        if captured and captured.auraInstanceID then
            return true, captured.unit or "player", captured.auraInstanceID
        end
    end

    -- Step D: out-of-combat aura API (in-combat AuraData has redacted
    -- auraInstanceID; can't be used here).
    if not InCombatLockdown() and C_UnitAuras then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and auraData and auraData.auraInstanceID
           and Helpers.IsAuraOwnedByPlayerOrPet(auraData, true) then
            return true, "player", auraData.auraInstanceID
        end
        if entry.name and entry.name ~= "" and C_UnitAuras.GetAuraDataBySpellName then
            local ok2, ad = pcall(C_UnitAuras.GetAuraDataBySpellName,
                                  "player", entry.name, "HELPFUL")
            if ok2 and ad and ad.auraInstanceID
               and Helpers.IsAuraOwnedByPlayerOrPet(ad, true) then
                return true, "player", ad.auraInstanceID
            end
        end
    end

    -- Final fallback: if Blizzard's wasSetFromAura flag was set on the
    -- viewer child, the aura IS active — Blizzard told us so. Return a
    -- positive answer with no instID so aura display priority still wins.
    if wasSetFromAura then return true, "player", nil end

    return false, nil, nil
end

CDMIcons.IsAuraCurrentlyActive = IsAuraCurrentlyActive

local function GetAuraDisplaySourceID(r, fallbackID)
    if not r then return fallbackID end
    local sourceID = r.auraInstanceID or r.totemSlot
    if sourceID and IsSecretValue(sourceID) then
        sourceID = r.durObj
    end
    return sourceID or fallbackID
end

local function ClearAuraStateForIcon(icon, entry)
    if not icon then return end
    icon._auraActive = false
    icon._auraUnit = nil
    icon._totemSlot = entry and entry._totemSlot or nil
    icon._isTotemInstance = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
end
CDMIcons.ClearAuraStateForIcon = ClearAuraStateForIcon

local function ApplyAuraStateToIcon(icon, entry, sid, r)
    if not r then
        return nil, false, nil
    end

    if r.isActive then
        local sourceID = GetAuraDisplaySourceID(r, sid)
        icon._auraActive = true
        icon._auraUnit = r.auraUnit
        icon._totemSlot = r.totemSlot or entry._totemSlot or nil
        icon._isTotemInstance = r.isTotemInstance and true or nil

        if r.durObj then
            icon._lastAuraDurObj = r.durObj
            icon._lastAuraSourceID = sourceID
            return r.durObj, true, sourceID
        end

        if icon._lastAuraDurObj then
            return icon._lastAuraDurObj, true, icon._lastAuraSourceID or sourceID
        end

        return nil, true, sourceID
    end

    ClearAuraStateForIcon(icon, entry)
    return nil, false, nil
end
CDMIcons.ApplyAuraStateToIcon = ApplyAuraStateToIcon

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
-- Cooldown-kind: charge count via C_Spell.GetSpellDisplayCount (via
-- TickCacheGetDisplayCount), gated by cached maxCharges > 1 in the
-- charge-metadata DB so single-cast spells return nil.
---------------------------------------------------------------------------
function CDMIcons.ResolveIconStackText(icon)
    if not icon or not icon._spellEntry then
        return nil, nil
    end
    local entry = icon._spellEntry

    -- Aura-kind path
    if IsAuraEntry(entry) then
        local active, auraUnit, instID = nil, nil, nil
        if icon._auraActive and entry._blizzChild
           and entry._blizzChild.auraInstanceID then
            -- Forward instID even if secret; C-side GetAuraApplicationDisplayCount
            -- accepts it, the cache uses it as an opaque table key.
            active, auraUnit, instID = true, "player", entry._blizzChild.auraInstanceID
        else
            active, auraUnit, instID = IsAuraCurrentlyActive(entry)
        end
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
    local overrideID = TickCacheGetOverrideSpell(sid)
    if overrideID then sid = overrideID end

    local svDB = GetChargeMetadataDB()
    local maxC = svDB and svDB[sid]
    if not maxC or maxC <= 1 then
        return nil, nil
    end

    local text = TickCacheGetDisplayCount(sid)
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

    ChargeDebug(entry.name, "DESAT result: hasRealCD=", hasRealCD,
        "_hasCooldownActive=", icon._hasCooldownActive,
        "mode=", tostring(resolvedMode),
        "hasCharges=", entry.hasCharges,
        "viewerType=", entry.viewerType)

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

function CDMIcons.CaptureTrustedGCDState()
    if not C_Spell or not C_Spell.GetSpellCooldown then
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
            if icon and icon._spellEntry then
                local sid = GetIconCooldownIdentifier(icon)
                if sid then
                    local trusted = spellState[sid]
                    if trusted == nil then
                        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, sid)
                        local onGCD = ok and cdInfo and cdInfo.isOnGCD
                        if type(onGCD) == "boolean" then
                            trusted = onGCD
                        end
                        if trusted ~= nil then
                            spellState[sid] = trusted
                        end
                    end
                    local prev = icon._isOnGCD
                    if type(trusted) == "boolean" then
                        if prev ~= trusted then anyChanged = true end
                        icon._isOnGCD = trusted
                        icon._isOnGCDTrustedAt = stamp
                    else
                        if prev ~= nil then anyChanged = true end
                        icon._isOnGCD = nil
                        icon._isOnGCDTrustedAt = nil
                    end
                else
                    if icon._isOnGCD ~= nil then anyChanged = true end
                    icon._isOnGCD = nil
                    icon._isOnGCDTrustedAt = nil
                end
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
        pcall(timer.Cancel, timer)
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
        pcall(existing.Cancel, existing)
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
        ClearUpdateTickCaches()
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

    local start, duration, timingSecret = CDMIcons.GetCooldownInfoStartDuration(cdInfo)
    if timingSecret or type(start) ~= "number" or type(duration) ~= "number" then
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

    local durObj, mode, sourceID, resolvedStart, resolvedDuration, resolvedSpellID =
        CDMIcons.ResolveIconDurationObject(icon)
    icon._resolvedCooldownMode = mode

    -- "Real CD active" desaturation gate. The only Lua decision inputs here
    -- are readable cooldown booleans. Charge counts are restricted during
    -- combat, so charged spells never consult currentCharges. A charged
    -- spell's SpellChargeInfo.isActive selects the recharge DurObj in the
    -- resolver; desaturation still follows SpellCooldownInfo.isActive and
    -- excludes only an explicit isOnGCD == true pulse.
    local entry = icon._spellEntry
    local itemEntryForCooldown = entry
        and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
    local sid = resolvedSpellID
    if not sid and entry and not itemEntryForCooldown then
        sid = icon._runtimeSpellID
            or entry.overrideSpellID or entry.spellID or entry.id
    end
    if sid then
        sid = TickCacheGetOverrideSpell(sid) or sid
    end
    local cdActive = false
    local resolvedCdInfo = nil
    local _dbgIsActive, _dbgIsOnGCD = nil, nil
    local _dbgChargeActive, _dbgChargeMax = nil, nil
    if entry and sid and C_Spell and C_Spell.GetSpellCharges then
        local ci = TickCacheGetCharges(sid)
        if ci then
            _dbgChargeActive = SafeValue(ci.isActive, "secret")
            _dbgChargeMax = SafeValue(ci.maxCharges, "secret")
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
    if sid and C_Spell and C_Spell.GetSpellCooldown then
        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, sid)
        if ok and cdInfo then
            resolvedCdInfo = cdInfo
            local cdInfoActive = CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
            local cdInfoOnGCD = cdInfo.isOnGCD
            _dbgIsActive = cdInfoActive
            _dbgIsOnGCD = cdInfoOnGCD
            local cdInfoNotGCD = cdInfoOnGCD ~= true
            if cdInfoActive == true and cdInfoNotGCD then
                cdActive = true
            end
        end
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
    ApplyCooldownDesaturation(icon, entry, nil, mode)

    local hasNumericCooldown = mode == "item-cooldown" and numericCooldownActive
    local keySource = sourceID
    if keySource and IsSecretValue(keySource) then
        keySource = durObj or mode
    end
    local key = mode .. ":" .. tostring(keySource)

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
            if addonCD.SetReverse then
                pcall(addonCD.SetReverse, addonCD, false)
            end
            addonCD:Clear()
            CDMIcons.ClearGCDSwipe(icon)
            icon._showingRealCooldownSwipe = nil
            return false
        end
        if icon._lastDurObjKey ~= nil then
            icon._lastDurObjKey = nil
            icon._lastDurObj = nil
            if not icon._showingGCDSwipe then
                if addonCD.SetReverse then
                    pcall(addonCD.SetReverse, addonCD, false)
                end
                addonCD:Clear()
                CDMIcons.ClearGCDSwipe(icon)
            end
        end
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
            icon._showingRealCooldownSwipe = true
        elseif mode == "gcd-only" then
            icon._showingRealCooldownSwipe = nil
        end
        return true
    end
    icon._lastDurObjKey = key
    icon._lastDurObj = durObj

    local applied
    if durObj then
        applied = CDMIcons.ApplyDurationObjectCooldown(addonCD, durObj, true, mode == "aura")
    elseif hasNumericCooldown and addonCD.SetCooldown then
        if addonCD.SetReverse then
            pcall(addonCD.SetReverse, addonCD, false)
        end
        applied = pcall(addonCD.SetCooldown, addonCD, resolvedStart, resolvedDuration)
    end
    if not applied then
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
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

    return true
end

local function EntryMatchesReadableID(icon, entry, id)
    id = SafeValue(id, nil)
    if not id then return nil end

    local function same(candidate)
        candidate = SafeValue(candidate, nil)
        return candidate ~= nil and candidate == id
    end

    if icon and same(icon._runtimeSpellID) then return true end
    if entry then
        if same(entry.overrideSpellID) then return true end
        if same(entry.spellID) then return true end
        if same(entry.id) then return true end
    end

    return false
end

local function ChildStillBoundToIcon(icon, blizzChild)
    if not icon or not blizzChild then return false end
    local entry = icon._spellEntry
    if not entry then return false end

    local sawReadableID = false
    local function checkID(id)
        local match = EntryMatchesReadableID(icon, entry, id)
        if match ~= nil then
            sawReadableID = true
            if match then return true end
        end
        return false
    end

    local cinfo = blizzChild.cooldownInfo
    if type(cinfo) == "table" and Helpers.CanAccessTable(cinfo) then
        if checkID(cinfo.spellID) then return true end
        if checkID(cinfo.overrideSpellID) then return true end
        if checkID(cinfo.overrideTooltipSpellID) then return true end
        local linkedSpellIDs = cinfo.linkedSpellIDs
        if type(linkedSpellIDs) == "table" and Helpers.CanAccessTable(linkedSpellIDs) then
            for _, linkedID in ipairs(linkedSpellIDs) do
                if checkID(linkedID) then return true end
            end
        end
    end

    if blizzChild.GetSpellID then
        local ok, spellID = pcall(blizzChild.GetSpellID, blizzChild)
        if ok and checkID(spellID) then return true end
    end
    if blizzChild.GetAuraSpellID then
        local ok, auraSpellID = pcall(blizzChild.GetAuraSpellID, blizzChild)
        if ok and checkID(auraSpellID) then return true end
    end

    if sawReadableID then
        return false
    end

    return true
end

local function UnmirrorBlizzCooldown(icon)
    if not icon._blizzCooldown then return end

    -- No reparenting to undo — the Blizzard CD was never moved.
    icon._blizzCooldown = nil
    icon._auraActive = nil
    icon._auraUnit = nil
    icon._lastAuraDurObj = nil
    icon._lastAuraSourceID = nil
end
CDMIcons.UnmirrorBlizzCooldown = UnmirrorBlizzCooldown
-- Exposed for cdm_icon_factory.lua (MirrorBlizzCooldown references these)
CDMIcons.ChildStillBoundToIcon = function(icon, blizzChild) return ChildStillBoundToIcon(icon, blizzChild) end
CDMIcons.ApplyResolvedCooldown = function(icon) return ApplyResolvedCooldown(icon) end
CDMIcons.ReapplySwipeStyle = function(cd, icon) return ReapplySwipeStyle(cd, icon) end

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

        -- Desaturation is driven solely by UpdateIconCooldown's real
        -- cooldown/recharge state. The mirror hook was forwarding Blizzard's
        -- transient desaturation toggles, causing flickering.
        -- Intentionally removed: no SetDesaturated forwarding.
    end
end
CDMIcons.HookBlizzTexture = HookBlizzTexture

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
CDMIcons.UnhookBlizzTexture = UnhookBlizzTexture

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
    if IsSecretValue(text) then
        return true
    end
    return text ~= nil and text ~= ""
end
CDMIcons.HookTextHasDisplay = HookTextHasDisplay  -- consumed by cdm_icon_factory.lua via _FinalizeImports

function CDMIcons.ValueIsPresent(value)
    if IsSecretValue(value) then
        return true
    end
    return value ~= nil
end

function CDMIcons.ValueIsMissing(value)
    return not CDMIcons.ValueIsPresent(value)
end

local function ClearAuraHookStackText(entry, icon)
    local child = entry and entry._blizzChild
    local state = child and blizzStackState[child]
    if state and (not icon or state.icon == icon or (state.subscribers and state.subscribers[icon])) then
        if icon and state.auraTexts then
            state.auraTexts[icon] = nil
        elseif state.auraTexts then
            wipe(state.auraTexts)
        end
        state.auraText = nil
    end
end
CDMIcons.ClearAuraHookStackText = ClearAuraHookStackText

--- Check whether Blizzard/native hook text is actively displaying on this
--- icon.  When true, API-based stack writes in UpdateIconCooldown should
--- yield so they do not overwrite clean hook arguments in the same frame.
local function IsHookStackActive(entry, icon)
    if not entry or not entry._blizzChild then return false end
    local child = entry._blizzChild
    if UsesAPIAuraStackText(entry) then
        local state = blizzStackState[child]
        if not (icon and icon._auraActive and state) then return false end
        if state.auraTexts and state.auraTexts[icon] ~= nil then return true end
        return state.icon == icon and state.auraText ~= nil
    end
    -- Cooldown container backed by a buff-viewer child: stacks come from
    -- the API hook path, not from the cooldown-viewer charge hook path.
    -- Hook is "active" whenever it has driven a non-empty text into our
    -- StackText for this icon.
    if IsBuffViewerChild(child) then
        local state = blizzStackState[child]
        if not state then return false end
        if state.auraTexts and state.auraTexts[icon] ~= nil then return true end
        return state.icon == icon and state.auraText ~= nil
    end
    local textOverlay = icon.TextOverlay
    if not textOverlay then return false end
    -- Legacy guard: if ChargeCount or Applications was already reparented
    -- onto our TextOverlay, treat that native stack display as active.
    if child.ChargeCount and child.ChargeCount:GetParent() == textOverlay then return true end
    if child.Applications and child.Applications:GetParent() == textOverlay then return true end
    return false
end
CDMIcons.IsHookStackActive = IsHookStackActive

local GetTrackerSettings

local function HookBlizzStackText(icon, blizzChild)
    if not blizzChild then return end

    local entry = icon._spellEntry
    local chargeFrame = blizzChild.ChargeCount
    local appFrame = blizzChild.Applications
    local iconApplications = blizzChild.Icon and blizzChild.Icon.Applications

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
        state.icon = icon
        state.blizzChild = blizzChild
        if not state.subscribers then
            state.subscribers = setmetatable({}, { __mode = "k" })
        end
        if not state.auraTexts then
            state.auraTexts = setmetatable({}, { __mode = "k" })
        end
        state.subscribers[icon] = true

        -- SetText hook fan-out retired in Phase 3 (Tasks 9–11). Stack/charge
        -- text is now driven by CDMIcons.ResolveIconStackText each tick from
        -- ApplyIconStackTextFromResolver inside UpdateIconVisualState.

        ChargeDebug(entry and entry.name, "HookBlizzStackText AURA ASSIGN",
            "spellID=", entry and entry.spellID, "overrideSpellID=", entry and entry.overrideSpellID,
            "hasCharges=", entry and entry.hasCharges,
            "buffViewerChild=", IsBuffViewerChild(blizzChild),
            "child.cooldownChargesCount=", blizzChild.cooldownChargesCount,
            "ChargeCount=", chargeFrame and "exists" or "nil",
            "Applications=", appFrame and "exists" or "nil",
            "IconApplications=", iconApplications and "exists" or "nil")
        return
    end

    -- Keep Blizzard's native stack frames on their original child and render
    -- QUI-owned count text through icon.StackText only. Rendering both native
    -- ChargeCount and owned StackText on the same icon gives two independently
    -- refreshed text layers, which can make stable charge counts shimmer.
    local textOverlay = icon.TextOverlay
    local function restoreNativeFrame(frame)
        if not frame or not textOverlay then return end
        local okParent, parent = pcall(frame.GetParent, frame)
        if okParent and parent == textOverlay then
            pcall(frame.SetParent, frame, blizzChild)
            pcall(frame.Hide, frame)
        end
    end
    restoreNativeFrame(chargeFrame)
    restoreNativeFrame(appFrame)

    -- Hook the native FontStrings so Blizzard's clean SetText arguments can
    -- fan out to owned StackText copies without showing the native layer.

    -- Minimal state tracking for IsHookStackActive and the FWD path.
    local state = blizzStackState[blizzChild]
    if not state then
        state = {}
        blizzStackState[blizzChild] = state
    end
    state.icon = icon
    state.blizzChild = blizzChild

    -- Multi-subscriber registration. A Blizzard FontString can only have one
    -- visual owner, so SetText hooks fan the value out to every subscriber's
    -- icon.StackText instead — each icon gets its own copy.
    -- The relevance check inside the fan-out (`ent._blizzChild == blizzChild`)
    -- handles icon recycle: a recycled icon no longer associated with this
    -- blizzChild is silently skipped instead of getting a stale write.
    -- Subscriber state lives on `state` (blizzStackState entry) instead of
    -- a separate module-level table to stay under Lua 5.1's 200-locals
    -- limit on the file's main chunk.
    if not state.subscribers then
        state.subscribers = setmetatable({}, { __mode = "k" })
    end
    state.subscribers[icon] = true

    -- SetText hook fan-out retired in Phase 3 (Tasks 9–11). Stack/charge
    -- text is now driven by CDMIcons.ResolveIconStackText each tick from
    -- ApplyIconStackTextFromResolver inside UpdateIconVisualState.

    ChargeDebug(entry and entry.name, "HookBlizzStackText ASSIGN",
        "spellID=", entry and entry.spellID, "overrideSpellID=", entry and entry.overrideSpellID,
        "hasCharges=", entry and entry.hasCharges,
        "child.cooldownChargesCount=", blizzChild.cooldownChargesCount,
        "ChargeCount=", chargeFrame and "exists" or "nil",
        "Applications=", appFrame and "exists" or "nil",
        "IconApplications=", iconApplications and "exists" or "nil")
end
CDMIcons.HookBlizzStackText = HookBlizzStackText

local function ClearIconStackText(icon)
    if not icon or not icon.StackText then return end
    pcall(icon.StackText.SetText, icon.StackText, "")
    pcall(icon.StackText.Hide, icon.StackText)
end
CDMIcons.ClearIconStackText = ClearIconStackText

-- Per-icon aura-applications fallback for cooldown-container icons.
-- HookBlizzStackText fans native values into owned StackText copies, but
-- buff-viewer children do not always emit a native stack update for every
-- subscriber. When the same single-charge stacking-aura spell (e.g., Mana
-- Tea) shows in multiple QUI containers, this API read is per-icon and
-- does not depend on native frame ownership. Returns the raw
-- applications value (may be secret in combat) for C-side forwarding,
-- or nil when no eligible aura is present.
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
-- compare against "" downstream (cdm_bars.lua, swipe.lua, profile_io.lua
-- all do `entry.name ~= ""`). Skips GetSpellInfo entirely in combat —
-- info.name there could be secret, and we don't want a secret leaking
-- onto entry.name and tainting unrelated comparison sites.
local function GetCachedSpellName(spellID)
    if not spellID then return nil end
    local cached = _spellNameCache[spellID]
    if cached then return cached end
    if InCombatLockdown() then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok or not info then return nil end
    local name = info.name
    if name == nil or IsSecretValue(name) then return nil end
    _spellNameCache[spellID] = name
    return name
end

function CDMIcons.GetSpellNameForAlias(spellID)
    if not spellID then return nil end
    local cached = GetCachedSpellName(spellID)
    if cached then return cached end
    if C_Spell and C_Spell.GetSpellName then
        local okName, name = pcall(C_Spell.GetSpellName, spellID)
        if okName and name and not IsSecretValue(name) then
            return name
        end
    end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if ok and info and info.name and not IsSecretValue(info.name) then
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
    if CDMIcons.DebugSpellEvent then
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

    local apps = auraData.applications
    if CDMIcons.ValueIsPresent(apps) then
        return apps, source
    end

    local auraInstanceID = auraData.auraInstanceID
    if auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, stacks = pcall(C_UnitAuras.GetAuraApplicationDisplayCount,
            unit or auraData.auraDataUnit or "player", auraInstanceID, 1, 99)
        if ok and HookTextHasDisplay(stacks) then
            return stacks, "display-count"
        end
    end

    return nil
end

function CDMIcons._TryAuraApplicationsBySpellID(auraID, source)
    if CDMIcons.ValueIsMissing(auraID) or not C_UnitAuras then return nil end

    if C_UnitAuras.GetCooldownAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetCooldownAuraBySpellID, auraID)
        if ok and auraData then
            local unit = auraData.auraDataUnit or "player"
            local apps, appSource = CDMIcons._GetAuraApplicationsFromData(
                auraData, unit, (source or "spell") .. "-cooldown-aura")
            if CDMIcons.ValueIsPresent(apps) then
                return apps, appSource
            end
        end
    end

    if C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, auraID)
        if ok and auraData then
            local apps, appSource = CDMIcons._GetAuraApplicationsFromData(
                auraData, "player", (source or "spell") .. "-player-spell")
            if CDMIcons.ValueIsPresent(apps) then
                return apps, appSource
            end
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
        local auraID = SafeValue(linkedID, nil)
        local linkedIsSecret = IsSecretValue(linkedID)

        if linkedIsSecret or (auraID and auraID > 0 and not seenIDs[auraID]) then
            if auraID then
                seenIDs[auraID] = true
                queryID = auraID
            end

            local apps, appSource = CDMIcons._TryAuraApplicationsBySpellID(queryID, source or "linked")
            if CDMIcons.ValueIsPresent(apps) then
                ChargeDebug(entry and entry.name, "AURA linked stack",
                    "auraID=", SafeValue(queryID, "secret"), "source=", appSource or "nil")
                return apps, appSource
            end

            if auraID then
                apps, appSource = CDMIcons._ResolveAuraApplicationsForEntry(auraID, entry, icon)
                if CDMIcons.ValueIsPresent(apps) then
                    ChargeDebug(entry and entry.name, "AURA linked resolve",
                        "auraID=", auraID, "source=", appSource or "nil")
                    return apps, appSource or (source or "linked")
                end
            end
        end
    end

    return nil
end

function CDMIcons._TryChildLinkedAuraApplications(child, entry, icon, seenIDs, source)
    local cooldownInfo = child and child.cooldownInfo
    if type(cooldownInfo) ~= "table" or not Helpers.CanAccessTable(cooldownInfo) then
        return nil
    end
    return CDMIcons._TryLinkedAuraApplications(cooldownInfo.linkedSpellIDs, entry, icon, seenIDs, source)
end

function CDMIcons.GetBlizzChildApplicationText(icon, entry)
    local child = entry and entry._blizzChild
    if not child then return nil end

    local auraInstanceID = child.auraInstanceID
    local function tryUnit(unit)
        if not unit or unit == "" then return nil end

        if auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
            local okApps, apps = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, 1, 99)
            if okApps and HookTextHasDisplay(apps) then
                return apps, "native-applications-display"
            end
        end

        if auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
            local okData, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
            if okData and auraData then
                local apps, source = CDMIcons._GetAuraApplicationsFromData(auraData, unit, "native-applications-data")
                if CDMIcons.ValueIsPresent(apps) then
                    return apps, source
                end
            end
        end

        return nil
    end

    local unit = icon and icon._auraUnit
    local apps, source = tryUnit(unit)
    if CDMIcons.ValueIsPresent(apps) then return apps, source end

    apps, source = tryUnit("player")
    if CDMIcons.ValueIsPresent(apps) then return apps, source end

    apps, source = tryUnit("pet")
    if CDMIcons.ValueIsPresent(apps) then return apps, source end

    apps, source = tryUnit("target")
    if CDMIcons.ValueIsPresent(apps) then return apps, source end

    local iconApplications = child.Icon and child.Icon.Applications
    if iconApplications and iconApplications.GetText then
        local okIconText, iconText = pcall(iconApplications.GetText, iconApplications)
        if okIconText and HookTextHasDisplay(iconText) then
            return iconText, "native-icon-applications-text"
        end
    end

    local appFrame = child.Applications
    local fs = appFrame and appFrame.Applications
    if fs and fs.GetText then
        local okText, text = pcall(fs.GetText, fs)
        if okText and HookTextHasDisplay(text) then
            return text, "native-applications-text"
        end
    end

    return nil
end

function CDMIcons._EntryHasAuraStackContext(icon, entry, child, spellID)
    if icon and icon._auraActive then return true end
    if IsAuraEntry(entry) then return true end
    if IsBuffViewerChild(child) then return true end

    if child then
        if child.auraInstanceID ~= nil or child.auraDataUnit ~= nil then
            return true
        end

        local cooldownInfo = child.cooldownInfo
        if type(cooldownInfo) == "table"
            and Helpers.CanAccessTable(cooldownInfo)
            and cooldownInfo.linkedSpellIDs then
            return true
        end
    end

    local barChild = entry and entry._blizzBarChild
    if barChild and (barChild.auraInstanceID ~= nil or barChild.auraDataUnit ~= nil) then
        return true
    end

    if entry and entry.linkedSpellIDs then
        return true
    end

    local auraMap = ns.CDMSpellData and ns.CDMSpellData._abilityToAuraSpellID
    if auraMap then
        local function mapped(id)
            id = SafeValue(id, nil)
            return id and auraMap[id] ~= nil
        end
        if mapped(spellID)
            or mapped(entry and entry.spellID)
            or mapped(entry and entry.overrideSpellID)
            or mapped(entry and entry.id) then
            return true
        end
    end

    return false
end

function CDMIcons._GetAuraBackedCooldownChargesCount(icon, entry, spellID)
    local child = entry and entry._blizzChild
    if not child or child.cooldownChargesCount == nil then
        return nil
    end
    if not CDMIcons._EntryHasAuraStackContext(icon, entry, child, spellID) then
        return nil
    end
    return child.cooldownChargesCount, "fwd-stacking-aura"
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
    p.viewerType = entry.viewerType
    p.blizzChild = entry._blizzChild
    p.blizzBarChild = entry._blizzBarChild
    p.totemSlot = IsTotemSlotEntry(entry) and entry._totemSlot or nil
    p.disableLooseVisibilityFallback = true

    local r = ns.CDMSpellData:ResolveAuraState(p)
    if r.blizzBarChild then
        entry._blizzBarChild = r.blizzBarChild
    end

    if r.isActive and not r.isTotemInstance then
        if CDMIcons.ValueIsPresent(r.stacks) then
            return r.stacks, r.stackSource
        end
        return CDMIcons._GetAuraApplicationsFromData(r.auraData, r.auraUnit, "resolved-data")
    end

    return nil
end

local function GetAuraApplicationsForSpell(spellID, entryOrName, icon)
    local entry = type(entryOrName) == "table" and entryOrName or nil
    local spellName = entry and entry.name or entryOrName
    local childApps, childSource = CDMIcons.GetBlizzChildApplicationText(icon, entry)
    if CDMIcons.ValueIsPresent(childApps) then
        return childApps, childSource
    end
    if CDMIcons.ValueIsMissing(spellID) or not C_UnitAuras then
        return nil
    end

    if IsSecretValue(spellID) then
        local directApps, directSource = CDMIcons._TryAuraApplicationsBySpellID(spellID, "spell")
        if CDMIcons.ValueIsPresent(directApps) then
            return directApps, directSource
        end
        return nil
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

    local linkedApps, linkedSource = CDMIcons._TryLinkedAuraApplications(
        entry and entry.linkedSpellIDs, entry, icon, seenIDs, "entry-linked")
    if CDMIcons.ValueIsPresent(linkedApps) then return linkedApps, linkedSource end

    linkedApps, linkedSource = CDMIcons._TryChildLinkedAuraApplications(
        entry and entry._blizzChild, entry, icon, seenIDs, "child-linked")
    if CDMIcons.ValueIsPresent(linkedApps) then return linkedApps, linkedSource end

    linkedApps, linkedSource = CDMIcons._TryChildLinkedAuraApplications(
        entry and entry._blizzBarChild, entry, icon, seenIDs, "bar-linked")
    if CDMIcons.ValueIsPresent(linkedApps) then return linkedApps, linkedSource end

    if entry and ns.CDMSpellData and ns.CDMSpellData._childBySpellID then
        local childList = ns.CDMSpellData._childBySpellID[spellID]
        if childList then
            for _, child in ipairs(childList) do
                linkedApps, linkedSource = CDMIcons._TryChildLinkedAuraApplications(
                    child, entry, icon, seenIDs, "map-linked")
                if CDMIcons.ValueIsPresent(linkedApps) then return linkedApps, linkedSource end
            end
        end
    end

    if not C_UnitAuras.GetAuraDataBySpellName then
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
    if (nameToUse == nil or nameToUse == "") and C_Spell and C_Spell.GetSpellInfo then
        local infoOk, info = pcall(C_Spell.GetSpellInfo, spellID)
        if infoOk and info then
            nameToUse = info.name  -- may be secret in combat — forwarded only
        end
    end
    if CDMIcons.ValueIsPresent(nameToUse) then
        local nOk, nad = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", nameToUse, "HELPFUL")
        if nOk and nad then
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

local function ApplyAuraStackText(icon, stackValue, showZero, preserveWhenMissing, stackSource)
    if not icon or not icon.StackText then return end

    if CDMIcons.ValueIsMissing(stackValue) then
        if not preserveWhenMissing then
            ClearIconStackText(icon)
        end
        return
    end

    if stackSource == "display-count" then
        if pcall(icon.StackText.SetText, icon.StackText, stackValue) then
            pcall(icon.StackText.Show, icon.StackText)
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

    if HookTextHasDisplay(displayText) then
        if pcall(icon.StackText.SetText, icon.StackText, displayText) then
            pcall(icon.StackText.Show, icon.StackText)
        end
    else
        ClearIconStackText(icon)
    end
end
CDMIcons.ApplyAuraStackText = ApplyAuraStackText

local function UnhookBlizzStackText(icon)
    local entry = icon._spellEntry
    if not entry or not entry._blizzChild then return end
    local state = blizzStackState[entry._blizzChild]
    if state then
        if state.icon == icon then
            state.icon = nil
        end
        if state.subscribers then
            state.subscribers[icon] = nil
        end
        if state.auraTexts then
            state.auraTexts[icon] = nil
        end
    end
end
CDMIcons.UnhookBlizzStackText = UnhookBlizzStackText

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

local function SyncNativeStackFrameLevel(icon, frame, requiredLevel)
    if not frame or not frame.GetParent or frame:GetParent() ~= icon.TextOverlay then return end
    if not frame.GetFrameLevel or not frame.SetFrameLevel then return end
    local ok, currentLevel = pcall(frame.GetFrameLevel, frame)
    if ok and currentLevel ~= requiredLevel then
        pcall(frame.SetFrameLevel, frame, requiredLevel)
    end
end

local function SyncNativeStackFrameLevels(icon)
    if not icon or not icon.TextOverlay then return end
    local entry = icon._spellEntry
    local blizzChild = entry and entry._blizzChild
    if not blizzChild then return end

    local requiredLevel = icon.TextOverlay:GetFrameLevel() + NATIVE_STACK_FRAME_LEVEL_OFFSET
    SyncNativeStackFrameLevel(icon, blizzChild.ChargeCount, requiredLevel)
    SyncNativeStackFrameLevel(icon, blizzChild.Applications, requiredLevel)
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

    SyncNativeStackFrameLevels(icon)
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

        -- Style the Cooldown frame's built-in text
        if icon.Cooldown then
            local ok, regions = pcall(function() return { icon.Cooldown:GetRegions() } end)
            if ok and regions then
                for _, region in ipairs(regions) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:SetFont(durationFont, durationSize, generalOutline)
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
        icon.DurationText:SetFont(durationFont, durationSize, generalOutline)
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
            if expiration and duration then
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

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and auraData then
            local expiration = SafeValue(auraData.expirationTime, nil)
            local duration = SafeValue(auraData.duration, nil)
            if expiration and duration then
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
    if not itemID or not C_Item or not C_Item.GetItemSpell then return false end
    local ok, _, itemSpellID = pcall(C_Item.GetItemSpell, itemID)
    if ok and itemSpellID then
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
        if C_Item and C_Item.GetItemInfoInstant and Enum and Enum.ItemClass then
            local okClass, instantItemID, instantItemType, instantItemSubType, instantEquipLoc, instantIcon, classID =
                pcall(C_Item.GetItemInfoInstant, entry.id)
            if okClass and (classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon) then
                if C_Item.IsEquippedItem then
                    local okEquipped, equipped = pcall(C_Item.IsEquippedItem, entry.id)
                    if okEquipped then
                        return equipped == true
                    end
                end
            end
        end
        if C_Item and C_Item.GetItemCount then
            local ok, count = pcall(C_Item.GetItemCount, entry.id, false, containerDB and containerDB.showItemCharges == true, true)
            if ok then
                if IsSecretValue and IsSecretValue(count) then
                    return true
                end
                count = SafeToNumber(count, nil)
                return count and count > 0
            end
        end
        return true
    elseif entry.type == "trinket" or entry.type == "slot" then
        local equippedItemID = GetInventoryItemID("player", entry.id)
        if not equippedItemID then return false end
        -- Trinket slots (13/14) track the slot rather than a specific item, so
        -- a passive stat-stick with no on-use would otherwise report usable
        -- and sit visible forever under hideNonUsable. Mirrors the legacy-
        -- container check in ComputeFilterHides so custom containers honor
        -- hideNonUsable for passive trinkets too.
        if entry.id == 13 or entry.id == 14 then
            if C_Item and C_Item.GetItemSpell then
                local okS, spellName = pcall(C_Item.GetItemSpell, equippedItemID)
                if okS and not spellName then return false end
            end
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
        if C_Spell and C_Spell.IsSpellUsable then
            local ok, usable = pcall(C_Spell.IsSpellUsable, sid)
            if ok and usable == false then
                return false
            end
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

    if CDMIcons.DebugIconEvent then
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
            pcall(icon.Icon.AddMaskTexture, icon.Icon, icon._customBarProcGlowMask)
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
        pcall(CDMIcons._LCG.ProcGlow_Stop, icon, "_QUIActiveGlow")
    elseif glowWasShown and glowType == "Autocast Shine" then
        pcall(CDMIcons._LCG.AutoCastGlow_Stop, icon, "_QUIActiveGlow")
    elseif glowWasShown then
        pcall(CDMIcons._LCG.PixelGlow_Stop, icon, "_QUIActiveGlow")
    end
    if icon.Icon and icon._customBarProcGlowMask then
        pcall(icon.Icon.RemoveMaskTexture, icon.Icon, icon._customBarProcGlowMask)
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

function CDMIcons.DebugStackText(icon, action, value, reason)
    if not _G.QUI_CDM_CHARGE_DEBUG then return end
    local entry = icon and icon._spellEntry
    local okShown, shown = false, nil
    local okText, text = false, nil
    if icon then
        okShown, shown = pcall(icon.IsShown, icon)
    end
    if icon and icon.StackText and icon.StackText.GetText then
        okText, text = pcall(icon.StackText.GetText, icon.StackText)
    end
    ChargeDebug(entry and entry.name,
        "STACKTEXT", action,
        "reason=", reason or "nil",
        "value=", SafeValue(value, "secret"),
        "oldText=", okText and SafeValue(text, "secret") or "err",
        "iconShown=", okShown and SafeValue(shown, "secret") or "err",
        "entryType=", entry and entry.type,
        "viewerType=", entry and entry.viewerType,
        "hasCharges=", entry and entry.hasCharges,
        "spellID=", entry and entry.spellID,
        "overrideSpellID=", entry and entry.overrideSpellID,
        "runtimeSpellID=", icon and icon._runtimeSpellID,
        "auraActive=", icon and icon._auraActive)
end

function CDMIcons.DebugNativeChargeText(icon, reason)
    if not _G.QUI_CDM_CHARGE_DEBUG then return end
    local entry = icon and icon._spellEntry
    local child = entry and entry._blizzChild
    local chargeFrame = child and child.ChargeCount
    local current = chargeFrame and chargeFrame.Current
    local textOverlay = icon and icon.TextOverlay
    if not chargeFrame and not current then
        ChargeDebug(entry and entry.name, "NATIVE-CHARGE", reason or "nil", "missing")
        return
    end

    local okFrameShown, frameShown = chargeFrame and pcall(chargeFrame.IsShown, chargeFrame)
    local okFrameParent, frameParent = chargeFrame and pcall(chargeFrame.GetParent, chargeFrame)
    local okTextShown, textShown = current and pcall(current.IsShown, current)
    local okText, text = current and pcall(current.GetText, current)
    local okTextParent, textParent = current and pcall(current.GetParent, current)
    ChargeDebug(entry and entry.name,
        "NATIVE-CHARGE", reason or "nil",
        "frameShown=", okFrameShown and SafeValue(frameShown, "secret") or "err",
        "frameParentOverlay=", okFrameParent and (frameParent == textOverlay) or "err",
        "textShown=", okTextShown and SafeValue(textShown, "secret") or "err",
        "text=", okText and SafeValue(text, "secret") or "err",
        "textParentOverlay=", okTextParent and (textParent == textOverlay) or "err",
        "childCount=", child and child.cooldownChargesCount,
        "hasCharges=", entry and entry.hasCharges,
        "viewerType=", entry and entry.viewerType)
end

function CDMIcons.ShowIconStackText(icon, value, containerDB, reason)
    if not icon or not icon.StackText then return end
    if CDMIcons.ShouldHideIconStackText(icon, containerDB) then
        CDMIcons.DebugStackText(icon, "hide", value, reason or "setting-hide-stack-text")
        pcall(icon.StackText.SetText, icon.StackText, "")
        pcall(icon.StackText.Hide, icon.StackText)
        return
    end
    local setErr
    local setOk
    setOk, setErr = pcall(icon.StackText.SetText, icon.StackText, value)
    if not setOk and icon.StackText.SetFormattedText then
        setOk, setErr = pcall(icon.StackText.SetFormattedText, icon.StackText, "%s", value)
    end
    local showOk = false
    local showErr
    if setOk then
        showOk, showErr = pcall(icon.StackText.Show, icon.StackText)
    end
    CDMIcons.DebugStackText(icon, setOk and "show" or "show-failed", value, reason)
    if _G.QUI_CDM_CHARGE_DEBUG then
        ChargeDebug(icon._spellEntry and icon._spellEntry.name,
            "STACKTEXT apply", "reason=", reason or "nil",
            "setOk=", tostring(setOk), "setErr=", tostring(setErr),
            "showOk=", tostring(showOk), "showErr=", tostring(showErr))
    end
end

function CDMIcons.HideIconStackText(icon, reason)
    if not icon or not icon.StackText then return end
    CDMIcons.DebugStackText(icon, "hide", nil, reason)
    pcall(icon.StackText.SetText, icon.StackText, "")
    pcall(icon.StackText.Hide, icon.StackText)
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
-- When false, cooldown-container icons skip aura detection entirely so
-- the icon shows the recharge/cooldown timer instead of the aura duration.
local _showBuffSwipe = true

CDMIcons._trustIsOnGCDForBatch = false
CDMIcons._pendingTrustIsOnGCD = false

function CDMIcons.RefreshSwipeBatchSettings()
    local swipeMod = ns._OwnedSwipe
    local swipeSettings = swipeMod and swipeMod.GetSettings and swipeMod.GetSettings()
    _showGCDSwipe = swipeSettings and swipeSettings.showGCDSwipe or false
    _showBuffSwipe = swipeSettings and (swipeSettings.showBuffSwipe ~= false) or false
end

function CDMIcons.ShouldUseBuffSwipeForIcon(icon, entry)
    if not _showBuffSwipe then return false end
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

local function WipeUpdateTickCaches(forceClear)
    BeginUpdateTickCaches(forceClear == true)
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
CDMIcons.GetChildIconTexture = GetChildIconTexture


---------------------------------------------------------------------------
-- ICON POOL MANAGEMENT
---------------------------------------------------------------------------
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
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            local itemName = C_Item.GetItemNameByID(itemID)
            spellEntry.name = itemName or ""
        end
    elseif entry.type == "item" then
        local itemName = C_Item.GetItemNameByID(entry.id)
        spellEntry.name = itemName or ""
    else
        spellEntry.name = GetCachedSpellName(entry.id) or ""
    end
    if CDMIcons.DebugEntryBuild then
        CDMIcons.DebugEntryBuild(entry, spellEntry, viewerType)
    end
    return spellEntry
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
            local positioned = {}
            local unpositioned = {}
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

    -- Fallback _blizzChild resolution: if ResolveOwnedEntry couldn't find
    -- a viewer child (e.g., _spellIDToChild wasn't populated yet), retry
    -- now.  Also handles custom entries from GetCustomData which skip
    -- ResolveOwnedEntry entirely. Custom containers can mix aura and
    -- cooldown entries, so resolve the child per entry kind instead of from
    -- the container shape.
    if ns.CDMSpellData then
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
                    if IsAuraEntry(entry) and ns.CDMSpellData.FindBuffChildForSpell then
                        entry._blizzChild = ns.CDMSpellData.FindBuffChildForSpell(
                            entry.viewerType,
                            searchIDs[1],
                            searchIDs[2],
                            searchIDs[3]
                        )
                    end

                    if not entry._blizzChild then
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
    end

    -- Bind owned cooldown frames through the resolver and attach texture hooks
    -- for spell-replacement icon changes. Blizzard CooldownFrames stay
    -- untouched; ApplyResolvedCooldown is the only swipe writer.
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
            local ok, count = pcall(C_Item.GetItemCount, entry.id, false, false)
            if ok and (not count or count <= 0) then return true end
        elseif entry.type == "trinket" or entry.type == "slot" then
            local equippedItemID = GetInventoryItemID("player", entry.id)
            if not equippedItemID then return true end
            -- Trinket slots (13/14): also hide passive trinkets — those without
            -- an on-use spell — under hideNonUsable. The slot is tracked rather
            -- than a specific item, so a stat-stick equipped in slot 13 would
            -- otherwise sit visible forever with nothing to display.
            if entry.id == 13 or entry.id == 14 then
                if C_Item and C_Item.GetItemSpell then
                    local okS, spellName = pcall(C_Item.GetItemSpell, equippedItemID)
                    if okS and not spellName then return true end
                end
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

-- Per-container dirty set. When the runtime visibility update detects that an
-- icon's filter verdict has flipped versus the last layout pass (e.g. mana-tea
-- becoming usable mid-combat with hideNonUsable enabled), it marks the
-- container here. After the per-icon loop in UpdateAllCooldowns /
-- UpdateCooldownOnly we drain the set and call LayoutContainer for each entry
-- so the bar collapses or expands around the slot. With clickableIcons = false,
-- ShouldDeferContainerLayoutInCombat now permits the relayout to run in
-- combat instead of waiting for PLAYER_REGEN_ENABLED.
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
        SyncCooldownBling(icon)
        return
    end

    if editMode then
        icon:SetAlpha(1)
        icon:Show()
        SyncCooldownBling(icon)
        return
    end

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
        if CDMIcons.DebugIconEvent then
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
function CDMIcons:UpdateAllCooldowns(keepTickCaches)
    -- Wipe per-tick caches: each batch starts fresh so every spellID
    -- is queried at most once via TickCacheGetCharges/TickCacheGetCooldown.
    WipeUpdateTickCaches(true)
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
    _hoistedNcdm = _ncdm;  CDMIcons._hoistedNcdm = _ncdm  -- consumed by UpdateIconCooldown
    _batchTime = GetTime(); CDMIcons._batchTime = _batchTime  -- consumed by UpdateIconCooldown + visibility loop
    -- Hoist GCD swipe setting so per-icon code can check it without DB lookups.
    CDMIcons.RefreshSwipeBatchSettings()
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
                        if CDMIcons.DebugIconEvent then
                            CDMIcons.DebugIconEvent(icon, "show",
                                "shouldShow=", tostring(shouldShow),
                                "shown=", tostring(icon:IsShown()),
                                "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
                                "effectiveMode=", tostring(effectiveMode),
                                "filterHidden=", tostring(filterHidesNow),
                                "dynamic=", tostring(containerDB and containerDB.dynamicLayout))
                        end
                        CDMIcons.ApplyCustomBarActiveGlow(icon, containerDB, visibility)

                        if visibility.isActive and not containerDB.showOnlyOnCooldown and icon.Icon and icon.Icon.SetDesaturated then
                            icon.Icon:SetDesaturated(false)
                            icon._cdDesaturated = nil
                        end

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
        WipeUpdateTickCaches(true)
    end
end

function CDMIcons:UpdateCooldownOnly(keepTickCaches)
    WipeUpdateTickCaches(true)
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
        WipeUpdateTickCaches(true)
    end
end

function CDMIcons:UpdateCooldownsForType(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        local _ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
        _hoistedNcdm = _ncdm;  CDMIcons._hoistedNcdm = _ncdm
        _batchTime = GetTime(); CDMIcons._batchTime = _batchTime
        CDMIcons.RefreshSwipeBatchSettings()
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
    local cmd, rest = filter:match("^(%S+)%s*(.-)$")
    local lower = cmd and cmd:lower() or ""
    if filter == "" then
        _G.QUI_CDM_ICON_DEBUG = not _G.QUI_CDM_ICON_DEBUG
        print("|cff34D399[CDM-IconDebug]|r", _G.QUI_CDM_ICON_DEBUG and "ON (all icons)" or "OFF")
        return
    end
    if lower == "off" or lower == "0" or lower == "false" then
        _G.QUI_CDM_ICON_DEBUG = nil
        print("|cff34D399[CDM-IconDebug]|r OFF")
        return
    end
    if lower == "dump" then
        _G.QUI_CDM_ICON_DEBUG = (rest and rest ~= "") and rest or true
        print("|cff34D399[CDM-IconDebug]|r dump - filter:", tostring(_G.QUI_CDM_ICON_DEBUG))
        if DumpDebugIcon then
            CDMIcons:ForEachIcon(function(icon)
                DumpDebugIcon(icon)
            end)
        end
        return
    end
    if lower == "all" then
        _G.QUI_CDM_ICON_DEBUG = true
    else
        _G.QUI_CDM_ICON_DEBUG = filter
    end
    print("|cff34D399[CDM-IconDebug]|r ON - filter:", tostring(_G.QUI_CDM_ICON_DEBUG))
end

function CDMIcons.ShouldDebugSpell(spellID, spellName)
    local dbg = _G.QUI_CDM_ICON_DEBUG
    if not dbg then return false end
    if dbg == true then return true end
    local filter = tostring(dbg):lower()
    if spellID and tostring(spellID) == filter then return true end
    local name = spellName and tostring(spellName):lower() or ""
    return name ~= "" and name:find(filter, 1, true) ~= nil
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

function CDMIcons.DebugSpellEvent(spellID, spellName, label, ...)
    if not CDMIcons.ShouldDebugSpell(spellID, spellName) then return end
    print("|cff34D399[CDM-IconTrace]|r", tostring(label), tostring(spellName or "?"), "spellID=", tostring(spellID), ...)
end

function CDMIcons.DebugIconEvent(icon, label, ...)
    if not ShouldDebugIcon(icon) then return end
    local now = GetTime()
    icon._debugEventTimes = icon._debugEventTimes or {}
    local last = icon._debugEventTimes[label]
    if last and (now - last) < 0.25 then return end
    icon._debugEventTimes[label] = now
    local entry = icon._spellEntry
    print("|cff34D399[CDM-IconTrace]|r", tostring(label),
        entry and (entry.name or "?") or "?",
        "viewer=", entry and tostring(entry.viewerType) or "nil",
        "entryID=", entry and tostring(entry.id) or "nil",
        ...)
end

function CDMIcons.DebugEntryBuild(entry, spellEntry, viewerType)
    if not CDMIcons.ShouldDebugSpell(spellEntry and (spellEntry.spellID or spellEntry.id), spellEntry and spellEntry.name) then return end
    print("|cff34D399[CDM-IconTrace]|r", "build",
        spellEntry and (spellEntry.name or "?") or "?",
        "viewer=", tostring(viewerType),
        "entryType=", entry and tostring(entry.type) or "nil",
        "entryID=", entry and tostring(entry.id) or "nil",
        "spellID=", spellEntry and tostring(spellEntry.spellID) or "nil",
        "kind=", spellEntry and tostring(spellEntry.kind) or "nil",
        "isAura=", spellEntry and tostring(spellEntry.isAura) or "nil")
end

function CDMIcons.DebugLayoutFilter(icon, filterHides, settings, effectiveOnCD)
    CDMIcons.DebugIconEvent(icon, "layout-filter",
        "hide=", tostring(filterHides and true or false),
        "effectiveOnCD=", tostring(effectiveOnCD),
        "dynamic=", tostring(settings and settings.dynamicLayout),
        "containerType=", tostring(settings and settings.containerType),
        "showOnlyOnCooldown=", tostring(settings and settings.showOnlyOnCooldown))
end

DebugIconSwipe = function(icon, ...)
    if not ShouldDebugIcon(icon) then return end
    local entry = icon and icon._spellEntry
    print("|cff34D399[CDM-IconSwipe]|r",
        entry and (entry.name or "?") or "?",
        "viewer=", entry and tostring(entry.viewerType) or "nil",
        "entryID=", entry and tostring(entry.id) or "nil",
        ...)
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
        "alpha=", tostring(icon.GetAlpha and icon:GetAlpha() or nil),
        "auraActive=", tostring(icon._auraActive),
        "customActive=", tostring(icon._customBarActive),
        "hasCooldownActive=", tostring(icon._hasCooldownActive),
        "hasRealCooldown=", tostring(icon._hasRealCooldownActive),
        "isOnGCD=", tostring(icon._isOnGCD),
        "lastStart=", tostring(icon._lastStart),
        "lastDuration=", tostring(icon._lastDuration),
        "isTotemInstance=", tostring(icon._isTotemInstance),
        "entry._totemSlot=", tostring(entry._totemSlot),
        "icon._totemSlot=", tostring(icon._totemSlot),
        "instanceKey=", tostring(entry._instanceKey))
    local containerDB = GetTrackerSettings(entry.viewerType)
    if CDMIcons.IsCustomBarContainer(containerDB) then
        local visibility = CDMIcons.ComputeCustomBarVisibility(icon, entry, containerDB, GetTime())
        print(P, "  customVisibility mode=", tostring(visibility.visibilityMode),
            "layout=", tostring(visibility.layoutVisible),
            "render=", tostring(visibility.renderVisible),
            "usable=", tostring(visibility.isUsable),
            "onCD=", tostring(visibility.isOnCooldown),
            "recharge=", tostring(visibility.rechargeActive),
            "active=", tostring(visibility.isActive),
            "dynamic=", tostring(containerDB.dynamicLayout),
            "displayMode=", tostring(containerDB.iconDisplayMode))
    end
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
        local childApps, childAppsSource = CDMIcons.GetBlizzChildApplicationText(icon, entry)
        print(P, "  blizzChild applications source=", tostring(childAppsSource),
            "value=", tostring(Helpers.SafeValue(childApps, "secret")),
            "auraDataUnit=", tostring(Helpers.SafeValue(rawget(blz, "auraDataUnit"), "secret")))
        local iconApps = blz.Icon and blz.Icon.Applications
        if iconApps and iconApps.GetText then
            local okIconApps, iconAppsText = pcall(iconApps.GetText, iconApps)
            local okIconShown, iconAppsShown = pcall(iconApps.IsShown, iconApps)
            print(P, "  blizzChild.Icon.Applications text=",
                okIconApps and tostring(Helpers.SafeValue(iconAppsText, "secret")) or "err",
                "shown=", okIconShown and tostring(Helpers.SafeValue(iconAppsShown, "secret")) or "err")
        end
        local appFrame = blz.Applications
        local appText = appFrame and appFrame.Applications
        if appText and appText.GetText then
            local okAppText, appValue = pcall(appText.GetText, appText)
            local okAppShown, appShown = pcall(appText.IsShown, appText)
            print(P, "  blizzChild.Applications.Applications text=",
                okAppText and tostring(Helpers.SafeValue(appValue, "secret")) or "err",
                "shown=", okAppShown and tostring(Helpers.SafeValue(appShown, "secret")) or "err")
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
-- UNIT_AURA) handles all cooldown/aura state changes.
function CDMIcons:StartUpdateTicker() end  -- no-op (kept for API compat)
function CDMIcons:StopUpdateTicker() end   -- no-op

---------------------------------------------------------------------------
-- CONFIGURE ICON (public wrapper)
---------------------------------------------------------------------------
CDMIcons.ConfigureIcon = ConfigureIcon
CDMIcons.UpdateIconCooldown = UpdateIconCooldown
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
    if IsSecretValue(usable) then return true, false end
    if usable == false then return false, noMana == true end
    if usable == true then return true, noMana == true end
    return true, noMana == true
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

-- Apply the resolver-computed stack/charge text to icon.StackText.
-- Forwards values directly to FontString:SetText (secret-safe; never
-- compares the value in Lua). Records the source in icon._stackTextSource
-- so we can distinguish "text WE wrote" from "text some other path wrote"
-- on subsequent ticks. The resolver only clears text it owns — leaves
-- text from other writers (item-count branches in UpdateIconCooldown,
-- aura-backed-charge FWD path) alone. Without this gate, the resolver
-- and legacy paths fight on every tick (resolver runs on every range
-- poll; legacy paths run on cooldown events) and the text flickers.
local function ApplyIconStackTextFromResolver(icon)
    if not icon or not icon.StackText then return end
    local text, source = CDMIcons.ResolveIconStackText(icon)
    if text == nil then
        -- Only clear if WE last wrote. Don't stomp on item-count or
        -- aura-backed-charge text from other writers.
        if icon._stackTextSource == "Applications" or icon._stackTextSource == "ChargeCount" then
            pcall(icon.StackText.SetText, icon.StackText, "")
            pcall(icon.StackText.Hide, icon.StackText)
            icon._stackTextSource = nil
        end
        return
    end
    pcall(icon.StackText.SetText, icon.StackText, text)
    pcall(icon.StackText.Show, icon.StackText)
    icon._stackTextSource = source
end

local function UpdateIconVisualState(icon, cachedDB)
    if not icon or not icon._spellEntry then return end
    ApplyIconStackTextFromResolver(icon)
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
    local cooldownVisualPriority = false

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
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
cdEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
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
    local trustIsOnGCD = CDMIcons._pendingTrustIsOnGCD == true
    CDMIcons._pendingTrustIsOnGCD = false

    if not CDMIcons:IsRuntimeEnabled() then
        WipeUpdateTickCaches(true)
        return
    end

    _lastCDMUpdateTime = GetTime()
    CDMIcons._trustIsOnGCDForBatch = trustIsOnGCD

    if mode == CDM_UPDATE_FULL then
        CDMIcons:UpdateAllCooldowns(true)
        if _barsDirty and ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
            _barsDirty = false
            ns.CDMBars:UpdateOwnedBars()
        end
    else
        CDMIcons:UpdateCooldownOnly(true)
    end

    CDMIcons._trustIsOnGCDForBatch = false
    WipeUpdateTickCaches(true)
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

local function ScheduleCDMUpdate(fast, mode, trustIsOnGCD)
    if not CDMIcons:IsRuntimeEnabled() then
        cdmUpdateFrame:SetScript("OnUpdate", nil)
        _cdmUpdatePending = false
        CDMIcons._pendingTrustIsOnGCD = false
        return
    end

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
        if trustIsOnGCD then
            CDMIcons._pendingTrustIsOnGCD = true
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
    CDMIcons._pendingTrustIsOnGCD = trustIsOnGCD == true
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
    if not CDMIcons:IsRuntimeEnabled() then
        self:SetScript("OnUpdate", nil)
        return
    end

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
    WipeUpdateTickCaches(true)
end

-- Walk every active icon and let the resolver drive icon.Cooldown.
-- ApplyResolvedCooldown binds via SetCooldownFromDurationObject (live C-side
-- binding) or guarded numeric item fallback; we re-bind only on source
-- transitions. Callers are coalesced. No per-tick re-applies.
local function ApplyResolvedCooldownAll()
    WipeUpdateTickCaches(true)
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon and icon._spellEntry then
                ApplyResolvedCooldown(icon)
            end
        end
    end
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

-- SPELL_UPDATE_COOLDOWN payload: { spellID, baseSpellID, category, startRecoveryCategory }.
-- When spellID is non-nil, only one spell changed — re-resolve icons whose base
-- matches spellID or baseSpellID instead of walking every icon. baseSpellID is set
-- by Blizzard when spellID is an override, so checking both covers base-keyed and
-- override-keyed icons without consulting (potentially secret) override caches.
local function ApplyResolvedCooldownForSpellID(eventSpellID, eventBaseSpellID)
    if not eventSpellID and not eventBaseSpellID then return end
    WipeUpdateTickCaches(true)
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry then
                local base = entry.spellID or entry.id
                if base and (base == eventSpellID or base == eventBaseSpellID) then
                    ApplyResolvedCooldown(icon)
                end
            end
        end
    end
end

function CDMIcons.NoteChargeDurationObjectsUpdated()
    CDMIcons._chargeDurationObjectSerial = (CDMIcons._chargeDurationObjectSerial or 0) + 1
end

function CDMIcons.EventTraceValue(value)
    if value == nil then return "nil" end
    if IsSecretValue(value) then return "secret" end
    return tostring(value)
end

function CDMIcons.EventTraceSpellIDMatches(targetID, value)
    if not targetID or value == nil then return false end
    return SafeToNumber(value, nil) == targetID
end

function CDMIcons.EventTraceIconMatches(icon, targetID)
    local entry = icon and icon._spellEntry
    if not entry or not targetID then return false end
    if CDMIcons.EventTraceSpellIDMatches(targetID, icon._runtimeSpellID) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.overrideSpellID) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.spellID) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.id) then return true end
    if CDMIcons.EventTraceSpellIDMatches(targetID, entry.itemID) then return true end
    if (entry.type == "trinket" or entry.type == "slot") and GetInventoryItemID then
        local itemID = GetInventoryItemID("player", entry.id)
        if CDMIcons.EventTraceSpellIDMatches(targetID, itemID) then return true end
    end
    return false
end

function CDMIcons.EventTraceItemUseSpellMatches(targetID, value)
    if not targetID or value == nil then return false end
    local spellID = SafeToNumber(value, nil)
    if not spellID then return false end

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if CDMIcons.EventTraceIconMatches(icon, targetID)
               and CDMIcons.IsItemLikeEntry(entry) then
                local _, _, itemSpellID = CDMIcons.ResolveItemCooldownIdentity(entry)
                if itemSpellID == spellID then
                    return true
                end
            end
        end
    end
    return false
end

function CDMIcons.EventTraceShouldPrintFrameEvent(event, arg1, arg2, arg3)
    local targetID = CDMIcons._eventTraceSpellID
    if not targetID then return false end

    if event == "UNIT_SPELLCAST_START"
       or event == "UNIT_SPELLCAST_STOP"
       or event == "UNIT_SPELLCAST_SUCCEEDED"
       or event == "UNIT_SPELLCAST_CHANNEL_START"
       or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        return arg1 == "player" and (
            CDMIcons.EventTraceSpellIDMatches(targetID, arg2)
            or CDMIcons.EventTraceSpellIDMatches(targetID, arg3)
            or CDMIcons.EventTraceItemUseSpellMatches(targetID, arg2)
            or CDMIcons.EventTraceItemUseSpellMatches(targetID, arg3)
        )
    end

    return true
end

function CDMIcons.EventTraceIconSummary(targetID)
    local parts = {}
    local matches = 0
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if CDMIcons.EventTraceIconMatches(icon, targetID) then
                matches = matches + 1
                if #parts < 3 then
                    local entry = icon._spellEntry
                    local shown = icon.IsShown and icon:IsShown() and "shown" or "hidden"
                    parts[#parts + 1] = string.format(
                        "%s/%s %s mode=%s aura=%s cd=%s real=%s gcd=%s key=%s",
                        tostring(entry.name or "?"),
                        tostring(entry.viewerType or "?"),
                        shown,
                        tostring(icon._resolvedCooldownMode),
                        tostring(icon._auraActive == true),
                        tostring(icon._hasCooldownActive == true),
                        tostring(icon._hasRealCooldownActive == true),
                        tostring(icon._showingGCDSwipe == true),
                        tostring(icon._lastDurObjKey))
                end
            end
        end
    end
    if matches == 0 then return "icons=0" end
    local more = matches > #parts and string.format(" +%d more", matches - #parts) or ""
    return string.format("icons=%d [%s%s]", matches, table.concat(parts, " | "), more)
end

function CDMIcons.EventTraceAPISummary(spellID)
    local cdActive, cdOnGCD = nil, nil
    local chargeActive, currentCharges, maxCharges = nil, nil, nil
    local usable, noMana = nil, nil
    local itemStart, itemDuration, itemEnabled = nil, nil, nil
    local itemSpellID = CDMIcons.GetItemUseSpellID(spellID)
    local itemSpellCdActive, itemSpellCdOnGCD = nil, nil

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and cdInfo then
            cdActive = CDMIcons.GetCooldownInfoField(cdInfo, "isActive")
            cdOnGCD = cdInfo.isOnGCD
        end
        if itemSpellID then
            local okItemSpell, itemSpellCdInfo = pcall(C_Spell.GetSpellCooldown, itemSpellID)
            if okItemSpell and itemSpellCdInfo then
                itemSpellCdActive = CDMIcons.GetCooldownInfoField(itemSpellCdInfo, "isActive")
                itemSpellCdOnGCD = itemSpellCdInfo.isOnGCD
            end
        end
    end
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, chargeInfo = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and chargeInfo then
            chargeActive = chargeInfo.isActive
            currentCharges = chargeInfo.currentCharges
            maxCharges = chargeInfo.maxCharges
        end
    end
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, isUsable, isNoMana = pcall(C_Spell.IsSpellUsable, spellID)
        if ok then
            usable = isUsable
            noMana = isNoMana
        end
    end
    if C_Item and C_Item.GetItemCooldown then
        local ok, startTime, duration, enabled = pcall(C_Item.GetItemCooldown, spellID)
        if ok then
            itemStart = startTime
            itemDuration = duration
            itemEnabled = enabled
        end
    end

    return string.format(
        "api cdActive=%s isOnGCD=%s charges=%s/%s chargeActive=%s usable=%s noMana=%s itemCd=%s/%s/%s itemSpell=%s itemSpellCd=%s/%s",
        CDMIcons.EventTraceValue(cdActive),
        CDMIcons.EventTraceValue(cdOnGCD),
        CDMIcons.EventTraceValue(currentCharges),
        CDMIcons.EventTraceValue(maxCharges),
        CDMIcons.EventTraceValue(chargeActive),
        CDMIcons.EventTraceValue(usable),
        CDMIcons.EventTraceValue(noMana),
        CDMIcons.EventTraceValue(itemStart),
        CDMIcons.EventTraceValue(itemDuration),
        CDMIcons.EventTraceValue(itemEnabled),
        CDMIcons.EventTraceValue(itemSpellID),
        CDMIcons.EventTraceValue(itemSpellCdActive),
        CDMIcons.EventTraceValue(itemSpellCdOnGCD))
end

function CDMIcons.EventTraceAuraInfo(updateInfo)
    if type(updateInfo) ~= "table" then return "auraInfo=nil" end
    local added = type(updateInfo.addedAuras) == "table" and #updateInfo.addedAuras or 0
    local updated = type(updateInfo.updatedAuraInstanceIDs) == "table" and #updateInfo.updatedAuraInstanceIDs or 0
    local removed = type(updateInfo.removedAuraInstanceIDs) == "table" and #updateInfo.removedAuraInstanceIDs or 0
    return string.format(
        "aura full=%s added=%d updated=%d removed=%d",
        CDMIcons.EventTraceValue(updateInfo.isFullUpdate),
        added, updated, removed)
end

function CDMIcons.EventTracePrint(source, event, arg1, arg2, arg3, extra)
    local targetID = CDMIcons._eventTraceSpellID
    if not targetID then return end
    local frameSource = source == "frame" or source == "frame-pre" or source == "frame-post"
    if frameSource and not CDMIcons.EventTraceShouldPrintFrameEvent(event, arg1, arg2, arg3) then
        return
    end

    local now = GetTime and GetTime() or 0
    local start = CDMIcons._eventTraceStartedAt or now
    print(string.format(
        "|cff34d399[cdmevents]|r +%.3f sid=%d %s:%s args=(%s,%s,%s) %s %s %s",
        now - start,
        targetID,
        tostring(source or "?"),
        tostring(event or "?"),
        CDMIcons.EventTraceValue(arg1),
        CDMIcons.EventTraceValue(arg2),
        CDMIcons.EventTraceValue(arg3),
        CDMIcons.EventTraceAPISummary(targetID),
        CDMIcons.EventTraceIconSummary(targetID),
        extra or ""))
end

function CDMIcons.EventFrameOnEvent(self, event, arg1, arg2, arg3)
    if not CDMIcons:IsRuntimeEnabled() then
        self:SetScript("OnUpdate", nil)
        cdmUpdateFrame:SetScript("OnUpdate", nil)
        safetyTickFrame:SetScript("OnUpdate", nil)
        _cdmUpdatePending = false
        return
    end

    if event == "UNIT_SPELLCAST_START"
       or event == "UNIT_SPELLCAST_STOP"
       or event == "UNIT_SPELLCAST_SUCCEEDED"
       or event == "UNIT_SPELLCAST_CHANNEL_START"
       or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if arg1 == "player" then
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                CDMIcons.RecordRecentPlayerSpellCast(arg3)
                -- Player-self event: spellID is non-secret. Re-bind every
                -- icon's Cooldown to the resolver's source DurObj so the cast
                -- spell's CD takes hold and other icons pick up the GCD
                -- overlay. SetCooldownFromDurationObject creates a live
                -- C-side binding; we only need to re-bind on source change.
                -- Invalidate gcd-only dedupe keys first: the next pulse uses
                -- the same key as the previous one, so without this the
                -- cooldown frame would stay bound to the (already-expired)
                -- previous pulse's DurationObject.
                InvalidateGCDOnlyBindings()
                ApplyResolvedCooldownAll()
            end
            ScheduleCDMUpdate(true, CDM_UPDATE_COOLDOWN)
        end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        ChargeDebug(nil, "EVENT", event, "full-refresh")
        CDMIcons:UpdateAllIconRanges()
        -- Target debuffs (e.g. Reaper's Mark) need a CDM refresh when target changes
        ns.CDMSpellData:InvalidateChildMap()
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        return
    end
    if event == "PLAYER_SOFT_ENEMY_CHANGED" then
        ChargeDebug(nil, "EVENT", event, "full-refresh")
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
            ApplyResolvedCooldownAll()
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
        return
    end
    if event == "UPDATE_MACROS" then
        InvalidateMacroCache()
        return
    end
    if event == "SPELL_UPDATE_USABLE" then
        -- Fires when a spell's usability changes — including when a CD ends
        -- (SPELL_UPDATE_COOLDOWN doesn't fire on CD-end). Re-resolve every
        -- icon so stale _hasCooldownActive flags from completed CDs clear.
        ApplyResolvedCooldownAll()
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
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        -- Both events carry a non-nil spellID (Nilable=false in the live FrameXML
        -- payload). At most one spell's cooldown state can be affected by a proc,
        -- so re-resolve only matching icons instead of triggering a full batch.
        -- glows.lua's dedicated handler owns the visual glow side.
        if arg1 then
            ApplyResolvedCooldownForSpellID(arg1, nil)
        end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Payload: (unitTarget, castGUID, spellID, castBarID). Filtered to
        -- "player" via RegisterUnitEvent; explicit arg1 check is a belt-and-
        -- suspenders guard. Player's spellID is non-restricted-scope so safe
        -- to compare against icon entries. Highlighter consumes the same
        -- event via dispatch — single registration, two consumers.
        if arg1 == "player" and arg3 then
            ApplyResolvedCooldownForSpellID(arg3, nil)
            local Highlighter = ns._OwnedHighlighter
            if Highlighter and Highlighter.OnPlayerCastSucceeded then
                Highlighter.OnPlayerCastSucceeded(arg3)
            end
        end
        return
    end
    local trustIsOnGCD = event == "SPELL_UPDATE_COOLDOWN"
    if event == "SPELL_UPDATE_CHARGES" then
        CDMIcons.NoteChargeDurationObjectsUpdated()
    end
    local gcdChanged = false
    if trustIsOnGCD then
        gcdChanged = CDMIcons.CaptureTrustedGCDState()
    end
    -- Coalesce cooldown events via the reusable update frame. isOnGCD is
    -- only trusted for batches caused by SPELL_UPDATE_COOLDOWN.
    ScheduleCDMUpdate(nil, CDM_UPDATE_COOLDOWN, trustIsOnGCD)
    -- Per-icon resolver walk. Single-spell SPELL_UPDATE_COOLDOWN fires can be
    -- scoped to matching icons. Three cases force a full walk:
    --   1. arg1 == nil — Blizzard's "update all" signal
    --   2. arg1 == GCD_SPELL_ID (61304) — explicit GCD spell signal
    --   3. gcdChanged — any icon's _isOnGCD just flipped
    if trustIsOnGCD then
        CDMIcons._trustIsOnGCDForBatch = true
        if arg1 and arg1 ~= GCD_SPELL_ID and not gcdChanged then
            ApplyResolvedCooldownForSpellID(arg1, arg2)
        else
            -- arg1 == GCD_SPELL_ID or gcdChanged or arg1 == nil all signal a
            -- new GCD pulse may be starting. Invalidate gcd-only dedupe keys
            -- so the rebind path runs (key matches across pulses; without
            -- this the cooldown frame stays on the prior pulse's timer).
            InvalidateGCDOnlyBindings()
            ApplyResolvedCooldownAll()
        end
        CDMIcons._trustIsOnGCDForBatch = false
    elseif event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_COOLDOWN" then
        ApplyResolvedCooldownAll()
    end
end

cdEventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    CDMIcons.EventTracePrint("frame-pre", event, arg1, arg2, arg3)
    CDMIcons.EventFrameOnEvent(self, event, arg1, arg2, arg3)
    CDMIcons.EventTracePrint("frame-post", event, arg1, arg2, arg3)
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
            if not CDMIcons:IsRuntimeEnabled() then return end
            CDMIcons.EventTracePrint("registry", "CooldownViewerSettings.OnDataChanged")
            ns.CDMSpellData:InvalidateChildMap()
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        end,
        "QUI_CDMIcons")
end

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_Icons", frame = cdEventFrame }

-- Exporters for /qui cdm_cache reset / status.
function CDMIcons:ClearTextureCycleCache()
    wipe(_textureCycleCache)
end

function CDMIcons:ClearTickCaches()
    ClearUpdateTickCaches()
end

function CDMIcons:RequestFullUpdate()
    if not CDMIcons:IsRuntimeEnabled() then return end
    _barsDirty = true
    ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
end

function CDMIcons:GetCacheStats()
    local n = 0
    for _ in pairs(_textureCycleCache) do n = n + 1 end
    return {
        textureCycleCache = n,
        barsDirty         = _barsDirty and true or false,
        updatePending     = _cdmUpdatePending and true or false,
    }
end

-- Subscribe to centralized aura dispatcher for prompt icon updates.
-- Player auras via "player" filter (avoids callback for all 20+ raid units).
-- Target debuffs via "all" filter (no "target" filter in the dispatcher).
-- Aura events set _barsDirty so UpdateOwnedBars (aura-state driven) runs next
-- coalesce tick. Pure cooldown events (SPELL_UPDATE_COOLDOWN path at
-- cdEventFrame:OnEvent) deliberately do NOT set the flag — bar fill is driven
-- by barTimerGroup independently of ScheduleCDMUpdate.
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
        if not CDMIcons:IsRuntimeEnabled() then return end
        CDMIcons.EventTracePrint("aura-pre", "UNIT_AURA", unit, nil, nil, CDMIcons.EventTraceAuraInfo(updateInfo))
        ns.CDMSpellData:InvalidateChildMap()
        _barsDirty = true
        ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
        ApplyResolvedCooldownAll()
        CDMIcons.EventTracePrint("aura-post", "UNIT_AURA", unit, nil, nil, CDMIcons.EventTraceAuraInfo(updateInfo))
    end)
    ns.AuraEvents:Subscribe("all", function(unit, updateInfo)
        if not CDMIcons:IsRuntimeEnabled() then return end
        if unit == "target" then
            CDMIcons.EventTracePrint("aura-pre", "UNIT_AURA", unit, nil, nil, CDMIcons.EventTraceAuraInfo(updateInfo))
            ns.CDMSpellData:InvalidateChildMap()
            _barsDirty = true
            ScheduleCDMUpdate(true, CDM_UPDATE_FULL)
            ApplyResolvedCooldownAll()
            CDMIcons.EventTracePrint("aura-post", "UNIT_AURA", unit, nil, nil, CDMIcons.EventTraceAuraInfo(updateInfo))
        end
    end)
end

-- Visual state polling: 250ms OnUpdate for range + usability checks.
-- Only active when at least one tracker has rangeIndicator or usabilityIndicator.
local function RangePollOnUpdate(self, elapsed)
    if not CDMIcons:IsRuntimeEnabled() then
        self:SetScript("OnUpdate", nil)
        rangePollActive = false
        return
    end

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
    if not CDMIcons:IsRuntimeEnabled() then
        rangePollActive = false
        cdEventFrame:SetScript("OnUpdate", nil)
        return
    end

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

function CDMIcons:DisableRuntime()
    cdEventFrame:UnregisterAllEvents()
    cdEventFrame:SetScript("OnEvent", nil)
    cdEventFrame:SetScript("OnUpdate", nil)
    cdmUpdateFrame:SetScript("OnUpdate", nil)
    safetyTickFrame:SetScript("OnUpdate", nil)
    _cdmUpdatePending = false
    rangePollActive = false
    _barsDirty = false
    WipeUpdateTickCaches(true)
end

---------------------------------------------------------------------------
-- /cdmprobe — Resolver parity probe. Walks every visible CDM icon and
-- prints (entry name, kind, resolver mode, mirror active?, parity?).
---------------------------------------------------------------------------
SLASH_CDMPROBE1 = "/cdmprobe"
SlashCmdList["CDMPROBE"] = function()
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmprobe]|r Owned engine not enabled.")
        return
    end

    local rows = 0
    local agree = 0
    local disagree = 0
    local resolverInactive = 0

    print("|cff34d399[cdmprobe]|r begin parity sweep")
    print("name | kind | mode | mActive | parity | rText | curText | textPar")

    for poolKey, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon and icon:IsShown() and icon._spellEntry then
                local entry = icon._spellEntry
                local name = entry.name or "?"
                local kind = entry.kind or "?"

                local durObj, mode, sourceID = CDMIcons.ResolveIconDurationObject(icon)
                local rText, rSource = CDMIcons.ResolveIconStackText(icon)
                local curText = icon.StackText and icon.StackText:GetText() or ""
                local textParity
                local rIsSecret = (rText ~= nil) and IsSecretValue(rText)
                local cIsSecret = (curText ~= nil) and IsSecretValue(curText)
                if rIsSecret or cIsSecret then
                    textParity = "secret"
                elseif (rText == nil or rText == "") and (curText == nil or curText == "") then
                    textParity = "OK"
                elseif rText == curText then
                    textParity = "OK"
                else
                    textParity = "MISMATCH"
                end
                local resolverActive = (mode ~= "inactive")
                local mirrorActive = icon._hasRealCooldownActive == true
                                  or icon._showingRealCooldownSwipe == true
                                  or icon._auraActive == true

                local parity
                if resolverActive == mirrorActive then
                    parity = "OK"
                    agree = agree + 1
                else
                    parity = "MISMATCH"
                    disagree = disagree + 1
                end
                if mode == "inactive" then
                    resolverInactive = resolverInactive + 1
                end

                rows = rows + 1
                local rTextDisplay = rIsSecret and "<secret>" or (rText == nil and "nil" or tostring(rText))
                local curTextDisplay = cIsSecret and "<secret>" or (curText == nil and "nil" or tostring(curText))
                print(string.format("%s | %s | %s | %s | %s | %s | %s | %s",
                    name, kind, mode,
                    mirrorActive and "yes" or "no",
                    parity,
                    rTextDisplay, curTextDisplay, textParity))

                -- Secret values can't be Lua-concatenated into the row above,
                -- but C_StringUtil.WrapString is AllowedWhenTainted and produces
                -- a (possibly-secret) string that AddMessage renders correctly.
                -- Emit one follow-up line per secret column so the actual value
                -- is visible during debugging.
                if rIsSecret and C_StringUtil and C_StringUtil.WrapString then
                    local ok, wrapped = pcall(C_StringUtil.WrapString, rText,
                        "  |cff888888\\_ rText[" .. name .. "]:|r ", "")
                    if ok and wrapped then
                        DEFAULT_CHAT_FRAME:AddMessage(wrapped)
                    end
                end
                if cIsSecret and C_StringUtil and C_StringUtil.WrapString then
                    local ok, wrapped = pcall(C_StringUtil.WrapString, curText,
                        "  |cff888888\\_ curText[" .. name .. "]:|r ", "")
                    if ok and wrapped then
                        DEFAULT_CHAT_FRAME:AddMessage(wrapped)
                    end
                end
            end
        end
    end

    print(string.format(
        "|cff34d399[cdmprobe]|r end — %d icons, %d agree, %d mismatch (%.1f%%), %d inactive",
        rows, agree, disagree,
        rows > 0 and (100 * agree / rows) or 0,
        resolverInactive))
end

---------------------------------------------------------------------------
-- /cdmflicker <spell name> — diagnose flicker by snapshotting icon state
-- every frame for 5 seconds. Logs only TRANSITIONS (when the captured
-- state changes), so output is compact. Used to trace which flag is
-- toggling sub-tick during the aura→cooldown transition.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- /cdmcharge <name> — Diagnostic for charge-spell recharge swipe issues.
-- Walks visible CDM icons, finds entries matching the name, prints the
-- relevant gates: hasCharges, classifier output, charge/cd DurObj presence.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- /cdmtrace <spell name> — Log every isActive/isOnGCD transition that
-- ApplyResolvedCooldown sees for the named spell. Empty name to clear.
---------------------------------------------------------------------------
SLASH_CDMEVENTS1 = "/cdmevents"
SlashCmdList["CDMEVENTS"] = function(msg)
    local text = msg and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" or text == "off" or text == "clear" then
        CDMIcons._eventTraceSpellID = nil
        CDMIcons._eventTraceStartedAt = nil
        print("|cffffaa00[cdmevents]|r cleared")
        return
    end

    local spellID = tonumber(text:match("^(%d+)"))
    if not spellID then
        print("|cffffaa00[cdmevents]|r Usage: /cdmevents <spellID>")
        return
    end
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmevents]|r Owned engine not enabled.")
        return
    end

    CDMIcons._eventTraceSpellID = spellID
    CDMIcons._eventTraceStartedAt = GetTime and GetTime() or 0
    print(string.format(
        "|cff34d399[cdmevents]|r tracing events for spellID %d. Use /cdmevents off to stop.",
        spellID))
    print("|cff34d399[cdmevents]|r " .. CDMIcons.EventTraceAPISummary(spellID))
    print("|cff34d399[cdmevents]|r " .. CDMIcons.EventTraceIconSummary(spellID))
end

SLASH_CDMTRACE1 = "/cdmtrace"
SlashCmdList["CDMTRACE"] = function(msg)
    local name = msg and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then
        CDMIcons._desatTraceName = nil
        for _, pool in pairs(iconPools) do
            for _, icon in ipairs(pool) do
                if icon then icon._desatTracePrev = nil end
            end
        end
        print("|cffffaa00[cdmtrace]|r cleared")
        return
    end
    CDMIcons._desatTraceName = name
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon then icon._desatTracePrev = nil end
        end
    end
    print("|cff34d399[cdmtrace]|r tracing transitions for '" .. name .. "'")
end

SLASH_CDMCHARGE1 = "/cdmcharge"
SlashCmdList["CDMCHARGE"] = function(msg)
    local name = msg and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then
        print("|cffffaa00[cdmcharge]|r Usage: /cdmcharge <spell name>")
        return
    end
    local matches = 0
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            local entry = icon and icon._spellEntry
            if entry and entry.name == name then
                matches = matches + 1
                local sid = icon._runtimeSpellID
                    or entry.overrideSpellID or entry.spellID or entry.id
                local apiA, realA, onGCD = CDMIcons.ClassifySpellCooldownState(sid)
                local chargeDur = C_Spell and C_Spell.GetSpellChargeDuration
                    and C_Spell.GetSpellChargeDuration(sid)
                local cdDur = C_Spell and C_Spell.GetSpellCooldownDuration
                    and C_Spell.GetSpellCooldownDuration(sid)
                print(string.format(
                    "|cff34d399[cdmcharge]|r %s sid=%s hasCharges=%s apiA=%s realA=%s onGCD=%s chargeDur=%s cdDur=%s",
                    tostring(entry.name), tostring(sid),
                    tostring(entry.hasCharges),
                    tostring(apiA), tostring(realA), tostring(onGCD),
                    chargeDur and "yes" or "nil",
                    cdDur and "yes" or "nil"))
            end
        end
    end
    if matches == 0 then
        print("|cffffaa00[cdmcharge]|r no icon found with name '" .. name .. "'")
    end
end

SLASH_CDMFLICKER1 = "/cdmflicker"
SlashCmdList["CDMFLICKER"] = function(msg)
    local name = msg and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then
        print("|cffffaa00[cdmflicker]|r Usage: /cdmflicker <spell name>")
        return
    end
    if not CDMIcons:IsRuntimeEnabled() then
        print("|cffffaa00[cdmflicker]|r Owned engine not enabled.")
        return
    end

    local target
    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
            if icon and icon._spellEntry and icon._spellEntry.name == name then
                target = icon
                break
            end
        end
        if target then break end
    end
    if not target then
        print("|cffffaa00[cdmflicker]|r Icon not found: " .. name)
        return
    end

    print(string.format(
        "|cff34d399[cdmflicker]|r logging '%s' for 5s — cast the spell NOW so the flicker happens within the window",
        name))

    local samples = {}
    local lastSig = nil
    local startTime = GetTime()
    local frame = CreateFrame("Frame")

    local function snapshot()
        local now = GetTime() - startTime
        local entry = target._spellEntry
        local bc = entry and entry._blizzChild
        local _, rMode = CDMIcons.ResolveIconDurationObject(target)

        local sig = string.format(
            "aA=%s wSFA=%s sRC=%s hRC=%s sGCD=%s rMode=%s",
            tostring(target._auraActive),
            tostring(bc and bc.wasSetFromAura),
            tostring(target._showingRealCooldownSwipe),
            tostring(target._hasRealCooldownActive),
            tostring(target._showingGCDSwipe),
            tostring(rMode))

        if sig ~= lastSig then
            samples[#samples+1] = string.format("+%.3f  %s", now, sig)
            lastSig = sig
        end

        if now > 5 then
            frame:SetScript("OnUpdate", nil)
            print(string.format(
                "|cff34d399[cdmflicker]|r '%s' end — %d transitions over 5s",
                name, #samples))
            for _, s in ipairs(samples) do
                print(s)
            end
        end
    end

    frame:SetScript("OnUpdate", snapshot)
end

---------------------------------------------------------------------------
-- LATE-BIND CROSS-FILE IMPORTS
-- cdm_resolvers.lua and cdm_icon_factory.lua load before this file (per
-- owned.xml) and cannot capture ns.CDMIcons at their own load time. They
-- declare the upvalues uninitialized; here we hand them the populated
-- CDMIcons table after every `CDMIcons.X = X` exposure above has run.
---------------------------------------------------------------------------
ns.CDMResolvers._FinalizeImports(CDMIcons)
ns.CDMIconFactory._FinalizeImports(CDMIcons)
