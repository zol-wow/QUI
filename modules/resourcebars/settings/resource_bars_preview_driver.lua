--[[
    QUI Resource Bars — settings-tile preview driver

    Drives the dynamic content of the Resource Bars settings tile preview
    pane. Owns the cycle state, OnUpdate ticker, preview chrome (background,
    border, "PREVIEW" label), the two mock-bar sections (primary +
    secondary), the per-tick StatusBar:SetValue + value-text writes, and
    the migrated preview-only helpers (MakeMockBar, ApplyPreviewTicks,
    ApplyPreviewSectionLayout, GetPreviewBarColor, GetPreviewBgColor,
    MockValueText, GetPreviewTextConfig, GetPreviewPowerMax,
    GetPreviewDisplaySize, MapPreviewMetric).

    Public surface:
        ns.QUI_ResourceBarsPreview.Build(host)
        ns.QUI_ResourceBarsPreview.Refresh()
        ns.QUI_ResourceBarsPreview.Teardown()
        ns.QUI_ResourceBarsPreview.GetCurrentPcts()

    Invariants:
        * No game events are registered. Cycle is time-driven via OnUpdate.
        * Driver never touches real (runtime) resource bars. Mock-only.
        * Shared runtime helpers (GetBarTexture, ShouldSwapBars, etc.) are
          imported from ns.QUI_ResourceBars_Internal (exported by
          resourcebars.lua in T2). Lookups happen lazily (inside Build /
          Refresh) so load-order between this file and resourcebars.lua
          doesn't matter.
]]

local _, ns = ...

-- Lazy lookups for ns.QUI_ResourceBars_Internal (populated in T2).
-- The actual lookup happens inside Build/Refresh, NOT at file-load time,
-- because resourcebars.lua may load before or after this file depending
-- on TOC ordering.
local function GetInternal()
    return ns.QUI_ResourceBars_Internal
end

-- Local aliases for built-ins used by the migrated helpers.
local math_max, math_min, math_floor = math.max, math.min, math.floor
local string_format = string.format

local Module = {}
ns.QUI_ResourceBarsPreview = Module

---------------------------------------------------------------------------
-- Cycle constants
-- A single 10s loop. Both bars use the same t with a 2s phase offset
-- between primary and secondary so the bars are visibly out of sync.
--
-- Primary:    drain 0–4 (1.0→0.0), refill 4–6 (0.0→1.0), idle 6–10 (1.0)
-- Secondary:  idle 0–2 (1.0), drain 2–6 (1.0→0.0), refill 6–8 (0.0→1.0),
--             idle 8–10 (1.0)
---------------------------------------------------------------------------
local CYCLE_LENGTH = 10

---------------------------------------------------------------------------
-- Driver state
---------------------------------------------------------------------------
local state = {
    host       = nil,
    ticker     = nil,
    cycle      = { t = 0 },
    previewRef = nil,   -- { pv, primary, secondary, fpath } after Build
}

---------------------------------------------------------------------------
-- Cycle math
---------------------------------------------------------------------------

local function ComputePcts(t)
    -- Primary
    local primaryPct
    if t < 4 then
        primaryPct = 1.0 - t / 4
    elseif t < 6 then
        primaryPct = (t - 4) / 2
    else
        primaryPct = 1.0
    end

    -- Secondary (phase-offset by +2s)
    local secondaryPct
    if t < 2 then
        secondaryPct = 1.0
    elseif t < 6 then
        secondaryPct = 1.0 - (t - 2) / 4
    elseif t < 8 then
        secondaryPct = (t - 6) / 2
    else
        secondaryPct = 1.0
    end

    return primaryPct, secondaryPct
end

local function AdvanceCycle(elapsed)
    state.cycle.t = (state.cycle.t + elapsed) % CYCLE_LENGTH
end

---------------------------------------------------------------------------
-- Preview constants (migrated from resourcebars.lua in T4)
---------------------------------------------------------------------------

-- Enum.PowerType is a WoW-runtime global; headless tooling (search-cache
-- generator, profile tests) loads this file without it, so guard every
-- load-time reference.
local POWER_DISPLAY_NAMES = {
    ["STAGGER"] = "Stagger",
    ["SOUL"]    = "Soul Fragments",
}
local PREVIEW_POWER_MAX_FALLBACKS = {}
if Enum and Enum.PowerType then
    POWER_DISPLAY_NAMES[Enum.PowerType.Mana]            = "Mana"
    POWER_DISPLAY_NAMES[Enum.PowerType.Rage]            = "Rage"
    POWER_DISPLAY_NAMES[Enum.PowerType.Focus]           = "Focus"
    POWER_DISPLAY_NAMES[Enum.PowerType.Energy]          = "Energy"
    POWER_DISPLAY_NAMES[Enum.PowerType.RunicPower]      = "Runic Power"
    POWER_DISPLAY_NAMES[Enum.PowerType.SoulShards]      = "Soul Shards"
    POWER_DISPLAY_NAMES[Enum.PowerType.LunarPower]      = "Lunar Power"
    POWER_DISPLAY_NAMES[Enum.PowerType.HolyPower]       = "Holy Power"
    POWER_DISPLAY_NAMES[Enum.PowerType.Maelstrom]       = "Maelstrom"
    POWER_DISPLAY_NAMES[Enum.PowerType.Chi]             = "Chi"
    POWER_DISPLAY_NAMES[Enum.PowerType.Insanity]        = "Insanity"
    POWER_DISPLAY_NAMES[Enum.PowerType.ArcaneCharges]   = "Arcane Charges"
    POWER_DISPLAY_NAMES[Enum.PowerType.Runes]           = "Runes"
    POWER_DISPLAY_NAMES[Enum.PowerType.Fury]            = "Fury"
    POWER_DISPLAY_NAMES[Enum.PowerType.Essence]         = "Essence"
    POWER_DISPLAY_NAMES[Enum.PowerType.ComboPoints]     = "Combo Points"
    POWER_DISPLAY_NAMES[Enum.PowerType.MaelstromWeapon] = "Maelstrom Weapon"
    POWER_DISPLAY_NAMES[Enum.PowerType.TipOfTheSpear]   = "Tip of the Spear"
    POWER_DISPLAY_NAMES[Enum.PowerType.Whirlwind]       = "Whirlwind"
    if Enum.PowerType.VengSoulFragments then
        POWER_DISPLAY_NAMES[Enum.PowerType.VengSoulFragments] = "Soul Fragments"
    end

    PREVIEW_POWER_MAX_FALLBACKS[Enum.PowerType.MaelstromWeapon]   = 10
    PREVIEW_POWER_MAX_FALLBACKS[Enum.PowerType.Whirlwind]         = 4
    PREVIEW_POWER_MAX_FALLBACKS[Enum.PowerType.TipOfTheSpear]     = 3
    if Enum.PowerType.VengSoulFragments then
        PREVIEW_POWER_MAX_FALLBACKS[Enum.PowerType.VengSoulFragments] = 6
    end
end

local BAR_PAD_X                     = 12
local PREVIEW_LABEL_GAP             = 2
local PREVIEW_SECTION_GAP           = 8
local PREVIEW_MIN_HORIZONTAL_LENGTH = 80
local PREVIEW_MIN_VERTICAL_LENGTH   = 20
local PREVIEW_MIN_THICKNESS         = 8
local PREVIEW_MAX_THICKNESS         = 22

---------------------------------------------------------------------------
-- Preview helpers (migrated from resourcebars.lua in T4)
---------------------------------------------------------------------------

local function GetPreviewPowerMax(resource)
    if type(resource) ~= "number" then return 0 end

    local fallback = PREVIEW_POWER_MAX_FALLBACKS[resource]
    if fallback then return fallback end

    local ok, maxValue = pcall(UnitPowerMax, "player", resource)
    if not ok then return 0 end
    local Helpers = ns.Helpers
    if Helpers and Helpers.SafeToNumber then
        return Helpers.SafeToNumber(maxValue, 0)
    end
    return tonumber(maxValue) or 0
end

local function MapPreviewMetric(value, minValue, maxValue, minPixels, maxPixels)
    value = tonumber(value) or minValue
    value = math_max(minValue, math_min(maxValue, value))

    if maxValue <= minValue or maxPixels <= minPixels then
        return minPixels
    end

    local pct = (value - minValue) / (maxValue - minValue)
    return math_floor(minPixels + ((maxPixels - minPixels) * pct) + 0.5)
end

local function GetPreviewTextConfig(cfg, isSecondary)
    local Internal = GetInternal()
    if isSecondary and Internal and Internal.GetSecondaryTextConfig then
        return Internal.GetSecondaryTextConfig(cfg)
    end
    return cfg
end

local function GetPreviewDisplaySize(cfg, pv, visibleCount)
    local orientation = cfg and cfg.orientation or "HORIZONTAL"
    local isVertical = orientation == "VERTICAL"
    local previewWidth = pv and pv.GetWidth and pv:GetWidth() or 280
    local maxHorizontalLength = math_max(PREVIEW_MIN_HORIZONTAL_LENGTH, previewWidth - (BAR_PAD_X * 2))
    local maxVerticalLength = visibleCount > 1 and 30 or 42
    local maxThickness = visibleCount > 1 and 18 or PREVIEW_MAX_THICKNESS

    local displayLength = MapPreviewMetric(cfg and cfg.width or 200, 50, 600,
        isVertical and PREVIEW_MIN_VERTICAL_LENGTH or PREVIEW_MIN_HORIZONTAL_LENGTH,
        isVertical and maxVerticalLength or maxHorizontalLength)
    local displayThickness = MapPreviewMetric(cfg and cfg.height or 8, 2, 40,
        PREVIEW_MIN_THICKNESS, maxThickness)

    if isVertical then
        return displayThickness, displayLength, true
    end

    return displayLength, displayThickness, false
end

local function GetPreviewBarColor(cfg, resource)
    local Internal = GetInternal()
    local mode = cfg and cfg.colorMode or "power"
    if mode == "custom" and cfg and cfg.customColor then
        local c = cfg.customColor
        return (c[1] or c.r or 0.2), (c[2] or c.g or 0.5), (c[3] or c.b or 1.0)
    elseif mode == "class" then
        local _, class = UnitClass("player")
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if cc then return cc.r, cc.g, cc.b end
    end
    local col = resource and Internal and Internal.GetResourceColor
        and Internal.GetResourceColor(resource)
    if col then return col.r, col.g, col.b end
    return 0.2, 0.5, 1.0
end

local function ApplyPreviewTicks(section, cfg, resource)
    section.ticks = section.ticks or {}
    for _, t in ipairs(section.ticks) do t:Hide() end
    if not cfg or not cfg.showTicks then return end
    local Internal = GetInternal()
    local tickedPowerTypes = Internal and Internal.tickedPowerTypes
    if type(resource) ~= "number" or not tickedPowerTypes or not tickedPowerTypes[resource] then return end

    local max = GetPreviewPowerMax(resource)
    if max < 2 then return end

    local bar = section.bar
    local width, height = bar:GetWidth(), bar:GetHeight()
    if width <= 0 or height <= 0 then return end

    local thickness = math_max(1, cfg.tickThickness or 1)
    local tc = cfg.tickColor or { 0, 0, 0, 1 }
    local isVertical = (cfg and cfg.orientation) == "VERTICAL"

    for i = 1, max - 1 do
        local tick = section.ticks[i]
        if not tick then
            tick = bar:CreateTexture(nil, "OVERLAY")
            section.ticks[i] = tick
        end
        tick:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 1)
        tick:ClearAllPoints()
        if isVertical then
            local y = (i / max) * height
            tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, y - (thickness / 2))
            tick:SetSize(width, thickness)
        else
            local x = (i / max) * width
            tick:SetPoint("LEFT", bar, "LEFT", x - (thickness / 2), 0)
            tick:SetSize(thickness, height)
        end
        tick:Show()
    end
end

local function GetPreviewBgColor(cfg)
    local bg = cfg and cfg.bgColor
    if bg then
        return (bg[1] or bg.r or 0), (bg[2] or bg.g or 0), (bg[3] or bg.b or 0), (bg[4] or bg.a or 0.4)
    end
    return 0, 0, 0, 0.4
end

local function MockValueText(cfg, textCfg, pct, resource)
    local Internal = GetInternal()
    local fragmentedPowerTypes = Internal and Internal.fragmentedPowerTypes
    if type(resource) == "number" and fragmentedPowerTypes and fragmentedPowerTypes[resource] then
        if cfg and cfg.showFragmentedPowerBarText == false then
            return ""
        end
        local maxValue = GetPreviewPowerMax(resource)
        if maxValue <= 0 then
            maxValue = 5
        end
        local current = math_max(1, math_floor((pct * maxValue) + 0.5))
        return string_format("%d / %d", current, maxValue)
    end

    if not textCfg or not textCfg.showText then return "" end
    if textCfg.showPercent then
        local v = math_floor(pct * 100)
        return textCfg.hidePercentSymbol and tostring(v) or (v .. "%")
    end
    return math_floor(pct * 100000)  -- fake raw value
end

local function MakeMockBar(parent, fpath)
    local section = CreateFrame("Frame", nil, parent)

    local lbl = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if fpath then lbl:SetFont(fpath, 9, "") end
    lbl:SetTextColor(1, 1, 1, 0.75)
    lbl:SetPoint("TOP", section, "TOP", 0, 0)
    section.lbl = lbl

    local barFrame = CreateFrame("Frame", nil, section)
    barFrame:SetPoint("TOP", lbl, "BOTTOM", 0, -PREVIEW_LABEL_GAP)
    section.barFrame = barFrame

    local bg = barFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(barFrame)
    bg:SetColorTexture(0, 0, 0, 0.4)
    section.bg = bg

    local bar = CreateFrame("StatusBar", nil, barFrame)
    bar:SetAllPoints(barFrame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.7)
    section.bar = bar

    local UIKit = ns.UIKit
    if UIKit and UIKit.CreateBorderLines then
        UIKit.CreateBorderLines(barFrame)
    end

    local val = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if fpath then val:SetFont(fpath, 9, "") end
    val:SetTextColor(1, 1, 1, 0.9)
    val:SetPoint("CENTER", barFrame, "CENTER", 0, 0)
    section.val = val

    return section
end

local function ApplyPreviewSectionLayout(section, cfg, pv, visibleCount)
    local width, height, isVertical = GetPreviewDisplaySize(cfg, pv, visibleCount)
    section:SetSize(math_max(width, 80), 12 + PREVIEW_LABEL_GAP + height)

    section.barFrame:ClearAllPoints()
    section.barFrame:SetSize(width, height)
    section.barFrame:SetPoint("TOP", section.lbl, "BOTTOM", 0, -PREVIEW_LABEL_GAP)

    section.bar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")

    local borderSize = cfg and cfg.borderSize or 0
    local UIKit = ns.UIKit
    if UIKit and UIKit.UpdateBorderLines then
        UIKit.UpdateBorderLines(section.barFrame, borderSize, 0, 0, 0, 1, borderSize <= 0)
    end
end

---------------------------------------------------------------------------
-- Per-tick dynamics application
-- Writes ONLY pct-dependent values (StatusBar value + value-text).
-- Geometry, ticks, colors, fonts, Show/Hide-by-setting are owned by
-- Refresh and are not touched here.
---------------------------------------------------------------------------

local function ApplyDynamics(primaryPct, secondaryPct)
    local pr = state.previewRef
    if not pr then return end

    local p, s = pr.primary, pr.secondary
    if p and p:IsShown() and p._cfg then
        p.bar:SetValue(primaryPct)
        if p.val then
            local cfg = p._cfg
            local textCfg = p._textCfg or GetPreviewTextConfig(cfg, false)
            p.val:SetText(MockValueText(cfg, textCfg, primaryPct, p._resource))
        end
    end
    if s and s:IsShown() and s._cfg then
        s.bar:SetValue(secondaryPct)
        if s.val then
            local cfg = s._cfg
            local textCfg = s._textCfg or GetPreviewTextConfig(cfg, true)
            s.val:SetText(MockValueText(cfg, textCfg, secondaryPct, s._resource))
        end
    end
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------

function Module.Build(host)
    if state.ticker then return end  -- idempotent
    state.host = host

    local GUI    = QUI and QUI.GUI
    local C      = (GUI and GUI.Colors) or {}
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local border = C.border or { 1, 1, 1, 0.06 }
    local UIKit  = ns.UIKit
    local fpath  = UIKit and UIKit.ResolveFontPath
                   and UIKit.ResolveFontPath(GUI and GUI:GetFontPath())

    -- Preview background fill
    local fill = host:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(host)
    fill:SetColorTexture(0, 0, 0, 0.2)

    -- Border lines
    if UIKit and UIKit.CreateBorderLines then
        UIKit.CreateBorderLines(host)
        UIKit.UpdateBorderLines(host, 1, border[1] or 1, border[2] or 1, border[3] or 1, 0.15, false)
    end

    -- "PREVIEW" label
    local lbl = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if fpath then lbl:SetFont(fpath, 8, "") end
    lbl:SetTextColor(accent[1], accent[2], accent[3], 0.7)
    lbl:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -6)
    lbl:SetText(("PREVIEW"):gsub(".", "%0 "):sub(1, -2))

    -- Primary + secondary mock sections
    local primary = MakeMockBar(host, fpath)
    primary:SetPoint("TOPLEFT",  host, "TOPLEFT",  BAR_PAD_X,  -20)
    primary:SetPoint("TOPRIGHT", host, "TOPRIGHT", -BAR_PAD_X, -20)
    primary:SetSize(100, 24)

    local secondary = MakeMockBar(host, fpath)
    secondary:Hide()

    state.previewRef = { pv = host, primary = primary, secondary = secondary, fpath = fpath }

    -- Ticker (60Hz cycle dispatcher)
    state.ticker = CreateFrame("Frame", nil, host)
    state.ticker:SetScript("OnUpdate", function(_, elapsed)
        AdvanceCycle(elapsed)
        ApplyDynamics(ComputePcts(state.cycle.t))
    end)

    -- Re-render on host resize
    host:SetScript("OnSizeChanged", function()
        Module.Refresh()
    end)

    -- First-frame paint
    Module.Refresh()
end

function Module.Refresh()
    local pr = state.previewRef
    if not pr then return end
    local p, s, fp = pr.primary, pr.secondary, pr.fpath

    local Helpers = ns.Helpers
    local core    = Helpers and Helpers.GetCore and Helpers.GetCore()
    local profile = core and core.db and core.db.profile
    if not profile then return end

    local pc = profile.powerBar
    local sc = profile.secondaryPowerBar

    local Internal           = GetInternal() or {}
    local GetPrimaryResource   = Internal.GetPrimaryResource   or function() end
    local GetSecondaryResource = Internal.GetSecondaryResource or function() end
    local ShouldSwapBars       = Internal.ShouldSwapBars       or function() return false end
    local ShouldHidePrimaryOnSwap = Internal.ShouldHidePrimaryOnSwap or function() return false end
    local GetBarTexture        = Internal.GetBarTexture        or function() return "" end

    local LSM = ns.LSM

    local primaryResource   = GetPrimaryResource()
    local secondaryResource = GetSecondaryResource()
    local primaryTextCfg    = GetPreviewTextConfig(pc, false)
    local secondaryTextCfg  = GetPreviewTextConfig(sc, true)
    local showPrimary       = pc and pc.enabled ~= false
    local showSecondary     = sc and sc.enabled ~= false and secondaryResource ~= nil
    local swapBars          = showSecondary and ShouldSwapBars()

    if showPrimary and swapBars and ShouldHidePrimaryOnSwap() then
        showPrimary = false
    end

    local visibleCount = (showPrimary and 1 or 0) + (showSecondary and 1 or 0)
    if visibleCount == 0 then
        p:Hide()
        s:Hide()
        return
    end

    p:Hide()
    s:Hide()

    local orderedSections = {}
    if swapBars then
        if showSecondary then
            orderedSections[#orderedSections + 1] = { section = s, cfg = sc, textCfg = secondaryTextCfg, resource = secondaryResource, label = POWER_DISPLAY_NAMES[secondaryResource] or "Secondary" }
        end
        if showPrimary then
            orderedSections[#orderedSections + 1] = { section = p, cfg = pc, textCfg = primaryTextCfg, resource = primaryResource, label = POWER_DISPLAY_NAMES[primaryResource] or "Power" }
        end
    else
        if showPrimary then
            orderedSections[#orderedSections + 1] = { section = p, cfg = pc, textCfg = primaryTextCfg, resource = primaryResource, label = POWER_DISPLAY_NAMES[primaryResource] or "Power" }
        end
        if showSecondary then
            orderedSections[#orderedSections + 1] = { section = s, cfg = sc, textCfg = secondaryTextCfg, resource = secondaryResource, label = POWER_DISPLAY_NAMES[secondaryResource] or "Secondary" }
        end
    end

    local nextY = -20
    for _, info in ipairs(orderedSections) do
        local section = info.section
        local cfg = info.cfg
        local textCfg = info.textCfg
        local resource = info.resource

        section:Show()
        section:ClearAllPoints()
        ApplyPreviewSectionLayout(section, cfg, pr.pv, visibleCount)
        section:SetPoint("TOP", pr.pv, "TOP", 0, nextY)
        nextY = nextY - section:GetHeight() - PREVIEW_SECTION_GAP

        section.lbl:SetText(info.label)

        local r, g, b = GetPreviewBarColor(cfg, resource)
        local bgr, bgg, bgb, bga = GetPreviewBgColor(cfg)
        section.bg:SetColorTexture(bgr, bgg, bgb, bga)

        local tex = LSM and LSM.Fetch and LSM:Fetch("statusbar", GetBarTexture(cfg))
        if tex then section.bar:SetStatusBarTexture(tex) end
        section.bar:SetStatusBarColor(r, g, b)
        -- Bar value is set per-tick by ApplyDynamics; do not call SetValue here.

        ApplyPreviewTicks(section, cfg, resource)

        local fontSize = textCfg and math_max(7, math_min(textCfg.textSize or 9, 13)) or 9
        if fp then section.val:SetFont(fp, fontSize, "") end

        local align = textCfg and textCfg.textAlign or "CENTER"
        section.val:ClearAllPoints()
        if align == "LEFT" then
            section.val:SetPoint("LEFT", section.barFrame, "LEFT", 4, (textCfg and textCfg.textY or 0))
        elseif align == "RIGHT" then
            section.val:SetPoint("RIGHT", section.barFrame, "RIGHT", -4, (textCfg and textCfg.textY or 0))
        else
            section.val:SetPoint("CENTER", section.barFrame, "CENTER", (textCfg and textCfg.textX or 0), (textCfg and textCfg.textY or 0))
        end

        -- Cache per-section settings on the section frame so ApplyDynamics
        -- doesn't have to re-resolve them every tick.
        section._cfg      = cfg
        section._resource = resource
        section._textCfg  = textCfg
    end

    -- Paint the first frame after refresh with live cycle pcts so the bars
    -- don't snap to a stale value between Refresh and the next OnUpdate tick.
    local pp, ss = ComputePcts(state.cycle.t)
    ApplyDynamics(pp, ss)
end

function Module.Teardown()
    if state.ticker then
        state.ticker:SetScript("OnUpdate", nil)
    end
    if state.host then
        state.host:SetScript("OnSizeChanged", nil)
    end
    state.host       = nil
    state.ticker     = nil
    state.previewRef = nil
    state.cycle      = { t = 0 }
end

function Module.GetCurrentPcts()
    local p, s = ComputePcts(state.cycle.t)
    return { primary = p, secondary = s }
end
