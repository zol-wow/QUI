local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local Helpers = ns.Helpers
local UIKit = ns.UIKit
local QUICore = ns.Addon
local IsSecretValue = Helpers.IsSecretValue

local type = type
local pcall = pcall
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitHealthPercent = UnitHealthPercent
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitName = UnitName

local NPHealth = {}
NP.Health = NPHealth

local WHITE8X8 = "Interface\\Buttons\\WHITE8x8"

local GetBarTexture = NP.GetBarTexture

local function GetHealthPct(unit)
    if type(UnitHealthPercent) == "function" then
        if CurveConstants and CurveConstants.ScaleTo100 then
            local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
            if ok then return pct end
        end
        local ok, pct = pcall(UnitHealthPercent, unit, true)
        if ok then return pct end
    end
    return nil
end

function NPHealth.Build(plate)
    local healthBar = CreateFrame("StatusBar", nil, plate)
    healthBar:SetPoint("CENTER", plate, "CENTER", 0, 0)
    healthBar:SetStatusBarTexture(WHITE8X8)
    healthBar:SetMinMaxValues(0, 1)
    healthBar:SetValue(0)
    healthBar:EnableMouse(false)
    plate.healthBar = healthBar

    plate.healthBg = UIKit.CreateBackground(healthBar, 0.12, 0.12, 0.12, 1)
    UIKit.CreateBorderLines(healthBar)

    local absorbBar = CreateFrame("StatusBar", nil, healthBar)
    absorbBar:SetStatusBarTexture(WHITE8X8)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    absorbBar:EnableMouse(false)
    absorbBar:Hide()
    plate.absorbBar = absorbBar

    local healPredictBar = CreateFrame("StatusBar", nil, healthBar)
    healPredictBar:SetStatusBarTexture(WHITE8X8)
    healPredictBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredictBar:EnableMouse(false)
    healPredictBar:Hide()
    plate.healPredictBar = healPredictBar

    local mask = healthBar:CreateMaskTexture()
    mask:SetTexture(WHITE8X8, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(healthBar)
    plate.absorbMask = mask
    local absorbTex = absorbBar:GetStatusBarTexture()
    if absorbTex and absorbTex.AddMaskTexture then
        pcall(absorbTex.AddMaskTexture, absorbTex, mask)
    end
    local healTex = healPredictBar:GetStatusBarTexture()
    if healTex and healTex.AddMaskTexture then
        pcall(healTex.AddMaskTexture, healTex, mask)
    end

    local powerBar = CreateFrame("StatusBar", nil, plate)
    powerBar:SetStatusBarTexture(WHITE8X8)
    powerBar:SetMinMaxValues(0, 1)
    powerBar:SetValue(0)
    powerBar:EnableMouse(false)
    powerBar:Hide()
    plate.powerBar = powerBar
    plate.powerBg = UIKit.CreateBackground(powerBar, 0.1, 0.1, 0.1, 0.9)
    UIKit.CreateBorderLines(powerBar)

    local textCarrier = CreateFrame("Frame", nil, plate)
    textCarrier:SetAllPoints(plate)
    textCarrier:SetFrameLevel(healthBar:GetFrameLevel() + 10)
    plate.npTextCarrier = textCarrier

    plate.nameText = UIKit.CreateText(textCarrier, 11, nil, "OUTLINE", "OVERLAY")
    plate.nameText:SetPoint("BOTTOM", healthBar, "TOP", 0, 4)
    plate.healthText = UIKit.CreateText(textCarrier, 10, nil, "OUTLINE", "OVERLAY")
    plate.healthText:SetPoint("RIGHT", healthBar, "RIGHT", -2, 0)

    plate.npTitleText = UIKit.CreateText(textCarrier, 9, nil, "OUTLINE", "OVERLAY")
    plate.npTitleText:SetPoint("TOP", plate.nameText, "BOTTOM", 0, -1)
    plate.npTitleText:Hide()

    plate.npAbsorbText = UIKit.CreateText(textCarrier, 9, nil, "OUTLINE", "OVERLAY")
    plate.npAbsorbText:Hide()

    plate.npLevelText = UIKit.CreateText(textCarrier, 9, nil, "OUTLINE", "OVERLAY")
    plate.npLevelText:Hide()
    plate.npClassIcon = textCarrier:CreateTexture(nil, "OVERLAY", nil, 4)
    plate.npClassIcon:Hide()
end

function NPHealth.ApplyAppearance(plate, settings)
    local health = settings.health or {}
    local nameS = settings.name or {}
    local textS = settings.healthText or {}
    local absorbS = settings.absorbs or {}

    local healthBar = plate.healthBar
    QUICore:SetPixelPerfectSize(healthBar, health.width or 210, health.height or 24)
    healthBar:SetStatusBarTexture(GetBarTexture(health.texture))
    local fillTex = healthBar:GetStatusBarTexture()
    if fillTex then
        fillTex:SetHorizTile(false)
        fillTex:SetVertTile(false)
    end

    local bg = health.bgColor or { 0.12, 0.12, 0.12 }
    plate.healthBg:SetVertexColor(bg[1], bg[2], bg[3], health.bgAlpha or 1)

    local bc = health.borderColor or { 0, 0, 0 }
    UIKit.UpdateBorderLines(healthBar, health.borderSize or 1, bc[1] or 0, bc[2] or 0, bc[3] or 0, 1,
        (health.borderSize or 1) <= 0)

    local absorbBar = plate.absorbBar
    absorbBar:ClearAllPoints()
    if fillTex then
        absorbBar:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        absorbBar:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    else
        absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        absorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    end
    absorbBar:SetWidth(QUICore:Pixels(health.width or 210, plate))
    absorbBar:SetStatusBarTexture(GetBarTexture(health.texture))
    local ac = absorbS.color or { 1, 1, 1 }
    absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], absorbS.opacity or 0.3)
    plate.npAbsorbsEnabled = absorbS.enabled ~= false

    local healS = settings.healPrediction or {}
    local healBar = plate.healPredictBar
    healBar:ClearAllPoints()
    if fillTex then
        healBar:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        healBar:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    else
        healBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        healBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    end
    healBar:SetWidth(QUICore:Pixels(health.width or 210, plate))
    healBar:SetStatusBarTexture(GetBarTexture(health.texture))
    local hc = healS.color or { 0.25, 0.80, 0.25 }
    healBar:SetStatusBarColor(hc[1], hc[2], hc[3], healS.opacity or 0.4)
    plate.npHealPredictEnabled = healS.enabled == true
    if not plate.npHealPredictEnabled then healBar:Hide() end

    plate.npSmoothInterp = (health.smooth == true and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut) or nil

    local pb = settings.powerBar or {}
    plate.npPowerBarEnabled = pb.enabled == true
    local powerBar = plate.powerBar
    QUICore:SetPixelPerfectSize(powerBar, health.width or 210, pb.height or 6)
    powerBar:ClearAllPoints()
    powerBar:SetPoint("TOP", healthBar, "BOTTOM", 0, -QUICore:Pixels(1, plate))
    powerBar:SetStatusBarTexture(GetBarTexture(health.texture))
    UIKit.UpdateBorderLines(powerBar, health.borderSize or 1, bc[1] or 0, bc[2] or 0, bc[3] or 0, 1,
        (health.borderSize or 1) <= 0)
    if not plate.npPowerBarEnabled then powerBar:Hide() end

    local fontPath, fontOutline = NP.ResolveFont(plate)

    QUICore:ApplyFont(plate.nameText, nil, nameS.size or 11, fontPath, fontOutline)
    plate.nameText:ClearAllPoints()
    plate.nameText:SetPoint(
        nameS.point or "BOTTOM",
        healthBar,
        nameS.relativePoint or "TOP",
        QUICore:Pixels(nameS.offsetX or 0, plate),
        QUICore:Pixels(nameS.offsetY or 4, plate))
    plate.nameText:SetJustifyH(nameS.justify or "CENTER")
    if nameS.enabled == false then plate.nameText:Hide() else plate.nameText:Show() end
    plate.npNameTruncate = nameS.truncateLength or 28

    QUICore:ApplyFont(plate.healthText, nil, textS.size or 10, fontPath, fontOutline)
    plate.healthText:ClearAllPoints()
    plate.healthText:SetPoint(
        textS.point or "RIGHT",
        healthBar,
        textS.relativePoint or "RIGHT",
        QUICore:Pixels(textS.offsetX or -2, plate),
        QUICore:Pixels(textS.offsetY or 0, plate))
    plate.healthText:SetJustifyH(textS.justify or "RIGHT")
    local htc = textS.color or { 1, 1, 1 }
    plate.healthText:SetTextColor(htc[1] or 1, htc[2] or 1, htc[3] or 1)

    local titleS = settings.npcTitle or {}
    plate.npTitleEnabled = titleS.enabled == true
    QUICore:ApplyFont(plate.npTitleText, nil, titleS.size or 9, fontPath, fontOutline)
    local tc = titleS.color or { 0.7, 0.7, 0.7 }
    plate.npTitleText:SetTextColor(tc[1] or 0.7, tc[2] or 0.7, tc[3] or 0.7)
    if not plate.npTitleEnabled then plate.npTitleText:Hide() end

    plate.npAbsorbTextEnabled = absorbS.showText == true
    QUICore:ApplyFont(plate.npAbsorbText, nil, absorbS.textSize or 9, fontPath, fontOutline)
    plate.npAbsorbText:ClearAllPoints()
    plate.npAbsorbText:SetPoint("LEFT", healthBar, "LEFT", QUICore:Pixels(2, plate), 0)
    if not plate.npAbsorbTextEnabled then plate.npAbsorbText:Hide() end

    local lvl = settings.level or {}
    plate.npLevelEnabled = lvl.enabled == true
    plate.npClassIconEnabled = lvl.showClassification ~= false
    QUICore:ApplyFont(plate.npLevelText, nil, lvl.size or 9, fontPath, fontOutline)
    plate.npLevelText:ClearAllPoints()
    plate.npLevelText:SetPoint(
        lvl.point or "LEFT",
        healthBar,
        lvl.relativePoint or "RIGHT",
        QUICore:Pixels(lvl.offsetX or 2, plate),
        QUICore:Pixels(lvl.offsetY or 0, plate))
    local iconSize = lvl.classificationSize or 14
    QUICore:SetPixelPerfectSize(plate.npClassIcon, iconSize, iconSize)
    plate.npClassIcon:ClearAllPoints()
    if plate.npLevelEnabled then
        plate.npClassIcon:SetPoint("RIGHT", plate.npLevelText, "LEFT", -QUICore:Pixels(1, plate), 0)
    else
        plate.npClassIcon:SetPoint(
            lvl.point or "LEFT",
            healthBar,
            lvl.relativePoint or "RIGHT",
            QUICore:Pixels(lvl.offsetX or 2, plate),
            QUICore:Pixels(lvl.offsetY or 0, plate))
    end
    if not plate.npLevelEnabled then
        plate.npLevelText:Hide()
    end
    if not plate.npClassIconEnabled then
        plate.npClassIcon:Hide()
    end

    local style = textS.style or "percent"
    if textS.enabled == false then style = "none" end
    plate.npHealthTextStyle = style
    if style == "none" then
        plate.healthText:SetText("")
        plate.healthText:Hide()
    else
        plate.healthText:Show()
    end
    local pctBase = (textS.precision == 1) and "%.1f" or "%.0f"
    plate.npPctFmt = (textS.hidePercentSymbol == true) and pctBase or (pctBase .. "%%")
    local seps = { bar = "%s | ", paren = "%s (", dash = "%s - ", space = "%s " }
    local sep = seps[textS.bothFormat or "bar"] or seps.bar
    plate.npBothFmt = sep .. plate.npPctFmt .. ((textS.bothFormat == "paren") and ")" or "")
end

function NPHealth.UpdateHealth(plate)
    local unit = plate.unit
    if not unit then return end
    local healthBar = plate.healthBar

    local maxHP = UnitHealthMax(unit)
    local hp = UnitHealth(unit)
    if type(maxHP) == "nil" then maxHP = 1 end
    if IsSecretValue(maxHP) or maxHP ~= plate.npLastMaxHP then
        if not IsSecretValue(maxHP) then plate.npLastMaxHP = maxHP end
        healthBar:SetMinMaxValues(0, maxHP)
    end
    if type(hp) ~= "nil" then
        if plate.npSmoothInterp then
            local okV = pcall(healthBar.SetValue, healthBar, hp, plate.npSmoothInterp)
            if not okV then healthBar:SetValue(hp) end
        else
            healthBar:SetValue(hp)
        end
    end

    local style = plate.npHealthTextStyle
    if style == "none" then
        return
    end
    local healthText = plate.healthText

    local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
    if okDead and NP.Plain(dead, "boolean") == true then
        healthText:SetText("0%")
        return
    end

    local ok
    if style == "absolute" then
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        if abbr then
            ok = pcall(healthText.SetText, healthText, abbr(hp))
        else
            ok = pcall(healthText.SetFormattedText, healthText, "%s", hp)
        end
    elseif style == "both" then
        local pct = GetHealthPct(unit)
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        if abbr then
            ok = pcall(healthText.SetFormattedText, healthText, plate.npBothFmt, abbr(hp), pct)
        else
            ok = pcall(healthText.SetFormattedText, healthText, plate.npBothFmt, hp, pct)
        end
    else
        local pct = GetHealthPct(unit)
        ok = pcall(healthText.SetFormattedText, healthText, plate.npPctFmt, pct)
    end
    if not ok then
        healthText:SetText("")
    end
end

function NPHealth.UpdateAbsorbs(plate)
    local unit = plate.unit
    if not unit or not plate.npAbsorbsEnabled then return end
    local absorbBar = plate.absorbBar

    local amount = UnitGetTotalAbsorbs(unit)
    if type(amount) == "nil" then
        if not plate.npAbsorbHidden then
            plate.npAbsorbHidden = true
            absorbBar:Hide()
        end
        plate.npAbsorbText:Hide()
        return
    end

    if not IsSecretValue(amount) and amount == 0 then -- @secret-safe: probe leads this compound; short-circuit keeps the compare off secrets
        if not plate.npAbsorbHidden then
            plate.npAbsorbHidden = true
            absorbBar:Hide()
        end
        plate.npAbsorbText:Hide()
        return
    end

    if plate.npAbsorbHidden then
        plate.npAbsorbHidden = false
        absorbBar:Show()
    end

    local maxHP = UnitHealthMax(unit)
    if type(maxHP) == "nil" then maxHP = 1 end
    if IsSecretValue(maxHP) or maxHP ~= plate.npLastAbsorbMax then
        if not IsSecretValue(maxHP) then plate.npLastAbsorbMax = maxHP end
        absorbBar:SetMinMaxValues(0, maxHP)
    end
    absorbBar:SetValue(amount)

    if plate.npAbsorbTextEnabled then
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        local okT
        if abbr then
            okT = pcall(plate.npAbsorbText.SetFormattedText, plate.npAbsorbText, "+%s", abbr(amount))
        else
            okT = pcall(plate.npAbsorbText.SetFormattedText, plate.npAbsorbText, "+%s", amount)
        end
        if okT then plate.npAbsorbText:Show() else plate.npAbsorbText:Hide() end
    else
        plate.npAbsorbText:Hide()
    end
end

function NPHealth.UpdateHealPrediction(plate)
    local bar = plate.healPredictBar
    if not bar then return end
    local unit = plate.unit
    if not unit or not plate.npHealPredictEnabled then
        bar:Hide()
        return
    end
    if type(UnitGetIncomingHeals) ~= "function" then
        bar:Hide()
        return
    end
    local ok, amount = pcall(UnitGetIncomingHeals, unit)
    if not ok or type(amount) == "nil" then
        bar:Hide()
        return
    end
    if not IsSecretValue(amount) and amount == 0 then -- @secret-safe: probe leads this compound; short-circuit keeps the compare off secrets
        bar:Hide()
        return
    end
    local maxHP = UnitHealthMax(unit)
    if type(maxHP) == "nil" then maxHP = 1 end
    bar:SetMinMaxValues(0, maxHP)
    bar:SetValue(amount)
    bar:Show()
end

function NPHealth.UpdatePower(plate)
    local bar = plate.powerBar
    if not bar then return end
    local unit = plate.unit
    if not unit or not plate.npPowerBarEnabled or plate.npIsPlayer == true then
        bar:Hide()
        return
    end
    local s = (NP.GetTypeSettings(plate) or {}).powerBar or {}
    local okT, token = pcall(UnitPowerType, unit)
    token = okT and NP.Plain(token, "number") or nil
    if token == nil or (s.manaOnly ~= false and token ~= 0) then
        bar:Hide()
        return
    end
    local okMax, maxP = pcall(UnitPowerMax, unit)
    if not okMax or type(maxP) == "nil" then
        bar:Hide()
        return
    end
    if not IsSecretValue(maxP) and maxP == 0 then -- @secret-safe: probe leads this compound; short-circuit keeps the compare off secrets
        bar:Hide()
        return
    end
    local okCur, cur = pcall(UnitPower, unit)
    if not okCur or type(cur) == "nil" then
        bar:Hide()
        return
    end
    bar:SetMinMaxValues(0, maxP)
    bar:SetValue(cur)
    local pc = _G.PowerBarColor and _G.PowerBarColor[token]
    if type(pc) == "table" and NP.Plain(pc.r, "number") then
        bar:SetStatusBarColor(pc.r, pc.g or 0.5, pc.b or 0.9)
    else
        bar:SetStatusBarColor(0.3, 0.5, 0.9)
    end
    bar:Show()
end

function NPHealth.UpdateName(plate)
    local unit = plate.unit
    if not unit then return end
    local nameText = plate.nameText

    if not UnitExists(unit) then return end

    local name = UnitName(unit)
    local ok = pcall(function()
        nameText:SetText(Helpers.TruncateUTF8(name, plate.npNameTruncate or 28))
    end)
    if not ok then
        nameText:SetText("")
    end

    local settings = NP.GetTypeSettings(plate) or {}
    local nameS = settings.name or {}
    if nameS.classColorPlayers ~= false and plate.npIsPlayer == true and plate.npClassToken then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[plate.npClassToken]
        if c then
            nameText:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
            return
        end
    end
    local nc = nameS.color or { 1, 1, 1 }
    nameText:SetTextColor(nc[1] or 1, nc[2] or 1, nc[3] or 1)
end

function NPHealth.UpdateLevel(plate)
    local text = plate.npLevelText
    if not text then return end
    local icon = plate.npClassIcon
    local unit = plate.unit
    if not unit then
        text:Hide()
        if icon then icon:Hide() end
        return
    end

    local okL, level = pcall(UnitEffectiveLevel or UnitLevel, unit)
    level = okL and NP.Plain(level, "number") or nil

    if not plate.npLevelEnabled then
        text:Hide()
    elseif level == nil then
        text:Hide()
    elseif level < 0 then
        text:SetText("??")
        text:SetTextColor(1, 0.1, 0.1)
        text:Show()
    else
        text:SetFormattedText("%.0f", level)
        local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
        if type(c) == "table" and NP.Plain(c.r, "number") then
            text:SetTextColor(c.r, c.g or 1, c.b or 1)
        else
            text:SetTextColor(1, 0.82, 0)
        end
        text:Show()
    end

    if icon and plate.npClassIconEnabled then
        local Classification = ns.Classification
        local okC, classification = pcall(UnitClassification, unit)
        local atlas, r, g, b
        if Classification then
            atlas, r, g, b = Classification.Resolve(
                okC and NP.Plain(classification, "string") or nil, level)
        end
        if atlas then
            local okA = pcall(icon.SetAtlas, icon, atlas, false)
            if okA then
                icon:SetVertexColor(r, g, b)
                icon:Show()
            else
                icon:Hide()
            end
        else
            icon:Hide()
        end
    elseif icon then
        icon:Hide()
    end
end

function NPHealth.UpdateNpcTitle(plate)
    local text = plate.npTitleText
    if not text then return end
    if not plate.npTitleEnabled or plate.npIsPlayer ~= false then
        text:Hide()
        return
    end
    local title = NP.Extras.GetNpcTitle(plate.unit)
    if title then
        text:SetText(title)
        text:Show()
    else
        text:Hide()
    end
end

function NPHealth.UpdateColor(plate, settings, context)
    local r, g, b = NP.Colors.Resolve(plate, settings, context)
    if r ~= plate.npLastR or g ~= plate.npLastG or b ~= plate.npLastB then
        plate.npLastR, plate.npLastG, plate.npLastB = r, g, b
        plate.healthBar:SetStatusBarColor(r, g, b)
    end
end
