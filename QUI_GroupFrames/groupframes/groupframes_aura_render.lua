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

local CHROME_LEVELS = (ns.QUI_GroupFrameChrome and ns.QUI_GroupFrameChrome.LEVELS)
    or { AURA_HOST = 12, AURA_BAR = 13 }

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local function IconLayout() return ns.QUI_GroupFrameIconLayout end

local function RenderIsSecretValue(v)
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

local function SkinBase() return ns.SkinBase end

local function GetFrameUnit(frame)
    local GF = ns.QUI_GroupFrames
    return GF and GF.GetFrameUnit and GF.GetFrameUnit(frame) or nil
end

local function GetFontPath(size)
    local sm = ns.LSM
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

local auraCountdownFormatter = false
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

local function ConfigureCountdown(cd, showText)
    if not cd then return end
    ns.SafeCallMethodIfPresent("sink-forward", cd, "SetHideCountdownNumbers", showText ~= true)
    if showText then
        local formatter = GetAuraCountdownFormatter()
        if formatter then
            ns.SafeCallMethodIfPresent("sink-forward", cd, "SetCountdownFormatter", formatter)
        end
    end
end

local function StyleCountdownText(cd, fontSize)
    if not cd then return end
    local ok, cdText = ns.SafeCallMethodIfPresent("sink-forward", cd, "GetCountdownFontString")
    if not ok or not cdText then return end
    CJKFont(cdText, GetFontPath(fontSize), fontSize or 9, "OUTLINE")
end

local math_max = math.max
local math_min = math.min

local activeHealthTintAnimations = {}
local activeHealthTintAnimationCount = 0
local healthTintAnimationFrame

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
    local canTweenValue = not RenderIsSecretValue(targetValue) and type(targetValue) == "number"

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
    else
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

local iconPool = {}
local barPool = {}

local function CreateIconFrame(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(16, 16)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = tex

    local br, bg, bb, ba = GetSkinBorderColor()
    SkinBase().ApplyPixelBackdrop(frame, 1, false, false, { br, bg, bb, ba })

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.cooldown = cd

    local solid = frame:CreateTexture(nil, "ARTWORK")
    solid:SetAllPoints()
    solid:SetColorTexture(1, 1, 1, 1)
    solid:Hide()
    frame.solidColor = solid

    local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop:SetColorTexture(0, 0, 0, 1)
    backdrop:SetAllPoints(frame)
    frame._quiBackdrop = backdrop

    local glossTex = frame:CreateTexture(nil, "OVERLAY")
    glossTex:SetTexture(ns.IconSkin and ns.IconSkin.GlossTexture)
    glossTex:SetBlendMode("ADD")
    glossTex:SetAllPoints(frame)
    frame._quiGloss = glossTex

    local function MakeTypeEdge()
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:Hide()
        return t
    end
    local tb = { top = MakeTypeEdge(), bottom = MakeTypeEdge(), left = MakeTypeEdge(), right = MakeTypeEdge() }
    tb.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tb.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); tb.top:SetHeight(1)
    tb.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    tb.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); tb.bottom:SetHeight(1)
    tb.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    tb.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); tb.left:SetWidth(1)
    tb.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tb.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); tb.right:SetWidth(1)
    frame._quiTypeBorder = tb

    local swipeBar = CreateFrame("StatusBar", nil, frame)
    swipeBar:SetAllPoints(frame)
    swipeBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    swipeBar:SetStatusBarColor(0, 0, 0, 0.6)
    swipeBar:SetFrameLevel(frame:GetFrameLevel())
    swipeBar:Hide()
    frame._swipeBar = swipeBar

    frame:Hide()
    return frame
end

local function ApplyAuraIconSkinOwnership(frame)
    if not frame then return end
    local profile = ns.Helpers and ns.Helpers.GetProfile and ns.Helpers.GetProfile()
    local extOn = profile and profile.quiGroupFrames and profile.quiGroupFrames.externalSkinning
    local Bridge = ns.ExternalSkinBridge
    if extOn and Bridge and Bridge.IsAvailable() then
        local r = frame._quiRegions
        if not r then r = {}; frame._quiRegions = r end
        r.Icon     = frame.icon
        r.Cooldown = frame.cooldown
        Bridge.AddButton("groupauras", frame, r)
        frame._quiBridged = true
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0) end
        if frame._quiBackdrop then frame._quiBackdrop:Hide() end
        if frame._quiGloss then frame._quiGloss:Hide() end
    else
        if frame._quiBridged and Bridge then
            Bridge.RemoveButton("groupauras", frame)
            frame._quiBridged = nil
            if frame.SetBackdropBorderColor then
                local br, bg, bb, ba = GetSkinBorderColor()
                frame:SetBackdropBorderColor(br, bg, bb, ba)
            end
        end
        local skinName = (profile and profile.quiGroupFrames and profile.quiGroupFrames.iconSkin) or "Default"
        if ns.IconSkin and skinName ~= "Default" then
            local rr = frame._quiRegions
            if not rr then rr = {}; frame._quiRegions = rr end
            rr.Backdrop = frame._quiBackdrop
            rr.Gloss    = frame._quiGloss
            ns.IconSkin.ApplySkin(frame, rr, skinName)
        else
            if frame._quiBackdrop then frame._quiBackdrop:Hide() end
            if frame._quiGloss then frame._quiGloss:Hide() end
        end
    end
end

local function AcquireIconFrame(parent)
    local item = table.remove(iconPool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
    else
        item = CreateIconFrame(parent)
    end
    ApplyAuraIconSkinOwnership(item)
    if item.icon then item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    item._cfgElement = nil
    return item
end

local function ReleaseIconFrame(item)
    if not item then return end
    item:Hide()
    item:ClearAllPoints()
    if item.cooldown then
        item.cooldown:Clear()
        ns.SafeCallMethodIfPresent("sink-forward", item.cooldown, "SetHideCountdownNumbers", true)
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

local activeTimerBars = {}
local activeTimerBarCount = 0
local barTimerFrame
local UpdateBarProgress

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

    local readableDuration = auraData.duration
    if not RenderIsSecretValue(readableDuration)
        and readableDuration ~= nil
        and SafeToNumber(readableDuration, 0) <= 0
    then
        return false
    end

    local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
    if not ok or not durationObj then
        return false
    end

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
        ApplyBarColor(bar, barCfg, element, nil)
        return
    end

    local duration = SafeToNumber(auraData.duration, 0)
    local expirationTime = SafeToNumber(auraData.expirationTime, 0)
    local remaining = nil
    local pct = 1
    if duration > 0 and expirationTime > 0
        and not RenderIsSecretValue(auraData.duration)
        and not RenderIsSecretValue(auraData.expirationTime)
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

-- >>> QUI_TEST_EXTRACT AuraBorderHelpers (sentinels used by
local function ShowTypeBorder(icon, color)
    local tb = icon._quiTypeBorder
    if not tb then return end
    local r, g, b, a = color:GetRGBA()
    tb.top:SetVertexColor(r, g, b, a)
    tb.bottom:SetVertexColor(r, g, b, a)
    tb.left:SetVertexColor(r, g, b, a)
    tb.right:SetVertexColor(r, g, b, a)
    tb.top:Show(); tb.bottom:Show(); tb.left:Show(); tb.right:Show()
    if icon.SetBackdropBorderColor then icon:SetBackdropBorderColor(0, 0, 0, 0) end
end

local function HideTypeBorder(icon)
    local tb = icon._quiTypeBorder
    if not tb then return end
    tb.top:Hide(); tb.bottom:Hide(); tb.left:Hide(); tb.right:Hide()
end

local function ApplyDebuffTypeBorder(icon, unit, element, auraData, borderCurve)
    if not borderCurve then return false end
    if not (element and element.auraType == "HARMFUL") then return false end
    if icon._quiBridged then return false end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor) then return false end
    local instID = auraData and auraData.auraInstanceID
    if not instID then return false end
    local ok, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, instID, borderCurve)
    if not ok then return false end
    -- @secret-policy: reject-secret-value
    if RenderIsSecretValue(color) then color = nil end
    if not color then return false end
    ShowTypeBorder(icon, color)
    return true
end
-- <<< QUI_TEST_EXTRACT AuraBorderHelpers

-- >>> QUI_TEST_EXTRACT ApplyLinearSwipe (sentinels used by
local function ApplyLinearSwipe(sb, unit, element, auraData)
    if not sb then return false end
    local style = (element and element.swipeStyle) or "radial"
    if style ~= "horizontal" and style ~= "vertical" then
        sb:Hide()
        return false
    end
    local instID = auraData and auraData.auraInstanceID
    if not (instID and C_UnitAuras and C_UnitAuras.GetAuraDuration and sb.SetTimerDuration) then
        sb:Hide()
        return false
    end
    local ok, durObj = pcall(C_UnitAuras.GetAuraDuration, unit, instID)
    if not ok or not durObj then
        sb:Hide()
        return false
    end
    sb:SetOrientation(style == "vertical" and "VERTICAL" or "HORIZONTAL")
    sb:SetTimerDuration(durObj, 0, (element.reverseSwipe and 0) or 1)
    local p = sb:GetParent()
    if p and sb.SetFrameLevel and p.GetFrameLevel then sb:SetFrameLevel(p:GetFrameLevel()) end
    sb:Show()
    return true
end
-- <<< QUI_TEST_EXTRACT ApplyLinearSwipe

local function ApplyIconData(icon, unit, element, auraData, cfgGen, br, bg, bb, ba, borderCurve)
    if icon.solidColor then icon.solidColor:Hide() end
    icon._auraInstanceID = auraData and auraData.auraInstanceID
    if icon.icon then
        icon.icon:Show()
        local tex = auraData and auraData.icon
        if tex then icon.icon:SetTexture(tex) end
    end

    local cd = icon.cooldown
    if cd then
        if icon._cfgElement ~= element or icon._cfgGen ~= cfgGen then
            icon._cfgElement = element
            icon._cfgGen = cfgGen
            local showText = element.showDurationText == true
            local H = ns.Helpers
            if H and H.ApplyCooldownSwipeStyle then
                H.ApplyCooldownSwipeStyle(cd, element)
            end
            ConfigureCountdown(cd, showText)
            if showText then
                StyleCountdownText(cd, element.durationFontSize or 9)
            end
        end

        local dur = auraData and auraData.duration
        local expTime = auraData and auraData.expirationTime
        if dur and expTime then
            -- ApplyCooldownFromAura prefers SetCooldownFromDurationObject
            local H = ns.Helpers
            if H and H.ApplyCooldownFromAura then
                H.ApplyCooldownFromAura(cd, unit, auraData.auraInstanceID, expTime, dur,
                    nil, auraData.timeMod)
            end
            ApplyLinearSwipe(icon._swipeBar, unit, element, auraData)
        else
            cd:Clear()
            if icon._swipeBar then icon._swipeBar:Hide() end
        end
    end

    icon:SetAlpha(1)
    if not ApplyDebuffTypeBorder(icon, unit, element, auraData, borderCurve) then
        HideTypeBorder(icon)
        icon:SetBackdropBorderColor(br, bg, bb, ba)
    end
end

function R.RenderIcon(self, frame, element, matches)
    if not frame then return end
    local unit = GetFrameUnit(frame)
    if not unit then return end
    local state = GetElementState(frame, element)

    local ordered = state._orderScratch or {}
    state._orderScratch = ordered
    for i = #ordered, 1, -1 do ordered[i] = nil end

    if element.mode == "tracked" and element.spells then
        for _, sid in ipairs(element.spells) do
            local data = matches and matches[sid]
            if data then ordered[#ordered + 1] = data end
        end
    elseif matches then
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

    local container = state.container
    if not container then
        container = CreateFrame("Frame", nil, frame)
        container:SetSize(1, 1)
        state.container = container
    end
    container:SetFrameLevel(frame:GetFrameLevel() + CHROME_LEVELS.AURA_HOST)
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

    local perRow = SafeToNumber(element.iconsPerRow, 0)
    if perRow < 0 then perRow = 0 end
    local rowDir
    if growDir == "UP" or growDir == "DOWN" then
        rowDir = (type(anchor) == "string" and anchor:find("RIGHT")) and "LEFT" or "RIGHT"
    else
        rowDir = (type(anchor) == "string" and anchor:find("BOTTOM")) and "UP" or "DOWN"
    end

    local IL = IconLayout()
    local iconAnchor = (IL and IL.GetIconAnchorForGrow and IL.GetIconAnchorForGrow(anchor, growDir))
        or anchor

    local layoutChanged = state._count ~= count
        or state._iconSize ~= iconSize
        or state._growDir ~= growDir
        or state._spacing ~= spacing
        or state._anchor ~= anchor
        or state._offX ~= offX
        or state._offY ~= offY
        or state._bottomPad ~= bottomPad
        or state._perRow ~= perRow
    state._count = count
    state._iconSize = iconSize
    state._growDir = growDir
    state._spacing = spacing
    state._anchor = anchor
    state._offX = offX
    state._offY = offY
    state._bottomPad = bottomPad
    state._perRow = perRow

    local br, bg, bb, ba = GetSkinBorderColor()
    local cfgGen = (ns.QUI_GroupFrameAuras and ns.QUI_GroupFrameAuras._configGeneration) or 0
    local borderCurve = ns.QUI_GroupFrameAuraBorderCurve and ns.QUI_GroupFrameAuraBorderCurve(frame._isRaid)

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
                slotX, slotY = IL.CalculateSlotOffset(idx, iconSize, spacing, growDir, count, perRow, rowDir)
            else
                slotX = (idx - 1) * (iconSize + spacing)
            end
            icon:SetPoint(iconAnchor, frame, anchor, offX + slotX, offY + slotY)
        end

        ApplyIconData(icon, unit, element, ordered[idx], cfgGen, br, bg, bb, ba, borderCurve)
        icon:Show()
    end

    for idx = #state.icons, count + 1, -1 do
        ReleaseIconFrame(state.icons[idx])
        state.icons[idx] = nil
    end

    for i = #ordered, 1, -1 do ordered[i] = nil end
end

function R.RenderSquare(self, frame, element, matches)
    if not frame then return end
    local unit = GetFrameUnit(frame)
    if not unit then return end
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
    icon:SetFrameLevel(frame:GetFrameLevel() + CHROME_LEVELS.AURA_HOST)
    icon:ClearAllPoints()
    icon:SetPoint(anchor, frame, anchor, offX, offY)

    local color = element.color or DEFAULT_SQUARE_COLOR
    if icon.icon then icon.icon:Hide() end
    if icon.cooldown then
        icon.cooldown:Hide()
        icon.cooldown:Clear()
    end
    if icon._swipeBar then icon._swipeBar:Hide() end
    if icon.solidColor then
        icon.solidColor:SetColorTexture(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5, color[4] or 1)
        icon.solidColor:Show()
    end
    icon:SetAlpha(1)
    local br, bg, bb, ba = GetSkinBorderColor()
    local borderCurve = ns.QUI_GroupFrameAuraBorderCurve and ns.QUI_GroupFrameAuraBorderCurve(frame._isRaid)
    if not ApplyDebuffTypeBorder(icon, unit, element, auraData, borderCurve) then
        HideTypeBorder(icon)
        icon:SetBackdropBorderColor(br, bg, bb, ba)
    end
    icon:Show()
end

function R.RenderBar(self, frame, element, matches)
    if not frame then return end
    local unit = GetFrameUnit(frame)
    if not unit then return end
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
    bar:SetFrameLevel(frame:GetFrameLevel() + CHROME_LEVELS.AURA_BAR)

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
            SkinBase().ApplyPixelBackdrop(bar, borderSize, false, false, { bcr, bcg, bcb, bca })
        end
    end

    bar._unit = unit
    bar._auraData = auraData
    bar._element = element
    bar._elapsed = 0
    UpdateBarProgress(bar)

    local duration = SafeToNumber(auraData.duration, 0)
    local expirationTime = SafeToNumber(auraData.expirationTime, 0)
    if bar._usesDurationObjectFill then
        UnregisterBarTimer(bar)
    elseif duration > 0 and expirationTime > 0
        and not RenderIsSecretValue(auraData.duration)
        and not RenderIsSecretValue(auraData.expirationTime)
    then
        RegisterBarTimer(bar)
    else
        UnregisterBarTimer(bar)
    end

    bar:Show()
end

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

-- >>> QUI_TEST_EXTRACT RefreshUpdatedIcons
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
        if frame and frame:IsShown() and GetFrameUnit(frame) == unit and store then
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
                                local dObj = GetDuration(unit, instID) -- @secret-safe: caller-gated — the fast-update (1910) and mixed-delta (cacheUpdated) paths both bail behind AurasAreSecret before reseating
                                local cd = icon.cooldown
                                if cd and dObj then
                                    ns.SafeCallMethodIfPresent("sink-forward", cd, "SetCooldownFromDurationObject", dObj, true)
                                end
                                local sb = icon._swipeBar
                                if sb and dObj then
                                    local el = icon._cfgElement
                                    ns.SafeCall("sink-forward", function()
                                        if sb:IsShown() then
                                            sb:SetTimerDuration(dObj, 0, (el and el.reverseSwipe and 0) or 1)
                                        end
                                    end)
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
-- <<< QUI_TEST_EXTRACT RefreshUpdatedIcons

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

local BORDER_OVERLAY_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local function GetOrCreateBorderOverlay(frame, thickness)
    if not frame then return nil end
    local anchorTo = frame.healthBar or frame
    local size = tonumber(thickness) or 2
    if size < 1 then size = 1 end
    local overlay = frame._quiAuraRenderBorderOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, anchorTo, "BackdropTemplate")
        overlay:EnableMouse(false)
        overlay:Hide()
        frame._quiAuraRenderBorderOverlay = overlay
    end
    if overlay._quiBorderSize ~= size and overlay.SetBackdrop then
        overlay._quiBorderSize = size
        overlay:SetBackdrop({ edgeFile = BORDER_OVERLAY_TEXTURE, edgeSize = size })
    end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", -size, size)
    overlay:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", size, -size)
    overlay:SetFrameLevel(frame:GetFrameLevel() + CHROME_LEVELS.AURA_HOST)
    return overlay
end

local function HideBorderOverlay(frame)
    local overlay = frame and frame._quiAuraRenderBorderOverlay
    if not overlay then return end
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

    local targetValue = SafeToNumber(frame._healthPct, 100)
    if not overlay._quiTintWasShown then
        overlay._quiTintWasShown = true
        StartHealthTintAnimation(overlay, animation, targetValue, 1)
    end
end

function R.RenderBorder(self, frame, element, matches)
    if not frame then return end

    local auraData
    if element.spells then
        for _, sid in ipairs(element.spells) do
            local data = matches and matches[sid]
            if data then auraData = data; break end
        end
    end

    if not auraData then
        if frame._quiAuraRenderBorderOwner == element.id then
            frame._quiAuraRenderBorderOwner = nil
            HideBorderOverlay(frame)
        end
        return
    end

    local bcfg = element.border or nil
    local thickness = (bcfg and bcfg.thickness) or 2
    local color = element.color or DEFAULT_HEALTH_COLOR

    frame._quiAuraRenderBorderOwner = element.id
    local overlay = GetOrCreateBorderOverlay(frame, thickness)
    if not overlay then return end

    local r = color[1] or 0.2
    local g = color[2] or 0.8
    local b = color[3] or 0.2
    local a = color[4] or 1
    overlay:SetBackdropBorderColor(r, g, b, a)
    overlay:Show()
end

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

    local targetValue = healthPct
    if not RenderIsSecretValue(targetValue) and targetValue == nil then
        targetValue = 0
    end
    if not overlay._quiTintWasShown then
        overlay._quiTintWasShown = true
        StartHealthTintAnimation(overlay, frame._quiAuraRenderHealthTintAnimation, targetValue, 1)
    elseif overlay._quiTintAnimating then
        if overlay._quiTintTweenValue and not RenderIsSecretValue(targetValue) and type(targetValue) == "number" then
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

function R.Release(self, frame, elementID)
    if not frame then return end
    local store = frame[STATE_KEY]
    if not store then
        if elementID and frame._quiAuraRenderHealthTintOwner == elementID then
            frame._quiAuraRenderHealthTintOwner = nil
            frame._quiAuraRenderHealthTintColor = nil
            HideHealthTintOverlay(frame)
        end
        if elementID and frame._quiAuraRenderBorderOwner == elementID then
            frame._quiAuraRenderBorderOwner = nil
            HideBorderOverlay(frame)
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

    if frame._quiAuraRenderBorderOwner == elementID then
        frame._quiAuraRenderBorderOwner = nil
        HideBorderOverlay(frame)
    end
end

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
    if frame._quiAuraRenderBorderOwner then
        frame._quiAuraRenderBorderOwner = nil
    end
    HideBorderOverlay(frame)
end

local DISPLAY_RENDERER = {
    icon = "RenderIcon",
    square = "RenderSquare",
    bar = "RenderBar",
    healthTint = "RenderHealthTint",
    border = "RenderBorder",
}

function R.Dispatch(self, frame, element, matches)
    if not element then return end
    if element.mode == "filterStrip" or element.mode == "missingRaidBuff" then
        return self.RenderIcon(self, frame, element, matches)
    end
    local method = DISPLAY_RENDERER[element.displayType]
    if method and self[method] then
        return self[method](self, frame, element, matches)
    end
end

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_Render_iconPool", tbl = iconPool }
    mp[#mp + 1] = { name = "GF_Render_barPool", tbl = barPool }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
end

return R
