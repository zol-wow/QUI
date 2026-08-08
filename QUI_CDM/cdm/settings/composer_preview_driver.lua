local _, ns = ...

local Resolvers       = ns.CDMResolvers
local GetSpellTexture = Resolvers and Resolvers.GetSpellTexture
local GetEntryTexture = Resolvers and Resolvers.GetEntryTexture

local function ResolveEntryTexture(entry)
    if entry.type and GetEntryTexture then
        return GetEntryTexture(entry)
    elseif GetSpellTexture then
        return GetSpellTexture(entry.overrideSpellID or entry.spellID)
    end
    return nil
end

local CDMComposerPreview = {}
ns.CDMComposerPreview = CDMComposerPreview

local state = {
    gridArea     = nil,
    ticker       = nil,
    scale        = 1.5,
    previewIcons = {},
    previewBars  = {},
    iconState    = {},
    glowOwnerIdx = 1,
    glowOwnerT   = 0,
    containerKey = nil,
    containerDB  = nil,
    scriptKind   = nil,
}

local PREVIEW_GLOW_KEY   = "_QUIComposerPreviewGlow"
local PREVIEW_ACTIVE_KEY = "_QUIComposerPreviewActive"
local PREVIEW_HL_KEY     = "_QUIComposerPreviewHL"

local function ContainerKeyToViewerType(containerKey)
    if containerKey == "essential" then return "Essential" end
    if containerKey == "utility"   then return "Utility"   end
    return containerKey
end

local function GlowSourceAllows()
    local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
    local source = profile and profile.ncdm and profile.ncdm.glowSource or "QUI"
    return source ~= "Off"
end

local function StartGlow(icon, containerKey)
    local Glows = ns._OwnedGlows
    if not icon or not Glows or not Glows.ApplyGlowWithKey or not Glows.GetViewerSettings then
        return
    end
    if not GlowSourceAllows() then return end
    local vs = Glows.GetViewerSettings(ContainerKeyToViewerType(containerKey))
    if not vs then return end
    Glows.ApplyGlowWithKey(icon, vs, PREVIEW_GLOW_KEY)
end

local function StopProcGlow(icon)
    local Glows = ns._OwnedGlows
    if icon and Glows and Glows.StopGlowWithKey then
        Glows.StopGlowWithKey(icon, PREVIEW_GLOW_KEY)
    end
end

local function StopGlow(icon)
    local Glows = ns._OwnedGlows
    if not icon or not Glows or not Glows.StopGlowWithKey then return end
    Glows.StopGlowWithKey(icon, PREVIEW_GLOW_KEY)
    Glows.StopGlowWithKey(icon, PREVIEW_ACTIVE_KEY)
    Glows.StopGlowWithKey(icon, PREVIEW_HL_KEY)
end

local function StartActiveGlow(icon)
    local db = state.containerDB
    local Glows = ns._OwnedGlows
    if not icon or not db or not Glows or not Glows.ApplyGlowWithKey then return end
    if not db.activeGlowEnabled then return end
    Glows.ApplyGlowWithKey(icon, {
        glowType  = db.activeGlowType or "Pixel Glow",
        color     = db.activeGlowColor or {0.95, 0.95, 0.32, 1},
        lines     = db.activeGlowLines or 8,
        frequency = db.activeGlowFrequency or 0.25,
        thickness = db.activeGlowThickness or 2,
        scale     = db.activeGlowScale or 1,
    }, PREVIEW_ACTIVE_KEY)
end

local function StopActiveGlow(icon)
    local Glows = ns._OwnedGlows
    if icon and Glows and Glows.StopGlowWithKey then
        Glows.StopGlowWithKey(icon, PREVIEW_ACTIVE_KEY)
    end
end

local function StartHighlighter(icon)
    local Glows = ns._OwnedGlows
    local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
    local hl = profile and profile.cooldownHighlighter
    if not icon or not hl or not hl.enabled or not Glows or not Glows.ApplyGlowWithKey then
        return
    end
    if not GlowSourceAllows() then return end
    Glows.ApplyGlowWithKey(icon, {
        glowType  = hl.glowType or "Pixel Glow",
        color     = hl.color or {1, 1, 1, 0.8},
        lines     = hl.lines or 8,
        frequency = hl.frequency or 0.25,
        thickness = hl.thickness or 1,
        scale     = hl.scale or 1,
    }, PREVIEW_HL_KEY)
end

local function StopHighlighter(icon)
    local Glows = ns._OwnedGlows
    if icon and Glows and Glows.StopGlowWithKey then
        Glows.StopGlowWithKey(icon, PREVIEW_HL_KEY)
    end
end

local function HighlighterDuration()
    local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
    local hl = profile and profile.cooldownHighlighter
    return (hl and hl.duration) or 0.4
end

local function ApplyPreviewSwipe(icon, mode)
    if not icon or not icon.Cooldown then return end
    local resolve = ns._CDM_ResolvePreviewSwipe
    local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
    local settings = profile and profile.cooldownSwipe
    if not resolve or not settings then return end
    local show, r, g, b, a = resolve(settings, mode)
    icon.Cooldown:SetDrawSwipe(show and true or false)
    icon.Cooldown:SetDrawEdge(show and true or false)
    if show then
        icon.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    end
    icon.Cooldown:SetSwipeColor(r, g, b, a)
end

local COOLDOWN_PHASES = {
    { phase = "cooldown",   duration = 7   },
    { phase = "ready_glow", duration = 1.5 },
    { phase = "charges",    duration = 3   },
    { phase = "idle",       duration = 0.5 },
}

local AURA_PHASES = {
    { phase = "applying",     duration = 0.3 },
    { phase = "stacking_up",  duration = 2   },
    { phase = "ticking_down", duration = 7   },
    { phase = "expiring",     duration = 0.5 },
}

local BAR_PHASES = {
    { phase = "applying",  duration = 0.2 },
    { phase = "draining",  duration = 8   },
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
    if phase.phase == "cooldown"
       or phase.phase == "ticking_down"
       or phase.phase == "draining" then
        return iconState.cooldownDur or phase.duration
    end
    return phase.duration
end

local function ApplyCooldownPhase(icon, iconState, phaseName, phaseT)
    if phaseName == "cooldown" then
        if icon.Cooldown and phaseT < 0.05 then
            icon.Cooldown:SetCooldown(GetTime(), iconState.cooldownDur or 7)
            ApplyPreviewSwipe(icon, "cooldown")
        end
        if icon.Icon then icon.Icon:SetDesaturated(true) end
        if icon.StackText then icon.StackText:Hide() end
        StopActiveGlow(icon)
        if phaseT <= HighlighterDuration() then
            if not iconState.hlActive then
                StartHighlighter(icon)
                iconState.hlActive = true
            end
        elseif iconState.hlActive then
            StopHighlighter(icon)
            iconState.hlActive = false
        end
    elseif phaseName == "ready_glow" then
        if icon.Cooldown then icon.Cooldown:Clear() end
        if icon.Icon then icon.Icon:SetDesaturated(false) end
        if iconState.hlActive then
            StopHighlighter(icon)
            iconState.hlActive = false
        end
        StartActiveGlow(icon)
    elseif phaseName == "charges" then
        StopActiveGlow(icon)
        if icon.StackText then
            local remaining = math.max(0, 3 - math.floor(phaseT / 0.75))
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
        StopActiveGlow(icon)
        if iconState.hlActive then
            StopHighlighter(icon)
            iconState.hlActive = false
        end
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
            if phaseT < 0.05 then
                icon.Cooldown:SetCooldown(GetTime(), iconState.cooldownDur or 7)
                ApplyPreviewSwipe(icon, "aura")
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
end

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

local function AdvanceGlowOwner(elapsed)
    if state.scriptKind == "bar" then return end
    if #state.previewIcons == 0 then return end
    state.glowOwnerT = state.glowOwnerT + elapsed
    if state.glowOwnerT < 1.5 then return end
    state.glowOwnerT = 0

    local prev = state.previewIcons[state.glowOwnerIdx]
    if prev then StopProcGlow(prev) end

    state.glowOwnerIdx = (state.glowOwnerIdx % #state.previewIcons) + 1
    local next = state.previewIcons[state.glowOwnerIdx]
    if next then StartGlow(next, state.containerKey) end
end

local function GetContainerDB(containerKey)
    local getter = _G.QUI_GetCDMContainerDB
    return getter and getter(containerKey) or nil
end

local function GetPreviewEntries(containerKey, containerDB)
    local getter = _G.QUI_GetCDMPreviewEntries
    if getter then
        local entries = getter(containerKey, containerDB)
        if type(entries) == "table" then
            return entries
        end
    end
    return containerDB and (
        containerDB.containerType == "customBar"
            and containerDB.entries
            or containerDB.ownedSpells
    ) or nil
end

local function ResolveContainerType(containerDB)
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
    return "cooldown"
end

local iconPool = {}
local barPool = {}

local function ReleasePreviewIcon(icon)
    StopGlow(icon)
    state.iconState[icon] = nil
    ns.CDMIconFactory.ReleaseForPreview(icon)
    iconPool[#iconPool + 1] = icon
end

local function AcquirePreviewIcon(entry)
    local icon = table.remove(iconPool)
    if not icon then
        return ns.CDMIconFactory.AcquireForPreview(state.gridArea, entry)
    end
    icon:SetParent(state.gridArea)
    icon._spellEntry = entry
    if icon.Icon then
        icon.Icon:SetDesaturated(false)
        icon.Icon:SetVertexColor(1, 1, 1, 1)
        if entry then
            local texID = ResolveEntryTexture(entry)
            if texID then icon.Icon:SetTexture(texID) end
        end
    end
    return icon
end

local function ReleasePreviewBar(bar)
    state.iconState[bar] = nil
    bar:Hide()
    bar:SetParent(nil)
    barPool[#barPool + 1] = bar
end

local function AcquirePreviewBar()
    local bar = table.remove(barPool)
    if bar then
        bar:SetParent(state.gridArea)
        return bar
    end
    return ns.CDMBars.CreateForPreview(state.gridArea)
end

local function RefreshIcons(containerKey, containerDB)
    local entries = GetPreviewEntries(containerKey, containerDB)
    if type(entries) ~= "table" then return end

    for i, entry in ipairs(entries) do
        local icon = state.previewIcons[i]
        if not icon then
            icon = AcquirePreviewIcon(entry)
            state.previewIcons[i] = icon
        else
            icon._spellEntry = entry
            if entry then
                local texID = ResolveEntryTexture(entry)
                if texID and icon.Icon then icon.Icon:SetTexture(texID) end
            end
        end
        icon:Show()

        if not state.iconState[icon] then
            state.iconState[icon] = {
                t            = math.random() * 5,
                peakStacks   = math.random(1, 5),
                cooldownDur  = 5 + math.random() * 5,
                glowActive   = false,
            }
        end
    end

    for i = #entries + 1, #state.previewIcons do
        local icon = state.previewIcons[i]
        if icon then
            ReleasePreviewIcon(icon)
            state.previewIcons[i] = nil
        end
    end

    if state.glowOwnerIdx > #state.previewIcons then
        state.glowOwnerIdx = 1
        state.glowOwnerT   = 0
    end

    if _G.QUI_LayoutCDMPreviewIcons then
        _G.QUI_LayoutCDMPreviewIcons(state.previewIcons, containerKey, state.scale)
    end

    if _G.QUI_StyleCDMPreviewIcons then
        _G.QUI_StyleCDMPreviewIcons(state.previewIcons, containerKey, state.scale)
    end
end

local function RefreshBars(_containerKey, containerDB)
    local entries = GetPreviewEntries(_containerKey, containerDB)
    if type(entries) ~= "table" then return end

    local barWidth = (containerDB.barWidth or 215) * state.scale * 0.5

    for i, entry in ipairs(entries) do
        local bar = state.previewBars[i]
        if not bar then
            bar = AcquirePreviewBar()
            state.previewBars[i] = bar
        end
        bar._spellEntry = entry
        bar._spellID    = entry and (entry.overrideSpellID or entry.spellID) or nil

        bar._active = true

        ns.CDMBars.ConfigureBar(bar, containerDB, barWidth)

        if entry and bar.IconTexture then
            local texID = ResolveEntryTexture(entry)
            if texID then bar.IconTexture:SetTexture(texID) end
        end
        if entry and bar.NameText then
            local nameGetter = _G.QUI_GetCDMEntryName
            local name = nameGetter and nameGetter(entry) or nil
            bar.NameText:SetText(name or "")
        end

        bar:Show()

        if not state.iconState[bar] then
            state.iconState[bar] = {
                t           = math.random() * 8,
                cooldownDur = 6 + math.random() * 6,
            }
        end
    end

    for i = #entries + 1, #state.previewBars do
        local bar = state.previewBars[i]
        if bar then
            ReleasePreviewBar(bar)
            state.previewBars[i] = nil
        end
    end

    if _G.QUI_LayoutCDMPreviewBars then
        _G.QUI_LayoutCDMPreviewBars(state.previewBars, containerDB, state.scale, state.containerKey)
    end
end

function CDMComposerPreview.Build(gridArea)
    if state.ticker then
        state.gridArea = gridArea
        state.ticker:SetParent(gridArea)
        return
    end
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

local function ClearPreviewIcons()
    for _, icon in ipairs(state.previewIcons) do
        if icon then
            ReleasePreviewIcon(icon)
        end
    end
    state.previewIcons = {}
    state.glowOwnerIdx = 1
    state.glowOwnerT   = 0
end

local function ClearPreviewBars()
    for _, bar in ipairs(state.previewBars) do
        if bar then
            ReleasePreviewBar(bar)
        end
    end
    state.previewBars = {}
end

function CDMComposerPreview.Refresh(containerKey)
    state.containerKey = containerKey
    state.containerDB  = GetContainerDB(containerKey)
    if not state.containerDB then return end

    local containerType = ResolveContainerType(state.containerDB)
    state.scriptKind = ResolveScriptKind(containerType)

    if containerType == "auraBar" then
        ClearPreviewIcons()
        RefreshBars(containerKey, state.containerDB)
        return
    end

    ClearPreviewBars()
    RefreshIcons(containerKey, state.containerDB)
end

function CDMComposerPreview.Teardown()
    ClearPreviewIcons()
    ClearPreviewBars()
    state.iconState    = {}
    state.containerKey = nil
    state.containerDB  = nil
    state.scriptKind   = nil
end

function CDMComposerPreview.SetScale(scale)
    state.scale = scale or 1.5
end

function CDMComposerPreview.GetContentFrames()
    if state.scriptKind == "bar" then
        return state.previewBars
    end
    return state.previewIcons
end

function CDMComposerPreview.Relayout()
    if state.scriptKind == "bar" then
        if _G.QUI_LayoutCDMPreviewBars and state.containerDB then
            _G.QUI_LayoutCDMPreviewBars(
                state.previewBars,
                state.containerDB,
                state.scale,
                state.containerKey
            )
        end
    elseif _G.QUI_LayoutCDMPreviewIcons and state.containerKey then
        _G.QUI_LayoutCDMPreviewIcons(
            state.previewIcons,
            state.containerKey,
            state.scale
        )
    end
end
