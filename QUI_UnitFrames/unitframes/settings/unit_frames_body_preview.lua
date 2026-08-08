local ADDON_NAME, ns = ...

local Module = {}
ns.QUI_UnitFramesBodyPreview = Module

local CYCLE_LENGTH = 14

local state = {
    mock         = nil,
    ticker       = nil,
    cycle        = { t = 0 },
    auraStates   = {},
    lastUnitDB   = nil,
}

local function ComputePcts(t)
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

    local powerPct
    if t < 8 then
        powerPct = 1.0 - (t / 8)
    elseif t < 10 then
        powerPct = (t - 8) / 2
    else
        powerPct = 1.0
    end

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

local function NewAuraState()
    return {
        duration = 5 + math.random() * 10,
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
            if icon._stack and icon._stack:IsShown() and st.shownStack ~= st.stack then
                st.shownStack = st.stack
                icon._stack:SetText(tostring(st.stack))
            end
            local secs = math.max(0, st.duration)
            local shownSecs = math.floor(secs + 0.5)
            if icon._dur and icon._dur:IsShown() and st.shownSecs ~= shownSecs then
                st.shownSecs = shownSecs
                icon._dur:SetText(string.format("%.0fs", secs))
            end
        end
    end
end

local function ApplyDynamics(mock, healthPct, powerPct, healPredPct, absorbPct)
    if not mock then return end
    local unitDB = state.lastUnitDB
    if not unitDB then return end

    local inner = math.max(0, unitDB.borderSize or 1)
    local mockW = mock:GetWidth() or 0
    local barAreaW = math.max(1, mockW - (inner * 2))

    if mock._healthBar then
        mock._healthBar:SetWidth(math.max(1, barAreaW * healthPct))
    end

    local healthInt = math.floor(healthPct * 100)
    if mock._healthText and mock._healthText:IsShown() and state.shownHealth ~= healthInt then
        state.shownHealth = healthInt
        mock._healthText:SetText(Module.FormatHealthText(
            unitDB.healthDisplayStyle or "percent",
            unitDB.hideHealthPercentSymbol,
            unitDB.healthDivider,
            healthPct
        ))
    end

    if mock._powerBar and unitDB.showPowerBar and mock._powerBar:IsShown() then
        mock._powerBar:SetWidth(barAreaW * powerPct)
    end

    local powerInt = math.floor(powerPct * 100)
    if mock._powerText and unitDB.showPowerText and unitDB.showPowerBar
        and mock._powerText:IsShown() and state.shownPower ~= powerInt then
        state.shownPower = powerInt
        mock._powerText:SetText(Module.FormatPowerText(
            unitDB.powerTextFormat or "percent",
            unitDB.hidePowerPercentSymbol,
            powerPct
        ))
    end

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
    end

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

    ApplyAuraDynamics(mock._debuffIcons)
    ApplyAuraDynamics(mock._buffIcons)
end

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

function Module.Build(mock)
    state.mock = mock
    local host = mock and mock.GetParent and mock:GetParent() or nil
    if state.ticker then
        state.ticker:SetParent(host)
        return
    end
    state.ticker = CreateFrame("Frame", nil, host)
    state.ticker:SetScript("OnUpdate", function(_, elapsed)
        AdvanceCycle(elapsed)
        AdvanceAuraStates(elapsed)
        ApplyDynamics(state.mock, ComputePcts(state.cycle.t))
    end)
end

function Module.Refresh(unitDB, _general)
    state.lastUnitDB = unitDB
    state.shownHealth = nil
    state.shownPower = nil

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

    if mock then
        ApplyDynamics(mock, ComputePcts(state.cycle.t))
    end
end

function Module.SetSelectedUnit(unitKey)
    if not unitKey then return end

    state.cycle.t = 0
    state.auraStates = {}
end
