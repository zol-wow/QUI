-- tests/unit/cdm_reanchor_realenv_test.lua
-- Run: lua tests/unit/cdm_reanchor_realenv_test.lua
local ns = {}
-- Task 45f: cdm_reanchor_realenv.lua routes discarded-result pcall guards
-- through ns.SafeCall. Additive stub (T1d/T1e precedent).
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_realenv.lua", "cdm_reanchor_realenv.lua")("QUI", ns)
local RE = assert(ns.CDMReanchorRealEnv, "CDMReanchorRealEnv should be exported")
assert(type(RE.BuildEnv) == "function", "BuildEnv is a function")

local placed, clickOverlayCall, releasedIcon, capturedClickable
local factoryStub = {
    AcquireIcon = function(_, c, e, clickable) capturedClickable = clickable; return { c, e } end,
    ReleaseIcon = function(_, icon) releasedIcon = icon end,
    _pools = {},
    EnsurePool = function(self, key)
        self._pools[key] = self._pools[key] or {}
        return self._pools[key]
    end,
    GetIconPool = function(self, key) return self._pools[key] or {} end,
}
-- getSettings backs the acquireIcon closure's clickable computation (EDIT 1):
-- a clickableIcons=true container's key -> clickable true, false/absent -> false.
local settingsByKey = {
    clickyContainer = { clickableIcons = true },
    plainContainer = { clickableIcons = false },
}
local getSettingsStub = function(key) return settingsByKey[key] end
local env = RE.BuildEnv({
    CDMContainers = { GetContainer = function(k) return "C:" .. k end },
    CDMSpellData = { BuildSpellListFromOwned = function(_, k) return { "S:" .. k } end },
    CDMIndex = "IDX",
    CDMLayout = { BuildIconLayout = "BL" },
    CDMIcons = {
        OnContainerIconPlaced = function(i, rc) placed = { i, rc } end,
        UpdateSecureClickOverlay = function(shell, entry, viewerType)
            clickOverlayCall = { shell = shell, entry = entry, viewerType = viewerType }
        end,
    },
    CDMIconFactory = factoryStub,
    core = { PixelRound = function(_, v) return v + 1 end },
    uiParent = "UIP",
    getSettings = getSettingsStub,
    resolveAdditional = "RA",
    onMetrics = "OM",
})

assert(env.getContainer("essential") == "C:essential", "getContainer -> CDMContainers.GetContainer")
assert(env.getCurated("buff")[1] == "S:buff", "getCurated -> SpellData:BuildSpellListFromOwned")
assert(env.index == "IDX", "index wired")
assert(env.buildLayout == "BL", "buildLayout -> CDMLayout.BuildIconLayout")
assert(env.uiParent == "UIP", "uiParent wired")
assert(env.getSettings == getSettingsStub and env.resolveAdditional == "RA" and env.onMetrics == "OM", "ctx internals passed through")
assert(env.pixelRound(5) == 6, "pixelRound -> core:PixelRound")
local ai = env.acquireIcon("CC", "EE")
assert(ai[1] == "CC" and ai[2] == "EE", "acquireIcon bound closure -> Factory:AcquireIcon(c,e)")
assert(type(env.releaseIcon) == "function", "releaseIcon exposed on the env")
env.releaseIcon("ICON")
assert(releasedIcon == "ICON", "releaseIcon bound closure -> Factory:ReleaseIcon(icon)")

-- Clickable wiring: acquireIcon computes `clickable` from the destination
-- container's settings (ctx.getSettings) and forwards it as AcquireIcon's
-- 3rd arg -- this is what lets AcquireIcon reuse a protected (clickButton)
-- icon from its dedicated pool instead of minting a fresh one every refresh.
do
    env.acquireIcon("CC", "EE", "clickyContainer")
    assert(capturedClickable == true,
        "acquireIcon computes clickable=true from a clickableIcons=true container")

    env.acquireIcon("CC", "EE", "plainContainer")
    assert(capturedClickable == false,
        "acquireIcon computes clickable=false from a clickableIcons=false container")

    env.acquireIcon("CC", "EE", nil)
    assert(capturedClickable == false,
        "acquireIcon computes clickable=false with no containerKey (no settings lookup)")
end

-- Runtime edit expansion is for QUI/CDM layout mode only. Blizzard Edit Mode
-- must stay untouched: opening it should not make the reanchor runtime show CDM
-- placeholders or expand hidden buff entries.
do
    local oldHelpers = ns.Helpers
    local oldCDMEdit = _G.QUI_IsCDMEditModeActive
    local blizzardEdit, layoutMode, cdmEdit = false, false, false
    ns.Helpers = {
        IsEditModeActive = function() return blizzardEdit end,
        IsLayoutModeActive = function() return layoutMode end,
    }
    _G.QUI_IsCDMEditModeActive = function() return cdmEdit end

    local editEnv = RE.BuildEnv({})
    blizzardEdit = true
    assert(editEnv.isEditMode() == false,
        "Blizzard Edit Mode alone must not activate CDM reanchor edit expansion")
    blizzardEdit = false
    layoutMode = true
    assert(editEnv.isEditMode() == true,
        "QUI layout mode activates CDM reanchor edit expansion")
    layoutMode = false
    cdmEdit = true
    assert(editEnv.isEditMode() == true,
        "CDM edit overlay mode activates CDM reanchor edit expansion")

    ns.Helpers = oldHelpers
    _G.QUI_IsCDMEditModeActive = oldCDMEdit
end

-- POOL MEMBERSHIP: everything that drives owned-icon CONTENT (stack text,
-- aura wakes, cooldown refresh in cdm_icon_runtime_refresh; glow/desat in
-- cdm_effects) walks Factory:GetIconPool(viewerType). Legacy BuildIcons was
-- the only pool writer, so engine-minted fallback icons rendered as static
-- textures: no stacks, no expired-state repaint. A KEYED acquire must register
-- the icon under its container key; a keyed release must remove it. Un-keyed
-- calls (legacy shape, pinned above) must not touch pools.
do
    local pooled = env.acquireIcon("CC", "EE", "buff")
    local pool = factoryStub._pools.buff
    assert(type(pool) == "table" and #pool == 1 and pool[1] == pooled,
        "keyed acquireIcon registers the icon in Factory pool[key]")
    env.releaseIcon(pooled, "buff")
    assert(#pool == 0, "keyed releaseIcon removes the icon from Factory pool[key]")
    assert(releasedIcon == pooled, "keyed releaseIcon still recycles via Factory:ReleaseIcon")
end
env.onIconPlaced("ic", "rc")
assert(placed[1] == "ic" and placed[2] == "rc", "onIconPlaced -> CDMIcons.OnContainerIconPlaced(icon,rowConfig)")
env.updateClickOverlay("shell", "entry", "essential")
assert(clickOverlayCall.shell == "shell" and clickOverlayCall.entry == "entry"
    and clickOverlayCall.viewerType == "essential",
    "updateClickOverlay -> CDMIcons.UpdateSecureClickOverlay(shell,entry,viewerType)")

do
    -- IsActive is authoritative for BuffIcon frames: it reads Blizzard's plain
    -- isActive field, and CooldownViewerBuffItemMixin:ShouldBeActive already
    -- covers totems (totemData not expired -> active) and infinite auras
    -- (expirationTime == 0 -> active). A readable FALSE must clear frames that
    -- Blizzard keeps natively SHOWN after the aura ends (Hide-When-Inactive off,
    -- CooldownViewerSettings visible) -- the old IsShown-first fast-path
    -- classified those expired frames active forever, so they never uncleared.
    local shownExpired = {
        IsActive = function() return false end,
        IsShown = function() return true end,
    }
    assert(env.frameIsActive(shownExpired, "buff") == false,
        "shown BuffIcon frame with readable IsActive()==false is NOT active (expired buffs must clear)")

    local shownActive = {
        IsActive = function() return true end,
        IsShown = function() return true end,
    }
    assert(env.frameIsActive(shownActive, "buff") == true,
        "readable IsActive()==true is active")

    local hiddenActive = {
        IsActive = function() return true end,
        IsShown = function() return false end,
    }
    assert(env.frameIsActive(hiddenActive, "buff") == true,
        "IsActive is authoritative even when the frame is natively hidden")

    -- IsActive unreadable (throws / combat-secret): fall back to the native
    -- shown state; only a readable natively-hidden frame counts inactive.
    local unreadableShown = {
        IsActive = function() error("secret") end,
        IsShown = function() return true end,
    }
    assert(env.frameIsActive(unreadableShown, "buff") == true,
        "unreadable IsActive + natively shown -> fail open (never hide a possibly-active frame)")

    local unreadableHidden = {
        IsActive = function() error("secret") end,
        IsShown = function() return false end,
    }
    assert(env.frameIsActive(unreadableHidden, "buff") == false,
        "unreadable IsActive + natively hidden -> inactive")

    local noSignals = {}
    assert(env.frameIsActive(noSignals, "buff") == true,
        "no readable signal at all -> fail open")
end

-- Aura truth remains available for non-Blizzard/custom owned fallbacks, but
-- Blizzard-CDM BuffIcon entries are native-only. frameIsActive itself stays a
-- pure native-usability predicate (IsActive first, IsShown fallback): a stale
-- hidden native frame must not be claimed just because an aura query sees the
-- aura.
do
    local oldSources = ns.CDMSources
    local presentIDs = {}
    local oldSpellData = ns.CDMSpellData
    ns.CDMSpellData = {
        GetCapturedAuraForLookup = function(ids)
            for _, id in ipairs(ids) do
                if presentIDs[id] then return { auraInstanceID = 1, unit = "player" } end
            end
        end,
    }
    local auraEnv = RE.BuildEnv({ CDMSpellData = ns.CDMSpellData })
    ns.CDMSources = oldSources
    ns.CDMSpellData = oldSpellData

    assert(type(auraEnv.entryAuraIsPresent) == "function",
        "entryAuraIsPresent exposed on the env for custom owned fallbacks")

    local entry = { spellID = 101 }
    presentIDs[101] = true
    assert(auraEnv.entryAuraIsPresent(entry) == false,
        "uncaptured player aura must not use a spell getter")
    presentIDs[101] = nil
    assert(auraEnv.entryAuraIsPresent(entry) == false, "absent aura -> false")

    -- override/linked variants are checked too (aura may live under a variant id)
    presentIDs[202] = true
    assert(auraEnv.entryAuraIsPresent({ spellID = 101, overrideSpellID = 202 }) == true,
        "captured override aura should use the captured lookup")
    presentIDs[202] = nil
    presentIDs[303] = true
    assert(auraEnv.entryAuraIsPresent({ spellID = 101, linkedSpellIDs = { 303 } }) == true,
        "captured linked aura should use the captured lookup")
    presentIDs[303] = nil

    -- frameIsActive is PURE native usability: a stale hidden frame with a live
    -- aura is still NOT usable.
    local staleHidden = {
        IsActive = function() return false end,
        IsShown = function() return false end,
    }
    presentIDs[101] = true
    assert(auraEnv.frameIsActive(staleHidden, "buff", entry) == false,
        "live aura must NOT make a stale hidden native frame claimable")
    presentIDs[101] = nil
end

do
    local oldCreateFrame = _G.CreateFrame
    local inCombat = false
    local createdFrames = {}
    local function makeRegion()
        return {
            ClearAllPoints = function(self) self.clearCount = (self.clearCount or 0) + 1 end,
            SetPoint = function(self) self.pointCount = (self.pointCount or 0) + 1 end,
            SetColorTexture = function(self) self.colorCount = (self.colorCount or 0) + 1 end,
            Show = function(self) self.shown = true; self.showCount = (self.showCount or 0) + 1 end,
            Hide = function(self) self.shown = false; self.hideCount = (self.hideCount or 0) + 1 end,
        }
    end
    _G.CreateFrame = function(_frameType, _name, parent)
        local frame = {
            parent = parent,
            shown = false,
            scripts = {},
            CreateTexture = function() return makeRegion() end,
            ClearAllPoints = function(self) self.clearCount = (self.clearCount or 0) + 1 end,
            SetPoint = function(self) self.pointCount = (self.pointCount or 0) + 1 end,
            SetSize = function(self, w, h) self.size = { w, h } end,
            Show = function(self) self.shown = true; self.showCount = (self.showCount or 0) + 1 end,
            Hide = function(self) self.shown = false; self.hideCount = (self.hideCount or 0) + 1 end,
            IsShown = function(self) return self.shown end,
            EnableMouse = function(self, enabled) self.mouseEnabled = enabled end,
            SetMouseClickEnabled = function(self, enabled) self.mouseClickEnabled = enabled end,
            SetMouseMotionEnabled = function(self, enabled) self.mouseMotionEnabled = enabled end,
            SetScript = function(self, name, fn) self.scripts[name] = fn end,
            GetScript = function(self, name) return self.scripts[name] end,
            SetAllPoints = function(self, relativeTo) self.allPoints = relativeTo end,
            SetFrameStrata = function(self, strata) self.strata = strata end,
            GetFrameStrata = function() return "MEDIUM" end,
            SetFrameLevel = function(self, level) self.level = level end,
            GetFrameLevel = function() return 10 end,
        }
        createdFrames[#createdFrames + 1] = frame
        return frame
    end

    local container = { CreateTexture = function() end }
    local shellEnv = RE.BuildEnv({
        CDMContainers = { GetContainer = function() return container end },
        isInCombat = function() return inCombat end,
    })
    local live = {}

    shellEnv.beginShellPass(container)
    local first = shellEnv.positionClickSlot(container, live, { spellID = 1 }, "essential", 0, 0, 40, 40)
    local second = shellEnv.positionClickSlot(container, live, { spellID = 2 }, "essential", 0, 0, 40, 40)
    shellEnv.endShellPass(container)
    assert(first and second and first ~= second, "initial shell pass mints two click slots")
    assert((first.hideCount or 0) == 0 and (second.hideCount or 0) == 0,
        "active slots are not hidden at the end of their generation")

    inCombat = true
    shellEnv.beginShellPass(container)
    local clearCountBeforeCombatPosition = first.clearCount or 0
    local positionedInCombat = shellEnv.positionClickSlot(container, live, { spellID = 3 }, "essential", 1, 2, 40, 40)
    shellEnv.endShellPass(container)
    assert(first._spellEntry and first._spellEntry.spellID == 3,
        "next generation reuses the first slot by index")
    assert(positionedInCombat == nil and (first.clearCount or 0) == clearCountBeforeCombatPosition,
        "combat shell pass reuses existing slots without protected layout writes")
    assert((second.hideCount or 0) == 0,
        "stale surplus slot cleanup is deferred while combat is active")

    inCombat = false
    shellEnv.beginShellPass(container)
    local reusedAgain = shellEnv.positionClickSlot(container, live, { spellID = 4 }, "essential", 0, 0, 40, 40)
    shellEnv.endShellPass(container)
    assert(reusedAgain == first, "out-of-combat generation keeps reusing the active slot")
    assert((second.hideCount or 0) == 1,
        "stale surplus slot is hidden once cleanup runs out of combat")

    _G.CreateFrame = oldCreateFrame
end

-- Task 2: applyChrome rides a BORDER-ONLY child ON the live icon (icon-relative
-- z-order -- the prerequisite for dropping the live-frame strata/level lift in
-- Task 3) and NEVER writes strata/level/ignore-alpha onto the live frame.
do
    local created, calls = {}, {}
    local function recordingRegion()
        -- Every region method is a no-op (the border tex: SetColorTexture/SetPoint/Show...).
        return setmetatable({}, { __index = function() return function() end end })
    end
    -- Sub-objects applyChrome probes (Cooldown swipe / charge / count): nil here so only
    -- the border path runs. Every OTHER method access is recorded into `calls` so a
    -- regression that writes strata/level/ignore-alpha on the live frame is caught.
    local SUBOBJECT = { Cooldown = true, ChargeCount = true, Applications = true, Icon = true }
    local icon = {
        CreateTexture = function(_, ...) created[#created + 1] = { ... }; return recordingRegion() end,
    }
    setmetatable(icon, { __index = function(_, k)
        if SUBOBJECT[k] then return nil end
        return function(_, ...) calls[#calls + 1] = { k, ... } end
    end })

    local chromeEnv = RE.BuildEnv({})
    assert(type(chromeEnv.applyChrome) == "function", "applyChrome exposed on the env for direct test")

    chromeEnv.applyChrome(icon, { borderSize = 2 })
    assert(#created >= 1, "applyChrome creates >=1 own child texture (border) on the live icon")
    local sawAlpha1 = false
    for _, c in ipairs(calls) do
        assert(c[1] ~= "SetFrameStrata", "applyChrome never SetFrameStrata on the live frame")
        assert(c[1] ~= "SetFrameLevel", "applyChrome never SetFrameLevel on the live frame")
        assert(c[1] ~= "SetIgnoreParentAlpha", "applyChrome never SetIgnoreParentAlpha on the live frame")
        if c[1] == "SetAlpha" and c[2] == 1 then sawAlpha1 = true end
    end
    assert(sawAlpha1,
        "applyChrome re-asserts claimed visibility via SetAlpha(1) -- a re-claimed frame "
        .. "may have been alpha-0'd by Sink/guard; park is retired so there is no viewer catch-all")

    local afterFirst = #created
    chromeEnv.applyChrome(icon, { borderSize = 2 })
    assert(#created == afterFirst, "applyChrome is idempotent: reuses the border child, no second CreateTexture")
end

-- Row opacity: applyChrome is the alpha authority for reanchored live icons.
-- OverlayRect re-asserts alpha 1 on every claim, so rowConfig.opacity must be
-- applied here per pass or the Row Opacity setting is silently ignored.
do
    local alphas = {}
    local SUBOBJECT = { Cooldown = true, ChargeCount = true, Applications = true, Icon = true }
    local icon = {
        CreateTexture = function()
            return setmetatable({}, { __index = function() return function() end end })
        end,
        SetAlpha = function(_, a) alphas[#alphas + 1] = a end,
    }
    setmetatable(icon, { __index = function(_, k)
        if SUBOBJECT[k] then return nil end
        return function() end
    end })

    local envO = RE.BuildEnv({})
    envO.applyChrome(icon, { opacity = 0.4 })
    assert(alphas[#alphas] == 0.4, "applyChrome applies rowConfig.opacity to the live frame")
    envO.applyChrome(icon, { opacity = 0 })
    assert(alphas[#alphas] == 0, "opacity 0 yields a fully transparent live frame, not a reset to 1")
    envO.applyChrome(icon, {})
    assert(alphas[#alphas] == 1.0, "missing opacity defaults to fully opaque")
end

-- Reference-parity PER-PASS writes on claimed frames (re-anchor reference
-- re-asserts these every collect pass):
-- Applications/ChargeCount frame-level raise: both are child FRAMES
-- (CooldownViewer.xml:54/:189), Blizzard resets pooled frame levels on zone
-- transitions, so the native stack/charge text must be re-raised above the
-- swirl every pass. Writes are on CHILD frames -- the live item frame keeps
-- its zero-forbidden-writes pin (no SetFrameLevel on the item itself).
do
    local cdCalls, appLevels, chargeLevels = {}, {}, {}
    local live = {
        Cooldown = setmetatable({}, { __index = function(_, k)
            return function(_, ...) cdCalls[#cdCalls + 1] = { k, ... } end
        end }),
        Applications = { SetFrameLevel = function(_, v) appLevels[#appLevels + 1] = v end },
        ChargeCount = { SetFrameLevel = function(_, v) chargeLevels[#chargeLevels + 1] = v end },
        GetFrameLevel = function() return 10 end,
        SetAlpha = function() end,
        CreateTexture = function()
            return setmetatable({}, { __index = function() return function() end end })
        end,
    }
    local envC = RE.BuildEnv({})
    local function countCalls(name, val)
        local n = 0
        for _, c in ipairs(cdCalls) do
            if c[1] == name and (val == nil or c[2] == val) then n = n + 1 end
        end
        return n
    end
    envC.applyChrome(live, { borderSize = 1 }, false) -- NON-first pass: per-pass writes only
    assert(appLevels[1] == 33 and chargeLevels[1] == 33,
        "claimed pass raises native stack/charge text child frames above the swirl (live level + 23)")
    envC.applyChrome(live, { borderSize = 1 }, false)
    assert(countCalls("SetDrawSwipe") == 0,
        "applyChrome must NEVER write SetDrawSwipe -- Blizzard owns that channel per event; "
        .. "a per-pass force-true alternates with Blizzard's charge edge-only false and flickers")
    assert(#appLevels == 2 and #chargeLevels == 2,
        "text raise runs every pass (Blizzard resets pooled frame levels on zone transitions)")
    -- Full reference parity: the native Cooldown widget writes also re-assert
    -- EVERY pass (Blizzard re-asserts its own values on refresh; a once-only
    -- write drifts back). The once-on-first-claim gating was based on a wrong
    -- taint theory -- the reference re-applies these per collect pass and is
    -- taint-clean in-game.
    assert(countCalls("SetSwipeTexture") == 2,
        "swipe texture re-asserts every claimed pass")
    for _, call in ipairs(cdCalls) do
        if call[1] == "SetSwipeTexture" then
            assert(call[3] == nil, "swipe texture styling must not overwrite native swipe color")
        end
    end
    assert(countCalls("SetDrawBling", false) == 2,
        "bling-off re-asserts every claimed pass")
    assert(countCalls("SetHideCountdownNumbers") == 2,
        "hide-countdown-numbers re-asserts every claimed pass")
end

-- resilient defaults: missing modules -> safe nils, resolveAdditional default empty
local env2 = RE.BuildEnv({})
assert(env2.getContainer("x") == nil, "no container module -> nil")
assert(type(env2.resolveAdditional) == "function" and #env2.resolveAdditional("x") == 0, "default resolveAdditional -> empty")
assert(env2.pixelRound(7) == 7, "no core -> identity pixelRound")

-- Task 3: _DecorateWork and _BarDecorateWork must make ZERO SetFrameStrata/
-- SetFrameLevel/SetIgnoreParentAlpha writes on the live Blizzard CDM frame.
-- Both functions are exposed as seams on CDMReanchorRealEnv for direct testing.
do
    assert(type(RE._DecorateWork) == "function",
        "Task 3 seam: _DecorateWork must be exported on CDMReanchorRealEnv")
    assert(type(RE._BarDecorateWork) == "function",
        "Task 3 seam: _BarDecorateWork must be exported on CDMReanchorRealEnv")

    local FORBIDDEN = { SetFrameStrata = true, SetFrameLevel = true, SetIgnoreParentAlpha = true }

    -- Self-referencing deep noop: indexing returns itself, calling is a noop.
    -- Used for sub-objects (Bar, Bg, BarIcon) so chained property access
    -- (e.g. bar.BarBG.SetAlpha) and colon calls don't crash.
    local deepNoop
    deepNoop = setmetatable({}, {
        __index = function() return deepNoop end,
        __call  = function() end,
    })

    -- Icon path: _DecorateWork(decorator, live, shell, rowConfig) --
    local iconCalls = {}
    local liveIcon = setmetatable({}, {
        __index = function(_, k)
            iconCalls[#iconCalls + 1] = { method = k }
            return function() end
        end,
    })
    local shellIcon = {
        Border         = { Hide = function() end },
        GetFrameStrata = function() return "MEDIUM" end,
        GetFrameLevel  = function() return 10 end,
    }
    local stubDecorator = { Decorate = function() end }
    RE._DecorateWork(stubDecorator, liveIcon, shellIcon, {})
    for _, c in ipairs(iconCalls) do
        assert(not FORBIDDEN[c.method],
            "_DecorateWork must not call live:" .. c.method .. " on the live frame")
    end

    -- Bar path: _BarDecorateWork(live, shell, settings) --
    -- live.Bar is a raw field (deepNoop) so _BarReskinWork sub-navigation works.
    -- Icon/DebuffBorder are false (falsy) so nil-guards in _BarReskinWork skip them.
    -- All other live field accesses (SetIgnoreParentAlpha, SetFrameStrata, etc.)
    -- go through __index and are recorded in barCalls.
    local barCalls = {}
    local liveBar = setmetatable(
        { Bar = deepNoop, Icon = false, DebuffBorder = false },
        {
            __index = function(_, k)
                barCalls[#barCalls + 1] = { method = k }
                return function() end
            end,
        }
    )
    -- _spellEntry = false (falsy) so _ResolveBarIconTexture skips the spellID
    -- path cleanly (a function value returned by __index would crash on .spellID).
    local shellBar = setmetatable(
        { Bg = deepNoop, BarIcon = deepNoop, Border = deepNoop,
          _spellEntry    = false,
          GetFrameStrata = function() return "MEDIUM" end,
          GetFrameLevel  = function() return 10 end },
        { __index = function() return function() end end }
    )
    RE._BarDecorateWork(liveBar, shellBar, {})
    local sawBarAlpha = false
    for _, c in ipairs(barCalls) do
        assert(not FORBIDDEN[c.method],
            "_BarDecorateWork must not call live:" .. c.method .. " on the live frame")
        if c.method == "SetAlpha" then sawBarAlpha = true end
    end
    assert(sawBarAlpha,
        "_BarDecorateWork re-asserts claimed bar visibility via SetAlpha(1) (park retired, no viewer catch-all)")

    print("OK: _DecorateWork/_BarDecorateWork zero forbidden live-frame writes + claimed SetAlpha(1)")
end

-- Task 5: applyChrome uses SetCountdownFont (AllowedWhenUntainted) and makes
-- NO raw SetFont on any native secret-tracked fontstring (countdown or count).
do
    -- Task A-G4: CreateFont must be available so _EnsureCountFont can create the
    -- per-(size,outline) font object and return its name for SetCountdownFont.
    local oldCreateFont5 = _G.CreateFont
    _G.CreateFont = function(name)
        local fo = setmetatable(
            { SetFont = function() end, SetTextColor = function() end },
            { __index = function() return function() end end }
        )
        _G[name] = fo
        return fo
    end

    local cdCountdownFontCalls = {}   -- cd:SetCountdownFont(name) calls
    local cdSetFontCalls = {}         -- cd:SetFont(...) calls (forbidden)
    local nativeFsSetFontCalls = {}   -- fontstring returned by GetCountdownFontString: SetFont (forbidden)
    local chargeCurrentCalls = {}     -- ChargeCount.Current:SetFont (forbidden)
    local appApplicationsCalls = {}   -- Applications.Applications:SetFont (forbidden)

    -- Mock native countdown fontstring (returned by GetCountdownFontString)
    local fakeCountdownFs = setmetatable({}, {
        __index = function(_, k)
            return function(_, ...)
                nativeFsSetFontCalls[#nativeFsSetFontCalls + 1] = { k, ... }
            end
        end,
    })

    -- Mock Cooldown sub-object
    local fakeCd = {
        SetSwipeTexture  = function() end,
        SetDrawBling     = function() end,
        GetCountdownFontString = function() return fakeCountdownFs end,
    }
    setmetatable(fakeCd, {
        __index = function(_, k)
            return function(_, ...)
                if k == "SetCountdownFont" then
                    cdCountdownFontCalls[#cdCountdownFontCalls + 1] = { ... }
                elseif k == "SetFont" then
                    cdSetFontCalls[#cdSetFontCalls + 1] = { ... }
                end
            end
        end,
    })

    -- Mock ChargeCount.Current (must NOT receive SetFont)
    local fakeChargeCurrent = setmetatable({}, {
        __index = function(_, k)
            return function(_, ...) chargeCurrentCalls[#chargeCurrentCalls + 1] = { k, ... } end
        end,
    })

    -- Mock Applications.Applications (must NOT receive SetFont)
    local fakeAppApps = setmetatable({}, {
        __index = function(_, k)
            return function(_, ...) appApplicationsCalls[#appApplicationsCalls + 1] = { k, ... } end
        end,
    })

    local frame5 = {
        Cooldown      = fakeCd,
        ChargeCount   = { Current = fakeChargeCurrent },
        Applications  = { Applications = fakeAppApps },
        CreateTexture = function()
            return setmetatable({}, { __index = function() return function() end end })
        end,
    }

    -- Provide Helpers (including ApplyFontWithFallback) so old raw-font path fires
    -- in the RED state; the new path must replace it with SetCountdownFont.
    local oldHelpers = ns.Helpers
    ns.Helpers = {
        GetGeneralFont       = function() return "Interface\\Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        GetSkinBorderColor   = function() return 0, 0, 0, 1 end,
        ApplyFontWithFallback = function(fs, _font, _sz, _outline)
            -- Proxy raw SetFont onto the fontstring so the test can detect it
            if fs and fs.SetFont then fs:SetFont(_font, _sz, _outline) end
        end,
    }
    local task5Env = RE.BuildEnv({})
    ns.Helpers = oldHelpers

    task5Env.applyChrome(frame5, { durationSize = 14, borderSize = 0 })

    -- 1. SetCountdownFont MUST be called with a QUI font-object name.
    -- After G4 the name is per-(size,outline) e.g. "QUI_CDM_CountFont_14_OUTLINE";
    -- assert the prefix rather than the old constant.
    assert(#cdCountdownFontCalls >= 1,
        "Task 5: applyChrome must call cd:SetCountdownFont")
    local t5name = cdCountdownFontCalls[1] and cdCountdownFontCalls[1][1]
    assert(type(t5name) == "string" and t5name:find("^QUI_CDM_CountFont") ~= nil,
        "Task 5: SetCountdownFont must be called with a name starting with 'QUI_CDM_CountFont', got: "
        .. tostring(t5name))

    -- 2. No raw SetFont on the native countdown fontstring
    local sawSetFont = false
    for _, c in ipairs(nativeFsSetFontCalls) do
        if c[1] == "SetFont" then sawSetFont = true; break end
    end
    assert(not sawSetFont,
        "Task 5: applyChrome must NOT call SetFont on the native countdown fontstring (GetCountdownFontString)")

    -- 3. No direct SetFont on the Cooldown frame itself
    assert(#cdSetFontCalls == 0,
        "Task 5: applyChrome must NOT call SetFont directly on the Cooldown frame")

    -- 4. ChargeCount.Current must not receive any font call
    local sawChargeSetFont = false
    for _, c in ipairs(chargeCurrentCalls) do
        if c[1] == "SetFont" then sawChargeSetFont = true; break end
    end
    assert(not sawChargeSetFont,
        "Task 5: applyChrome must NOT call SetFont on ChargeCount.Current")

    -- 5. Applications.Applications must not receive any font call
    local sawAppSetFont = false
    for _, c in ipairs(appApplicationsCalls) do
        if c[1] == "SetFont" then sawAppSetFont = true; break end
    end
    assert(not sawAppSetFont,
        "Task 5: applyChrome must NOT call SetFont on Applications.Applications")

    print("OK: Task 5 — applyChrome uses SetCountdownFont, zero raw SetFont on native frames")
    _G.CreateFont = oldCreateFont5
end

-- Task 6: _BarReskinWork must NOT call SetFont/ApplyFontWithFallback on
-- bar.Name or bar.Duration (native Blizzard secret-tracked fontstrings).
-- SetStatusBarColor and SetStatusBarTexture must still fire (reskin preserved).
do
    assert(type(RE._BarReskinWork) == "function",
        "Task 6 seam: _BarReskinWork must be exported on CDMReanchorRealEnv")

    local nameFontCalls, durationFontCalls = {}, {}
    local statusBarColorCalled, statusBarTextureCalled = false, false

    local barName = setmetatable({}, {
        __index = function(_, k)
            return function(_, ...) nameFontCalls[#nameFontCalls + 1] = { k, ... } end
        end,
    })
    local barDuration = setmetatable({}, {
        __index = function(_, k)
            return function(_, ...) durationFontCalls[#durationFontCalls + 1] = { k, ... } end
        end,
    })
    local mockBar = {
        Name     = barName,
        Duration = barDuration,
        BarBG    = { Hide = function() end, SetAlpha = function() end },
        Pip      = { Hide = function() end, SetAlpha = function() end },
        ClearAllPoints       = function() end,
        SetPoint             = function() end,
        SetStatusBarColor    = function() statusBarColorCalled = true end,
        SetStatusBarTexture  = function() statusBarTextureCalled = true end,
    }
    local mockLive = {
        Bar          = mockBar,
        Icon         = { Hide = function() end },
        DebuffBorder = { Hide = function() end },
    }

    -- Inject Helpers with ApplyFontWithFallback so the old raw-font path would
    -- fire in the RED state if the block is still present.
    local oldHelpers = ns.Helpers
    ns.Helpers = {
        GetGeneralFont        = function() return "Interface\\Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        ApplyFontWithFallback = function(fs, font, sz, outline)
            if fs and fs.SetFont then fs:SetFont(font, sz, outline) end
        end,
        -- Provide LSM stub so SetStatusBarTexture branch is exercised
    }
    -- Provide LSM stub on ns so the texture path fires
    local oldLSM = ns.LSM
    ns.LSM = { Fetch = function() return "FakeTex" end }

    RE._BarReskinWork(mockLive, {})

    ns.Helpers = oldHelpers
    ns.LSM = oldLSM

    -- bar.Name and bar.Duration must have received NO calls at all (the block
    -- referencing them is deleted, so neither the metatables nor SetFont fire).
    local function hasSetFont(calls, label)
        for _, c in ipairs(calls) do
            if c[1] == "SetFont" then
                return true, label .. " received SetFont — raw font block not deleted"
            end
        end
        return false
    end
    local bad, msg = hasSetFont(nameFontCalls, "bar.Name")
    assert(not bad, "Task 6: " .. (msg or ""))
    bad, msg = hasSetFont(durationFontCalls, "bar.Duration")
    assert(not bad, "Task 6: " .. (msg or ""))
    assert(#nameFontCalls == 0,
        "Task 6: bar.Name must receive zero method calls (not indexed at all)")
    assert(#durationFontCalls == 0,
        "Task 6: bar.Duration must receive zero method calls (not indexed at all)")

    -- Reskin (color + texture) must still fire.
    assert(statusBarColorCalled,
        "Task 6: SetStatusBarColor must still be called by _BarReskinWork")
    assert(statusBarTextureCalled,
        "Task 6: SetStatusBarTexture must still be called by _BarReskinWork")

    print("OK: Task 6 — _BarReskinWork zero raw SetFont on native bar.Name/bar.Duration; reskin intact")
end

-- Task A: G2 (SetHideCountdownNumbers), G3 (duration text colour),
-- G4 (per-(size,outline) font-object cache; distinct names, no collapse).
-- Field names verified against the owned-icon path:
--   hideDurationText   — cdm_icon_renderer.lua:2440
--   durationTextColor  — cdm_icon_renderer.lua:2442  default {1,1,1,1}
do
    local oldCreateFontA = _G.CreateFont
    local fontObjects = {}
    _G.CreateFont = function(name)
        local fo = {
            _lastFont  = nil,
            _lastColor = nil,
            SetFont      = function(self, f, s, o) self._lastFont  = {f, s, o} end,
            SetTextColor = function(self, r, g, b, a) self._lastColor = {r, g, b, a} end,
        }
        fontObjects[name] = fo
        _G[name] = fo
        return fo
    end

    local function makeCd(hideLog, fontLog)
        return {
            SetSwipeTexture = function() end,
            SetDrawBling    = function() end,
            SetCountdownFont = function(_, name)
                fontLog[#fontLog + 1] = name
            end,
            SetHideCountdownNumbers = function(_, val)
                hideLog[#hideLog + 1] = val
            end,
        }
    end
    local function makeIconFrame(cd)
        return {
            Cooldown = cd,
            SetAlpha = function() end,
            CreateTexture = function()
                return setmetatable({}, { __index = function() return function() end end })
            end,
        }
    end

    local oldHelpersA = ns.Helpers
    ns.Helpers = {
        GetGeneralFont        = function() return "Interface\\Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,   -- no outline → clean key "14", "16"
        GetSkinBorderColor    = function() return 0, 0, 0, 1 end,
    }
    local taskAEnv = RE.BuildEnv({})
    ns.Helpers = oldHelpersA

    -- G2a: hideDurationText = true → SetHideCountdownNumbers(true)
    local hideLog1, fontLog1 = {}, {}
    taskAEnv.applyChrome(makeIconFrame(makeCd(hideLog1, fontLog1)),
        { durationSize = 14, borderSize = 0, hideDurationText = true })
    assert(#hideLog1 >= 1,
        "G2: SetHideCountdownNumbers must be called when hideDurationText=true")
    assert(hideLog1[1] == true,
        "G2: hideDurationText=true → SetHideCountdownNumbers(true), got: " .. tostring(hideLog1[1]))

    -- G2b: hideDurationText absent (nil) → SetHideCountdownNumbers(false)
    local hideLog2, fontLog2 = {}, {}
    taskAEnv.applyChrome(makeIconFrame(makeCd(hideLog2, fontLog2)),
        { durationSize = 14, borderSize = 0 })
    assert(#hideLog2 >= 1,
        "G2: SetHideCountdownNumbers must be called when hideDurationText=nil")
    assert(hideLog2[1] == false,
        "G2: hideDurationText=nil → SetHideCountdownNumbers(false), got: " .. tostring(hideLog2[1]))

    -- G3: durationTextColor propagated to font object SetTextColor.
    -- Use durationSize=12 (unused above) so a fresh font object is minted.
    local hideLog3, fontLog3 = {}, {}
    local testColor = {1, 0.5, 0.25, 0.9}
    taskAEnv.applyChrome(makeIconFrame(makeCd(hideLog3, fontLog3)),
        { durationSize = 12, borderSize = 0, durationTextColor = testColor })
    assert(#fontLog3 >= 1,
        "G3: SetCountdownFont must be called (durationSize=12)")
    local foName3 = fontLog3[1]
    local fo3 = fontObjects[foName3] or _G[foName3]
    assert(fo3, "G3: font object '" .. tostring(foName3) .. "' must exist")
    assert(fo3._lastColor,
        "G3: SetTextColor must have been called on the font object")
    assert(math.abs(fo3._lastColor[1] - testColor[1]) < 0.001
        and math.abs(fo3._lastColor[2] - testColor[2]) < 0.001
        and math.abs(fo3._lastColor[3] - testColor[3]) < 0.001
        and math.abs(fo3._lastColor[4] - testColor[4]) < 0.001,
        "G3: font object color (incl alpha) must match durationTextColor, got r=" .. tostring(fo3._lastColor[1]))

    -- G4: two applyChrome calls with DIFFERENT durationSize → DISTINCT SetCountdownFont names.
    -- (No name collapse / last-writer-wins.)
    local hideLog4, fontLog4 = {}, {}
    local cd4a = makeCd(hideLog4, fontLog4)
    local cd4b = makeCd(hideLog4, fontLog4)
    taskAEnv.applyChrome(makeIconFrame(cd4a), { durationSize = 16, borderSize = 0 })
    taskAEnv.applyChrome(makeIconFrame(cd4b), { durationSize = 14, borderSize = 0 })
    assert(#fontLog4 == 2,
        "G4: two applyChrome calls must each call SetCountdownFont (got " .. #fontLog4 .. ")")
    assert(fontLog4[1] ~= fontLog4[2],
        "G4: durationSize=16 and durationSize=14 must map to DISTINCT font-object names; "
        .. "both resolved to: " .. tostring(fontLog4[1]))

    -- G3+G4: SAME size, DIFFERENT durationTextColor -> DISTINCT font-object names
    -- (colour is part of the cache key, so per-container colour can't last-writer collapse).
    local fontLogC = {}
    taskAEnv.applyChrome(makeIconFrame(makeCd({}, fontLogC)),
        { durationSize = 15, borderSize = 0, durationTextColor = {1, 0, 0, 1} })
    taskAEnv.applyChrome(makeIconFrame(makeCd({}, fontLogC)),
        { durationSize = 15, borderSize = 0, durationTextColor = {0, 1, 0, 1} })
    assert(#fontLogC == 2 and fontLogC[1] ~= fontLogC[2],
        "G3+G4: same size + different durationTextColor must map to DISTINCT font objects "
        .. "(no colour collapse); both resolved to: " .. tostring(fontLogC[1]))

    _G.CreateFont = oldCreateFontA
    print("OK: Task A — G2 SetHideCountdownNumbers, G3 durationTextColor, G4 per-(size,outline,colour) font cache")
end

-- Task E: BuffBar surface faithfulness — G1/G12/G15. The bar bg/icon/name are
-- OWN CHILDREN of the LIVE bar frame chain (deterministic z-order vs the native
-- StatusBar fill -- same parent chain), the icon is resolved LIVE-FIRST (tracks
-- aura swaps), the name carries the QUI font on an OWN fontstring with the native
-- bar.Name hidden via SetAlpha(0), the native bar.Duration is left PASSTHROUGH (the
-- secret timer can't be owned), and ZERO forbidden strata/level/ignore-alpha/raw-SetFont
-- write lands on the live frame.
-- B4: bars now DIRECT-ANCHOR the live frame (no per-slot shell); _BarDecorateWork gets the
-- minimal stand-in `{ _spellEntry = ... }` and the retired _StyleBarShell shell-occluder
-- hide is gone, so _BarDecorateWork reads ONLY _spellEntry off the stand-in -- never a
-- shell.Bg / shell.BarIcon / shell.Border path (asserted below via a field-read tracker).
do
    local oldCSpell = _G.C_Spell
    _G.C_Spell = {
        -- Curated fallbacks DIFFER from the live values so live-first ordering is provable.
        GetSpellTexture = function() return "CURATED_ICON" end,
        GetSpellName    = function() return "Curated Name" end,
    }

    local FORBIDDEN_E = { SetFrameStrata = true, SetFrameLevel = true,
                          SetIgnoreParentAlpha = true, SetFont = true }
    local liveCalls = {}      -- methods reached through live's __index (missing fields)

    local function widget()
        local w = { _log = {} }
        return setmetatable(w, { __index = function(_, k)
            return function(_, ...) w._log[#w._log + 1] = { k, ... }; return w end
        end })
    end
    local function logHas(w, method, arg1)
        for _, c in ipairs(w._log) do
            if c[1] == method and (arg1 == nil or c[2] == arg1) then return true end
        end
        return false
    end

    local createdOnBar = {}    -- { layer = ... } for each live.Bar:CreateTexture
    local barFontStrings = {}  -- { layer = ... } for each live.Bar:CreateFontString
    local createdOnLive = {}   -- { layer = ... } for each live:CreateTexture (icon ARTWORK + border BACKGROUND)
    local ownBg, ownName, ownIcon, ownBorder

    local nameCalls, durationCalls = {}, {}
    local barName = setmetatable({}, { __index = function(_, k)
        return function(_, ...) nameCalls[#nameCalls + 1] = { k, ... } end
    end })
    local barDuration = setmetatable({}, { __index = function(_, k)
        return function(_, ...) durationCalls[#durationCalls + 1] = { k, ... } end
    end })

    local bar = {
        Name = barName, Duration = barDuration,
        BarBG = { Hide = function() end, SetAlpha = function() end },
        Pip   = { Hide = function() end, SetAlpha = function() end },
        ClearAllPoints = function() end, SetPoint = function() end,
        SetStatusBarColor = function() end, SetStatusBarTexture = function() end,
        CreateTexture = function(_, _, layer)
            local t = widget(); createdOnBar[#createdOnBar + 1] = { layer = layer }
            ownBg = t; return t
        end,
        CreateFontString = function(_, _, layer)
            local fs = widget(); barFontStrings[#barFontStrings + 1] = { layer = layer }
            ownName = fs; return fs
        end,
    }
    local liveIconTex = { GetTexture = function() return "LIVE_ICON" end }
    local live = setmetatable({
        Bar = bar,
        Icon = { Hide = function() end, Icon = liveIconTex },
        DebuffBorder = { Hide = function() end },
        CreateTexture = function(_, _, layer)
            local t = widget()
            createdOnLive[#createdOnLive + 1] = { layer = layer }
            if layer == "ARTWORK" then ownIcon = t
            elseif layer == "BACKGROUND" then ownBorder = t end
            return t
        end,
    }, { __index = function(_, k)
        return function(_, ...) liveCalls[#liveCalls + 1] = { k, ... }; return nil end
    end })

    -- B4: bars direct-anchor -> _BarDecorateWork receives the minimal stand-in
    -- `{ _spellEntry = ... }` (no shell widgets). Record EVERY field read off the
    -- stand-in so we can prove _BarDecorateWork touches no retired shell.Bg/BarIcon/
    -- Border path (_spellEntry is a rawget field, so it never trips __index).
    local shellFieldReads = {}
    local shellE = setmetatable({ _spellEntry = { spellID = 4242 } }, {
        __index = function(_, k) shellFieldReads[k] = true; return nil end,
    })

    local oldHelpersE = ns.Helpers
    ns.Helpers = {
        GetGeneralFont = function() return "Interface\\Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
    }
    local oldLSME = ns.LSM
    ns.LSM = { Fetch = function() return "Tex" end }

    RE._BarDecorateWork(live, shellE, { barHeight = 24, borderSize = 2 })

    ns.Helpers = oldHelpersE
    ns.LSM = oldLSME
    _G.C_Spell = oldCSpell

    -- Taint invariant: no forbidden write on the live frame.
    for _, c in ipairs(liveCalls) do
        assert(not FORBIDDEN_E[c[1]],
            "Task E taint: _BarDecorateWork must not call live:" .. tostring(c[1]) .. " on the live frame")
    end

    -- G1: own BACKGROUND bg on live.Bar (behind the native fill, same chain).
    local sawBgBackground = false
    for _, e in ipairs(createdOnBar) do if e.layer == "BACKGROUND" then sawBgBackground = true end end
    assert(sawBgBackground,
        "G1: own bg texture must be created on live.Bar at BACKGROUND (same chain, behind native fill)")
    assert(ownBg and logHas(ownBg, "SetColorTexture") and logHas(ownBg, "SetAllPoints"),
        "G1: own bg must be coloured + SetAllPoints behind the fill")
    -- B4: the retired shell.Bg widget is gone -- _BarDecorateWork must NOT read shell.Bg.
    assert(not shellFieldReads.Bg,
        "B4: _BarDecorateWork must NOT read shell.Bg (shell bar-widgets retired; bars direct-anchor)")

    -- G12: bar icon resolved LIVE-FIRST (live.Icon.Icon:GetTexture -> LIVE_ICON), NOT the curated spellID.
    assert(ownIcon, "G12: own bar icon texture must be created on the live frame")
    assert(logHas(ownIcon, "SetTexture", "LIVE_ICON"),
        "G12: own bar icon must take the LIVE icon texture before the curated spellID")
    assert(not logHas(ownIcon, "SetTexture", "CURATED_ICON"),
        "G12: own bar icon must NOT use the curated spellID texture when a live icon exists")
    -- B4: the retired shell.BarIcon widget is gone -- _BarDecorateWork must NOT read shell.BarIcon.
    assert(not shellFieldReads.BarIcon,
        "B4: _BarDecorateWork must NOT read shell.BarIcon (shell bar-widgets retired; bars direct-anchor)")

    -- G15: own OVERLAY name fontstring on live.Bar with the QUI font; native bar.Name hidden via
    -- SetAlpha(0); native bar.Duration left PASSTHROUGH (the secret timer can't be owned).
    local sawNameOverlay = false
    for _, e in ipairs(barFontStrings) do if e.layer == "OVERLAY" then sawNameOverlay = true end end
    assert(sawNameOverlay, "G15: own name fontstring must be created on live.Bar at OVERLAY")
    assert(ownName and logHas(ownName, "SetFont"),
        "G15: own name fontstring must carry the QUI font (SetFont on the OWN fontstring)")
    assert(ownName and logHas(ownName, "SetText"),
        "G15: own name fontstring must be populated via SetText")
    local nameHidden = false
    for _, c in ipairs(nameCalls) do if c[1] == "SetAlpha" and c[2] == 0 then nameHidden = true end end
    assert(nameHidden, "G15: native bar.Name must be hidden via SetAlpha(0)")
    assert(#durationCalls == 0,
        "G15: native bar.Duration must be left untouched (passthrough -- the secret timer can't be owned)")

    -- G1 (border): the QUI theme border is an OWN child of the LIVE bar frame chain
    -- (distinct from bg/icon/name), so border + bg + fill + name share one parent chain
    -- -> deterministic z-order, fill guaranteed visible. B4: bars direct-anchor (no shell),
    -- so _BarDecorateWork must NOT read the retired cross-chain shell.Border either.
    assert(not shellFieldReads.Border,
        "B4: _BarDecorateWork must NOT read shell.Border for bars (own border rides the live chain)")
    local sawBorderBackground = false
    for _, e in ipairs(createdOnLive) do if e.layer == "BACKGROUND" then sawBorderBackground = true end end
    assert(sawBorderBackground,
        "G1: own theme border must be created on the LIVE frame at BACKGROUND (same chain as bg/fill)")
    assert(ownBorder and ownBorder ~= ownIcon and ownBorder ~= ownBg,
        "G1: own border child must be distinct from the bg and icon textures")
    assert(ownBorder and logHas(ownBorder, "SetColorTexture") and logHas(ownBorder, "SetPoint")
        and logHas(ownBorder, "Show"),
        "G1: own border (borderSize>0) must be coloured, anchored to live, and shown")

    print("OK: Task E — G1 own-child bar bg+border on live chain, G12 live-first icon, G15 own QUI name + native hide")
end

-- G14: stack/count text stays native. Blizzard already mirrors charge and aura
-- application text onto the re-anchored item frame; QUI must not replace it with
-- an owned query overlay or hide the native count. The only invariant here is
-- that we still never SetFont on Blizzard's secret-tracked fontstrings.
do
    local oldCreateFont = _G.CreateFont
    _G.CreateFont = function(name)
        local fo = setmetatable({ SetFont = function() end, SetTextColor = function() end },
            { __index = function() return function() end end })
        _G[name] = fo; return fo
    end
    local oldRQ, oldS, oldICL, oldHelpers, oldCSpell =
        ns.CDMRuntimeQueries, ns.CDMSources, _G.InCombatLockdown, ns.Helpers, _G.C_Spell
    local displayCountQueried = false
    ns.CDMRuntimeQueries = {
        GetChargeMetadataDB = function() return { [777] = 3 } end,
        QueryCharges = function() error("native stack mirroring must not query charges") end,
    }
    ns.CDMSources = {
        QuerySpellDisplayCount = function()
            displayCountQueried = true
            return 2
        end,
    }
    ns.Helpers = {
        GetGeneralFont = function() return "Interface\\Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        GetSkinBorderColor = function() return 0, 0, 0, 1 end,
    }
    _G.C_Spell = { GetSpellName = function() return "X" end }

    local function recWidget()
        local w = { _log = {} }
        return setmetatable(w, { __index = function(_, k)
            return function(_, ...) w._log[#w._log + 1] = { k, ... }; return w end
        end })
    end
    local function logHas(w, m, a1)
        for _, c in ipairs(w._log) do if c[1] == m and (a1 == nil or c[2] == a1) then return true end end
        return false
    end
    local function makeChargeFrame(spellIDFn)
        local ownFs
        local chargeCur, appApps = recWidget(), recWidget()
        local frame = {
            ChargeCount  = { Current = chargeCur },
            Applications = { Applications = appApps },
            GetSpellID   = spellIDFn,
            CreateFontString = function() ownFs = recWidget(); return ownFs end,
            CreateTexture = function() return setmetatable({}, { __index = function() return function() end end }) end,
        }
        return frame, function() return ownFs end, chargeCur, appApps
    end

    local g14env = RE.BuildEnv({})

    -- Case 1: OUT OF COMBAT, applyChrome must not read live spell state, create
    -- a replacement count fontstring, or hide the native Blizzard count.
    _G.InCombatLockdown = function() return false end
    local liveIdCalled = false
    local f1, getFs1, cc1, ap1 = makeChargeFrame(function() liveIdCalled = true; return 777 end)
    g14env.applyChrome(f1, { durationSize = 14, borderSize = 0 })
    assert(liveIdCalled == false, "G14: native mirroring path does not read live GetSpellID")
    assert(getFs1() == nil, "G14: native mirroring path does not create an owned count fontstring")
    assert(not logHas(cc1, "SetAlpha", 0), "G14: native ChargeCount.Current remains visible")
    assert(not logHas(ap1, "SetAlpha", 0), "G14: native Applications.Applications remains visible")
    assert(not logHas(cc1, "SetFont"), "G14: NEVER SetFont on native ChargeCount.Current")
    assert(not logHas(ap1, "SetFont"), "G14: NEVER SetFont on native Applications.Applications")
    assert(displayCountQueried == false, "G14: native mirroring path does not query replacement display counts")

    -- Case 2: IN COMBAT with no stashed entry id -> still do nothing to the
    -- native count and do not read the live secret spell id.
    _G.InCombatLockdown = function() return true end
    liveIdCalled = false
    local f2, getFs2, cc2 = makeChargeFrame(function() liveIdCalled = true; return 777 end)
    g14env.applyChrome(f2, { durationSize = 14, borderSize = 0 })
    assert(liveIdCalled == false, "G14: in combat the live (secret) frame:GetSpellID() is NEVER read")
    assert(getFs2() == nil, "G14: in combat, no owned count overlay is created")
    assert(not logHas(cc2, "SetAlpha", 0), "G14: in combat, the native count is NOT blanked")

    -- Case 3: even with a curated entry id threaded through _DecorateWork, the
    -- reanchored icon should leave Blizzard's native count as the mirror.
    _G.InCombatLockdown = function() return true end
    local f3, getFs3, cc3 = makeChargeFrame(function() error("must not read live id in combat") end)
    RE._DecorateWork({ Decorate = function() end }, f3, { _spellEntry = { spellID = 777 } }, {})
    g14env.applyChrome(f3, { durationSize = 14, borderSize = 0 })
    assert(getFs3() == nil, "G14: stashed entry id does not create a replacement count overlay")
    assert(not logHas(cc3, "SetAlpha", 0), "G14: stashed entry id does not hide the native count")

    _G.CreateFont, ns.CDMRuntimeQueries, ns.CDMSources = oldCreateFont, oldRQ, oldS
    _G.InCombatLockdown, ns.Helpers, _G.C_Spell = oldICL, oldHelpers, oldCSpell
    print("OK: G14 — native stack/count text preserved, zero raw SetFont on native")
end

-- releaseIcon success contract: when Factory:ReleaseIcon REFUSES (returns false,
-- protected in combat), releaseIcon returns false AND keeps the icon in the pool
-- (a refused release must not orphan pool membership). On success it removes the
-- icon and returns a non-false value, unchanged from before.
do
    local refused = false
    local savedReleaseIcon = factoryStub.ReleaseIcon
    factoryStub.ReleaseIcon = function(_, icon) releasedIcon = icon; if refused then return false end end

    local pooled = env.acquireIcon("CC", "EE", "essential")
    assert(#factoryStub._pools.essential == 1, "setup: icon registered in pool")

    refused = true
    local ret = env.releaseIcon(pooled, "essential")
    assert(ret == false, "refused Factory:ReleaseIcon -> releaseIcon returns false")
    assert(#factoryStub._pools.essential == 1, "refused release keeps pool membership")

    refused = false
    local ret2 = env.releaseIcon(pooled, "essential")
    assert(ret2 ~= false, "successful release returns non-false")
    assert(#factoryStub._pools.essential == 0, "successful release removes pool membership")

    factoryStub.ReleaseIcon = savedReleaseIcon
end

-- Duration/stack text styling on re-anchored live items (Discord report 2026-08):
-- pre-reanchor, ConfigureIcon styled QUI-owned icons; post-reanchor the live
-- Blizzard item kept its native centered countdown + small NumberFontNormal
-- charge/stack text, ignoring durationAnchor/offsets and stackSize/stackAnchor.
-- applyChrome must now (a) re-anchor the native countdown fontstring per
-- rowConfig and (b) restyle native ChargeCount.Current / Applications.Applications
-- via a font OBJECT (SetFontObject -- G14's "never raw SetFont" invariant holds)
-- plus anchor writes relative to the live item frame.
do
    local oldCreateFont, oldHelpers = _G.CreateFont, ns.Helpers
    local fontObjs = {}
    _G.CreateFont = function(name)
        local fo = { _sets = {} }
        fo.SetFont = function(_, f, sz, o) fo._sets[#fo._sets + 1] = { f, sz, o } end
        fo.SetTextColor = function() end
        fontObjs[name] = fo
        _G[name] = fo
        return fo
    end
    ns.Helpers = {
        GetGeneralFont = function() return "QUIFONT.TTF" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
        GetSkinBorderColor = function() return 0, 0, 0, 1 end,
    }

    local function fsWidget()
        local w = { _log = {} }
        w.GetObjectType = function() return "FontString" end
        return setmetatable(w, { __index = function(_, k)
            return function(_, ...) w._log[#w._log + 1] = { k, ... } end
        end })
    end
    local function logFind(w, m)
        for _, c in ipairs(w._log) do if c[1] == m then return c end end
        return nil
    end

    -- shape = "charge" (essential/utility: ChargeCount.Current) or
    -- "apps" (buff icon: Applications frame -> Applications fontstring)
    local function makeItem(shape)
        local countFs, stackFs = fsWidget(), fsWidget()
        local cdLog = {}
        local cd = setmetatable({
            GetCountdownFontString = function() return countFs end,
            GetRegions = function() return countFs end,
        }, { __index = function(_, k)
            return function(_, ...) cdLog[#cdLog + 1] = { k, ... } end
        end })
        local holderAlphas = {}
        local holder = { SetAlpha = function(_, a) holderAlphas[#holderAlphas + 1] = a end }
        local frame = {
            Cooldown = cd,
            GetFrameLevel = function() return 10 end,
            SetAlpha = function() end,
            CreateTexture = function()
                return setmetatable({}, { __index = function() return function() end end })
            end,
        }
        if shape == "charge" then
            holder.Current = stackFs
            frame.ChargeCount = holder
        else
            holder.Applications = stackFs
            frame.Applications = holder
        end
        return frame, countFs, stackFs, cdLog, holderAlphas
    end
    local function cdLogFind(cdLog, m)
        for _, c in ipairs(cdLog) do if c[1] == m then return c end end
        return nil
    end

    local styleEnv = RE.BuildEnv({})
    local rc = {
        borderSize = 0,
        durationSize = 20, durationAnchor = "TOP", durationOffsetX = 1, durationOffsetY = 5,
        durationTextColor = { 1, 1, 1, 1 },
        stackSize = 20, stackAnchor = "BOTTOM", stackOffsetX = 0, stackOffsetY = -8,
        stackTextColor = { 1, 1, 1, 1 },
    }

    for _, shape in ipairs({ "charge", "apps" }) do
        local frame, countFs, stackFs, cdLog = makeItem(shape)
        styleEnv.applyChrome(frame, rc)

        -- (a) countdown text follows durationAnchor/offsets (was: native center)
        assert(logFind(countFs, "ClearAllPoints"), shape .. ": countdown fs re-anchored (ClearAllPoints)")
        local sp = logFind(countFs, "SetPoint")
        assert(sp and sp[2] == "TOP" and sp[3] == frame and sp[4] == "TOP"
            and sp[5] == 1 and sp[6] == 5,
            shape .. ": countdown fs SetPoint(durationAnchor, live, durationAnchor, dx, dy)")
        local scf = cdLogFind(cdLog, "SetCountdownFont")
        assert(scf and fontObjs[scf[2]], shape .. ": SetCountdownFont uses a registered font object")
        assert(fontObjs[scf[2]]._sets[1] and fontObjs[scf[2]]._sets[1][2] == 20,
            shape .. ": countdown font object carries durationSize")

        -- (b) native stack/charge text picks up stackSize/stackAnchor via font object
        assert(not logFind(stackFs, "SetFont"), shape .. ": still NEVER raw SetFont on the native fs (G14)")
        local sfo = logFind(stackFs, "SetFontObject")
        assert(sfo and fontObjs[sfo[2]], shape .. ": stack fs styled via SetFontObject(font object)")
        assert(fontObjs[sfo[2]]._sets[1] and fontObjs[sfo[2]]._sets[1][2] == 20,
            shape .. ": stack font object carries stackSize (was: Blizzard NumberFontNormal)")
        local ssp = logFind(stackFs, "SetPoint")
        assert(ssp and ssp[2] == "BOTTOM" and ssp[3] == frame and ssp[4] == "BOTTOM"
            and ssp[5] == 0 and ssp[6] == -8,
            shape .. ": stack fs SetPoint(stackAnchor, live, stackAnchor, sx, sy)")
    end

    -- hideStackText blanks the native count via alpha on holder + fs (Blizzard
    -- SetShown()s the holder every refresh, so Hide() would not stick)
    do
        local frame, _, stackFs, _, holderAlphas = makeItem("charge")
        styleEnv.applyChrome(frame, {
            borderSize = 0, durationSize = 20, stackSize = 20, hideStackText = true,
        })
        assert(holderAlphas[#holderAlphas] == 0, "hideStackText alpha-0s the native holder frame")
        local sa = logFind(stackFs, "SetAlpha")
        assert(sa and sa[2] == 0, "hideStackText alpha-0s the native fs")
        assert(not logFind(stackFs, "SetFontObject"), "hidden stack text is not restyled")
    end

    -- hideDurationText suppresses the countdown re-anchor (numbers are hidden
    -- natively via SetHideCountdownNumbers; no anchor writes needed)
    do
        local frame, countFs = makeItem("charge")
        styleEnv.applyChrome(frame, {
            borderSize = 0, durationSize = 20, stackSize = 20, hideDurationText = true,
        })
        assert(not logFind(countFs, "SetPoint"), "hideDurationText: countdown fs left un-anchored")
    end

    _G.CreateFont, ns.Helpers = oldCreateFont, oldHelpers
    print("OK: reanchor chrome styles native countdown + stack text per rowConfig")
end

do
    local holderAlphaCalls, textAlphaCalls = 0, 0
    local count = {
        SetAlpha = function() textAlphaCalls = textAlphaCalls + 1 end,
    }
    local frame = {
        ChargeCount = {
            Current = count,
            SetAlpha = function() holderAlphaCalls = holderAlphaCalls + 1 end,
        },
    }
    RE.BuildEnv({}).applyChrome(frame, { borderSize = 0 })
    assert(holderAlphaCalls == 0 and textAlphaCalls == 0,
        "native stack styling does not force Blizzard charge visibility")
end

print("OK: cdm_reanchor_realenv_test")
