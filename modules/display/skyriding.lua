---------------------------------------------------------------------------
-- QUI Skyriding Module
-- Unified continuous vigor bar with segment markers
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI

local LSM = LibStub("LibSharedMedia-3.0")
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue

-- Constants
local VIGOR_SPELL_ID = 372608
local SECOND_WIND_SPELL_ID = 425782
local WHIRLING_SURGE_SPELL_ID = 361584

-- Frame references
local skyridingFrame
local vigorBar, vigorBackground, rechargeOverlay, shadowTexture
local flashTexture, flashAnim
local segmentMarkers = {}
local secondWindPips = {}
local vigorText, speedText
local secondWindText, secondWindMiniBar
local swBackground, swBorder, swRechargeOverlay
local swSegmentMarkers = {}
local abilityIcon, abilityIconCooldown

-- State tracking
local lastVigorCharges = -1
local lastMaxCharges = -1
local lastSecondWind = -1
local lastSecondWindMax = -1
local isGliding = false
local canGlide = false
local forwardSpeed = 0
local groundedTime = 0
local fadeStart = 0
local fadeStartAlpha = 1
local fadeTargetAlpha = 1
local inCombat = false

-- Smooth animation state
local targetBarValue = 0
local currentBarValue = 0
local swTargetValue = 0
local swCurrentValue = 0
local swMaxCharges = 0
local LERP_SPEED = 8  -- Higher = faster animation

-- Update throttling
local UPDATE_THROTTLE = 0.05  -- 50ms = 20 FPS
local elapsed = 0

-- Texture paths
local DOT_TEXTURE = "Interface\\AddOns\\QUI\\assets\\cursor\\qui_reticle_dot"

---------------------------------------------------------------------------
-- Settings Helper
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("skyriding")
end

local function Scale(x)
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.Scale then
        return QUICore:Scale(x)
    end
    return x
end

---------------------------------------------------------------------------
-- API Wrappers
---------------------------------------------------------------------------
local function GetVigorInfo()
    local data = C_Spell.GetSpellCharges(VIGOR_SPELL_ID)
    if not data then return 0, 6, 0, 0, 1 end

    -- Check for secret values (API restriction when not skyriding)
    if IsSecretValue(data.maxCharges) then
        return 0, 6, 0, 0, 1
    end

    return data.currentCharges or 0,
           data.maxCharges or 6,
           data.cooldownStartTime or 0,
           data.cooldownDuration or 0,
           data.chargeModRate or 1
end

local function GetSecondWindInfo()
    local data = C_Spell.GetSpellCharges(SECOND_WIND_SPELL_ID)
    if not data then return 0, 0, 0, 0, 1 end

    -- Check for secret values (API restriction)
    if IsSecretValue(data.maxCharges) then
        return 0, 0, 0, 0, 1
    end

    return data.currentCharges or 0,
           data.maxCharges or 0,
           data.cooldownStartTime or 0,
           data.cooldownDuration or 0,
           data.chargeModRate or 1
end

local function GetGlidingInfo()
    local gliding, canGlideNow, speed = C_PlayerInfo.GetGlidingInfo()
    return gliding or false, canGlideNow or false, speed or 0
end

---------------------------------------------------------------------------
-- Font Helper
---------------------------------------------------------------------------
local function GetFontPath()
    return Helpers.GetGeneralFont()
end

---------------------------------------------------------------------------
-- Cooldown Font Helper
---------------------------------------------------------------------------
local function ApplyCooldownFont(cooldown, fontSize)
    if not cooldown then return end
    local fontPath = GetFontPath()

    -- Method 1: Direct text property
    if cooldown.text then
        cooldown.text:SetFont(fontPath, fontSize, "OUTLINE")
    end

    -- Method 2: Iterate through cooldown regions
    local ok, regions = pcall(function() return { cooldown:GetRegions() } end)
    if ok and regions then
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                region:SetFont(fontPath, fontSize, "OUTLINE")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------
local function CreateSkyridingFrame()
    if skyridingFrame then return end

    local settings = GetSettings()
    local width = settings and settings.width or 250
    local height = settings and settings.vigorHeight or 12

    -- Main container frame
    skyridingFrame = CreateFrame("Frame", "QUI_Skyriding", UIParent)
    skyridingFrame:SetSize(width, height)
    skyridingFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    skyridingFrame:SetFrameStrata("MEDIUM")
    skyridingFrame:SetClampedToScreen(true)

    -- Shadow underneath (glass effect)
    shadowTexture = skyridingFrame:CreateTexture(nil, "BACKGROUND", nil, -2)
    shadowTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
    shadowTexture:SetPoint("TOPLEFT", skyridingFrame, "BOTTOMLEFT", 2, 0)
    shadowTexture:SetPoint("BOTTOMRIGHT", skyridingFrame, "BOTTOMRIGHT", -2, -3)
    shadowTexture:SetGradient("VERTICAL",
        CreateColor(0, 0, 0, 0),
        CreateColor(0, 0, 0, 0.5)
    )

    -- Background
    vigorBackground = skyridingFrame:CreateTexture(nil, "BACKGROUND")
    vigorBackground:SetAllPoints(skyridingFrame)
    vigorBackground:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Main vigor bar (StatusBar)
    vigorBar = CreateFrame("StatusBar", nil, skyridingFrame)
    vigorBar:SetAllPoints(skyridingFrame)
    vigorBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    vigorBar:SetStatusBarColor(0.2, 0.8, 1.0, 1)
    vigorBar:SetMinMaxValues(0, 1)
    vigorBar:SetValue(0)

    -- Recharge overlay (shows within current charging segment)
    rechargeOverlay = vigorBar:CreateTexture(nil, "OVERLAY")
    rechargeOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    rechargeOverlay:SetVertexColor(0.4, 0.9, 1.0, 0.6)
    rechargeOverlay:SetHeight(height)
    rechargeOverlay:Hide()

    -- Flash texture for charge complete animation (positioned dynamically per-segment)
    flashTexture = vigorBar:CreateTexture(nil, "OVERLAY", nil, 7)
    flashTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
    flashTexture:SetBlendMode("ADD")
    flashTexture:SetVertexColor(1, 1, 1, 0)
    flashTexture:Hide()
    -- Size/position set dynamically in UpdateVigorBar when a charge completes

    -- Flash animation group
    flashAnim = flashTexture:CreateAnimationGroup()
    local fadeIn = flashAnim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(0.5)
    fadeIn:SetDuration(0.08)
    fadeIn:SetOrder(1)
    local fadeOut = flashAnim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.5)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.25)
    fadeOut:SetOrder(2)
    flashAnim:SetScript("OnPlay", function() flashTexture:Show() end)
    flashAnim:SetScript("OnFinished", function() flashTexture:Hide() end)

    -- Border
    skyridingFrame.border = CreateFrame("Frame", nil, skyridingFrame, "BackdropTemplate")
    skyridingFrame.border:SetPoint("TOPLEFT", -1, 1)
    skyridingFrame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    skyridingFrame.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = Scale(1),
    })
    skyridingFrame.border:SetBackdropBorderColor(0, 0, 0, 1)
    if skyridingFrame.border.Center then skyridingFrame.border.Center:Hide() end

    -- Vigor text (left side)
    vigorText = vigorBar:CreateFontString(nil, "OVERLAY")
    vigorText:SetFont(GetFontPath(), 11, "OUTLINE")
    vigorText:SetPoint("LEFT", vigorBar, "LEFT", 4, 0)
    vigorText:SetTextColor(1, 1, 1, 1)

    -- Speed text (right side)
    speedText = vigorBar:CreateFontString(nil, "OVERLAY")
    speedText:SetFont(GetFontPath(), 11, "OUTLINE")
    speedText:SetPoint("RIGHT", vigorBar, "RIGHT", -4, 0)
    speedText:SetTextColor(1, 1, 1, 1)

    -- Second Wind text (alternative display)
    secondWindText = skyridingFrame:CreateFontString(nil, "OVERLAY")
    secondWindText:SetFont(GetFontPath(), 10, "OUTLINE")
    secondWindText:SetPoint("TOP", skyridingFrame, "BOTTOM", 0, -2)
    secondWindText:SetTextColor(1, 0.8, 0.2, 1)
    secondWindText:Hide()

    -- Create segment markers (up to 10 for flexibility)
    for i = 1, 10 do
        local marker = vigorBar:CreateTexture(nil, "ARTWORK", nil, 3)
        marker:SetTexture("Interface\\Buttons\\WHITE8x8")
        marker:SetVertexColor(0, 0, 0, 0.5)
        marker:SetWidth(Scale(1))
        marker:SetHeight(height)
        marker:Hide()
        segmentMarkers[i] = marker
    end

    -- Create Second Wind pips (up to 5) with glow
    for i = 1, 5 do
        -- Glow behind pip
        local glow = skyridingFrame:CreateTexture(nil, "ARTWORK", nil, -1)
        glow:SetTexture(DOT_TEXTURE)
        glow:SetBlendMode("ADD")
        glow:SetSize(14, 14)
        glow:SetVertexColor(1, 0.8, 0.2, 0.5)
        glow:Hide()

        -- Main pip (circular)
        local pip = skyridingFrame:CreateTexture(nil, "OVERLAY")
        pip:SetTexture(DOT_TEXTURE)
        pip:SetSize(6, 6)
        pip:Hide()

        pip.glow = glow
        secondWindPips[i] = pip
    end

    -- Second Wind mini bar (alternative display) with full visual treatment
    secondWindMiniBar = CreateFrame("StatusBar", nil, skyridingFrame)
    secondWindMiniBar:SetHeight(6)
    secondWindMiniBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    secondWindMiniBar:SetStatusBarColor(1, 0.8, 0.2, 1)
    secondWindMiniBar:SetMinMaxValues(0, 1)
    secondWindMiniBar:Hide()

    -- Second Wind background
    swBackground = secondWindMiniBar:CreateTexture(nil, "BACKGROUND")
    swBackground:SetAllPoints(secondWindMiniBar)
    swBackground:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Second Wind border
    swBorder = CreateFrame("Frame", nil, secondWindMiniBar, "BackdropTemplate")
    swBorder:SetPoint("TOPLEFT", -1, 1)
    swBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    swBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = Scale(1),
    })
    swBorder:SetBackdropBorderColor(0, 0, 0, 1)

    -- Second Wind segment markers (up to 5)
    for i = 1, 5 do
        local marker = secondWindMiniBar:CreateTexture(nil, "ARTWORK", nil, 3)
        marker:SetTexture("Interface\\Buttons\\WHITE8x8")
        marker:SetVertexColor(0, 0, 0, 0.5)
        marker:SetWidth(Scale(1))
        marker:Hide()
        swSegmentMarkers[i] = marker
    end

    -- Second Wind recharge overlay (shows progress within current charging segment)
    swRechargeOverlay = secondWindMiniBar:CreateTexture(nil, "OVERLAY")
    swRechargeOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    swRechargeOverlay:SetVertexColor(1, 0.9, 0.4, 0.6)  -- Slightly brighter gold
    swRechargeOverlay:SetHeight(6)
    swRechargeOverlay:Hide()

    -- Whirling Surge ability icon (right side of bar)
    abilityIcon = CreateFrame("Frame", nil, skyridingFrame)
    abilityIcon:SetSize(height, height)
    abilityIcon:SetPoint("LEFT", skyridingFrame, "RIGHT", 2, 0)

    -- Icon texture
    abilityIcon.texture = abilityIcon:CreateTexture(nil, "ARTWORK")
    abilityIcon.texture:SetAllPoints()
    local iconTexture = C_Spell.GetSpellTexture(WHIRLING_SURGE_SPELL_ID)
    abilityIcon.texture:SetTexture(iconTexture or 136116)
    abilityIcon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border (1px black, extends beyond icon)
    abilityIcon.border = CreateFrame("Frame", nil, abilityIcon, "BackdropTemplate")
    abilityIcon.border:SetPoint("TOPLEFT", -1, 1)
    abilityIcon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    abilityIcon.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = Scale(1),
    })
    abilityIcon.border:SetBackdropBorderColor(0, 0, 0, 1)

    -- Cooldown overlay
    abilityIconCooldown = CreateFrame("Cooldown", nil, abilityIcon, "CooldownFrameTemplate")
    abilityIconCooldown:SetAllPoints(abilityIcon.texture)
    abilityIconCooldown:SetDrawEdge(true)
    abilityIconCooldown:SetHideCountdownNumbers(false)

    -- Apply QUI font to cooldown text (deferred to ensure template is initialized)
    C_Timer.After(0, function()
        ApplyCooldownFont(abilityIconCooldown, 12)
    end)

    abilityIcon:Hide()  -- Hidden until skyriding

    -- Make draggable when unlocked
    skyridingFrame:SetMovable(true)
    skyridingFrame:EnableMouse(false)  -- Disabled by default (locked)
    skyridingFrame:RegisterForDrag("LeftButton")
    skyridingFrame:SetScript("OnDragStart", function(self)
        local settings = GetSettings()
        if settings and not settings.locked then
            self:StartMoving()
        end
    end)
    skyridingFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position relative to UIParent center
        local settings = GetSettings()
        if settings then
            local centerX, centerY = self:GetCenter()
            local uiCenterX, uiCenterY = UIParent:GetCenter()
            local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            settings.offsetX = math.floor((centerX - uiCenterX) * scale + 0.5)
            settings.offsetY = math.floor((centerY - uiCenterY) * scale + 0.5)
        end
    end)

    skyridingFrame:Hide()
end

---------------------------------------------------------------------------
-- Update Segment Markers
---------------------------------------------------------------------------
local function UpdateSegmentMarkers(maxCharges)
    local settings = GetSettings()
    if not settings or not skyridingFrame then return end

    local showSegments = settings.showSegments ~= false
    local barWidth = skyridingFrame:GetWidth()
    local barHeight = skyridingFrame:GetHeight()
    local segmentWidth = barWidth / maxCharges
    local thickness = Scale(settings.segmentThickness or 1)

    -- Use soft colors: 30% of bar color instead of harsh black
    local barColor = settings.barColor or {0.2, 0.8, 1.0, 1}
    local softColor = {
        barColor[1] * 0.25,
        barColor[2] * 0.25,
        barColor[3] * 0.25,
        0.6
    }

    for i = 1, 10 do
        local marker = segmentMarkers[i]
        if showSegments and i < maxCharges then
            local xPos = i * segmentWidth
            marker:ClearAllPoints()
            marker:SetPoint("LEFT", vigorBar, "LEFT", Scale(xPos - (thickness / 2)), 0)
            marker:SetWidth(math.max(Scale(1), thickness))
            marker:SetHeight(barHeight)
            marker:SetVertexColor(softColor[1], softColor[2], softColor[3], softColor[4])
            marker:Show()
        else
            marker:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Update Second Wind Display
---------------------------------------------------------------------------
local function UpdateSecondWind()
    local settings = GetSettings()
    if not settings or not skyridingFrame then return end

    local mode = settings.secondWindMode or "PIPS"
    local current, max, _, _, _ = GetSecondWindInfo()  -- Ignore cooldown data here (used in recharge func)

    -- Second Wind color (with class color support)
    local color
    if settings.useClassColorSecondWind then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            color = {classColor.r, classColor.g, classColor.b, 1}
        else
            color = settings.secondWindColor or {1, 0.8, 0.2, 1}
        end
    else
        color = settings.secondWindColor or {1, 0.8, 0.2, 1}
    end

    -- Hide all Second Wind elements first
    for i = 1, 5 do
        local pip = secondWindPips[i]
        pip:Hide()
        if pip.glow then pip.glow:Hide() end
        -- Hide SW segment markers too
        if swSegmentMarkers[i] then swSegmentMarkers[i]:Hide() end
    end
    secondWindText:Hide()
    secondWindMiniBar:Hide()

    -- If no Second Wind available, done
    if max == 0 then return end

    if mode == "PIPS" then
        local scale = settings.secondWindScale or 1.0
        local basePipSize = 6
        local baseGap = 4
        local baseGlowSize = 14

        local pipSize = basePipSize * scale
        local pipGap = baseGap * scale
        local glowSize = baseGlowSize * scale
        local totalWidth = (max * pipSize) + ((max - 1) * pipGap)
        local startX = -totalWidth / 2

        for i = 1, max do
            local pip = secondWindPips[i]
            local xPos = startX + ((i - 1) * (pipSize + pipGap))

            -- Position main pip
            pip:ClearAllPoints()
            pip:SetPoint("BOTTOM", skyridingFrame, "TOP", xPos + (pipSize / 2), 3)
            pip:SetSize(pipSize, pipSize)

            -- Position glow behind pip
            if pip.glow then
                pip.glow:ClearAllPoints()
                pip.glow:SetPoint("CENTER", pip, "CENTER", 0, 0)
                pip.glow:SetSize(glowSize, glowSize)
            end

            if i <= current then
                -- Active: bright gold with glow
                pip:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
                pip:Show()
                if pip.glow then
                    pip.glow:SetVertexColor(color[1], color[2], color[3], 0.5)
                    pip.glow:Show()
                end
            else
                -- Inactive: dim gray, no glow
                pip:SetVertexColor(0.25, 0.25, 0.25, 0.5)
                pip:Show()
                if pip.glow then pip.glow:Hide() end
            end
        end

    elseif mode == "TEXT" then
        secondWindText:SetText(string.format("SW: %d/%d", current, max))
        secondWindText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        secondWindText:Show()

    elseif mode == "MINIBAR" then
        local swHeight = settings.secondWindHeight or 6
        local barWidth = skyridingFrame:GetWidth()

        secondWindMiniBar:ClearAllPoints()
        secondWindMiniBar:SetPoint("TOPLEFT", skyridingFrame, "BOTTOMLEFT", 0, -2)
        secondWindMiniBar:SetPoint("TOPRIGHT", skyridingFrame, "BOTTOMRIGHT", 0, -2)
        secondWindMiniBar:SetHeight(swHeight)
        secondWindMiniBar:SetMinMaxValues(0, max)

        -- When charge completes: SNAP bar value (don't lerp)
        if current > lastSecondWind and lastSecondWind >= 0 then
            swCurrentValue = current / max
            secondWindMiniBar:SetValue(swCurrentValue * max)
        end

        -- Set target for smooth animation (lerp only applies when NOT completing a charge)
        swTargetValue = current / max
        swMaxCharges = max
        secondWindMiniBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        secondWindMiniBar:Show()

        -- Position segment markers for Second Wind
        local segmentWidth = barWidth / max
        local thickness = Scale(settings.segmentThickness or 1)
        local softColor = {
            color[1] * 0.25,
            color[2] * 0.25,
            color[3] * 0.25,
            0.6
        }

        for i = 1, 5 do
            local marker = swSegmentMarkers[i]
            if i < max then
                local xPos = i * segmentWidth
                marker:ClearAllPoints()
                marker:SetPoint("LEFT", secondWindMiniBar, "LEFT", Scale(xPos - (thickness / 2)), 0)
                marker:SetWidth(math.max(Scale(1), thickness))
                marker:SetHeight(swHeight)
                marker:SetVertexColor(softColor[1], softColor[2], softColor[3], softColor[4])
                marker:Show()
            else
                marker:Hide()
            end
        end
    end
    -- mode == "HIDDEN" does nothing (all hidden)

    -- Track last value for snap detection
    lastSecondWind = current
end

---------------------------------------------------------------------------
-- Update Vigor Bar
---------------------------------------------------------------------------
local function UpdateVigorBar()
    local settings = GetSettings()
    if not settings or not skyridingFrame then return end

    local current, max, startTime, duration, modRate = GetVigorInfo()

    -- Update segment markers if max changed
    if max ~= lastMaxCharges then
        UpdateSegmentMarkers(max)
        lastMaxCharges = max
    end

    -- When charge completes: SNAP bar value (don't lerp) then flash
    if current > lastVigorCharges and lastVigorCharges >= 0 then
        -- Snap the bar to include the completed segment immediately
        -- (the recharge overlay already showed the progress visually)
        currentBarValue = current / max
        vigorBar:SetValue(currentBarValue)

        -- Flash the completed segment
        if flashAnim and not flashAnim:IsPlaying() then
            local barWidth = skyridingFrame:GetWidth()
            local segmentWidth = barWidth / max
            local segmentStart = lastVigorCharges * segmentWidth
            flashTexture:ClearAllPoints()
            flashTexture:SetPoint("LEFT", vigorBar, "LEFT", segmentStart, 0)
            flashTexture:SetWidth(segmentWidth)
            flashTexture:SetHeight(skyridingFrame:GetHeight())
            flashAnim:Play()
        end
    end

    -- Set target for smooth animation (lerp only applies when NOT completing a charge)
    targetBarValue = current / max

    -- Update vigor text
    if settings.showVigorText ~= false then
        local format = settings.vigorTextFormat or "FRACTION"
        if format == "FRACTION" then
            vigorText:SetText(string.format("%d/%d", current, max))
        else
            vigorText:SetText(tostring(current))
        end
        vigorText:Show()
    else
        vigorText:Hide()
    end

    lastVigorCharges = current
end

---------------------------------------------------------------------------
-- Update Recharge Animation
---------------------------------------------------------------------------
local function UpdateRechargeAnimation()
    local settings = GetSettings()
    if not settings or not skyridingFrame then return end

    local current, max, startTime, duration, modRate = GetVigorInfo()

    -- If fully charged, hide overlay
    if current >= max or duration == 0 then
        rechargeOverlay:Hide()
        return
    end

    -- Calculate progress of current charge
    local now = GetTime()
    local elapsedTime = (now - startTime) * modRate
    local progress = math.min(1, elapsedTime / duration)

    -- Position recharge overlay within the current segment
    local barWidth = skyridingFrame:GetWidth()
    local segmentWidth = barWidth / max
    local segmentStart = current * segmentWidth
    local fillWidth = math.max(1, progress * segmentWidth)

    local color = settings.rechargeColor or {0.4, 0.9, 1.0, 0.6}

    rechargeOverlay:ClearAllPoints()
    rechargeOverlay:SetPoint("LEFT", vigorBar, "LEFT", segmentStart, 0)
    rechargeOverlay:SetWidth(fillWidth)
    rechargeOverlay:SetHeight(skyridingFrame:GetHeight())

    -- Pulse alpha for visual feedback
    local pulse = 0.7 + 0.3 * math.sin(now * 4)
    rechargeOverlay:SetVertexColor(color[1], color[2], color[3], (color[4] or 0.6) * pulse)
    rechargeOverlay:Show()
end

---------------------------------------------------------------------------
-- Update Second Wind Recharge Animation
---------------------------------------------------------------------------
local function UpdateSecondWindRecharge()
    local settings = GetSettings()
    if not settings or not secondWindMiniBar or not swRechargeOverlay then return end

    -- Only show for MINIBAR mode
    local mode = settings.secondWindMode or "PIPS"
    if mode ~= "MINIBAR" then
        swRechargeOverlay:Hide()
        return
    end

    local current, max, startTime, duration, modRate = GetSecondWindInfo()

    -- If no Second Wind available, fully charged, or not recharging, hide overlay
    if max == 0 or current >= max or duration == 0 then
        swRechargeOverlay:Hide()
        return
    end

    -- Calculate progress of current charge
    local now = GetTime()
    local elapsedTime = (now - startTime) * modRate
    local progress = math.min(1, elapsedTime / duration)

    -- Position recharge overlay within the current segment
    local barWidth = secondWindMiniBar:GetWidth()
    local barHeight = secondWindMiniBar:GetHeight()
    local segmentWidth = barWidth / max
    local segmentStart = current * segmentWidth
    local fillWidth = math.max(1, progress * segmentWidth)

    -- Use SW color (with class color support)
    local color
    if settings.useClassColorSecondWind then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            color = {classColor.r, classColor.g, classColor.b, 0.6}
        else
            color = {1, 0.9, 0.4, 0.6}
        end
    else
        color = {1, 0.9, 0.4, 0.6}  -- Slightly brighter gold
    end

    swRechargeOverlay:ClearAllPoints()
    swRechargeOverlay:SetPoint("LEFT", secondWindMiniBar, "LEFT", segmentStart, 0)
    swRechargeOverlay:SetWidth(fillWidth)
    swRechargeOverlay:SetHeight(barHeight)

    -- Pulse alpha for visual feedback
    local pulse = 0.7 + 0.3 * math.sin(now * 4)
    swRechargeOverlay:SetVertexColor(color[1], color[2], color[3], color[4] * pulse)
    swRechargeOverlay:Show()
end

---------------------------------------------------------------------------
-- Update Speed Display
---------------------------------------------------------------------------
local function UpdateSpeed()
    local settings = GetSettings()
    if not settings or not skyridingFrame then return end

    if settings.showSpeed == false then
        speedText:Hide()
        return
    end

    local _, _, speed = GetGlidingInfo()
    forwardSpeed = speed

    local format = settings.speedFormat or "PERCENT"
    if format == "PERCENT" then
        speedText:SetText(string.format("%d%%", math.floor(speed * 10)))
    else
        speedText:SetText(string.format("%.1f", speed))
    end
    speedText:Show()
end

---------------------------------------------------------------------------
-- Update Ability Icon (Whirling Surge)
---------------------------------------------------------------------------
local function UpdateAbilityIcon()
    if not abilityIcon or not abilityIconCooldown then return end

    local settings = GetSettings()
    if not settings then return end

    -- Check if ability icon is enabled (default true)
    if settings.showAbilityIcon == false then
        abilityIcon:Hide()
        return
    end

    -- Only show when skyriding is available
    -- Don't hide directly - let the parent frame's fade animation handle it
    local _, canGlideNow, _ = GetGlidingInfo()
    if not canGlideNow then
        return  -- Skip update, fade animation controls visibility
    end

    -- Calculate icon height to span both bars and center vertically
    local vigorHeight = settings.vigorHeight or 12
    local swHeight = settings.secondWindHeight or 6
    local swMode = settings.secondWindMode or "PIPS"
    local _, swMax = GetSecondWindInfo()

    local totalHeight = vigorHeight
    local yOffset = 0
    if swMode == "MINIBAR" and swMax > 0 then
        totalHeight = vigorHeight + 2 + swHeight  -- 2px gap between bars
        yOffset = -(2 + swHeight) / 2  -- Shift down to center on both bars
    end
    abilityIcon:SetSize(totalHeight, totalHeight)
    abilityIcon:ClearAllPoints()
    abilityIcon:SetPoint("LEFT", skyridingFrame, "RIGHT", 2, yOffset)

    -- Get cooldown info
    local cooldownInfo = C_Spell.GetSpellCooldown(WHIRLING_SURGE_SPELL_ID)
    if cooldownInfo and cooldownInfo.duration and not IsSecretValue(cooldownInfo.duration) and cooldownInfo.duration > 0 then
        abilityIconCooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
    else
        abilityIconCooldown:Clear()
    end

    abilityIcon:Show()
end

---------------------------------------------------------------------------
-- Fade Animation (matches CDM/unitframes pattern)
---------------------------------------------------------------------------
local function StartSkyridingFade(targetAlpha)
    if not skyridingFrame then return end

    local currentAlpha = skyridingFrame:GetAlpha()
    if math.abs(currentAlpha - targetAlpha) < 0.01 then return end

    fadeStart = GetTime()
    fadeStartAlpha = currentAlpha
    fadeTargetAlpha = targetAlpha
end

---------------------------------------------------------------------------
-- Update Visibility
---------------------------------------------------------------------------
local function UpdateVisibility()
    local settings = GetSettings()
    if not settings or not skyridingFrame then return end

    if not settings.enabled then
        skyridingFrame:Hide()
        return
    end

    local gliding, canGlideNow, _ = GetGlidingInfo()
    isGliding = gliding
    canGlide = canGlideNow

    local visibility = settings.visibility or "AUTO"
    local fadeDelay = settings.fadeDelay or 3

    -- Hide when in combat with secret values (API limitation)
    if inCombat and canGlideNow then
        local current, max = GetVigorInfo()
        if current == 0 and max == 6 then
            skyridingFrame:Hide()
            return
        end
    end

    if visibility == "ALWAYS" then
        skyridingFrame:Show()
        StartSkyridingFade(1)

    elseif visibility == "FLYING_ONLY" then
        if canGlideNow then
            skyridingFrame:Show()
            StartSkyridingFade(1)
        else
            StartSkyridingFade(0)
        end

    elseif visibility == "AUTO" then
        if isGliding then
            -- Flying - show immediately (no fade)
            groundedTime = 0
            fadeStart = 0  -- Cancel any fade in progress
            skyridingFrame:SetAlpha(1)
            -- Reset icon alpha (may have been faded)
            if abilityIcon then
                abilityIcon:SetAlpha(1)
                if abilityIconCooldown then
                    abilityIconCooldown:SetAlpha(1)
                end
            end
            skyridingFrame:Show()
        elseif canGlideNow then
            -- Can fly but grounded - fade after delay
            if groundedTime >= fadeDelay then
                StartSkyridingFade(0)
            else
                skyridingFrame:Show()
                StartSkyridingFade(1)
            end
        else
            -- Cannot fly here
            StartSkyridingFade(0)
        end
    end
end

---------------------------------------------------------------------------
-- Apply All Settings
---------------------------------------------------------------------------
local function ApplySettings()
    local settings = GetSettings()
    if not skyridingFrame then
        CreateSkyridingFrame()
    end
    if not settings then
        if skyridingFrame then skyridingFrame:Hide() end
        return
    end

    local width = settings.width or 250
    local height = settings.vigorHeight or 12
    local offsetX = settings.offsetX or 0
    local offsetY = settings.offsetY or -150
    local locked = settings.locked ~= false

    -- Size and position
    skyridingFrame:SetSize(width, height)
    skyridingFrame:ClearAllPoints()
    skyridingFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)

    -- Apply HUD layer priority
    local QUICore = _G.QUI and _G.QUI.QUICore
    local db = QUICore and QUICore.db and QUICore.db.profile
    local layerPriority = db and db.hudLayering and db.hudLayering.skyridingHUD or 5
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        skyridingFrame:SetFrameLevel(frameLevel)
    end

    -- Draggable state
    skyridingFrame:EnableMouse(not locked)

    -- Bar texture
    local textureName = settings.barTexture or "Solid"
    local texturePath = LSM:Fetch("statusbar", textureName) or "Interface\\Buttons\\WHITE8x8"
    vigorBar:SetStatusBarTexture(texturePath)
    if secondWindMiniBar then
        secondWindMiniBar:SetStatusBarTexture(texturePath)
    end

    -- Bar colors (with class color support)
    local barColor
    if settings.useClassColorVigor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            barColor = {classColor.r, classColor.g, classColor.b, 1}
        else
            barColor = settings.barColor or {0.2, 0.8, 1.0, 1}
        end
    else
        barColor = settings.barColor or {0.2, 0.8, 1.0, 1}
    end
    vigorBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] or 1)

    -- Background color
    local bgColor = settings.backgroundColor or {0.1, 0.1, 0.1, 0.8}
    vigorBackground:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)

    -- Second Wind background color (separate setting)
    local swBgColor = settings.secondWindBackgroundColor or bgColor
    if swBackground then
        swBackground:SetColorTexture(swBgColor[1], swBgColor[2], swBgColor[3], swBgColor[4] or 0.8)
    end

    -- Border
    local borderSize = settings.borderSize or 1
    local borderColor = settings.borderColor or {0, 0, 0, 1}
    skyridingFrame.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = borderSize,
    })
    skyridingFrame.border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    if skyridingFrame.border.Center then skyridingFrame.border.Center:Hide() end

    -- Recharge overlay height
    rechargeOverlay:SetHeight(height)

    -- Font sizes
    local vigorFontSize = settings.vigorFontSize or 11
    local speedFontSize = settings.speedFontSize or 11
    local fontPath = GetFontPath()
    vigorText:SetFont(fontPath, vigorFontSize, "OUTLINE")
    speedText:SetFont(fontPath, speedFontSize, "OUTLINE")

    -- Refresh ability icon cooldown font
    if abilityIconCooldown then
        ApplyCooldownFont(abilityIconCooldown, vigorFontSize)
    end

    -- Update segment markers
    local _, max = GetVigorInfo()
    UpdateSegmentMarkers(max)

    -- Update all displays
    UpdateVigorBar()
    UpdateRechargeAnimation()
    UpdateSecondWind()
    UpdateSpeed()
    UpdateAbilityIcon()
    UpdateVisibility()
end

---------------------------------------------------------------------------
-- OnUpdate Handler (Throttled)
---------------------------------------------------------------------------
local function OnUpdate(self, delta)
    elapsed = elapsed + delta
    if elapsed < UPDATE_THROTTLE then return end
    elapsed = 0

    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    -- Track grounded time for auto-fade
    local gliding, canGlideNow, _ = GetGlidingInfo()
    if not gliding and canGlideNow then
        groundedTime = groundedTime + UPDATE_THROTTLE
    else
        groundedTime = 0
    end

    -- Smooth bar animation (lerp toward target)
    if currentBarValue ~= targetBarValue then
        local diff = targetBarValue - currentBarValue
        if math.abs(diff) < 0.005 then
            -- Snap when very close
            currentBarValue = targetBarValue
        else
            -- Smooth interpolation
            currentBarValue = currentBarValue + diff * LERP_SPEED * UPDATE_THROTTLE
        end
        vigorBar:SetValue(currentBarValue)
    end

    -- Time-based fade animation (matches CDM/unitframes pattern)
    if fadeStart > 0 then
        local now = GetTime()
        local elapsedTime = now - fadeStart
        local fadeDuration = settings.fadeDuration or 0.3
        local progress = math.min(elapsedTime / fadeDuration, 1)

        -- Linear interpolation
        local alpha = fadeStartAlpha + (fadeTargetAlpha - fadeStartAlpha) * progress
        skyridingFrame:SetAlpha(alpha)

        -- Explicitly fade icon components (CooldownFrameTemplate may not inherit parent alpha)
        if abilityIcon then
            abilityIcon:SetAlpha(alpha)
            if abilityIconCooldown then
                abilityIconCooldown:SetAlpha(alpha)
            end
        end

        -- Check if fade complete
        if progress >= 1 then
            fadeStart = 0  -- Stop fading
            if fadeTargetAlpha < 0.01 then
                skyridingFrame:Hide()
            end
        end
    end

    -- Smooth Second Wind bar animation (lerp toward target)
    if swCurrentValue ~= swTargetValue and swMaxCharges > 0 then
        local diff = swTargetValue - swCurrentValue
        if math.abs(diff) < 0.005 then
            -- Snap when very close
            swCurrentValue = swTargetValue
        else
            -- Smooth interpolation
            swCurrentValue = swCurrentValue + diff * LERP_SPEED * UPDATE_THROTTLE
        end
        secondWindMiniBar:SetValue(swCurrentValue * swMaxCharges)
    end

    -- Update displays
    UpdateVigorBar()
    UpdateRechargeAnimation()
    UpdateSecondWind()
    UpdateSecondWindRecharge()
    UpdateSpeed()
    UpdateAbilityIcon()
    UpdateVisibility()
end

---------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
eventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            CreateSkyridingFrame()
            ApplySettings()
            -- Start OnUpdate for animations
            if skyridingFrame then
                skyridingFrame:SetScript("OnUpdate", OnUpdate)
            end
        end)
    elseif event == "PLAYER_CAN_GLIDE_CHANGED" then
        canGlide = arg1
        UpdateVisibility()
    elseif event == "PLAYER_IS_GLIDING_CHANGED" then
        isGliding = arg1
        groundedTime = 0
        UpdateVisibility()
    elseif event == "UPDATE_BONUS_ACTIONBAR" or event == "SPELL_UPDATE_CHARGES" then
        if skyridingFrame and skyridingFrame:IsShown() then
            UpdateVigorBar()
            UpdateSecondWind()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if skyridingFrame and skyridingFrame:IsShown() then
            UpdateAbilityIcon()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateVisibility()
    end
end)

---------------------------------------------------------------------------
-- Global Refresh Function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshSkyriding = ApplySettings

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
QUI.Skyriding = {
    Refresh = ApplySettings,
    Create = CreateSkyridingFrame,
    UpdateVisibility = UpdateVisibility,
}
