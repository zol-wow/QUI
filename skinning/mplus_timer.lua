---------------------------------------------------------------------------
-- QUI Mythic+ Timer Skinning
-- Applies QUI skin colors to the custom M+ timer frame
-- Frame created in utils/qui_mplus_timer.lua
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Utility: Calculate luminance to determine if color is "dark"
---------------------------------------------------------------------------
local function GetLuminance(r, g, b)
    -- Standard luminance formula (perceived brightness)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

local function IsDarkBackground(r, g, b)
    return GetLuminance(r, g, b) < 0.35
end

---------------------------------------------------------------------------
-- Get QUI Skin Colors
---------------------------------------------------------------------------
local function GetSkinColors()
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1       -- Fallback mint
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95  -- Fallback dark

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

---------------------------------------------------------------------------
-- Get M+ Timer Settings
---------------------------------------------------------------------------
local function GetMPlusTimerSettings()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.mplusTimer then
        return QUICore.db.profile.mplusTimer
    end
    return { showBorder = true }
end

---------------------------------------------------------------------------
-- Get contrast-aware colors based on background
---------------------------------------------------------------------------
local function GetContrastColors(bgr, bgg, bgb)
    local isDark = IsDarkBackground(bgr, bgg, bgb)

    if isDark then
        -- Dark background: use light text, lighter bar backgrounds to stand out from frame
        return {
            text = { 1.0, 1.0, 1.0, 1 },              -- Pure white
            textMuted = { 0.75, 0.75, 0.75, 1 },      -- Lighter grey
            textRed = { 1.0, 0.45, 0.45, 1 },         -- Bright red
            textGreen = { 0.45, 1.0, 0.65, 1 },       -- Bright green
            textYellow = { 1.0, 0.9, 0.3, 1 },        -- Bright yellow
            barBg = { 0.18, 0.18, 0.20, 1 },          -- Lighter bar bg to contrast with dark frame
            barBorder = 1.0,                          -- Full brightness borders
        }
    else
        -- Light background: use dark text
        return {
            text = { 0.1, 0.1, 0.1, 1 },              -- Dark text
            textMuted = { 0.3, 0.3, 0.3, 1 },         -- Medium grey
            textRed = { 0.8, 0.15, 0.15, 1 },         -- Dark red
            textGreen = { 0.1, 0.6, 0.3, 1 },         -- Dark green
            textYellow = { 0.7, 0.5, 0.0, 1 },        -- Dark yellow/gold
            barBg = { 0.15, 0.15, 0.15, 0.9 },        -- Dark bar background
            barBorder = 0.5,                          -- Border multiplier
        }
    end
end

---------------------------------------------------------------------------
-- Apply Backdrop to Frame
---------------------------------------------------------------------------
local function ApplyBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga, showBorder)
    if not frame then return end

    if not frame.quiBackdrop then
        frame.quiBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.quiBackdrop:SetAllPoints()
        frame.quiBackdrop:SetFrameLevel(math.max(1, frame:GetFrameLevel() - 1))
        frame.quiBackdrop:EnableMouse(false)
    end

    frame.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)

    -- Border visibility controlled by showBorder setting (alpha 0 when hidden)
    local borderAlpha = showBorder and sa or 0
    frame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, borderAlpha)
end

---------------------------------------------------------------------------
-- Apply Bar Styling
---------------------------------------------------------------------------
local function ApplyBarSkin(bar, sr, sg, sb, colors, isTimerBar, barIndex, showBorder)
    if not bar or not bar.frame then return end

    local barBg = colors.barBg
    local borderMult = colors.barBorder

    -- Bar container backdrop - use contrast-aware background
    bar.frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    bar.frame:SetBackdropColor(barBg[1], barBg[2], barBg[3], barBg[4])

    -- Border visibility controlled by showBorder setting
    local borderAlpha = showBorder and 1 or 0
    bar.frame:SetBackdropBorderColor(sr * borderMult, sg * borderMult, sb * borderMult, borderAlpha)

    -- Status bar color
    if bar.bar then
        bar.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

        if isTimerBar then
            -- Timer bars: gradient from green (+3) to yellow (+2) to accent (+1)
            if barIndex == 3 then
                -- +3 bar (leftmost) - green
                bar.bar:SetStatusBarColor(0.2, 0.85, 0.4, 1)
            elseif barIndex == 2 then
                -- +2 bar (middle) - yellow
                bar.bar:SetStatusBarColor(0.95, 0.75, 0.2, 1)
            else
                -- +1 bar (rightmost) - accent color
                bar.bar:SetStatusBarColor(sr, sg, sb, 1)
            end
        else
            -- Forces bar - accent color
            bar.bar:SetStatusBarColor(sr, sg, sb, 1)
        end
    end

    -- Pull overlay texture (forces bar only)
    if bar.overlay then
        -- Slightly brighter version of accent for pull preview
        bar.overlay:SetVertexColor(
            math.min(sr * 1.3, 1),
            math.min(sg * 1.3, 1),
            math.min(sb * 1.3, 1),
            0.6
        )
    end

    -- Bar text - use contrast-aware text color
    if bar.text then
        bar.text:SetTextColor(colors.text[1], colors.text[2], colors.text[3], colors.text[4])
    end
end

---------------------------------------------------------------------------
-- Main Skin Application
---------------------------------------------------------------------------
local function ApplyMPlusTimerSkin()
    local MPlusTimer = _G.QUI_MPlusTimer
    if not MPlusTimer or not MPlusTimer.frames or not MPlusTimer.frames.root then
        return
    end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    local colors = GetContrastColors(bgr, bgg, bgb)
    local settings = GetMPlusTimerSettings()
    local showBorder = settings.showBorder ~= false  -- Default true

    -- Root frame backdrop
    ApplyBackdrop(MPlusTimer.frames.root, sr, sg, sb, sa, bgr, bgg, bgb, bga, showBorder)

    -- Deaths text (red)
    if MPlusTimer.frames.deathsText then
        MPlusTimer.frames.deathsText:SetTextColor(
            colors.textRed[1], colors.textRed[2], colors.textRed[3], colors.textRed[4]
        )
    end

    -- Timer text
    if MPlusTimer.frames.timerText then
        MPlusTimer.frames.timerText:SetTextColor(
            colors.text[1], colors.text[2], colors.text[3], colors.text[4]
        )
    end

    -- Dungeon name text
    if MPlusTimer.frames.dungeonText then
        MPlusTimer.frames.dungeonText:SetTextColor(
            colors.text[1], colors.text[2], colors.text[3], colors.text[4]
        )
    end

    -- Key level text (accent color - but ensure visibility)
    if MPlusTimer.frames.keyText then
        -- Use accent but boost brightness if needed for dark backgrounds
        local kr, kg, kb = sr, sg, sb
        if IsDarkBackground(bgr, bgg, bgb) then
            -- Ensure accent is bright enough on dark bg
            local lum = GetLuminance(sr, sg, sb)
            if lum < 0.4 then
                kr = math.min(sr * 1.5, 1)
                kg = math.min(sg * 1.5, 1)
                kb = math.min(sb * 1.5, 1)
            end
        end
        MPlusTimer.frames.keyText:SetTextColor(kr, kg, kb, 1)
    end

    -- Affixes text (muted) - legacy, usually hidden
    if MPlusTimer.frames.affixText then
        MPlusTimer.frames.affixText:SetTextColor(
            colors.textMuted[1], colors.textMuted[2], colors.textMuted[3], colors.textMuted[4]
        )
    end

    -- Timer bars (+3, +2, +1)
    if MPlusTimer.bars then
        for i = 1, 3 do
            if MPlusTimer.bars[i] then
                ApplyBarSkin(MPlusTimer.bars[i], sr, sg, sb, colors, true, i, showBorder)
            end
        end

        -- Forces bar
        if MPlusTimer.bars.forces then
            ApplyBarSkin(MPlusTimer.bars.forces, sr, sg, sb, colors, false, nil, showBorder)
        end
    end

    -- Sleek mode: Segmented bar backdrop
    if MPlusTimer.frames.sleekBar then
        local barBg = colors.barBg
        local borderMult = colors.barBorder
        local borderAlpha = showBorder and 1 or 0

        MPlusTimer.frames.sleekBar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        MPlusTimer.frames.sleekBar:SetBackdropColor(barBg[1], barBg[2], barBg[3], barBg[4])
        MPlusTimer.frames.sleekBar:SetBackdropBorderColor(sr * borderMult, sg * borderMult, sb * borderMult, borderAlpha)
    end

    -- Sleek mode: Update segment colors to use accent for +1
    if MPlusTimer.sleekSegments then
        -- +3 segment: green
        if MPlusTimer.sleekSegments[3] then
            MPlusTimer.sleekSegments[3]:SetVertexColor(0.2, 0.85, 0.4, 1)
        end
        -- +2 segment: yellow
        if MPlusTimer.sleekSegments[2] then
            MPlusTimer.sleekSegments[2]:SetVertexColor(0.95, 0.75, 0.2, 1)
        end
        -- +1 segment: accent color
        if MPlusTimer.sleekSegments[1] then
            MPlusTimer.sleekSegments[1]:SetVertexColor(sr, sg, sb, 1)
        end
    end

    -- Sleek mode: Position marker
    if MPlusTimer.frames.sleekPosMarker then
        -- White marker for visibility
        MPlusTimer.frames.sleekPosMarker:SetVertexColor(1, 1, 1, 0.95)
    end

    -- Sleek mode: Pace text (color handled dynamically in RenderTimer based on pace status)

    -- Objective texts
    if MPlusTimer.objectives then
        for i, objText in ipairs(MPlusTimer.objectives) do
            if objText and objText.SetTextColor then
                objText:SetTextColor(
                    colors.text[1], colors.text[2], colors.text[3], colors.text[4]
                )
            end
        end
    end

    -- Store colors for refresh
    MPlusTimer.frames.root.quiSkinned = true
    MPlusTimer.frames.root.quiColors = colors
end

---------------------------------------------------------------------------
-- Color Refresh (for live preview in options)
---------------------------------------------------------------------------
local function RefreshMPlusTimerColors()
    local MPlusTimer = _G.QUI_MPlusTimer
    if not MPlusTimer or not MPlusTimer.frames or not MPlusTimer.frames.root then
        return
    end
    if not MPlusTimer.frames.root.quiSkinned then return end

    -- Re-apply full skin to pick up new contrast colors
    ApplyMPlusTimerSkin()
end

---------------------------------------------------------------------------
-- Expose Functions Globally
---------------------------------------------------------------------------
_G.QUI_ApplyMPlusTimerSkin = ApplyMPlusTimerSkin
_G.QUI_RefreshMPlusTimerColors = RefreshMPlusTimerColors
