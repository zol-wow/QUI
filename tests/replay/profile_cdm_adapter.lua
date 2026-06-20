-- tests/replay/profile_cdm_adapter.lua
-- Headless CDM allocation-profiling adapter.
-- Replays a captured QUI_Logger event session into CDM's real refresh
-- controllers and reports per-event-type allocation churn via profile_replay.
--
-- Usage (module):
--   local A = assert(loadfile("tests/replay/profile_cdm_adapter.lua"))()
--   local built = A.Build()           -- stubs WoW globals, loads CDM, builds controller
--   local churn, counts, rep = A.ProfileSession(built.controller, events)
--
-- luacheck: globals CreateFrame GetTime InCombatLockdown IsInRaid issecretvalue wipe
-- luacheck: globals C_Timer C_Spell C_Item C_UnitAuras debugprofilestop
-- luacheck: globals GetInventoryItemID GetInventoryItemLink GetInventoryItemTexture
-- luacheck: globals GetInventoryItemCooldown

local A = {}

-- -----------------------------------------------------------------------
-- WoW global stubs (set lazily at Build() time so they don't pollute the
-- test runner namespace before the adapter is used)
-- -----------------------------------------------------------------------
local function stubWoWGlobals(opts)
    local onCB = opts and opts.onCallback

    -- Core frame / timing
    CreateFrame = function()                          -- luacheck: ignore 121
        return {
            SetScript        = function() end,
            RegisterEvent    = function() end,
            UnregisterEvent  = function() end,
            Show             = function() end,
            Hide             = function() end,
            SetParent        = function() end,
        }
    end
    GetTime           = function() return 0 end       -- luacheck: ignore 121
    InCombatLockdown  = function() return false end   -- luacheck: ignore 121
    IsInRaid          = function() return false end   -- luacheck: ignore 121
    issecretvalue     = function() return false end   -- luacheck: ignore 121
    debugprofilestop  = function() return 0 end       -- luacheck: ignore 121

    wipe = function(t)                                -- luacheck: ignore 121
        for k in pairs(t) do t[k] = nil end
        return t
    end

    C_Timer = {                                       -- luacheck: ignore 121
        After    = function() end,
        NewTimer = function() return { Cancel = function() end } end,
    }

    C_Spell = {                                       -- luacheck: ignore 121
        GetSpellCharges            = function() end,
        GetSpellCooldown           = function() return { startTime=0, duration=0, isEnabled=true } end,
        GetSpellCooldownDuration   = function() return 0 end,
        GetBaseSpell               = function(id) return id end,
        GetSpellBaseCooldown       = function() return 0 end,
        GetSpellChargeDuration     = function() return 0 end,
        GetOverrideSpell           = function(id) return id end,
        GetSpellDisplayCount       = function() return 0 end,
        GetSpellCastCount          = function() return 0 end,
        GetSpellInfo               = function() return nil end,
        GetSpellName               = function() return "Spell" end,
        GetSpellTexture            = function() return 0 end,
        IsSpellUsable              = function() return true end,
        IsSpellInRange             = function() return true end,
        SpellHasRange              = function() return false end,
    }

    C_Item = {                                        -- luacheck: ignore 121
        GetItemInfoInstant             = function() end,
        GetItemIconByID                = function() end,
        GetItemNameByID                = function() end,
        GetItemSpell                   = function() end,
        GetItemQualityByID             = function() end,
        GetFirstTriggeredSpellForItem  = function() end,
        IsEquippedItem                 = function() end,
        GetItemCount                   = function() return 0 end,
        GetItemCooldown                = function() return 0, 0, 0 end,
    }

    C_UnitAuras = {                                   -- luacheck: ignore 121
        GetAuraDuration           = function() return 0 end,
        GetAuraDataByAuraInstanceID = function() return nil end,
    }

    GetInventoryItemID       = function() end         -- luacheck: ignore 121
    GetInventoryItemLink     = function() end         -- luacheck: ignore 121
    GetInventoryItemTexture  = function() end         -- luacheck: ignore 121
    GetInventoryItemCooldown = function() return 0, 0, 0 end -- luacheck: ignore 121

    -- Return a helper for wrapping callbacks with instrumentation
    return function(name, fn)
        if not onCB then return fn end
        return function(...)
            onCB(name)
            return fn(...)
        end
    end
end

-- -----------------------------------------------------------------------
-- Build realistic icon pools (~40 icons)
-- -----------------------------------------------------------------------
local function buildPools()
    local function makeIcon(name, entry)
        return { name = name, _spellEntry = entry }
    end

    local essential = {}
    -- 15 cooldown spell icons, spellIDs 100..114
    for i = 1, 15 do
        essential[i] = makeIcon("ess_spell_" .. i, {
            id          = 100 + i - 1,
            spellID     = 100 + i - 1,
            kind        = "cooldown",
            type        = "spell",
            viewerType  = "essential",
        })
    end
    -- 2 item icons
    essential[16] = makeIcon("ess_item_1", {
        id           = 501,
        spellID      = 501,
        itemID       = 501,
        kind         = "cooldown",
        type         = "item",
        viewerType   = "essential",
    })
    essential[17] = makeIcon("ess_item_2", {
        id           = 502,
        spellID      = 502,
        itemID       = 502,
        kind         = "cooldown",
        type         = "item",
        viewerType   = "essential",
    })

    local utility = {}
    for i = 1, 10 do
        utility[i] = makeIcon("util_spell_" .. i, {
            id         = 120 + i - 1,
            spellID    = 120 + i - 1,
            kind       = "cooldown",
            type       = "spell",
            viewerType = "utility",
        })
    end

    local buff = {}
    for i = 1, 12 do
        local icon = makeIcon("buff_aura_" .. i, {
            id            = 200 + i - 1,
            spellID       = 200 + i - 1,
            kind          = "aura",
            type          = "spell",
            viewerType    = "buff",
            containerType = "aura",
        })
        icon._auraActive = true
        buff[i] = icon
    end

    return { essential = essential, utility = utility, buff = buff }
end

-- -----------------------------------------------------------------------
-- Build the CDM controller with realistic callbacks
-- -----------------------------------------------------------------------
local function buildController(ns, pools, wrap)
    -- wrap() adds optional instrumentation around a callback fn
    local function w(name, fn) return wrap(name, fn) end

    local callbacks = {
        isRuntimeEnabled = w("isRuntimeEnabled", function() return true end),

        getIconPools = w("getIconPools", function() return pools end),

        isSecretValue = w("isSecretValue", function() return false end),

        prepareBatch = w("prepareBatch", function()
            -- editMode, ncdm, ncdmContainers, inCombat
            return false, {}, {}, false
        end),

        beginBatch = w("beginBatch", function() end),

        endBatch = w("endBatch", function() end),

        setStackTextWrites = w("setStackTextWrites", function() end),

        -- Per-icon work callbacks: do a small realistic touch so churn is
        -- non-trivial and attributable to the right event type.
        applyResolvedCooldown = w("applyResolvedCooldown", function(icon)
            -- Read entry fields and stamp a runtime field (realistic touch)
            local entry = icon._spellEntry
            if entry then
                icon._runtimeSpellID   = entry.spellID
                icon._runtimeKind      = entry.kind
                icon._runtimeViewerType = entry.viewerType
            end
        end),

        updateIconCooldown = w("updateIconCooldown", function(icon)
            local entry = icon._spellEntry
            if entry then
                icon._runtimeSpellID = entry.spellID
                icon._lastUpdateTick = 1
            end
        end),

        applyAuraScopedResolvedCooldown = w("applyAuraScopedResolvedCooldown", function(icon)
            local entry = icon._spellEntry
            if entry then
                icon._runtimeSpellID = entry.spellID
                icon._auraResolved   = true
            end
            return true
        end),

        resolveContainerDBAndType = w("resolveContainerDBAndType", function(entry)
            return {}, entry and entry.containerType
        end),

        updateContainerVisibility = w("updateContainerVisibility", function(icon)
            icon._visible = true
        end),

        syncCooldownBling = w("syncCooldownBling", function() end),

        drainLayoutDirty = w("drainLayoutDirty", function() end),

        isAuraEntry = w("isAuraEntry", function(entry)
            return entry and entry.kind == "aura"
        end),

        isDefinitivelySelfAuraIcon = w("isDefinitivelySelfAuraIcon", function()
            return false
        end),

        getMirrorStateByCooldownID = w("getMirrorStateByCooldownID", function()
            return nil
        end),

        getItemIDForEntry = w("getItemIDForEntry", function(entry)
            return entry and entry.itemID
        end),

        queryItemSpell = w("queryItemSpell", function()
            return nil
        end),

        queryCooldownAuraBySpellID = w("queryCooldownAuraBySpellID", function()
            return nil
        end),

        clearDurationBinding = w("clearDurationBinding", function(icon)
            icon._lastDurObjKey        = nil
            icon._lastDurObj           = nil
            icon._lastResolvedMode     = nil
            icon._lastResolvedSourceID = nil
            icon._lastResolvedSpellID  = nil
        end),

        updateIconRangesForUsabilityEvent = w("updateIconRangesForUsabilityEvent", function() end),

        scheduleUpdate = w("scheduleUpdate", function() end),

        isPlayerInCombat = w("isPlayerInCombat", function() return false end),

        getCombatQueueDelay = w("getCombatQueueDelay", function() return 0.3 end),

        requestStackTextUpdate = w("requestStackTextUpdate", function() end),

        noteChargeDurationObjectsUpdated = w("noteChargeDurationObjectsUpdated", function() end),

        recordRecentPlayerSpellCast = w("recordRecentPlayerSpellCast", function() end),

        getHighlighter = w("getHighlighter", function()
            return { OnPlayerCastSucceeded = function() end }
        end),

        setBarsDirty = w("setBarsDirty", function() end),

        markBarsForAuraRefresh = w("markBarsForAuraRefresh", function() end),

        runDirtyBarUpdate = w("runDirtyBarUpdate", function() end),

        clearDurationBindingKeyCache = w("clearDurationBindingKeyCache", function() end),

        clearStableCaches = w("clearStableCaches", function() end),

        invalidateSpellCaches = w("invalidateSpellCaches", function() end),

        invalidateMacroCache = w("invalidateMacroCache", function() end),

        updateAllIconRanges = w("updateAllIconRanges", function() end),

        updateIconsForSpellRangeEvent = w("updateIconsForSpellRangeEvent", function() end),
    }

    return ns.CDMIconRuntimeRefresh.Create(callbacks)
end

-- -----------------------------------------------------------------------
-- EVENT -> controller method map
-- -----------------------------------------------------------------------

-- Built lazily after Build() creates the controller
A.EVENT_MAP = {}

local function buildEventMap()
    return {
        UNIT_AURA = function(ctrl, a)
            -- a[1]=unit, a[2]=updateInfo (may be nil)
            ctrl:HandleAuraRefresh(a[1], a[2])
        end,

        SPELL_UPDATE_USABLE = function(ctrl)
            ctrl:QueueUsabilityRefresh()
        end,

        SPELL_UPDATE_COOLDOWN = function(ctrl, a)
            -- a[1]=spellID, drive with kind="refresh"
            ctrl:HandleCooldownChanged(nil, a[1], nil, "refresh")
        end,

        PLAYER_TARGET_CHANGED = function(ctrl, a)
            ctrl:ApplyTargetScope(a[1])
        end,

        PLAYER_SOFT_ENEMY_CHANGED = function(ctrl, a)
            ctrl:ApplyTargetScope(a[1])
        end,

        PLAYER_REGEN_ENABLED = function(ctrl)
            ctrl:DrainDeferredFullRefresh()
        end,

        SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = function(ctrl, a)
            ctrl:QueueResolvedCooldownForSpellID(a[1], nil)
        end,

        SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = function(ctrl, a)
            ctrl:QueueResolvedCooldownForSpellID(a[1], nil)
        end,

        BAG_UPDATE_COOLDOWN = function(ctrl)
            ctrl:QueueItemScopeRefresh({ refreshRuntime = true })
        end,

        BAG_UPDATE_DELAYED = function(ctrl)
            ctrl:QueueItemScopeRefresh({ refreshRuntime = true })
        end,

        UPDATE_SHAPESHIFT_FORM = function(ctrl)
            ctrl:QueueCatalogScopeRefresh({ includeItems = false })
        end,

        UPDATE_SHAPESHIFT_FORMS = function(ctrl)
            ctrl:QueueCatalogScopeRefresh({ includeItems = false })
        end,
    }
end

-- -----------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------

--- A.Build(opts) -> { controller, pools, stats }
-- opts.onCallback(name) is called inside each instrumented callback (optional).
function A.Build(opts)
    local wrap = stubWoWGlobals(opts)

    local loader = dofile("tests/helpers/load_cdm_icon_runtime.lua")
    local ns = loader({})

    assert(ns.CDMIconRuntimeRefresh, "CDMIconRuntimeRefresh must load")

    local pools      = buildPools()
    local controller = buildController(ns, pools, wrap)

    -- Populate the shared EVENT_MAP after first Build()
    A.EVENT_MAP = buildEventMap()

    return {
        controller = controller,
        pools      = pools,
        stats      = {},
    }
end

--- A.dispatch(controller, event) -> applies one event via EVENT_MAP
function A.dispatch(controller, event)
    local fn = A.EVENT_MAP[event.e]
    if fn then
        fn(controller, event.a or {})
    end
end

--- A.ProfileSession(controller, events)
--   -> churn (table), counts (table), report (string)
-- Also returns a fourth value: total P.measure result.
function A.ProfileSession(controller, events)
    local P = assert(loadfile("tests/replay/profile_replay.lua"))()

    local unmappedCount = 0

    local churn, counts = P.profilePerKey(
        events,
        function(ev) return ev.e end,
        function(ev)
            local fn = A.EVENT_MAP[ev.e]
            if fn then
                fn(controller, ev.a or {})
            else
                unmappedCount = unmappedCount + 1
            end
        end)

    -- Remove unmapped entries from churn/counts so they don't pollute
    -- the per-event attribution (they were counted but got 0 work).
    -- Expose unmapped total via stats field on the module.
    A._lastUnmappedCount = unmappedCount

    local rep = P.report(churn, counts)
    local total = P.measure(function()
        for i = 1, #events do
            local ev = events[i]
            local fn = A.EVENT_MAP[ev.e]
            if fn then fn(controller, ev.a or {}) end
        end
    end)

    return churn, counts, rep, total
end

return A
