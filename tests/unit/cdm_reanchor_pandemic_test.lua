-- tests/unit/cdm_reanchor_pandemic_test.lua
-- Run: lua tests/unit/cdm_reanchor_pandemic_test.lua
--
-- Pandemic glow bridge for re-anchored Blizzard CDM frames. Owned icons drive
-- pandemic from the resolver's aura DurationObject; re-anchored live frames
-- never enter that path, so the bridge post-hooks Blizzard's OWN pandemic
-- state machine (ShowPandemicStateFrame/HidePandemicStateFrame, fired from
-- CooldownViewerItemMixin:CheckPandemicTimeDisplay) and paints QUI's pandemic
-- flash on the QUI-OWNED overlay child. The only live-frame writes are
-- SetAlpha(0)/Hide on the native PandemicIcon child (suppressed on managed
-- frames; untouched on unmanaged frames). Show re-fires every item OnUpdate
-- tick during pandemic, so the paint latches per (frame, entry).
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_hooks.lua", "cdm_reanchor_hooks.lua")("QUI", ns)

local PB = assert(ns.CDMReanchorPandemic, "CDMReanchorPandemic should be exported")
assert(type(PB.New) == "function", "New is a function")

-- A live (secret) frame must never receive these writes inside the hook body.
local FORBIDDEN = { SetFrameStrata = true, SetFrameLevel = true, SetIgnoreParentAlpha = true,
                    SetFont = true, SetAlpha = true, Hide = true, Show = true }

-- Recording live frame with the pandemic mixin methods + a native PandemicIcon.
local function makeLiveFrame()
    local liveCalls = {}
    local nativeIcon = {
        alpha = 1, shown = true,
        SetAlpha = function(self, a) self.alpha = a end,
        Hide     = function(self) self.shown = false end,
    }
    local frame = setmetatable({
        PandemicIcon = nativeIcon,
        ShowPandemicStateFrame = function() end,
        HidePandemicStateFrame = function() end,
    }, {
        __index = function(_, k)
            -- Any other method call on the live frame is recorded so the test
            -- can prove the hook makes no forbidden writes on the secret frame.
            return function() liveCalls[#liveCalls + 1] = k end
        end,
    })
    return frame, nativeIcon, liveCalls
end

-- Build an instance + capture installed hooks via a fake hooksecurefunc.
local function buildInstance(overrides)
    overrides = overrides or {}
    local rec = {
        ensured = {},        -- frame -> overlay
        starts = {},         -- overlays painted
        stops = {},          -- overlays cleared
        hooks = {},          -- { owner, method, fn }
        securecalls = 0,
    }
    local function makeOverlay(frame)
        local o = rec.ensured[frame]
        if not o then o = { __overlay = true, forFrame = frame }; rec.ensured[frame] = o end
        return o
    end
    local deps = {
        getEntryForFrame = overrides.getEntryForFrame,
        ensureOverlay = function(frame) return makeOverlay(frame) end,
        isPandemicEnabled = overrides.isPandemicEnabled or function() return true end,
        startPandemic = function(overlay) rec.starts[#rec.starts + 1] = overlay end,
        stopPandemic = function(overlay) rec.stops[#rec.stops + 1] = overlay end,
        hooksecurefunc = function(owner, method, fn)
            rec.hooks[#rec.hooks + 1] = { owner = owner, method = method, fn = fn }
        end,
        securecall = function(fn, ...)
            rec.securecalls = rec.securecalls + 1
            return fn(...)
        end,
    }
    local inst = PB.New(deps)
    return inst, rec
end

local function fireHook(rec, owner, method, ...)
    for _, h in ipairs(rec.hooks) do
        if h.owner == owner and h.method == method then h.fn(...) end
    end
end

-- ── Hook install: both methods, per frame, idempotent ────────────────────────
do
    local inst, rec = buildInstance({ getEntryForFrame = function(f) return f._entry end })
    local frame = makeLiveFrame()
    inst:Hook(frame)
    local sawShow, sawHide = false, false
    for _, h in ipairs(rec.hooks) do
        assert(h.owner == frame, "hooks installed on the frame")
        if h.method == "ShowPandemicStateFrame" then sawShow = true end
        if h.method == "HidePandemicStateFrame" then sawHide = true end
    end
    assert(sawShow and sawHide, "both pandemic methods hooked")
    local before = #rec.hooks
    inst:Hook(frame)
    assert(#rec.hooks == before, "Hook is idempotent per frame")

    -- A frame without the pandemic mixin methods is skipped entirely.
    local bare = setmetatable({}, { __index = function() return nil end })
    inst:Hook(bare)
    assert(#rec.hooks == before, "frame without pandemic methods: no hooks installed")
end

-- ── Managed frame: suppress native FX, paint own overlay, latch per tick ─────
do
    local entry = { spellID = 100, viewerType = "essential" }
    local inst, rec = buildInstance({ getEntryForFrame = function(f) return f._entry end })
    local frame, nativeIcon, liveCalls = makeLiveFrame()
    frame._entry = entry
    inst:Hook(frame)

    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(rec.securecalls > 0, "hook body runs under securecall")
    assert(nativeIcon.alpha == 0, "native PandemicIcon:SetAlpha(0) called")
    assert(nativeIcon.shown == false, "native PandemicIcon:Hide() called")
    for _, m in ipairs(liveCalls) do
        assert(not FORBIDDEN[m], "Show must not call live:" .. m .. " on the secret frame")
    end
    assert(#rec.starts == 1, "pandemic painted once on the own overlay")
    local overlay = rec.ensured[frame]
    assert(overlay and overlay.__overlay, "an own overlay was ensured for the frame")
    assert(rec.starts[1] == overlay, "paint applied to the own overlay")
    assert(rec.starts[1] ~= frame, "paint NOT applied to the live frame")

    -- Show re-fires every OnUpdate tick during pandemic: latched, no re-paint.
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(#rec.starts == 1, "latch: repeated Show ticks do not re-paint")

    -- Hide stops the glow once; a second Hide is a no-op.
    fireHook(rec, frame, "HidePandemicStateFrame", frame)
    assert(#rec.stops == 1 and rec.stops[1] == overlay, "Hide stops the glow on the own overlay")
    fireHook(rec, frame, "HidePandemicStateFrame", frame)
    assert(#rec.stops == 1, "second Hide is a no-op (latch cleared)")

    -- Next pandemic window re-paints.
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(#rec.starts == 2, "after Hide, the next Show re-paints")
end

-- ── Unmanaged frame: native FX untouched, no paint ───────────────────────────
do
    local inst, rec = buildInstance({ getEntryForFrame = function() return nil end })
    local frame, nativeIcon = makeLiveFrame()
    inst:Hook(frame)
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(nativeIcon.alpha == 1 and nativeIcon.shown == true,
        "unmanaged frame: native PandemicIcon untouched")
    assert(#rec.starts == 0, "unmanaged frame: no QUI paint")
    fireHook(rec, frame, "HidePandemicStateFrame", frame)
    assert(#rec.stops == 0, "unmanaged frame: no stop")
end

-- ── Settings gate: native FX still suppressed; live toggle clears the latch ──
do
    local enabled = true
    local inst, rec = buildInstance({
        getEntryForFrame = function(f) return f._entry end,
        isPandemicEnabled = function() return enabled end,
    })
    local frame, nativeIcon = makeLiveFrame()
    frame._entry = { spellID = 7, viewerType = "utility" }
    inst:Hook(frame)

    enabled = false
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(nativeIcon.alpha == 0 and nativeIcon.shown == false,
        "native FX suppressed on managed frames even when QUI pandemic disabled")
    assert(#rec.starts == 0, "disabled: no QUI paint")

    -- Toggled on mid-pandemic: next tick paints.
    enabled = true
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(#rec.starts == 1, "enabled mid-pandemic: next Show tick paints")

    -- Toggled off mid-pandemic: next tick clears the painted latch.
    enabled = false
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(#rec.stops == 1, "disabled mid-pandemic: next Show tick stops the glow")
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(#rec.stops == 1, "stop latched too: further ticks no-op")
end

-- ── OnClaim reconcile: re-pooled frame drops the old spell's glow ─────────────
do
    local entryA = { spellID = 1, viewerType = "essential" }
    local entryB = { spellID = 2, viewerType = "essential" }
    local inst, rec = buildInstance({ getEntryForFrame = function(f) return f._entry end })
    local frame = makeLiveFrame()
    frame._entry = entryA
    inst:Hook(frame)
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(#rec.starts == 1, "painted for entry A")

    -- Same entry re-claimed: glow untouched.
    inst:OnClaim(frame, entryA)
    assert(#rec.stops == 0, "OnClaim with the same entry keeps the glow")

    -- Curated rebuild: a NEW entry table for the SAME spell must keep the glow
    -- (the latch keys on spellID, not entry-table identity).
    inst:OnClaim(frame, { spellID = 1, viewerType = "essential" })
    assert(#rec.stops == 0, "OnClaim with a rebuilt same-spell entry keeps the glow")
    frame._entry = { spellID = 1, viewerType = "essential" }
    fireHook(rec, frame, "ShowPandemicStateFrame", frame)
    assert(#rec.starts == 1, "Show with a rebuilt same-spell entry stays latched (no re-paint)")
    frame._entry = entryA

    -- Frame re-pooled to entry B (Hide never fired): claim reconcile stops it.
    inst:OnClaim(frame, entryB)
    assert(#rec.stops == 1, "OnClaim with a different entry stops the stale glow")

    -- Un-latched frame: reconcile is a no-op.
    inst:OnClaim(frame, entryB)
    assert(#rec.stops == 1, "OnClaim on an un-latched frame is a no-op")
end

-- ── nil frame guards ─────────────────────────────────────────────────────────
do
    local inst, rec = buildInstance({ getEntryForFrame = function() return {} end })
    inst:Hook(nil)
    assert(#rec.hooks == 0, "Hook(nil): no-op")
    inst:_OnShowPandemic(nil)
    inst:_OnHidePandemic(nil)
    inst:OnClaim(nil, {})
    assert(#rec.starts == 0 and #rec.stops == 0, "nil frame: no-ops")
end

print("OK: cdm_reanchor_pandemic_test")
