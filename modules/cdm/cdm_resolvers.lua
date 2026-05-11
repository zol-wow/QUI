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
        publish("CDM:COOLDOWN_CHANGED", arg1, "refresh")
    elseif evt == "SPELL_UPDATE_CHARGES" then
        publish("CDM:CHARGES_CHANGED", arg1)
    elseif evt == "UNIT_SPELLCAST_START" then
        if arg1 == "player" then
            publish("CDM:COOLDOWN_CHANGED", arg3, "cast_start")
        end
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            publish("CDM:COOLDOWN_CHANGED", arg3, "cast_succeeded")
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

-- Source-facade passthroughs. No caching: each call is a live read. Names
-- dropped the misleading "TickCache" prefix.
function CDMResolvers.QueryCharges(spellID)
    if not spellID then return nil end
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
    return chargeInfo
end

function CDMResolvers.QueryCooldown(spellID)
    if not spellID then return nil end
    if Sources and Sources.QuerySpellCooldown then
        return Sources.QuerySpellCooldown(spellID)
    end
    return nil
end

function CDMResolvers.QueryDuration(spellID)
    if not spellID then return nil end
    -- ignoreGCD=true: return the spell's own cooldown DurationObject
    -- even during the GCD, so the icon swipe tracks the spell's real
    -- cooldown instead of the 1.5s GCD sweep that masks it.
    if Sources and Sources.QuerySpellCooldownDuration then
        return Sources.QuerySpellCooldownDuration(spellID, true)
    end
    return nil
end

function CDMResolvers.QueryChargeDuration(spellID)
    if not spellID then return nil end
    if Sources and Sources.QuerySpellChargeDuration then
        return Sources.QuerySpellChargeDuration(spellID)
    end
    return nil
end

function CDMResolvers.QueryOverrideSpell(spellID)
    if not spellID then return nil end
    if Sources and Sources.QueryOverrideSpell then
        return Sources.QueryOverrideSpell(spellID)
    end
    return nil
end

function CDMResolvers.QueryDisplayCount(spellID)
    if not spellID then return nil end
    if Sources and Sources.QuerySpellDisplayCount then
        return Sources.QuerySpellDisplayCount(spellID)
    end
    return nil
end

function CDMResolvers.QuerySpellCount(spellID)
    if not spellID then return nil end
    if Sources and Sources.QuerySpellCount then
        return Sources.QuerySpellCount(spellID)
    end
    return nil
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
    if not (Sources and Sources.QuerySpellCooldownDuration) then
        return nil
    end

    local durObj = nil
    if spellID then
        durObj = Sources.QuerySpellCooldownDuration(spellID, false)
    end
    if not durObj and spellID ~= GCD_SPELL_ID then
        durObj = Sources.QuerySpellCooldownDuration(GCD_SPELL_ID, false)
    end
    return durObj
end

local function SpellHasBaseCooldownLongerThanGCD(spellID)
    if spellID
       and CDMIcons
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD(spellID) == true then
        return true
    end
    return false
end

local function HasRealCooldownProof(spellID, durObj, cdInfo, currentOnGCD)
    if currentOnGCD == true then
        if CDMIcons and CDMIcons.IsCooldownInfoRealCooldown then
            local realCooldown = CDMIcons.IsCooldownInfoRealCooldown(cdInfo)
            if realCooldown == true then
                return true
            elseif realCooldown == false then
                return false
            end
        end
        return SpellHasBaseCooldownLongerThanGCD(spellID)
    end
    if durObj then
        return true
    end
    return SpellHasBaseCooldownLongerThanGCD(spellID)
end

local _mirrorPolicyStats = {
    staleGCDSkips = 0,
    staleInactiveSkips = 0,
}

local function IsMirrorChargeSource(durObjSource)
    return durObjSource == "spell-charge" or durObjSource == "resource-duration"
end

local function GetMirroredChargeActive(spellID)
    local ci = QueryCharges(spellID)
    if not ci then
        return nil
    end
    return SafeBoolean(ci.isActive)
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

local function ShouldTreatLiveDurationAsGCD(spellID, entry, cdInfo, currentOnGCD)
    if currentOnGCD ~= true then
        return false
    end
    if IsChargeSpellNotRecharging(spellID, entry) then
        return true
    end
    if CDMIcons and CDMIcons.IsCooldownInfoRealCooldown then
        local realCooldown = CDMIcons.IsCooldownInfoRealCooldown(cdInfo)
        if realCooldown == true then
            return false
        elseif realCooldown == false then
            return true
        end
    end
    return false
end

local function GetMirroredCooldownPolicy(mode, durObjSource, liveCdActive, currentOnGCD, gcdDurObj, realCooldownDurObj, realCooldownLikely, gcdSwipeEnabled, liveChargeActive)
    if mode == "charge" and IsMirrorChargeSource(durObjSource) then
        if liveChargeActive == false then
            if currentOnGCD == true then
                if gcdSwipeEnabled == true and not gcdDurObj then
                    return true, nil, "gcd-only"
                end
                return false, "stale-gcd", nil
            end
            return false, "stale-inactive", nil
        end
        return true, nil, nil
    end

    if mode ~= "cooldown" or durObjSource ~= "spell-cooldown" then
        return true, nil, nil
    end
    if liveCdActive == false then
        return false, "stale-inactive", nil
    end
    if currentOnGCD == true and realCooldownLikely ~= true then
        if gcdSwipeEnabled == true and not gcdDurObj then
            return true, nil, "gcd-only"
        end
        return false, "stale-gcd", nil
    end
    return true, nil, nil
end

function CDMResolvers.ShouldUseMirroredCooldownDuration(mode, durObjSource, liveCdActive, currentOnGCD, gcdDurObj, realCooldownDurObj, realCooldownLikely, gcdSwipeEnabled, liveChargeActive)
    return GetMirroredCooldownPolicy(mode, durObjSource, liveCdActive, currentOnGCD, gcdDurObj, realCooldownDurObj, realCooldownLikely, gcdSwipeEnabled, liveChargeActive)
end

function CDMResolvers.GetMirrorPolicyStats()
    local staleGCD = _mirrorPolicyStats.staleGCDSkips or 0
    local staleInactive = _mirrorPolicyStats.staleInactiveSkips or 0
    return {
        staleGCDSkips = staleGCD,
        staleInactiveSkips = staleInactive,
        staleMirrorSkips = staleGCD + staleInactive,
    }
end

function CDMResolvers.ResetMirrorPolicyStats()
    _mirrorPolicyStats.staleGCDSkips = 0
    _mirrorPolicyStats.staleInactiveSkips = 0
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

    if durObj and apiIsActive == true
       and CDMIcons.SpellHasBaseCooldownLongerThanGCD(runtimeSpellID or entry.spellID or entry.overrideSpellID or entry.id) then
        return true
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

    -- 1.5. Blizzard CDM mirror — for cooldown-kind entries with a known
    -- viewer child, prefer Blizzard's privileged durObj over our own
    -- spell cooldown source query. Blizzard's child receives
    -- SetCooldownFromDurationObject from the same data feed that drives
    -- their UI, including talent-modified durations and per-charge
    -- cooldowns.
    --
    -- Exact cID binding wins first. It keeps custom containers and duplicate
    -- placements tied to the same Blizzard child without guessing from a
    -- spellID map. The spellID lookup remains as a fallback for icons built
    -- before the child exists. Aura viewers (buff / trackedBar) are
    -- intentionally NOT probed here — that's the aura resolver's job.
    do
        local m
        local mirrorCooldownID = icon._blizzMirrorCooldownID
        local mirror = ns.CDMBlizzMirror
        if mirrorCooldownID and mirror and mirror.GetStateByCooldownID then
            m = mirror.GetStateByCooldownID(mirrorCooldownID, icon._blizzMirrorCategory)
        end
        if not m and Sources and Sources.QueryMirroredCooldownState then
            m = Sources.QueryMirroredCooldownState(sid, entry.viewerType)
        end
        if m and m.isActive and m.durObj then
            local sourceCooldownID = m.cooldownID or mirrorCooldownID or sid
            local sourceSpellID = m.overrideSpellID or m.spellID or sid
            local mode = (m.durObjSource == "aura-duration"
                or m.durObjSource == "aura-child"
                or m.durObjSource == "aura-child-frame"
                or m.durObjSource == "aura-related-child") and "aura" or "cooldown"
            if m.durObjSource == "spell-charge"
                or m.durObjSource == "resource-duration" then
                mode = "charge"
            end
            local liveCdActive = gcdCdInfo and CDMIcons.GetCooldownInfoField(gcdCdInfo, "isActive")
            local liveChargeActive = nil
            if mode == "charge" and IsMirrorChargeSource(m.durObjSource) then
                liveChargeActive = GetMirroredChargeActive(sourceSpellID)
            end
            local realCooldownDurObj = nil
            if mode == "cooldown" and m.durObjSource == "spell-cooldown" then
                realCooldownDurObj = QueryDuration(sourceSpellID)
            end
            local realCooldownLikely = HasRealCooldownProof(sourceSpellID, realCooldownDurObj, gcdCdInfo, currentOnGCD)
            local useMirror, skipReason, mirrorMode = GetMirroredCooldownPolicy(
                mode, m.durObjSource, liveCdActive, currentOnGCD, gcdDurObj, realCooldownDurObj,
                realCooldownLikely, CDMIcons.IsGCDSwipeEnabled(), liveChargeActive)
            if useMirror then
                if mirrorMode == "gcd-only" then
                    return m.durObj, "gcd-only", sourceSpellID
                end
                return m.durObj, mode,
                    "mirror:" .. tostring(sourceCooldownID) .. ":" .. tostring(m.mirrorEpoch),
                    nil, nil, sourceSpellID
            elseif skipReason == "stale-gcd" then
                _mirrorPolicyStats.staleGCDSkips = (_mirrorPolicyStats.staleGCDSkips or 0) + 1
            elseif skipReason == "stale-inactive" then
                _mirrorPolicyStats.staleInactiveSkips = (_mirrorPolicyStats.staleInactiveSkips or 0) + 1
            end
        end
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
            local durationIsGCD = ShouldTreatLiveDurationAsGCD(sid, entry, cdInfo, cdInfoOnGCD)
            if durObj and not durationIsGCD then
                return durObj, "cooldown", sid
            end
            if cdInfoOnGCD == true then
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
