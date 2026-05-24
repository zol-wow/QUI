--[[
    QUI CDM Composer Live Preview Driver

    Renders the composer's "Live Preview" pane by acquiring real CDM
    factory primitives (icons via CDMIconFactory.AcquireForPreview,
    bars via CDMBars.CreateForPreview) and walking each one through a
    time-driven cycle script. The cycle exercises hidden-by-default
    states — cooldown swipe + countdown text, stack ramps, proc glow,
    charges, animated bar fills, desaturation — so users see settings
    changes immediately as they edit a container.

    Public surface:
        ns.CDMComposerPreview.Build(gridArea)
        ns.CDMComposerPreview.Refresh(containerKey)
        ns.CDMComposerPreview.Teardown()
        ns.CDMComposerPreview.SetScale(scale)

    Invariants:
        * No game events are registered.
        * Never calls into cdm_runtime.lua.
        * Never touches the Blizzard CDM mirror (enforced by
          CDMIconFactory.AcquireForPreview skipping TryBindIconToBlizz).
        * Preview icons/bars are not pooled with runtime frames.
        * LibCustomGlow keys are scoped to "_QUIComposerPreviewGlow".
]]

local _, ns = ...

local Resolvers       = ns.CDMResolvers
local GetSpellTexture = Resolvers and Resolvers.GetSpellTexture
local GetEntryTexture = Resolvers and Resolvers.GetEntryTexture

local CDMComposerPreview = {}
ns.CDMComposerPreview = CDMComposerPreview

---------------------------------------------------------------------------
-- Driver state
---------------------------------------------------------------------------
local state = {
    gridArea     = nil,
    ticker       = nil,
    scale        = 1.5,
    previewIcons = {},   -- array of acquired icon frames
    previewBars  = {},   -- array of acquired bar frames
    iconState    = {},   -- per-icon cycle records (phase, t, peakStacks, ...)
    glowOwnerIdx = 1,    -- which icon currently owns the rotating glow
    glowOwnerT   = 0,    -- elapsed time for current glow owner
    containerKey = nil,
    containerDB  = nil,
    scriptKind   = nil,  -- "cooldown" | "aura" | "bar"
}

---------------------------------------------------------------------------
-- Preview-scoped glow helper
-- Uses LibCustomGlow directly with a scoped key so preview glows can
-- never collide with runtime glows on a same-spell icon. The runtime
-- glow key is different; preview exclusively uses "_QUIComposerPreviewGlow".
---------------------------------------------------------------------------
local PREVIEW_GLOW_KEY = "_QUIComposerPreviewGlow"

local function GetLCG()
    return LibStub and LibStub("LibCustomGlow-1.0", true) or nil
end

local function StartGlow(icon, containerDB)
    local LCG = GetLCG()
    if not LCG or not icon then return end
    local style     = containerDB and containerDB.glowStyle or "pixel"
    local color     = containerDB and containerDB.glowColor or {1, 1, 0, 1}
    local lines     = containerDB and containerDB.glowLines or 8
    local frequency = containerDB and containerDB.glowFrequency or 0.25
    local thickness = containerDB and containerDB.glowThickness or 2
    local scale     = containerDB and containerDB.glowScale or 1

    if style == "pixel" then
        LCG.PixelGlow_Start(icon, color, lines, frequency, nil, thickness, 0, 0, true, PREVIEW_GLOW_KEY)
    elseif style == "autocast" then
        LCG.AutoCastGlow_Start(icon, color, lines, frequency, scale, 0, 0, PREVIEW_GLOW_KEY)
    else
        LCG.ButtonGlow_Start(icon, color, frequency)
    end
end

local function StopGlow(icon, _containerDB)
    local LCG = GetLCG()
    if not LCG or not icon then return end
    -- Stop every style defensively — the user may have changed glowStyle
    -- mid-cycle and we don't know which one is currently active.
    if LCG.PixelGlow_Stop    then LCG.PixelGlow_Stop(icon, PREVIEW_GLOW_KEY)    end
    if LCG.AutoCastGlow_Stop then LCG.AutoCastGlow_Stop(icon, PREVIEW_GLOW_KEY) end
    if LCG.ButtonGlow_Stop   then LCG.ButtonGlow_Stop(icon)                    end
end

---------------------------------------------------------------------------
-- Cycle script tables
-- Each entry: { phase = <string>, duration = <seconds> }
-- Per-icon state tracks current phase + elapsed; advance happens in
-- OnUpdate. Phase ordering is the cycle order.
---------------------------------------------------------------------------
local COOLDOWN_PHASES = {
    { phase = "cooldown",   duration = 7   },  -- per-icon override via state.cooldownDur
    { phase = "ready_glow", duration = 1.5 },
    { phase = "charges",    duration = 3   },
    { phase = "idle",       duration = 0.5 },
}

local AURA_PHASES = {
    { phase = "applying",     duration = 0.3 },
    { phase = "stacking_up",  duration = 2   },
    { phase = "ticking_down", duration = 7   },  -- per-icon override via state.cooldownDur
    { phase = "expiring",     duration = 0.5 },
}

local BAR_PHASES = {
    { phase = "applying",  duration = 0.2 },
    { phase = "draining",  duration = 8   },  -- per-bar override via state.cooldownDur
    { phase = "expiring",  duration = 0.4 },
    { phase = "idle",      duration = 0.6 },
}

local function PhaseTable(scriptKind)
    if scriptKind == "aura" then return AURA_PHASES end
    if scriptKind == "bar"  then return BAR_PHASES  end
    return COOLDOWN_PHASES
end

local function PhaseDuration(scriptKind, phaseIdx, iconState)
    local phases = PhaseTable(scriptKind)
    local phase  = phases[phaseIdx]
    if not phase then return 1 end
    -- Long phases use per-icon randomized duration so cycles stagger.
    if phase.phase == "cooldown"
       or phase.phase == "ticking_down"
       or phase.phase == "draining" then
        return iconState.cooldownDur or phase.duration
    end
    return phase.duration
end

---------------------------------------------------------------------------
-- Per-icon cycle advance
---------------------------------------------------------------------------
local function ApplyCooldownPhase(icon, iconState, phaseName, phaseT)
    if phaseName == "cooldown" then
        -- Re-arm Cooldown only on phase entry; calling SetCooldown every
        -- frame would reset start to GetTime() each frame and freeze the
        -- swipe at frame 0.
        if icon.Cooldown and phaseT < 0.05 then
            icon.Cooldown:SetCooldown(GetTime(), iconState.cooldownDur or 7)
        end
        if icon.Icon then icon.Icon:SetDesaturated(true) end
        if icon.StackText then icon.StackText:Hide() end
    elseif phaseName == "ready_glow" then
        if icon.Cooldown then icon.Cooldown:Clear() end
        if icon.Icon then icon.Icon:SetDesaturated(false) end
        -- Glow is owned by the rotating glowOwner, not every icon.
    elseif phaseName == "charges" then
        -- Charges drain over the 3s phase: 3 → 2 → 1 → hidden. QUI renders
        -- charge count as a single number on StackText (same fontstring,
        -- different data source — see cdm_icon_renderer stackSource == "ChargeCount").
        if icon.StackText then
            local remaining = math.max(0, 3 - math.floor(phaseT))
            if remaining > 0 then
                icon.StackText:SetText(tostring(remaining))
                icon.StackText:Show()
            else
                icon.StackText:Hide()
            end
        end
    elseif phaseName == "idle" then
        if icon.Cooldown then icon.Cooldown:Clear() end
        if icon.Icon then icon.Icon:SetDesaturated(false) end
        if icon.StackText then icon.StackText:Hide() end
    end
end

local function ApplyAuraPhase(icon, iconState, phaseName, phaseT)
    if phaseName == "applying" then
        if icon.Icon then icon.Icon:SetDesaturated(false) end
        if icon.StackText then icon.StackText:Hide() end
    elseif phaseName == "stacking_up" then
        local peak = iconState.peakStacks or 1
        local stacks = math.min(peak, math.floor(phaseT / 0.4) + 1)
        if icon.StackText then
            if stacks > 1 then
                icon.StackText:SetText(tostring(stacks))
                icon.StackText:Show()
            else
                icon.StackText:Hide()
            end
        end
    elseif phaseName == "ticking_down" then
        if icon.Cooldown then
            -- Re-set the cooldown only on phase entry (phaseT near 0).
            if phaseT < 0.05 then
                icon.Cooldown:SetCooldown(GetTime(), iconState.cooldownDur or 7)
            end
        end
    elseif phaseName == "expiring" then
        if icon.Cooldown then icon.Cooldown:Clear() end
        if icon.StackText then icon.StackText:Hide() end
    end
end

local function AdvanceIcon(icon, elapsed)
    local s = state.iconState[icon]
    if not s then return end
    s.phaseIdx = s.phaseIdx or 1
    s.t = (s.t or 0) + elapsed

    local phaseDur = PhaseDuration(state.scriptKind, s.phaseIdx, s)
    if s.t >= phaseDur then
        s.t = 0
        s.phaseIdx = (s.phaseIdx % #PhaseTable(state.scriptKind)) + 1
    end

    local phaseName = PhaseTable(state.scriptKind)[s.phaseIdx].phase
    if state.scriptKind == "cooldown" then
        ApplyCooldownPhase(icon, s, phaseName, s.t)
    elseif state.scriptKind == "aura" then
        ApplyAuraPhase(icon, s, phaseName, s.t)
    end
    -- Bar advance is wired in Task 9.
end

---------------------------------------------------------------------------
-- Per-bar cycle advance
---------------------------------------------------------------------------
local function ApplyBarPhase(bar, barState, phaseName, phaseT)
    local dur = barState.cooldownDur or 8
    if phaseName == "applying" then
        if bar.StatusBar then
            bar.StatusBar:SetMinMaxValues(0, dur)
            bar.StatusBar:SetValue(dur)
        end
        if bar.DurationText then
            bar.DurationText:SetText(string.format("%.0fs", dur))
        end
    elseif phaseName == "draining" then
        local remaining = math.max(0, dur - phaseT)
        if bar.StatusBar then
            -- SetMinMaxValues is invariant during draining; only re-apply on phase entry.
            if phaseT < 0.05 then
                bar.StatusBar:SetMinMaxValues(0, dur)
            end
            bar.StatusBar:SetValue(remaining)
        end
        if bar.DurationText then
            bar.DurationText:SetText(string.format("%.1fs", remaining))
        end
    elseif phaseName == "expiring" then
        if bar.StatusBar then bar.StatusBar:SetValue(0) end
        if bar.DurationText then bar.DurationText:SetText("0.0s") end
    elseif phaseName == "idle" then
        bar:Hide()
        return
    end
    bar:Show()
end

local function AdvanceBar(bar, elapsed)
    local s = state.iconState[bar]
    if not s then return end
    s.phaseIdx = s.phaseIdx or 1
    s.t = (s.t or 0) + elapsed

    local phaseDur = PhaseDuration("bar", s.phaseIdx, s)
    if s.t >= phaseDur then
        s.t = 0
        s.phaseIdx = (s.phaseIdx % #BAR_PHASES) + 1
    end

    local phaseName = BAR_PHASES[s.phaseIdx].phase
    ApplyBarPhase(bar, s, phaseName, s.t)
end

---------------------------------------------------------------------------
-- Glow-owner rotation
-- Only one icon at a time has the proc glow active. Owner advances every
-- 1.5s. Bar containers do not participate in glow rotation.
---------------------------------------------------------------------------
local function AdvanceGlowOwner(elapsed)
    if state.scriptKind == "bar" then return end
    if #state.previewIcons == 0 then return end
    state.glowOwnerT = state.glowOwnerT + elapsed
    if state.glowOwnerT < 1.5 then return end
    state.glowOwnerT = 0

    -- Stop glow on previous owner
    local prev = state.previewIcons[state.glowOwnerIdx]
    if prev then StopGlow(prev, state.containerDB) end

    -- Advance index, start glow on new owner
    state.glowOwnerIdx = (state.glowOwnerIdx % #state.previewIcons) + 1
    local next = state.previewIcons[state.glowOwnerIdx]
    if next then StartGlow(next, state.containerDB) end
end

---------------------------------------------------------------------------
-- Container DB resolution helpers
---------------------------------------------------------------------------
local function GetContainerDB(containerKey)
    -- Composer.lua already exposes this; the driver uses QUI_GetCDMContainerDB
    -- as a thin shim so the driver does not need composer.lua loaded at parse
    -- time. Composer.lua publishes this global as part of Task 10.
    local getter = _G.QUI_GetCDMContainerDB
    return getter and getter(containerKey) or nil
end

local function ResolveContainerType(containerDB)
    -- Resolution mirrors composer.lua's existing ResolveContainerType helper.
    if not containerDB then return "cooldown" end
    if containerDB.containerType == "auraBar" then return "auraBar" end
    if containerDB.containerType == "customBar" then
        if containerDB.shape == "bar" then return "auraBar" end
        return "customBar"
    end
    if containerDB.containerType == "aura" then return "aura" end
    return "cooldown"
end

local function ResolveScriptKind(containerType)
    if containerType == "auraBar" then return "bar"      end
    if containerType == "aura"    then return "aura"     end
    return "cooldown"  -- includes "cooldown" and "customBar" (icon shape)
end

---------------------------------------------------------------------------
-- Icon refresh path
---------------------------------------------------------------------------
local function RefreshIcons(containerKey, containerDB)
    local entries = containerDB.containerType == "customBar"
        and containerDB.entries
        or containerDB.ownedSpells
    if type(entries) ~= "table" then return end

    -- Acquire / re-use icons one-to-one with entries
    for i, entry in ipairs(entries) do
        local icon = state.previewIcons[i]
        if not icon then
            icon = ns.CDMIconFactory.AcquireForPreview(state.gridArea, entry)
            state.previewIcons[i] = icon
        else
            -- Re-bind spell entry on existing icon (entry list edits)
            icon._spellEntry = entry
            if entry then
                local texID
                if entry.type and GetEntryTexture then
                    texID = GetEntryTexture(entry)
                elseif GetSpellTexture then
                    texID = GetSpellTexture(entry.overrideSpellID or entry.spellID)
                end
                if texID and icon.Icon then icon.Icon:SetTexture(texID) end
            end
        end
        icon:Show()

        -- Initialize per-icon cycle state if missing. Phase offset is
        -- randomized so cycles visibly stagger across icons.
        if not state.iconState[icon] then
            state.iconState[icon] = {
                t            = math.random() * 5,   -- random initial offset
                peakStacks   = math.random(1, 5),
                cooldownDur  = 5 + math.random() * 5,  -- 5-10s
                glowActive   = false,
            }
        end
    end

    -- Release extras (entries removed by user)
    for i = #entries + 1, #state.previewIcons do
        local icon = state.previewIcons[i]
        if icon then
            state.iconState[icon] = nil
            ns.CDMIconFactory.ReleaseForPreview(icon)
            state.previewIcons[i] = nil
        end
    end

    -- Clamp glow owner if entry shrink left it past the new icon count
    if state.glowOwnerIdx > #state.previewIcons then
        state.glowOwnerIdx = 1
        state.glowOwnerT   = 0
    end

    -- Layout: defer to composer.lua's existing icon layout function which
    -- knows about rows, growth direction, customBar shape, etc.
    if _G.QUI_LayoutCDMPreviewIcons then
        _G.QUI_LayoutCDMPreviewIcons(state.previewIcons, containerKey, state.scale)
    end

    -- Styling: defer to composer.lua's existing ApplyRowStyle path which
    -- reads the container DB and writes font sizes, durations, stacks, etc.
    if _G.QUI_StyleCDMPreviewIcons then
        _G.QUI_StyleCDMPreviewIcons(state.previewIcons, containerKey, state.scale)
    end
end

---------------------------------------------------------------------------
-- Bar refresh path
---------------------------------------------------------------------------
local function RefreshBars(_containerKey, containerDB)
    local entries = containerDB.containerType == "customBar"
        and containerDB.entries
        or containerDB.ownedSpells
    if type(entries) ~= "table" then return end

    local barWidth = (containerDB.barWidth or 215) * state.scale * 0.5

    for i, entry in ipairs(entries) do
        local bar = state.previewBars[i]
        if not bar then
            bar = ns.CDMBars.CreateForPreview(state.gridArea)
            state.previewBars[i] = bar
        end
        -- Bind the entry so ConfigureBar can read spell-level overrides.
        bar._spellEntry = entry
        bar._spellID    = entry and (entry.overrideSpellID or entry.spellID) or nil

        -- Force-active before ConfigureBar: the runtime only flips _active
        -- when a live aura/cooldown is detected, but the preview is a pure
        -- mockup with no aura source. Without this, ConfigureBar applies
        -- the trackedBar default inactiveMode="hide" → SetAlpha(0) and the
        -- entire preview is invisible.
        bar._active = true

        -- Style via the real production styling path. ConfigureBar reads
        -- the container's settings table (barHeight, barColor, bgColor,
        -- texture, font sizes, hideIcon, etc.).
        ns.CDMBars.ConfigureBar(bar, containerDB, barWidth)

        -- ConfigureBar is content-agnostic — it sizes/styles the icon and
        -- text frames but does not bind spell-specific image or label. The
        -- runtime sets these in its UpdateOwnedBarAura path which the
        -- preview deliberately bypasses, so paint them here from the entry.
        if entry and bar.IconTexture then
            local texID
            if entry.type and GetEntryTexture then
                texID = GetEntryTexture(entry)
            elseif GetSpellTexture then
                texID = GetSpellTexture(entry.overrideSpellID or entry.spellID)
            end
            if texID then bar.IconTexture:SetTexture(texID) end
        end
        if entry and bar.NameText then
            local nameGetter = _G.QUI_GetCDMEntryName
            local name = nameGetter and nameGetter(entry) or nil
            bar.NameText:SetText(name or "")
        end

        bar:Show()

        -- Initialize per-bar cycle state.
        if not state.iconState[bar] then
            state.iconState[bar] = {
                t           = math.random() * 8,
                cooldownDur = 6 + math.random() * 6,  -- 6-12s
            }
        end
    end

    -- Release extras
    for i = #entries + 1, #state.previewBars do
        local bar = state.previewBars[i]
        if bar then
            state.iconState[bar] = nil
            bar:Hide()
            bar:SetParent(nil)
            state.previewBars[i] = nil
        end
    end

    -- Layout the stack (vertical, centered, optional growUp).
    if _G.QUI_LayoutCDMPreviewBars then
        _G.QUI_LayoutCDMPreviewBars(state.previewBars, containerDB, state.scale)
    end
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------

function CDMComposerPreview.Build(gridArea)
    if state.ticker then return end  -- idempotent
    state.gridArea = gridArea
    state.ticker = CreateFrame("Frame", nil, gridArea)
    state.ticker:SetScript("OnUpdate", function(_, elapsed)
        if not state.containerDB then return end
        if state.scriptKind == "cooldown" or state.scriptKind == "aura" then
            for _, icon in ipairs(state.previewIcons) do
                AdvanceIcon(icon, elapsed)
            end
            AdvanceGlowOwner(elapsed)
        elseif state.scriptKind == "bar" then
            for _, bar in ipairs(state.previewBars) do
                AdvanceBar(bar, elapsed)
            end
        end
    end)
end

function CDMComposerPreview.Refresh(containerKey)
    state.containerKey = containerKey
    state.containerDB  = GetContainerDB(containerKey)
    if not state.containerDB then return end

    local containerType = ResolveContainerType(state.containerDB)
    state.scriptKind = ResolveScriptKind(containerType)

    if containerType == "auraBar" then
        RefreshBars(containerKey, state.containerDB)
        return
    end

    RefreshIcons(containerKey, state.containerDB)
end

function CDMComposerPreview.Teardown()
    for _, icon in ipairs(state.previewIcons) do
        if icon then
            StopGlow(icon, state.containerDB)
            ns.CDMIconFactory.ReleaseForPreview(icon)
        end
    end
    for _, bar in ipairs(state.previewBars) do
        if bar then bar:Hide(); bar:SetParent(nil) end
    end
    state.previewIcons = {}
    state.previewBars  = {}
    state.iconState    = {}
    state.glowOwnerIdx = 1
    state.glowOwnerT   = 0
    state.containerKey = nil
    state.containerDB  = nil
    state.scriptKind   = nil
end

function CDMComposerPreview.SetScale(scale)
    state.scale = scale or 1.5
end
