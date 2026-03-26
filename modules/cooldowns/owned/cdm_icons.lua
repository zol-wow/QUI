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
local C_CooldownViewer = C_CooldownViewer
local C_StringUtil = C_StringUtil
local issecretvalue = issecretvalue

local function IsSafeNumeric(val)
    if IsSecretValue(val) then return false end
    return type(val) == "number"
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

-- TAINT SAFETY: Blizzard stack/charge text hook state tracked in a weak-keyed
-- table.  Maps Blizzard _blizzChild → { icon, chargeVisible, appVisible, hooked }.
-- Hooks on Show/Hide/SetText receive parameters from Blizzard's secure calling
-- code — not tainted — unlike polling IsShown()/GetText() on the alpha=0 viewer
-- children which always returns QUI-tainted secret values.
local blizzStackState = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- PER-TICK CACHES: wiped at the start of each UpdateAllCooldowns batch.
-- Avoids redundant C API calls when the same spellID appears in multiple
-- containers or is queried by both GetBestSpellCooldown and stack/visibility.
---------------------------------------------------------------------------
local _tickChargeCache = {}   -- [spellID] = chargeInfo or false
local _tickCooldownCache = {} -- [spellID] = cdInfo or false

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
    local cached = _tickChargeCache[spellID]
    if cached ~= nil then return cached or nil end
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID) or nil
    _tickChargeCache[spellID] = chargeInfo or false
    -- Persist multi-charge detection OOC for combat fallback
    if chargeInfo and not InCombatLockdown() then
        local maxC = SafeToNumber(chargeInfo.maxCharges, nil)
        if maxC and maxC > 1 then
            local svDB = GetChargeMetadataDB()
            if svDB then svDB[spellID] = maxC end
        end
    end
    return chargeInfo
end

local function TickCacheGetCooldown(spellID)
    local cached = _tickCooldownCache[spellID]
    if cached ~= nil then return cached or nil end
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    _tickCooldownCache[spellID] = cdInfo or false
    return cdInfo
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

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local GetDB = Helpers.CreateDBGetter("ncdm")

local function GetCustomData(trackerKey)
    if QUICore and QUICore.db and QUICore.db.char and QUICore.db.char.ncdm
        and QUICore.db.char.ncdm[trackerKey] and QUICore.db.char.ncdm[trackerKey].customEntries then
        return QUICore.db.char.ncdm[trackerKey].customEntries
    end
    return nil
end

---------------------------------------------------------------------------
-- TEXTURE HELPERS
---------------------------------------------------------------------------
-- Per-cycle texture cache: wiped once per UpdateAllCooldowns batch so
-- each spellID→iconID lookup happens at most once per tick, not per-icon.
local _textureCycleCache = {}

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
    if entry.type == "trinket" then
        -- Trinket entries store the equipment slot number (13/14), not the item ID.
        -- Resolve to the actual equipped item ID before looking up the icon.
        local itemID = GetInventoryItemID("player", entry.id)
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
        local chargeActive = false
        if chargeInfo.isActive ~= nil then
            chargeActive = chargeInfo.isActive == true
        else
            local currentCharges = SafeToNumber(chargeInfo.currentCharges, 0)
            local maxCharges = SafeToNumber(chargeInfo.maxCharges, 0)
            chargeActive = currentCharges < maxCharges
        end
        if chargeActive then
            bestStart, bestDuration, secretStart, secretDuration, bestDurObj =
                AccumulateCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo,
                    bestStart, bestDuration, secretStart, secretDuration, bestDurObj)
        end
    end

    -- Check override spell (no table allocation — just a second ID)
    if C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(spellID)
        if overrideID and overrideID ~= spellID then
            cdInfo = TickCacheGetCooldown(overrideID)
            if cdInfo then
                bestStart, bestDuration, secretStart, secretDuration, bestDurObj =
                    AccumulateCooldown(cdInfo.startTime, cdInfo.duration, cdInfo,
                        bestStart, bestDuration, secretStart, secretDuration, bestDurObj)
            end
            chargeInfo = TickCacheGetCharges(overrideID)
            if chargeInfo then
                local chargeActive2 = false
                if chargeInfo.isActive ~= nil then
                    chargeActive2 = chargeInfo.isActive == true
                else
                    local cc = SafeToNumber(chargeInfo.currentCharges, 0)
                    local mc = SafeToNumber(chargeInfo.maxCharges, 0)
                    chargeActive2 = cc < mc
                end
                if chargeActive2 then
                    bestStart, bestDuration, secretStart, secretDuration, bestDurObj =
                        AccumulateCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo,
                            bestStart, bestDuration, secretStart, secretDuration, bestDurObj)
                end
            end
        end
    end

    -- DurationObject APIs (12.0+, secret-safe).  These return objects that
    -- can be forwarded directly to SetCooldownFromDurationObject without
    -- reading values in Lua — the Blizzard-blessed path for addon code.
    -- Gate: only query when a cooldown is known active.  12.0.5+ returns
    -- zero-span DurationObjects for inactive spells.
    local hasActiveCooldown = bestStart or secretStart
    if not bestDurObj and hasActiveCooldown then
        -- Check charge duration FIRST — for charged spells, the charge
        -- recharge DurationObject is what we want to display, not the
        -- spell's own cooldown DurationObject (which may be a shorter
        -- per-use CD or GCD).  GetSpellChargeDuration returns the
        -- recharge timer DurationObject, secret-safe for combat.
        if C_Spell.GetSpellChargeDuration then
            local ok, durObj = pcall(C_Spell.GetSpellChargeDuration, spellID)
            if ok and durObj then bestDurObj = durObj end
        end
        if not bestDurObj and C_Spell.GetOverrideSpell and C_Spell.GetSpellChargeDuration then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID then
                local ok, durObj = pcall(C_Spell.GetSpellChargeDuration, overrideID)
                if ok and durObj then bestDurObj = durObj end
            end
        end
        -- Fall back to spell cooldown duration (non-charged spells)
        if not bestDurObj and C_Spell.GetSpellCooldownDuration then
            local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
            if ok and durObj then bestDurObj = durObj end
        end
        if not bestDurObj and C_Spell.GetOverrideSpell then
            local overrideID = C_Spell.GetOverrideSpell(spellID)
            if overrideID and overrideID ~= spellID and C_Spell.GetSpellCooldownDuration then
                local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, overrideID)
                if ok and durObj then bestDurObj = durObj end
            end
        end
    end
    -- Discard DurationObjects extracted from cdInfo when no source confirms
    -- an active cooldown.  12.0.5+ cooldown info tables may carry zero-span
    -- DurationObjects for ready-to-use spells.
    if not hasActiveCooldown then
        bestDurObj = nil
    end

    -- Prefer safe numeric values, then DurationObject, then hook cache
    if bestStart then
        return bestStart, bestDuration, bestDurObj
    end
    if bestDurObj then
        return nil, nil, bestDurObj
    end
    -- Secret fallback: no longer forward raw secrets to SetCooldown (12.0.5+).
    -- Try hook cache DurationObject from Blizzard viewer children.
    if secretStart and ns.CDMSpellData and ns.CDMSpellData.GetCachedDurObj then
        local hookDurObj = ns.CDMSpellData:GetCachedDurObj(spellID)
        if hookDurObj then
            return nil, nil, hookDurObj
        end
    end
    return nil, nil, nil
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

-- Expose for external use
CDMIcons.GetBestSpellCooldown = GetBestSpellCooldown

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

local function GetIconCooldownIdentifier(icon)
    local entry = icon and icon._spellEntry
    if not entry then return nil end
    return entry.overrideSpellID or entry.spellID or entry.id
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
                    synced = pcall(addonCD.SetCooldown, addonCD, start, duration)
                elseif duration == 0 or not enabled then
                    addonCD:Clear()
                    synced = true
                end
            end
        end
    end

    if not synced and addonCD.SetCooldownFromDurationObject then
        local entry = icon._spellEntry
        if entry and entry.viewerType ~= "buff" then
            local startTime, duration, durObj = GetBestSpellCooldown(GetIconCooldownIdentifier(icon))
            if durObj then
                synced = pcall(addonCD.SetCooldownFromDurationObject, addonCD, durObj, false)
            elseif IsSafeNumeric(startTime) and IsSafeNumeric(duration) and duration > 0 then
                synced = pcall(addonCD.SetCooldown, addonCD, startTime, duration)
            end
        end
    end

    SyncMirroredCooldownState(icon, blizzCD, synced)
    RefreshIconGCDState(icon)
    return synced
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
                local cd = targetIcon.Cooldown
                local tSkipCharge = tEntry and tEntry.hasCharges

                if not tSkipCharge and cd and cd.SetCooldownFromDurationObject then
                    pcall(cd.SetCooldownFromDurationObject, cd, durationObj)
                end

                if not tSkipCharge then
                    SyncMirroredCooldownState(targetIcon, self, true)
                end
                RefreshIconGCDState(targetIcon)

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

            -- Mirror to addon-owned CD.
            -- Skip for charged entries (same reason as durObj hook above).
            local cd = targetIcon.Cooldown
            local tSkipCharge2 = tEntry and tEntry.hasCharges
            if not tSkipCharge2 and cd and IsSafeNumeric(start) and IsSafeNumeric(duration)
               and start > 0 and duration > 0 then
                pcall(cd.SetCooldown, cd, start, duration)
            end


            if not tSkipCharge2 then
                SyncMirroredCooldownState(targetIcon, self, IsSafeNumeric(start) and IsSafeNumeric(duration) and start > 0 and duration > 0)
            end
            RefreshIconGCDState(targetIcon)

            ReapplySwipeStyle(cd, targetIcon)
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
            if quiIcon.Icon and texture then
                quiIcon.Icon:SetTexture(texture)
            end
        end)

        -- Mirror desaturation from Blizzard's icon so our icon reflects
        -- the same visual state without needing API calls in combat.
        hooksecurefunc(iconRegion, "SetDesaturated", function(self, desaturated)
            local s = blizzTexState[self]
            if not s or not s.icon then return end
            local quiIcon = s.icon
            if not quiIcon.Icon then return end
            local entry = quiIcon._spellEntry
            if not entry then return end
            local viewerType = entry.viewerType
            if viewerType == "buff" or quiIcon._auraActive then
                return
            end
            local db = GetDB()
            local settings = db and db[viewerType]
            if settings and settings.desaturateOnCooldown then
                quiIcon.Icon:SetDesaturated(desaturated)
            end
        end)
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

local function SyncStackText(state)
    local icon = state.icon
    if not icon then return end
    -- Stale mapping guard: if the icon was remapped to a different
    -- Blizzard child, this state is orphaned — skip to prevent
    -- cross-icon stack contamination.
    if state.blizzChild then
        local entry = icon._spellEntry
        if entry and entry._blizzChild and entry._blizzChild ~= state.blizzChild then
            return
        end
    end
    -- ChargeCount takes priority over Applications.
    -- chargeText/appText may be secret values (Blizzard passes them to
    -- SetText during combat) — forward to C-side SetText without comparing.
    -- Use pcall for the ~= "" check: secret values will error on comparison;
    -- if comparison fails, treat the value as non-empty (it's a secret number).
    local hasCharge = state.chargeText ~= nil
    if hasCharge then
        local eqOk, eqResult = pcall(function() return state.chargeText == "" end)
        if eqOk and eqResult then hasCharge = false end
    end
    local hasApp = state.appText ~= nil
    if hasApp and not hasCharge then
        local eqOk, eqResult = pcall(function() return state.appText == "" end)
        if eqOk and eqResult then hasApp = false end
    end

    -- Write when hooks provide actual content.  Only clear when
    -- transitioning from content → empty (e.g., charged child recycled
    -- to a non-charged spell).  Don't clear on repeated empty SetText
    -- calls — Blizzard spams SetText("") on ChargeCount.Current for
    -- every viewer child on every refresh (even buffs without charges),
    -- which would race with the API path and cause flicker.
    if hasCharge then
        pcall(icon.StackText.SetText, icon.StackText, state.chargeText)
        icon.StackText:Show()
        state._hookHadContent = true
    elseif hasApp then
        pcall(icon.StackText.SetText, icon.StackText, state.appText)
        icon.StackText:Show()
        state._hookHadContent = true
    elseif state._hookHadContent then
        -- Was showing content, now empty: legitimate clear
        -- (child recycled or charges consumed).
        icon.StackText:SetText("")
        icon.StackText:Hide()
        state._hookHadContent = false
    end
end

--- Check whether hooks are actively driving stack text for an icon.
--- When true, API-based stack writes in UpdateIconCooldown should yield
--- to avoid overwriting the hook-driven values (our event handler runs
--- after Blizzard's hooks, creating a race where the API path clears or
--- sets stacks that the hook just populated correctly).
local function IsHookStackActive(entry, icon)
    if not entry or not entry._blizzChild then return false end
    local bss = blizzStackState[entry._blizzChild]
    if not bss or bss.icon ~= icon then return false end
    -- chargeText/appText may be secret values — pcall the comparison.
    -- If comparison errors (secret), treat as non-empty (active).
    if bss.chargeText ~= nil then
        local ok, eq = pcall(function() return bss.chargeText == "" end)
        if not ok or not eq then return true end
    end
    if bss.appText ~= nil then
        local ok, eq = pcall(function() return bss.appText == "" end)
        if not ok or not eq then return true end
    end
    return false
end

local function HookBlizzStackText(icon, blizzChild)
    if not blizzChild then return end

    local state = blizzStackState[blizzChild]
    if not state then
        state = {}
        blizzStackState[blizzChild] = state
    end
    state.icon = icon
    state.blizzChild = blizzChild  -- Track child for stale mapping guard

    if not state.hooked then
        state.hooked = true

        -- Log what children exist on this blizzChild
        local chargeFrame = blizzChild.ChargeCount
        local appFrame = blizzChild.Applications
        -- Hook ChargeCount (e.g., DH Soul Fragments on Soul Cleave)
        -- Only SetText hooks drive the display — Show/Hide track visibility
        -- state but do NOT call SyncStackText.  Blizzard's viewer refresh
        -- cycle (RefreshSpellChargeInfo) calls Hide→SetText→Show in sequence
        -- on every UNIT_AURA event.  Calling SyncStackText from Hide clears
        -- chargeText, defeats IsHookStackActive, and causes the API path to
        -- overwrite — creating a clear/set alternation flicker every tick.
        if chargeFrame then
            hooksecurefunc(chargeFrame, "Show", function()
                local s = blizzStackState[blizzChild]
                if not s or not s.icon then return end
                s.chargeVisible = true
            end)
            hooksecurefunc(chargeFrame, "Hide", function()
                local s = blizzStackState[blizzChild]
                if not s or not s.icon then return end
                s.chargeVisible = false
            end)
            if chargeFrame.Current then
                hooksecurefunc(chargeFrame.Current, "SetText", function(_, text)
                    local s = blizzStackState[blizzChild]
                    if not s or not s.icon then return end
                    s.lastHookTime = GetTime()
                    s.chargeText = text
                    SyncStackText(s)
                end)
            end
        end

        -- Hook Applications (e.g., Renewing Mists stacks, Sheilun's Gift)
        if appFrame then
            hooksecurefunc(appFrame, "Show", function()
                local s = blizzStackState[blizzChild]
                if not s or not s.icon then return end
                s.appVisible = true
            end)
            hooksecurefunc(appFrame, "Hide", function()
                local s = blizzStackState[blizzChild]
                if not s or not s.icon then return end
                s.appVisible = false
            end)
            if appFrame.Applications then
                hooksecurefunc(appFrame.Applications, "SetText", function(_, text)
                    local s = blizzStackState[blizzChild]
                    if not s or not s.icon then return end
                    s.lastHookTime = GetTime()
                    s.appText = text
                    SyncStackText(s)
                end)
            end
        end
    end

    -- No seeding — frames are tainted by QUI's SetAlpha(0) on the viewer,
    -- making all reads (IsShown, GetText) return secret values.  Hooks will
    -- populate state on the next Blizzard update.  Apply any existing hook
    -- state from a previous icon that used this blizzChild.
    SyncStackText(state)
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

    -- .TextOverlay (sits above the CooldownFrame so text is never behind the swipe)
    icon.TextOverlay = CreateFrame("Frame", nil, icon)
    icon.TextOverlay:SetAllPoints(icon)
    icon.TextOverlay:SetFrameLevel(icon.Cooldown:GetFrameLevel() + 2)

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
        if texID then
            icon.Icon:SetTexture(texID)
            icon._desiredTexture = texID
        end
    end

    -- Tooltip support
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if GameTooltip.IsForbidden and GameTooltip:IsForbidden() then return end
        local entry = self._spellEntry
        if not entry then return end
        local tooltipSettings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip
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
        local sid = entry.overrideSpellID or entry.spellID or (entry.type and entry.id)
        if sid then
            if entry.type == "trinket" then
                -- Trinket entries store slot number; resolve to item ID for tooltip
                local itemID = GetInventoryItemID("player", sid)
                if itemID then
                    pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
                end
            elseif entry.type == "item" then
                pcall(GameTooltip.SetItemByID, GameTooltip, sid)
            else
                pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
            end
        end
        pcall(GameTooltip.Show, GameTooltip)
    end)
    icon:SetScript("OnLeave", function()
        pcall(GameTooltip.Hide, GameTooltip)
    end)

    icon:Show()
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
    elseif entry.type == "trinket" then
        local itemID = GetInventoryItemID("player", entry.id)
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
    else
        icon._spellOverrideDesaturate = nil
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

local function UpdateIconCooldown(icon)
    if not icon or not icon._spellEntry then return end
    local entry = icon._spellEntry

        -- Aura-driven update: delegates to shared CDMSpellData:ResolveAuraState().
        -- Icons apply result to swipe/stacks display on CooldownFrame.
        do
            local ownedDB = _hoistedNcdm and _hoistedNcdm[entry.viewerType]
            local cType = ownedDB and ownedDB.containerType
            if not cType then
                local vt = entry.viewerType
                cType = (vt == "buff" or vt == "trackedBar") and "aura" or "cooldown"
            end
            if cType == "aura" or cType == "auraBar" then
                local auraSpellID = entry.overrideSpellID or entry.spellID or entry.id
                if auraSpellID and ns.CDMSpellData then
                    local p = icon._auraParams or {}
                    icon._auraParams = p
                    p.spellID = auraSpellID
                    p.entrySpellID = entry.spellID
                    p.entryID = entry.id
                    p.entryName = entry.name
                    p.viewerType = entry.viewerType
                    p.blizzChild = entry._blizzChild
                    p.blizzBarChild = nil

                    local r = ns.CDMSpellData:ResolveAuraState(p)
                    if r.blizzChild and r.blizzChild ~= entry._blizzChild then
                        -- Blizzard child changed — reconnect mirror/texture/stack
                        -- hooks to the new child. Old hooks on the previous child
                        -- self-disable via stale mapping guards in each callback.
                        entry._blizzChild = r.blizzChild
                        MirrorBlizzCooldown(icon, r.blizzChild)
                        HookBlizzTexture(icon, r.blizzChild)
                        HookBlizzStackText(icon, r.blizzChild)
                    end

                    if r.isActive then
                        icon._auraActive = true

                        -- Swipe priority: durObj → hookDurObj → raw start/dur
                        local swipeSet = false
                        if icon.Cooldown and r.durObj and icon.Cooldown.SetCooldownFromDurationObject then
                            pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, r.durObj, true)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                            swipeSet = true
                        end
                        if not swipeSet and icon.Cooldown and r.hookDurObj and icon.Cooldown.SetCooldownFromDurationObject then
                            pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, r.hookDurObj, true)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                            swipeSet = true
                        end
                        if not swipeSet and icon.Cooldown and r.hookStart and r.hookDur
                           and IsSafeNumeric(r.hookStart) and IsSafeNumeric(r.hookDur) then
                            pcall(icon.Cooldown.SetCooldown, icon.Cooldown, r.hookStart, r.hookDur)
                            pcall(icon.Cooldown.SetReverse, icon.Cooldown, true)
                        end

                        -- Stacks: hooks are authoritative when active —
                        -- our handler runs after Blizzard's hooks, so
                        -- API writes would overwrite correct hook values.
                        local _auraHookActive = IsHookStackActive(entry, icon)
                        if _auraHookActive then

                        end
                        if not _auraHookActive then
                            if r.stacks then

                                pcall(icon.StackText.SetText, icon.StackText, C_StringUtil.TruncateWhenZero(r.stacks))
                                icon.StackText:Show()
                            elseif not InCombatLockdown() then

                                icon.StackText:SetText("")
                                icon.StackText:Hide()
                            end
                        end

                        -- Keep texture showing the tracked aura spell
                        if icon.Icon then
                            local texSpellID = entry.overrideSpellID or entry.spellID or entry.id
                            if texSpellID then
                                local texID = GetSpellTexture(texSpellID)
                                if texID and texID ~= icon._lastTexture then
                                    icon.Icon:SetTexture(texID)
                                    icon._lastTexture = texID
                                end
                            end
                        end

                        ReapplySwipeStyle(icon.Cooldown, icon)
                        return  -- Aura path complete
                    else
                        -- Combat debounce: if hook cache still has data for this
                        -- spell, Blizzard's viewer child hasn't been hidden/cleared
                        -- yet — the aura is still present.  isActive detection can
                        -- briefly return false due to auraInstanceID nil-check
                        -- timing races with the viewer update cycle.  Skip the
                        -- inactive transition to prevent the entire icon from
                        -- flickering (visibility code hides icon when _auraActive
                        -- is false).  Once Blizzard actually expires the aura, the
                        -- Hide/Clear hooks clear the cache and the next tick
                        -- transitions cleanly.
                        if InCombatLockdown() and (r.hookDurObj or (r.hookStart and r.hookDur)) then
                            return  -- transient miss, keep current icon state
                        end
                        icon._auraActive = false
                        if icon.Cooldown then icon.Cooldown:Clear() end

                        icon.StackText:SetText("")
                        icon.StackText:Hide()
                        return  -- Aura path complete
                    end
                end
            end
        end

        -- Custom entry: use addon-created CD with our cooldown resolution
        local startTime, duration, durObj
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
                -- Use GetInventoryItemCooldown for equipped items (not GetItemCooldown).
                -- Guard comparisons: startTime/duration may be secret in combat.
                if GetInventoryItemCooldown then
                    local s, d, e = GetInventoryItemCooldown("player", slotID)
                    if IsSafeNumeric(s) and IsSafeNumeric(d) and d > 1.5 and e == 1 then
                        startTime = s
                        duration = d
                    end
                end
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
            startTime, duration, durObj = GetBestSpellCooldown(entry.overrideSpellID or entry.spellID or entry.id)

            -- Sync texture for spell overrides (e.g., Judgment → Hammer of Wrath).
            -- Cache override ID to avoid repeated GetSpellTexture lookups, but
            -- always re-apply the desired texture so Blizzard texture hook drift
            -- (viewer child showing a different icon, e.g., debuff instead of
            -- ability) is corrected every tick.
            if C_Spell.GetOverrideSpell and icon.Icon then
                local baseID = entry.overrideSpellID or entry.spellID or entry.id
                if baseID then
                    local overrideID = C_Spell.GetOverrideSpell(baseID)
                    if not Helpers.IsSecretValue(overrideID) and overrideID ~= icon._cachedOverrideID then
                        icon._cachedOverrideID = overrideID
                        icon._desiredTexture = GetSpellTexture(overrideID or baseID)
                    end
                    -- Always re-apply: SetTexture is a C-side no-op when unchanged.
                    if icon._desiredTexture then
                        icon.Icon:SetTexture(icon._desiredTexture)
                    end
                end
            end
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
        -- When API returns no data (fully charged / off CD), clear stale
        -- values so desaturation doesn't persist from a previous recharge.
        if not startTime and not duration then
            icon._lastStart = 0
            icon._lastDuration = 0
        end

        if icon.Cooldown then
            -- When mirror hooks are active, they forward Blizzard's exact
            -- cooldown state (SetCooldown / SetCooldownFromDurationObject)
            -- and call SyncMirroredCooldownState which maintains
            -- _hasCooldownActive / _lastStart / _lastDuration.  The API
            -- path writing to the same CooldownFrame causes the swipe to
            -- restart or fight (e.g., GCD vs charge recharge).  Skip API
            -- writes and trust the mirror as sole driver.
            local cdApplied = false
            -- Priority 1: DurationObject (secret-safe via SetCooldownFromDurationObject)
            if durObj and icon.Cooldown.SetCooldownFromDurationObject then
                local ok = pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, durObj, false)
                cdApplied = ok
            end
            -- Priority 2: safe numeric values (OOC or non-secret)
            if not cdApplied and startTime and duration
               and IsSafeNumeric(startTime) and IsSafeNumeric(duration) then
                pcall(icon.Cooldown.SetCooldown, icon.Cooldown, startTime, duration)
                cdApplied = true
            end
            -- Priority 3: hook cache DurationObject from Blizzard viewer children
            if not cdApplied and ns.CDMSpellData then
                local hookDurObj = ns.CDMSpellData:GetCachedDurObj(
                    entry.overrideSpellID or entry.spellID or entry.id)
                if hookDurObj and icon.Cooldown.SetCooldownFromDurationObject then
                    pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, hookDurObj, false)
                    cdApplied = true
                end
            end
            -- No data: clear
            if not cdApplied and not startTime and not duration then
                icon.Cooldown:Clear()
            end
            icon._hasCooldownActive = cdApplied or false
        end

    -- Stack/charge text: API-driven on each tick.
    -- Cache chargeInfo for this icon — reused by desaturation check below
    -- (was called 3x per cooldown icon per tick, now 1x)
    local _cachedChargeInfo = nil
    local _cachedChargeOk = false

    -- Populate _cachedChargeInfo unconditionally (needed for desaturation
    -- check below), independent of whether hooks are driving stack text.
    do
        local spellID = entry.overrideSpellID or entry.spellID or entry.id
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
    if _hookActive then

    end
    if not _hookActive then
        if entry.type == "item" then
            -- Item stack text was already set above in the cooldown section;
            -- nothing to do here — just prevent the else clause from clearing it.
        elseif entry.type == "spell" then
            -- Custom spell entry: check charges/stacks via API.
            -- Values may be secret in combat — pass directly to C-side functions
            -- (TruncateWhenZero, SetText) without reading in Lua.
            local spellID = entry.overrideSpellID or entry.spellID or entry.id
            local stackVal  -- raw value (may be secret), forwarded to C-side

            -- Primary: C_Spell.GetSpellDisplayCount (canonical API, handles
            -- charges, stacks, and cast counts; secret-safe via C-side).
            if spellID and C_Spell.GetSpellDisplayCount then
                local ok, val = pcall(C_Spell.GetSpellDisplayCount, spellID)
                if ok and val then
                    stackVal = val
                end
            end

            -- Fallback: manual charge detection when GetSpellDisplayCount unavailable
            if not stackVal and _cachedChargeInfo and _cachedChargeInfo.maxCharges then
                local isMultiCharge = false
                if not IsSecretValue(_cachedChargeInfo.maxCharges) then
                    isMultiCharge = _cachedChargeInfo.maxCharges > 1
                else
                    local svDB = GetChargeMetadataDB()
                    isMultiCharge = svDB and svDB[spellID] and true or false
                end
                if isMultiCharge and _cachedChargeInfo.currentCharges then
                    stackVal = _cachedChargeInfo.currentCharges
                end
            end

            -- Fallback: secondary resource counts (e.g. Festering Wounds)
            if not stackVal and spellID and C_Spell.GetSpellCastCount then
                local ok, val = pcall(C_Spell.GetSpellCastCount, spellID)
                if ok and val then
                    stackVal = val
                end
            end

            -- Forward to C-side: TruncateWhenZero returns "" for zero (hides
            -- stacks visually). Guard with pcall — the function requires a finite
            -- number and will reject secret values or unexpected types.
            if stackVal then
                local truncOk, truncText = pcall(C_StringUtil.TruncateWhenZero, stackVal)
                local displayText = truncOk and truncText or stackVal
                -- Only show when there's actual text — TruncateWhenZero returns
                -- "" for zero, and many spells return 0 from GetSpellDisplayCount
                -- even when they have no charge mechanic.
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

        -- Skip buff viewer icons and aura-active icons (they show buff timers)
        if viewerType ~= "buff" and not icon._auraActive and not icon._rangeTinted and not icon._usabilityTinted then
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
                local dur = icon._lastDuration or 0
                local start = icon._lastStart or 0

                if dur > 1.5 and start > 0 then
                    local remaining = (start + dur) - _batchTime
                    if remaining > 0 then
                        -- Charged spells: Blizzard's viewer handles
                        -- desaturation natively via SetDesaturated on the
                        -- viewer child's Icon texture — our mirror hook
                        -- forwards these calls.  Skip our own logic to
                        -- avoid overriding Blizzard's correct charge state.
                        if entry.hasCharges then
                            return
                        end
                    end
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
        icon._hasCooldownActive = nil

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
                icon._desiredTexture = texID
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
        icon:Show()
        return icon
    end
    local newIcon = CreateIcon(parent, spellEntry)
    -- Update click-to-cast secure attributes for new icons
    if spellEntry.viewerType ~= "buff" then
        UpdateIconSecureAttributes(newIcon, spellEntry, spellEntry.viewerType)
    end
    return newIcon
end

function CDMIcons:ReleaseIcon(icon)
    if not icon then return end
    -- Disconnect hooks before clearing _spellEntry (needs blizzChild ref)
    UnmirrorBlizzCooldown(icon)
    UnhookBlizzTexture(icon)
    UnhookBlizzStackText(icon)
    icon:Hide()
    icon:ClearAllPoints()
    icon._spellEntry = nil
    icon._rangeTinted = nil
    icon._usabilityTinted = nil
    icon._cdDesaturated = nil
    icon._spellOverrideDesaturate = nil
    icon._lastStart = nil
    icon._lastDuration = nil
    icon._isOnGCD = nil
    icon._hasCooldownActive = nil
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
                    local spellEntry = {
                        spellID = entry.id,
                        overrideSpellID = entry.id,
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
            local QUICore = ns.Addon
            local ncdm = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.ncdm
            local containerDB = ncdm and ncdm[entry.viewerType]
            local cType = containerDB and containerDB.containerType
            if not cType then
                local vt = entry.viewerType
                cType = (vt == "buff" or vt == "trackedBar") and "aura" or "cooldown"
            end
            if cType == "aura" or cType == "auraBar" then
                icon._auraActive = false  -- will be set true by UpdateIconCooldown when aura present
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
            MirrorBlizzCooldown(icon, entry._blizzChild)
            HookBlizzTexture(icon, entry._blizzChild)
            HookBlizzStackText(icon, entry._blizzChild)
            -- Buff icons are always auras — initialize _auraActive so the
            -- swipe module classifies them correctly before the
            -- SetCooldownFromDurationObject hook fires.
            if entry.viewerType == "buff" then
                icon._auraActive = true
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
-- UPDATE ALL COOLDOWNS
---------------------------------------------------------------------------
function CDMIcons:UpdateAllCooldowns()
    -- Wipe per-tick caches: each batch starts fresh so every spellID
    -- is queried at most once via TickCacheGetCharges/TickCacheGetCooldown.
    wipe(_tickChargeCache)
    wipe(_tickCooldownCache)
    wipe(_textureCycleCache)

    -- Child map is invalidated by aura/cooldown event subscribers via
    -- CDMSpellData:InvalidateChildMap(). RebuildChildMap is a no-op when clean.

    local editMode = Helpers.IsEditModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())

    -- Hoist DB lookups above the loop (avoids 4 table hops per icon).
    -- Also set file-scoped _hoistedNcdm so UpdateIconCooldown can read it
    -- without re-walking the chain for every icon.
    local _ncdm = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.ncdm
    _hoistedNcdm = _ncdm  -- consumed by UpdateIconCooldown
    _batchTime = GetTime()  -- consumed by UpdateIconCooldown + visibility loop
    local _ncdmContainers = _ncdm and _ncdm.containers
    local inCombat = InCombatLockdown()

    for _, pool in pairs(iconPools) do
        for _, icon in ipairs(pool) do
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
                        local spellID = entry.overrideSpellID or entry.spellID or entry.id
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
                            if icon:IsShown() then icon:Hide() end
                        end
                    end

                    -- Grey out when linked debuff/aura not active on target
                    local greyOut = containerDB and containerDB.greyOutInactive
                    if greyOut and icon:IsShown() and icon.Icon and icon.Icon.SetDesaturated then
                        -- Only apply to spells that have aura tracking (linked auras)
                        local hasAuraLink = entry.linkedSpellIDs or entry._abilityToAuraSpellID
                            or (icon._spellEntry and icon._spellEntry.linkedSpellIDs)
                        if hasAuraLink and not icon._auraActive then
                            local rowOpacity = icon._rowOpacity or 1
                            icon:SetAlpha(rowOpacity * 0.4)
                            if not icon._cdDesaturated then
                                icon.Icon:SetDesaturated(true)
                            end
                            icon._greyedOut = true
                        elseif icon._greyedOut then
                            local rowOpacity = icon._rowOpacity or 1
                            icon:SetAlpha(rowOpacity)
                            if not icon._cdDesaturated then
                                icon.Icon:SetDesaturated(false)
                            end
                            icon._greyedOut = nil
                        end
                    elseif icon._greyedOut then
                        local rowOpacity = icon._rowOpacity or 1
                        icon:SetAlpha(rowOpacity)
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

end

function CDMIcons:UpdateCooldownsForType(viewerType)
    local pool = iconPools[viewerType]
    if pool then
        for _, icon in ipairs(pool) do
            UpdateIconCooldown(icon)
        end
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

    local customData = GetCustomData(trackerKey)
    if not customData then return false end
    if not customData.entries then customData.entries = {} end

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

function CustomCDM:MoveEntry(trackerKey, fromIndex, direction)
    local customData = GetCustomData(trackerKey)
    if not customData or not customData.entries then return end

    local entries = customData.entries
    local toIndex = fromIndex + direction
    if toIndex < 1 or toIndex > #entries then return end

    entries[fromIndex], entries[toIndex] = entries[toIndex], entries[fromIndex]
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
end


-- Legacy compat: GetIcons returns the pool for a viewer name.
-- Returns empty when called from the classic engine's LayoutViewer context
-- (which passes Blizzard viewer names) to prevent the classic engine from
-- repositioning our addon-owned icons onto the Blizzard viewer during combat.
function CustomCDM:GetIcons(viewerName)
    -- Only return icons when asked for addon-owned container names
    -- (internal callers from the owned engine).  The classic engine passes
    -- Blizzard viewer names ("EssentialCooldownViewer", etc.) — return
    -- empty so it doesn't adopt and reposition our icons.
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

-- Safe wrapper: C_Spell.IsSpellInRange can return secret values in Midnight.
-- Calls pcall directly (no closure allocation).
local function SafeIsSpellInRange(spellID)
    if not spellID or not C_Spell or not C_Spell.IsSpellInRange then return nil end
    local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, "target")
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
    if entry.type == "item" or entry.type == "trinket" then return end

    -- Resolve current spell ID (prefer cached override from cooldown update cycle
    -- to avoid redundant GetOverrideSpell API calls during range polling)
    local spellID = entry.overrideSpellID or entry.spellID or entry.id
    if icon._cachedOverrideID then
        spellID = icon._cachedOverrideID
    elseif C_Spell and C_Spell.GetOverrideSpell then
        local currentOverride = C_Spell.GetOverrideSpell(entry.spellID or entry.id)
        if currentOverride then spellID = currentOverride end
    end
    if not spellID then return end

    ---------------------------------------------------------------------------
    -- Compute desired visual state (API calls use per-cycle dedup caches)
    ---------------------------------------------------------------------------
    local newVisualState = "normal"

    -- Priority 1: Out of range (red tint) — only when target exists + ranged
    if rangeEnabled and UnitExists("target") then
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
                inRange = SafeIsSpellInRange(spellID)
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
    -- State-change gating: skip SetVertexColor if visual state unchanged
    ---------------------------------------------------------------------------
    if icon._lastVisualState == newVisualState then return end
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
        -- Clear cooldown desaturation so vertex color darkening is visible
        if icon._cdDesaturated then
            icon.Icon:SetDesaturated(false)
            icon._cdDesaturated = nil
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
cdEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
cdEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cdEventFrame:RegisterEvent("UPDATE_MACROS")
-- UNIT_AURA handled by centralized dispatcher subscription (below)

-- C_Timer coalescing for cooldown events: batches SPELL_UPDATE_COOLDOWN,
-- SPELL_UPDATE_CHARGES, BAG_UPDATE_COOLDOWN, and UNIT_AURA into a single
-- UpdateAllCooldowns after a short delay.
-- Throttled to max ~20 FPS (50ms) — raid combat fires SPELL_UPDATE_COOLDOWN
-- many times per second; 60 FPS updates are excessive for icon display.
local CDM_MIN_UPDATE_INTERVAL = 0.05
local _lastCDMUpdateTime = 0

local _cdmUpdatePending = false

local function ScheduleCDMUpdate()
    if _cdmUpdatePending then return end
    _cdmUpdatePending = true
    C_Timer.After(CDM_MIN_UPDATE_INTERVAL, function()
        _cdmUpdatePending = false
        _lastCDMUpdateTime = GetTime()
        CDMIcons:UpdateAllCooldowns()
        if ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
            ns.CDMBars:UpdateOwnedBars()
        end
    end)
end

-- Combat safety ticker: periodic UpdateAllCooldowns during combat.
-- DurationObject sources may resolve late (viewer hook delays); a
-- low-frequency ticker ensures icons recover within 250ms even if the
-- initial event-driven update failed due to secret values.
local safetyTickFrame = CreateFrame("Frame")
local SAFETY_TICK_INTERVAL = 0.25
local safetyTickElapsed = 0
local function SafetyTickOnUpdate(self, elapsed)
    safetyTickElapsed = safetyTickElapsed + elapsed
    if safetyTickElapsed < SAFETY_TICK_INTERVAL then return end
    safetyTickElapsed = 0
    CDMIcons:UpdateAllCooldowns()
    if ns.CDMBars and ns.CDMBars.UpdateOwnedBars then
        ns.CDMBars:UpdateOwnedBars()  -- safety ticker, don't clear oocInactive
    end
end

cdEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        CDMIcons:UpdateAllIconRanges()
        -- Target debuffs (e.g. Reaper's Mark) need a CDM refresh when target changes
        ns.CDMSpellData:InvalidateChildMap()
        ScheduleCDMUpdate()
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Trinket slots 13-14: refresh textures and cooldowns immediately
        if arg1 == 13 or arg1 == 14 then
            ns.CDMSpellData:InvalidateChildMap()
            CDMIcons:UpdateAllCooldowns()
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        rangePollInCombat = true
        rangePollElapsed = 0  -- reset so combat interval kicks in immediately
        safetyTickElapsed = 0
        safetyTickFrame:SetScript("OnUpdate", SafetyTickOnUpdate)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        rangePollInCombat = false
        safetyTickFrame:SetScript("OnUpdate", nil)
        -- One-shot catch-up: refresh all cooldowns after combat ends
        ns.CDMSpellData:InvalidateChildMap()
        ScheduleCDMUpdate()
        return
    end
    if event == "UPDATE_MACROS" then
        InvalidateMacroCache()
        return
    end
    -- Coalesce cooldown events via C_Timer
    ns.CDMSpellData:InvalidateChildMap()  -- cooldown state changed, children may have shown/hidden
    ScheduleCDMUpdate()
end)

-- Subscribe to centralized aura dispatcher for prompt icon updates.
-- Player auras via "player" filter (avoids callback for all 20+ raid units).
-- Target debuffs via "all" filter (no "target" filter in the dispatcher).
if ns.AuraEvents then
    ns.AuraEvents:Subscribe("player", function(unit, updateInfo)
        ns.CDMSpellData:InvalidateChildMap()
        ScheduleCDMUpdate()
    end)
    ns.AuraEvents:Subscribe("all", function(unit, updateInfo)
        if unit == "target" then
            ns.CDMSpellData:InvalidateChildMap()
            ScheduleCDMUpdate()
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
