-- tests/unit/cdm_reanchor_procglow_test.lua
-- Run: lua tests/unit/cdm_reanchor_procglow_test.lua
--
-- Task C (G6 + G8): the ActionButtonSpellAlertManager ShowAlert/HideAlert hook
-- that suppresses Blizzard's native proc flipbook on re-anchored CDM frames (G6)
-- and paints QUI's configured glow on a QUI-OWNED overlay CHILD of the live frame
-- (G8). The whole hook body is securecall-wrapped; the only writes the body makes
-- on the LIVE (secret) frame are SetAlpha/Hide on its SpellActivationAlert region.
-- It NEVER writes strata/level/ignore-alpha on the live frame, and the glow is
-- applied to the own overlay, never the live frame.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_hooks.lua", "cdm_reanchor_hooks.lua")("QUI", ns)

local PG = assert(ns.CDMReanchorProcGlow, "CDMReanchorProcGlow should be exported")
assert(type(PG.New) == "function", "New is a function")

-- A live (secret) frame must never receive these writes inside the hook body.
local FORBIDDEN = { SetFrameStrata = true, SetFrameLevel = true, SetIgnoreParentAlpha = true,
                    SetFont = true }

-- Recording live frame with a SpellActivationAlert child region.
local function makeLiveFrame()
    local liveCalls = {}
    local alert = {
        alpha = 1, shown = true,
        SetAlpha = function(self, a) self.alpha = a end,
        Hide     = function(self) self.shown = false end,
    }
    local frame = setmetatable({ SpellActivationAlert = alert }, {
        __index = function(_, k)
            -- Any method call on the live frame is recorded so the test can prove
            -- the hook makes no forbidden state writes on the secret frame.
            return function() liveCalls[#liveCalls + 1] = k end
        end,
    })
    return frame, alert, liveCalls
end

-- Build an instance + capture the installed hooks via a fake hooksecurefunc.
local function buildInstance(overrides)
    overrides = overrides or {}
    local rec = {
        ensured = {},      -- frame -> overlay
        startGlow = {},    -- { overlay = , settings = }
        stopGlow = {},     -- overlay
        resolved = {},     -- entry
        hooks = {},        -- { owner, method, fn }
    }
    local function makeOverlay(frame)
        local o = rec.ensured[frame]
        if not o then o = { __overlay = true, forFrame = frame }; rec.ensured[frame] = o end
        return o
    end
    local deps = {
        getEntryForFrame = overrides.getEntryForFrame,
        ensureOverlay = function(frame) return makeOverlay(frame) end,
        resolveGlow = overrides.resolveGlow or function(entry)
            rec.resolved[#rec.resolved + 1] = entry
            return { glowType = "Pixel Glow" }
        end,
        startGlow = function(overlay, settings)
            rec.startGlow[#rec.startGlow + 1] = { overlay = overlay, settings = settings }
        end,
        stopGlow = function(overlay)
            rec.stopGlow[#rec.stopGlow + 1] = overlay
        end,
        hooksecurefunc = function(owner, method, fn)
            rec.hooks[#rec.hooks + 1] = { owner = owner, method = method, fn = fn }
        end,
    }
    local inst = PG.New(deps)
    return inst, rec
end

local function fireHook(rec, method, ...)
    for _, h in ipairs(rec.hooks) do
        if h.method == method then h.fn(...) end
    end
end

-- ── Install hooks ────────────────────────────────────────────────────────────
do
    local managedEntry = { spellID = 100, viewerType = "essential" }
    local inst, rec = buildInstance({
        getEntryForFrame = function(frame) return frame._entry end,
    })
    local manager = { ShowAlert = function() end, HideAlert = function() end }
    assert(inst:Install(manager) == true, "Install hooks ShowAlert/HideAlert and reports success")
    local sawShow, sawHide = false, false
    for _, h in ipairs(rec.hooks) do
        assert(h.owner == manager, "hook installed on the manager")
        if h.method == "ShowAlert" then sawShow = true end
        if h.method == "HideAlert" then sawHide = true end
    end
    assert(sawShow and sawHide, "both ShowAlert and HideAlert hooked")
    -- idempotent: second install does nothing
    local before = #rec.hooks
    assert(inst:Install(manager) == false, "Install is idempotent (second call no-ops)")
    assert(#rec.hooks == before, "no double-hook")

    -- ── G6 + G8: ShowAlert on a MANAGED frame ────────────────────────────────
    local managedFrame, alert, liveCalls = makeLiveFrame()
    managedFrame._entry = managedEntry
    fireHook(rec, "ShowAlert", manager, managedFrame)

    -- G6: native proc flipbook suppressed
    assert(alert.alpha == 0, "G6: SpellActivationAlert:SetAlpha(0) called")
    assert(alert.shown == false, "G6: SpellActivationAlert:Hide() called")
    -- no forbidden state write on the live secret frame
    for _, m in ipairs(liveCalls) do
        assert(not FORBIDDEN[m], "ShowAlert must not call live:" .. m .. " on the secret frame")
    end
    -- G8: glow painted on the QUI-owned overlay, NOT the live frame
    assert(#rec.startGlow == 1, "G8: glow started once on a managed proc")
    local overlay = rec.ensured[managedFrame]
    assert(overlay and overlay.__overlay, "G8: an own overlay was ensured for the frame")
    assert(rec.startGlow[1].overlay == overlay, "G8: glow applied to the own overlay")
    assert(rec.startGlow[1].overlay ~= managedFrame, "G8: glow NOT applied to the live frame")
    assert(rec.resolved[1] == managedEntry, "G8: glow config resolved from the frame's entry")

    -- ── HideAlert on the managed frame stops the glow ─────────────────────────
    fireHook(rec, "HideAlert", manager, managedFrame)
    assert(#rec.stopGlow == 1, "HideAlert stops the glow")
    assert(rec.stopGlow[1] == overlay, "HideAlert stops the glow on the own overlay")
end

-- ── Unmanaged frame: ShowAlert is a no-op ────────────────────────────────────
do
    local inst, rec = buildInstance({
        getEntryForFrame = function() return nil end,  -- not a managed re-anchored frame
    })
    inst:Install({ ShowAlert = function() end, HideAlert = function() end })
    local frame, alert = makeLiveFrame()
    fireHook(rec, "ShowAlert", {}, frame)
    assert(alert.alpha == 1 and alert.shown == true, "unmanaged frame: native alert untouched")
    assert(#rec.startGlow == 0, "unmanaged frame: no QUI glow painted")
    -- HideAlert on unmanaged frame also a no-op
    fireHook(rec, "HideAlert", {}, frame)
    assert(#rec.stopGlow == 0, "unmanaged frame: no glow stop")
end

-- ── nil frame guard ──────────────────────────────────────────────────────────
do
    local inst, rec = buildInstance({ getEntryForFrame = function() return {} end })
    inst:Install({ ShowAlert = function() end, HideAlert = function() end })
    fireHook(rec, "ShowAlert", {}, nil)
    assert(#rec.startGlow == 0, "nil frame: no-op")
end

-- ── G6 still fires when glow is disabled (resolveGlow -> nil) ─────────────────
do
    local inst, rec = buildInstance({
        getEntryForFrame = function(f) return f._entry end,
        resolveGlow = function() return nil end,  -- viewer/spell glow disabled
    })
    inst:Install({ ShowAlert = function() end, HideAlert = function() end })
    local frame, alert = makeLiveFrame()
    frame._entry = { spellID = 7 }
    fireHook(rec, "ShowAlert", {}, frame)
    assert(alert.alpha == 0 and alert.shown == false, "G6: alert suppressed even when glow disabled")
    assert(#rec.startGlow == 0, "G8: no glow when resolveGlow returns nil")
end

-- ── Latch: repeated ShowAlert fires must not restart the glow ─────────────────
-- Blizzard's CooldownViewerCooldownItemMixin:RefreshData() calls
-- RefreshOverlayGlow() -> ActionButtonSpellAlertManager:ShowAlert on EVERY
-- cooldown/aura/charge refresh while the proc is overlayed. The manager dedups
-- internally (currentAlertType unchanged = no-op) but hooksecurefunc fires on
-- every public call, and the glow applier (ApplyLibCustomGlow) is Stop->Start,
-- so an unlatched hook replays the glow start anim per refresh = proc flicker.
do
    local inst, rec = buildInstance({ getEntryForFrame = function(f) return f._entry end })
    inst:Install({ ShowAlert = function() end, HideAlert = function() end })
    local frame, alert = makeLiveFrame()
    frame._entry = { spellID = 100, viewerType = "essential" }

    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.startGlow == 1, "first ShowAlert paints the glow")

    -- Refresh storm mid-proc: same frame, same entry, N more ShowAlert fires.
    alert.alpha, alert.shown = 1, true  -- pretend Blizzard re-showed the native alert
    fireHook(rec, "ShowAlert", {}, frame)
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.startGlow == 1, "latched: refresh-storm ShowAlert fires do not restart the glow")
    assert(alert.alpha == 0 and alert.shown == false,
        "G6: native alert suppression re-applied on every fire")

    -- Curated rebuild: NEW entry table, SAME spell -> still latched (key on
    -- spellID, not entry-table identity; curated lists rebuild across passes).
    frame._entry = { spellID = 100, viewerType = "essential" }
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.startGlow == 1, "rebuilt same-spell entry table stays latched")

    -- HideAlert clears the latch; the next proc paints again.
    fireHook(rec, "HideAlert", {}, frame)
    assert(#rec.stopGlow == 1, "HideAlert stops the glow")
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.startGlow == 2, "after HideAlert, next ShowAlert paints fresh")
end

-- ── Latch re-key: same frame re-fired for a DIFFERENT spell restarts ──────────
do
    local inst, rec = buildInstance({ getEntryForFrame = function(f) return f._entry end })
    inst:Install({ ShowAlert = function() end, HideAlert = function() end })
    local frame = makeLiveFrame()
    frame._entry = { spellID = 1, viewerType = "essential" }
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.startGlow == 1, "painted for spell 1")

    frame._entry = { spellID = 2, viewerType = "essential" }
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.stopGlow == 1, "different spell on the same frame stops the stale glow")
    assert(#rec.startGlow == 2, "then paints for the new spell")
end

-- ── Glow disabled mid-proc: latched glow torn down on the next fire ───────────
do
    local enabled = true
    local inst, rec = buildInstance({
        getEntryForFrame = function(f) return f._entry end,
        resolveGlow = function() return enabled and { glowType = "Pixel Glow" } or nil end,
    })
    inst:Install({ ShowAlert = function() end, HideAlert = function() end })
    local frame = makeLiveFrame()
    frame._entry = { spellID = 9, viewerType = "essential" }
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.startGlow == 1, "painted while enabled")

    enabled = false
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.stopGlow == 1, "disabled mid-proc: next ShowAlert fire stops the live glow")
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.stopGlow == 1, "stop latched too: further fires no-op")
end

-- ── OnClaim reconcile: re-pooled frame drops the old spell's glow ─────────────
-- Pool release just Hide()s the frame (HideAlert never fires for the old spell),
-- so a stale latched glow would re-show with the re-pooled frame. Mirrors
-- CDMReanchorPandemic:OnClaim.
do
    local entryA = { spellID = 1, viewerType = "essential" }
    local entryB = { spellID = 2, viewerType = "essential" }
    local inst, rec = buildInstance({ getEntryForFrame = function(f) return f._entry end })
    inst:Install({ ShowAlert = function() end, HideAlert = function() end })
    local frame = makeLiveFrame()
    frame._entry = entryA
    fireHook(rec, "ShowAlert", {}, frame)
    assert(#rec.startGlow == 1, "painted for entry A")

    inst:OnClaim(frame, entryA)
    assert(#rec.stopGlow == 0, "OnClaim with the same entry keeps the glow")

    inst:OnClaim(frame, { spellID = 1, viewerType = "essential" })
    assert(#rec.stopGlow == 0, "OnClaim with a rebuilt same-spell entry keeps the glow")

    inst:OnClaim(frame, entryB)
    assert(#rec.stopGlow == 1, "OnClaim with a different entry stops the stale glow")

    inst:OnClaim(frame, entryB)
    assert(#rec.stopGlow == 1, "OnClaim on an un-latched frame is a no-op")

    inst:OnClaim(nil, entryB)
    assert(#rec.stopGlow == 1, "OnClaim(nil): no-op")
end

print("OK: cdm_reanchor_procglow_test")
