--[[
    QUI Options V2 — Unit Frames preview: body driver

    Drives the dynamic content of the body region of the Unit Frames
    settings preview (everything outside the castbar). Owns the cycle
    state, OnUpdate ticker, per-aura state, and the ApplyDynamics
    helper that writes the current pcts to the mock primitives built
    by unit_frames_surface.lua's BuildMockFrame.

    Public surface:
        ns.QUI_UnitFramesBodyPreview.Build(mock)
        ns.QUI_UnitFramesBodyPreview.Refresh(unitDB, general)
        ns.QUI_UnitFramesBodyPreview.SetSelectedUnit(unitKey)
        ns.QUI_UnitFramesBodyPreview.Teardown()
        ns.QUI_UnitFramesBodyPreview.GetCurrentPcts()

    Invariants:
        * No game events are registered. Cycle is time-driven via OnUpdate.
        * Driver never touches real (runtime) unit frames. Mock-only.
        * Castbar mock is owned by ns.QUI_UnitFramesCastbarPreview; this
          driver does not touch it.
        * ApplyDynamics writes ONLY pct-dependent values (bar widths,
          health/power text, heal-pred width, absorb width, aura stack +
          duration text). All other styling lives in RefreshMock.
]]

local ADDON_NAME, ns = ...

local Module = {}
ns.QUI_UnitFramesBodyPreview = Module

---------------------------------------------------------------------------
-- Cycle constants
-- A single 14s loop. Health drives the named phases; power, heal-pred,
-- and absorb run on their own boundaries against the same t.
--
-- Health:    drain 0–6 (1.0→0.2), low 6–7 (0.2), refill 7–11 (0.2→1.0), idle 11–14 (1.0)
-- Power:     drain 0–8 (1.0→0.0), refill 8–10 (0.0→1.0), idle 10–14 (1.0)
-- HealPred:  hidden 0–6, grow 6–7 (0→0.25), fade 7–11 (0.25→0), hidden 11–14
-- Absorb:    hidden 0–11, grow 11–12 (0→0.25), hold 12–13 (0.25), fade 13–14 (0.25→0)
---------------------------------------------------------------------------
local CYCLE_LENGTH = 14

---------------------------------------------------------------------------
-- Driver state
---------------------------------------------------------------------------
local state = {
    mock         = nil,   -- mock frame handle from unit_frames_surface.lua's BuildMockFrame
    ticker       = nil,
    cycle        = { t = 0 },
    auraStates   = {},    -- keyed by aura icon frame; { duration = N, stack = N }
    lastUnitDB   = nil,
}

---------------------------------------------------------------------------
-- Cycle math
---------------------------------------------------------------------------

local function ComputePcts(t)
    -- Health
    local healthPct
    if t < 6 then
        healthPct = 1.0 + (0.2 - 1.0) * (t / 6)
    elseif t < 7 then
        healthPct = 0.2
    elseif t < 11 then
        healthPct = 0.2 + (1.0 - 0.2) * ((t - 7) / 4)
    else
        healthPct = 1.0
    end

    -- Power
    local powerPct
    if t < 8 then
        powerPct = 1.0 - (t / 8)
    elseif t < 10 then
        powerPct = (t - 8) / 2
    else
        powerPct = 1.0
    end

    -- Heal prediction (peaks 0.25 at t=7, fades to 0 at t=11)
    local healPredPct
    if t < 6 then
        healPredPct = 0
    elseif t < 7 then
        healPredPct = (t - 6) * 0.25
    elseif t < 11 then
        healPredPct = 0.25 * (1 - (t - 7) / 4)
    else
        healPredPct = 0
    end

    -- Absorb (grows 11→12, holds 12→13, fades 13→14)
    local absorbPct
    if t < 11 then
        absorbPct = 0
    elseif t < 12 then
        absorbPct = (t - 11) * 0.25
    elseif t < 13 then
        absorbPct = 0.25
    else
        absorbPct = 0.25 * (1 - (t - 13))
    end

    return healthPct, powerPct, healPredPct, absorbPct
end

local function AdvanceCycle(elapsed)
    state.cycle.t = (state.cycle.t + elapsed) % CYCLE_LENGTH
end

---------------------------------------------------------------------------
-- Per-aura cycle state
-- Each icon (frame) gets a state record: { duration, stack }. Independent
-- of the health/power phases — aura icons keep ticking during the idle
-- phase so the user always sees motion.
---------------------------------------------------------------------------

local function NewAuraState()
    return {
        duration = 5 + math.random() * 10,  -- 5–15s
        stack    = math.random(1, 9),
    }
end

local function EnsureAuraState(icon)
    if not state.auraStates[icon] then
        state.auraStates[icon] = NewAuraState()
    end
    return state.auraStates[icon]
end

local function AdvanceAuraStates(elapsed)
    for _, st in pairs(state.auraStates) do
        st.duration = st.duration - elapsed
        if st.duration <= 0 then
            st.duration = 5 + math.random() * 10
            local delta = (math.random(0, 1) == 0) and -1 or 1
            st.stack = math.max(1, math.min(9, st.stack + delta))
        end
    end
end

local function ApplyAuraDynamics(pool)
    if not pool then return end
    for _, icon in ipairs(pool) do
        if icon:IsShown() then
            local st = EnsureAuraState(icon)
            if icon._stack and icon._stack:IsShown() then
                icon._stack:SetText(tostring(st.stack))
            end
            if icon._dur and icon._dur:IsShown() then
                icon._dur:SetText(string.format("%.0fs", math.max(0, st.duration)))
            end
        end
    end
end

---------------------------------------------------------------------------
-- Per-tick dynamics application
-- Writes ONLY pct-dependent values. Geometry, anchors, colors, fonts,
-- textures, and Show/Hide-by-setting are owned by RefreshMock and are
-- not touched here. RefreshMock left healPred/absorb anchored to the
-- healthBar (so they auto-follow as healthBar width changes), set the
-- color/texture once, and hid them when the setting is disabled.
---------------------------------------------------------------------------

local function ApplyDynamics(mock, healthPct, powerPct, healPredPct, absorbPct)
    if not mock then return end
    local unitDB = state.lastUnitDB
    if not unitDB then return end

    local inner = math.max(0, unitDB.borderSize or 1)
    local mockW = mock:GetWidth() or 0
    local barAreaW = math.max(1, mockW - (inner * 2))

    -- Health bar width
    if mock._healthBar then
        mock._healthBar:SetWidth(math.max(1, barAreaW * healthPct))
    end

    -- Health text (uses pct-formatted string)
    if mock._healthText and mock._healthText:IsShown() then
        mock._healthText:SetText(Module.FormatHealthText(
            unitDB.healthDisplayStyle or "percent",
            unitDB.hideHealthPercentSymbol,
            unitDB.healthDivider,
            healthPct
        ))
    end

    -- Power bar width (only if power bar is shown)
    if mock._powerBar and unitDB.showPowerBar and mock._powerBar:IsShown() then
        mock._powerBar:SetWidth(barAreaW * powerPct)
    end

    -- Power text (uses pct-formatted string)
    if mock._powerText and unitDB.showPowerText and unitDB.showPowerBar
        and mock._powerText:IsShown() then
        mock._powerText:SetText(Module.FormatPowerText(
            unitDB.powerTextFormat or "percent",
            unitDB.hidePowerPercentSymbol,
            powerPct
        ))
    end

    -- Heal prediction: width grows past the healthBar's right edge.
    -- RefreshMock already anchored TOPLEFT/BOTTOMLEFT to the healthBar's
    -- TOPRIGHT/BOTTOMRIGHT, so the anchor auto-tracks the moving healthBar.
    if mock._healPred then
        local enabled = unitDB.healPrediction and unitDB.healPrediction.enabled
        if enabled and healPredPct > 0 then
            local healthW = barAreaW * healthPct
            local predW = math.min(math.max(0, barAreaW - healthW), barAreaW * healPredPct)
            if predW > 0 then
                mock._healPred:Show()
                mock._healPred:SetWidth(predW)
            else
                mock._healPred:Hide()
            end
        elseif enabled then
            mock._healPred:Hide()
        end
        -- If not enabled, RefreshMock already called Hide(); leave it alone.
    end

    -- Absorb: stripe pinned to the right edge of healthBar, grows leftward.
    if mock._absorb then
        local enabled = unitDB.absorbs and unitDB.absorbs.enabled
        if enabled and absorbPct > 0 then
            local healthW = barAreaW * healthPct
            local absW = math.min(barAreaW * absorbPct, healthW)
            if absW > 0 then
                mock._absorb:Show()
                mock._absorb:SetWidth(absW)
            else
                mock._absorb:Hide()
            end
        elseif enabled then
            mock._absorb:Hide()
        end
    end

    -- Aura stack + duration text. Independent of the health/power phases.
    -- Only writes to icons that are currently shown (RefreshMock controls
    -- the visible set per the unit's enabled aura kinds and maxIcons).
    ApplyAuraDynamics(mock._debuffIcons)
    ApplyAuraDynamics(mock._buffIcons)
end

---------------------------------------------------------------------------
-- Text formatters (migrated from unit_frames_surface.lua in T2)
-- pct flows in as a parameter — driver owns the cycle's current value.
---------------------------------------------------------------------------

function Module.FormatHealthText(style, hideSymbol, divider, pct)
    pct = pct or 0
    local pctInt = math.floor(pct * 100)
    local mockCur = "42.5k"
    local pctStr = hideSymbol and tostring(pctInt) or (pctInt .. "%")
    local sep = divider or " | "
    if style == "absolute"        then return mockCur
    elseif style == "both"        then return mockCur .. sep .. pctStr
    elseif style == "both_reverse" then return pctStr .. sep .. mockCur
    elseif style == "missing_percent" then
        local missing = 100 - pctInt
        return hideSymbol and ("-" .. missing) or ("-" .. missing .. "%")
    elseif style == "missing_value" then return "-12.5k"
    else return pctStr end
end

function Module.FormatPowerText(format, hideSymbol, pct)
    pct = pct or 0
    local pctInt = math.floor(pct * 100)
    local mockCur = "12.5k"
    local pctStr = hideSymbol and tostring(pctInt) or (pctInt .. "%")
    if format == "current"     then return mockCur
    elseif format == "both"    then return mockCur .. " | " .. pctStr
    else return pctStr end
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------

function Module.Build(mock)
    if state.ticker then return end  -- idempotent
    state.mock = mock
    local host = mock and mock.GetParent and mock:GetParent() or nil
    state.ticker = CreateFrame("Frame", nil, host)
    state.ticker:SetScript("OnUpdate", function(_, elapsed)
        AdvanceCycle(elapsed)
        AdvanceAuraStates(elapsed)
        ApplyDynamics(state.mock, ComputePcts(state.cycle.t))
    end)
end

function Module.Refresh(unitDB, _general)
    state.lastUnitDB = unitDB

    -- Clear aura state entries for icons that became hidden (so a
    -- newly re-enabled aura kind starts with fresh randomized state).
    local mock = state.mock
    if mock then
        local function syncPool(pool)
            if not pool then return end
            for _, icon in ipairs(pool) do
                if not icon:IsShown() then
                    state.auraStates[icon] = nil
                end
            end
        end
        syncPool(mock._debuffIcons)
        syncPool(mock._buffIcons)
    end

    -- Paint the first frame after refresh with live cycle pcts so the
    -- bars don't snap to 72% / 85% between RefreshMock and the next tick.
    if mock then
        ApplyDynamics(mock, ComputePcts(state.cycle.t))
    end
end

function Module.SetSelectedUnit(unitKey)
    if not unitKey then return end

    -- Unit change → start a fresh cycle and re-randomize all aura state.
    state.cycle.t = 0
    state.auraStates = {}
end

function Module.Teardown()
    if state.ticker then
        state.ticker:SetScript("OnUpdate", nil)
    end
    state.mock       = nil
    state.ticker     = nil
    state.auraStates = {}
    state.cycle      = { t = 0 }
end

function Module.GetCurrentPcts()
    local h, p, hp, ab = ComputePcts(state.cycle.t)
    return { health = h, power = p, healPred = hp, absorb = ab }
end
