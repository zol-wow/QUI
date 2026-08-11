local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

local function GetLuminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

local function IsDarkBackground(r, g, b)
    return GetLuminance(r, g, b) < 0.35
end

local function GetMPlusTimerSettings()
    local core = GetCore()
    if core and core.db and core.db.profile and core.db.profile.mplusTimer then
        return core.db.profile.mplusTimer
    end
    return { showBorder = true }
end

local function GetContrastColors(bgr, bgg, bgb)
    local isDark = IsDarkBackground(bgr, bgg, bgb)

    if isDark then
        return {
            text = { 1.0, 1.0, 1.0, 1 },
            textMuted = { 0.75, 0.75, 0.75, 1 },
            textRed = { 1.0, 0.45, 0.45, 1 },
            textGreen = { 0.45, 1.0, 0.65, 1 },
            textYellow = { 1.0, 0.9, 0.3, 1 },
            barBg = { 0.18, 0.18, 0.20, 1 },
            barBorder = 1.0,
        }
    else
        return {
            text = { 0.1, 0.1, 0.1, 1 },
            textMuted = { 0.3, 0.3, 0.3, 1 },
            textRed = { 0.8, 0.15, 0.15, 1 },
            textGreen = { 0.1, 0.6, 0.3, 1 },
            textYellow = { 0.7, 0.5, 0.0, 1 },
            barBg = { 0.15, 0.15, 0.15, 0.9 },
            barBorder = 0.5,
        }
    end
end

local function ApplyBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga, showBorder)
    if not frame then return end

    local backdrop = SkinBase.GetFrameData(frame, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(frame, "backdrop", backdrop)
    end

    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true)
    Helpers.SetFrameBackdropColor(backdrop, bgr, bgg, bgb, bga)

    local borderAlpha = showBorder and sa or 0
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, borderAlpha)
end

local function ApplyForcesTextColor(fontString, colors, settings)
    if settings and type(settings.forcesTextColor) == "table" then
        local r, g, b, a = unpack(settings.forcesTextColor)
        fontString:SetTextColor(r, g, b, a)
    else
        fontString:SetTextColor(colors.text[1], colors.text[2], colors.text[3], colors.text[4])
    end
end

local function ApplyBarSkin(bar, sr, sg, sb, br, bg, bb, colors, isTimerBar, barIndex, showBorder, settings)
    if not bar or not bar.frame then return end

    local barBg = colors.barBg
    local borderMult = colors.barBorder

    SkinBase.ApplyPixelBackdrop(bar.frame, 1, true, false)
    Helpers.SetFrameBackdropColor(bar.frame, barBg[1], barBg[2], barBg[3], barBg[4])

    local borderAlpha = showBorder and 1 or 0
    Helpers.SetFrameBackdropBorderColor(bar.frame, sr * borderMult, sg * borderMult, sb * borderMult, borderAlpha)

    if bar.bar then
        bar.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

        if isTimerBar then
            if barIndex == 3 then
                bar.bar:SetStatusBarColor(0.2, 0.85, 0.4, 1)
            elseif barIndex == 2 then
                bar.bar:SetStatusBarColor(0.95, 0.75, 0.2, 1)
            else
                bar.bar:SetStatusBarColor(br, bg, bb, 1)
            end
        else
            bar.bar:SetStatusBarColor(br, bg, bb, 1)
        end
    end

    if bar.overlay then
        bar.overlay:SetVertexColor(
            math.min(br * 1.3, 1),
            math.min(bg * 1.3, 1),
            math.min(bb * 1.3, 1),
            0.6
        )
    end

    if bar.text then
        if not isTimerBar then
            ApplyForcesTextColor(bar.text, colors, settings)
        else
            bar.text:SetTextColor(colors.text[1], colors.text[2], colors.text[3], colors.text[4])
        end
    end
end

local function ApplyMPlusTimerSkin()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    local MPlusTimer = _G.QUI_MPlusTimer
    if not MPlusTimer or not MPlusTimer.frames or not MPlusTimer.frames.root then
        return
    end

    local settings = GetMPlusTimerSettings()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings)
    local opacityMul = settings.frameBackgroundOpacity
    if opacityMul == nil then opacityMul = 1 end
    opacityMul = math.max(0, math.min(1, opacityMul))
    bga = math.max(0, math.min(1, bga * opacityMul))
    local br, bg, bb = SkinBase.GetSkinBarColor(settings)
    local colors = GetContrastColors(bgr, bgg, bgb)
    local showBorder = settings.showBorder ~= false

    ApplyBackdrop(MPlusTimer.frames.root, sr, sg, sb, sa, bgr, bgg, bgb, bga, showBorder)

    if MPlusTimer.frames.deathsText then
        MPlusTimer.frames.deathsText:SetTextColor(
            colors.textRed[1], colors.textRed[2], colors.textRed[3], colors.textRed[4]
        )
    end

    if MPlusTimer.frames.timerText then
        MPlusTimer.frames.timerText:SetTextColor(
            colors.text[1], colors.text[2], colors.text[3], colors.text[4]
        )
    end

    if MPlusTimer.frames.dungeonText then
        MPlusTimer.frames.dungeonText:SetTextColor(
            colors.text[1], colors.text[2], colors.text[3], colors.text[4]
        )
    end

    if MPlusTimer.frames.keyText then
        local kr, kg, kb = sr, sg, sb
        if IsDarkBackground(bgr, bgg, bgb) then
            local lum = GetLuminance(sr, sg, sb)
            if lum < 0.4 then
                kr = math.min(sr * 1.5, 1)
                kg = math.min(sg * 1.5, 1)
                kb = math.min(sb * 1.5, 1)
            end
        end
        MPlusTimer.frames.keyText:SetTextColor(kr, kg, kb, 1)
    end

    if MPlusTimer.frames.affixText then
        MPlusTimer.frames.affixText:SetTextColor(
            colors.textMuted[1], colors.textMuted[2], colors.textMuted[3], colors.textMuted[4]
        )
    end

    if MPlusTimer.bars then
        for i = 1, 3 do
            if MPlusTimer.bars[i] then
                ApplyBarSkin(MPlusTimer.bars[i], sr, sg, sb, br, bg, bb, colors, true, i, showBorder, settings)
            end
        end

        if MPlusTimer.bars.forces then
            ApplyBarSkin(MPlusTimer.bars.forces, sr, sg, sb, br, bg, bb, colors, false, nil, showBorder, settings)
        end
    end

    if MPlusTimer.frames.forcesLabelText then
        MPlusTimer.frames.forcesLabelText:SetTextColor(
            colors.textMuted[1], colors.textMuted[2], colors.textMuted[3], colors.textMuted[4]
        )
    end
    if MPlusTimer.frames.forcesValueText then
        ApplyForcesTextColor(MPlusTimer.frames.forcesValueText, colors, settings)
    end

    if MPlusTimer.frames.sleekBar then
        local barBg = colors.barBg
        local borderMult = colors.barBorder
        local borderAlpha = showBorder and 1 or 0
        SkinBase.ApplyPixelBackdrop(MPlusTimer.frames.sleekBar, 1, true, false)
        Helpers.SetFrameBackdropColor(MPlusTimer.frames.sleekBar, barBg[1], barBg[2], barBg[3], barBg[4])
        Helpers.SetFrameBackdropBorderColor(MPlusTimer.frames.sleekBar, sr * borderMult, sg * borderMult, sb * borderMult, borderAlpha)
    end

    if MPlusTimer.sleekSegments then
        if MPlusTimer.sleekSegments[3] then
            MPlusTimer.sleekSegments[3]:SetVertexColor(0.2, 0.85, 0.4, 1)
        end
        if MPlusTimer.sleekSegments[2] then
            MPlusTimer.sleekSegments[2]:SetVertexColor(0.95, 0.75, 0.2, 1)
        end
        if MPlusTimer.sleekSegments[1] then
            MPlusTimer.sleekSegments[1]:SetVertexColor(sr, sg, sb, 1)
        end
    end

    if MPlusTimer.frames.sleekPosMarker then
        MPlusTimer.frames.sleekPosMarker:SetVertexColor(1, 1, 1, 0.95)
    end

    if MPlusTimer.objectives then
        for i, objText in ipairs(MPlusTimer.objectives) do
            if objText and objText.SetTextColor then
                objText:SetTextColor(
                    colors.text[1], colors.text[2], colors.text[3], colors.text[4]
                )
            end
        end
    end

    SkinBase.MarkSkinned(MPlusTimer.frames.root)
    SkinBase.SetFrameData(MPlusTimer.frames.root, "colors", colors)
end

local function RefreshMPlusTimerColors()
    local MPlusTimer = _G.QUI_MPlusTimer
    if not MPlusTimer or not MPlusTimer.frames or not MPlusTimer.frames.root then
        return
    end
    if not SkinBase.IsSkinned(MPlusTimer.frames.root) then return end

    ApplyMPlusTimerSkin()
end

_G.QUI_ApplyMPlusTimerSkin = ApplyMPlusTimerSkin
_G.QUI_RefreshMPlusTimerColors = RefreshMPlusTimerColors

if ns.Registry then
    ns.Registry:Register("skinMPlusTimer", {
        refresh = _G.QUI_RefreshMPlusTimerColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "mplusTimer", label = ns.L["M+ Timer"], category = "HUD", prefix = "",
        db = function(p) return p.mplusTimer end,
        refresh = function() if _G.QUI_RefreshMPlusTimerColors then _G.QUI_RefreshMPlusTimerColors() end end,
        legacy = { override = "borderOverride", useClass = "borderUseClassColor" },
    })
end
