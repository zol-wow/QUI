-- tests/unit/aura_slots_layout_test.lua
-- Task 6: tracked slots (core/aura_slots.lua) honor element.maxIcons,
-- element.iconsPerRow (wrap) and growDirection == "CENTER". AnchorSlot does
-- manual SetPoint math (unlike the filter-strip engine flow layout in
-- core/aura_skin.lua) so these three behaviors are exercised end-to-end
-- through S.Sync against stub container/frame objects that capture the
-- SetPoint args (forbidden objects can't run headless, so we stand in with
-- plain tables exposing exactly the methods aura_slots.lua calls).
-- Run: lua5.1 tests/unit/aura_slots_layout_test.lua
_G.InCombatLockdown = function() return false end

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()  -- real ns.AuraGlue.ElementProfile + ns.AuraElements

-- AuraSkin is the live secure-button adapter (buildButtonArt touches
-- forbidden inbound setters that don't exist on a plain stub) — stub it,
-- same boundary aura_slots.lua itself draws (Deps() only needs it truthy).
ns.Addon = ns.Addon or {}
ns.Addon.AuraSkin = { WireButton = function() end }

local S = assert(loadfile("core/aura_slots.lua"))("QUI", ns)

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

-- Minimal slot-frame stub: only the methods StyleSlot/AnchorSlot call on a
-- non-bar, non-square, radial-swipe (default) element ever get invoked.
-- _setPointCount distinguishes birth-time (initializeFrame) anchoring from
-- the post-birth pass: restricted creation must anchor exactly once (birth).
local function MakeFrame()
    return {
        _setPointCount = 0,
        SetSize = function() end,
        ClearAllPoints = function() end,
        Icon = { SetAlpha = function() end },
        SetPoint = function(self, point, relativeTo, relativePoint, dx, dy)
            self._setPointCount = self._setPointCount + 1
            self._lastSetPoint = { point = point, relativeTo = relativeTo,
                relativePoint = relativePoint, dx = dx, dy = dy }
        end,
    }
end

-- Minimal container stub: records every SetAuraSlotCandidateFilters /
-- SetAuraSlotFilterString call by slot key so tests can assert park vs.
-- live filters, and AddAuraSlot hands back a fresh frame stub. Like the live
-- 68675 frame provider (Blizzard_AuraContainerFrameProviders), AddAuraSlot
-- runs opts.initializeFrame(frame) at creation — BEFORE the child-access
-- restriction would apply — so birth-time styling/anchoring is exercised.
local function MakeContainer()
    local c = { _filterCalls = {}, _stringCalls = {}, _createdKeys = {}, _birthFilters = {} }
    c.SetAuraSlotFilterString = function(self, key, base) c._stringCalls[key] = base end
    c.SetAuraSlotCandidateFilters = function(self, key, filters) c._filterCalls[key] = filters end
    c.AddAuraSlot = function(self, key, base, opts)
        c._createdKeys[#c._createdKeys + 1] = key
        c._birthFilters[key] = opts and opts.candidateFilters
        local frame = MakeFrame()
        if opts and type(opts.initializeFrame) == "function" then
            opts.initializeFrame(frame)
        end
        return frame
    end
    return c
end

----------------------------------------------------------------------------
-- Test A: maxIcons truncates — 5 spells, maxIcons = 3. Slots 4/5 (already
-- present in the pool from a prior sync at a higher cap) are parked.
----------------------------------------------------------------------------
do
    local element = {
        spells = { 101, 102, 103, 104, 105 },
        maxIcons = 3,
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "RIGHT",
    }
    local container = MakeContainer()
    container._quiSlots = {}
    for i = 1, 5 do
        container._quiSlots[i] = { key = "t" .. i, frame = MakeFrame(), parked = false }
    end

    local complete = S.Sync(container, element, true)
    check("maxIcons: Sync reports complete", complete == true)

    local pool = container._quiSlots
    check("maxIcons: slot 1 stays live", pool[1].parked == false)
    check("maxIcons: slot 2 stays live", pool[2].parked == false)
    check("maxIcons: slot 3 stays live", pool[3].parked == false)
    check("maxIcons: slot 4 parked (surplus)", pool[4].parked == true)
    check("maxIcons: slot 5 parked (surplus)", pool[5].parked == true)

    check("maxIcons: slot 4 filter is the park recipe (maxDuration=0)",
        container._filterCalls["t4"] and container._filterCalls["t4"].maxDuration == 0)
    check("maxIcons: slot 5 filter is the park recipe (maxDuration=0)",
        container._filterCalls["t5"] and container._filterCalls["t5"].maxDuration == 0)
    check("maxIcons: slot 1 filter is a live per-spell filter, not parked",
        container._filterCalls["t1"] and container._filterCalls["t1"].includeSpellIDs ~= nil
        and container._filterCalls["t1"].maxDuration == nil)
end

----------------------------------------------------------------------------
-- Test B: iconsPerRow wraps — 5 spells, iconsPerRow = 2, TOP-anchored grow
-- RIGHT. Slot 3 (index 3, 0-based step 2) is the first icon of the second
-- row: col 0, row 1 -> dy == -(1 * (h + spacing)) (extra rows grow AWAY
-- from a TOP anchor, i.e. downward/negative).
----------------------------------------------------------------------------
do
    local element = {
        spells = { 101, 102, 103, 104, 105 },
        iconsPerRow = 2,
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "RIGHT",
    }
    local container = MakeContainer()
    local complete = S.Sync(container, element, true)
    check("iconsPerRow: Sync reports complete", complete == true)

    local pool = container._quiSlots
    local h, spacing = 22, 2  -- ElementProfile defaults (no iconSize/spacing set)
    local slot3 = pool[3]
    local sp = slot3 and slot3.frame._lastSetPoint
    check("iconsPerRow: slot 3 SetPoint captured", sp ~= nil)
    if sp then
        check("iconsPerRow: slot 3 wraps to col 0 (dx == 0)", sp.dx == 0, tostring(sp.dx))
        check("iconsPerRow: slot 3 row offset dy == -(1 * (h + spacing))",
            sp.dy == -(1 * (h + spacing)), tostring(sp.dy))
    end

    -- Regression: slot 1 (row 0, col 0) stays at the origin.
    local slot1 = pool[1]
    local sp1 = slot1 and slot1.frame._lastSetPoint
    check("iconsPerRow: slot 1 stays at origin (dx=0, dy=0)",
        sp1 and sp1.dx == 0 and sp1.dy == 0)
end

----------------------------------------------------------------------------
-- Test C: CENTER grow — 3 spells, growDirection = "CENTER". Row is centered
-- on the anchor: slot 1 at -(w+spacing), slot 2 at 0, slot 3 at +(w+spacing).
----------------------------------------------------------------------------
do
    local element = {
        spells = { 201, 202, 203 },
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "CENTER",
    }
    local container = MakeContainer()
    local complete = S.Sync(container, element, true)
    check("CENTER: Sync reports complete", complete == true)

    local pool = container._quiSlots
    local w, spacing = 22, 2
    local step = w + spacing
    local sp1 = pool[1] and pool[1].frame._lastSetPoint
    local sp2 = pool[2] and pool[2].frame._lastSetPoint
    local sp3 = pool[3] and pool[3].frame._lastSetPoint
    check("CENTER: slot 1 dx == -(w + spacing)", sp1 and sp1.dx == -step, sp1 and tostring(sp1.dx))
    check("CENTER: slot 2 dx == 0", sp2 and sp2.dx == 0, sp2 and tostring(sp2.dx))
    check("CENTER: slot 3 dx == +(w + spacing)", sp3 and sp3.dx == step, sp3 and tostring(sp3.dx))
    check("CENTER: all three share dy == 0 (single row)",
        sp1 and sp2 and sp3 and sp1.dy == 0 and sp2.dy == 0 and sp3.dy == 0)
end

----------------------------------------------------------------------------
-- Test D: vertical grow wrap is anchor-symmetric — anchor TOPRIGHT, grow UP,
-- iconsPerRow = 2, 4 spells. Extra COLUMNS must extend AWAY from the
-- anchored RIGHT edge (leftward, dx negative), mirroring how horizontal
-- grows push extra rows away from a TOP/BOTTOM anchor. All other tests use
-- TOPLEFT, which masks the sign.
----------------------------------------------------------------------------
do
    local element = {
        spells = { 301, 302, 303, 304 },
        iconsPerRow = 2,
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPRIGHT",
        growDirection = "UP",
    }
    local container = MakeContainer()
    local complete = S.Sync(container, element, true)
    check("UP@TOPRIGHT: Sync reports complete", complete == true)

    local pool = container._quiSlots
    local w, spacing = 22, 2
    local step = w + spacing
    local sp1 = pool[1] and pool[1].frame._lastSetPoint
    local sp2 = pool[2] and pool[2].frame._lastSetPoint
    local sp3 = pool[3] and pool[3].frame._lastSetPoint
    local sp4 = pool[4] and pool[4].frame._lastSetPoint
    check("UP@TOPRIGHT: slot 1 at origin", sp1 and sp1.dx == 0 and sp1.dy == 0)
    check("UP@TOPRIGHT: slot 2 climbs (dy == +(h + spacing), dx == 0)",
        sp2 and sp2.dx == 0 and sp2.dy == step, sp2 and (tostring(sp2.dx) .. "," .. tostring(sp2.dy)))
    check("UP@TOPRIGHT: slot 3 wraps LEFTWARD off the right edge (dx == -(w + spacing))",
        sp3 and sp3.dx == -step, sp3 and tostring(sp3.dx))
    check("UP@TOPRIGHT: slot 3 restarts the column (dy == 0)",
        sp3 and sp3.dy == 0, sp3 and tostring(sp3.dy))
    check("UP@TOPRIGHT: slot 4 second column, second icon (dx == -(w+spacing), dy == +(h+spacing))",
        sp4 and sp4.dx == -step and sp4.dy == step,
        sp4 and (tostring(sp4.dx) .. "," .. tostring(sp4.dy)))
end

----------------------------------------------------------------------------
-- Test E: non-number spell entries don't inflate CENTER's total — 4 array
-- entries but only 3 numeric. total must be the RENDERED count (3), so the
-- three live slots center symmetrically exactly as in Test C.
----------------------------------------------------------------------------
do
    local element = {
        spells = { 201, "bogus", 202, 203 },
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "CENTER",
    }
    local container = MakeContainer()
    local complete = S.Sync(container, element, true)
    check("CENTER+junk: Sync reports complete", complete == true)

    local pool = container._quiSlots
    check("CENTER+junk: only 3 slots rendered", pool[3] ~= nil and pool[4] == nil)
    local w, spacing = 22, 2
    local step = w + spacing
    local sp1 = pool[1] and pool[1].frame._lastSetPoint
    local sp2 = pool[2] and pool[2].frame._lastSetPoint
    local sp3 = pool[3] and pool[3].frame._lastSetPoint
    check("CENTER+junk: slot 1 dx == -(w + spacing)", sp1 and sp1.dx == -step, sp1 and tostring(sp1.dx))
    check("CENTER+junk: slot 2 dx == 0", sp2 and sp2.dx == 0, sp2 and tostring(sp2.dx))
    check("CENTER+junk: slot 3 dx == +(w + spacing)", sp3 and sp3.dx == step, sp3 and tostring(sp3.dx))
end

----------------------------------------------------------------------------
-- Test F: CENTER short last row — 5 spells, iconsPerRow = 2, TOP-anchored.
-- Full rows (2 icons) center at dx = ±(w+spacing)/2; the wrapped LAST row
-- of 1 centers on its own count: dx == 0, two rows down (dy == -2*(h+sp)).
----------------------------------------------------------------------------
do
    local element = {
        spells = { 401, 402, 403, 404, 405 },
        iconsPerRow = 2,
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "CENTER",
    }
    local container = MakeContainer()
    local complete = S.Sync(container, element, true)
    check("CENTER short row: Sync reports complete", complete == true)

    local pool = container._quiSlots
    local w, spacing = 22, 2
    local step = w + spacing
    local half = step / 2
    local sp1 = pool[1] and pool[1].frame._lastSetPoint
    local sp2 = pool[2] and pool[2].frame._lastSetPoint
    local sp3 = pool[3] and pool[3].frame._lastSetPoint
    local sp5 = pool[5] and pool[5].frame._lastSetPoint
    check("CENTER short row: slot 1 dx == -(w+spacing)/2 (full row of 2)",
        sp1 and sp1.dx == -half, sp1 and tostring(sp1.dx))
    check("CENTER short row: slot 2 dx == +(w+spacing)/2", sp2 and sp2.dx == half, sp2 and tostring(sp2.dx))
    check("CENTER short row: slot 3 starts row 2 (dx == -(w+spacing)/2, dy == -(h+spacing))",
        sp3 and sp3.dx == -half and sp3.dy == -step,
        sp3 and (tostring(sp3.dx) .. "," .. tostring(sp3.dy)))
    check("CENTER short row: slot 5 (last row of 1) centers at dx == 0",
        sp5 and sp5.dx == 0, sp5 and tostring(sp5.dx))
    check("CENTER short row: slot 5 dy == -(2 * (h + spacing))",
        sp5 and sp5.dy == -2 * step, sp5 and tostring(sp5.dy))
end

----------------------------------------------------------------------------
-- Test G: restricted creation (68675) — auras secret during Sync. AddAuraSlot
-- still runs (only combat gates creation) and initializeFrame styles/anchors
-- AT BIRTH (the provider runs it before the child-access restriction
-- applies). The post-birth child pass is restriction-gated and must be
-- SKIPPED, so each frame anchors exactly once, and Sync reports incomplete
-- so the caller's regen replay re-runs it once the restriction clears.
----------------------------------------------------------------------------
do
    _G.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    local element = {
        spells = { 501, 502, 503 },
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "RIGHT",
    }
    local container = MakeContainer()
    local complete = S.Sync(container, element, true)
    check("restricted create: Sync reports INCOMPLETE (replay at regen)", complete == false)

    local pool = container._quiSlots
    check("restricted create: all 3 slots created", pool and pool[3] ~= nil)
    local w, spacing = 22, 2
    for i = 1, 3 do
        local f = pool[i] and pool[i].frame
        check(("restricted create: slot %d anchored exactly once (at birth)"):format(i),
            f and f._setPointCount == 1, f and tostring(f._setPointCount))
        local sp = f and f._lastSetPoint
        check(("restricted create: slot %d birth anchor dx == %d"):format(i, (i - 1) * (w + spacing)),
            sp and sp.dx == (i - 1) * (w + spacing), sp and tostring(sp.dx))
    end
    _G.C_Secrets = nil
end

----------------------------------------------------------------------------
-- Test H: restricted REWRITE — pool already populated, auras secret. The
-- container-level SetAuraSlot* rewrites stay live (only CHILD access is
-- restricted), no child write happens (no SetPoint at all on the pre-seeded
-- frames), and Sync reports incomplete.
----------------------------------------------------------------------------
do
    _G.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    local element = {
        spells = { 601, 602 },
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "RIGHT",
    }
    local container = MakeContainer()
    container._quiSlots = {}
    for i = 1, 2 do
        container._quiSlots[i] = { key = "t" .. i, frame = MakeFrame(), parked = true }
    end
    local complete = S.Sync(container, element, true)
    check("restricted rewrite: Sync reports INCOMPLETE", complete == false)
    check("restricted rewrite: slot 1 unparked (container writes stay live)",
        container._quiSlots[1].parked == false)
    check("restricted rewrite: slot 1 got a live per-spell filter",
        container._filterCalls["t1"] and container._filterCalls["t1"].includeSpellIDs ~= nil)
    check("restricted rewrite: no child writes (SetPoint never called)",
        container._quiSlots[1].frame._setPointCount == 0
        and container._quiSlots[2].frame._setPointCount == 0)
    _G.C_Secrets = nil
end

----------------------------------------------------------------------------
-- Test I: parkAll shell transition (live-assist gate, party/raid HELPFUL) —
-- probe FALSE out of combat builds slot shells PARKED (birth filters = the
-- never-match park recipe); when the probe flips TRUE mid-combat, the next
-- Sync unparks them via container-level filter REWRITES alone: no new
-- AddAuraSlot (creation is combat-forbidden), slots go live, and only the
-- child anchor pass defers to the regen replay (Sync reports incomplete).
----------------------------------------------------------------------------
do
    local assistable = false
    _G.UnitIsConnected = function() return assistable end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitCanAssist = function() return true end
    _G.UnitIsVisible = function() return true end
    _G.UnitPhaseReason = function() return nil end

    local element = {
        spells = { 701, 702 },
        enabled = true,
        auraType = "HELPFUL",
        anchor = "TOPLEFT",
        growDirection = "RIGHT",
    }
    local container = MakeContainer()
    container.GetUnit = function() return "party1" end

    -- Phase 1: out of combat, probe FALSE — shells must still be built.
    local complete = S.Sync(container, element, true)
    local pool = container._quiSlots
    check("parkAll: cold false-probe Sync completes (creation + birth anchor OOC)",
        complete == true)
    check("parkAll: shells CREATED despite the false probe",
        #container._createdKeys == 2 and pool[1] ~= nil and pool[2] ~= nil)
    check("parkAll: both shells born PARKED",
        pool[1].parked == true and pool[2].parked == true)
    check("parkAll: birth filters are the park recipe, never a spell filter",
        container._birthFilters["t1"] and container._birthFilters["t1"].maxDuration == 0
        and container._birthFilters["t2"] and container._birthFilters["t2"].maxDuration == 0)
    check("parkAll: applied assist state recorded FALSE (Sync is the writer)",
        container._quiAssistApplied == false)

    -- Phase 2: probe flips TRUE while IN COMBAT — unpark must ride filter
    -- rewrites on the existing shells.
    assistable = true
    _G.InCombatLockdown = function() return true end
    complete = S.Sync(container, element, true)
    check("parkAll->live: NO new slot creation in combat",
        #container._createdKeys == 2)
    check("parkAll->live: slots unparked mid-combat via rewrite",
        pool[1].parked == false and pool[2].parked == false)
    check("parkAll->live: filter string rewritten to the live base",
        container._stringCalls["t1"] == "HELPFUL" and container._stringCalls["t2"] == "HELPFUL")
    check("parkAll->live: candidate filters rewritten to per-spell includes",
        container._filterCalls["t1"] and container._filterCalls["t1"].includeSpellIDs ~= nil
        and container._filterCalls["t1"].maxDuration == nil
        and container._filterCalls["t2"] and container._filterCalls["t2"].includeSpellIDs ~= nil)
    check("parkAll->live: applied assist state now TRUE",
        container._quiAssistApplied == true)
    check("parkAll->live: Sync reports INCOMPLETE (child anchor deferred to regen)",
        complete == false)

    _G.InCombatLockdown = function() return false end
    _G.UnitIsConnected = nil
    _G.UnitIsDeadOrGhost = nil
    _G.UnitCanAssist = nil
    _G.UnitIsVisible = nil
    _G.UnitPhaseReason = nil
end

if failures > 0 then error(failures .. " failure(s) in aura_slots_layout_test") end
print("OK: aura_slots_layout_test (all checks passed)")
