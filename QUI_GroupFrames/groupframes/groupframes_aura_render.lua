--[[
    QUI Group Frames - Unified Aura Renderer

    A single render surface for the v46 aura element model
    (groupframes_aura_model.lua). One element drives exactly one visual:
    an icon strip, a colored square, a duration bar, or a health-bar tint.

    The caller resolves matches from the shared aura cache and hands them to us.
    For a TRACKED element `matches` is a `{ [spellID] = auraData }` map (looked up
    in configured spell order). For a FILTERSTRIP element `matches` is an ORDERED
    ARRAY `{ auraData, ... }` already in the consumer's priority order and capped
    at maxIcons — RenderIcon renders it in that exact order. This module NEVER
    scans auras and NEVER reads the DB. It owns rendering only.

    Rendering techniques are relocated/adapted from:
      - groupframes_indicators.lua (icon strip layout, bar renderer +
        DurationObject fill, health-tint overlay + animation modes, pools)
      - groupframes_pinned_auras.lua (square color-swatch renderer, fixed
        single-icon placement)

    SECRET-VALUE SAFETY (WoW 12.0): aura duration / expirationTime can be
    secret in combat. We NEVER compare or do arithmetic on them in Lua, and
    NEVER string.format a secret. All timing is forwarded to the C side:
      - cooldown swipe  -> Helpers.ApplyCooldownFromAura (prefers
        SetCooldownFromDurationObject; numeric only when non-secret)
      - duration TEXT   -> Blizzard's native C-side countdown
        (SetHideCountdownNumbers(false) + optional SetCountdownFormatter,
        styling GetCountdownFontString) — NO Lua FormatDuration timer
      - bar fill        -> bar:SetTimerDuration(DurationObject, ...) (C-side
        drains the bar); numeric SetValue only when non-secret
      - health tint     -> only non-secret health % is tweened in Lua; the
        secret path falls back to a direct SetValue

    INERT: nothing calls into this module until a later flip task. It defines
    functions that call WoW API but performs no WoW API call at file scope, so
    it loads cleanly under a bare `loadfile(path)("QUI_GroupFrames", ns)`.
]]

local ADDON_NAME, ns = ...

local R = ns.QUI_GroupFrameAuraRender or {}
ns.QUI_GroupFrameAuraRender = R

---------------------------------------------------------------------------
-- LAZY GLOBAL/HELPER ACCESS
-- Resolved on first use rather than at file scope so the module loads under a
-- bare test harness ns (where ns.Helpers / WoW globals do not exist yet).
---------------------------------------------------------------------------
local function IconLayout() return ns.QUI_GroupFrameIconLayout end

local function IsSecretValue(v)
    local H = ns.Helpers
    if H and H.IsSecretValue then return H.IsSecretValue(v) end
    return issecretvalue and issecretvalue(v) or false
end

local function SafeToNumber(v, fallback)
    local H = ns.Helpers
    if H and H.SafeToNumber then return H.SafeToNumber(v, fallback) end
    if issecretvalue and issecretvalue(v) then return fallback or 0 end
    return tonumber(v) or fallback or 0
end

local function GetSkinBorderColor()
    local H = ns.Helpers
    if H and H.GetSkinBorderColor then return H.GetSkinBorderColor() end
    return 0, 0, 0, 1
end

local function GetPixelSize(frame)
    local C = ns.Addon
    if C and C.GetPixelSize then return C:GetPixelSize(frame) end
    return 1
end

local function GetFontPath(size)
    local sm = ns.LSM
    -- General group-frame font; falls back to the stock font. Element font
    -- size comes from element.durationFontSize, not from the DB.
    local fontName = "Quazii"
    local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
    local general = profile and profile.general
    if general and general.font then fontName = general.font end
    local path = sm and sm.Fetch and sm:Fetch("font", fontName) or nil
    return path or "Fonts\\FRIZQT__.TTF"
end

local function GetStatusBarTexturePath()
    local sm = ns.LSM
    local textureName = "Quazii v5"
    local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
    local general = profile and profile.general
    if general and general.texture then textureName = general.texture end
    return (sm and sm.Fetch and sm:Fetch("statusbar", textureName, true))
        or "Interface\\TargetingFrame\\UI-StatusBar"
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local POOL_SIZE = 60
local DEFAULT_HEALTH_COLOR = { 0.2, 0.8, 0.2, 1 }
local DEFAULT_SQUARE_COLOR = { 0.5, 0.5, 0.5, 1 }
local DEFAULT_BORDER_COLOR = { 0, 0, 0, 1 }

local HEALTH_TINT_ANIMATION_DEFAULT = "fill"
local HEALTH_TINT_ANIMATION_DURATIONS = {
    instant = 0, fill = 0.35, fade = 0.25, fillFade = 0.35, pulse = 0.28,
}
local STATUS_BAR_INTERPOLATION_IMMEDIATE = 0
local STATUS_BAR_TIMER_REMAINING = 1

local STATE_KEY = "_quiAuraRender"

---------------------------------------------------------------------------
-- COUNTDOWN FORMATTER (secret-safe duration TEXT)
-- Cloned from the action-bar buff-border fix: SecondsToTimeAbbrev rounding
-- (CEIL, 1.5x-unit band starts) so the native countdown matches the tooltip
-- on long auras. Rendering stays 100% C-side; secretness rides on the
-- formatter via SetCountdownFormatter, never on a Lua read.
---------------------------------------------------------------------------
local auraCountdownFormatter = false -- false = not built; nil = unsupported client
local function GetAuraCountdownFormatter()
    if auraCountdownFormatter == false then
        auraCountdownFormatter = nil
        local rounding = Enum and Enum.NumericRuleFormatRounding
        if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and rounding then
            local ok, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
            if ok and formatter then
                local applied = pcall(formatter.SetBreakpoints, formatter, {
                    { threshold = 0, step = 1, rounding = rounding.Up, format = "%ds" },
                    { threshold = 90, format = "%dm",
                        components = { { div = 60, step = 1, rounding = rounding.Up } } },
                    { threshold = 5400, format = "%dh",
                        components = { { div = 3600, step = 1, rounding = rounding.Up } } },
                    { threshold = 129600, format = "%dd",
                        components = { { div = 86400, step = 1, rounding = rounding.Up } } },
                })
                if applied then
                    auraCountdownFormatter = formatter
                end
            end
        end
    end
    return auraCountdownFormatter
end

-- Configure a cooldown's native countdown numbers. When `showText` is true the
-- C-side renderer draws the duration text (secret-safe); when false the numbers
-- are hidden and the swipe alone conveys time.
local function ConfigureCountdown(cd, showText)
    if not cd then return end
    if cd.SetHideCountdownNumbers then
        pcall(cd.SetHideCountdownNumbers, cd, showText ~= true)
    end
    if showText and cd.SetCountdownFormatter then
        local formatter = GetAuraCountdownFormatter()
        if formatter then
            pcall(cd.SetCountdownFormatter, cd, formatter)
        end
    end
end

-- Style the native countdown FontString (this IS the duration text) per the
-- element's font size. Mirrors the buff-border StyleIcon countdown styling.
local function StyleCountdownText(cd, fontSize)
    if not cd or not cd.GetCountdownFontString then return end
    local ok, cdText = pcall(cd.GetCountdownFontString, cd)
    if not ok or not cdText or not cdText.SetFont then return end
    cdText:SetFont(GetFontPath(fontSize), fontSize or 9, "OUTLINE")
end

---------------------------------------------------------------------------
-- HEALTH-TINT ANIMATION DRIVER (adapted from groupframes_indicators.lua:165-332)
-- A single shared OnUpdate frame tweens alpha (and, when non-secret, fill
-- value) of every active health-tint overlay.
---------------------------------------------------------------------------
local math_max = math.max
local math_min = math.min

local activeHealthTintAnimations = {}
local activeHealthTintAnimationCount = 0
local healthTintAnimationFrame -- created lazily (no WoW API at file scope)

local function EaseOutCubic(t)
    local inv = 1 - t
    return 1 - (inv * inv * inv)
end

local function UnregisterHealthTintAnimation(overlay)
    if activeHealthTintAnimations[overlay] then
        activeHealthTintAnimations[overlay] = nil
        activeHealthTintAnimationCount = math_max(activeHealthTintAnimationCount - 1, 0)
        if activeHealthTintAnimationCount == 0 and healthTintAnimationFrame then
            healthTintAnimationFrame:Hide()
        end
    end
    if overlay then
        overlay._quiTintAnimating = nil
    end
end

local function HealthTintOnUpdate(_, elapsed)
    for overlay in pairs(activeHealthTintAnimations) do
        if not overlay:IsShown() then
            UnregisterHealthTintAnimation(overlay)
        else
            overlay._quiTintElapsed = (overlay._quiTintElapsed or 0) + elapsed
            local duration = overlay._quiTintDuration or 0
            local progress = duration > 0 and math_min(overlay._quiTintElapsed / duration, 1) or 1
            local eased = EaseOutCubic(progress)
            local value
            local startAlpha = overlay._quiTintStartAlpha or 1
            local alpha = startAlpha + ((overlay._quiTintTargetAlpha or 1) - startAlpha) * eased

            if overlay._quiTintTweenValue then
                local startValue = overlay._quiTintStartValue or 0
                value = startValue + ((overlay._quiTintTargetValue or 0) - startValue) * eased
                overlay:SetValue(value)
            end

            overlay:SetAlpha(alpha)

            if progress >= 1 then
                if overlay._quiTintTweenValue then
                    overlay:SetValue(overlay._quiTintTargetValue or value)
                end
                overlay:SetAlpha(overlay._quiTintTargetAlpha or alpha)
                UnregisterHealthTintAnimation(overlay)
            end
        end
    end
end

local function EnsureHealthTintAnimationFrame()
    if not healthTintAnimationFrame then
        healthTintAnimationFrame = CreateFrame("Frame")
        healthTintAnimationFrame:Hide()
        healthTintAnimationFrame:SetScript("OnUpdate", HealthTintOnUpdate)
    end
    return healthTintAnimationFrame
end

local function RegisterHealthTintAnimation(overlay)
    if not activeHealthTintAnimations[overlay] then
        activeHealthTintAnimations[overlay] = true
        activeHealthTintAnimationCount = activeHealthTintAnimationCount + 1
    end
    overlay._quiTintAnimating = true
    EnsureHealthTintAnimationFrame():Show()
end

local function NormalizeHealthTintAnimation(value)
    if value == "instant" or value == "fill" or value == "fade"
        or value == "fillFade" or value == "pulse" then
        return value
    end
    return HEALTH_TINT_ANIMATION_DEFAULT
end

local function StartHealthTintAnimation(overlay, mode, targetValue, targetAlpha)
    mode = NormalizeHealthTintAnimation(mode)
    local duration = HEALTH_TINT_ANIMATION_DURATIONS[mode]
        or HEALTH_TINT_ANIMATION_DURATIONS[HEALTH_TINT_ANIMATION_DEFAULT]
    local nativeInterpolation = Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut
    local canTweenValue = not IsSecretValue(targetValue) and type(targetValue) == "number"

    overlay._quiTintMode = mode
    overlay._quiTintElapsed = 0
    overlay._quiTintDuration = duration
    overlay._quiTintTargetValue = targetValue
    overlay._quiTintTargetAlpha = targetAlpha
    overlay._quiTintTweenValue = nil

    if mode == "instant" or duration <= 0 then
        overlay:SetValue(targetValue)
        overlay:SetAlpha(targetAlpha)
        UnregisterHealthTintAnimation(overlay)
        return
    elseif mode == "fade" then
        overlay:SetValue(targetValue)
        overlay._quiTintStartValue = targetValue
        overlay._quiTintStartAlpha = 0
    elseif mode == "fillFade" then
        overlay:SetValue(0)
        if nativeInterpolation then
            overlay:SetValue(targetValue, nativeInterpolation)
            overlay._quiTintStartValue = targetValue
        elseif canTweenValue then
            overlay._quiTintTweenValue = true
            overlay._quiTintStartValue = 0
        else
            overlay:SetValue(targetValue)
            overlay._quiTintStartValue = targetValue
        end
        overlay._quiTintStartAlpha = 0
    elseif mode == "pulse" then
        overlay:SetValue(targetValue)
        overlay._quiTintStartValue = targetValue
        overlay._quiTintStartAlpha = targetAlpha * 0.35
    else -- fill
        overlay:SetAlpha(targetAlpha)
        overlay:SetValue(0)
        if nativeInterpolation then
            overlay:SetValue(targetValue, nativeInterpolation)
            UnregisterHealthTintAnimation(overlay)
            return
        elseif canTweenValue then
            overlay._quiTintTweenValue = true
            overlay._quiTintStartValue = 0
        else
            overlay:SetValue(targetValue)
            UnregisterHealthTintAnimation(overlay)
            return
        end
        overlay._quiTintStartAlpha = targetAlpha
    end

    if overlay._quiTintTweenValue then
        overlay:SetValue(overlay._quiTintStartValue or 0)
    end
    overlay:SetAlpha(overlay._quiTintStartAlpha or targetAlpha)
    RegisterHealthTintAnimation(overlay)
end

---------------------------------------------------------------------------
-- FRAME POOLS (adapted from indicators.lua + pinned_auras.lua)
-- icon frames double as square swatches (solidColor child); bars are
-- StatusBars. Pools are module-level; per-element acquisition lives on
-- frame[STATE_KEY][element.id].
---------------------------------------------------------------------------
local iconPool = {}
local barPool = {}

local function CreateIconFrame(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(16, 16)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = tex

    local px = GetPixelSize(frame)
    frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = px })
    local br, bg, bb, ba = GetSkinBorderColor()
    frame:SetBackdropBorderColor(br, bg, bb, ba)

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.cooldown = cd

    -- Solid color texture for the "square" display type (hidden by default).
    local solid = frame:CreateTexture(nil, "ARTWORK")
    solid:SetAllPoints()
    solid:SetColorTexture(1, 1, 1, 1)
    solid:Hide()
    frame.solidColor = solid

    frame:Hide()
    return frame
end

local function AcquireIconFrame(parent)
    local item = table.remove(iconPool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
        return item
    end
    return CreateIconFrame(parent)
end

local function ReleaseIconFrame(item)
    if not item then return end
    item:Hide()
    item:ClearAllPoints()
    if item.cooldown then
        item.cooldown:Clear()
        if item.cooldown.SetHideCountdownNumbers then
            pcall(item.cooldown.SetHideCountdownNumbers, item.cooldown, true)
        end
    end
    if item.icon then
        item.icon:Show()
        item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if item.solidColor then item.solidColor:Hide() end
    item._auraInstanceID = nil
    item:SetAlpha(1)
    local br, bg, bb, ba = GetSkinBorderColor()
    item:SetBackdropBorderColor(br, bg, bb, ba)
    if #iconPool < POOL_SIZE then
        table.insert(iconPool, item)
    end
end

---------------------------------------------------------------------------
-- BAR POOL + DurationObject fill (adapted from indicators.lua:780-1063)
---------------------------------------------------------------------------
local activeTimerBars = {}
local activeTimerBarCount = 0
local barTimerFrame -- lazy
local UpdateBarProgress -- forward decl

local function CreateBarFrame(parent)
    local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.28)
    bar.background = bg
    bar:Hide()
    return bar
end

local function AcquireBarFrame(parent)
    local item = table.remove(barPool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
        return item
    end
    return CreateBarFrame(parent)
end

local function UnregisterBarTimer(bar)
    if activeTimerBars[bar] then
        activeTimerBars[bar] = nil
        activeTimerBarCount = math_max(activeTimerBarCount - 1, 0)
        if activeTimerBarCount == 0 and barTimerFrame then
            barTimerFrame:Hide()
        end
    end
end

local function ReleaseBarFrame(item)
    if not item then return end
    item:Hide()
    item:ClearAllPoints()
    UnregisterBarTimer(item)
    item._elapsed = 0
    item._auraData = nil
    item._unit = nil
    item._element = nil
    item._usesDurationObjectFill = nil
    item._durationObject = nil
    item._layoutOrientation = nil
    item._layoutWidth = nil
    item._layoutHeight = nil
    item._layoutAnchor = nil
    item._layoutTexturePath = nil
    item:SetMinMaxValues(0, 1)
    item:SetValue(1)
    if item.background then
        item.background:SetColorTexture(0, 0, 0, 0.28)
    end
    item:SetBackdrop(nil)
    if #barPool < POOL_SIZE then
        table.insert(barPool, item)
    end
end

local function GetBarConfig(element)
    return element.bar or nil
end

-- low-time color band; remaining is only ever passed when non-secret
local function GetBarDisplayColor(barCfg, element, remaining)
    local color = (barCfg and barCfg.color) or element.color or DEFAULT_HEALTH_COLOR
    local threshold = SafeToNumber(barCfg and barCfg.lowTimeThreshold, 0)
    if remaining and threshold > 0 and remaining <= threshold then
        local lowColor = barCfg and barCfg.lowTimeColor
        if type(lowColor) == "table" then
            return lowColor
        end
    end
    return color
end

local function ApplyBarColor(bar, barCfg, element, remaining)
    local color = GetBarDisplayColor(barCfg, element, remaining)
    local r = color[1] or 0.2
    local g = color[2] or 0.8
    local b = color[3] or 0.2
    local a = color[4] or 1
    bar:SetStatusBarColor(r, g, b, a)
    if bar.background then
        local bg = barCfg and barCfg.backgroundColor
        if type(bg) == "table" then
            bar.background:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.18)
        else
            bar.background:SetColorTexture(r, g, b, 0.18)
        end
    end
end

local function BindBarDurationObject(bar)
    if not bar or not bar.SetTimerDuration then
        return false
    end
    local auraData = bar._auraData
    local auraInstanceID = auraData and auraData.auraInstanceID
    local unit = bar._unit
    if not unit or not auraInstanceID or not C_UnitAuras or not C_UnitAuras.GetAuraDuration then
        return false
    end

    -- A readable, non-secret, non-positive duration means "no live timer".
    local readableDuration = auraData.duration
    if readableDuration ~= nil
        and not IsSecretValue(readableDuration)
        and SafeToNumber(readableDuration, 0) <= 0
    then
        return false
    end

    local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
    if not ok or not durationObj then
        return false
    end

    -- Forward the DurationObject straight to the C-side fill driver. C drains
    -- the bar with remaining-time direction; no secret value is ever read.
    local applied = pcall(
        bar.SetTimerDuration,
        bar,
        durationObj,
        STATUS_BAR_INTERPOLATION_IMMEDIATE,
        STATUS_BAR_TIMER_REMAINING
    )
    if not applied then
        return false
    end

    bar._usesDurationObjectFill = true
    bar._durationObject = durationObj
    return true
end

UpdateBarProgress = function(bar)
    local auraData = bar._auraData
    local element = bar._element
    if not auraData or not element then
        return
    end
    local barCfg = GetBarConfig(element)

    bar._usesDurationObjectFill = nil
    bar._durationObject = nil

    if BindBarDurationObject(bar) then
        -- The client now drives fill timing from the live DurationObject. The
        -- cached AuraData can be stale across mixed deltas, so do NOT use a Lua
        -- timestamp to zero the bar right after binding.
        ApplyBarColor(bar, barCfg, element, nil)
        return
    end

    -- No DurationObject: numeric fallback, only when values are non-secret.
    local duration = SafeToNumber(auraData.duration, 0)
    local expirationTime = SafeToNumber(auraData.expirationTime, 0)
    local remaining = nil
    local pct = 1
    if duration > 0 and expirationTime > 0
        and not IsSecretValue(auraData.duration)
        and not IsSecretValue(auraData.expirationTime)
    then
        remaining = math_max(expirationTime - GetTime(), 0)
        pct = math_min(math_max(remaining / duration, 0), 1)
    end
    bar:SetValue(pct)
    ApplyBarColor(bar, barCfg, element, remaining)
end

local function BarTimerOnUpdate(self, elapsed)
    self._elapsed = (self._elapsed or 0) + elapsed
    if self._elapsed < 0.08 then return end
    self._elapsed = 0
    for bar in pairs(activeTimerBars) do
        if bar:IsShown() then
            UpdateBarProgress(bar)
        else
            activeTimerBars[bar] = nil
            activeTimerBarCount = math_max(activeTimerBarCount - 1, 0)
        end
    end
    if activeTimerBarCount == 0 then
        self:Hide()
    end
end

local function EnsureBarTimerFrame()
    if not barTimerFrame then
        barTimerFrame = CreateFrame("Frame")
        barTimerFrame:Hide()
        barTimerFrame:SetScript("OnUpdate", BarTimerOnUpdate)
    end
    return barTimerFrame
end

local function RegisterBarTimer(bar)
    if not activeTimerBars[bar] then
        activeTimerBars[bar] = true
        activeTimerBarCount = activeTimerBarCount + 1
    end
    EnsureBarTimerFrame():Show()
end

---------------------------------------------------------------------------
-- PER-FRAME / PER-ELEMENT STATE
-- frame[STATE_KEY] = { [element.id] = { icons = {}, bar = <frame|nil>,
--   container = <frame|nil>, layout cache fields... } }
-- Health tint lives on the frame itself (one overlay per frame) keyed by the
-- owning element id so a stale element can be cleared.
---------------------------------------------------------------------------
local function GetFrameStore(frame)
    local store = frame[STATE_KEY]
    if not store then
        store = {}
        frame[STATE_KEY] = store
    end
    return store
end

local function GetElementState(frame, element)
    local store = GetFrameStore(frame)
    local id = element.id
    local st = store[id]
    if not st then
        st = { icons = {} }
        store[id] = st
    end
    return st
end

---------------------------------------------------------------------------
-- ICON DATA WRITE (shared by strip + single icon)
---------------------------------------------------------------------------
local function ApplyIconData(icon, unit, element, auraData)
    if icon.solidColor then icon.solidColor:Hide() end
    -- Stash the live aura instance so the runtime fast path (pure stack/
    -- duration updates) can reseat this icon's swipe without a full rebuild.
    icon._auraInstanceID = auraData and auraData.auraInstanceID
    if icon.icon then
        icon.icon:Show()
        icon.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local tex = auraData and auraData.icon
        if tex then icon.icon:SetTexture(tex) end
    end

    local cd = icon.cooldown
    if cd then
        local showText = element.showDurationText == true
        if cd.SetDrawSwipe then
            pcall(cd.SetDrawSwipe, cd, element.hideSwipe ~= true)
        end
        if cd.SetReverse then
            pcall(cd.SetReverse, cd, element.reverseSwipe == true)
        end
        -- Duration TEXT is the native C-side countdown (secret-safe). Configure
        -- visibility/formatter and style its FontString per element font size.
        ConfigureCountdown(cd, showText)
        if showText then
            StyleCountdownText(cd, element.durationFontSize or 9)
        end

        local dur = auraData and auraData.duration
        local expTime = auraData and auraData.expirationTime
        if dur and expTime then
            -- ApplyCooldownFromAura prefers SetCooldownFromDurationObject
            -- (C-side, secret-safe) and only uses numeric timing when readable.
            local H = ns.Helpers
            if H and H.ApplyCooldownFromAura then
                H.ApplyCooldownFromAura(cd, unit, auraData.auraInstanceID, expTime, dur,
                    nil, auraData.timeMod)
            end
        else
            cd:Clear()
        end
    end

    icon:SetAlpha(1)
    local br, bg, bb, ba = GetSkinBorderColor()
    icon:SetBackdropBorderColor(br, bg, bb, ba)
end

---------------------------------------------------------------------------
-- RENDERER: ICON
-- Handles BOTH a multi-spell grow-strip (tracked icon with several spells, or
-- a filterStrip) AND a single fixed icon. Icons are pooled on
-- frame[STATE_KEY][element.id].icons; surplus is released.
---------------------------------------------------------------------------
function R.RenderIcon(self, frame, element, matches)
    if not frame or not frame.unit then return end
    local state = GetElementState(frame, element)

    -- Build the ordered list of auras to show. For a tracked element we honor
    -- the configured spell order, looking each spell up in the matches map. For a
    -- filterStrip the caller hands us an ALREADY-ORDERED array (priority order,
    -- already capped) — we iterate it verbatim and must NOT re-sort by spellID,
    -- or we'd clobber the consumer's priority (e.g. dispellable > boss > normal).
    local ordered = state._orderScratch or {}
    state._orderScratch = ordered
    for i = #ordered, 1, -1 do ordered[i] = nil end

    if element.mode == "tracked" and element.spells then
        for _, sid in ipairs(element.spells) do
            local data = matches and matches[sid]
            if data then ordered[#ordered + 1] = data end
        end
    elseif matches then
        -- filterStrip: caller-resolved, priority-ordered array. Preserve order.
        for _, data in ipairs(matches) do
            if data then ordered[#ordered + 1] = data end
        end
    end

    local maxIcons = SafeToNumber(element.maxIcons, 0)
    if maxIcons <= 0 then maxIcons = #ordered end
    local count = math_min(#ordered, maxIcons)

    if count == 0 then
        for idx = #state.icons, 1, -1 do
            ReleaseIconFrame(state.icons[idx])
            state.icons[idx] = nil
        end
        if state.container then state.container:Hide() end
        return
    end

    -- Lazily create a per-element container so the strip can be positioned as a
    -- unit and frame-level-bumped above the unit frame.
    local container = state.container
    if not container then
        container = CreateFrame("Frame", nil, frame)
        container:SetSize(1, 1)
        state.container = container
    end
    container:SetFrameLevel(frame:GetFrameLevel() + 8)
    container:ClearAllPoints()
    container:SetAllPoints(frame)
    container:Show()

    local iconSize = SafeToNumber(element.iconSize, 14)
    if iconSize <= 0 then iconSize = 14 end
    local growDir = element.growDirection or "RIGHT"
    local spacing = SafeToNumber(element.spacing, 2)
    local anchor = element.anchor or "TOPLEFT"
    local offX = SafeToNumber(element.offsetX, 0)
    local offY = SafeToNumber(element.offsetY, 0)
    local bottomPad = frame._bottomPad or 0
    if type(anchor) == "string" and anchor:find("BOTTOM") then
        offY = offY + bottomPad
    end

    local IL = IconLayout()
    local iconAnchor = (IL and IL.GetIconAnchorForGrow and IL.GetIconAnchorForGrow(anchor, growDir))
        or anchor

    -- Layout invalidates when any geometry input changes (so repeated calls
    -- with steady config skip the reposition churn).
    local layoutChanged = state._count ~= count
        or state._iconSize ~= iconSize
        or state._growDir ~= growDir
        or state._spacing ~= spacing
        or state._anchor ~= anchor
        or state._offX ~= offX
        or state._offY ~= offY
        or state._bottomPad ~= bottomPad
    state._count = count
    state._iconSize = iconSize
    state._growDir = growDir
    state._spacing = spacing
    state._anchor = anchor
    state._offX = offX
    state._offY = offY
    state._bottomPad = bottomPad

    for idx = 1, count do
        local icon = state.icons[idx]
        if not icon then
            icon = AcquireIconFrame(container)
            state.icons[idx] = icon
            layoutChanged = true
        end
        icon:SetSize(iconSize, iconSize)

        if layoutChanged then
            icon:ClearAllPoints()
            local slotX, slotY = 0, 0
            if IL and IL.CalculateSlotOffset then
                slotX, slotY = IL.CalculateSlotOffset(idx, iconSize, spacing, growDir, count)
            else
                slotX = (idx - 1) * (iconSize + spacing)
            end
            icon:SetPoint(iconAnchor, frame, anchor, offX + slotX, offY + slotY)
        end

        ApplyIconData(icon, frame.unit, element, ordered[idx])
        icon:Show()
    end

    for idx = #state.icons, count + 1, -1 do
        ReleaseIconFrame(state.icons[idx])
        state.icons[idx] = nil
    end

    for i = #ordered, 1, -1 do ordered[i] = nil end
end

---------------------------------------------------------------------------
-- RENDERER: SQUARE (adapted from pinned_auras.lua:347-360)
-- Single-spell colored swatch at anchor+offset; hidden when absent.
---------------------------------------------------------------------------
function R.RenderSquare(self, frame, element, matches)
    if not frame then return end
    local state = GetElementState(frame, element)

    local auraData
    if element.spells then
        for _, sid in ipairs(element.spells) do
            local data = matches and matches[sid]
            if data then auraData = data; break end
        end
    end

    local icon = state.icons[1]

    if not auraData then
        if icon then
            ReleaseIconFrame(icon)
            state.icons[1] = nil
        end
        return
    end

    if not icon then
        icon = AcquireIconFrame(frame)
        state.icons[1] = icon
    end

    local size = SafeToNumber(element.iconSize, 8)
    if size <= 0 then size = 8 end
    local anchor = element.anchor or "TOPLEFT"
    local offX = SafeToNumber(element.offsetX, 0)
    local offY = SafeToNumber(element.offsetY, 0)
    local bottomPad = frame._bottomPad or 0
    if type(anchor) == "string" and anchor:find("BOTTOM") then
        offY = offY + bottomPad
    end

    icon:SetSize(size, size)
    icon:SetFrameLevel(frame:GetFrameLevel() + 8)
    icon:ClearAllPoints()
    icon:SetPoint(anchor, frame, anchor, offX, offY)

    local color = element.color or DEFAULT_SQUARE_COLOR
    if icon.icon then icon.icon:Hide() end
    if icon.cooldown then
        icon.cooldown:Hide()
        icon.cooldown:Clear()
    end
    if icon.solidColor then
        icon.solidColor:SetColorTexture(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5, color[4] or 1)
        icon.solidColor:Show()
    end
    icon:SetAlpha(1)
    local br, bg, bb, ba = GetSkinBorderColor()
    icon:SetBackdropBorderColor(br, bg, bb, ba)
    icon:Show()
end

---------------------------------------------------------------------------
-- RENDERER: BAR (adapted from indicators.lua:981-1063, 1308-1329)
-- Single-spell duration bar; hidden when absent.
---------------------------------------------------------------------------
function R.RenderBar(self, frame, element, matches)
    if not frame or not frame.unit then return end
    local state = GetElementState(frame, element)

    local auraData
    if element.spells then
        for _, sid in ipairs(element.spells) do
            local data = matches and matches[sid]
            if data then auraData = data; break end
        end
    end

    local bar = state.bar

    if not auraData then
        if bar then
            ReleaseBarFrame(bar)
            state.bar = nil
        end
        return
    end

    if not bar then
        bar = AcquireBarFrame(frame)
        state.bar = bar
    end
    bar:SetFrameLevel(frame:GetFrameLevel() + 9)

    local barCfg = GetBarConfig(element) or {}
    local orientation = barCfg.orientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL"
    local thickness = math_max(1, SafeToNumber(barCfg.thickness, 4))
    local length = math_max(1, SafeToNumber(barCfg.length, 40))
    local matchFrameSize = barCfg.matchFrameSize == true
    local frameWidth = math_max(1, (frame:GetWidth() or 1) - 2)
    local frameHeight = math_max(1, (frame:GetHeight() or 1) - ((frame._bottomPad or 0) * 0.5) - 2)
    local width = orientation == "HORIZONTAL" and (matchFrameSize and frameWidth or length) or thickness
    local height = orientation == "VERTICAL" and (matchFrameSize and frameHeight or length) or thickness
    local anchor = barCfg.anchor or element.anchor or "BOTTOM"
    local offsetX = SafeToNumber(barCfg.offsetX ~= nil and barCfg.offsetX or element.offsetX, 0)
    local offsetY = SafeToNumber(barCfg.offsetY ~= nil and barCfg.offsetY or element.offsetY, 0)

    local borderSize = math_max(1, SafeToNumber(barCfg.borderSize, 1))
    local borderColor = barCfg.borderColor or DEFAULT_BORDER_COLOR
    local px = GetPixelSize(bar)
    local texturePath = GetStatusBarTexturePath()
    local bottomPad = frame._bottomPad or 0
    local hideBorder = barCfg.hideBorder == true
    local bcr, bcg, bcb, bca = borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1

    local layoutChanged = bar._layoutOrientation ~= orientation
        or bar._layoutWidth ~= width
        or bar._layoutHeight ~= height
        or bar._layoutAnchor ~= anchor
        or bar._layoutOffsetX ~= offsetX
        or bar._layoutOffsetY ~= offsetY
        or bar._layoutBottomPad ~= bottomPad
        or bar._layoutBorderSize ~= borderSize
        or bar._layoutHideBorder ~= hideBorder
        or bar._layoutTexturePath ~= texturePath
        or bar._layoutBorderR ~= bcr
        or bar._layoutBorderG ~= bcg
        or bar._layoutBorderB ~= bcb
        or bar._layoutBorderA ~= bca

    if layoutChanged then
        bar._layoutOrientation = orientation
        bar._layoutWidth = width
        bar._layoutHeight = height
        bar._layoutAnchor = anchor
        bar._layoutOffsetX = offsetX
        bar._layoutOffsetY = offsetY
        bar._layoutBottomPad = bottomPad
        bar._layoutBorderSize = borderSize
        bar._layoutHideBorder = hideBorder
        bar._layoutTexturePath = texturePath
        bar._layoutBorderR, bar._layoutBorderG, bar._layoutBorderB, bar._layoutBorderA = bcr, bcg, bcb, bca
        local applyOffsetY = offsetY
        bar:ClearAllPoints()
        if type(anchor) == "string" and anchor:find("BOTTOM") then
            applyOffsetY = applyOffsetY + bottomPad
        end
        bar:SetPoint(anchor, frame, anchor, offsetX, applyOffsetY)
        bar:SetSize(width, height)
        bar:SetOrientation(orientation)
        bar:SetStatusBarTexture(texturePath)
        if hideBorder then
            bar:SetBackdrop(nil)
        else
            bar:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = borderSize * px })
            bar:SetBackdropBorderColor(bcr, bcg, bcb, bca)
        end
    end

    bar._unit = frame.unit
    bar._auraData = auraData
    bar._element = element
    bar._elapsed = 0
    UpdateBarProgress(bar)

    -- Register the Lua fallback ticker only when timing is readable & numeric;
    -- when the C-side DurationObject drives the fill, no Lua ticker is needed.
    local duration = SafeToNumber(auraData.duration, 0)
    local expirationTime = SafeToNumber(auraData.expirationTime, 0)
    if bar._usesDurationObjectFill then
        UnregisterBarTimer(bar)
    elseif duration > 0 and expirationTime > 0
        and not IsSecretValue(auraData.duration)
        and not IsSecretValue(auraData.expirationTime)
    then
        RegisterBarTimer(bar)
    else
        UnregisterBarTimer(bar)
    end

    bar:Show()
end

-- Rebind bar fills for the given frames/unit when specific aura instances
-- update (used by the runtime to re-seat C-side DurationObjects). Mirrors
-- indicators.lua:RefreshUpdatedBars. Returns true if any bar was rebound.
function R.RefreshUpdatedBars(self, frames, nFrames, unit, updatedAuraInstanceIDs)
    if not frames or not updatedAuraInstanceIDs or #updatedAuraInstanceIDs == 0 then
        return false
    end
    local rebound = false
    for f = 1, nFrames do
        local frame = frames[f]
        local store = frame and frame[STATE_KEY]
        if frame and frame:IsShown() and store then
            for _, st in pairs(store) do
                local bar = st.bar
                local auraData = bar and bar._auraData
                local auraInstanceID = auraData and auraData.auraInstanceID
                if bar and bar:IsShown() and bar._unit == unit and auraInstanceID then
                    local matchUpdate = false
                    for i = 1, #updatedAuraInstanceIDs do
                        if updatedAuraInstanceIDs[i] == auraInstanceID then
                            matchUpdate = true
                            break
                        end
                    end
                    if matchUpdate then
                        if BindBarDurationObject(bar) then
                            ApplyBarColor(bar, GetBarConfig(bar._element), bar._element, nil)
                            UnregisterBarTimer(bar)
                            rebound = true
                        else
                            UpdateBarProgress(bar)
                        end
                    end
                end
            end
        end
    end
    return rebound
end

-- Fast path (pure stack/duration delta): reseat the C-side cooldown swipe on
-- any visible element icon whose aura instance updated, without rebuilding the
-- element list. Zero allocation; mirrors the old per-panel icon swipe refresh.
-- `frames` is the unitFrameMap list for `unit`.
function R.RefreshUpdatedIcons(self, frames, nFrames, unit, updatedAuraInstanceIDs)
    if not frames or not updatedAuraInstanceIDs or #updatedAuraInstanceIDs == 0 then
        return false
    end
    local GetDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if not GetDuration then return false end
    local n = #updatedAuraInstanceIDs
    for f = 1, nFrames do
        local frame = frames[f]
        local store = frame and frame[STATE_KEY]
        if frame and frame:IsShown() and frame.unit == unit and store then
            for _, st in pairs(store) do
                local icons = st.icons
                if icons then
                    for i = 1, #icons do
                        local icon = icons[i]
                        local instID = icon and icon._auraInstanceID
                        if instID and icon:IsShown() then
                            local hit = false
                            for j = 1, n do
                                if updatedAuraInstanceIDs[j] == instID then hit = true; break end
                            end
                            if hit then
                                local cd = icon.cooldown
                                if cd and cd.SetCooldownFromDurationObject then
                                    local dObj = GetDuration(unit, instID)
                                    if dObj then pcall(cd.SetCooldownFromDurationObject, cd, dObj, true) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- RENDERER: HEALTH TINT (adapted from indicators.lua:229-332, 1109-1176)
-- Tints the frame's health bar with element.color via the element's animation
-- mode; clears the tint when the tracked spell is absent.
---------------------------------------------------------------------------
local function GetOrCreateHealthTintOverlay(frame)
    if not frame or not frame.healthBar then
        return nil
    end
    local overlay = frame._quiAuraRenderHealthTintOverlay
    if not overlay then
        overlay = CreateFrame("StatusBar", nil, frame.healthBar)
        overlay:SetAllPoints(frame.healthBar)
        overlay:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
        overlay:SetMinMaxValues(0, 100)
        overlay:SetValue(0)
        overlay:SetAlpha(1)
        overlay:EnableMouse(false)
        overlay:Hide()
        frame._quiAuraRenderHealthTintOverlay = overlay
    end
    local texture = frame.healthBar:GetStatusBarTexture()
    overlay:SetStatusBarTexture(texture and texture:GetTexture() or GetStatusBarTexturePath())
    overlay:SetOrientation(frame._isVerticalFill and "VERTICAL" or "HORIZONTAL")
    if overlay.SetReverseFill then overlay:SetReverseFill(false) end
    overlay:SetAllPoints(frame.healthBar)
    overlay:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
    return overlay
end

local function HideHealthTintOverlay(frame)
    local overlay = frame and frame._quiAuraRenderHealthTintOverlay
    if not overlay then return end
    UnregisterHealthTintAnimation(overlay)
    overlay:SetAlpha(1)
    overlay:SetValue(0)
    overlay._quiTintWasShown = nil
    overlay:Hide()
end

function R.RenderHealthTint(self, frame, element, matches)
    if not frame then return end

    local auraData
    if element.spells then
        for _, sid in ipairs(element.spells) do
            local data = matches and matches[sid]
            if data then auraData = data; break end
        end
    end

    -- Record/clear which element owns the tint so a later element removal can
    -- be detected by R.Release.
    if not auraData then
        if frame._quiAuraRenderHealthTintOwner == element.id then
            frame._quiAuraRenderHealthTintOwner = nil
            frame._quiAuraRenderHealthTintColor = nil
            HideHealthTintOverlay(frame)
        end
        return
    end

    local htCfg = element.healthTint or nil
    local animation = NormalizeHealthTintAnimation(htCfg and htCfg.animation)
    local color = element.color or DEFAULT_HEALTH_COLOR

    frame._quiAuraRenderHealthTintOwner = element.id
    frame._quiAuraRenderHealthTintColor = color
    frame._quiAuraRenderHealthTintAnimation = animation

    local overlay = GetOrCreateHealthTintOverlay(frame)
    if not overlay then return end

    local r = color[1] or 0.2
    local g = color[2] or 0.8
    local b = color[3] or 0.2
    local a = color[4] or 1
    overlay:SetStatusBarColor(r, g, b, a)
    overlay:Show()

    -- Drive the overlay fill from the frame's current health. The runtime
    -- normally feeds healthPct via R.SyncHealthBarTint on UNIT_HEALTH; on the
    -- initial paint we start the animation toward a full bar and let the sync
    -- pass correct it. Any secret health value is handled inside the animation
    -- (canTweenValue gate) so nothing secret is compared here.
    local targetValue = SafeToNumber(frame._healthPct, 100)
    if not overlay._quiTintWasShown then
        overlay._quiTintWasShown = true
        StartHealthTintAnimation(overlay, animation, targetValue, 1)
    end
end

-- Feed live health into an active tint overlay (called by the runtime on
-- UNIT_HEALTH). `healthPct` may be secret; it is forwarded to SetValue and only
-- tweened when non-secret.
function R.SyncHealthBarTint(self, frame, healthPct, canShow)
    if not frame then return end
    local color = frame._quiAuraRenderHealthTintColor
    if not color or canShow == false then
        HideHealthTintOverlay(frame)
        return
    end
    local overlay = GetOrCreateHealthTintOverlay(frame)
    if not overlay then return end

    local r = color[1] or 0.2
    local g = color[2] or 0.8
    local b = color[3] or 0.2
    local a = color[4] or 1
    overlay:SetStatusBarColor(r, g, b, a)
    overlay:Show()

    local targetValue = healthPct or 0
    if not overlay._quiTintWasShown then
        overlay._quiTintWasShown = true
        StartHealthTintAnimation(overlay, frame._quiAuraRenderHealthTintAnimation, targetValue, 1)
    elseif overlay._quiTintAnimating then
        if overlay._quiTintTweenValue and not IsSecretValue(targetValue) and type(targetValue) == "number" then
            overlay._quiTintTargetValue = targetValue
        else
            overlay._quiTintTweenValue = nil
            overlay._quiTintTargetValue = targetValue
            overlay:SetValue(targetValue)
        end
        overlay._quiTintTargetAlpha = 1
    else
        overlay:SetValue(targetValue)
        overlay:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- RELEASE: hide/release one element's frames (used when an element is removed)
---------------------------------------------------------------------------
function R.Release(self, frame, elementID)
    if not frame then return end
    local store = frame[STATE_KEY]
    if not store then
        -- Health tint lives on the frame; clear if this element owned it.
        if elementID and frame._quiAuraRenderHealthTintOwner == elementID then
            frame._quiAuraRenderHealthTintOwner = nil
            frame._quiAuraRenderHealthTintColor = nil
            HideHealthTintOverlay(frame)
        end
        return
    end

    local st = store[elementID]
    if st then
        if st.icons then
            for idx = #st.icons, 1, -1 do
                ReleaseIconFrame(st.icons[idx])
                st.icons[idx] = nil
            end
        end
        if st.bar then
            ReleaseBarFrame(st.bar)
            st.bar = nil
        end
        if st.container then
            st.container:Hide()
        end
        store[elementID] = nil
    end

    if frame._quiAuraRenderHealthTintOwner == elementID then
        frame._quiAuraRenderHealthTintOwner = nil
        frame._quiAuraRenderHealthTintColor = nil
        HideHealthTintOverlay(frame)
    end
end

-- Release every element's frames on a unit frame (full teardown).
function R.ReleaseAll(self, frame)
    if not frame then return end
    local store = frame[STATE_KEY]
    if store then
        for id in pairs(store) do
            R.Release(self, frame, id)
        end
    end
    if frame._quiAuraRenderHealthTintOwner then
        frame._quiAuraRenderHealthTintOwner = nil
        frame._quiAuraRenderHealthTintColor = nil
    end
    HideHealthTintOverlay(frame)
end

---------------------------------------------------------------------------
-- DISPATCH: route an element to its renderer.
-- filterStrip => icon strip; tracked => element.displayType.
---------------------------------------------------------------------------
local DISPLAY_RENDERER = {
    icon = "RenderIcon",
    square = "RenderSquare",
    bar = "RenderBar",
    healthTint = "RenderHealthTint",
}

function R.Dispatch(self, frame, element, matches)
    if not element then return end
    if element.mode == "filterStrip" then
        return self.RenderIcon(self, frame, element, matches)
    end
    local method = DISPLAY_RENDERER[element.displayType]
    if method and self[method] then
        return self[method](self, frame, element, matches)
    end
end

---------------------------------------------------------------------------
-- DEBUG INSTRUMENTATION (dormant until QUI_Debug loads; gate-safe)
---------------------------------------------------------------------------
local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_Render_iconPool", tbl = iconPool }
    mp[#mp + 1] = { name = "GF_Render_barPool", tbl = barPool }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
end

return R
