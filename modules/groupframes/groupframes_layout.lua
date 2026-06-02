--[[ QUI Group Frames - Layout and Secure Header Management ]]
local ADDON_NAME, ns = ...
local QUI_GF = ns.QUI_GroupFrames
if not QUI_GF then return end
local _ = QUI_GF._
if not _ then return end

local QUICore = _.QUICore
local Helpers = _.Helpers
local IsSecretValue = _.IsSecretValue
local _state = _.state
local _pending = _.pending
local COLORS = _.COLORS
local MAX_RAID_SECTION_HEADERS = _.MAX_RAID_SECTION_HEADERS
local RAID_SECTION_ROLE_PRIORITY = _.RAID_SECTION_ROLE_PRIORITY
local RAID_SECTION_CLASS_PRIORITY = _.RAID_SECTION_CLASS_PRIORITY
local AddFrameToMap = _.AddFrameToMap
local RemoveFrameFromMap = _.RemoveFrameFromMap
local GetSettings = _.GetSettings
local GetPartySelfFirst = _.GetPartySelfFirst
local GetRaidSelfFirst = _.GetRaidSelfFirst
local UseRaidSectionHeaders = _.UseRaidSectionHeaders
local GetLayoutGrowDirection = _.GetLayoutGrowDirection
local GetRaidColumnAnchorPoint = _.GetRaidColumnAnchorPoint
local GetVisualDB = _.GetVisualDB
local GetGeneralSettings = _.GetGeneralSettings
local GetLayoutSettings = _.GetLayoutSettings
local GetHealthSettings = _.GetHealthSettings
local GetPowerSettings = _.GetPowerSettings
local GetNameSettings = _.GetNameSettings
local GetIndicatorSettings = _.GetIndicatorSettings
local GetHealerSettings = _.GetHealerSettings
local GetPortraitSettings = _.GetPortraitSettings
local GetHealthFillDirection = _.GetHealthFillDirection
local GetFontPath = _.GetFontPath
local GetFontOutline = _.GetFontOutline
local GetTextAnchorInfo = _.GetTextAnchorInfo
local GetFrameDimensions = _.GetFrameDimensions
local GetGroupMode = _.GetGroupMode
local CalculateHeaderSize = _.CalculateHeaderSize
local ShowUnitTooltip = _.ShowUnitTooltip
local HideUnitTooltip = _.HideUnitTooltip
local ApplyStatusBarTexture = _.ApplyStatusBarTexture
local GetCachedBackdrop = _.GetCachedBackdrop
local EnsureBackdrop = _.EnsureBackdrop
local SetBackdropFillColor = _.SetBackdropFillColor
local UpdateDarkModeVisuals = _.UpdateDarkModeVisuals
local UpdateHealth = _.UpdateHealth
local UpdatePower = _.UpdatePower
local UpdateName = _.UpdateName
local UpdateAbsorbs = _.UpdateAbsorbs
local UpdateHealAbsorb = _.UpdateHealAbsorb
local UpdateHealPrediction = _.UpdateHealPrediction
local UpdateRoleIcon = _.UpdateRoleIcon
local UpdateReadyCheck = _.UpdateReadyCheck
local UpdateResurrection = _.UpdateResurrection
local UpdateSummonPending = _.UpdateSummonPending
local UpdateThreat = _.UpdateThreat
local UpdateTargetMarker = _.UpdateTargetMarker
local UpdateLeaderIcon = _.UpdateLeaderIcon
local UpdatePhaseIcon = _.UpdatePhaseIcon
local UpdateConnection = _.UpdateConnection
local UpdateTargetHighlight = _.UpdateTargetHighlight
local UpdateDispelOverlay = _.UpdateDispelOverlay
local UpdateDefensiveIndicator = _.UpdateDefensiveIndicator
local UpdatePortrait = _.UpdatePortrait
local function RebuildUnitFrameMap() if _.RebuildUnitFrameMap then _.RebuildUnitFrameMap() end end
local function RefreshClickCastFrames() if _.RefreshClickCastFrames then _.RefreshClickCastFrames() end end
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local wipe = wipe
local tostring = tostring
local table_insert = table.insert
local table_concat = table.concat
local table_sort = table.sort
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local string_format = string.format
local GetRaidDisplaySections
local GetRaidSectionUnitsPerColumn
local CalculateRaidSectionHeaderSize

local function UpdateFrame(frame)
    if not frame or not frame.unit then return end
    UpdateDarkModeVisuals(frame, true)
    UpdateHealth(frame)
    UpdatePower(frame)
    UpdateName(frame)
    UpdateAbsorbs(frame)
    UpdateHealAbsorb(frame)
    UpdateHealPrediction(frame)
    UpdateRoleIcon(frame)
    UpdateReadyCheck(frame)
    UpdateResurrection(frame)
    UpdateSummonPending(frame)
    UpdateThreat(frame)
    UpdateTargetMarker(frame)
    UpdateLeaderIcon(frame)
    UpdatePhaseIcon(frame)
    UpdateConnection(frame)
    UpdateTargetHighlight(frame)
    UpdateDispelOverlay(frame)
    UpdateDefensiveIndicator(frame)
    UpdatePortrait(frame)
end

---------------------------------------------------------------------------
-- DECORATE: Apply QUI visuals to a SecureGroupHeader child frame
---------------------------------------------------------------------------
local function DecorateGroupFrame(frame)
    if not frame or frame._quiDecorated then return end
    frame._quiDecorated = true

    -- Tag frame with party/raid context for settings resolution
    local parent = frame:GetParent()
    local isRaidParent = (parent == QUI_GF.headers.raid)
        or (parent == QUI_GF.spotlightHeader)
    if not isRaidParent then
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
            if parent == header then
                isRaidParent = true
                break
            end
        end
    end
    frame._isRaid = isRaidParent
    local isRaid = frame._isRaid

    local db = GetSettings()
    local general = GetGeneralSettings(isRaid)

    -- Backdrop
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

    EnsureBackdrop(frame, GetCachedBackdrop(
        "Interface\\Buttons\\WHITE8x8",
        borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        borderSize > 0 and borderSize or nil
    ))

    local bgColor, healthOpacity, bgOpacity
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or _state.defaultColors.darkModeBg
        healthOpacity = general.darkModeHealthOpacity or 1.0
        bgOpacity = general.darkModeBgOpacity or 1.0
    else
        bgColor = general and general.defaultBgColor or _state.defaultColors.frameBg
        healthOpacity = general and general.defaultHealthOpacity or 1.0
        bgOpacity = general and general.defaultBgOpacity or 1.0
    end
    local bgAlpha = (bgColor[4] or 1) * bgOpacity
    frame._lastBackdropColorR = bgColor[1]
    frame._lastBackdropColorG = bgColor[2]
    frame._lastBackdropColorB = bgColor[3]
    frame._lastBackdropColorA = bgAlpha
    frame._lastBackdropReapplyTime = GetTime()
    SetBackdropFillColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
    if borderSize > 0 then
        local bdr, bdg, bdb, bda = 0, 0, 0, 1
        if Helpers and Helpers.GetSkinBorderColor then bdr, bdg, bdb, bda = Helpers.GetSkinBorderColor() end
        frame:SetBackdropBorderColor(bdr, bdg, bdb, bda)
    end

    -- Power bar height calculation
    local powerSettings = GetPowerSettings(isRaid)
    local showPower = powerSettings and powerSettings.showPowerBar ~= false
    local powerHeight = showPower and (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, frame) or 4) or 0
    local separatorHeight = showPower and px or 0

    -- Health bar (reuse existing to avoid frame leaks on re-decoration)
    local healthBar = frame.healthBar or CreateFrame("StatusBar", nil, frame)
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    ApplyStatusBarTexture(healthBar)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:EnableMouse(false)
    healthBar:SetAlpha(healthOpacity)
    local isVertical = (GetHealthFillDirection(isRaid) == "VERTICAL")
    healthBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    frame._isVerticalFill = isVertical
    frame.healthBar = healthBar

    -- No separate healthBg texture — the frame backdrop shows through the
    -- unfilled StatusBar area, matching unit frame behavior.
    if frame.healthBg then
        frame.healthBg:Hide()
        frame.healthBg = nil
    end

    -- Heal prediction bar (overlays health bar, peeks out beyond health fill)
    local vdb = GetVisualDB(isRaid)
    local predSettings = vdb and vdb.healPrediction
    local healPredictionBar = frame.healPredictionBar or CreateFrame("StatusBar", nil, healthBar)
    ApplyStatusBarTexture(healPredictionBar)
    healPredictionBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredictionBar:ClearAllPoints()
    healPredictionBar:SetAllPoints(healthBar)
    healPredictionBar:SetMinMaxValues(0, 1)
    healPredictionBar:SetValue(0)
    local pc = predSettings and predSettings.color or _state.defaultColors.healPrediction
    local pa = predSettings and predSettings.opacity or 0.5
    healPredictionBar:SetStatusBarColor(pc[1] or 0.2, pc[2] or 1, pc[3] or 0.2, pa)
    healPredictionBar:Hide()
    frame.healPredictionBar = healPredictionBar

    -- Absorb bar (overlays health bar, reverse-fills from right)
    local absorbSettings = vdb and vdb.absorbs
    local absorbBar = frame.absorbBar
    if not absorbBar then
        absorbBar = CreateFrame("StatusBar", nil, healthBar)
    end
    absorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    local ac = absorbSettings and absorbSettings.color or COLORS.WHITE
    local aa = absorbSettings and absorbSettings.opacity or 0.3
    absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    absorbBar:SetFrameStrata(healthBar:GetFrameStrata())
    absorbBar:ClearAllPoints()
    absorbBar:SetAllPoints(healthBar)
    absorbBar:SetReverseFill(true)
    absorbBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:Hide()
    frame.absorbBar = absorbBar

    -- Heal absorb bar (overlays health bar — shows heal absorb debuffs like Necrotic Wound)
    local healAbsorbSettings = vdb and vdb.healAbsorbs
    local healAbsorbBar = frame.healAbsorbBar
    if not healAbsorbBar then
        healAbsorbBar = CreateFrame("StatusBar", nil, healthBar)
    end
    healAbsorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    local hac = healAbsorbSettings and healAbsorbSettings.color or _state.defaultColors.healAbsorb
    local haa = healAbsorbSettings and healAbsorbSettings.opacity or 0.6
    healAbsorbBar:SetStatusBarColor(hac[1], hac[2], hac[3], haa)
    healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    healAbsorbBar:SetFrameStrata(healthBar:GetFrameStrata())
    healAbsorbBar:ClearAllPoints()
    healAbsorbBar:SetAllPoints(healthBar)
    healAbsorbBar:SetReverseFill(true)
    healAbsorbBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:Hide()
    frame.healAbsorbBar = healAbsorbBar

    -- Power bar
    if showPower then
        local powerBar = frame.powerBar or CreateFrame("StatusBar", nil, frame)
        powerBar:ClearAllPoints()
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        ApplyStatusBarTexture(powerBar)
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        powerBar:EnableMouse(false)
        frame.powerBar = powerBar

        -- Power bar background
        if not frame._powerBg then
            local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
            powerBg:SetAllPoints()
            powerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
            powerBg:SetVertexColor(0.05, 0.05, 0.05, 0.9)
            frame._powerBg = powerBg
        end

        -- Separator
        if not frame._powerSeparator then
            local separator = powerBar:CreateTexture(nil, "OVERLAY")
            separator:SetHeight(px)
            separator:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
            separator:SetTexture("Interface\\Buttons\\WHITE8x8")
            separator:SetVertexColor(0, 0, 0, 1)
            frame._powerSeparator = separator
        end
    end

    -- Text frame (above health bar for layering)
    local textFrame = frame._textFrame or CreateFrame("Frame", nil, frame)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    frame._textFrame = textFrame

    -- Centered status text (DEAD / OFFLINE overlay)
    local statusText = frame.statusText or textFrame:CreateFontString(nil, "OVERLAY")
    statusText:ClearAllPoints()
    statusText:SetFont(GetFontPath(), 14, "OUTLINE")
    statusText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    statusText:SetJustifyH("CENTER")
    statusText:SetJustifyV("MIDDLE")
    statusText:SetTextColor(0.9, 0.9, 0.9, 1)
    statusText:Hide()
    frame.statusText = statusText

    -- Bottom-anchor offset: push elements above power bar + separator
    local bottomPad = powerHeight + separatorHeight + borderSize
    frame._bottomPad = bottomPad

    -- Name text
    local fontPath = GetFontPath()
    local fontOutline = GetFontOutline()
    local nameSettings = GetNameSettings(isRaid)
    local nameFontSize = nameSettings and nameSettings.nameFontSize or 12
    local nameAnchor = GetTextAnchorInfo(nameSettings and nameSettings.nameAnchor or "LEFT")
    local nameOffsetX = nameSettings and nameSettings.nameOffsetX or 4
    local nameOffsetY = nameSettings and nameSettings.nameOffsetY or 0
    local nameBottomPad = nameAnchor.point:find("BOTTOM") and bottomPad or 0

    local nameText = frame.nameText or textFrame:CreateFontString(nil, "OVERLAY")
    nameText:ClearAllPoints()
    nameText:SetFont(fontPath, nameFontSize, fontOutline)
    local namePadX = math.abs(nameOffsetX)
    nameText:SetPoint(nameAnchor.leftPoint, frame, nameAnchor.leftPoint, namePadX, nameOffsetY + nameBottomPad)
    nameText:SetPoint(nameAnchor.rightPoint, frame, nameAnchor.rightPoint, -namePadX, nameOffsetY + nameBottomPad)
    local nameJustify = nameSettings and nameSettings.nameJustify or nameAnchor.justify
    nameText:SetJustifyH(nameJustify)
    nameText:SetJustifyV(nameAnchor.justifyV)
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetWordWrap(false)
    frame.nameText = nameText

    -- Health text
    local healthSettings = GetHealthSettings(isRaid)
    local healthFontSize = healthSettings and healthSettings.healthFontSize or 12
    local healthAnchor = GetTextAnchorInfo(healthSettings and healthSettings.healthAnchor or "RIGHT")
    local healthOffsetX = healthSettings and healthSettings.healthOffsetX or -4
    local healthOffsetY = healthSettings and healthSettings.healthOffsetY or 0
    local healthBottomPad = healthAnchor.point:find("BOTTOM") and bottomPad or 0

    local healthText = frame.healthText or textFrame:CreateFontString(nil, "OVERLAY")
    healthText:ClearAllPoints()
    healthText:SetFont(fontPath, healthFontSize, fontOutline)
    local healthPadX = math.abs(healthOffsetX)
    healthText:SetPoint(healthAnchor.leftPoint, frame, healthAnchor.leftPoint, healthPadX, healthOffsetY + healthBottomPad)
    healthText:SetPoint(healthAnchor.rightPoint, frame, healthAnchor.rightPoint, -healthPadX, healthOffsetY + healthBottomPad)
    local healthJustify = healthSettings and healthSettings.healthJustify or healthAnchor.justify
    healthText:SetJustifyH(healthJustify)
    healthText:SetJustifyV(healthAnchor.justifyV)
    healthText:SetTextColor(1, 1, 1, 1)
    healthText:SetWordWrap(false)
    frame.healthText = healthText

    -- Read indicator positioning from DB
    local indDB = GetIndicatorSettings(isRaid) or {}

    -- Helper: add bottomPad to Y offset for any BOTTOM* anchor
    local function BottomPadY(anchor, offY)
        if anchor:find("BOTTOM") then return offY + bottomPad end
        return offY
    end

    -- Role icon
    local roleIconSize = indDB.roleIconSize or 12
    local roleAnchor = indDB.roleIconAnchor or "TOPLEFT"
    local roleOffX = indDB.roleIconOffsetX or 2
    local roleOffY = indDB.roleIconOffsetY or -2

    local roleIcon = frame.roleIcon or textFrame:CreateTexture(nil, "OVERLAY")
    roleIcon:ClearAllPoints()
    roleIcon:SetSize(roleIconSize, roleIconSize)
    roleIcon:SetPoint(roleAnchor, frame, roleAnchor, roleOffX, BottomPadY(roleAnchor, roleOffY))
    roleIcon:Hide()
    frame.roleIcon = roleIcon

    -- Ready check icon
    local readyCheckIcon = frame.readyCheckIcon or textFrame:CreateTexture(nil, "OVERLAY")
    readyCheckIcon:ClearAllPoints()
    local rcSize = indDB.readyCheckSize or 16
    readyCheckIcon:SetSize(rcSize, rcSize)
    local rcAnchor = indDB.readyCheckAnchor or "CENTER"
    readyCheckIcon:SetPoint(rcAnchor, frame, rcAnchor, indDB.readyCheckOffsetX or 0, BottomPadY(rcAnchor, indDB.readyCheckOffsetY or 0))
    readyCheckIcon:Hide()
    frame.readyCheckIcon = readyCheckIcon

    -- Resurrection icon
    local resIcon = frame.resIcon or textFrame:CreateTexture(nil, "OVERLAY")
    resIcon:ClearAllPoints()
    local resSize = indDB.resurrectionSize or 16
    resIcon:SetSize(resSize, resSize)
    local resAnchor = indDB.resurrectionAnchor or "CENTER"
    resIcon:SetPoint(resAnchor, frame, resAnchor, indDB.resurrectionOffsetX or 0, BottomPadY(resAnchor, indDB.resurrectionOffsetY or 0))
    resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    resIcon:Hide()
    frame.resIcon = resIcon

    -- Summon pending icon
    local summonIcon = frame.summonIcon or textFrame:CreateTexture(nil, "OVERLAY")
    summonIcon:ClearAllPoints()
    local sumSize = indDB.summonSize or 20
    summonIcon:SetSize(sumSize, sumSize)
    local sumAnchor = indDB.summonAnchor or "CENTER"
    summonIcon:SetPoint(sumAnchor, frame, sumAnchor, indDB.summonOffsetX or 16, BottomPadY(sumAnchor, indDB.summonOffsetY or 0))
    summonIcon:SetAtlas("RaidFrame-Icon-SummonPending")
    summonIcon:Hide()
    frame.summonIcon = summonIcon

    -- Leader icon
    local leaderIcon = frame.leaderIcon or textFrame:CreateTexture(nil, "OVERLAY")
    leaderIcon:ClearAllPoints()
    local ldrSize = indDB.leaderSize or 12
    leaderIcon:SetSize(ldrSize, ldrSize)
    local ldrAnchor = indDB.leaderAnchor or "TOP"
    leaderIcon:SetPoint(ldrAnchor, frame, ldrAnchor, indDB.leaderOffsetX or 0, BottomPadY(ldrAnchor, indDB.leaderOffsetY or 6))
    leaderIcon:Hide()
    frame.leaderIcon = leaderIcon

    -- Target marker (raid icon)
    local targetMarker = frame.targetMarker or textFrame:CreateTexture(nil, "OVERLAY")
    targetMarker:ClearAllPoints()
    local tmSize = indDB.targetMarkerSize or 14
    targetMarker:SetSize(tmSize, tmSize)
    local tmAnchor = indDB.targetMarkerAnchor or "TOPRIGHT"
    targetMarker:SetPoint(tmAnchor, frame, tmAnchor, indDB.targetMarkerOffsetX or -2, BottomPadY(tmAnchor, indDB.targetMarkerOffsetY or -2))
    targetMarker:Hide()
    frame.targetMarker = targetMarker

    -- Phase icon
    local phaseIcon = frame.phaseIcon or textFrame:CreateTexture(nil, "OVERLAY")
    phaseIcon:ClearAllPoints()
    local phSize = indDB.phaseSize or 16
    phaseIcon:SetSize(phSize, phSize)
    local phAnchor = indDB.phaseAnchor or "BOTTOMLEFT"
    phaseIcon:SetPoint(phAnchor, frame, phAnchor, indDB.phaseOffsetX or 2, BottomPadY(phAnchor, indDB.phaseOffsetY or 2))
    phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
    phaseIcon:Hide()
    frame.phaseIcon = phaseIcon

    -- Threat border (overlay frame)
    indDB = GetIndicatorSettings(isRaid) or {}
    local threatBorderPx = px * (indDB.threatBorderSize or 3)
    local threatBorder = frame.threatBorder or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    threatBorder:ClearAllPoints()
    threatBorder:SetPoint("TOPLEFT", -px, px)
    threatBorder:SetPoint("BOTTOMRIGHT", px, -px)
    threatBorder:SetFrameLevel(frame:GetFrameLevel() + 3)
    EnsureBackdrop(threatBorder, GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", threatBorderPx))
    threatBorder:Hide()
    frame.threatBorder = threatBorder

    -- Target highlight (overlay frame)
    local targetHighlight = frame.targetHighlight or CreateFrame("Frame", nil, frame, "BackdropTemplate")
    targetHighlight:ClearAllPoints()
    targetHighlight:SetPoint("TOPLEFT", -px, px)
    targetHighlight:SetPoint("BOTTOMRIGHT", px, -px)
    targetHighlight:SetFrameLevel(frame:GetFrameLevel() + 4)
    EnsureBackdrop(targetHighlight, GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", px * 2))
    targetHighlight:Hide()
    frame.targetHighlight = targetHighlight

    -- Dispel overlay (StatusBar borders for secret-value-safe SetVertexColor)
    local dispelOverlay = frame.dispelOverlay or CreateFrame("Frame", nil, frame)
    dispelOverlay:ClearAllPoints()
    dispelOverlay:SetAllPoints(frame)
    dispelOverlay:SetFrameLevel(frame:GetFrameLevel() + 6)

    local healerDB = GetHealerSettings(isRaid)
    local dispelSettings = healerDB and healerDB.dispelOverlay
    local dispelBorderSize = px * (dispelSettings and dispelSettings.borderSize or 3)
    local function MakeDispelBorder(parent)
        local sb = CreateFrame("StatusBar", nil, parent)
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(1)
        return sb
    end

    local bTop = dispelOverlay.borderTop or MakeDispelBorder(dispelOverlay)
    bTop:ClearAllPoints()
    bTop:SetPoint("TOPLEFT", dispelOverlay, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", dispelOverlay, "TOPRIGHT", 0, 0)
    bTop:SetHeight(dispelBorderSize)
    dispelOverlay.borderTop = bTop

    local bBottom = dispelOverlay.borderBottom or MakeDispelBorder(dispelOverlay)
    bBottom:ClearAllPoints()
    bBottom:SetPoint("BOTTOMLEFT", dispelOverlay, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", dispelOverlay, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(dispelBorderSize)
    dispelOverlay.borderBottom = bBottom

    local bLeft = dispelOverlay.borderLeft or MakeDispelBorder(dispelOverlay)
    bLeft:ClearAllPoints()
    bLeft:SetPoint("TOPLEFT", dispelOverlay, "TOPLEFT", 0, 0)
    bLeft:SetPoint("BOTTOMLEFT", dispelOverlay, "BOTTOMLEFT", 0, 0)
    bLeft:SetWidth(dispelBorderSize)
    dispelOverlay.borderLeft = bLeft

    local bRight = dispelOverlay.borderRight or MakeDispelBorder(dispelOverlay)
    bRight:ClearAllPoints()
    bRight:SetPoint("TOPRIGHT", dispelOverlay, "TOPRIGHT", 0, 0)
    bRight:SetPoint("BOTTOMRIGHT", dispelOverlay, "BOTTOMRIGHT", 0, 0)
    bRight:SetWidth(dispelBorderSize)
    dispelOverlay.borderRight = bRight

    -- Fill texture (full-frame tint behind borders)
    local dispelFill = dispelOverlay.fill
    if not dispelFill then
        dispelFill = dispelOverlay:CreateTexture(nil, "BACKGROUND")
        dispelOverlay.fill = dispelFill
    end
    dispelFill:SetAllPoints(dispelOverlay)
    dispelFill:SetColorTexture(1, 1, 1, 1)
    dispelFill:SetVertexColor(0, 0, 0, 0) -- colored dynamically by SetDispelBorderColor
    dispelOverlay._fillOpacity = dispelSettings and dispelSettings.fillOpacity or 0

    dispelOverlay:Hide()
    frame.dispelOverlay = dispelOverlay

    -- Defensive indicator icons are allocated lazily by UpdateDefensiveIndicator
    -- so profiles with the feature disabled do not pay for 5 cooldown frames
    -- on every group member.
    _state.HideDefensiveIcons(frame)

    -- Portrait (optional, side-attached)
    local portraitSettings = GetPortraitSettings(isRaid)
    if portraitSettings and portraitSettings.showPortrait then
        local portraitSizePx = portraitSettings.portraitSize or 30
        local portraitSizeRound = QUICore.PixelRound and QUICore:PixelRound(portraitSizePx, frame) or portraitSizePx
        local portraitBorderPx = QUICore.Pixels and QUICore:Pixels(1, frame) or px

        local portrait = frame.portrait or CreateFrame("Frame", nil, frame, "BackdropTemplate")
        portrait:SetSize(portraitSizeRound, portraitSizeRound)
        portrait:ClearAllPoints()

        local side = portraitSettings.portraitSide or "LEFT"
        if side == "LEFT" then
            portrait:SetPoint("RIGHT", frame, "LEFT", 0, 0)
        else
            portrait:SetPoint("LEFT", frame, "RIGHT", 0, 0)
        end

        EnsureBackdrop(portrait, GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", portraitBorderPx))
        local pbdr, pbdg, pbdb, pbda = 0, 0, 0, 1
        if Helpers and Helpers.GetSkinBorderColor then pbdr, pbdg, pbdb, pbda = Helpers.GetSkinBorderColor() end
        portrait:SetBackdropBorderColor(pbdr, pbdg, pbdb, pbda)
        portrait:SetFrameLevel(frame:GetFrameLevel() + 1)

        local portraitTex = frame.portraitTexture or portrait:CreateTexture(nil, "ARTWORK")
        portraitTex:ClearAllPoints()
        portraitTex:SetPoint("TOPLEFT", portraitBorderPx, -portraitBorderPx)
        portraitTex:SetPoint("BOTTOMRIGHT", -portraitBorderPx, portraitBorderPx)
        frame.portraitTexture = portraitTex
        frame.portrait = portrait
        portrait:Show()
    elseif frame.portrait then
        frame.portrait:Hide()
    end

    -- One-time hooks (only on first decoration)
    if not frame._quiHooked then
        frame._quiHooked = true

        frame:HookScript("OnEnter", function(self)
            ShowUnitTooltip(self)
        end)
        frame:HookScript("OnLeave", HideUnitTooltip)

        -- Sync unit attribute → frame.unit whenever the secure header changes it.
        -- GUID-based skip: avoids expensive UpdateFrame when the same player is
        -- reassigned to a different slot (common during roster shuffles).
        --   Level 0: Both old and new nil → skip (empty slot noise)
        --   Level 1: Same unit + same GUID → skip (no real change)
        --   Level 2: Different unit, same GUID → light update (remap only)
        --   Level 3: Genuinely different player → full UpdateFrame
        frame:HookScript("OnAttributeChanged", function(self, key, value)
            if key ~= "unit" then return end
            local oldUnit = self.unit
            -- Level 0: both nil — nothing to do
            if not oldUnit and not value then return end

            self.unit = value

            -- Clean up old mapping (idempotently removes self from the list)
            if oldUnit then
                RemoveFrameFromMap(oldUnit, self)
            end

            if not value then
                -- Unit cleared (frame hidden by header)
                _state.unitGuidCache[self] = nil
                if self.summonIcon then self.summonIcon:Hide() end
                return
            end

            -- Register new mapping immediately (so events dispatch correctly)
            AddFrameToMap(value, self)

            -- GUID comparison: detect whether the actual player changed.
            -- UnitGUID returns secret strings during combat — coerce to nil
            -- so we never store or compare secret values.
            local rawGuid = UnitGUID(value)
            local newGuid = (rawGuid and not IsSecretValue(rawGuid)) and rawGuid or nil
            local oldGuid = _state.unitGuidCache[self]
            if newGuid then
                _state.unitGuidCache[self] = newGuid
            end

            if oldGuid and newGuid and oldGuid == newGuid then
                if oldUnit == value then
                    -- Level 1: same unit, same player — nothing changed
                    return
                end
                -- Level 2: slot moved (e.g., raid3 → raid5), same player.
                -- Map is already updated; skip full refresh.
                return
            end

            -- Level 3: genuinely different player (or first assignment)
            UpdateFrame(self)
        end)
    end

    -- Pick up the current unit if already assigned by the secure header
    local currentUnit = frame:GetAttribute("unit")
    if currentUnit then
        frame.unit = currentUnit
        AddFrameToMap(currentUnit, frame)
    end

    -- Register with Clique / click-cast
    if ClickCastFrames then
        ClickCastFrames[frame] = true
    end

    -- Register with QUI click-cast system
    local GFCC = ns.QUI_GroupFrameClickCast
    if GFCC and GFCC:IsEnabled() then
        GFCC:RegisterFrame(frame)
    end

    -- Store in flat list
    table.insert(QUI_GF.allFrames, frame)
end

-- Expose for spotlight (and any future external headers)
QUI_GF.DecorateGroupFrame = DecorateGroupFrame

-- Called from QUIGroupUnitButtonTemplate OnLoad the moment the secure header
-- creates each child. Runs inside the ADDON_LOADED safe window where the
-- script execution-time budget is effectively unlimited.
function QUI_GF:InitializeHeaderChild(frame)
    if not frame then return end
    DecorateGroupFrame(frame)
    if not InCombatLockdown() then
        frame:RegisterForClicks("AnyUp")
    else
        _pending.registerClicks = true
    end
end

---------------------------------------------------------------------------
-- UNIT FRAME MAP: Rebuild unit → list-of-frames lookup

local function EnsureAnchorFrame(key)
    local root = QUI_GF.anchorFrames[key]
    if root then return root end

    local name = key == "raid" and "QUI_RaidFramesRoot" or "QUI_PartyFramesRoot"
    -- On /reload, WoW does not destroy frames — the old root from the previous
    -- session survives with its children (headers + unit buttons) still visible.
    -- Hide it before creating the replacement to prevent duplicate frames.
    local old = _G[name]
    if old then old:Hide() end

    root = CreateFrame("Frame", name, UIParent)
    root:EnableMouse(false)
    root:Hide()

    QUI_GF.anchorFrames[key] = root
    return root
end

local function GetAnchorPosition(key, db)
    if key == "raid" and db and db.unifiedPosition == false then
        local pos = db.raidPosition
        return pos and pos.offsetX or -400, pos and pos.offsetY or 0
    end

    local pos = db and db.position
    return pos and pos.offsetX or -400, pos and pos.offsetY or 0
end

-- Compute a fallback size for an anchor root when no headers are visible
-- (solo for party, or no raid members for raid).  Frames anchored to this
-- root via keepInPlace need a valid GetLeft/GetWidth to compute coordinates
-- against, otherwise they render at nil coordinates.  The fallback matches
-- what Layout Mode's test mode would display for a full party/raid so the
-- size is consistent between the two modes.
local function GetAnchorFallbackSize(key, db)
    local isRaid = key == "raid"
    local vdb = isRaid and (db and (db.raid or db)) or (db and (db.party or db))
    local layout = (vdb and vdb.layout)
        or (db and ((isRaid and db.raidLayout) or db.partyLayout))
        or (db and db.layout)

    local count
    if isRaid then
        count = (db and db.testMode and db.testMode.raidCount) or 25
    else
        count = 5
    end

    local framesPerGroup = 5
    local numGroups = math_ceil(count / framesPerGroup)
    local spacing = (layout and layout.spacing) or 2
    local groupSpacing = (layout and layout.groupSpacing) or 10
    local grow = (layout and layout.growDirection) or "DOWN"
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    -- Frame dimensions — mirror the logic in groupframes_editmode.lua
    -- EnableTestMode for consistency with the live layout-mode preview.
    local dims = vdb and vdb.dimensions
    local mode
    if count <= 5 then mode = "party"
    elseif count <= 15 then mode = "small"
    elseif count <= 25 then mode = "medium"
    else mode = "large"
    end

    local frameW, frameH
    if mode == "party" then
        frameW, frameH = (dims and dims.partyWidth) or 200, (dims and dims.partyHeight) or 40
    elseif mode == "small" then
        frameW, frameH = (dims and dims.smallRaidWidth) or 180, (dims and dims.smallRaidHeight) or 36
    elseif mode == "medium" then
        frameW, frameH = (dims and dims.mediumRaidWidth) or 160, (dims and dims.mediumRaidHeight) or 30
    else
        frameW, frameH = (dims and dims.largeRaidWidth) or 140, (dims and dims.largeRaidHeight) or 24
    end

    local totalW, totalH
    if horizontal then
        totalW = framesPerGroup * frameW + (framesPerGroup - 1) * spacing
        totalH = numGroups * frameH + (numGroups - 1) * groupSpacing
    else
        totalW = numGroups * frameW + (numGroups - 1) * groupSpacing
        totalH = framesPerGroup * frameH + (framesPerGroup - 1) * spacing
    end

    return math_max(totalW, 1), math_max(totalH, 1)
end

local function GetHeaderLeadEdge(isRaid)
    local layout = GetLayoutSettings(isRaid)
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local groupBy = isRaid and (layout and layout.groupBy or "GROUP") or "GROUP"
    local leadEdge = "LEFT"

    if grow == "LEFT" then
        leadEdge = "RIGHT"
    elseif isRaid and (grow == "DOWN" or grow == "UP") and groupBy ~= "NONE" and
        (layout and layout.groupGrowDirection) == "LEFT" then
        leadEdge = "RIGHT"
    end

    return grow, leadEdge
end

local function AnchorHeaderToRoot(root, header, grow, leadEdge, attachTo, gap, isSelfHeader)
    if not (root and header) then return end

    header:SetParent(root)
    header:ClearAllPoints()

    if attachTo then
        if grow == "UP" then
            header:SetPoint("BOTTOM" .. leadEdge, attachTo, "TOP" .. leadEdge, 0, gap or 0)
        elseif grow == "LEFT" then
            if isSelfHeader then
                header:SetPoint("TOPRIGHT", attachTo, "TOPLEFT", -(gap or 0), 0)
            else
                header:SetPoint("TOPRIGHT", attachTo, "TOPLEFT", -(gap or 0), 0)
            end
        elseif grow == "RIGHT" then
            if isSelfHeader then
                header:SetPoint("TOPLEFT", attachTo, "TOPRIGHT", gap or 0, 0)
            else
                header:SetPoint("TOPLEFT", attachTo, "TOPRIGHT", gap or 0, 0)
            end
        else
            header:SetPoint("TOP" .. leadEdge, attachTo, "BOTTOM" .. leadEdge, 0, -(gap or 0))
        end
        return
    end

    if grow == "UP" then
        header:SetPoint("BOTTOM" .. leadEdge, root, "BOTTOM" .. leadEdge, 0, 0)
    elseif grow == "LEFT" then
        header:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    elseif grow == "RIGHT" then
        header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    else
        header:SetPoint("TOP" .. leadEdge, root, "TOP" .. leadEdge, 0, 0)
    end
end

local function UpdateAnchorRoot(key, mainHeader, selfHeader, isRaid)
    local root = EnsureAnchorFrame(key)
    local grow, leadEdge = GetHeaderLeadEdge(isRaid)
    local db = GetSettings()
    local vdb = db and (isRaid and (db.raid or db) or (db.party or db))
    local layout = vdb and vdb.layout or (db and ((isRaid and db.raidLayout) or db.partyLayout)) or (db and db.layout)
    local gap = layout and layout.spacing or 2

    local mainVisible = mainHeader and mainHeader:IsShown()
    local selfVisible = selfHeader and selfHeader:IsShown()

    if not mainVisible and not selfVisible then
        -- No headers to display, but we still give the root a valid
        -- SetPoint and SetSize so frames anchored to it via keepInPlace
        -- (in the anchoring system) can compute coordinates.  Without
        -- this, GetLeft/GetBottom/GetWidth all return nil on the hidden
        -- root and any child anchored through it renders at nil
        -- coordinates (invisible).  The size matches what Layout Mode's
        -- test mode would display for a full party/raid so there's no
        -- visual jump between layout mode and gameplay.
        local fallbackW, fallbackH = GetAnchorFallbackSize(key, db)
        local posX, posY = GetAnchorPosition(key, db)
        root:ClearAllPoints()
        root:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
        root:SetSize(fallbackW, fallbackH)
        root:Hide()
        return
    end

    local mainW = mainVisible and Helpers.SafeValue(mainHeader:GetWidth(), 1) or 0
    local mainH = mainVisible and Helpers.SafeValue(mainHeader:GetHeight(), 1) or 0
    local selfW = selfVisible and Helpers.SafeValue(selfHeader:GetWidth(), 1) or 0
    local selfH = selfVisible and Helpers.SafeValue(selfHeader:GetHeight(), 1) or 0

    local totalW, totalH
    if grow == "LEFT" or grow == "RIGHT" then
        totalW = math_max(1, mainW + (mainVisible and selfVisible and gap or 0) + selfW)
        totalH = math_max(1, math_max(mainH, selfH))
    else
        totalW = math_max(1, math_max(mainW, selfW))
        totalH = math_max(1, mainH + (mainVisible and selfVisible and gap or 0) + selfH)
    end

    root:SetSize(totalW, totalH)

    if selfVisible then
        AnchorHeaderToRoot(root, selfHeader, grow, leadEdge, nil, 0, true)
    end

    if mainVisible then
        AnchorHeaderToRoot(root, mainHeader, grow, leadEdge, selfVisible and selfHeader or nil, selfVisible and gap or 0, false)
    end

    root:Show()
end

-- Compute total dimensions of all visible group headers for the anchor root
local function GetMultiHeaderTotalSize()
    local layout = GetLayoutSettings(true)
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local groupGrow = layout and layout.groupGrowDirection
    local groupSpacing = layout and layout.groupSpacing or 10
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    if not groupGrow then
        groupGrow = horizontal and "DOWN" or "RIGHT"
    end

    local totalW, totalH = 0, 0
    local visibleCount = 0

    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header and header:IsShown() then
            local hW = Helpers.SafeValue(header:GetWidth(), 1)
            local hH = Helpers.SafeValue(header:GetHeight(), 1)
            visibleCount = visibleCount + 1

            if horizontal then
                -- Groups stack vertically; width = max, height = sum
                totalW = math_max(totalW, hW)
                totalH = totalH + hH
            else
                -- Groups stack horizontally; width = sum, height = max
                totalW = totalW + hW
                totalH = math_max(totalH, hH)
            end
        end
    end

    -- Add group spacing between visible groups
    if visibleCount > 1 then
        if horizontal then
            totalH = totalH + (visibleCount - 1) * groupSpacing
        else
            totalW = totalW + (visibleCount - 1) * groupSpacing
        end
    end

    return math_max(totalW, 1), math_max(totalH, 1)
end

local function UpdateAnchorFrames()
    if not _pending.initSafe and InCombatLockdown() then
        _pending.anchorUpdate = true
        return
    end
    local db = GetSettings()
    if not db then return end

    local partyRoot = EnsureAnchorFrame("party")
    local raidRoot = EnsureAnchorFrame("raid")
    local partyX, partyY = GetAnchorPosition("party", db)
    local raidX, raidY = GetAnchorPosition("raid", db)

    -- Resize roots FIRST so that size-stable CENTER anchoring in
    -- ApplyFrameAnchor uses the correct dimensions. Previously the
    -- external position was computed before the resize, causing a
    -- CENTER offset mismatch that ApplyAllFrameAnchors would later
    -- "correct" — producing visible jumps during combat.
    local selfHdr = QUI_GF.headers.self
    local selfOnParty = selfHdr and selfHdr:IsShown() and not IsInRaid()

    UpdateAnchorRoot("party", QUI_GF.headers.party, selfOnParty and selfHdr or nil, false)

    if UseRaidSectionHeaders(db) and IsInRaid() then
        local root = raidRoot

        local mW, mH = GetMultiHeaderTotalSize()
        local anyVisible = mW > 1 or mH > 1

        if not anyVisible then
            root:ClearAllPoints()
            root:Hide()
            -- Still position both roots even when raid sections are invisible
            local applyAnchor = _G.QUI_ApplyFrameAnchor
            local hasAnchor = _G.QUI_HasFrameAnchor
            if hasAnchor and hasAnchor("partyFrames") and applyAnchor then
                applyAnchor("partyFrames")
            elseif partyRoot:GetNumPoints() == 0 then
                partyRoot:SetPoint("CENTER", UIParent, "CENTER", partyX, partyY)
            end
            if hasAnchor and hasAnchor("raidFrames") and applyAnchor then
                applyAnchor("raidFrames")
            elseif raidRoot:GetNumPoints() == 0 then
                raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidX, raidY)
            end
            return
        end

        root:SetSize(math_max(1, mW), math_max(1, mH))
        root:Show()
    else
        UpdateAnchorRoot("raid", QUI_GF.headers.raid, nil, true)
    end

    -- Position roots AFTER resize: delegate to the anchoring system when it
    -- owns the frame (preserves size-stable CENTER anchoring), otherwise
    -- fall back to legacy.
    local applyAnchor = _G.QUI_ApplyFrameAnchor
    local hasAnchor = _G.QUI_HasFrameAnchor
    if hasAnchor and hasAnchor("partyFrames") and applyAnchor then
        applyAnchor("partyFrames")
    elseif partyRoot:GetNumPoints() == 0 then
        partyRoot:SetPoint("CENTER", UIParent, "CENTER", partyX, partyY)
    end
    if hasAnchor and hasAnchor("raidFrames") and applyAnchor then
        applyAnchor("raidFrames")
    elseif raidRoot:GetNumPoints() == 0 then
        raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidX, raidY)
    end
end

---------------------------------------------------------------------------
-- HEADER: Configure secure header attributes
---------------------------------------------------------------------------
local function GetVisiblePartyUnitCount()
    local layout = GetLayoutSettings(false)
    if not layout then return 0 end

    local db = GetSettings()
    local selfFirst = GetPartySelfFirst(db)

    if IsInRaid() then
        return 0
    end

    if IsInGroup() then
        local subgroupCount
        if type(GetNumSubgroupMembers) == "function" then
            subgroupCount = GetNumSubgroupMembers() or 0
        else
            subgroupCount = math_max((GetNumGroupMembers() or 0) - 1, 0)
        end

        if selfFirst or layout.showPlayer == false then
            return subgroupCount
        end

        return subgroupCount + 1
    end

    if selfFirst or not layout.showSolo then
        return 0
    end

    return 1
end

local function ConfigurePartyHeader(header)
    local layout = GetLayoutSettings(false)
    if not layout then return end

    local db = GetSettings()
    local selfFirst = GetPartySelfFirst(db)
    local inParty = IsInGroup() and not IsInRaid()
    local showSolo = (not inParty) and layout.showSolo and not selfFirst

    header:SetAttribute("showParty", true)
    header:SetAttribute("showPlayer", (not selfFirst and ((inParty and layout.showPlayer ~= false) or showSolo)) and true or false)
    header:SetAttribute("showRaid", false)
    header:SetAttribute("showSolo", showSolo or false)
    header:SetAttribute("maxColumns", 1)
    header:SetAttribute("unitsPerColumn", 5)

    local mode = "party"
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2

    -- Grow direction
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    if grow == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("yOffset", -spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("yOffset", spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
        header:SetAttribute("yOffset", 0)
    elseif grow == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
        header:SetAttribute("yOffset", 0)
    end

    -- Sorting
    if layout.sortByRole then
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    else
        local sortMethod = layout.sortMethod or "INDEX"
        header:SetAttribute("sortMethod", sortMethod)
    end

    -- Frame size via initial config
    header:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
    header:SetAttribute("_initialAttribute-unit-width", w)
    header:SetAttribute("_initialAttribute-unit-height", h)
end

local function ConfigureRaidHeader(header)
    local layout = GetLayoutSettings(true)
    if not layout then return end

    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", false)
    header:SetAttribute("showPlayer", false)
    header:SetAttribute("showSolo", false)

    local mode = GetGroupMode()
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2
    local groupSpacing = layout.groupSpacing or 10

    -- Grow direction (within each group column)
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    if grow == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("yOffset", -spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("yOffset", spacing)
        header:SetAttribute("xOffset", 0)
    elseif grow == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
        header:SetAttribute("yOffset", 0)
    elseif grow == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
        header:SetAttribute("yOffset", 0)
    end

    -- Columns for groups
    -- When frames within a group are horizontal, groups stack vertically (and vice versa)
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    local groupBy = layout.groupBy or "GROUP"
    local isFlat = (groupBy == "NONE")
    local groupLimit = _state.GetRaidGroupLimit(layout)
    local groupFilter = _state.GetRaidGroupFilterString(layout)

    if isFlat then
        local upc = layout.unitsPerFlat or 5
        header:SetAttribute("unitsPerColumn", upc)
        header:SetAttribute("maxColumns", math.ceil((groupLimit * 5) / upc))
        header:SetAttribute("columnSpacing", spacing)
    else
        header:SetAttribute("maxColumns", groupLimit)
        header:SetAttribute("unitsPerColumn", 5)
        header:SetAttribute("columnSpacing", groupSpacing)
    end

    if horizontal then
        -- Groups stack vertically when intra-group is horizontal
        header:SetAttribute("columnAnchorPoint", "TOP")
    else
        local groupGrow = layout.groupGrowDirection or "RIGHT"
        if groupGrow == "RIGHT" then
            header:SetAttribute("columnAnchorPoint", "LEFT")
        else
            header:SetAttribute("columnAnchorPoint", "RIGHT")
        end
    end

    -- Group filtering
    if groupBy == "NONE" then
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupFilter", groupLimit < 8 and groupFilter or nil)
        header:SetAttribute("groupingOrder", nil)
    elseif groupBy == "GROUP" then
        header:SetAttribute("groupBy", "GROUP")
        header:SetAttribute("groupFilter", groupFilter)
        header:SetAttribute("groupingOrder", groupFilter)
    elseif groupBy == "ROLE" then
        header:SetAttribute("groupBy", "ASSIGNEDROLE")
        header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    elseif groupBy == "CLASS" then
        header:SetAttribute("groupBy", "CLASS")
        header:SetAttribute("groupingOrder", "WARRIOR,DEATHKNIGHT,PALADIN,MONK,PRIEST,SHAMAN,DRUID,ROGUE,MAGE,WARLOCK,HUNTER,DEMONHUNTER,EVOKER")
    end

    -- Sorting
    if layout.sortByRole and groupBy ~= "ROLE" then
        -- Role sort within groups
        header:SetAttribute("sortMethod", "NAME")
    else
        header:SetAttribute("sortMethod", layout.sortMethod or "INDEX")
    end

    -- Frame size via initial config
    header:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
    header:SetAttribute("_initialAttribute-unit-width", w)
    header:SetAttribute("_initialAttribute-unit-height", h)
end

_state.SetHeaderAttributeIfChanged = function(header, name, value)
    if header:GetAttribute(name) ~= value then
        header:SetAttribute(name, value)
    end
end

---------------------------------------------------------------------------
-- MULTI-HEADER: Configure per-group raid headers
---------------------------------------------------------------------------
local function ConfigureRaidGroupHeaders()
    local layout = GetLayoutSettings(true)
    if not layout then return end

    local mode = GetGroupMode()
    local w, h = GetFrameDimensions(mode)
    local spacing = layout.spacing or 2

    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local point, xOff, yOff
    if grow == "DOWN" then
        point, xOff, yOff = "TOP", 0, -spacing
    elseif grow == "UP" then
        point, xOff, yOff = "BOTTOM", 0, spacing
    elseif grow == "RIGHT" then
        point, xOff, yOff = "LEFT", spacing, 0
    elseif grow == "LEFT" then
        point, xOff, yOff = "RIGHT", -spacing, 0
    end
    local columnAnchorPoint = GetRaidColumnAnchorPoint(layout, grow)

    local sortMethod = layout.sortMethod or "INDEX"
    local sortByRole = layout.sortByRole
    local db = GetSettings()
    local useNameListSections = _state.UseRaidNameListSections(db, layout)
    local sections = useNameListSections and GetRaidDisplaySections() or nil
    local groupLimit = _state.GetRaidGroupLimit(layout)

    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        local section = sections and sections[g] or nil
        if header then
            header:SetAttribute("point", point)
            header:SetAttribute("xOffset", xOff)
            header:SetAttribute("yOffset", yOff)
            header:SetAttribute("showRaid", true)
            header:SetAttribute("showParty", false)
            header:SetAttribute("showPlayer", false)
            header:SetAttribute("showSolo", false)
            header:SetAttribute("columnSpacing", spacing)
            header:SetAttribute("columnAnchorPoint", columnAnchorPoint)
            _state.SetHeaderAttributeIfChanged(header, "sortDir", "ASC")

            if section then
                local unitsPerColumn = math_max(1, math_min(section.memberCount, GetRaidSectionUnitsPerColumn(layout)))
                header:SetAttribute("maxColumns", math_max(1, math.ceil(section.memberCount / unitsPerColumn)))
                header:SetAttribute("unitsPerColumn", unitsPerColumn)
                -- Switching INTO nameList mode: set nameList/sortMethod BEFORE
                -- clearing groupBy/groupFilter/groupingOrder. The reverse order
                -- leaves the secure header in an invalid intermediate state
                -- where Blizzard's private-aura anchor hook calls Hide on a
                -- stale child frame, throwing "calling 'Hide' on bad self".
                _state.SetHeaderAttributeIfChanged(header, "nameList", section.nameList)
                _state.SetHeaderAttributeIfChanged(header, "sortMethod", "NAMELIST")
                _state.SetHeaderAttributeIfChanged(header, "sortDir", "ASC")
                _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupFilter", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
            elseif useNameListSections then
                header:SetAttribute("maxColumns", 1)
                header:SetAttribute("unitsPerColumn", 1)
                _state.SetHeaderAttributeIfChanged(header, "groupBy", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupFilter", nil)
                _state.SetHeaderAttributeIfChanged(header, "groupingOrder", nil)
                _state.SetHeaderAttributeIfChanged(header, "nameList", nil)
                _state.SetHeaderAttributeIfChanged(header, "sortMethod", "INDEX")
            else
                header:SetAttribute("maxColumns", 1)
                header:SetAttribute("unitsPerColumn", 5)
                if g <= groupLimit then
                    header:SetAttribute("groupBy", "GROUP")
                    header:SetAttribute("groupFilter", tostring(g))
                    header:SetAttribute("groupingOrder", tostring(g))
                    header:SetAttribute("nameList", nil)

                    if sortByRole then
                        header:SetAttribute("sortMethod", "NAME")
                    else
                        header:SetAttribute("sortMethod", sortMethod)
                    end
                else
                    header:SetAttribute("groupBy", nil)
                    header:SetAttribute("groupFilter", nil)
                    header:SetAttribute("groupingOrder", nil)
                    header:SetAttribute("nameList", nil)
                    header:SetAttribute("sortMethod", "INDEX")
                end
            end

            header:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
            header:SetAttribute("_initialAttribute-unit-width", w)
            header:SetAttribute("_initialAttribute-unit-height", h)
        end
    end

    return sections
end

---------------------------------------------------------------------------
-- MULTI-HEADER: Position per-group headers with group spacing
---------------------------------------------------------------------------
local function PositionRaidGroupHeaders()
    if InCombatLockdown() then
        _pending.groupReflow = true
        return
    end

    local layout = GetLayoutSettings(true)
    if not layout then return end

    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local groupGrow = layout.groupGrowDirection
    local groupSpacing = layout.groupSpacing or 10
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    -- Determine default group grow direction based on primary axis
    if not groupGrow then
        groupGrow = horizontal and "DOWN" or "RIGHT"
    end

    local raidRoot = QUI_GF.anchorFrames.raid
    local prevHeader = nil

    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header and header:IsShown() then
            header:ClearAllPoints()

            if not prevHeader then
                -- First visible header: anchor to root
                if horizontal then
                    if groupGrow == "UP" then
                        if grow == "RIGHT" then
                            header:SetPoint("BOTTOMLEFT", raidRoot, "BOTTOMLEFT", 0, 0)
                        else
                            header:SetPoint("BOTTOMRIGHT", raidRoot, "BOTTOMRIGHT", 0, 0)
                        end
                    else -- DOWN
                        if grow == "RIGHT" then
                            header:SetPoint("TOPLEFT", raidRoot, "TOPLEFT", 0, 0)
                        else
                            header:SetPoint("TOPRIGHT", raidRoot, "TOPRIGHT", 0, 0)
                        end
                    end
                else
                    if groupGrow == "LEFT" then
                        if grow == "DOWN" then
                            header:SetPoint("TOPRIGHT", raidRoot, "TOPRIGHT", 0, 0)
                        else
                            header:SetPoint("BOTTOMRIGHT", raidRoot, "BOTTOMRIGHT", 0, 0)
                        end
                    else -- RIGHT
                        if grow == "DOWN" then
                            header:SetPoint("TOPLEFT", raidRoot, "TOPLEFT", 0, 0)
                        else
                            header:SetPoint("BOTTOMLEFT", raidRoot, "BOTTOMLEFT", 0, 0)
                        end
                    end
                end
            else
                -- Subsequent headers: anchor relative to previous
                if horizontal then
                    if groupGrow == "UP" then
                        if grow == "RIGHT" then
                            header:SetPoint("BOTTOMLEFT", prevHeader, "TOPLEFT", 0, groupSpacing)
                        else
                            header:SetPoint("BOTTOMRIGHT", prevHeader, "TOPRIGHT", 0, groupSpacing)
                        end
                    else -- DOWN
                        if grow == "RIGHT" then
                            header:SetPoint("TOPLEFT", prevHeader, "BOTTOMLEFT", 0, -groupSpacing)
                        else
                            header:SetPoint("TOPRIGHT", prevHeader, "BOTTOMRIGHT", 0, -groupSpacing)
                        end
                    end
                else
                    if groupGrow == "LEFT" then
                        if grow == "DOWN" then
                            header:SetPoint("TOPRIGHT", prevHeader, "TOPLEFT", -groupSpacing, 0)
                        else
                            header:SetPoint("BOTTOMRIGHT", prevHeader, "BOTTOMLEFT", -groupSpacing, 0)
                        end
                    else -- RIGHT
                        if grow == "DOWN" then
                            header:SetPoint("TOPLEFT", prevHeader, "TOPRIGHT", groupSpacing, 0)
                        else
                            header:SetPoint("BOTTOMLEFT", prevHeader, "BOTTOMRIGHT", groupSpacing, 0)
                        end
                    end
                end
            end

            prevHeader = header
        end
    end
end

---------------------------------------------------------------------------
-- HEADER: Create secure group headers
---------------------------------------------------------------------------
local function CreateHeaders()
    local db = GetSettings()
    if not db then return end
    local position = db.position
    local partyRoot = EnsureAnchorFrame("party")
    local raidRoot = EnsureAnchorFrame("raid")

    -- initialConfigFunction runs in secure context for each new child
    local initConfigFunc = [[
        local header = self:GetParent()
        local w = header:GetAttribute("_initialAttribute-unit-width") or 200
        local h = header:GetAttribute("_initialAttribute-unit-height") or 40
        self:SetWidth(w)
        self:SetHeight(h)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
        RegisterUnitWatch(self)
    ]]

    -- Party header
    local partyHeader = CreateFrame("Frame", "QUI_PartyHeader", partyRoot, "SecureGroupHeaderTemplate")
    partyHeader:SetAttribute("template", "QUIGroupUnitButtonTemplate")
    partyHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    -- Publish header reference BEFORE invisible-show so QUIGroupUnitButtonTemplate's
    -- OnLoad-triggered DecorateGroupFrame sees correct raid-vs-party context when
    -- checking frame:GetParent() against QUI_GF.headers.*.
    QUI_GF.headers.party = partyHeader
    ConfigurePartyHeader(partyHeader)

    -- Position: prefer frameAnchoring if available, fall back to legacy db.position
    local partyW, partyH = CalculateHeaderSize(db, 5)
    partyHeader:SetSize(partyW, partyH)
    partyRoot:ClearAllPoints()
    local faDB = QUI.db and QUI.db.profile and QUI.db.profile.frameAnchoring
    local faParty = faDB and faDB.partyFrames
    if faParty and faParty.point then
        partyRoot:SetPoint(faParty.point, UIParent, faParty.relative or faParty.point, faParty.offsetX or 0, faParty.offsetY or 0)
    else
        local offsetX = position and position.offsetX or -400
        local offsetY = position and position.offsetY or 0
        partyRoot:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end
    partyHeader:SetMovable(true)
    partyHeader:SetClampedToScreen(true)

    -- Pre-create all 5 party frames upfront so no frames are created mid-combat.
    -- Two requirements for SecureGroupHeaderTemplate to create children:
    --   1. Parent root must be shown (hidden parent prevents child creation)
    --   2. At least 1 managed unit must exist (showPlayer + showSolo forces the player)
    partyRoot:Show()
    partyHeader:SetAttribute("showPlayer", true)
    partyHeader:SetAttribute("showSolo", true)
    partyHeader:SetAttribute("startingIndex", -4)
    partyHeader:Show()
    partyHeader:SetAttribute("startingIndex", 1)
    partyHeader:Hide()
    partyRoot:Hide()
    -- Restore correct show* attributes for runtime operation
    ConfigurePartyHeader(partyHeader)

    -- Raid header
    local raidHeader = CreateFrame("Frame", "QUI_RaidHeader", raidRoot, "SecureGroupHeaderTemplate")
    raidHeader:SetAttribute("template", "QUIGroupUnitButtonTemplate")
    raidHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    -- Publish before invisible-show so OnLoad-triggered DecorateGroupFrame
    -- correctly identifies raid children via parent comparison.
    QUI_GF.headers.raid = raidHeader
    ConfigureRaidHeader(raidHeader)

    local raidCount = math_max(IsInRaid() and GetNumGroupMembers() or 25, 5)
    local raidW, raidH = CalculateHeaderSize(db, raidCount)
    raidHeader:SetSize(raidW, raidH)

    -- Raid position: position raidRoot from frameAnchoring (matching partyRoot).
    -- UpdateAnchorRoot will position the header within raidRoot.
    raidRoot:ClearAllPoints()
    local faRaid = faDB and faDB.raidFrames
    if faRaid and faRaid.point then
        raidRoot:SetPoint(faRaid.point, UIParent, faRaid.relative or faRaid.point, faRaid.offsetX or 0, faRaid.offsetY or 0)
    else
        local raidPos = db.raidPosition
        local raidOffX = raidPos and raidPos.offsetX or -400
        local raidOffY = raidPos and raidPos.offsetY or 0
        raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidOffX, raidOffY)
    end
    raidHeader:SetMovable(true)
    raidHeader:SetClampedToScreen(true)

    -- Pre-create all 40 raid frames upfront so no frames are created mid-combat.
    -- Force showPlayer + showSolo so the header has at least 1 managed unit.
    raidRoot:Show()
    raidHeader:SetAttribute("showPlayer", true)
    raidHeader:SetAttribute("showSolo", true)
    raidHeader:SetAttribute("startingIndex", -39)
    raidHeader:Show()
    raidHeader:SetAttribute("startingIndex", 1)
    raidHeader:Hide()
    raidRoot:Hide()
    ConfigureRaidHeader(raidHeader)

    -- Raid section headers. Reused for grouped raids and for raid self-first mode.
    raidRoot:Show()  -- Parent must be visible for child creation
    for g = 1, MAX_RAID_SECTION_HEADERS do
        local groupHeader = CreateFrame("Frame", "QUI_RaidGroup" .. g .. "Header", raidRoot, "SecureGroupHeaderTemplate")
        groupHeader:SetAttribute("template", "QUIGroupUnitButtonTemplate")
        groupHeader:SetAttribute("initialConfigFunction", initConfigFunc)
        -- Publish before invisible-show so OnLoad-triggered DecorateGroupFrame's
        -- raid-section parent check sees this header in QUI_GF.raidGroupHeaders.
        groupHeader._raidGroupIndex = g
        QUI_GF.raidGroupHeaders[g] = groupHeader
        groupHeader:SetAttribute("showRaid", true)
        groupHeader:SetAttribute("showParty", false)
        groupHeader:SetAttribute("showPlayer", false)
        groupHeader:SetAttribute("showSolo", false)
        groupHeader:SetAttribute("groupBy", "GROUP")
        groupHeader:SetAttribute("groupFilter", tostring(g))
        groupHeader:SetAttribute("groupingOrder", tostring(g))
        groupHeader:SetAttribute("maxColumns", 8)
        groupHeader:SetAttribute("unitsPerColumn", 5)
        groupHeader:SetAttribute("_initialAttributeNames", "unit-width,unit-height")

        local rW, rH = GetFrameDimensions("small")
        groupHeader:SetAttribute("_initialAttribute-unit-width", rW)
        groupHeader:SetAttribute("_initialAttribute-unit-height", rH)
        groupHeader:SetSize(rW, rH)
        groupHeader:SetMovable(true)
        groupHeader:SetClampedToScreen(true)

        -- Set child layout attributes BEFORE pre-creation Show() so the
        -- SecureGroupHeaderTemplate positions children correctly on the
        -- very first layout pass.  Without this, children get the template's
        -- default positioning and may not fully reposition on /reload.
        local layoutDB = GetLayoutSettings(true)
        local preGrow = GetLayoutGrowDirection(layoutDB, "DOWN")
        local preSpacing = layoutDB and layoutDB.spacing or 2
        local preColumnAnchorPoint = GetRaidColumnAnchorPoint(layoutDB, preGrow)
        if preGrow == "DOWN" then
            groupHeader:SetAttribute("point", "TOP")
            groupHeader:SetAttribute("xOffset", 0)
            groupHeader:SetAttribute("yOffset", -preSpacing)
        elseif preGrow == "UP" then
            groupHeader:SetAttribute("point", "BOTTOM")
            groupHeader:SetAttribute("xOffset", 0)
            groupHeader:SetAttribute("yOffset", preSpacing)
        elseif preGrow == "RIGHT" then
            groupHeader:SetAttribute("point", "LEFT")
            groupHeader:SetAttribute("xOffset", preSpacing)
            groupHeader:SetAttribute("yOffset", 0)
        elseif preGrow == "LEFT" then
            groupHeader:SetAttribute("point", "RIGHT")
            groupHeader:SetAttribute("xOffset", -preSpacing)
            groupHeader:SetAttribute("yOffset", 0)
        end
        groupHeader:SetAttribute("columnAnchorPoint", preColumnAnchorPoint)

        -- Pre-create enough children for the largest possible section so
        -- custom raid self-first ordering never needs to create frames in combat.
        groupHeader:SetAttribute("showPlayer", true)
        groupHeader:SetAttribute("showSolo", true)
        groupHeader:SetAttribute("startingIndex", -39)
        groupHeader:Show()
        groupHeader:SetAttribute("startingIndex", 1)
        groupHeader:Hide()
        groupHeader:SetAttribute("showPlayer", false)
        groupHeader:SetAttribute("showSolo", false)
    end
    raidRoot:Hide()

    -- Self header — shows only the player for party/solo self-first.
    local selfHeader = CreateFrame("Frame", "QUI_SelfHeader", partyRoot, "SecureGroupHeaderTemplate")
    selfHeader:SetAttribute("template", "QUIGroupUnitButtonTemplate")
    selfHeader:SetAttribute("initialConfigFunction", initConfigFunc)
    QUI_GF.headers.self = selfHeader
    selfHeader:SetAttribute("showPlayer", true)
    selfHeader:SetAttribute("showParty", false)
    selfHeader:SetAttribute("showRaid", false)
    selfHeader:SetAttribute("showSolo", true)
    selfHeader:SetAttribute("maxColumns", 1)
    selfHeader:SetAttribute("unitsPerColumn", 1)

    -- Use party dimensions for self header
    local partyDims = db.party and db.party.dimensions
    local selfW = partyDims and partyDims.partyWidth or 200
    local selfH = partyDims and partyDims.partyHeight or 40
    selfHeader:SetAttribute("_initialAttributeNames", "unit-width,unit-height")
    selfHeader:SetAttribute("_initialAttribute-unit-width", selfW)
    selfHeader:SetAttribute("_initialAttribute-unit-height", selfH)
    selfHeader:SetSize(selfW, selfH)
    selfHeader:SetMovable(true)
    selfHeader:SetClampedToScreen(true)

    -- Pre-create the single child (parent must be shown for creation to work)
    partyRoot:Show()
    selfHeader:SetAttribute("startingIndex", 1)
    selfHeader:Show()
    selfHeader:Hide()
    partyRoot:Hide()
end

---------------------------------------------------------------------------
-- SPOTLIGHT: Create runtime spotlight header if enabled
---------------------------------------------------------------------------
local function CreateSpotlightHeader()
    local db = GetSettings()
    if not db then return end
    local spot = db.raid and db.raid.spotlight
    if not spot or not spot.enabled then return end
    if InCombatLockdown() and not _state.inInitSafeWindow then return end

    -- Already exists (e.g., from a previous init before combat reload)
    if QUI_GF.spotlightContainer then return end

    local w = spot.frameWidth or 180
    local h = spot.frameHeight or 36

    -- Non-secure container: provides stable size. SecureGroupHeaderTemplate
    -- auto-sizes to 0 with no children, making the frame un-clickable.
    local container = CreateFrame("Frame", "QUI_SpotlightContainer", UIParent)
    container:SetSize(w, h)
    container:SetMovable(true)
    container:SetClampedToScreen(true)

    -- Position via frameAnchoring
    local faDB = QUI.db and QUI.db.profile and QUI.db.profile.frameAnchoring
    local saved = faDB and faDB.spotlightFrames
    if saved and saved.point then
        container:SetPoint(saved.point, UIParent, saved.relative or saved.point,
            saved.offsetX or 0, saved.offsetY or 0)
    else
        local pos = spot.position
        container:SetPoint("CENTER", UIParent, "CENTER",
            pos and pos.offsetX or -400, pos and pos.offsetY or 200)
    end

    -- Secure header with QUIGroupUnitButtonTemplate for proper decoration
    local initConfigFunc = [[
        local header = self:GetParent()
        local w = header:GetAttribute("_initialAttribute-unit-width") or 200
        local h = header:GetAttribute("_initialAttribute-unit-height") or 40
        self:SetWidth(w)
        self:SetHeight(h)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
        RegisterUnitWatch(self)
    ]]

    local header = CreateFrame("Frame", "QUI_SpotlightRTHeader", container, "SecureGroupHeaderTemplate")
    header:SetAttribute("template", "QUIGroupUnitButtonTemplate")
    header:SetAttribute("initialConfigFunction", initConfigFunc)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", false)
    header:SetPoint("TOPLEFT")

    -- Filtering: use roleFilter (not groupBy/strictFiltering which are for sorting)
    local filterMode = spot.filterMode or "ROLE"
    if filterMode == "ROLE" then
        local roles = {}
        if spot.filterTank then roles[#roles + 1] = "TANK" end
        if spot.filterHealer then roles[#roles + 1] = "HEALER" end
        if #roles > 0 then
            header:SetAttribute("roleFilter", table.concat(roles, ","))
            -- Also sort by role so tanks appear before healers
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
            header:SetAttribute("groupingOrder", table.concat(roles, ","))
        end
    elseif filterMode == "NAME" then
        local nameList = spot.nameList
        if nameList and nameList ~= "" then
            header:SetAttribute("nameList", nameList)
        end
    end

    header:SetAttribute("_initialAttribute-unit-width", w)
    header:SetAttribute("_initialAttribute-unit-height", h)

    -- Grow direction
    local spacing = spot.spacing or 2
    local grow = spot.growDirection or "DOWN"
    if grow == "DOWN" then
        header:SetAttribute("point", "TOP")
        header:SetAttribute("yOffset", -spacing)
    elseif grow == "UP" then
        header:SetAttribute("point", "BOTTOM")
        header:SetAttribute("yOffset", spacing)
    elseif grow == "RIGHT" then
        header:SetAttribute("point", "LEFT")
        header:SetAttribute("xOffset", spacing)
    elseif grow == "LEFT" then
        header:SetAttribute("point", "RIGHT")
        header:SetAttribute("xOffset", -spacing)
    end

    -- Store references
    QUI_GF.spotlightHeader = header
    QUI_GF.spotlightContainer = container

    -- Force child creation now (during ADDON_LOADED safe window).
    -- Note: SecureGroupHeaderTemplate does NOT fire QUIGroupUnitButtonTemplate
    -- OnLoad for children created on a header whose parent is a non-secure
    -- container. Decorate children manually after creation.
    container:Show()
    header:Show()

    -- Deferred decoration: the secure header needs one frame to finish
    -- creating/assigning children. Decorate + size them once ready.
    C_Timer.After(0, function()
        local h = QUI_GF.spotlightHeader
        if not h then return end
        local s = GetSettings()
        s = s and s.raid and s.raid.spotlight
        local fw = s and s.frameWidth or 180
        local fh = s and s.frameHeight or 36
        local i = 1
        while true do
            local child = h:GetAttribute("child" .. i)
            if not child then break end
            -- Always re-decorate on init: frame may persist from a prior
            -- reload with stale _quiDecorated from a different header.
            child._quiDecorated = nil
            child:SetSize(fw, fh)
            QUI_GF:InitializeHeaderChild(child)
            i = i + 1
        end
        RefreshClickCastFrames()
    end)
end

local function DestroySpotlightHeader()
    if InCombatLockdown() then return end
    local header = QUI_GF.spotlightHeader
    local container = QUI_GF.spotlightContainer
    if header then
        header:Hide()
        QUI_GF.spotlightHeader = nil
    end
    if container then
        container:Hide()
        QUI_GF.spotlightContainer = nil
    end
end

-- Public: edit mode calls this to reconfigure after settings change
function QUI_GF:RecreateSpotlightHeader()
    DestroySpotlightHeader()
    CreateSpotlightHeader()
end

---------------------------------------------------------------------------
-- HEADER: Helper to determine which raid groups (1-8) have at least one member
---------------------------------------------------------------------------
local function GetPopulatedRaidGroups()
    local layout = GetLayoutSettings(true)
    local populated = {}
    for i = 1, GetNumGroupMembers() do
        local _, _, subgroup = GetRaidRosterInfo(i)
        if subgroup and _state.IsRaidSubgroupAllowed(subgroup, layout) then
            populated[subgroup] = true
        end
    end
    return populated
end

local function NormalizeRaidRole(role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return "NONE"
end

_state.GetRaidSortNameParts = function(name)
    if type(name) ~= "string" then
        return "", ""
    end

    local dash = string.find(name, "-", 1, true)
    if dash then
        return string.lower(name:sub(1, dash - 1)), string.lower(name:sub(dash + 1))
    end

    return string.lower(name), ""
end

_state.UnitNameMatchesRoster = function(unit, rosterName)
    if not unit or not rosterName then return false end

    local unitName, unitRealm = UnitName(unit)
    if not unitName then return false end

    if string.find(rosterName, "-", 1, true) then
        if unitRealm and unitRealm ~= "" then
            return rosterName == (unitName .. "-" .. unitRealm)
        end
        return rosterName == unitName
    end

    return rosterName == unitName
end

_state.GetPlayerRosterNames = function()
    local playerName, playerRealm = UnitName("player")
    if not playerName then return nil, nil end
    if playerRealm and playerRealm ~= "" then
        return playerName, playerName .. "-" .. playerRealm
    end
    return playerName, playerName
end

_state.IsPlayerRosterName = function(name, playerName, playerFullName)
    return name and (name == playerName or name == playerFullName)
end

_state.GetStableRaidRosterRole = function(name, unit, rosterRole, unitMatchesRoster, now)
    local role = NormalizeRaidRole(rosterRole)

    if role == "NONE" and unitMatchesRoster then
        local unitRole = NormalizeRaidRole(UnitGroupRolesAssigned(unit))
        if unitRole ~= "NONE" then
            role = unitRole
        end
    end

    local cache = _state.raidRosterSortCache
    local cached = cache[name]
    local inSettlingWindow = now
        and _state.lastGroupRosterUpdateTime
        and (now - _state.lastGroupRosterUpdateTime) <= 2.0

    if role == "NONE" and inSettlingWindow and cached and cached.role and cached.role ~= "NONE" then
        role = cached.role
    end

    if cached then
        cached.role = role
    else
        cache[name] = { role = role }
    end

    return role
end

local function CompareRaidSectionMembers(a, b, sortMethod, sortByRole, playerFirst)
    if playerFirst and a.isPlayer ~= b.isPlayer then
        return a.isPlayer
    end

    if sortByRole and a.role ~= b.role then
        return (RAID_SECTION_ROLE_PRIORITY[a.role] or 99) < (RAID_SECTION_ROLE_PRIORITY[b.role] or 99)
    end

    if sortMethod == "NAME" then
        if a.sortName ~= b.sortName then
            return a.sortName < b.sortName
        end
        if a.sortRealm ~= b.sortRealm then
            return a.sortRealm < b.sortRealm
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
    else
        if a.index ~= b.index then
            return a.index < b.index
        end
    end

    return a.index < b.index
end

GetRaidDisplaySections = function()
    if not IsInRaid() then
        wipe(_state.raidRosterSortCache)
        return {}
    end

    local db = GetSettings()
    local layout = GetLayoutSettings(true)
    if not db or not layout then
        return {}
    end

    local raidSelfFirst = GetRaidSelfFirst(db)
    local groupBy = layout.groupBy or "GROUP"
    local sortMethod = layout.sortMethod or "INDEX"
    local sortByRole = layout.sortByRole == true and groupBy ~= "ROLE"
    local playerSectionKey
    local sectionsByKey = {}
    local sections = {}
    local seenRosterNames = {}
    local playerName, playerFullName = _state.GetPlayerRosterNames()
    local now = GetTime()

    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local name, _, subgroup, _, _, rosterClassFile, _, _, _, _, _, rosterRole = GetRaidRosterInfo(i)
        if name and _state.IsRaidSubgroupAllowed(subgroup, layout) then
            seenRosterNames[name] = true

            local unitMatchesRoster = _state.UnitNameMatchesRoster(unit, name)
            local classFile = rosterClassFile
            if not classFile and unitMatchesRoster then
                local _, unitClassFile = UnitClass(unit)
                classFile = unitClassFile
            end
            classFile = classFile or "UNKNOWN"

            local role = _state.GetStableRaidRosterRole(name, unit, rosterRole, unitMatchesRoster, now)
            local sortName, sortRealm = _state.GetRaidSortNameParts(name)
            local sectionKey, sectionOrder

            if groupBy == "NONE" then
                sectionKey, sectionOrder = "ALL", 1
            elseif groupBy == "ROLE" then
                sectionKey = role
                sectionOrder = RAID_SECTION_ROLE_PRIORITY[role] or 99
            elseif groupBy == "CLASS" then
                sectionKey = classFile or "UNKNOWN"
                sectionOrder = RAID_SECTION_CLASS_PRIORITY[sectionKey] or 99
            else
                sectionKey = tostring(subgroup or 0)
                sectionOrder = subgroup or 99
            end

            local section = sectionsByKey[sectionKey]
            if not section then
                section = {
                    key = sectionKey,
                    order = sectionOrder,
                    members = {},
                }
                sectionsByKey[sectionKey] = section
                table_insert(sections, section)
            end

            local isPlayer = _state.IsPlayerRosterName(name, playerName, playerFullName)
                or (unitMatchesRoster and UnitIsUnit(unit, "player"))
            table_insert(section.members, {
                name = name,
                index = i,
                subgroup = subgroup or 0,
                classFile = classFile,
                role = role,
                isPlayer = isPlayer,
                sortName = sortName,
                sortRealm = sortRealm,
            })

            if isPlayer then
                playerSectionKey = sectionKey
            end
        end
    end

    for name in pairs(_state.raidRosterSortCache) do
        if not seenRosterNames[name] then
            _state.raidRosterSortCache[name] = nil
        end
    end

    for _, section in ipairs(sections) do
        table_sort(section.members, function(a, b)
            return CompareRaidSectionMembers(a, b, sortMethod, sortByRole, raidSelfFirst)
        end)

        local names = {}
        for _, member in ipairs(section.members) do
            table_insert(names, member.name)
        end

        section.memberCount = #section.members
        section.nameList = table_concat(names, ",")
    end

    table_sort(sections, function(a, b)
        if raidSelfFirst and playerSectionKey then
            if a.key == playerSectionKey and b.key ~= playerSectionKey then
                return true
            end
            if b.key == playerSectionKey and a.key ~= playerSectionKey then
                return false
            end
        end

        if a.order ~= b.order then
            return a.order < b.order
        end

        return tostring(a.key) < tostring(b.key)
    end)

    return sections
end

GetRaidSectionUnitsPerColumn = function(layout)
    if not layout then return 5 end
    if (layout.groupBy or "GROUP") == "NONE" then
        return math_max(layout.unitsPerFlat or 5, 1)
    end
    return 5
end

CalculateRaidSectionHeaderSize = function(sectionCount, mode, layout)
    if not sectionCount or sectionCount <= 0 then
        return 1, 1
    end

    local frameW, frameH = GetFrameDimensions(mode)
    local spacing = layout and layout.spacing or 2
    local grow = GetLayoutGrowDirection(layout, "DOWN")
    local unitsPerColumn = math_max(1, math_min(sectionCount, GetRaidSectionUnitsPerColumn(layout)))
    local columnCount = math_max(1, math.ceil(sectionCount / unitsPerColumn))
    local leadingCount = math_min(sectionCount, unitsPerColumn)
    local horizontal = (grow == "LEFT" or grow == "RIGHT")

    if horizontal then
        return leadingCount * frameW + (leadingCount - 1) * spacing,
            columnCount * frameH + (columnCount - 1) * spacing
    end

    return columnCount * frameW + (columnCount - 1) * spacing,
        leadingCount * frameH + (leadingCount - 1) * spacing
end

-- Forward declaration: defined after UpdateHeaderVisibility (used in deferred callback)
local ApplyChildFrameLayout

---------------------------------------------------------------------------
-- HEADER: Update header sizes based on current roster
---------------------------------------------------------------------------
local function UpdateHeaderSizes()
    if InCombatLockdown() and not _state.inInitSafeWindow then return end
    local db = GetSettings()
    if not db then return end

    local partyHdr = QUI_GF.headers.party
    if partyHdr then
        local count = math_max(GetVisiblePartyUnitCount(), 1)
        local w, h = CalculateHeaderSize(db, count)
        partyHdr:SetSize(w, h)
    end

    if UseRaidSectionHeaders(db) and IsInRaid() then
        -- Section-header mode: size each visible raid section individually.
        local mode = GetGroupMode()
        local raidVdb = db.raid or db
        local layout = raidVdb and raidVdb.layout
        local sections = _state.UseRaidNameListSections(db, layout) and GetRaidDisplaySections() or nil
        local populated = sections and nil or GetPopulatedRaidGroups()

        for g, header in ipairs(QUI_GF.raidGroupHeaders) do
            if sections then
                local section = sections[g]
                if section then
                    local hdrW, hdrH = CalculateRaidSectionHeaderSize(section.memberCount, mode, layout)
                    header:SetSize(hdrW, hdrH)
                else
                    header:SetSize(1, 1)
                end
            elseif g <= 8 and populated and populated[g] then
                local groupCount = 0
                for i = 1, GetNumGroupMembers() do
                    local _, _, subgroup = GetRaidRosterInfo(i)
                    if subgroup == g then
                        groupCount = groupCount + 1
                    end
                end
                local hdrW, hdrH = CalculateRaidSectionHeaderSize(math_max(groupCount, 1), mode, layout)
                header:SetSize(hdrW, hdrH)
            else
                header:SetSize(1, 1)
            end
        end

        -- Hide single raid header whenever section headers are active.
        if QUI_GF.headers.raid then QUI_GF.headers.raid:SetSize(1, 1) end
    else
        local raidHdr = QUI_GF.headers.raid
        if raidHdr then
            local count = IsInRaid() and GetNumGroupMembers() or 25
            count = math_max(count, 5)
            local w, h = CalculateHeaderSize(db, count)
            raidHdr:SetSize(w, h)
        end
    end

    -- Self header uses party dimensions; root layout handles ordering.
    local selfHdr = QUI_GF.headers.self
    if selfHdr then
        local partyDims = db.party and db.party.dimensions
        local sw = partyDims and partyDims.partyWidth or 200
        local sh = partyDims and partyDims.partyHeight or 40
        selfHdr:SetAttribute("_initialAttribute-unit-width", sw)
        selfHdr:SetAttribute("_initialAttribute-unit-height", sh)
        selfHdr:SetSize(sw, sh)
        -- Resize existing child
        local child = selfHdr:GetAttribute("child1")
        if child then child:SetSize(sw, sh) end
        -- Self header is party-only, so keep it chained to the party block.
        if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("partyFrames")) then
            selfHdr:ClearAllPoints()
            if partyHdr then
                selfHdr:SetPoint("BOTTOMLEFT", partyHdr, "TOPLEFT", 0, 4)
            end
        end
    end

    UpdateAnchorFrames()
end

---------------------------------------------------------------------------
-- HEADER: Show/hide based on group status
---------------------------------------------------------------------------
-- Show/hide per-group headers; hide single raid header
local function ShowRaidGroupHeaders()
    if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end

    local db = GetSettings()
    local layout = GetLayoutSettings(true)
    local useNameListSections = _state.UseRaidNameListSections(db, layout)
    local sections = ConfigureRaidGroupHeaders()
    local populated = useNameListSections and nil or GetPopulatedRaidGroups()

    for g, header in ipairs(QUI_GF.raidGroupHeaders) do
        if useNameListSections then
            if sections and sections[g] then
                header:Show()
            else
                header:Hide()
            end
        elseif g <= 8 and populated and populated[g] then
            header:Show()
        else
            header:Hide()
        end
    end

    PositionRaidGroupHeaders()
end

-- Hide all per-group headers
local function HideRaidGroupHeaders()
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header then header:Hide() end
    end
end

_state.EnsureCombatVisibleRoots = function()
    local layoutMode = ns.QUI_LayoutMode
    local hidden = layoutMode and layoutMode._gameplayHidden
    local partyRoot = QUI_GF.anchorFrames and QUI_GF.anchorFrames.party
    if partyRoot and not (hidden and hidden.partyFrames) then
        partyRoot:SetAlpha(1)
    end

    local raidRoot = QUI_GF.anchorFrames and QUI_GF.anchorFrames.raid
    if raidRoot and not (hidden and hidden.raidFrames) then
        raidRoot:SetAlpha(1)
    end

    if QUI_GF.spotlightContainer and not (hidden and hidden.spotlightFrames) then
        QUI_GF.spotlightContainer:SetAlpha(1)
    end
end

local function UpdateHeaderVisibility()
    if InCombatLockdown() and not _state.inInitSafeWindow then
        _state.EnsureCombatVisibleRoots()
        _pending.visibilityUpdate = true
        return
    end

    local db = GetSettings()
    if not db or not db.enabled then
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
        if QUI_GF.headers.self then QUI_GF.headers.self:Hide() end
        if QUI_GF.spotlightHeader then QUI_GF.spotlightHeader:Hide() end
        if QUI_GF.spotlightContainer then QUI_GF.spotlightContainer:Hide() end
        HideRaidGroupHeaders()
        UpdateAnchorFrames()
        return
    end

    if QUI_GF.testMode then
        -- Test mode handled by edit mode module
        UpdateAnchorFrames()
        return
    end

    local partySelfFirst = GetPartySelfFirst(db)
    local selfHeader = QUI_GF.headers.self
    local useRaidSections = UseRaidSectionHeaders(db)

    if QUI_GF.headers.party then ConfigurePartyHeader(QUI_GF.headers.party) end

    -- Configure single or multi-header raid headers
    if useRaidSections then
        -- Single header is hidden; per-group headers are configured below
    else
        if QUI_GF.headers.raid then ConfigureRaidHeader(QUI_GF.headers.raid) end
        HideRaidGroupHeaders()
    end

    if selfHeader then
        selfHeader:SetAttribute("showSolo", partySelfFirst and true or false)
    end

    if IsInRaid() then
        if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
        if useRaidSections then
            ShowRaidGroupHeaders()
        else
            if QUI_GF.headers.raid then QUI_GF.headers.raid:Show() end
            HideRaidGroupHeaders()
        end
        if selfHeader then
            selfHeader:Hide()
        end
    elseif IsInGroup() then
        if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
        HideRaidGroupHeaders()
        if QUI_GF.headers.party then QUI_GF.headers.party:Show() end
        if selfHeader then
            if partySelfFirst then selfHeader:Show() else selfHeader:Hide() end
        end
    else
        -- Solo: check showSolo setting
        local partyLayout = GetLayoutSettings(false)
        local showSolo = partyLayout and partyLayout.showSolo
        if partySelfFirst then showSolo = false end
        if showSolo then
            if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
            HideRaidGroupHeaders()
            if QUI_GF.headers.party then QUI_GF.headers.party:Show() end
        else
            if QUI_GF.headers.party then QUI_GF.headers.party:Hide() end
            if QUI_GF.headers.raid then QUI_GF.headers.raid:Hide() end
            HideRaidGroupHeaders()
        end
        if selfHeader then
            if partySelfFirst then selfHeader:Show() else selfHeader:Hide() end
        end
    end

    -- Spotlight: raid-only. Hidden in party and solo.
    if QUI_GF.spotlightContainer then
        if IsInRaid() then
            QUI_GF.spotlightContainer:Show()
            if QUI_GF.spotlightHeader then QUI_GF.spotlightHeader:Show() end
            -- Decorate any new children (SecureGroupHeaderTemplate OnLoad
            -- does not fire QUIGroupUnitButtonTemplate scripts reliably).
            C_Timer.After(0.2, function()
                local h = QUI_GF.spotlightHeader
                if not h then return end
                local s = GetSettings()
                s = s and s.raid and s.raid.spotlight
                local fw = s and s.frameWidth or 180
                local fh = s and s.frameHeight or 36
                local newCount = 0
                local i = 1
                while true do
                    local child = h:GetAttribute("child" .. i)
                    if not child then break end
                    if not child._quiDecorated then
                        child:SetSize(fw, fh)
                        QUI_GF:InitializeHeaderChild(child)
                        newCount = newCount + 1
                    end
                    i = i + 1
                end
                -- Refresh all spotlight frames so they display current unit data
                if newCount > 0 then
                    RefreshClickCastFrames()
                    RebuildUnitFrameMap()
                    QUI_GF:RefreshAllFrames()
                end
            end)
        else
            if QUI_GF.spotlightHeader then QUI_GF.spotlightHeader:Hide() end
            QUI_GF.spotlightContainer:Hide()
        end
    end

    -- On first layout (no decorated children yet), hide anchor roots so
    -- the user never sees unstyled raw rectangles pop in one by one.
    -- The secure header still creates children (the root is Shown via
    -- UpdateAnchorFrames), but alpha 0 keeps them invisible until ready.
    -- Skip for subsequent roster updates when frames are already styled.
    local needsReveal = not _state.initialLayoutDone
    if needsReveal then
        for _, root in pairs(QUI_GF.anchorFrames) do
            root:SetAlpha(0)
        end
    end

    UpdateHeaderSizes()
    UpdateAnchorFrames()

    -- End safe period before the deferred callback so combat guards apply
    _pending.initSafe = false

    -- Children self-decorate via QUIGroupUnitButtonTemplate OnLoad at header
    -- creation time — no decoration work remains for this path. Defer the
    -- map rebuild + refresh one frame so the secure header has finished any
    -- in-progress child reassignments from the size/attribute changes above.
    C_Timer.After(0, function()
        ApplyChildFrameLayout()
        RebuildUnitFrameMap()
        RefreshClickCastFrames()
        QUI_GF:RefreshAllFrames()
        UpdateAnchorFrames()
        initSafePeriod = false

        -- Reveal: all frames are now sized and populated.
        if needsReveal then
            _state.initialLayoutDone = true
            for _, root in pairs(QUI_GF.anchorFrames) do
                root:SetAlpha(1)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- SCALING: Resize frames based on group size thresholds
---------------------------------------------------------------------------
-- Resize/layout unit buttons and bars. SetSize on the secure unit buttons
-- themselves is protected, so skip it during combat — the pending resize
-- will re-apply after combat via PLAYER_REGEN_ENABLED.
-- Uses per-child dimensions: party/self children get party dims, raid
-- children get current raid-mode dims. This prevents cross-contamination
-- when the group transitions between party and raid.
ApplyChildFrameLayout = function()
    local inCombat = InCombatLockdown()
    local partyW, partyH = GetFrameDimensions("party")
    local raidMode = GetGroupMode()
    local raidW, raidH = GetFrameDimensions(raidMode ~= "party" and raidMode or "small")

    local function LayoutChildren(header)
        if not header then return end
        local i = 1
        while true do
            local child = header:GetAttribute("child" .. i)
            if not child then break end
            if not child._quiDecorated and (not inCombat or _state.inInitSafeWindow) then
                QUI_GF:InitializeHeaderChild(child)
            end
            local isRaidChild = child._isRaid and true or false
            if not inCombat then
                local cw, ch = isRaidChild and raidW or partyW, isRaidChild and raidH or partyH
                child:SetSize(cw, ch)
            end
            if child.healthBar and child.powerBar then
                local general = GetGeneralSettings(isRaidChild)
                local borderPx = general and general.borderSize or 1
                local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, child) or borderPx) or 0
                local powerSettings = GetPowerSettings(isRaidChild)
                local powerHeight = powerSettings and powerSettings.showPowerBar ~= false and
                    (QUICore.PixelRound and QUICore:PixelRound(powerSettings.powerBarHeight or 4, child) or 4) or 0
                local px = QUICore.GetPixelSize and QUICore:GetPixelSize(child) or 1
                local sepH = powerHeight > 0 and px or 0

                child.healthBar:ClearAllPoints()
                child.healthBar:SetPoint("TOPLEFT", child, "TOPLEFT", borderSize, -borderSize)
                child.healthBar:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + sepH)
                ApplyStatusBarTexture(child.healthBar)

                local vertFill = (GetHealthFillDirection(isRaidChild) == "VERTICAL")
                child.healthBar:SetOrientation(vertFill and "VERTICAL" or "HORIZONTAL")
                child._isVerticalFill = vertFill

                if child.powerBar then
                    child.powerBar:ClearAllPoints()
                    child.powerBar:SetPoint("BOTTOMLEFT", child, "BOTTOMLEFT", borderSize, borderSize)
                    child.powerBar:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -borderSize, borderSize)
                    child.powerBar:SetHeight(powerHeight)
                    ApplyStatusBarTexture(child.powerBar)
                end
                if child.healPredictionBar then ApplyStatusBarTexture(child.healPredictionBar) end
            end
            i = i + 1
        end
    end

    for _, headerKey in ipairs({"party", "raid", "self"}) do
        LayoutChildren(QUI_GF.headers[headerKey])
    end
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        LayoutChildren(header)
    end
end

local function UpdateFrameScaling(forceUpdate)
    local mode = GetGroupMode()

    if InCombatLockdown() and not _state.inInitSafeWindow then
        _pending.resize = true
        _pending.resizeForce = _pending.resizeForce or (forceUpdate and true or false)
        ApplyChildFrameLayout()
        return
    end

    if not forceUpdate and mode == _state.lastMode then return end
    _state.lastMode = mode

    -- Per-header-type attributes: party/self get party dims, raid headers
    -- get current raid-mode dims. This ensures initialConfigFunction uses
    -- the correct dimensions if the secure system ever creates new children.
    local partyW, partyH = GetFrameDimensions("party")
    local raidW, raidH = GetFrameDimensions(mode ~= "party" and mode or "small")

    local partyHeader = QUI_GF.headers.party
    if partyHeader then
        partyHeader:SetAttribute("_initialAttribute-unit-width", partyW)
        partyHeader:SetAttribute("_initialAttribute-unit-height", partyH)
    end
    local selfHeader = QUI_GF.headers.self
    if selfHeader then
        selfHeader:SetAttribute("_initialAttribute-unit-width", partyW)
        selfHeader:SetAttribute("_initialAttribute-unit-height", partyH)
    end
    local raidHeader = QUI_GF.headers.raid
    if raidHeader then
        raidHeader:SetAttribute("_initialAttribute-unit-width", raidW)
        raidHeader:SetAttribute("_initialAttribute-unit-height", raidH)
    end
    for _, header in ipairs(QUI_GF.raidGroupHeaders) do
        if header then
            header:SetAttribute("_initialAttribute-unit-width", raidW)
            header:SetAttribute("_initialAttribute-unit-height", raidH)
        end
    end

    ApplyChildFrameLayout()
    UpdateHeaderSizes()
end

local function ApplyHUDLayering()
    local profile = QUI.db and QUI.db.profile
    local layering = profile and profile.hudLayering
    local level = layering and layering.groupFrames or 4
    if QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(level)
        for _, headerKey in ipairs({"party", "raid", "self"}) do
            local header = QUI_GF.headers[headerKey]
            if header then pcall(header.SetFrameLevel, header, frameLevel) end
        end
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
            if header then pcall(header.SetFrameLevel, header, frameLevel) end
        end
    end
end

_.UpdateFrame = UpdateFrame
_.DecorateGroupFrame = DecorateGroupFrame
_.EnsureAnchorFrame = EnsureAnchorFrame
_.UpdateAnchorFrames = UpdateAnchorFrames
_.ConfigurePartyHeader = ConfigurePartyHeader
_.ConfigureRaidHeader = ConfigureRaidHeader
_.ConfigureRaidGroupHeaders = ConfigureRaidGroupHeaders
_.PositionRaidGroupHeaders = PositionRaidGroupHeaders
_.UpdateHeaderSizes = UpdateHeaderSizes
_.UpdateHeaderVisibility = UpdateHeaderVisibility
_.ApplyChildFrameLayout = ApplyChildFrameLayout
_.UpdateFrameScaling = UpdateFrameScaling
_.CreateHeaders = CreateHeaders
_.CreateSpotlightHeader = CreateSpotlightHeader
_.DestroySpotlightHeader = DestroySpotlightHeader
_.ApplyHUDLayering = ApplyHUDLayering
