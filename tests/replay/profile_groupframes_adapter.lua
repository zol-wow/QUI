-- tests/replay/profile_groupframes_adapter.lua
-- Headless group-frames allocation-profiling adapter.
-- Replays a captured QUI_Logger event session into group-frames' real aura
-- render sub-modules and reports per-event-type allocation churn via
-- profile_replay.
--
-- SCOPE "aura" (default, PRIMARY):
--   Loads the self-contained sub-modules:
--     QUI_GroupFrames/groupframes/groupframes_aura_model.lua  (pure data)
--     QUI_GroupFrames/groupframes/groupframes_aura_render.lua (render dispatch)
--   Both load cleanly via assert(loadfile(path))("QUI_GroupFrames", ns).
--   The UNIT_AURA hot path (aura scan -> Model + R.Dispatch) is the
--   FPS-critical path and is fully exercised here.
--
-- SCOPE "full" (SECONDARY):
--   Loads the REAL QUI_GroupFrames/groupframes/groupframes.lua, captures the
--   module-scope OnEvent handler set via eventFrame:SetScript("OnEvent", fn),
--   injects a synthetic unit frame into QUI_GF.unitFrameMap["raid1"], and
--   drives the REAL local Update* functions (UpdateHealth, UpdatePower,
--   UpdateAbsorbs, UpdateHealAbsorb, UpdateHealPrediction, UpdateName,
--   UpdateThreat, UpdateConnection) via the captured OnEvent.
--
-- Usage (module):
--   local A = assert(loadfile("tests/replay/profile_groupframes_adapter.lua"))()
--   local built = A.Build()                       -- aura scope (default)
--   local churn, counts, rep, total = A.ProfileSession(built.ctx, events)
--
--   local fbuilt = A.Build({scope="full"})        -- full scope
--   local churn, counts, rep, total = A.ProfileSessionFull(fbuilt.ctx, events)
--
-- luacheck: globals CreateFrame issecretvalue GetTime C_UnitAuras
-- luacheck: globals UnitHealth UnitHealthMax UnitPower UnitPowerMax UnitExists
-- luacheck: globals UnitIsConnected UnitClass UnitName UnitThreatSituation
-- luacheck: globals UnitGetTotalAbsorbs UnitHealPrediction InCombatLockdown
-- luacheck: globals hooksecurefunc wipe
-- luacheck: globals UnitIsDeadOrGhost UnitIsGhost UnitGroupRolesAssigned
-- luacheck: globals UnitGetTotalHealAbsorbs UnitIsUnit UnitGUID UnitPowerType
-- luacheck: globals UnitIsPlayer UnitHealthPercent CurveConstants
-- luacheck: globals GetNumGroupMembers GetRaidRosterInfo IsInRaid IsInGroup
-- luacheck: globals GetReadyCheckStatus GetRaidTargetIndex SetRaidTargetIconTexture
-- luacheck: globals GetInstanceInfo CheckUnitRange RegisterUnitWatch
-- luacheck: globals AbbreviateNumbers AbbreviateLargeNumbers RAID_CLASS_COLORS
-- luacheck: globals C_UnitAuras C_IncomingSummon C_SummonInfo C_CurveUtil
-- luacheck: globals C_Timer StaticPopup_FindVisible GameTooltip UIParent
-- luacheck: globals CreateColor format

local A = {}

-- -----------------------------------------------------------------------
-- WoW global stubs (set at Build() time; do not pollute before use)
-- -----------------------------------------------------------------------
local function stubWoWGlobals(opts)
    local onCB = opts and opts.onCallback

    -- Minimal CreateFrame: returns a stub frame with all methods used by
    -- groupframes_aura_render.lua at function-call time (NOT file scope).
    CreateFrame = function(ftype, _name, _parent, _template) -- luacheck: ignore 121
        local f = { _type = ftype, _shown = false, _level = 1,
                    _w = 40, _h = 40, _points = {} }
        f.SetScript          = function() end
        f.RegisterEvent      = function() end
        f.UnregisterEvent    = function() end
        f.Show               = function(self) self._shown = true end
        f.Hide               = function(self) self._shown = false end
        f.IsShown            = function(self) return self._shown end
        f.SetParent          = function() end
        f.SetAllPoints       = function() end
        f.ClearAllPoints     = function(self) self._points = {} end
        f.SetPoint           = function() end
        f.SetSize            = function(self, w, h) self._w = w; self._h = h end
        f.GetWidth           = function(self) return self._w end
        f.GetHeight          = function(self) return self._h end
        f.GetFrameLevel      = function(self) return self._level end
        f.SetFrameLevel      = function(self, l) self._level = l end
        f.SetAlpha           = function() end
        f.SetBackdropBorderColor = function() end
        f.SetBackdrop        = function() end
        f.EnableMouse        = function() end
        -- StatusBar
        f.SetMinMaxValues    = function() end
        f.SetValue           = function() end
        f.SetStatusBarColor  = function() end
        f.SetStatusBarTexture = function() end
        f.SetOrientation     = function() end
        f.SetReverseFill     = function() end
        -- Cooldown
        f.SetDrawEdge        = function() end
        f.SetDrawBling       = function() end
        f.SetDrawSwipe       = function() end
        f.SetHideCountdownNumbers = function() end
        f.SetReverse         = function() end
        f.Clear              = function() end
        f.SetCooldownFromDurationObject = function() end
        -- CreateTexture child
        f.CreateTexture = function()
            local t = {}
            t.SetAllPoints   = function() end
            t.SetTexCoord    = function() end
            t.SetTexture     = function() end
            t.SetColorTexture = function() end
            t.SetBlendMode   = function() end
            t.Show           = function() end
            t.Hide           = function() end
            t.GetTexture     = function() return nil end
            return t
        end
        return f
    end

    -- Timing / combat
    GetTime          = function() return 0 end          -- luacheck: ignore 121
    InCombatLockdown = function() return false end      -- luacheck: ignore 121
    issecretvalue    = function() return false end      -- luacheck: ignore 121

    -- Unit query stubs (used by UNIT_HEALTH / UNIT_POWER handlers)
    UnitHealth       = function() return 100 end        -- luacheck: ignore 121
    UnitHealthMax    = function() return 100 end        -- luacheck: ignore 121
    UnitPower        = function() return 100 end        -- luacheck: ignore 121
    UnitPowerMax     = function() return 100 end        -- luacheck: ignore 121
    UnitExists       = function() return true end       -- luacheck: ignore 121
    UnitIsConnected  = function() return true end       -- luacheck: ignore 121
    UnitClass        = function() return "Warrior", "WARRIOR" end -- luacheck: ignore 121
    UnitName         = function() return "Player" end   -- luacheck: ignore 121
    UnitThreatSituation = function() return nil end     -- luacheck: ignore 121
    UnitGetTotalAbsorbs = function() return 0 end       -- luacheck: ignore 121
    UnitHealPrediction  = function() return 0 end       -- luacheck: ignore 121

    -- C_UnitAuras: aura query (returns nil = no live aura)
    C_UnitAuras = {                                     -- luacheck: ignore 121
        GetAuraDuration             = function() return nil end,
        GetAuraDataByAuraInstanceID = function() return nil end,
    }

    -- hooksecurefunc: no-op stub
    hooksecurefunc = function() end                     -- luacheck: ignore 121

    -- wipe: Lua 5.1 compatible table-wipe
    wipe = function(t)                                  -- luacheck: ignore 121
        for k in pairs(t) do t[k] = nil end
        return t
    end

    -- Return a helper that wraps a render method with an onCallback notification
    return function(name, fn)
        if not onCB then return fn end
        return function(...)
            onCB(name)
            return fn(...)
        end
    end
end

-- -----------------------------------------------------------------------
-- Load the aura sub-modules
-- -----------------------------------------------------------------------
local function loadSubModules()
    local ns = {}
    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_aura_model.lua"))(
        "QUI_GroupFrames", ns)
    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_aura_render.lua"))(
        "QUI_GroupFrames", ns)
    assert(ns.QUI_GroupFramesAuraModel,   "aura model must load")
    assert(ns.QUI_GroupFrameAuraRender,   "aura render must load")
    return ns
end

-- -----------------------------------------------------------------------
-- Build a synthetic unit frame + aura cache
-- The synthetic frame mimics the shape groupframes_aura_render.lua expects:
--   frame.unit       = "player"
--   frame._bottomPad = 0
--   frame:GetFrameLevel() => number
--   frame:GetWidth()      => number
-- -----------------------------------------------------------------------
local function buildSyntheticFrame(ns)
    -- Use the CreateFrame stub that was just installed
    local frame = CreateFrame("Frame") -- luacheck: ignore
    frame.unit       = "player"
    frame._bottomPad = 0
    -- ns.SkinBase must be a TABLE (render module does: SkinBase() -> ns.SkinBase)
    ns.SkinBase = { ApplyPixelBackdrop = function() end }
    return frame
end

-- Build a synthetic aura cache with a few sample entries for "player".
-- The cache shape mirrors what groupframes_auras.lua builds:
--   cache.buffsBySpellID  = { [spellID] = auraData }
--   cache.debuffsBySpellID = { [spellID] = auraData }
local function buildAuraCache()
    return {
        buffsBySpellID = {
            [21562] = { auraInstanceID = 1001, spellId = 21562, icon = 135924,
                        duration = 3600, expirationTime = 3600 },
            [1126]  = { auraInstanceID = 1002, spellId = 1126,  icon = 136100,
                        duration = 3600, expirationTime = 3600 },
        },
        debuffsBySpellID = {
            [8326]  = { auraInstanceID = 2001, spellId = 8326,  icon = 136050,
                        duration = 10,   expirationTime = 15 },
        },
    }
end

-- Build a realistic aura element list (a filterStrip + a tracked icon),
-- matching what the user would configure for a group frame.
local function buildElements(Model)
    local els = {}
    -- Debuff filterStrip
    local strip = Model.NewFilterStripElement("HARMFUL")
    strip.maxIcons = 3
    strip.iconSize = 16
    els[#els + 1] = strip
    -- Buff filterStrip (disabled by default per shipped seed, but enabled here
    -- so ProfileSession exercises it)
    local buffs = Model.NewFilterStripElement("HELPFUL")
    buffs.enabled = true
    buffs.maxIcons = 3
    buffs.iconSize = 14
    els[#els + 1] = buffs
    -- Tracked icon (Rejuvenation)
    local tracked = Model.NewTrackedElement({ 774 }, "icon")
    tracked.iconSize = 14
    els[#els + 1] = tracked
    return els
end

-- -----------------------------------------------------------------------
-- Build filterStrip matches from aura cache (mimics groupframes_auras.lua's
-- BuildFilterStripMatches). For profiling purposes we hand ALL debuffs/buffs
-- to their respective strips in insertion order.
-- -----------------------------------------------------------------------
local function buildFilterMatches(element, auraCache)
    local matches = {}
    if element.auraType == "HARMFUL" then
        for _, data in pairs(auraCache.debuffsBySpellID or {}) do
            matches[#matches + 1] = data
        end
    else
        for _, data in pairs(auraCache.buffsBySpellID or {}) do
            matches[#matches + 1] = data
        end
    end
    return matches
end

-- -----------------------------------------------------------------------
-- Instrument R.Dispatch and R.RenderIcon so opts.onCallback fires
-- -----------------------------------------------------------------------
local function instrumentRender(R, wrap)
    local origDispatch  = R.Dispatch
    local origRenderIcon = R.RenderIcon
    R.Dispatch   = wrap("Dispatch",   origDispatch)
    R.RenderIcon = wrap("RenderIcon", origRenderIcon)
end

-- -----------------------------------------------------------------------
-- Core aura scan: simulate what the real groupframes_auras.lua does on
-- UNIT_AURA for a single frame. Calls R.Dispatch per element so the
-- render hot path runs with real code.
-- -----------------------------------------------------------------------
local function runAuraScan(ctx)
    local R          = ctx.R
    local Model      = ctx.Model
    local frame      = ctx.frame
    local auraCache  = ctx.auraCache
    local elements   = ctx.elements
    local specID     = ctx.specID
    local scratch    = ctx.scratch or {}
    ctx.scratch = scratch

    -- ActiveElementsForSpec: zero-alloc reuse of scratch table
    local active = Model.ActiveElementsForSpec(
        { enabled = true, elementsSeeded = true, elements = { ["*"] = elements } },
        specID, scratch)

    for _, element in ipairs(active) do
        local matches
        if element.mode == "filterStrip" then
            matches = buildFilterMatches(element, auraCache)
        elseif element.mode == "tracked" then
            matches = Model.PopulateElementMatches(element, auraCache)
        else
            matches = {}
        end
        R:Dispatch(frame, element, matches)
    end
end

-- -----------------------------------------------------------------------
-- EVENT -> ctx dispatch map
-- UNIT_AURA drives the full aura scan (model + render) — this is the hot path.
-- UNIT_HEALTH / UNIT_POWER* / UNIT_ABSORB / UNIT_HEAL_PREDICTION do a
-- lightweight synthetic touch (update the frame's cached health/power pct) so
-- churn from these events is attributable and non-zero.
-- Unmapped events: silently skip + count.
-- -----------------------------------------------------------------------

A.EVENT_MAP = {}   -- populated after first Build()

local function buildEventMap()
    return {
        UNIT_AURA = function(ctx, a)
            -- a[1]=unit; if it's our synthetic unit, run the aura scan
            -- (mirrors the real per-frame UNIT_AURA fan-out)
            local _ = a[1]  -- unit token consumed (unused beyond identity check)
            runAuraScan(ctx)
        end,

        UNIT_HEALTH = function(ctx, a)
            local _ = a[1]  -- unit
            -- Realistic touch: update cached healthPct (no allocation normally,
            -- but UnitHealth/UnitHealthMax calls exercise the stub path)
            local hp    = UnitHealth("player")    -- luacheck: ignore
            local hpMax = UnitHealthMax("player") -- luacheck: ignore
            local pct = (hpMax and hpMax > 0) and (hp / hpMax * 100) or 0
            ctx.frame._healthPct = pct
        end,

        UNIT_MAXHEALTH = function(ctx, a)
            local _ = a[1]
            local hp    = UnitHealth("player")    -- luacheck: ignore
            local hpMax = UnitHealthMax("player") -- luacheck: ignore
            local pct = (hpMax and hpMax > 0) and (hp / hpMax * 100) or 0
            ctx.frame._healthPct = pct
        end,

        UNIT_POWER_UPDATE = function(ctx, a)
            local _ = a[1]  -- unit
            local _pt = a[2]  -- powerType
            ctx.frame._powerPct = UnitPower("player") / math.max(1, UnitPowerMax("player")) -- luacheck: ignore
        end,

        UNIT_POWER_FREQUENT = function(ctx, a)
            local _ = a[1]
            local _pt = a[2]
            ctx.frame._powerPct = UnitPower("player") / math.max(1, UnitPowerMax("player")) -- luacheck: ignore
        end,

        UNIT_ABSORB_AMOUNT_CHANGED = function(ctx, a)
            local _ = a[1]
            ctx.frame._absorb = UnitGetTotalAbsorbs("player") -- luacheck: ignore
        end,

        UNIT_HEAL_PREDICTION = function(ctx, a)
            local _ = a[1]
            ctx.frame._healPred = UnitHealPrediction("player") -- luacheck: ignore
        end,

        UNIT_THREAT_SITUATION_UPDATE = function(ctx, a)
            local _ = a[1]
            ctx.frame._threat = UnitThreatSituation("player", "player") -- luacheck: ignore
        end,

        UNIT_NAME_UPDATE = function(ctx, a)
            local _ = a[1]
            ctx.frame._name = UnitName("player") -- luacheck: ignore
        end,
    }
end

-- -----------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------

--- A.Build(opts) -> { ctx }
-- opts.onCallback(name) instrumentation hook (optional).
-- Stubs WoW globals, loads real aura sub-modules, builds synthetic frame +
-- aura cache + element list. Returns { ctx = { R, Model, frame, auraCache,
-- elements, specID, scratch } }.
function A.Build(opts)
    local wrap = stubWoWGlobals(opts)

    local ns    = loadSubModules()
    local Model = ns.QUI_GroupFramesAuraModel
    local R     = ns.QUI_GroupFrameAuraRender

    -- Instrument render methods so onCallback fires when they run
    instrumentRender(R, wrap)

    local frame     = buildSyntheticFrame(ns)
    local auraCache = buildAuraCache()
    local elements  = buildElements(Model)

    local ctx = {
        R          = R,
        Model      = Model,
        frame      = frame,
        auraCache  = auraCache,
        elements   = elements,
        specID     = nil,   -- nil -> inherit "*" bucket
        scratch    = {},
        stats      = {},
    }

    -- Populate the shared EVENT_MAP after first Build()
    A.EVENT_MAP = buildEventMap()

    return { ctx = ctx }
end

--- A.dispatch(ctx, event) -> applies one event via EVENT_MAP
function A.dispatch(ctx, event)
    local fn = A.EVENT_MAP[event.e]
    if fn then
        fn(ctx, event.a or {})
    end
end

--- A.ProfileSession(ctx, events)
--   -> churn (table), counts (table), report (string), total (P.measure result)
-- Profiles per-event-type allocation churn over a captured event list.
-- Unmapped events are silently skipped; their total is in A._lastUnmappedCount.
function A.ProfileSession(ctx, events)
    local P = assert(loadfile("tests/replay/profile_replay.lua"))()

    local unmappedCount = 0

    local churn, counts = P.profilePerKey(
        events,
        function(ev) return ev.e end,
        function(ev)
            local fn = A.EVENT_MAP[ev.e]
            if fn then
                fn(ctx, ev.a or {})
            else
                unmappedCount = unmappedCount + 1
            end
        end)

    A._lastUnmappedCount = unmappedCount

    local rep = P.report(churn, counts)
    local total = P.measure(function()
        for i = 1, #events do
            local ev = events[i]
            local fn = A.EVENT_MAP[ev.e]
            if fn then fn(ctx, ev.a or {}) end
        end
    end)

    return churn, counts, rep, total
end

-- =======================================================================
-- FULL-SCOPE IMPLEMENTATION
-- Loads QUI_GroupFrames/groupframes/groupframes.lua headlessly, captures
-- the module-scope OnEvent handler, and drives the REAL local Update*
-- functions (UpdateHealth, UpdatePower, UpdateAbsorbs, etc.) via it.
-- =======================================================================

-- -----------------------------------------------------------------------
-- Build a rich CreateFrame stub that captures OnEvent handlers.
-- capturedHandlers is keyed by frame index (order of creation); we keep all
-- OnEvent handlers that get set and return the last one (the eventFrame
-- one is the one we care about — set at line 5452 of groupframes.lua).
-- -----------------------------------------------------------------------
local function makeFullFrameStub(capturedHandlers, onCB)
    local frameCount = 0

    local function makeStatusBarStub(name)
        local sb = { _shown = false, _level = 1, _val = 0, _min = 0, _max = 100 }
        sb.SetValue = function(self, v)
            self._val = v
            if onCB then onCB(name .. ":SetValue") end
        end
        sb.SetMinMaxValues = function(self, mn, mx) self._min = mn; self._max = mx end
        sb.SetStatusBarColor = function() end
        sb.SetStatusBarTexture = function() end
        sb.SetOrientation     = function() end
        sb.SetReverseFill     = function() end
        sb.GetFrameLevel      = function(self) return self._level end
        sb.SetFrameLevel      = function(self, l) self._level = l end
        sb.ClearAllPoints     = function() end
        sb.SetAllPoints       = function() end
        sb.SetPoint           = function() end
        sb.SetAlpha           = function() end
        sb.Show               = function(self) self._shown = true end
        sb.Hide               = function(self) self._shown = false end
        sb.IsShown            = function(self) return self._shown end
        sb.SetSize            = function() end
        sb.SetWidth           = function() end
        sb.SetHeight          = function() end
        sb.GetWidth           = function() return 200 end
        sb.GetHeight          = function() return 40 end
        sb.SetScript          = function() end
        return sb
    end

    local function makeFontStringStub()
        local fs = {}
        fs.SetText          = function() end
        fs.SetFormattedText = function() end
        fs.SetTextColor     = function() end
        fs.SetFont          = function() end
        fs.GetFont          = function() return "Fonts\\FRIZQT__.TTF", 10, "" end
        fs.Show             = function() end
        fs.Hide             = function() end
        fs.IsShown          = function() return false end
        fs.SetAlpha         = function() end
        return fs
    end

    local function makeTextureStub()
        local t = {}
        t.SetTexture      = function() end
        t.SetColorTexture = function() end
        t.SetVertexColor  = function() end
        t.SetAlpha        = function() end
        t.Show            = function() end
        t.Hide            = function() end
        t.IsShown         = function() return false end
        t.SetBlendMode    = function() end
        t.SetTexCoord     = function() end
        t.SetAllPoints    = function() end
        t.SetPoint        = function() end
        t.SetSize         = function() end
        t.GetTexture      = function() return nil end
        return t
    end

    local function makeFrame()
        frameCount = frameCount + 1
        local idx = frameCount
        local f = {
            _idx   = idx,
            _shown = false,
            _level = 1,
            _w = 200, _h = 40,
            _points = {},
            _scripts = {},
        }
        f.SetScript = function(self, scriptName, fn)
            self._scripts[scriptName] = fn
            if scriptName == "OnEvent" and fn then
                capturedHandlers[#capturedHandlers + 1] = { frame = self, fn = fn, idx = idx }
            end
        end
        f.GetScript         = function(self, scriptName) return self._scripts[scriptName] end
        f.RegisterEvent     = function() end
        f.RegisterUnitEvent = function() end
        f.UnregisterEvent   = function() end
        f.Show              = function(self) self._shown = true end
        f.Hide              = function(self) self._shown = false end
        f.IsShown           = function(self) return self._shown end
        f.SetParent         = function() end
        f.GetParent         = function() return nil end
        f.SetAllPoints      = function() end
        f.ClearAllPoints    = function(self) self._points = {} end
        f.SetPoint          = function() end
        f.SetSize           = function(self, w, h) self._w = w; self._h = h end
        f.SetWidth          = function() end
        f.SetHeight         = function() end
        f.GetWidth          = function(self) return self._w end
        f.GetHeight         = function(self) return self._h end
        f.GetFrameLevel     = function(self) return self._level end
        f.SetFrameLevel     = function(self, l) self._level = l end
        f.SetAlpha          = function() end
        f.GetAlpha          = function() return 1 end
        f.SetBackdrop       = function() end
        f.SetBackdropColor  = function() end
        f.SetBackdropBorderColor = function() end
        f.SetFixedFrameStrata = function() end
        f.SetFrameStrata    = function() end
        f.GetFrameStrata    = function() return "MEDIUM" end
        f.EnableMouse       = function() end
        f.SetMovable        = function() end
        f.SetResizable      = function() end
        f.IsForbidden       = function() return false end
        f.SetAttribute      = function() end
        f.GetAttribute      = function() return nil end
        f.SetClipsChildren  = function() end
        f.CreateTexture     = function() return makeTextureStub() end
        f.CreateFontString  = function() return makeFontStringStub() end
        -- StatusBar methods (for when CreateFrame("StatusBar") is used)
        f.SetValue          = function(self, v)
            if onCB then onCB("statusbar:SetValue") end
            self._val = v
        end
        f.SetMinMaxValues   = function() end
        f.SetStatusBarColor = function() end
        f.SetStatusBarTexture = function() end
        f.SetOrientation    = function() end
        f.SetReverseFill    = function() end
        -- SecureFrame
        f.CallMethod        = function() end

        -- Sub-widgets that groupframes.lua expects on unit frames
        -- (these are normally set by DecorateGroupFrame; we pre-attach them
        --  so the Update* functions don't nil-guard past the first check)
        f.healthBar        = makeStatusBarStub("healthBar")
        f.powerBar         = makeStatusBarStub("powerBar")
        f.absorbBar        = makeStatusBarStub("absorbBar")
        f.healAbsorbBar    = makeStatusBarStub("healAbsorbBar")
        f.healPredictionBar = makeStatusBarStub("healPredictionBar")
        f.healthText       = makeFontStringStub()
        f.nameText         = makeFontStringStub()
        f.statusText       = makeFontStringStub()
        f.Center           = makeTextureStub()   -- for SetBackdropFillColor
        return f
    end

    -- Override the global CreateFrame with our rich stub
    CreateFrame = function(_ftype, _name, _parent, _template) -- luacheck: ignore 121
        return makeFrame()
    end

    return makeStatusBarStub, makeFontStringStub, makeTextureStub
end

-- -----------------------------------------------------------------------
-- Build the ns object needed by groupframes.lua at load time.
-- ns.Helpers must provide: IsSecretValue, SafeValue, SafeToNumber,
-- ApplyCooldownFromAura, CreateDBGetter, GetCore, CreateStateTable,
-- TruncateUTF8, GetSkinBorderColor, ApplyFontWithFallback.
-- ns.Addon must carry db.profile.quiGroupFrames for GetDB() to return
-- {enabled=true} so RefreshCachedEnabled() sets cachedModuleEnabled=true.
-- -----------------------------------------------------------------------
local function buildFullNs(onCB)
    local profileDB = { quiGroupFrames = { enabled = true } }
    local coreAddon = { db = { profile = profileDB } }

    local Helpers = {}
    Helpers.IsSecretValue    = function() return false end
    Helpers.SafeValue        = function(v, fallback) return v ~= nil and v or fallback end
    Helpers.SafeToNumber     = function(v, fallback)
        local n = tonumber(v)
        return n ~= nil and n or (fallback or 0)
    end
    Helpers.ApplyCooldownFromAura = function() end
    Helpers.GetCore          = function() return coreAddon end
    Helpers.GetProfile       = function() return coreAddon.db.profile end
    Helpers.CreateDBGetter   = function(moduleName)
        return function()
            return coreAddon.db.profile[moduleName]
        end
    end
    Helpers.CreateStateTable = function()
        local tbl = setmetatable({}, { __mode = "k" })
        local function get(key)
            local s = tbl[key]
            if not s then s = {}; tbl[key] = s end
            return s
        end
        return tbl, get
    end
    Helpers.TruncateUTF8     = function(s, maxLen)
        return s and s:sub(1, maxLen) or ""
    end
    Helpers.GetSkinBorderColor = function() return 0.3, 0.3, 0.3, 1 end
    Helpers.ApplyFontWithFallback = function() end

    -- ns.L: localization table (string keys → display strings)
    local L = setmetatable({}, {
        __index = function(_, k) return k end,
    })

    -- ns.QUI_GroupFrameIconLayout: needed at module scope
    local QUI_GroupFrameIconLayout = {
        DISPEL_DEFAULT_COLORS = {
            Magic   = { 0.2, 0.6, 1.0, 1 },
            Curse   = { 0.6, 0.0, 1.0, 1 },
            Disease = { 0.6, 0.4, 0.0, 1 },
            Poison  = { 0.0, 0.6, 0.0, 1 },
            Bleed   = { 0.8, 0.1, 0.1, 1 },
        },
        HEADER_INIT_CONFIG_FUNC = "",
    }

    -- Instrument QUI_GroupFrameAuraRender if the aura sub-modules were loaded earlier
    -- (they share the same ns table — not the case here; full scope uses its own ns).
    local ns = {
        Addon                    = coreAddon,
        LSM                      = { Fetch = function() return "Fonts\\FRIZQT__.TTF" end },
        Helpers                  = Helpers,
        L                        = L,
        QUI_GroupFrameIconLayout = QUI_GroupFrameIconLayout,
        Registry                 = nil,  -- safe: guarded by `if ns.Registry then`
        -- These are nil at first; groupframes.lua populates them on load:
        QUI_GroupFrames          = nil,
        -- Optional modules that groupframes.lua checks with guards:
        QUI_GroupFrameAuraRender    = nil,
        QUI_GroupFramePrivateAuras  = nil,
        QUI_GroupFrameBlizzard      = nil,
        QUI_GroupFrameEditMode      = nil,
        QUI_GroupFrameClickCast     = nil,
    }

    return ns, onCB
end

-- -----------------------------------------------------------------------
-- Stub the global WoW APIs needed by groupframes.lua at LOAD time and at
-- Update* call time.  These are set into _G so the local upvalue captures
-- at module scope (lines 45-64 of groupframes.lua) pick them up.
-- -----------------------------------------------------------------------
local function installFullGlobals()
    -- Core globals captured as upvalues at load time.
    -- GetTime returns an incrementing value (step 0.5s) so per-unit throttles
    -- (powerThrottle, absorbThrottle) whose default `last` is 0 pass on the
    -- first call: (0.5 - 0) = 0.5 > THROTTLE_INTERVAL(0.1).
    local _gtTime = 0
    GetTime = function()                                    -- luacheck: ignore 121
        _gtTime = _gtTime + 0.5
        return _gtTime
    end
    InCombatLockdown = function() return false end          -- luacheck: ignore 121
    hooksecurefunc   = function() end                       -- luacheck: ignore 121
    issecretvalue    = function() return false end          -- luacheck: ignore 121
    format           = string.format                        -- luacheck: ignore 121

    wipe = function(t)                                      -- luacheck: ignore 121
        for k in pairs(t) do t[k] = nil end
        return t
    end

    -- RAID_CLASS_COLORS: returns a color table for any class key
    RAID_CLASS_COLORS = setmetatable({}, {                  -- luacheck: ignore 121
        __index = function() return { r=1, g=1, b=1, colorStr="ffffffff" } end
    })

    -- Unit query stubs
    UnitExists           = function() return true end       -- luacheck: ignore 121
    UnitHealth           = function() return 100 end        -- luacheck: ignore 121
    UnitHealthMax        = function() return 100 end        -- luacheck: ignore 121
    UnitPower            = function() return 50 end         -- luacheck: ignore 121
    UnitPowerMax         = function() return 100 end        -- luacheck: ignore 121
    UnitPowerType        = function() return 0 end          -- luacheck: ignore 121
    UnitClass            = function() return "Warrior", "WARRIOR" end -- luacheck: ignore 121
    UnitName             = function() return "Unit", "Realm" end      -- luacheck: ignore 121
    UnitIsDeadOrGhost    = function() return false end      -- luacheck: ignore 121
    UnitIsConnected      = function() return true end       -- luacheck: ignore 121
    UnitGroupRolesAssigned = function() return "DAMAGER" end -- luacheck: ignore 121
    UnitThreatSituation  = function() return nil end        -- luacheck: ignore 121
    UnitGetTotalAbsorbs  = function() return 0 end          -- luacheck: ignore 121
    UnitGetTotalHealAbsorbs = function() return 0 end       -- luacheck: ignore 121
    UnitIsUnit           = function() return false end      -- luacheck: ignore 121
    UnitIsGhost          = function() return false end      -- luacheck: ignore 121
    UnitGUID             = function() return "Player-1-00000000" end -- luacheck: ignore 121
    UnitIsPlayer         = function() return true end       -- luacheck: ignore 121
    UnitIsAFK            = function() return false end      -- luacheck: ignore 121
    UnitPhaseReason      = function() return nil end        -- luacheck: ignore 121
    UnitIsGroupLeader    = function() return false end      -- luacheck: ignore 121
    UnitIsGroupAssistant = function() return false end      -- luacheck: ignore 121
    UnitHasIncomingResurrection = function() return false end -- luacheck: ignore 121
    UnitHealthMissing    = function() return 0 end          -- luacheck: ignore 121
    -- UnitHealthPercent: used by GetHealthPct() → UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    UnitHealthPercent    = function() return 80 end         -- luacheck: ignore 121
    -- CurveConstants: table with ScaleTo100 enum value
    CurveConstants       = { ScaleTo100 = 1 }              -- luacheck: ignore 121

    GetNumGroupMembers   = function() return 5 end          -- luacheck: ignore 121
    GetRaidRosterInfo    = function() return nil end        -- luacheck: ignore 121
    IsInRaid             = function() return true end       -- luacheck: ignore 121
    IsInGroup            = function() return true end       -- luacheck: ignore 121
    GetReadyCheckStatus  = function() return nil end        -- luacheck: ignore 121
    GetRaidTargetIndex   = function() return nil end        -- luacheck: ignore 121
    SetRaidTargetIconTexture = function() end               -- luacheck: ignore 121
    GetInstanceInfo      = function() return "", "party", 1, "", 5, "", false, 0, "", 0 end -- luacheck: ignore 121
    CheckUnitRange       = function() return true end       -- luacheck: ignore 121
    RegisterUnitWatch    = function() end                   -- luacheck: ignore 121
    AbbreviateNumbers    = function(n) return tostring(n) end  -- luacheck: ignore 121
    AbbreviateLargeNumbers = function(n) return tostring(n) end -- luacheck: ignore 121

    -- C_* namespaces
    C_UnitAuras = {                                         -- luacheck: ignore 121
        GetAuraDataByAuraInstanceID  = function() return nil end,
        GetAuraDispelTypeColor       = function() return { r=0, g=0, b=0 } end,
        IsAuraFilteredOutByInstanceID = function() return false end,
        GetAuraSlots                 = function() return nil end,
        GetAuraDataBySlot            = function() return nil end,
        GetAuraDuration              = function() return 0 end,
    }

    C_IncomingSummon = {                                    -- luacheck: ignore 121
        HasIncomingSummon    = function() return false end,
        IncomingSummonStatus = function() return 0 end,
    }

    C_SummonInfo = {                                        -- luacheck: ignore 121
        GetSummonConfirmTimeLeft = function() return 0 end,
    }

    C_CurveUtil = {                                         -- luacheck: ignore 121
        CreateColorCurve = function()
            return {
                SetType  = function() end,
                AddPoint = function() end,
                Evaluate = function() return 1, 1, 1 end,
            }
        end,
    }

    C_Timer = {                                             -- luacheck: ignore 121
        After     = function() end,
        NewTicker = function() return { Cancel = function() end } end,
        NewTimer  = function() return { Cancel = function() end } end,
    }

    StaticPopup_FindVisible = function() return nil end     -- luacheck: ignore 121

    -- CreateColor: WoW color constructor — return a plain table
    CreateColor = function(r, g, b, a)                      -- luacheck: ignore 121
        return { r = r or 0, g = g or 0, b = b or 0, a = a or 1 }
    end

    -- GameTooltip stub
    GameTooltip = {                                         -- luacheck: ignore 121
        SetOwner = function() end,
        SetUnit  = function() end,
        Show     = function() end,
        Hide     = function() end,
    }

    -- UIParent: a minimal frame used for anchoring
    UIParent = {                                            -- luacheck: ignore 121
        SetPoint           = function() end,
        GetWidth           = function() return 1920 end,
        GetHeight          = function() return 1080 end,
        GetEffectiveScale  = function() return 1 end,
    }

    -- C_StringUtil (referenced in healthText deficit path)
    C_StringUtil = {                                        -- luacheck: ignore 121
        TruncateWhenZero = function(v) return tostring(v) end,
        WrapString       = function(s, prefix) return (prefix or "") .. s end,
    }
end

-- -----------------------------------------------------------------------
-- Load the real groupframes.lua headlessly.
-- Returns the loaded ns table (with ns.QUI_GroupFrames populated) and
-- the list of captured OnEvent handlers.
-- -----------------------------------------------------------------------
local function loadFullGroupFrames(opts)
    local capturedHandlers = {}

    -- Install rich WoW globals (sets CreateFrame + all Unit* etc. into _G)
    installFullGlobals()

    -- Override CreateFrame to capture OnEvent handlers
    makeFullFrameStub(capturedHandlers, opts and opts.onCallback)

    -- Build ns object for the module
    local ns = buildFullNs(opts and opts.onCallback)

    -- Load groupframes.lua — this runs all module-scope code including:
    --   local gruCoalesceFrame = CreateFrame("Frame")    (captures idx 1)
    --   local eventFrame = CreateFrame("Frame")          (captures idx 2)
    --   eventFrame:SetScript("OnEvent", OnEvent)         → capturedHandlers[?]
    --   local initFrame = CreateFrame("Frame")
    --   initFrame:RegisterEvent("ADDON_LOADED")
    --   initFrame:SetScript("OnEvent", fn)               → capturedHandlers[?]
    local loader = assert(loadfile("QUI_GroupFrames/groupframes/groupframes.lua"),
        "QUI_GroupFrames/groupframes/groupframes.lua must exist")
    loader("QUI_GroupFrames", ns)

    -- The QUI_GF module table is now in ns.QUI_GroupFrames
    local QUI_GF = ns.QUI_GroupFrames
    assert(QUI_GF, "QUI_GroupFrames must be populated after load")

    -- The main eventFrame OnEvent is the LAST one set before initFrame's handler.
    -- capturedHandlers contains all SetScript("OnEvent", fn) calls in order:
    --   [1] = gruCoalesceFrame OnUpdate (not OnEvent — this is a no-op SetScript)
    --   ... frames created at module scope ...
    --   [N-1] = eventFrame's OnEvent (line 5452: the main dispatcher)
    --   [N]   = initFrame's OnEvent  (line 5988: ADDON_LOADED handler)
    -- We want the second-to-last (the main eventFrame OnEvent).
    -- However, initFrame's handler is keyed to ADDON_LOADED and will be the
    -- last one. So we pick the second-to-last captured handler.
    local nH = #capturedHandlers
    assert(nH >= 2, "expected at least 2 OnEvent handlers; got " .. nH)

    -- The main OnEvent is nH-1 (before initFrame's handler)
    local mainHandler = capturedHandlers[nH - 1]
    assert(mainHandler, "main OnEvent handler must be captured")

    -- Prime cachedModuleEnabled: call RefreshSettings with initialized=false
    -- so it just calls RefreshCachedEnabled() and returns without doing full work.
    QUI_GF:RefreshSettings()

    -- Mark module as initialized so OnEvent doesn't early-return
    QUI_GF.initialized = true

    return ns, capturedHandlers, mainHandler
end

-- -----------------------------------------------------------------------
-- Build a synthetic unit frame with instrumented sub-regions.
-- This frame is injected into QUI_GF.unitFrameMap["raid1"].
-- The sub-regions (healthBar, powerBar, etc.) record SetValue calls via
-- opts.onCallback so tests can assert that real Update* ran.
-- -----------------------------------------------------------------------
local function buildFullSyntheticFrame(opts)
    local onCB = opts and opts.onCallback

    local function makeBar(name)
        local b = {
            _shown = false, _level = 1,
            _val = 0, _min = 0, _max = 100,
        }
        b.SetValue = function(self, v)
            self._val = v
            if onCB then onCB(name .. ":SetValue") end
        end
        b.SetMinMaxValues   = function(self, mn, mx) self._min = mn; self._max = mx end
        b.SetStatusBarColor = function() end
        b.SetStatusBarTexture = function() end
        b.SetOrientation    = function() end
        b.SetReverseFill    = function() end
        b.GetFrameLevel     = function(self) return self._level end
        b.SetFrameLevel     = function(self, l) self._level = l end
        b.ClearAllPoints    = function() end
        b.SetAllPoints      = function() end
        b.SetPoint          = function() end
        b.SetAlpha          = function() end
        b.Show              = function(self) self._shown = true end
        b.Hide              = function(self) self._shown = false end
        b.IsShown           = function(self) return self._shown end
        return b
    end

    local function makeFontStr()
        local f = {}
        f.SetText          = function() end
        f.SetFormattedText = function() end
        f.SetTextColor     = function() end
        f.SetFont          = function() end
        f.GetFont          = function() return "Fonts\\FRIZQT__.TTF", 10, "" end
        f.Show             = function() end
        f.Hide             = function() end
        f.IsShown          = function() return false end
        f.SetAlpha         = function() end
        return f
    end

    local function makeTex()
        local t = {}
        t.SetTexture      = function() end
        t.SetColorTexture = function() end
        t.SetVertexColor  = function() end
        t.SetAlpha        = function() end
        t.Show            = function() end
        t.Hide            = function() end
        t.IsShown         = function() return false end
        return t
    end

    local frame = {
        unit        = "raid1",
        _isRaid     = true,
        _shown      = false,
        _level      = 1,
        _w = 180, _h = 36,
    }
    -- Sub-regions that Update* functions read
    frame.healthBar         = makeBar("healthBar")
    frame.powerBar          = makeBar("powerBar")
    frame.absorbBar         = makeBar("absorbBar")
    frame.healAbsorbBar     = makeBar("healAbsorbBar")
    frame.healPredictionBar = makeBar("healPredictionBar")
    frame.healthText        = makeFontStr()
    frame.nameText          = makeFontStr()
    frame.statusText        = makeFontStr()
    frame.Center            = makeTex()   -- for SetBackdropFillColor
    -- Frame methods needed by Update* guard checks
    frame.SetAlpha          = function() end
    frame.GetAlpha          = function() return 1 end
    frame.SetBackdrop       = function() end
    frame.SetBackdropColor  = function() end
    frame.IsShown           = function() return true end
    frame.Show              = function(self) self._shown = true end
    frame.Hide              = function(self) self._shown = false end
    frame.GetFrameLevel     = function(self) return self._level end
    frame.SetFrameLevel     = function(self, l) self._level = l end
    frame.GetWidth          = function(self) return self._w end
    frame.GetHeight         = function(self) return self._h end
    return frame
end

-- -----------------------------------------------------------------------
-- EVENT_MAP for full scope:
-- Dispatches by calling captured OnEvent(eventFrame, event, unit, ...).
-- -----------------------------------------------------------------------
A.FULL_EVENT_MAP = {}

local function buildFullEventMap(onEvent, eventFrame)
    return {
        UNIT_HEALTH = function(_, a)
            onEvent(eventFrame, "UNIT_HEALTH", a[1] or "raid1")
        end,
        UNIT_MAXHEALTH = function(_, a)
            onEvent(eventFrame, "UNIT_MAXHEALTH", a[1] or "raid1")
        end,
        UNIT_POWER_UPDATE = function(_, a)
            onEvent(eventFrame, "UNIT_POWER_UPDATE", a[1] or "raid1", a[2])
        end,
        UNIT_POWER_FREQUENT = function(_, a)
            onEvent(eventFrame, "UNIT_POWER_FREQUENT", a[1] or "raid1", a[2])
        end,
        UNIT_MAXPOWER = function(_, a)
            onEvent(eventFrame, "UNIT_MAXPOWER", a[1] or "raid1")
        end,
        UNIT_ABSORB_AMOUNT_CHANGED = function(_, a)
            onEvent(eventFrame, "UNIT_ABSORB_AMOUNT_CHANGED", a[1] or "raid1")
        end,
        UNIT_HEAL_ABSORB_AMOUNT_CHANGED = function(_, a)
            onEvent(eventFrame, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", a[1] or "raid1")
        end,
        UNIT_HEAL_PREDICTION = function(_, a)
            onEvent(eventFrame, "UNIT_HEAL_PREDICTION", a[1] or "raid1")
        end,
        UNIT_NAME_UPDATE = function(_, a)
            onEvent(eventFrame, "UNIT_NAME_UPDATE", a[1] or "raid1")
        end,
        UNIT_THREAT_SITUATION_UPDATE = function(_, a)
            onEvent(eventFrame, "UNIT_THREAT_SITUATION_UPDATE", a[1] or "raid1")
        end,
        UNIT_CONNECTION = function(_, a)
            onEvent(eventFrame, "UNIT_CONNECTION", a[1] or "raid1")
        end,
        UNIT_FLAGS = function(_, a)
            onEvent(eventFrame, "UNIT_FLAGS", a[1] or "raid1")
        end,
    }
end

-- -----------------------------------------------------------------------
-- Full-scope Build: loads real groupframes.lua, captures OnEvent, wires
-- synthetic frame into unitFrameMap, returns a ctx for ProfileSessionFull.
-- -----------------------------------------------------------------------
local function buildFullScope(opts)
    local ns, _capturedHandlers, mainHandler =
        loadFullGroupFrames(opts)

    local QUI_GF = ns.QUI_GroupFrames

    -- Build synthetic unit frame and inject into unitFrameMap
    local syntheticFrame = buildFullSyntheticFrame(opts)
    QUI_GF.unitFrameMap["raid1"] = { syntheticFrame }

    local onEvent    = mainHandler.fn
    local eventFrame = mainHandler.frame

    A.FULL_EVENT_MAP = buildFullEventMap(onEvent, eventFrame)

    local ctx = {
        QUI_GF       = QUI_GF,
        onEvent      = onEvent,
        eventFrame   = eventFrame,
        frame        = syntheticFrame,
        ns           = ns,
        stats        = {},
    }

    return { ctx = ctx }
end

--- A.Build(opts) -> { ctx }
-- opts.scope = "aura" (default) or "full"
-- opts.onCallback(name) instrumentation hook (optional).
--
-- "aura" scope: loads aura sub-modules (existing behavior, unchanged).
-- "full" scope: loads real groupframes.lua, captures OnEvent, wires
--   synthetic unit frame. ctx carries QUI_GF, onEvent, eventFrame, frame.
function A.Build(opts)
    local scope = opts and opts.scope or "aura"
    if scope == "full" then
        return buildFullScope(opts)
    end

    -- === EXISTING aura-scope behavior (unchanged) ===
    local wrap = stubWoWGlobals(opts)

    local ns    = loadSubModules()
    local Model = ns.QUI_GroupFramesAuraModel
    local R     = ns.QUI_GroupFrameAuraRender

    -- Instrument render methods so onCallback fires when they run
    instrumentRender(R, wrap)

    local frame     = buildSyntheticFrame(ns)
    local auraCache = buildAuraCache()
    local elements  = buildElements(Model)

    local ctx = {
        R          = R,
        Model      = Model,
        frame      = frame,
        auraCache  = auraCache,
        elements   = elements,
        specID     = nil,   -- nil -> inherit "*" bucket
        scratch    = {},
        stats      = {},
    }

    -- Populate the shared EVENT_MAP after first Build()
    A.EVENT_MAP = buildEventMap()

    return { ctx = ctx }
end

--- A.dispatchFull(ctx, event) -> applies one event via FULL_EVENT_MAP
function A.dispatchFull(ctx, event)
    local fn = A.FULL_EVENT_MAP[event.e]
    if fn then
        fn(ctx, event.a or {})
    end
end

--- A.ProfileSessionFull(ctx, events)
--   -> churn (table), counts (table), report (string), total (P.measure result)
-- Profiles per-event-type allocation churn for the full-scope adapter.
function A.ProfileSessionFull(ctx, events)
    local P = assert(loadfile("tests/replay/profile_replay.lua"))()

    local unmappedCount = 0

    local churn, counts = P.profilePerKey(
        events,
        function(ev) return ev.e end,
        function(ev)
            local fn = A.FULL_EVENT_MAP[ev.e]
            if fn then
                fn(ctx, ev.a or {})
            else
                unmappedCount = unmappedCount + 1
            end
        end)

    A._lastFullUnmappedCount = unmappedCount

    local rep = P.report(churn, counts)
    local total = P.measure(function()
        for i = 1, #events do
            local ev = events[i]
            local fn = A.FULL_EVENT_MAP[ev.e]
            if fn then fn(ctx, ev.a or {}) end
        end
    end)

    return churn, counts, rep, total
end

return A
