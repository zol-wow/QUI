-- cdm_resolvers.lua
-- Pure resolution layer for the QUI CDM owned engine.
-- Functions in this file MUST NOT write to frames; they compute and return values.
-- Runtime query/cache wrappers live in cdm_runtime_queries.lua so resolvers
-- consume source facts through a narrow shared seam.

local _, ns = ...
local Helpers = ns.Helpers
local Shared = ns.CDMShared

-- WoW provides `wipe`; the standalone test harness does not. Mirror the
-- fallback used by cdm_icon_runtime_refresh.lua so the scratch-reuse helpers
-- below work in both environments.
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local CDMResolvers = {}
ns.CDMResolvers = CDMResolvers
local Scheduler = ns.CDMScheduler
local Sources = ns.CDMSources

local resolverStats -- debug counters; nil until QUI_Debug activates instrumentation
local currentResolveCallerTag -- string or nil; set by SetResolveCallerTag before each resolve
local markFn -- profiler hook; bound at debug activation (nil otherwise)
local function MemAuditProfilerMark(name)
    if markFn then markFn(name) end
end

---------------------------------------------------------------------------
-- Event bus
--
-- Synchronous dispatch with a per-call snapshot of the subscriber list. The
-- snapshot is intentional: it freezes which handlers fire for the current
-- publish so that subscribing during dispatch doesn't include the new
-- handler in the in-flight event (verified by tests/unit/cdm_bus_test.lua).
-- Subscribers run in the resolver's tick. Events carry IDs only; subscribers
-- pull fresh state through the runtime query wrappers. See spec:
-- docs/superpowers/specs/2026-05-05-cdm-blizzard-child-decoupling-design.md
---------------------------------------------------------------------------
local _subscribers = {} -- [eventName] = { handler1, handler2, ... }

local _fallbackSnapshotPool = {}
local _fallbackSnapshotPoolN = 0

local function publish(eventName, ...)
    if Scheduler and Scheduler.Publish then
        Scheduler.Publish(eventName, ...)
        return
    end

    local list = _subscribers[eventName]
    if not list then return end
    local n = #list
    if n == 0 then return end

    local poolN = _fallbackSnapshotPoolN
    local snapshot
    if poolN > 0 then
        snapshot = _fallbackSnapshotPool[poolN]
        _fallbackSnapshotPool[poolN] = nil
        _fallbackSnapshotPoolN = poolN - 1
    else
        snapshot = {}
    end

    for i = 1, n do snapshot[i] = list[i] end
    for i = 1, n do
        xpcall(snapshot[i], geterrorhandler(), eventName, ...)
    end

    wipe(snapshot)
    poolN = _fallbackSnapshotPoolN + 1
    _fallbackSnapshotPoolN = poolN
    _fallbackSnapshotPool[poolN] = snapshot
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
-- Publishes CDM:CATALOG_REBUILT when the cdID<->spell catalog actually reshapes
-- (spec / talent / spell-list changes). Combat-deferred: these can fire inside
-- combat, so the rebuild waits for PLAYER_REGEN_ENABLED. Encounter / Mythic+ /
-- rated-PvP starts only re-randomize aura instance IDs (not the catalog) and are
-- handled by cdm_blizz_mirror.lua's own re-capture, NOT here.
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
-- ENCOUNTER_START / CHALLENGE_MODE_START / PVP_MATCH_ACTIVE are NOT catalog
-- triggers: those boundaries only re-randomize aura instance IDs, not the
-- cdID<->spell catalog. cdm_blizz_mirror.lua handles them directly with a cheap
-- in-combat aura re-capture (re-stamps the instance IDs) — no full catalog
-- rebuild deferred to PLAYER_REGEN_ENABLED.
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
_runtimeFrame:RegisterEvent("SPELL_UPDATE_USES")
_runtimeFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_runtimeFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")

local function IsPlayerUnitToken(value)
    if issecretvalue and issecretvalue(value) then return false end
    return value == "player"
end

-- Debug trace hook slot. The debug addon populates this at load time
-- so /cdmdebug spell <id> events can see SUC / SPELL_UPDATE_CHARGES /
-- SPELL_UPDATE_USES / UNIT_SPELLCAST_* fires — those events only route
-- through _runtimeFrame (registered above), never the icon-renderer
-- frame. Kept as a generic hook slot so this consolidated chunk does
-- not import the renderer module, per the architectural contract in
-- cdm_fast_visual_refresh_contract_test.lua. Stays nil when QUI_Debug
-- isn't loaded; the OnEvent body skips the call.
ns.CDMRuntimeEventTraceHook = nil

_runtimeFrame:SetScript("OnEvent", function(_, evt, arg1, arg2, arg3, arg4)
    -- Per SpellBookDocumentation.lua:859 the SPELL_UPDATE_COOLDOWN
    -- payload is (spellID, baseSpellID, category, startRecoveryCategory)
    -- — capture all four for the trace. The publish() calls below
    -- intentionally still forward only the fields existing subscribers
    -- consume; arg3/arg4 propagate to the trace only.
    local traceHook = ns.CDMRuntimeEventTraceHook
    if traceHook then
        traceHook("runtime-pre", evt, arg1, arg2, arg3, arg4)
    end

    if evt == "SPELL_UPDATE_COOLDOWN" then
        -- arg1 is Blizzard's spellID hint (may be nil for "update all").
        -- Subscriber chooses per-spell fast-path vs global walk.
        publish("CDM:COOLDOWN_CHANGED", arg1, arg2, "refresh")
    elseif evt == "SPELL_UPDATE_CHARGES" or evt == "SPELL_UPDATE_USES" then
        publish("CDM:CHARGES_CHANGED", arg1, arg2)
    elseif evt == "UNIT_SPELLCAST_START" then
        if IsPlayerUnitToken(arg1) then
            publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_start")
        end
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if IsPlayerUnitToken(arg1) then
            publish("CDM:COOLDOWN_CHANGED", arg3, nil, "cast_succeeded")
        end
    end
end)

local WoW_IsSecretValue = issecretvalue
local ResolverIsSecretValue

local function IsSafeNumeric(val)
    if ResolverIsSecretValue and ResolverIsSecretValue(val) then
        return false
    end
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
    return auraData.auraInstanceID
end

local GCD_MAX_DURATION = 1.75
local GCD_SPELL_ID = 61304

ResolverIsSecretValue = function(value)
    if WoW_IsSecretValue then
        return WoW_IsSecretValue(value)
    end
    return false
end

local function DecodePotentialSecretBoolean(value)
    if ResolverIsSecretValue(value) then return nil end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function HasOpaqueValue(value)
    if ResolverIsSecretValue(value) then
        return true
    end
    return value ~= nil
end

local function CleanOpaqueValue(value)
    if ResolverIsSecretValue(value) then
        return nil
    end
    return value
end

function CDMResolvers.GetCooldownInfoField(info, key)
    -- Returns (value, isSecret). Combat-restricted fields may be secret when
    -- the Blizzard CDM feed is active; callers may pass the raw value to safe
    -- C-side sinks but must not compare it in Lua when isSecret is true.
    if not info then return nil, false end
    local value = info[key]
    if ResolverIsSecretValue(value) then
        return value, true
    end
    if value == nil then return nil, false end
    return value, false
end

function CDMResolvers.IsCooldownInfoActive(info)
    local active = CDMResolvers.GetCooldownInfoField(info, "isActive")
    return DecodePotentialSecretBoolean(active)
end

local GetCooldownInfoField = CDMResolvers.GetCooldownInfoField
local IsCooldownInfoActive = CDMResolvers.IsCooldownInfoActive

local RuntimeQueries = ns.CDMRuntimeQueries

local QueryCharges        = RuntimeQueries.QueryCharges
local QueryCooldown       = RuntimeQueries.QueryCooldown
local QueryDuration       = RuntimeQueries.QueryDuration
local QueryGCDDuration    = RuntimeQueries.QueryGCDDuration
local QueryChargeDuration = RuntimeQueries.QueryChargeDuration
local QueryOverrideSpell  = RuntimeQueries.QueryOverrideSpell


-- IDENTITY RESOLVERS

local function IsItemLikeEntry(entry)
    return entry and (entry.type == "item" or entry.type == "trinket" or entry.type == "slot")
end

local function QueryItemUseSpellID(itemID)
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

local function ResolveItemCooldownIdentity(entry)
    if not entry then return nil, nil, nil, nil end

    local itemID, slotID
    if entry.type == "item" then
        itemID = (Sources and Sources.QueryBestOwnedItemVariant
            and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
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

    local itemSpellID = QueryItemUseSpellID(itemID)
    local keySource = slotID and (tostring(slotID) .. ":" .. tostring(itemID)) or tostring(itemID)
    return itemID, slotID, itemSpellID, keySource
end

-- TEXTURE & MACRO RESOLVERS

-- Persistent texture cache: spellID→iconID rarely changes (only on talent
-- swap / spec change), so we keep it across ticks.  Wiped on SPELLS_CHANGED
-- and PLAYER_SPECIALIZATION_CHANGED to pick up new icons.
local _textureCycleCache = {}
CDMResolvers._textureCycleCache = _textureCycleCache

local function SetupDebugInstrumentation()
    resolverStats = {
        mirrorAuraQueries = 0,
        mirrorAuraSkips = 0,
        mirrorStateCacheHits = 0,
        itemDurationIconReuses = 0,
        resolveBy = {
            spellID     = 0,
            aura        = 0,
            usability   = 0,
            catalog     = 0,
            walk        = 0,
            cooldownOnly = 0,
            other       = 0,
        },
        auraProbeHit           = 0,
        auraProbeGuardSkip     = 0,
        auraProbeExpensiveMiss = 0,
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_resolverMirrorAuraQueries", counter = true, fn = function() return resolverStats.mirrorAuraQueries end }
    mp[#mp + 1] = { name = "CDM_resolverMirrorAuraSkips", counter = true, fn = function() return resolverStats.mirrorAuraSkips end }
    mp[#mp + 1] = { name = "CDM_resolverMirrorStateCacheHits", counter = true, fn = function() return resolverStats.mirrorStateCacheHits end }
    mp[#mp + 1] = { name = "CDM_itemDurationIconReuses", counter = true, fn = function() return resolverStats.itemDurationIconReuses end }
    mp[#mp + 1] = { name = "CDM_textureCycleCache", tbl = _textureCycleCache }
    local rb = resolverStats.resolveBy
    mp[#mp + 1] = { name = "CDM_resolveBy_spellID",           counter = true, fn = function() return rb.spellID end }
    mp[#mp + 1] = { name = "CDM_resolveBy_aura",              counter = true, fn = function() return rb.aura end }
    mp[#mp + 1] = { name = "CDM_resolveBy_usability",         counter = true, fn = function() return rb.usability end }
    mp[#mp + 1] = { name = "CDM_resolveBy_catalog",           counter = true, fn = function() return rb.catalog end }
    mp[#mp + 1] = { name = "CDM_resolveBy_walk",              counter = true, fn = function() return rb.walk end }
    mp[#mp + 1] = { name = "CDM_resolveBy_cooldownOnly",      counter = true, fn = function() return rb.cooldownOnly end }
    mp[#mp + 1] = { name = "CDM_resolveBy_other",             counter = true, fn = function() return rb.other end }
    mp[#mp + 1] = { name = "CDM_resolveBy_item",              counter = true, fn = function() return rb.item or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_auraScope",         counter = true, fn = function() return rb.auraScope or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_spellQueue",        counter = true, fn = function() return rb.spellQueue or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_expiry",            counter = true, fn = function() return rb.expiry or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_mirrorCooldownOnly",counter = true, fn = function() return rb.mirrorCooldownOnly or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_auraScopedCooldown",counter = true, fn = function() return rb.auraScopedCooldown or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_ownedBar",           counter = true, fn = function() return rb.ownedBar or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_mirrorRefresh",      counter = true, fn = function() return rb.mirrorRefresh or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_typeRefresh",        counter = true, fn = function() return rb.typeRefresh or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_runtimeTypeRefresh", counter = true, fn = function() return rb.runtimeTypeRefresh or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_iconPlaced",         counter = true, fn = function() return rb.iconPlaced or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_rangeUsable",         counter = true, fn = function() return rb.rangeUsable or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_rangeTarget",         counter = true, fn = function() return rb.rangeTarget or 0 end }
    mp[#mp + 1] = { name = "CDM_resolveBy_rangeCheck",          counter = true, fn = function() return rb.rangeCheck or 0 end }
    mp[#mp + 1] = { name = "CDM_auraProbeHit",            counter = true, fn = function() return resolverStats.auraProbeHit end }
    mp[#mp + 1] = { name = "CDM_auraProbeGuardSkip",      counter = true, fn = function() return resolverStats.auraProbeGuardSkip end }
    mp[#mp + 1] = { name = "CDM_auraProbeExpensiveMiss",  counter = true, fn = function() return resolverStats.auraProbeExpensiveMiss end }
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "CDM_RuntimeEvents", frame = _runtimeFrame }
    markFn = ns.MemAuditProfilerMark
    -- Expose the setter only while debug is active; call sites guard with
    -- `if Resolvers.SetResolveCallerTag then` and skip the call entirely when nil.
    CDMResolvers.SetResolveCallerTag = function(tag)
        currentResolveCallerTag = tag
    end
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

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
            local itemID = (Sources.QueryBestOwnedItemVariant
                and Sources.QueryBestOwnedItemVariant(entry.id)) or entry.id
            _, _, _, _, icon = Sources.QueryItemInfoInstant(itemID)
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

local function GetCooldownInfoBoolean(info, key)
    if not info then
        return nil
    end
    local value = GetCooldownInfoField(info, key)
    return DecodePotentialSecretBoolean(value)
end

local function GetCurrentIsOnGCD(info)
    -- isOnGCD is NeverSecret (per SpellCooldownInfo docs + .taintrc), so read it
    -- straight off the cdInfo the resolver already fetched.
    return GetCooldownInfoBoolean(info, "isOnGCD")
end

local function QueryGCDDurationObject(spellID)
    local durObj = nil
    if spellID then
        durObj = QueryGCDDuration(spellID)
    end
    if not durObj and spellID ~= GCD_SPELL_ID then
        durObj = QueryGCDDuration(GCD_SPELL_ID)
    end
    return durObj
end

local function SpellMayHaveCharges(entry, spellID)
    if entry and (entry.hasCharges == true or entry.charges == true) then
        return true
    end
    if not spellID then
        return false
    end
    local gdb = QUI and QUI.db and QUI.db.global
    local svCharges = gdb and gdb.cdmChargeSpells
    return svCharges and svCharges[spellID] ~= nil or false
end

local function BuildMirrorDurationSourceKey(mode, sourceCooldownID, sourceSpellID, mirrorEpoch, cooldownLaneEpoch)
    if mode == "gcd-only" then
        return sourceSpellID
    end
    -- For real-cooldown modes (cooldown / item-cooldown), embed the
    -- cooldown lane + spell + cooldownLaneEpoch. We avoid mirrorEpoch
    -- because that bumps on every aura update and routine mirror tick
    -- (~200-500ms during combat), which forces SCFDO rebinds and
    -- restarts the C-side sweep animation before any visible progress
    -- accumulates.
    --
    -- cooldownLaneEpoch is bumped ONLY by cooldown-setter hooks
    -- (SetCooldown family + SCFDO + Clear) — i.e. when Blizzard's CV
    -- pushes a NEW cooldown timer to the frame. Within a single recharge
    -- cycle the value is stable so the swipe animation plays
    -- uninterrupted; on a cycle boundary (charge spell 0/2 → 1/2 → 2/2
    -- where the recharge IS the cooldown, DK Death Charge is the
    -- reference case) it advances and forces a SCFDO rebind so the
    -- icon's cooldown frame picks up the new cycle's start/duration
    -- instead of holding stale data from the previous cycle.
    --
    -- Falls back to (cooldownID, spellID) when cooldownLaneEpoch is
    -- absent (e.g. mock mirror states in tests) — same key as before
    -- the cycle-aware change.
    --
    -- Aura mode keeps the mepoch-suffixed key. Its DurationBindingMatches
    -- branch (cdm_icon_renderer.lua:6193-6194) compares userdata
    -- identity AFTER the sameBinding check, and
    -- C_UnitAuras.GetAuraDuration returns stable userdata across
    -- UNIT_AURA refreshes that share an auraInstanceID — so aura's
    -- dedup is already robust against the churn this change addresses.
    if mode == "cooldown" or mode == "item-cooldown" then
        if cooldownLaneEpoch ~= nil then
            return "mirror:" .. tostring(sourceCooldownID) .. ":" .. tostring(sourceSpellID)
                .. ":" .. tostring(cooldownLaneEpoch)
        end
        return "mirror:" .. tostring(sourceCooldownID) .. ":" .. tostring(sourceSpellID)
    end
    return "mirror:" .. tostring(sourceCooldownID) .. ":" .. tostring(mirrorEpoch)
end

local function IsSupportedMirrorMode(mode)
    return mode == "aura"
        or mode == "cooldown"
        or mode == "item-cooldown"
        or mode == "gcd-only"
        or mode == "inactive"
end

local function ShouldRenderLiveGCD(currentOnGCD)
    return currentOnGCD == true
end

function CDMResolvers.GetSpellCastInfo(spellID)
    if not spellID or not UnitCastingInfo then return false end
    local _, _, _, startMS, endMS, _, _, _, castSpellID = UnitCastingInfo("player")
    if castSpellID and castSpellID == spellID and startMS and endMS then
        return true, startMS / 1000, (endMS - startMS) / 1000, "cast"
    end
    return false
end

function CDMResolvers.GetSpellChannelInfo(spellID)
    if not spellID or not UnitChannelInfo then return false end
    local _, _, _, startMS, endMS, _, _, channelSpellID = UnitChannelInfo("player")
    if channelSpellID and channelSpellID == spellID and startMS and endMS then
        return true, startMS / 1000, (endMS - startMS) / 1000, "channel"
    end
    return false
end

function CDMResolvers.GetSpellBuffInfo(spellID, icon, entry)
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

function CDMResolvers.ResolveSpellActiveState(spellID, icon, entry)
    if not spellID then return false end

    local active, start, duration, activeType = CDMResolvers.GetSpellCastInfo(spellID)
    if active then return active, start, duration, activeType end

    active, start, duration, activeType = CDMResolvers.GetSpellChannelInfo(spellID)
    if active then return active, start, duration, activeType end

    active, start, duration, activeType = CDMResolvers.GetSpellBuffInfo(spellID, icon, entry)
    if active then return active, start, duration, activeType end

    local overrideID = QueryOverrideSpell(spellID)
    if overrideID and overrideID ~= spellID then
        active, start, duration, activeType = CDMResolvers.GetSpellCastInfo(overrideID)
        if active then return active, start, duration, activeType end
        active, start, duration, activeType = CDMResolvers.GetSpellChannelInfo(overrideID)
        if active then return active, start, duration, activeType end
        active, start, duration, activeType = CDMResolvers.GetSpellBuffInfo(overrideID, icon, entry)
        if active then return active, start, duration, activeType end
    end

    return false
end

local function NewCooldownActivityState(entry)
    return {
        isOnCooldown = false,
        rechargeActive = false,
        hasChargesRemaining = false,
        -- Internal QUI metadata only; do not populate this from secret API
        -- charge predicates.
        hasCharges = entry and entry.hasCharges or false,
        gcdOnly = false,
    }
end

local function ApplyStoredCooldownActivityState(state, storedState)
    if not (state and storedState and storedState.mode) then
        return false
    end

    local mode = storedState.mode
    state.gcdOnly = storedState.gcdOnly == true or mode == "gcd-only"
    if storedState.hasCharges ~= nil then
        state.hasCharges = storedState.hasCharges == true
    end
    if mode == "charge" then
        state.hasCharges = true
    end

    if storedState.isOnCooldown ~= nil
       or storedState.rechargeActive ~= nil
       or storedState.hasChargesRemaining ~= nil then
        state.isOnCooldown = storedState.isOnCooldown == true
        state.rechargeActive = storedState.rechargeActive == true
        state.hasChargesRemaining = storedState.hasChargesRemaining == true
        return true
    end

    if mode == "charge" then
        state.rechargeActive = storedState.active == true
        state.isOnCooldown = storedState.active == true
        state.hasChargesRemaining = state.rechargeActive == true
            and state.isOnCooldown ~= true
        return true
    elseif mode == "cooldown" or mode == "item-cooldown" then
        state.isOnCooldown = storedState.active == true
        return true
    elseif mode == "gcd-only" or mode == "aura" or mode == "inactive" then
        return true
    end

    return false
end

local function ResolveActivityRuntimeSpellID(icon, entry)
    if icon and icon._runtimeSpellID then
        return icon._runtimeSpellID
    end
    if not entry then return nil, nil end

    if entry.type == "macro" then
        local resolvedID, resolvedType = CDMResolvers.ResolveMacro(entry)
        if resolvedType == "spell" then
            return resolvedID, resolvedType
        end
        return nil, resolvedType
    end

    return entry.spellID or entry.overrideSpellID or entry.id, nil
end

local function MarkKnownChargeSpell(state, spellID)
    if not (state and spellID) or state.hasCharges then return end
    local gdb = QUI and QUI.db and QUI.db.global
    local svCharges = gdb and gdb.cdmChargeSpells
    if svCharges and svCharges[spellID] then
        state.hasCharges = true
    end
end

local function ApplyResolvedCooldownActivityState(state, resolvedState)
    if not (state and resolvedState and resolvedState.mode) then
        return false
    end

    local mode = resolvedState.mode
    state.gcdOnly = resolvedState.gcdOnly == true or mode == "gcd-only"
    state.hasCharges = resolvedState.hasCharges == true
        or state.hasCharges == true
        or mode == "charge"

    if resolvedState.isOnCooldown ~= nil
        or resolvedState.rechargeActive ~= nil
        or resolvedState.hasChargesRemaining ~= nil then
        state.isOnCooldown = resolvedState.isOnCooldown == true
        state.rechargeActive = resolvedState.rechargeActive == true
        state.hasChargesRemaining = resolvedState.hasChargesRemaining == true
        return true
    elseif mode == "cooldown" or mode == "item-cooldown" then
        state.isOnCooldown = resolvedState.active == true
        return true
    elseif mode == "charge" then
        state.rechargeActive = resolvedState.active == true
            or resolvedState.isActive == true
        state.isOnCooldown = resolvedState.active == true
        state.hasChargesRemaining = state.rechargeActive == true
            and state.isOnCooldown ~= true
        return true
    elseif mode == "gcd-only" or mode == "aura" or mode == "inactive" then
        return true
    end

    return false
end

function CDMResolvers.ResolveCooldownActivityStateFromResolvedState(entry, resolvedState)
    local state = NewCooldownActivityState(entry)
    if ApplyResolvedCooldownActivityState(state, resolvedState) then
        return state
    end
    return nil
end

local _activityCooldownStateContextOptions = {
    contextKey = "_activityCooldownStateContext",
    mirrorIdentityPolicy = "frame-or-entry",
}

local function BuildActivityCooldownStateContext(icon, entry, containerDB, spellID, runtimeOptions)
    if not (icon and entry) then return nil end

    local options = _activityCooldownStateContextOptions
    options.containerKey = (containerDB and containerDB.viewerType) or entry.viewerType
    options.totemSlot = icon._totemSlot
    options.useBuffSwipe = runtimeOptions and runtimeOptions.useBuffSwipe
    options.skipAuraPhase = runtimeOptions and runtimeOptions.skipAuraPhase == true
    options.showGCDSwipe = runtimeOptions and runtimeOptions.showGCDSwipe == true

    return CDMResolvers.BuildCooldownStateContext(icon, entry, spellID, options)
end

local function ApplyChargeRuntimeFallback(state, entry, spellID, isItemLike)
    if not (state and spellID) or isItemLike then
        return
    end
    if InCombatLockdown and InCombatLockdown()
        and not SpellMayHaveCharges(entry, spellID) then
        return
    end

    local ci = QueryCharges(spellID)
    if ci then
        local maxC = ci.maxCharges
        -- Any spell that the charge API reports for (maxCharges >= 1) is a
        -- charge-system spell. Single-charge cases include the shared brez
        -- pool in raids/M+ (Rebirth/Raise Ally/Intercession), where the
        -- displayed cooldown is the recharge timer, not a "spell blocked"
        -- cooldown — so the icon must stay saturated while a charge is
        -- available. Downstream `cdInfo.isActive` still gates actual usability.
        if IsSafeNumeric(maxC) and maxC >= 1 then
            state.hasCharges = true
        end
    end

    if not state.hasCharges then
        return
    end

    local cdInfo = QueryCooldown(spellID)
    local cooldownActive = cdInfo and IsCooldownInfoActive(cdInfo)
    if cooldownActive == true then
        state.rechargeActive = true
        state.isOnCooldown = true
        return
    elseif cooldownActive == false then
        -- Do not use SpellChargeInfo.currentCharges here. The charge info
        -- payload can be restricted in combat; a readable "spell cooldown is
        -- inactive" signal is enough to know the charged spell is not fully
        -- locked out.
        state.hasChargesRemaining = true
        state.isOnCooldown = false
    end

    if ci then
        local chargeActive = DecodePotentialSecretBoolean(ci.isActive)
        if chargeActive == true then
            state.rechargeActive = true
        end
    end
end

local function ResolveCooldownActivityStateCore(icon, entry, containerDB, now, runtimeOptions)
    local state = NewCooldownActivityState(entry)
    if not icon or not entry then return state end

    now = now or GetTime()
    local runtimeStore = ns.CDMRuntimeStore
    local storedState = runtimeStore and runtimeStore.GetFrameState
        and runtimeStore.GetFrameState(icon)
    if ApplyStoredCooldownActivityState(state, storedState) then
        return state
    end

    local spellID, macroResolvedType = ResolveActivityRuntimeSpellID(icon, entry)
    local isItemLike = IsItemLikeEntry(entry)
        or (entry.type == "macro" and macroResolvedType == "item")

    MarkKnownChargeSpell(state, spellID)

    local resolver = CDMResolvers.ResolveCooldownState
    if resolver then
        local resolvedState = resolver(BuildActivityCooldownStateContext(icon, entry, containerDB, spellID, runtimeOptions))
        if ApplyResolvedCooldownActivityState(state, resolvedState) then
            return state
        end
    end

    ApplyChargeRuntimeFallback(state, entry, spellID, isItemLike)

    if state.hasCharges then
        return state
    end

    return state
end

function CDMResolvers.ResolveCooldownActivityState(icon, entry, containerDB, now, runtimeOptions)
    if icon and RuntimeQueries and RuntimeQueries.WithRuntimeQueryOwner then
        return RuntimeQueries.WithRuntimeQueryOwner(
            icon, ResolveCooldownActivityStateCore, icon, entry, containerDB, now, runtimeOptions)
    end
    return ResolveCooldownActivityStateCore(icon, entry, containerDB, now, runtimeOptions)
end


-- DURATION OBJECT RESOLVERS

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

-- Reused scratch + hoisted helpers for ResolveAuraActiveState. The old inline
-- versions allocated two tables AND up to four closures per call on the aura
-- probe path; module-level scratch (wiped per call) plus module-level helpers
-- removes all of that GC churn. The capture block (lookup/seen) is fully
-- consumed before the query block runs, and GetCapturedAuraForLookup iterates
-- the array synchronously without retaining it, so reuse is safe. Not
-- re-entrant: no callee re-enters ResolveAuraActiveState.
local _auraActiveLookupIDs = {}
local _auraActiveSeenLookup = {}
local _auraActiveQuerySeen = {}

local function _AuraActiveAddLookup(id)
    if not id or _auraActiveSeenLookup[id] then return end
    _auraActiveSeenLookup[id] = true
    _auraActiveLookupIDs[#_auraActiveLookupIDs + 1] = id
end

local function _AuraActiveAddMappedLookups(CDMSpellData, id)
    if not (id and CDMSpellData.GetAuraIDsForSpell) then return end
    local mappedIDs = CDMSpellData:GetAuraIDsForSpell(id)
    if mappedIDs then
        for _, auraID in ipairs(mappedIDs) do _AuraActiveAddLookup(auraID) end
    end
end

local function _AuraActiveTryQuery(id)
    if not id or _auraActiveQuerySeen[id] then return nil end
    _auraActiveQuerySeen[id] = true
    if Sources.QueryUnitAuraBySpellID then
        local auraData = Sources.QueryUnitAuraBySpellID("player", id)
        if auraData then return auraData end
    end
    if Sources.QueryPlayerAuraBySpellID then
        local auraData = Sources.QueryPlayerAuraBySpellID(id)
        if auraData then return auraData end
    end
    return nil
end

local function _AuraActiveTryMappedIDs(CDMSpellData, id)
    if not id then return false end
    local mappedIDs = CDMSpellData:GetAuraIDsForSpell(id)
    if mappedIDs then
        for _, auraID in ipairs(mappedIDs) do
            local mappedAuraData = _AuraActiveTryQuery(auraID)
            if mappedAuraData then
                return true, "player", GetAuraDataInstanceID(mappedAuraData)
            end
        end
    end
    return false
end

function CDMResolvers.ResolveAuraActiveState(entry)
    if not entry then return false, nil, nil end

    local sid = entry.overrideSpellID or entry.spellID or entry.id
    if not sid then
        return false, nil, nil
    end

    -- Captured UNIT_AURA payloads are combat-safe and include aura IDs that
    -- differ from the configured cast/ability ID.
    local CDMSpellData = ns.CDMSpellData
    if CDMSpellData and CDMSpellData.GetCapturedAuraForLookup then
        wipe(_auraActiveLookupIDs)
        wipe(_auraActiveSeenLookup)
        _AuraActiveAddLookup(sid)
        _AuraActiveAddLookup(entry.spellID)
        _AuraActiveAddLookup(entry.id)
        _AuraActiveAddMappedLookups(CDMSpellData, sid)
        _AuraActiveAddMappedLookups(CDMSpellData, entry.spellID)
        _AuraActiveAddMappedLookups(CDMSpellData, entry.id)
        local captured = CDMSpellData.GetCapturedAuraForLookup(_auraActiveLookupIDs, entry.name)
        local auraInstanceID = captured and captured.auraInstanceID
        if captured and HasOpaqueValue(auraInstanceID) then
            return true, captured.unit or "player", auraInstanceID
        end
    end

    -- Direct aura query fallback. If the query returns AuraData, existence is
    -- enough to classify the aura as active; auraInstanceID is forwarded to
    -- downstream C-side consumers.
    if Sources and (Sources.QueryUnitAuraBySpellID or Sources.QueryPlayerAuraBySpellID) then
        wipe(_auraActiveQuerySeen)

        local auraData = _AuraActiveTryQuery(sid)
        if auraData then return true, "player", GetAuraDataInstanceID(auraData) end
        auraData = _AuraActiveTryQuery(entry.spellID)
        if auraData then return true, "player", GetAuraDataInstanceID(auraData) end
        auraData = _AuraActiveTryQuery(entry.id)
        if auraData then return true, "player", GetAuraDataInstanceID(auraData) end

        if CDMSpellData and CDMSpellData.GetAuraIDsForSpell then
            local active, unit, instID = _AuraActiveTryMappedIDs(CDMSpellData, sid)
            if active then return active, unit, instID end
            active, unit, instID = _AuraActiveTryMappedIDs(CDMSpellData, entry.spellID)
            if active then return active, unit, instID end
            active, unit, instID = _AuraActiveTryMappedIDs(CDMSpellData, entry.id)
            if active then return active, unit, instID end
        end
    end

    -- Name fallback for cast-id vs aura-id mismatches that share names and
    -- are not in the CDM catalog.
    if entry.name and entry.name ~= ""
        and Sources and Sources.QueryAuraDataBySpellName then
        local auraData = Sources.QueryAuraDataBySpellName("player", entry.name, "HELPFUL")
        if auraData then
            return true, "player", GetAuraDataInstanceID(auraData)
        end
    end

    return false, nil, nil
end

local PLAYER_AURA_CAPTURE_LOOKUP_UNITS = { "player", "pet" }

-- Reused scratch + hoisted helpers for QueryCapturedPlayerAuraDuration; same
-- rationale as the ResolveAuraActiveState scratch above (kills two tables +
-- two closures per call). Distinct tables from the ResolveAuraActiveState
-- scratch, so the two are safe even if both run within one resolve sequence.
local _capturedDurLookupIDs = {}
local _capturedDurSeen = {}

local function _CapturedDurAddLookup(id)
    if ResolverIsSecretValue(id) then return end
    if id == nil then return end
    local idType = type(id)
    if idType ~= "number" and idType ~= "string" then return end
    if _capturedDurSeen[id] then return end
    _capturedDurSeen[id] = true
    _capturedDurLookupIDs[#_capturedDurLookupIDs + 1] = id
end

local function _CapturedDurAddCooldownAuraLookup(id)
    if ResolverIsSecretValue(id) or id == nil then return end
    if not (Sources and Sources.QueryCooldownAuraBySpellID) then return end
    _CapturedDurAddLookup(Sources.QueryCooldownAuraBySpellID(id))
end

local function QueryCapturedPlayerAuraDuration(spellID, name)
    if not InCombatLockdown()
       or not (Sources and Sources.QueryAuraDuration) then
        return nil
    end

    local CDMSpellData = ns.CDMSpellData
    if not (CDMSpellData and CDMSpellData.GetCapturedAuraForLookup) then
        return nil
    end

    wipe(_capturedDurLookupIDs)
    wipe(_capturedDurSeen)

    if CDMSpellData.GetAuraIDsForSpell and spellID then
        local catalogIDs = CDMSpellData:GetAuraIDsForSpell(spellID)
        if catalogIDs then
            for _, auraID in ipairs(catalogIDs) do
                _CapturedDurAddLookup(auraID)
            end
        end
    end
    _CapturedDurAddCooldownAuraLookup(spellID)
    _CapturedDurAddLookup(spellID)

    local captured = CDMSpellData.GetCapturedAuraForLookup(
        _capturedDurLookupIDs, name, PLAYER_AURA_CAPTURE_LOOKUP_UNITS, false)
    local auraInstanceID = captured and captured.auraInstanceID
    if not HasOpaqueValue(auraInstanceID) then
        return nil
    end

    local auraUnit = captured.unit or "player"
    return Sources.QueryAuraDuration(auraUnit, auraInstanceID),
        captured.spellID,
        auraInstanceID,
        auraUnit
end

local function QueryPlayerAuraDurationBySpellID(rawSpellID, name)
    if not rawSpellID or not (Sources and Sources.QueryAuraDuration) then
        return nil
    end

    local capturedDurObj, capturedAuraSpellID, capturedAuraInstanceID, capturedAuraUnit =
        QueryCapturedPlayerAuraDuration(rawSpellID, name)
    if capturedDurObj then
        return capturedDurObj, capturedAuraSpellID, capturedAuraInstanceID, capturedAuraUnit
    end

    local function queryAuraData(auraSpellID)
        if ResolverIsSecretValue(auraSpellID) or auraSpellID == nil then return nil end
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
        if not HasOpaqueValue(auraInstanceID) then return nil end

        return Sources.QueryAuraDuration("player", auraInstanceID), auraSpellID, auraInstanceID, "player"
    end

    if Sources.QueryCooldownAuraBySpellID then
        local auraSpellID = Sources.QueryCooldownAuraBySpellID(rawSpellID)
        if not ResolverIsSecretValue(auraSpellID) and auraSpellID ~= nil then
            local durObj, resolvedAuraSpellID, auraInstanceID, auraUnit = queryDuration(auraSpellID)
            if durObj then
                return durObj, resolvedAuraSpellID, auraInstanceID, auraUnit
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

    local capturedDurObj, _, capturedAuraInstanceID, capturedAuraUnit =
        QueryCapturedPlayerAuraDuration(nil, name)
    if capturedDurObj then
        return capturedDurObj, capturedAuraInstanceID, capturedAuraUnit
    end

    if not Sources.QueryAuraDataBySpellName then
        return nil
    end

    local auraData = Sources.QueryAuraDataBySpellName("player", name, "HELPFUL")
    if not auraData then
        return nil
    end

    local auraInstanceID = GetAuraDataInstanceID(auraData)
    if not HasOpaqueValue(auraInstanceID) then return nil end

    return Sources.QueryAuraDuration("player", auraInstanceID), auraInstanceID, "player"
end

local function IsUsableMirrorID(value)
    if ResolverIsSecretValue(value) then return false end
    return type(value) == "number" and value > 0
end

local function NormalizeMirrorCategory(category)
    if Shared and Shared.NormalizeMirrorCategory then
        return Shared.NormalizeMirrorCategory(category)
    end
    if ResolverIsSecretValue(category) or type(category) ~= "string" then
        return nil
    end
    if category == "essential" or category == "utility"
        or category == "buff" or category == "trackedBar" then return category end
    return nil
end

local function IsAuraMirrorCategory(category)
    if Shared and Shared.IsAuraMirrorCategory then
        return Shared.IsAuraMirrorCategory(category)
    end
    category = NormalizeMirrorCategory(category)
    return category == "buff" or category == "trackedBar"
end

local function IsCooldownMirrorCategory(category)
    if Shared and Shared.IsCooldownMirrorCategory then
        return Shared.IsCooldownMirrorCategory(category)
    end
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

local function AddMirrorIdentityID(set, id)
    if not IsUsableMirrorID(id) then return end
    set[id] = true
end

local function AddEntryMirrorIdentityID(set, id)
    if not IsUsableMirrorID(id) then return end
    set[id] = true
    local overrideID = QueryOverrideSpell(id)
    if overrideID ~= id then
        AddMirrorIdentityID(set, overrideID)
    end
end

local _mirrorEntryIdentityScratch = {}

local function ClearMirrorEntryIdentityScratch()
    for id in pairs(_mirrorEntryIdentityScratch) do
        _mirrorEntryIdentityScratch[id] = nil
    end
end

local function MirrorStateHasSpellIdentity(state)
    if not state then return false end
    if IsUsableMirrorID(state.overrideTooltipSpellID)
        or IsUsableMirrorID(state.overrideSpellID)
        or IsUsableMirrorID(state.spellID) then
        return true
    end
    local linkedStateIDs = state.linkedSpellIDs
    if type(linkedStateIDs) == "table" then
        for _, linkedID in ipairs(linkedStateIDs) do
            if IsUsableMirrorID(linkedID) then return true end
        end
    end
    return false
end

local function MirrorStateMatchesEntryIdentity(state, entry)
    if not (state and entry) then return true end
    if not MirrorStateHasSpellIdentity(state) then return true end

    local entryIDs = _mirrorEntryIdentityScratch
    ClearMirrorEntryIdentityScratch()
    AddEntryMirrorIdentityID(entryIDs, SafeEntryField(entry, "overrideSpellID"))
    AddEntryMirrorIdentityID(entryIDs, SafeEntryField(entry, "spellID"))
    AddEntryMirrorIdentityID(entryIDs, SafeEntryField(entry, "id"))

    if next(entryIDs) == nil then return true end

    local sawStateIdentity = false

    local id = state.overrideTooltipSpellID
    if IsUsableMirrorID(id) then
        sawStateIdentity = true
        if entryIDs[id] == true then return true end
    end

    id = state.overrideSpellID
    if IsUsableMirrorID(id) then
        sawStateIdentity = true
        if entryIDs[id] == true then return true end
    end

    id = state.spellID
    if IsUsableMirrorID(id) then
        sawStateIdentity = true
        if entryIDs[id] == true then return true end
    end

    local linkedStateIDs = state.linkedSpellIDs
    if type(linkedStateIDs) == "table" then
        for _, linkedID in ipairs(linkedStateIDs) do
            if IsUsableMirrorID(linkedID) then
                sawStateIdentity = true
                if entryIDs[linkedID] == true then return true end
            end
        end
    end

    return not sawStateIdentity
end

function CDMResolvers._MirrorStateContainsEntryID(state, id)
    if not (state and IsUsableMirrorID(id) and MirrorStateHasSpellIdentity(state)) then
        return false
    end

    local overrideID = QueryOverrideSpell(id)
    local hasOverride = IsUsableMirrorID(overrideID) and overrideID ~= id

    local candidate = state.overrideTooltipSpellID
    if IsUsableMirrorID(candidate) and (candidate == id or (hasOverride and candidate == overrideID)) then
        return true
    end

    candidate = state.overrideSpellID
    if IsUsableMirrorID(candidate) and (candidate == id or (hasOverride and candidate == overrideID)) then
        return true
    end

    candidate = state.spellID
    if IsUsableMirrorID(candidate) and (candidate == id or (hasOverride and candidate == overrideID)) then
        return true
    end

    local linkedStateIDs = state.linkedSpellIDs
    if type(linkedStateIDs) == "table" then
        for _, linkedID in ipairs(linkedStateIDs) do
            if IsUsableMirrorID(linkedID)
                and (linkedID == id or (hasOverride and linkedID == overrideID)) then
                return true
            end
        end
    end

    return false
end

local function MirrorBindingIsStrictAura(entry, entryType, viewerCategory)
    if not entry then return false end
    local entryKind = SafeEntryField(entry, "kind")
    local normalizedEntryType = entryType or SafeEntryField(entry, "type")
    local entryIsAura = SafeEntryField(entry, "isAura")
    return entryKind == "aura"
        or normalizedEntryType == "aura"
        or entryIsAura == true
        or IsAuraMirrorCategory(viewerCategory)
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

local function ExplicitMirrorIdentityStateAccepted(
    mirror, entry, cooldownID, category, viewerCategory, strictAuraBinding)
    local acceptedCategory, state = MirrorIdentityStateAccepted(
        mirror, cooldownID, category, viewerCategory, strictAuraBinding)
    if not acceptedCategory then
        return nil, nil
    end
    if not MirrorStateMatchesEntryIdentity(state, entry) then
        return nil, nil
    end
    return acceptedCategory, state
end

local function ResolveMirrorIDInCategory(mirror, id, category, viewerCategory, strictAuraBinding)
    if not IsUsableMirrorID(id) then return nil, nil, nil end

    local cooldownID
    local requireStateIdentity = false
    if strictAuraBinding and IsAuraMirrorCategory(category) then
        if mirror.GetDirectCooldownIDForViewer then
            cooldownID = mirror.GetDirectCooldownIDForViewer(id, category)
        end
        if not IsUsableMirrorID(cooldownID) then
            if not mirror.GetCooldownIDForViewer then return nil, nil, nil end
            cooldownID = mirror.GetCooldownIDForViewer(id, category)
            requireStateIdentity = true
        end
    else
        if not mirror.GetCooldownIDForViewer then return nil, nil, nil end
        cooldownID = mirror.GetCooldownIDForViewer(id, category)
    end

    if not IsUsableMirrorID(cooldownID) then return nil, nil, nil end

    local acceptedCategory, state = MirrorIdentityStateAccepted(
        mirror, cooldownID, category, viewerCategory, strictAuraBinding)
    if acceptedCategory then
        if requireStateIdentity
            and not CDMResolvers._MirrorStateContainsEntryID(state, id) then
            return nil, nil, nil
        end
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

-- Singleton identity result for the resolver hot path. Callers MUST consume
-- this immediately; the next mirror identity resolution reuses the table.
local _mirrorIdentityScratch = {
    cooldownID = nil,
    category = nil,
    state = nil,
    viewerCategory = nil,
    strictAuraBinding = false,
    source = nil,
    entryType = nil,
}

local function WipeMirrorIdentityScratch()
    local identity = _mirrorIdentityScratch
    identity.cooldownID = nil
    identity.category = nil
    identity.state = nil
    identity.viewerCategory = nil
    identity.strictAuraBinding = false
    identity.source = nil
    identity.entryType = nil
end

local function StoreMirrorIdentity(
    cooldownID, category, state, viewerCategory, strictAuraBinding, source, entryType)
    local identity = _mirrorIdentityScratch
    identity.cooldownID = cooldownID
    identity.category = category
    identity.state = state
    identity.viewerCategory = viewerCategory
    identity.strictAuraBinding = strictAuraBinding == true
    identity.source = source
    identity.entryType = entryType
    return identity
end

local function ResolveExplicitMirrorIdentityState(
    mirror, entry, cooldownID, category, viewerCategory, strictAuraBinding, source, entryType)
    if not (IsUsableMirrorID(cooldownID) and mirror.GetStateByCooldownID) then
        return nil
    end

    local acceptedCategory, state = ExplicitMirrorIdentityStateAccepted(
        mirror, entry, cooldownID, category, viewerCategory, strictAuraBinding)
    if not acceptedCategory then
        return nil
    end

    return StoreMirrorIdentity(
        cooldownID, acceptedCategory, state,
        viewerCategory, strictAuraBinding, source, entryType)
end

local function ValidateMirrorIdentityEntry(entry, mirror)
    if not (entry and mirror) then return false, nil, nil, nil end

    local entryType = SafeEntryField(entry, "type")
    if entryType
        and entryType ~= "spell"
        and entryType ~= "aura"
        and entryType ~= "cooldown" then
        return false, nil, nil, nil
    end

    local viewerCategory = ResolveEntryMirrorCategory(entry)
    local strictAuraBinding = MirrorBindingIsStrictAura(entry, entryType, viewerCategory)
    return true, entryType, viewerCategory, strictAuraBinding
end

local function ResolveBlizzardMirrorIdentityState(entry)
    WipeMirrorIdentityScratch()

    local mirror = ns.CDMBlizzMirror
    local valid, entryType, viewerCategory, strictAuraBinding =
        ValidateMirrorIdentityEntry(entry, mirror)
    if not valid then
        return nil
    end

    local category1, category2 = GetMirrorCategoryCandidates(viewerCategory, strictAuraBinding)

    local explicitCooldownID = entry.cooldownID
    local identity = ResolveExplicitMirrorIdentityState(
        mirror, entry, explicitCooldownID, category1,
        viewerCategory, strictAuraBinding, "entry-cooldownID", entryType)
    if identity then
        return identity
    end

    if category2 then
        identity = ResolveExplicitMirrorIdentityState(
            mirror, entry, explicitCooldownID, category2,
            viewerCategory, strictAuraBinding, "entry-cooldownID", entryType)
        if identity then
            return identity
        end
    end

    local cooldownID, acceptedCategory, state = ResolveMirrorEntryInCategory(
        mirror, entry, category1, viewerCategory, strictAuraBinding)
    if cooldownID then
        return StoreMirrorIdentity(
            cooldownID, acceptedCategory, state,
            viewerCategory, strictAuraBinding, "entry", entryType)
    end

    if category2 then
        cooldownID, acceptedCategory, state = ResolveMirrorEntryInCategory(
            mirror, entry, category2, viewerCategory, strictAuraBinding)
        if cooldownID then
            return StoreMirrorIdentity(
                cooldownID, acceptedCategory, state,
                viewerCategory, strictAuraBinding, "entry", entryType)
        end
    end

    return nil
end

function CDMResolvers.ResolveBlizzardMirrorIdentityState(entry)
    return ResolveBlizzardMirrorIdentityState(entry)
end

local function ResolveCooldownContextMirror(owner, entry, options)
    local policy = options and options.mirrorIdentityPolicy or "frame-or-entry"
    local cooldownID
    local category

    if policy ~= "entry" and policy ~= "entry-or-fallback" then
        cooldownID = options and options.mirrorCooldownID
        category = options and options.mirrorCategory
        if cooldownID == nil and owner then
            cooldownID = owner._blizzMirrorCooldownID
            category = owner._blizzMirrorCategory
        end
    end

    if policy ~= "frame-only"
        and (cooldownID == nil or policy == "entry" or policy == "entry-or-fallback") then
        local identity = ResolveBlizzardMirrorIdentityState(entry)
        if identity and identity.cooldownID ~= nil then
            return identity.cooldownID, identity.category
        end
    end

    if cooldownID == nil and policy == "entry-or-fallback" and entry then
        cooldownID = entry.cooldownID
        category = ResolveEntryMirrorCategory(entry)
    end

    return cooldownID, category
end

local function ClearCooldownStateContext(context)
    context.owner = nil
    context.entry = nil
    context.runtimeSpellID = nil
    context.mirrorCooldownID = nil
    context.mirrorCategory = nil
    context.cachedMirrorState = nil
    context.cachedMirrorSourceID = nil
    context.containerKey = nil
    context.totemSlot = nil
    context.useBuffSwipe = nil
    context.skipAuraPhase = nil
    context.showGCDSwipe = nil
    context.lastChargeMirrorCooldownID = nil
    context.lastChargeMirrorCategory = nil
    context.lastChargeRuntimeSpellID = nil
end

function CDMResolvers.BuildCooldownStateContext(owner, entry, runtimeSpellID, options)
    local context = options and options.context
    local contextKey = options and options.contextKey or "_cooldownStateContext"
    if not context and owner then
        context = owner[contextKey]
        if not context then
            context = {}
            owner[contextKey] = context
        end
    end
    if not context then
        context = {}
    end

    ClearCooldownStateContext(context)

    local containerKey = options and options.containerKey
    if containerKey == nil then
        containerKey = entry and entry.viewerType
    end
    if containerKey == nil and options then
        containerKey = options.fallbackContainerKey
    end

    local totemSlot = options and options.totemSlot
    if totemSlot == nil and owner then
        totemSlot = owner._totemSlot
    end

    local mirrorCooldownID, mirrorCategory = ResolveCooldownContextMirror(owner, entry, options)

    context.entry = entry
    context.owner = owner
    context.runtimeSpellID = runtimeSpellID
    context.mirrorCooldownID = mirrorCooldownID
    context.mirrorCategory = mirrorCategory
    context.cachedMirrorState = options and options.cachedMirrorState
    context.cachedMirrorSourceID = options and options.cachedMirrorSourceID
    context.containerKey = containerKey
    context.totemSlot = totemSlot
    context.useBuffSwipe = options and options.useBuffSwipe
    context.skipAuraPhase = options and options.skipAuraPhase == true
    context.showGCDSwipe = options and options.showGCDSwipe == true
    context.lastChargeMirrorCooldownID = options and options.lastChargeMirrorCooldownID
    context.lastChargeMirrorCategory = options and options.lastChargeMirrorCategory
    context.lastChargeRuntimeSpellID = options and options.lastChargeRuntimeSpellID
    return context
end

local function SafeMirrorString(value)
    if ResolverIsSecretValue(value) or type(value) ~= "string" then
        return nil
    end
    return value
end

local function SafeMirrorCountNumber(value)
    if ResolverIsSecretValue(value) or value == nil then
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

-- Singleton scratch tables for mirror payload generation. Both the runtime aura
-- resolver's closure-heavy churn and BuildMirrorRenderPayload's
-- fresh-table-per-call pattern dominated combat GC. The aura resolver was fixed
-- in 2026-05-11; this scratch pair fixes the mirror payload side.
--
-- Callers MUST treat these as consume-immediately. The resolved cooldown
-- state copies count fields into its own scratch table so renderers do not
-- retain this singleton.
local _mirrorPayloadScratch = {
    mirrorBacked = true,
    state = nil, active = false, mode = nil, sourceID = nil,
    cooldownID = nil, category = nil, spellID = nil, auraInstanceID = nil,
    durObj = nil, durationStateUnknown = nil, auraUnit = nil,
    auraData = nil,
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
    p.auraData = nil
    p.cooldownDurObj = nil
    p.totemSlot = nil; p.totemName = nil; p.totemIcon = nil
    p.isTotemInstance = false
    p.count = nil
    p.hasExpirationTime = nil; p.hideDurationText = nil
end

local function BuildMirrorCountPayload(m, renderMode)
    if not m then return nil end
    local c = _mirrorCountScratch
    c.value = nil; c.sinkText = nil; c.shown = false; c.source = nil

    -- Cross-category aura applications carried from the source child (see
    -- CaptureAuraInstanceFromChildFrame). The host child only has its own
    -- (chargeless) ChargeCount text, so prefer the borrowed aura stack text --
    -- but only while this payload renders the aura. When the icon is on
    -- cooldown (debuff still up but the spell cooldown is showing) or the
    -- viewer is configured to skip the aura phase, renderMode is not "aura"
    -- and the carried count must stay off.
    if renderMode == "aura"
        and (ResolverIsSecretValue(m.auraStackText) or m.auraStackText ~= nil) then
        if SafeBoolean(m.auraStackTextShown) ~= false then
            c.value = SafeMirrorCountNumber(m.auraStackText)
            c.sinkText = m.auraStackText
            c.shown = true
            c.source = SafeMirrorString(m.auraStackTextSource) or "Applications"
            return c
        end
    end

    local shown = SafeBoolean(m.stackTextShown)
    local source = SafeMirrorString(m.stackTextSource) or "mirror-text"
    if shown == false then
        c.shown = false
        c.source = source
        return c
    end

    local stackText = m.stackText
    if ResolverIsSecretValue(stackText) or stackText ~= nil then
        c.value = SafeMirrorCountNumber(stackText)
        c.sinkText = stackText
        c.shown = true
        c.source = source
        return c
    end

    return nil
end

local function MirrorAuraHasCapturedPresence(m)
    -- Target auraData can be unreadable during combat; a stamped mirror aura
    -- instance plus duration/count evidence is enough to keep the aura lane.
    if not (m and HasOpaqueValue(m.auraInstanceID)) then return false end
    if HasOpaqueValue(m.auraDurObj) then return true end
    if m.auraDurationStateUnknown == true then return true end
    if SafeBoolean(m.childIsActive) == true then return true end
    if ResolverIsSecretValue(m.auraStackText) or m.auraStackText ~= nil then return true end
    return false
end

-- Classify what mode this mirror state should render as, by querying live
-- API state at evaluation time. The mirror caches only event-bound state
-- (aura attribution, totem ownership, registration metadata); the
-- aura / cooldown / gcd-only / inactive decision lives here, against the
-- NeverSecret fields of C_Spell.GetSpellCooldown and C_UnitAuras.
--
-- suppressAura is true when the caller already finished the aura phase and
-- wants the underlying cooldown surfaced (icon's skipAuraPhase contract).
--
-- Returns (mode, queriedAuraData) so the payload builder can reuse the
-- aura data without re-querying.
-- True when C_Spell.GetSpellCharges reports an active recharge cycle for a
-- multi-charge spell. Some charge spells (DK Death Charge is the reference
-- case) leave C_Spell.GetSpellCooldown.isActive=false while one charge is
-- regenerating, because the spell is castable from another charge and the
-- recharge timing lives only on the charges API. Matches Blizzard's
-- CooldownViewer CheckCacheCooldownValuesFromCharges precedence.
--
-- mayHaveCharges is a hint from the caller (entry.hasCharges / m.charges).
-- In combat we only probe the charges API when this hint is true or the
-- saved chargeSpells metadata already records the spell, to avoid
-- tainted API calls on bare cooldowns.
local function HasActiveChargeRecharge(spellID, mayHaveCharges)
    if not spellID then return false end
    if InCombatLockdown and InCombatLockdown() and not mayHaveCharges then
        local gdb = QUI and QUI.db and QUI.db.global
        local svCharges = gdb and gdb.cdmChargeSpells
        if not (svCharges and svCharges[spellID]) then
            return false
        end
    end
    local chargeInfo = QueryCharges(spellID)
    if not chargeInfo then return false end
    local maxCharges = chargeInfo.maxCharges
    if not (IsSafeNumeric(maxCharges) and maxCharges > 1) then return false end
    return DecodePotentialSecretBoolean(chargeInfo.isActive) == true
end

local function PlayerIsCastingMirrorSpell(m, sid)
    if not sid then return false end
    if not (UnitCastingInfo or UnitChannelInfo) then return false end

    local castSpellID, channelSpellID
    if UnitCastingInfo then
        local _, _, _, _, _, _, _, _, csid = UnitCastingInfo("player")
        castSpellID = csid
    end
    if UnitChannelInfo then
        local _, _, _, _, _, _, _, chsid = UnitChannelInfo("player")
        channelSpellID = chsid
    end
    if castSpellID == nil and channelSpellID == nil then return false end

    if castSpellID == sid or channelSpellID == sid then return true end
    if m and m.overrideSpellID and m.overrideSpellID ~= sid then
        if castSpellID == m.overrideSpellID or channelSpellID == m.overrideSpellID then
            return true
        end
    end
    if Sources and Sources.QueryBaseSpell then
        local baseSid = Sources.QueryBaseSpell(sid)
        if baseSid and baseSid ~= sid then
            if castSpellID == baseSid or channelSpellID == baseSid then return true end
        end
    end
    return false
end

-- A transient PROC override (e.g. Hammer of Light 427453 overriding Wake of
-- Ashes 255937 on a Light's Guidance proc) makes the override the AVAILABLE
-- spell while the base keeps recharging on its own lane. C_Spell.GetSpellCooldown
-- on the override reports the base's SHARED recharge slot as active, so the naive
-- cooldown branch paints the base recharge under the override's art. Blizzard's
-- CooldownViewer shows the proc READY instead. Detect it precisely so ONLY this
-- shape is affected:
--   * sid is the registered base (sid == m.spellID, distinct from override),
--   * a live override exists (m.overrideSpellID),
--   * the base (m.spellID) is still INDEPENDENTLY known -> a transient proc, NOT
--     a permanent talent conversion (Berserk 50334 -> Incarnation 102558, where
--     the base reports isActive=false and the override owns the real cooldown),
--   * the base is itself on a REAL (non-GCD) recharge -> the override's reported
--     cooldown really is the base's shared slot. (Augmentation Breath of Eons'
--     base reports isOnGCD=true, so it fails this and keeps its handling.)
-- Called only from the base real-cooldown branch, so `sid` is the registered
-- base and is already known to be on a real (non-GCD) recharge. This is a
-- transient proc when an override is currently ACTIVE (m.overrideSpellID, set by
-- Blizzard when the proc replaces the base on the bar) and the base is still
-- INDEPENDENTLY known. Talent conversions (Berserk 50334 -> Incarnation 102558)
-- never reach here -- their base reports isActive=false. m.overrideSpellID /
-- m.spellID are sanitized mirror fields; QueryIsSpellKnownOrPlayerSpell is a
-- non-secret IsSpellKnown/IsPlayerSpell probe.
local function IsTransientProcOverrideReady(m, sid)
    if not (m and sid) then return false end
    -- Read the override from the LIVE spell-override map (C_Spell.GetOverrideSpell
    -- via QueryOverrideSpell), NOT m.overrideSpellID. The mirror field comes from
    -- C_CooldownViewer.GetCooldownViewerCooldownInfo, which does not expose every
    -- proc override (Hammer of Light 427453 overriding Wake of Ashes 255937 is the
    -- reference case: GetOverrideSpell flips to 427453 but the cooldown-info
    -- override field stays at the base 255937, so the old m.overrideSpellID read
    -- never fired this guard and the base recharge painted under the usable proc).
    -- QueryOverrideSpell is kept fresh at the proc edge by the glow-event override
    -- cache clear in cdm_effects.lua.
    local ovSid = QueryOverrideSpell(sid)
    if not ovSid or ovSid == sid then return false end
    if m.spellID and m.spellID ~= sid then return false end
    return Sources ~= nil and Sources.QueryIsSpellKnownOrPlayerSpell ~= nil
        and Sources.QueryIsSpellKnownOrPlayerSpell(sid) == true
end

-- Returns (mode, auraData, cooldownSpellID). cooldownSpellID is the spellID
-- where an active cooldown was detected (used by BuildMirrorRenderPayload to
-- acquire the matching DurationObject). It is nil for "aura" and "inactive"
-- modes and for totem-derived modes where no per-spell probe was performed.
local function DeriveMirrorPayloadMode(m, sid, suppressAura)
    if not m then return "inactive", nil, nil end

    local category = NormalizeMirrorCategory(m.viewerCategory)
    local isAuraCategory = category == "buff" or category == "trackedBar"

    if not suppressAura then
        if HasOpaqueValue(m.totemSlot) or HasOpaqueValue(m.totemDurObj) then
            return isAuraCategory and "aura" or "cooldown", nil, nil
        end

        if HasOpaqueValue(m.auraInstanceID) then
            local auraUnit = SafeMirrorString(m.auraUnit) or "player"
            local aura = m.auraData
            if not aura and Sources and Sources.QueryAuraDataByAuraInstanceID then
                aura = Sources.QueryAuraDataByAuraInstanceID(auraUnit, m.auraInstanceID)
            end
            if aura then return "aura", aura, nil end
            if MirrorAuraHasCapturedPresence(m) then
                return "aura", nil, nil
            end
        end

        if isAuraCategory and SafeBoolean(m.childIsActive) == true then
            return "aura", nil, nil
        end
    end

    if isAuraCategory then return "inactive", nil, nil end
    if not sid then return "inactive", nil, nil end

    local cdInfo = Sources and Sources.QuerySpellCooldown and Sources.QuerySpellCooldown(sid)
    local cdActive = cdInfo and cdInfo.isActive == true
    -- isOnGCD distinguishes a real (non-GCD) cooldown from an incidental GCD.
    -- This drives only the swipe lane (real-CD vs GCD); the icon's saturation
    -- is driven independently and lag-free by the real-CD-only DurationObject
    -- curve in cdm_icon_renderer.lua, so a cosmetic isOnGCD wobble here only
    -- affects which swipe shows, never the dark/bright state the user sees.
    local baseOnGCD = cdInfo and cdInfo.isOnGCD
    -- A real (non-GCD) cooldown on the base always wins -- EXCEPT when this is a
    -- transient proc override that is available while its base recharges, where
    -- the "cooldown" we just read is the base's shared slot and Blizzard shows
    -- the proc ready. Show ready (inactive) so the proc surfaces + glows.
    if cdActive and baseOnGCD ~= true then
        if IsTransientProcOverrideReady(m, sid) then
            return "inactive", nil, nil
        end
        return "cooldown", nil, sid
    end
    -- Talent-override cooldowns sit on the override spellID, not the registered
    -- base. C_Spell.GetSpellCooldown reports isActive=true only on the spellID
    -- the cooldown was directly initiated on. Two shapes reach here:
    --   1. The base reports isActive=false (its cooldown lane is idle). Guardian
    --      Druid Berserk -> Incarnation: Guardian of Ursoc is the reference
    --      case: m.spellID=50334 reports isActive=false while
    --      m.overrideSpellID=102558 reports isActive=true. Probing only
    --      m.spellID would drop the icon to mode=inactive for the rest of the cd.
    --   2. The base reports isActive=true, isOnGCD=true. The base has no
    --      cooldown of its own, so an incidental GCD from casting ANY other
    --      spell shows up on it every global cooldown. Augmentation Breath of
    --      Eons (base Deep Breath 357210 -> override 403631) is the reference
    --      case. Returning gcd-only on the base here demotes the icon every
    --      incidental GCD during the ~2-min cooldown and erases the real swipe.
    -- In both shapes the override's real (non-GCD) cooldown is authoritative: a
    -- real cooldown outranks the GCD, mirroring Blizzard's CooldownViewer (which
    -- shows max(realCD, GCD)). The override's DurObj is also where the live
    -- timing lives — base's C_Spell.GetSpellCooldownDuration returns a DurObj
    -- whose visible timing reflects "no active cd", which binds via SCFDO but
    -- renders no swipe. Return the override sid so BuildMirrorRenderPayload's
    -- cooldown branch queries the matching duration.
    local overrideSid = m.overrideSpellID
    local overrideCdInfo
    local overrideOnGCD
    if overrideSid and overrideSid ~= sid
        and Sources and Sources.QuerySpellCooldown then
        overrideCdInfo = Sources.QuerySpellCooldown(overrideSid)
        if overrideCdInfo and overrideCdInfo.isActive == true then
            overrideOnGCD = overrideCdInfo.isOnGCD
            if overrideOnGCD ~= true then
                return "cooldown", nil, overrideSid
            end
        end
    end
    -- An active multi-charge recharge outranks the GCD. While a charge is
    -- rolling, Blizzard's CooldownViewer shows the recharge swipe, not the
    -- incidental GCD from casting other spells — the same precedence a real
    -- (non-GCD) cooldown already gets above. Check it before the gcd-only
    -- fallback so a recharging charge spell (Unholy DK Putrefy is the reference
    -- case) keeps its recharge swipe instead of flickering to a GCD swipe every
    -- global cooldown. HasActiveChargeRecharge self-gates on a known-charge
    -- capability in combat, so a non-charge spell still falls through to the
    -- GCD branch below.
    if HasActiveChargeRecharge(sid, SafeBoolean(m.charges) == true) then
        return "cooldown", nil, sid
    end
    -- No real cooldown on the base or override and no rolling recharge. Fall
    -- back to a GCD swipe (base first, then override) so a freshly cast spell
    -- still surfaces its GCD.
    if cdActive and baseOnGCD == true then
        return "gcd-only", nil, sid
    end
    if overrideCdInfo and overrideCdInfo.isActive == true
        and overrideOnGCD == true then
        return "gcd-only", nil, overrideSid
    end
    -- Hold gcd-only through the cast when cast time exceeds the GCD (Shadow
    -- Priest Mind Blast is the reference case). GCD ends before
    -- UNIT_SPELLCAST_SUCCEEDED fires, leaving an ~80ms window where
    -- C_Spell.GetSpellCooldown(sid).isActive=false. Returning "inactive"
    -- here clears the swipe until the post-SUCCEEDED SPELL_UPDATE_COOLDOWN
    -- re-binds it — visible as a swipe vanish blip mid-cast.
    if PlayerIsCastingMirrorSpell(m, sid) then
        return "gcd-only", nil, sid
    end
    return "inactive", nil, nil
end

local function ResolveMirrorAuraData(m, auraUnit, active, mode)
    if not active or mode ~= "aura" then return nil end
    if m and type(m.auraData) == "table" then
        return m.auraData
    end
    if not (m and HasOpaqueValue(m.auraInstanceID) and auraUnit
        and Sources and Sources.QueryAuraDataByAuraInstanceID) then
        return nil
    end
    return Sources.QueryAuraDataByAuraInstanceID(auraUnit, m.auraInstanceID)
end

local function ResolveOwnedTargetMirrorAuraData(m, auraUnit, auraData)
    -- The mirror's capture path (AuraInstanceMatchesExpectedOwner,
    -- cdm_blizz_mirror.lua:1495) already verified player-ownership via the
    -- combat-safe "HARMFUL|PLAYER" aura filter before stamping
    -- m.auraInstanceID. auraInstanceIDs are unique per aura instance on a
    -- unit and Blizzard does not reassign them across casters, so passing
    -- the PLAYER filter at capture binds this stamped ID to a player-cast
    -- aura for its full lifetime.
    --
    -- Re-verifying ownership here via auraData field reads
    -- (isFromPlayerOrPlayerPet / sourceUnit / sourceGUID) is fragile: those
    -- fields become secret values in combat post-12.0.5, pcall-decoded
    -- boolean reads return nil, and the check defaults to "foreign" —
    -- demoting player-cast target debuffs (DK Unholy Soul Reaper is the
    -- reference case) to mode=inactive and stopping the cooldown icon
    -- from showing the aura phase.
    --
    -- C_UnitAuras.GetAuraDataByAuraInstanceID is the trusted presence
    -- check: it returns auraData iff the aura is still on the unit. Trust
    -- the capture-side filter; just confirm presence here.
    if auraData then return auraData end
    if not (m and HasOpaqueValue(m.auraInstanceID)
        and auraUnit == "target"
        and Sources and Sources.QueryAuraDataByAuraInstanceID) then
        return nil
    end
    return Sources.QueryAuraDataByAuraInstanceID(auraUnit, m.auraInstanceID)
end

local function BuildMirrorRenderPayload(
    m, fallbackCooldownID, fallbackCategory, fallbackSpellID,
    overrideDurObj, overrideMode, overrideUnknown, cachedSourceID, suppressAura)
    if not m then return nil end

    local sourceCooldownID = m.cooldownID or fallbackCooldownID or fallbackSpellID
    local sourceSpellID = m.spellID or m.overrideSpellID or fallbackSpellID
    local mode, derivedAuraData, cooldownSpellID
    if overrideMode then
        mode = overrideMode
    else
        mode, derivedAuraData, cooldownSpellID = DeriveMirrorPayloadMode(m, sourceSpellID, suppressAura)
    end
    local active = mode ~= "inactive"
    -- DeriveMirrorPayloadMode returns the spellID where the active cooldown
    -- was detected. For talent-overridden cooldowns (e.g., Berserk ->
    -- Incarnation: Guardian of Ursoc) this is m.overrideSpellID, whose
    -- C_Spell.GetSpellCooldownDuration carries the live timing — the base's
    -- DurObj binds an empty cooldown. Default to sourceSpellID when the
    -- mode classifier didn't report one (overrideMode caller, etc.).
    local cdQuerySpellID = cooldownSpellID or sourceSpellID

    local selfAura = SafeBoolean(m.selfAura)
    local auraUnit = SafeMirrorString(m.auraUnit)
        or ((selfAura == false) and "target" or "player")
    local auraInstanceID = m.auraInstanceID
    local auraData = derivedAuraData or ResolveMirrorAuraData(m, auraUnit, active, mode)

    if active and mode == "aura" and auraUnit == "target" then
        auraData = ResolveOwnedTargetMirrorAuraData(m, auraUnit, auraData)
        if not auraData and not MirrorAuraHasCapturedPresence(m) then
            active = false
            mode = "inactive"
            auraInstanceID = nil
            auraUnit = nil
        end
    end

    local payloadDurObj = overrideDurObj
    local durationStateUnknown = overrideUnknown
    if not payloadDurObj then
        if mode == "aura" and active then
            payloadDurObj = m.auraDurObj or m.totemDurObj
            if not payloadDurObj then
                durationStateUnknown = m.auraDurationStateUnknown
            end
        elseif mode == "cooldown" and sourceSpellID then
            -- Prefer the hook-captured cooldownDurObj (cdm_blizz_mirror.lua
            -- stamps this from the live-cooldown event) above everything
            -- else. The hook-cache papers over a brief API lag between
            -- cooldown-start and C_Spell.GetSpellCooldownDuration
            -- returning the new value; without it, Scenario H of the
            -- aura-priority integration test fails on a real cooldown
            -- that has just begun.
            --
            -- During an active multi-charge recharge, probe
            -- C_Spell.GetSpellChargeDuration before falling back to
            -- C_Spell.GetSpellCooldownDuration. This mirrors Blizzard
            -- CooldownViewerCooldownItemMixin's
            -- CheckCacheCooldownValuesFromCharges (FrameXML
            -- CooldownViewer.lua:840) — charges take precedence over the
            -- spell cooldown only until all charges are spent. For spells
            -- whose recharge IS the cooldown (Death Charge / Death's
            -- Advance is the reference case) GetSpellCooldownDuration
            -- returns a non-nil ZERO DurationObject which would otherwise
            -- win the `or` chain and bind an empty swipe.
            --
            -- Gate on HasActiveChargeRecharge (maxCharges > 1 AND
            -- chargeInfo.isActive) rather than m.charges (capability).
            -- Shadow Priest Mind Blast is the reference case for the
            -- inverse pathology: it carries a charge capability but at
            -- 1/1 max its real cooldown duration lives on the spell
            -- cooldown, not the (degenerate) charge duration. The
            -- capability-only gate bound an empty charge DurObj and
            -- produced no visible swipe.
            payloadDurObj = m.cooldownDurObj
            if not payloadDurObj
               and HasActiveChargeRecharge(sourceSpellID, SafeBoolean(m.charges) == true) then
                payloadDurObj = QueryChargeDuration(sourceSpellID)
            end
            if not payloadDurObj then
                payloadDurObj = QueryDuration(cdQuerySpellID)
            end
            if not payloadDurObj then
                durationStateUnknown = true
            end
        elseif mode == "gcd-only" and sourceSpellID then
            payloadDurObj = QueryGCDDuration(sourceSpellID)
            if not payloadDurObj then
                durationStateUnknown = true
            end
        end
    end

    local sourceKey = cachedSourceID
    if mode == "inactive" then
        sourceKey = nil
    elseif mode == "gcd-only" then
        sourceKey = sourceSpellID
    elseif mode == "cooldown" or mode == "item-cooldown" then
        -- Bypass cachedSourceID for real-cooldown modes. The cache at
        -- cdm_icon_renderer.lua:6249 (StoreCachedMirrorStateForIcon)
        -- builds "mirror:<cooldownID>:<epoch>", which advances on every
        -- mirror update tick — that would force a fresh
        -- DurationBindingMatches miss → SCFDO rebind on every event,
        -- restarting the C-side sweep animation before any visible
        -- progress accumulates.
        --
        -- Use sourceSpellID for the key. sourceSpellID resolves to
        -- m.spellID (the registered base) when available, falling back
        -- to m.overrideSpellID or fallbackSpellID. In practice m.spellID
        -- is always populated for an active mirror, so the key stays
        -- stable across an override-firing proc — overrideSpellID changes
        -- mid-cooldown do not re-key. The cascade above passes the same
        -- sourceSpellID to QueryDuration / QueryGCDDuration, so the
        -- DurObj lookup and the key stay synchronized, and the
        -- already-bound C-side animation doesn't restart.
        --
        -- Aura mode keeps the cache because its DurationBindingMatches
        -- branch (cdm_icon_renderer.lua:6193-6194) does a userdata-
        -- identity check downstream that handles aura refreshes
        -- correctly.
        sourceKey = BuildMirrorDurationSourceKey(
            mode, sourceCooldownID, sourceSpellID, m.mirrorEpoch, m.cooldownLaneEpoch)
    elseif not sourceKey then
        sourceKey = BuildMirrorDurationSourceKey(
            mode, sourceCooldownID, sourceSpellID, m.mirrorEpoch, m.cooldownLaneEpoch)
    end

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
    payload.auraInstanceID = auraInstanceID
    payload.durObj = payloadDurObj
    payload.durationStateUnknown = durationStateUnknown
    payload.auraUnit = auraUnit
    payload.auraData = auraData
    payload.totemSlot = m.totemSlot
    payload.totemName = m.totemName
    payload.totemIcon = m.totemIcon
    payload.cooldownDurObj = m.cooldownDurObj
    payload.isTotemInstance = m.totemSlot and true or false
    payload.count = BuildMirrorCountPayload(m, mode)

    if active and mode == "aura" and not payloadDurObj then
        payload.hasExpirationTime = false
        payload.hideDurationText = true
    end

    return payload
end

-- Re-build the payload with aura mode suppressed so the underlying cooldown
-- surfaces. Used by icons that have already finished their aura phase and
-- want to display the cd swipe behind a still-active buff.
local function BuildMirrorCooldownPhasePayload(payload)
    local m = payload and payload.state
    if not m then return nil end

    local rebuilt = BuildMirrorRenderPayload(
        m, payload.cooldownID, payload.category, payload.spellID,
        nil, nil, nil, nil, true)
    if not rebuilt or rebuilt.mode == "aura" or rebuilt.mode == "inactive" then
        return nil
    end
    return rebuilt
end

local function CachedMirrorStateAcceptedForEntry(
    state, entry, cooldownID, category, viewerCategory, strictAuraBinding)
    if not state then return false end

    local stateCooldownID = state.cooldownID
    if cooldownID ~= nil and stateCooldownID ~= nil and stateCooldownID ~= cooldownID then
        return false
    end

    local normalizedCategory = NormalizeMirrorCategory(category)
    local actualCategory = NormalizeMirrorCategory(state.viewerCategory) or normalizedCategory
    if normalizedCategory ~= nil and actualCategory ~= normalizedCategory then
        return false
    end

    if not MirrorCategoryMatchesEntry(actualCategory, viewerCategory, strictAuraBinding) then
        return false
    end

    return MirrorStateMatchesEntryIdentity(state, entry)
end

local function EntryMirrorBindingIsStrictAura(entry, viewerCategory)
    return MirrorBindingIsStrictAura(entry, nil, viewerCategory)
end

local function ResolveMirrorRenderPayloadForEntry(
    entry, explicitCooldownID, explicitCategory, fallbackSpellID,
    cachedMirrorState, cachedMirrorSourceID)
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

    if CachedMirrorStateAcceptedForEntry(
        cachedMirrorState, entry, explicitCooldownID, explicitCat,
        viewerCategory, strictAuraBinding) then
        if resolverStats then resolverStats.mirrorStateCacheHits = resolverStats.mirrorStateCacheHits + 1 end
        return BuildMirrorRenderPayload(
            cachedMirrorState, explicitCooldownID, explicitCat, fallbackSpellID,
            nil, nil, nil, cachedMirrorSourceID)
    end

    local identity = ResolveExplicitMirrorIdentityState(
        mirror, entry, explicitCooldownID, explicitCat,
        viewerCategory, strictAuraBinding, "context", entryType)
    if identity and identity.state then
        return BuildMirrorRenderPayload(
            identity.state, identity.cooldownID, identity.category, fallbackSpellID)
    end

    identity = ResolveBlizzardMirrorIdentityState(entry)
    if identity and identity.state then
        return BuildMirrorRenderPayload(
            identity.state, identity.cooldownID, identity.category, fallbackSpellID)
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

local QueryItemCooldown
local QuerySlotCooldown

local function BuildDurationObjectFromStart(startTime, duration)
    local startSecret = ResolverIsSecretValue(startTime)
    local durationSecret = ResolverIsSecretValue(duration)
    if not startSecret and startTime == nil then return nil end
    if not durationSecret and duration == nil then return nil end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end

    local okCreate, durObj = pcall(C_DurationUtil.CreateDuration)
    if not okCreate or not durObj or not durObj.SetTimeFromStart then
        return nil
    end

    local okSet = pcall(durObj.SetTimeFromStart, durObj, startTime, duration)
    if okSet then return durObj end
    return nil
end

-- keySource is stable per entry (item/slot identity), so the derived
-- "item-duration:<key>" string is invariant across ticks. Rebuilding it every
-- resolve was pure GC churn on the hot item path; cache it on the icon and
-- only re-concat when the key actually changes.
local function BuildItemDurationSourceID(icon, keySource)
    if not icon then
        return "item-duration:" .. tostring(keySource)
    end
    if icon._itemDurSourceKey == keySource and icon._itemDurSourceID then
        return icon._itemDurSourceID
    end
    local sourceID = "item-duration:" .. tostring(keySource)
    icon._itemDurSourceKey = keySource
    icon._itemDurSourceID = sourceID
    return sourceID
end

local function GetIconItemDurationObject(icon, sourceID, startTime, duration)
    if not icon then return nil end
    if ResolverIsSecretValue(startTime) or ResolverIsSecretValue(duration) then
        return nil
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) then
        return nil
    end

    local state = icon._cdmRuntimeState
    if not state or state.mode ~= "item-cooldown" or state.sourceID ~= sourceID then
        return nil
    end

    local priorStart = state.start
    local priorDuration = state.duration
    if ResolverIsSecretValue(priorStart) or ResolverIsSecretValue(priorDuration) then
        return nil
    end
    if priorStart ~= startTime or priorDuration ~= duration then
        return nil
    end

    local durObj = state.durObj or icon._lastDurObj
    if durObj then
        if resolverStats then resolverStats.itemDurationIconReuses = resolverStats.itemDurationIconReuses + 1 end
        return durObj
    end
    return nil
end

local function BuildIconItemDurationObject(icon, keySource, startTime, duration)
    local sourceID = BuildItemDurationSourceID(icon, keySource)
    local durObj = GetIconItemDurationObject(icon, sourceID, startTime, duration)
    if durObj then
        return durObj, sourceID
    end
    return BuildDurationObjectFromStart(startTime, duration), sourceID
end

local function CleanItemCooldownIsDisabled(enabled, requireEnabledOne)
    if ResolverIsSecretValue(enabled) then
        return false
    end
    if enabled == 0 or enabled == false then
        return true
    end
    if requireEnabledOne
        and enabled ~= nil
        and enabled ~= 1
        and enabled ~= true then
        return true
    end
    return false
end

local function CleanItemCooldownIsInactive(startTime, duration, enabled, requireEnabledOne)
    if CleanItemCooldownIsDisabled(enabled, requireEnabledOne) then
        return true
    end
    if ResolverIsSecretValue(startTime) or ResolverIsSecretValue(duration) then
        return false
    end
    if not IsSafeNumeric(startTime) or not IsSafeNumeric(duration) then
        return true
    end
    if startTime <= 0 then
        return true
    end
    if duration <= GCD_MAX_DURATION then
        return true
    end
    if (startTime + duration) <= GetTime() then
        return true
    end
    return false
end

local function CleanItemCooldownIsActive(startTime, duration, enabled, requireEnabledOne)
    if CleanItemCooldownIsDisabled(enabled, requireEnabledOne) then
        return false
    end
    if ResolverIsSecretValue(startTime) or ResolverIsSecretValue(duration) then
        return false
    end
    return IsSafeNumeric(startTime)
        and IsSafeNumeric(duration)
        and startTime > 0
        and duration > GCD_MAX_DURATION
        and (startTime + duration) > GetTime()
end

local function HasItemCooldownTiming(startTime, duration, enabled)
    return startTime ~= nil or duration ~= nil or enabled ~= nil
end

local function ResolveItemDurationObjectForIcon(icon, entry)
    local itemID, slotID, itemSpellID, keySource = ResolveItemCooldownIdentity(entry)
    if not itemID then return nil, "inactive", nil, nil, nil, nil end

    local startTime, duration, enabled
    local requireEnabledOne = slotID ~= nil
    local itemCooldownKnown = false
    if slotID then
        startTime, duration, enabled = QuerySlotCooldown(slotID)
        itemCooldownKnown = HasItemCooldownTiming(startTime, duration, enabled)
        if CleanItemCooldownIsInactive(startTime, duration, enabled, true) then
            local itemStart, itemDuration, itemEnabled = QueryItemCooldown(itemID)
            itemCooldownKnown = itemCooldownKnown or HasItemCooldownTiming(itemStart, itemDuration, itemEnabled)
            if not CleanItemCooldownIsInactive(itemStart, itemDuration, itemEnabled, false) then
                startTime = itemStart
                duration = itemDuration
                enabled = itemEnabled
                requireEnabledOne = false
            end
        end
    else
        startTime, duration, enabled = QueryItemCooldown(itemID)
        itemCooldownKnown = HasItemCooldownTiming(startTime, duration, enabled)
    end

    if not CleanItemCooldownIsInactive(startTime, duration, enabled, requireEnabledOne) then
        local cleanNumericActive = CleanItemCooldownIsActive(startTime, duration, enabled, requireEnabledOne)
        local itemDurObj, itemDurationSourceID =
            BuildIconItemDurationObject(icon, keySource, startTime, duration)
        if itemDurObj then
            return itemDurObj, "item-cooldown",
                itemDurationSourceID,
                cleanNumericActive and startTime or nil,
                cleanNumericActive and duration or nil,
                itemSpellID
        end

        if cleanNumericActive then
            return nil, "item-cooldown",
                "item:" .. tostring(keySource) .. ":" .. tostring(startTime) .. ":" .. tostring(duration),
                startTime, duration, itemSpellID
        end
    elseif itemCooldownKnown then
        return nil, "inactive", nil, nil, nil, itemSpellID
    end

    if itemSpellID then
        local cdInfo = QueryCooldown(itemSpellID)
        local cdInfoActive = cdInfo and IsCooldownInfoActive(cdInfo)
        if cdInfoActive == true and GetCurrentIsOnGCD(cdInfo) ~= true then
            local durObj = QueryDuration(itemSpellID)
            if durObj then
                return durObj, "item-cooldown",
                    "spell:" .. tostring(itemSpellID) .. ":" .. tostring(keySource),
                    nil, nil, itemSpellID
            end
        end
    end

    return nil, "inactive", nil, nil, nil, itemSpellID
end

QueryItemCooldown = function(itemID)
    if not itemID or not (Sources and Sources.QueryItemCooldown) then
        return nil, nil, nil
    end
    local startTime, duration, enabled = Sources.QueryItemCooldown(itemID)
    return startTime, duration, enabled
end

local _GetInventoryItemCooldown = GetInventoryItemCooldown

QuerySlotCooldown = function(slotID)
    if not slotID or not _GetInventoryItemCooldown then
        return nil, nil, nil
    end
    return _GetInventoryItemCooldown("player", slotID)
end

local _cooldownStateCountScratch = {
    value = nil,
    sinkText = nil,
    shown = false,
    source = nil,
}

local _cooldownStateScratch = {
    mode = "inactive",
    active = false,
    isActive = false,
    spellID = nil,
    sourceID = nil,
    durObj = nil,
    start = nil,
    duration = nil,
    mirrorBacked = nil,
    mirrorCooldownID = nil,
    mirrorCategory = nil,
    mirrorState = nil,
    state = nil,
    cooldownID = nil,
    category = nil,
    auraInstanceID = nil,
    auraUnit = nil,
    auraData = nil,
    resolvedAuraSpellID = nil,
    hasExpirationTime = nil,
    hideDurationText = nil,
    durationStateUnknown = nil,
    countValue = nil,
    countSinkText = nil,
    countShown = false,
    countSource = nil,
    countMirrorBacked = nil,
    count = _cooldownStateCountScratch,
    totemSlot = nil,
    totemName = nil,
    totemIcon = nil,
    isTotemInstance = false,
    numericCooldownActive = nil,
    auraResolved = nil,
    auraActive = nil,
    auraIsActive = nil,
    isOnCooldown = false,
    rechargeActive = false,
    hasCharges = false,
    hasChargesRemaining = false,
    gcdOnly = false,
    isGCDOnly = false,
    isAuraMode = false,
    isRealCooldownMode = false,
    hasDurationObject = false,
    hasRenderableCooldown = false,
    cooldownInfo = nil,
    cooldownInfoActive = nil,
    cooldownInfoOnGCD = nil,
}

local function WipeCooldownState()
    local s = _cooldownStateScratch
    s.mode = "inactive"
    s.active = false
    s.isActive = false
    s.spellID = nil
    s.sourceID = nil
    s.durObj = nil
    s.start = nil
    s.duration = nil
    s.mirrorBacked = nil
    s.mirrorCooldownID = nil
    s.mirrorCategory = nil
    s.mirrorState = nil
    s.state = nil
    s.cooldownID = nil
    s.category = nil
    s.auraInstanceID = nil
    s.auraUnit = nil
    s.auraData = nil
    s.resolvedAuraSpellID = nil
    s.hasExpirationTime = nil
    s.hideDurationText = nil
    s.durationStateUnknown = nil
    s.countValue = nil
    s.countSinkText = nil
    s.countShown = false
    s.countSource = nil
    s.countMirrorBacked = nil
    s.totemSlot = nil
    s.totemName = nil
    s.totemIcon = nil
    s.isTotemInstance = false
    s.numericCooldownActive = nil
    s.auraResolved = nil
    s.auraActive = nil
    s.auraIsActive = nil
    s.isOnCooldown = false
    s.rechargeActive = false
    s.hasCharges = false
    s.hasChargesRemaining = false
    s.gcdOnly = false
    s.isGCDOnly = false
    s.isAuraMode = false
    s.isRealCooldownMode = false
    s.hasDurationObject = false
    s.hasRenderableCooldown = false
    s.cooldownInfo = nil
    s.cooldownInfoActive = nil
    s.cooldownInfoOnGCD = nil

    local c = _cooldownStateCountScratch
    c.value = nil
    c.sinkText = nil
    c.shown = false
    c.source = nil
    s.count = c
    return s
end

local function SetCooldownStateActivity(state, active)
    active = active == true
    state.active = active
    state.isActive = active
end

local function CopyCountFactsToState(state, count, mirrorBacked)
    local c = _cooldownStateCountScratch
    if count then
        c.value = count.value
        c.sinkText = count.sinkText
        c.shown = count.shown == true
        c.source = count.source
    else
        c.value = nil
        c.sinkText = nil
        c.shown = false
        c.source = nil
    end
    state.count = c
    state.countValue = c.value
    state.countSinkText = c.sinkText
    state.countShown = c.shown
    state.countSource = c.source
    state.countMirrorBacked = mirrorBacked == true and count ~= nil or nil
end

local function CopyAuraFactsToState(state, aura)
    if not aura then return end
    local auraActive = aura.isActive == true
    state.auraResolved = true
    state.auraActive = auraActive
    state.auraIsActive = auraActive
    state.auraInstanceID = aura.auraInstanceID
    state.auraUnit = aura.auraUnit
    state.auraData = aura.auraData
    state.resolvedAuraSpellID = aura.resolvedAuraSpellID or state.spellID
    state.hasExpirationTime = aura.hasExpirationTime
    state.hideDurationText = aura.hideDurationText
    state.durationStateUnknown = aura.durationStateUnknown
    state.totemSlot = aura.totemSlot
    state.totemName = aura.totemName
    state.totemIcon = aura.totemIcon
    state.isTotemInstance = aura.isTotemInstance and true or false
    CopyCountFactsToState(state, aura.count, false)
end

local function GetAuraStateSourceID(aura, fallbackID)
    if not aura then return fallbackID end
    return aura.auraInstanceID or aura.totemSlot or fallbackID
end

local _cooldownStateAuraParams = {}

local function ResolveAuraRuntimeStateForContext(context, entry, sid, entryIsAura)
    local AuraRuntime = ns.CDMAuraRuntime
    if not (context and entry and sid) then
        return nil
    end
    if not entryIsAura and context.useBuffSwipe == false then
        return nil
    end

    local p = _cooldownStateAuraParams
    p.spellID = sid
    p.entrySpellID = entry.spellID
    p.entryID = entry.id
    p.entryName = entry.name
    p.entryKind = entry.kind
    p.entryType = entry.type
    p.entryIsAura = entryIsAura
    p.entryTexture = CDMResolvers.GetEntryTexture(entry)
    p.viewerType = context.containerKey or entry.viewerType
    p.totemSlot = context.totemSlot
    p.disableLooseVisibilityFallback = true
    p.blizzardMirrorCooldownID = context.mirrorCooldownID
    p.blizzardMirrorCategory = context.mirrorCategory

    if AuraRuntime and AuraRuntime.ResolveState then
        local aura = AuraRuntime.ResolveState(p)
        if aura then
            return aura
        end
    end
    return nil
end

local function ApplyAuraStateToCooldownState(state, aura, fallbackSpellID)
    CopyAuraFactsToState(state, aura)
    if not (aura and aura.isActive) then
        return false
    end
    state.mode = "aura"
    SetCooldownStateActivity(state, true)
    state.durObj = aura.durObj
    state.sourceID = GetAuraStateSourceID(aura, fallbackSpellID)
    state.spellID = aura.resolvedAuraSpellID or fallbackSpellID
    if aura.isActive and aura.hasExpirationTime == nil and not aura.durObj then
        state.hasExpirationTime = false
        state.hideDurationText = true
    end
    return true
end

local function ResolveMirrorPayloadAuraActive(payload)
    if not (payload and payload.active == true) then
        return false
    end
    if payload.mode == "aura" then
        return true
    end
    if HasOpaqueValue(payload.auraInstanceID) or HasOpaqueValue(payload.totemSlot) then
        return true
    end
    local m = payload.state
    if m and (HasOpaqueValue(m.auraDurObj) or HasOpaqueValue(m.totemDurObj)) then
        return true
    end
    return false
end

local function MirrorPayloadMayHaveAuraOverlay(payload)
    if not payload then return false end
    if payload.mode == "aura" then return true end
    if HasOpaqueValue(payload.auraInstanceID) or HasOpaqueValue(payload.totemSlot) then
        return true
    end

    local m = payload.state
    if not m then return false end
    if HasOpaqueValue(m.auraInstanceID)
        or HasOpaqueValue(m.auraDurObj)
        or HasOpaqueValue(m.totemDurObj) then
        return true
    end
    if DecodePotentialSecretBoolean(m.wasSetFromAura) == true then
        return true
    end
    if DecodePotentialSecretBoolean(m.hasAura) == true then
        return true
    end

    local linkedSpellIDs = m.linkedSpellIDs
    if type(linkedSpellIDs) == "table" and next(linkedSpellIDs) ~= nil then
        return true
    end

    if DecodePotentialSecretBoolean(m.hasAura) == false then
        -- hasAura=false sibling-aura lookup. Some defensive cooldowns
        -- (DK Anti-Magic Shell, hasAura=false self-buff entries) register
        -- with hasAura=false on the cooldown cdID even though the spell
        -- applies a buff visible in the buff/trackedBar viewer category.
        -- If a sibling cdID exists in those categories for this spellID,
        -- there IS an aura the cooldown icon should overlay. Let the aura
        -- runtime (CDMAuraRuntime.ResolveState) query the live aura by
        -- spellID and surface it; without this gate the resolver bails
        -- on hasAura=false below and the cooldown icon never enters
        -- mode=aura during the buff phase.
        --
        -- childIsActive alone is not aura evidence here: an ordinary active
        -- cooldown child also reports active, and probing same-spell auras for
        -- those entries can promote a non-aura cooldown into mode="aura".
        local cat = m.viewerCategory
        if cat == "essential" or cat == "utility" then
            local mirror = ns.CDMBlizzMirror
            local sid = m.spellID
            if sid and mirror and mirror.GetCooldownIDForViewer then
                if mirror.GetCooldownIDForViewer(sid, "buff")
                    or mirror.GetCooldownIDForViewer(sid, "trackedBar") then
                    return true
                end
            end
        end
        return false
    end
    return true
end

local function ApplyMirrorPayloadToCooldownState(state, payload)
    if not payload then return false end
    local auraActive = ResolveMirrorPayloadAuraActive(payload)
    state.mode = payload.mode or "inactive"
    SetCooldownStateActivity(state, payload.active == true)
    state.spellID = payload.spellID
    state.sourceID = payload.sourceID
    state.durObj = payload.durObj
    state.cooldownDurObj = payload.cooldownDurObj
    state.mirrorBacked = true
    state.mirrorCooldownID = payload.cooldownID
    state.mirrorCategory = payload.category
    state.mirrorState = payload.state
    state.state = payload.state
    state.cooldownID = payload.cooldownID
    state.category = payload.category
    state.auraInstanceID = payload.auraInstanceID
    state.auraUnit = payload.auraUnit
    state.auraData = payload.auraData
    state.resolvedAuraSpellID = payload.spellID
    state.hasExpirationTime = payload.hasExpirationTime
    state.hideDurationText = payload.hideDurationText
    state.durationStateUnknown = payload.durationStateUnknown
    state.auraActive = auraActive
    state.auraIsActive = auraActive
    state.totemSlot = payload.totemSlot
    state.totemName = payload.totemName
    state.totemIcon = payload.totemIcon
    state.isTotemInstance = payload.isTotemInstance and true or false
    CopyCountFactsToState(state, payload.count, true)
    if state.active and state.mode == "aura" and state.hasExpirationTime == nil and not state.durObj then
        state.hasExpirationTime = false
        state.hideDurationText = true
    end
    return true
end

local function ApplyCleanItemAuraTiming(state, itemID, spellID, resolvedAuraSpellID, auraUnit, auraInstanceID,
                                        expiration, duration, sourceSuffix)
    if ResolverIsSecretValue(expiration) or ResolverIsSecretValue(duration) then
        return false
    end
    if not (IsSafeNumeric(expiration) and IsSafeNumeric(duration)) then
        return false
    end
    if duration <= 0 or expiration <= GetTime() then
        return false
    end

    state.mode = "aura"
    SetCooldownStateActivity(state, true)
    state.start = expiration - duration
    state.duration = duration
    state.sourceID = "item-aura-" .. tostring(sourceSuffix or "scanner") .. ":" .. tostring(itemID)
    state.spellID = spellID
    state.auraResolved = true
    state.auraActive = true
    state.auraIsActive = true
    state.auraUnit = auraUnit or "player"
    state.auraInstanceID = CleanOpaqueValue(auraInstanceID)
    state.hasAuraInstanceID = HasOpaqueValue(auraInstanceID)
    state.resolvedAuraSpellID = resolvedAuraSpellID or spellID
    return true
end

local function ResolveItemAuraForContext(state, context, entry, itemID, itemSpellID)
    if not (context and entry and itemID) then
        return false
    end

    local function trySpellID(rawSpellID, sourceKey)
        local durObj, resolvedAuraSpellID, auraInstanceID, auraUnit =
            QueryPlayerAuraDurationBySpellID(rawSpellID, entry.name)
        if durObj then
            local cleanAuraInstanceID = CleanOpaqueValue(auraInstanceID)
            state.mode = "aura"
            SetCooldownStateActivity(state, true)
            state.durObj = durObj
            state.sourceID = "item-aura-spell:" .. tostring(itemID) .. ":" .. sourceKey
            state.spellID = rawSpellID
            state.auraResolved = true
            state.auraActive = true
            state.auraIsActive = true
            state.auraUnit = auraUnit or "player"
            state.auraInstanceID = cleanAuraInstanceID
            state.hasAuraInstanceID = HasOpaqueValue(auraInstanceID)
            state.resolvedAuraSpellID = resolvedAuraSpellID or rawSpellID
            return true
        end
        return false
    end

    local rawItemSpellID = QueryItemUseSpellID(itemID)
    if trySpellID(rawItemSpellID, "raw-use") then return true end
    if trySpellID(itemSpellID, "use") then return true end

    if Sources and Sources.QueryScannedItemAuraInfo then
        local scanned = Sources.QueryScannedItemAuraInfo(itemID, itemSpellID or rawItemSpellID)
        if scanned then
            local auraInstanceID = scanned.auraInstanceID
            if HasOpaqueValue(auraInstanceID) and Sources.QueryAuraDuration then
                local auraUnit = scanned.auraUnit or "player"
                local durObj = Sources.QueryAuraDuration(auraUnit, auraInstanceID)
                if durObj then
                    local cleanAuraInstanceID = CleanOpaqueValue(auraInstanceID)
                    state.mode = "aura"
                    SetCooldownStateActivity(state, true)
                    state.durObj = durObj
                    state.sourceID = cleanAuraInstanceID
                        and ("item-aura-instance:" .. tostring(itemID) .. ":" .. tostring(cleanAuraInstanceID))
                        or ("item-aura-instance:" .. tostring(itemID))
                    state.spellID = scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID
                    state.auraResolved = true
                    state.auraActive = true
                    state.auraIsActive = true
                    state.auraUnit = auraUnit
                    state.auraInstanceID = cleanAuraInstanceID
                    state.hasAuraInstanceID = true
                    state.resolvedAuraSpellID = scanned.buffSpellID or scanned.useSpellID or state.spellID
                    return true
                end
                if Sources.QueryAuraDataByAuraInstanceID then
                    local auraData = Sources.QueryAuraDataByAuraInstanceID(auraUnit, auraInstanceID)
                    if auraData and ApplyCleanItemAuraTiming(
                        state,
                        itemID,
                        scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID,
                        scanned.buffSpellID or scanned.useSpellID,
                        auraUnit,
                        auraInstanceID,
                        auraData.expirationTime,
                        auraData.duration,
                        "aura-data") then
                        return true
                    end
                end
            end
            if trySpellID(scanned.buffSpellID, "scanner-buff") then return true end
            if trySpellID(scanned.useSpellID, "scanner-use") then return true end
            if trySpellID(scanned.sourceSpellID, "scanner-source") then return true end
            local scannedActive = scanned.active
            if ResolverIsSecretValue(scannedActive) then
                scannedActive = nil
            end
            if scannedActive == true then
                local expiration = scanned.expiration
                local duration = scanned.duration
                local scannedSpellID = scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID
                if ApplyCleanItemAuraTiming(
                    state,
                    itemID,
                    scannedSpellID,
                    scanned.buffSpellID or scanned.useSpellID or scannedSpellID,
                    scanned.auraUnit or "player",
                    scanned.auraInstanceID,
                    expiration,
                    duration,
                    "scanner") then
                    return true
                end

                state.mode = "aura"
                SetCooldownStateActivity(state, true)
                state.sourceID = "item-aura-scanner:" .. tostring(itemID)
                state.spellID = scanned.buffSpellID or scanned.useSpellID or itemSpellID or rawItemSpellID
                state.auraResolved = true
                state.auraActive = true
                state.auraIsActive = true
                state.auraUnit = scanned.auraUnit or "player"
                state.auraInstanceID = CleanOpaqueValue(scanned.auraInstanceID)
                state.hasAuraInstanceID = HasOpaqueValue(scanned.auraInstanceID)
                state.resolvedAuraSpellID = scanned.buffSpellID or scanned.useSpellID or state.spellID
                state.hasExpirationTime = false
                state.hideDurationText = true
                return true
            end
        end
    end

    if trySpellID(entry.spellID, "entry") then return true end
    if trySpellID(entry.overrideSpellID, "override") then return true end
    if trySpellID(entry.id, "id") then return true end

    local durObj, auraInstanceID, auraUnit = QueryPlayerAuraDurationByName(entry.name)
    if durObj then
        local cleanAuraInstanceID = CleanOpaqueValue(auraInstanceID)
        state.mode = "aura"
        SetCooldownStateActivity(state, true)
        state.durObj = durObj
        state.sourceID = "item-aura-name:" .. tostring(itemID)
        state.auraResolved = true
        state.auraActive = true
        state.auraIsActive = true
        state.auraUnit = auraUnit or "player"
        state.auraInstanceID = cleanAuraInstanceID
        state.hasAuraInstanceID = HasOpaqueValue(auraInstanceID)
        state.resolvedAuraSpellID = itemSpellID
        state.spellID = itemSpellID
        return true
    end

    return false
end

local function IsRealCooldownDurationMode(mode)
    return mode == "cooldown"
        or mode == "charge"
        or mode == "item-cooldown"
end

local function HasDurationObject(value)
    if ResolverIsSecretValue(value) then
        return true
    end
    return value ~= nil
end

function CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    if not state then return state end

    local mode = state.mode
    if not IsSupportedMirrorMode(mode) then
        mode = "inactive"
        state.mode = mode
    end

    local active = state.active == true
    if mode == "inactive" then
        active = false
    end
    state.active = active
    state.isActive = active

    if state.auraActive ~= nil or state.auraIsActive ~= nil then
        local auraActive = state.auraActive == true
        state.auraActive = auraActive
        state.auraIsActive = auraActive
    end

    state.gcdOnly = mode == "gcd-only"
    state.isGCDOnly = state.gcdOnly
    state.isAuraMode = mode == "aura"
    state.isRealCooldownMode = IsRealCooldownDurationMode(mode)
    state.hasCharges = state.hasCharges == true or mode == "charge"
    state.isOnCooldown = state.isOnCooldown == true
    state.rechargeActive = state.rechargeActive == true
    state.hasChargesRemaining = state.hasChargesRemaining == true
    state.numericCooldownActive = state.numericCooldownActive == true or nil

    local hasDurationObject = mode ~= "inactive" and HasDurationObject(state.durObj)
    state.hasDurationObject = hasDurationObject == true
    state.hasRenderableCooldown = mode ~= "inactive"
        and (state.hasDurationObject == true or state.numericCooldownActive == true)

    local count = state.count
    if count then
        count.shown = count.shown == true
        state.countValue = count.value
        state.countSinkText = count.sinkText
        state.countShown = count.shown
        state.countSource = count.source
    else
        state.countValue = nil
        state.countSinkText = nil
        state.countShown = false
        state.countSource = nil
    end

    return state
end

local function IsNumericCooldownActive(startTime, duration)
    return IsSafeNumeric(startTime)
        and IsSafeNumeric(duration)
        and startTime > 0
        and duration > GCD_MAX_DURATION
        and (startTime + duration) > GetTime()
end

local function FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    if not state then return state end

    local mode = state.mode or "inactive"

    state.gcdOnly = mode == "gcd-only"
    state.hasCharges = nil
    state.hasChargesRemaining = nil
    state.rechargeActive = nil

    local hasNumericCooldown = (mode == "item-cooldown" or mode == "aura")
        and IsNumericCooldownActive(state.start, state.duration)
    state.numericCooldownActive = hasNumericCooldown == true or nil

    if mode == "inactive" then
        SetCooldownStateActivity(state, false)
        state.isOnCooldown = false
        return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    end

    if mode == "aura" or mode == "gcd-only" then
        state.isOnCooldown = false
        return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    end

    if mode == "item-cooldown" then
        state.isOnCooldown = HasDurationObject(state.durObj) or hasNumericCooldown == true
        return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
    end

    -- mode == "cooldown": API said cdInfo.isActive == true and isOnGCD ~= true
    -- at derivation. Trust that classification — no mirror-state re-adjudication,
    -- no IsSpellUsable re-check, no live cdInfo re-query.
    --
    -- Aura/item/macro entries can land here when their mirror payload was
    -- rewritten cooldown-side (BuildMirrorCooldownPhasePayload at the
    -- skipAuraPhase exit) or when no sid resolved; fall back to state.active.
    if entryIsAura or itemBackedEntry or not sid then
        state.isOnCooldown = state.active == true
    else
        state.isOnCooldown = true
    end
    return CDMResolvers.NormalizeResolvedCooldownStateContract(state)
end

local function ResolveCooldownStateCore(context)
    local state = WipeCooldownState()
    local entry = context and context.entry
    if not entry then
        return FinalizeCooldownStateActivity(state, context, entry, nil, nil, nil)
    end

    local entryIsAura = CDMResolvers.IsAuraEntry(entry)
    local macroResolvedID, macroResolvedType
    if entry.type == "macro" then
        macroResolvedID, macroResolvedType = CDMResolvers.ResolveMacro(entry)
    end
    local sid = (macroResolvedType == "spell" and macroResolvedID)
        or context.runtimeSpellID
        or entry.overrideSpellID or entry.spellID or entry.id
    if sid and not entryIsAura then
        sid = QueryOverrideSpell(sid) or sid
    end
    state.spellID = sid
    MemAuditProfilerMark("CDM_rsIdentity")

    local itemID, itemSpellID
    local itemBackedEntry = IsItemLikeEntry(entry)
        or (entry.type == "macro" and macroResolvedType == "item")
    if itemBackedEntry then
        local _
        itemID, _, itemSpellID = ResolveItemCooldownIdentity(entry)
        if itemSpellID then
            sid = itemSpellID
            state.spellID = sid
        end
    end
    MemAuditProfilerMark("CDM_rsItemIdentity")

    local mirrorPayload = ResolveMirrorRenderPayloadForEntry(
        entry,
        context.mirrorCooldownID,
        context.mirrorCategory,
        sid,
        context.cachedMirrorState,
        context.cachedMirrorSourceID)
    MemAuditProfilerMark("CDM_rsMirrorLookup")
    if mirrorPayload then
        if mirrorPayload.mode ~= "aura" and context.skipAuraPhase ~= true then
            if MirrorPayloadMayHaveAuraOverlay(mirrorPayload) then
                if resolverStats then resolverStats.mirrorAuraQueries = resolverStats.mirrorAuraQueries + 1 end
                local aura = ResolveAuraRuntimeStateForContext(context, entry, sid, entryIsAura)
                MemAuditProfilerMark("CDM_rsMirrorAura")
                if ApplyAuraStateToCooldownState(state, aura, sid) then
                    MemAuditProfilerMark("CDM_rsReturnMirrorAura")
                    return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
                end
            else
                if resolverStats then resolverStats.mirrorAuraSkips = resolverStats.mirrorAuraSkips + 1 end
                MemAuditProfilerMark("CDM_rsMirrorAuraSkip")
            end
        end
        if mirrorPayload.mode == "aura" and context.skipAuraPhase == true then
            mirrorPayload = BuildMirrorCooldownPhasePayload(mirrorPayload) or mirrorPayload
            MemAuditProfilerMark("CDM_rsMirrorPhase")
        end
        ApplyMirrorPayloadToCooldownState(state, mirrorPayload)
        MemAuditProfilerMark("CDM_rsReturnMirror")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    end

    local aura = ResolveAuraRuntimeStateForContext(context, entry, sid, entryIsAura)
    MemAuditProfilerMark("CDM_rsAuraRuntime")
    if ApplyAuraStateToCooldownState(state, aura, sid) then
        if resolverStats then resolverStats.auraProbeHit = resolverStats.auraProbeHit + 1 end
        MemAuditProfilerMark("CDM_rsReturnAura")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    else
        if resolverStats then
            if (not entryIsAura) and context.useBuffSwipe == false then
                resolverStats.auraProbeGuardSkip = resolverStats.auraProbeGuardSkip + 1
            else
                resolverStats.auraProbeExpensiveMiss = resolverStats.auraProbeExpensiveMiss + 1
            end
        end
    end

    if itemID and ResolveItemAuraForContext(state, context, entry, itemID, itemSpellID) then
        MemAuditProfilerMark("CDM_rsReturnItemAura")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    end

    if itemBackedEntry then
        local itemDur, itemMode, itemSourceID, itemStart, itemDuration, resolvedItemSpellID =
            ResolveItemDurationObjectForIcon(context.owner, entry)
        MemAuditProfilerMark("CDM_rsItemCooldown")
        if itemMode == "item-cooldown" then
            state.mode = itemMode
            SetCooldownStateActivity(state, true)
            state.durObj = itemDur
            state.sourceID = itemSourceID
            state.start = itemStart
            state.duration = itemDuration
            state.spellID = resolvedItemSpellID
            state.numericCooldownActive = itemStart ~= nil and itemDuration ~= nil or nil
            MemAuditProfilerMark("CDM_rsReturnItemCD")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
        if entry.type ~= "macro" or macroResolvedType == "item" then
            state.mode = "inactive"
            state.spellID = resolvedItemSpellID
            MemAuditProfilerMark("CDM_rsReturnItemOff")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
    end

    if entryIsAura or not sid then
        state.mode = "inactive"
        state.spellID = sid
        MemAuditProfilerMark("CDM_rsReturnNoSpell")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    end

    local gcdCdInfo = QueryCooldown(sid)
    local currentOnGCD = GetCurrentIsOnGCD(gcdCdInfo)
    local gcdDurObj
    if currentOnGCD == true and context.showGCDSwipe == true then
        gcdDurObj = QueryGCDDurationObject(sid)
    end
    MemAuditProfilerMark("CDM_rsGCDProbe")

    local entryMayHaveCharges = entry
        and (entry.hasCharges == true or entry.charges == true)
    -- An active multi-charge recharge outranks the GCD swipe, mirroring
    -- Blizzard's CooldownViewer (the recharge shows, not the incidental GCD
    -- from casting other spells). Gated on currentOnGCD so it intercepts only
    -- the on-GCD window: ShouldRenderLiveGCD(currentOnGCD) already gates the
    -- real-cooldown branch below off whenever currentOnGCD is true, so a real
    -- non-GCD cooldown still wins there, and an off-GCD recharge is handled by
    -- the charge block at the end. Unholy DK Putrefy is the reference case
    -- (flickered to a GCD swipe every global cooldown while a charge recharged).
    if currentOnGCD == true and HasActiveChargeRecharge(sid, entryMayHaveCharges) then
        local chargeDur = QueryChargeDuration(sid)
        if chargeDur then
            state.mode = "cooldown"
            SetCooldownStateActivity(state, true)
            state.durObj = chargeDur
            state.sourceID = sid
            state.spellID = sid
            MemAuditProfilerMark("CDM_rsReturnChargeRechargeGCD")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
    end

    do
        local cdInfo = gcdCdInfo or QueryCooldown(sid)
        local cdInfoActive = cdInfo and IsCooldownInfoActive(cdInfo)
        if cdInfoActive == true then
            -- isOnGCD only selects the swipe lane (real-CD vs GCD); the icon's
            -- saturation is driven lag-free by the real-CD-only DurationObject
            -- curve in cdm_icon_renderer.lua, so a cosmetic-moment isOnGCD read
            -- here can at most pick the wrong swipe for a frame, never strand
            -- the dark/bright state the user sees.
            local cdInfoOnGCD = GetCurrentIsOnGCD(cdInfo)
            local durObj = QueryDuration(sid)
            local renderLiveGCD = ShouldRenderLiveGCD(cdInfoOnGCD)
            -- Real CD classification needs only: isActive=true (already checked)
            -- AND isOnGCD~=true. Both are NeverSecret. IsSpellUsable was
            -- previously layered on top and flipped misclassification on
            -- every resource tick.
            if durObj and not renderLiveGCD then
                state.mode = "cooldown"
                SetCooldownStateActivity(state, true)
                state.durObj = durObj
                state.sourceID = sid
                state.spellID = sid
                state.cooldownInfo = cdInfo
                MemAuditProfilerMark("CDM_rsReturnLiveCD")
                return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
            end
            if cdInfoOnGCD == true and context.showGCDSwipe == true then
                local gcdDur = QueryGCDDurationObject(sid)
                if gcdDur then
                    state.mode = "gcd-only"
                    SetCooldownStateActivity(state, true)
                    state.durObj = gcdDur
                    state.sourceID = sid
                    state.spellID = sid
                    state.cooldownInfo = cdInfo
                    MemAuditProfilerMark("CDM_rsReturnGCD")
                    return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
                end
                if durObj and renderLiveGCD then
                    state.mode = "gcd-only"
                    SetCooldownStateActivity(state, true)
                    state.durObj = durObj
                    state.sourceID = sid
                    state.spellID = sid
                    state.cooldownInfo = cdInfo
                    MemAuditProfilerMark("CDM_rsReturnGCDDur")
                    return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
                end
            end
        end
    end
    MemAuditProfilerMark("CDM_rsLiveCDProbe")

    if gcdDurObj then
        state.mode = "gcd-only"
        SetCooldownStateActivity(state, true)
        state.durObj = gcdDurObj
        state.sourceID = sid
        state.spellID = sid
        state.cooldownInfo = gcdCdInfo
        MemAuditProfilerMark("CDM_rsReturnGCDCached")
        return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
    end

    -- Charge recharge on a multi-charge spell that the cooldown API reports
    -- as castable (cdInfo.isActive=false because a charge is still
    -- available). Blizzard's CooldownViewer surfaces the recharge timing
    -- from C_Spell.GetSpellCharges in this state — see
    -- CheckCacheCooldownValuesFromCharges. Mirror it here so the recharge
    -- swipe binds instead of falling through to inactive. (entryMayHaveCharges
    -- is computed once above for the on-GCD recharge interception.)
    if HasActiveChargeRecharge(sid, entryMayHaveCharges) then
        local chargeDur = QueryChargeDuration(sid)
        if chargeDur then
            state.mode = "cooldown"
            SetCooldownStateActivity(state, true)
            state.durObj = chargeDur
            state.sourceID = sid
            state.spellID = sid
            MemAuditProfilerMark("CDM_rsReturnChargeRecharge")
            return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
        end
    end

    state.mode = "inactive"
    state.spellID = sid
    MemAuditProfilerMark("CDM_rsReturnInactive")
    return FinalizeCooldownStateActivity(state, context, entry, sid, entryIsAura, itemBackedEntry)
end

-- SetResolveCallerTag is nil until QUI_Debug activates instrumentation; the
-- if-guards in cdm_icon_renderer.lua and cdm_icon_runtime_refresh.lua
-- short-circuit to a single nil-check when debug is off (mirrors measureFn/markFn).

function CDMResolvers.ResolveCooldownState(context)
    if resolverStats then
        local tag = currentResolveCallerTag or "other"
        local byTag = resolverStats.resolveBy
        byTag[tag] = (byTag[tag] or 0) + 1
    end
    local owner = context and context.owner
    if owner and RuntimeQueries and RuntimeQueries.WithRuntimeQueryOwner then
        return RuntimeQueries.WithRuntimeQueryOwner(owner, ResolveCooldownStateCore, context)
    end
    return ResolveCooldownStateCore(context)
end
