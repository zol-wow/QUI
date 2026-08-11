local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local Helpers = ns.Helpers

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local GetDB = Helpers.CreateDBGetter("quiUnitFrames")

local GetCore = ns.Helpers.GetCore

local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local tostring = tostring
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local string_format = string.format
local math_floor = math.floor
local math_max = math.max

local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local GetTime = GetTime

local inInitSafeWindow = false

local QUI_UF = {}
ns.QUI_UnitFrames = QUI_UF

local ufUnitState, GetUFUnitState = Helpers.CreateStateTable()
function QUI_UF.GetFrameUnit(frame)
    if not frame then return nil end
    local state = ufUnitState[frame]
    return state and state.unit or nil
end
function QUI_UF.SetFrameUnit(frame, unit)
    if not frame then return end
    GetUFUnitState(frame).unit = unit
end

QUI_UF.frames = {}
QUI_UF.castbars = {}
QUI_UF.previewMode = {}
QUI_UF.auraPreviewMode = {}

local QUI_Castbar = ns.QUI_Castbar

local function ComputeBossExtent()
    local left, right, top, bottom
    for i = 1, 5 do
        local f = QUI_UF.frames["boss" .. i]
        if f and f:IsShown() then
            local fL, fR, fT, fB = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
            if fL and fR and fT and fB then
                left = left and math.min(left, fL) or fL
                right = right and math.max(right, fR) or fR
                top = top and math.max(top, fT) or fT
                bottom = bottom and math.min(bottom, fB) or fB
            end
            local cb = ns.QUI_Castbar and ns.QUI_Castbar.castbars and ns.QUI_Castbar.castbars["boss" .. i]
            if cb and cb:IsShown() then
                local cbL, cbR, cbT, cbB = cb:GetLeft(), cb:GetRight(), cb:GetTop(), cb:GetBottom()
                if cbL and cbR and cbT and cbB then
                    left = left and math.min(left, cbL) or cbL
                    right = right and math.max(right, cbR) or cbR
                    top = top and math.max(top, cbT) or cbT
                    bottom = bottom and math.min(bottom, cbB) or cbB
                end
            end
        end
    end
    return left, right, top, bottom
end

local function IsFrameOverridden(frame)
    local anchoring = ns.QUI_Anchoring
    return anchoring and anchoring.layoutOwnedFrames and anchoring.layoutOwnedFrames[frame]
end

local function GetActiveFrameOverrideSettings(frame)
    local overrideKey = IsFrameOverridden(frame)
    if not overrideKey then return nil end

    local profile = QUICore and QUICore.db and QUICore.db.profile
    local anchoringDB = profile and profile.frameAnchoring
    local settings = anchoringDB and anchoringDB[overrideKey]
    if type(settings) ~= "table" or settings.enabled == false then
        return nil
    end
    return settings
end

local function ResolveRefreshSize(frame, baseWidth, baseHeight)
    local width = baseWidth
    local height = baseHeight
    local overrideSettings = GetActiveFrameOverrideSettings(frame)
    if overrideSettings then
        if overrideSettings.autoWidth then
            local currentWidth = frame:GetWidth()
            if currentWidth and currentWidth > 0 then
                width = currentWidth
            end
        end
        if overrideSettings.autoHeight then
            local currentHeight = frame:GetHeight()
            if currentHeight and currentHeight > 0 then
                height = currentHeight
            end
        end
    end
    return width, height
end

local POWER_COLORS = {
    [0] = { 0, 0.50, 1 },
    [1] = { 1, 0, 0 },
    [2] = { 1, 0.5, 0.25 },
    [3] = { 1, 1, 0 },
    [6] = { 0, 0.82, 1 },
    [8] = { 0.3, 0.52, 0.9 },
    [11] = { 0, 0.5, 1 },
    [13] = { 0.4, 0, 0.8 },
}

local tocVersion = tonumber((select(4, GetBuildInfo()))) or 0

local function GetHealthPct(unit, usePredicted)
    if tocVersion >= 120000 and type(UnitHealthPercent) == "function"
       and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, pct = pcall(UnitHealthPercent, unit, usePredicted, CurveConstants.ScaleTo100)
        if ok then return pct end
    end
    if type(UnitHealthPercent) == "function" then
        local ok, pct = pcall(UnitHealthPercent, unit, usePredicted)
        if ok then return pct end
    end
    return nil
end

local function GetPowerPct(unit, powerType, usePredicted)
    if tocVersion >= 120000 and type(UnitPowerPercent) == "function" then
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted, CurveConstants.ScaleTo100)
        end
        if IsSecretValue(pct) then return pct end
        if not ok or pct == nil then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted)
        end
        if IsSecretValue(pct) then return pct end
        if ok and pct ~= nil then
            return pct
        end
    end
    local cur = UnitPower(unit, powerType)
    local max = UnitPowerMax(unit, powerType)
    local calcOk, result = pcall(function()
        if cur and max and max > 0 then
            return (cur / max) * 100
        end
        return nil
    end)
    if calcOk and result then
        return result
    end
    return nil
end

local function GetGeneralSettings()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        return QUICore.db.profile.general
    end
    return nil
end

local function GetUnitSettings(unit)
    local db = GetDB()
    return db and db[unit]
end

local VALID_BOSS_GROW_DIRECTION = {
    UP = true,
    DOWN = true,
    LEFT = true,
    RIGHT = true,
}

local function GetBossLayoutSettings(settings)
    if not settings then return "DOWN", 35, 35 end

    local direction = rawget(settings, "growDirection") or settings.growDirection or "DOWN"
    if not VALID_BOSS_GROW_DIRECTION[direction] then
        direction = "DOWN"
    end

    local legacySpacing = rawget(settings, "spacing")
    if legacySpacing == nil then
        legacySpacing = settings.spacing
    end
    legacySpacing = tonumber(legacySpacing) or 35

    local xSpacing = rawget(settings, "xSpacing")
    if xSpacing == nil then
        xSpacing = legacySpacing
    end
    xSpacing = tonumber(xSpacing) or legacySpacing

    local ySpacing = rawget(settings, "ySpacing")
    if ySpacing == nil then
        ySpacing = legacySpacing
    end
    ySpacing = tonumber(ySpacing) or legacySpacing

    return direction, xSpacing, ySpacing
end

local function AnchorBossFrameToPrevious(frame, previousFrame, direction, xSpacing, ySpacing)
    if not frame or not previousFrame then return end

    frame:ClearAllPoints()
    if direction == "UP" then
        frame:SetPoint("BOTTOM", previousFrame, "TOP", 0, ySpacing)
    elseif direction == "LEFT" then
        frame:SetPoint("RIGHT", previousFrame, "LEFT", -xSpacing, 0)
    elseif direction == "RIGHT" then
        frame:SetPoint("LEFT", previousFrame, "RIGHT", xSpacing, 0)
    else
        frame:SetPoint("TOP", previousFrame, "BOTTOM", 0, -ySpacing)
    end
end

local function GetNameSettings(settings)
    return settings and settings.name or settings
end

local function IsPlayerFrameEnabled(db)
    return db and db.player and db.player.enabled
end

local function IsStandalonePlayerCastbarActive(db)
    local playerDB = db and db.player
    if not playerDB or not playerDB.standaloneCastbar then
        return false
    end
    return not IsPlayerFrameEnabled(db)
end

local function EnsurePlayerCastbarSettings(db)
    if not db or not db.player then return nil end
    if not db.player.castbar then
        db.player.castbar = { enabled = true }
    elseif db.player.castbar.enabled == nil then
        db.player.castbar.enabled = true
    end
    return db.player.castbar
end

local function ApplyStandalonePlayerCastbarMode()
    local db = GetDB()
    if not db or not db.player then return false end

    local standaloneActive = IsStandalonePlayerCastbarActive(db)
    local castSettings = EnsurePlayerCastbarSettings(db)
    local castbarAllowed = castSettings and castSettings.enabled ~= false
    local hasPlayerFrame = QUI_UF.frames and QUI_UF.frames.player
    local castbar = QUI_UF.castbars and QUI_UF.castbars.player

    if standaloneActive and not hasPlayerFrame and castbarAllowed then
        if castbar and QUI_Castbar and QUI_Castbar.RefreshCastbar then
            QUI_Castbar:RefreshCastbar(castbar, "player", castSettings, nil)
        elseif QUI_Castbar and QUI_Castbar.CreateCastbar then
            QUI_UF.castbars.player = QUI_Castbar:CreateCastbar(nil, "player", "player")
        end
        QUI_UF:HideBlizzardCastbars()
        return true
    end

    if castbar and not hasPlayerFrame then
        if QUI_Castbar and QUI_Castbar.DestroyCastbar then
            QUI_Castbar.DestroyCastbar(castbar)
        end
        QUI_UF.castbars.player = nil
    end

    return false
end

local function ApplyExistingCastbarLiveSettings(unitKey)
    local castbar = QUI_UF.castbars and QUI_UF.castbars[unitKey]
    if not castbar or not QUI_Castbar or not QUI_Castbar.ApplyLiveCastbarSettings then
        return
    end

    local settings = GetUnitSettings(unitKey)
    local castSettings = settings and settings.castbar
    if not castSettings or castSettings.enabled == false then
        return
    end

    QUI_Castbar:ApplyLiveCastbarSettings(castbar, unitKey, castSettings)
end

local function IsTargetHealthDirectionInverted(unitKey, settings)
    return unitKey == "target" and settings and settings.invertHealthDirection == true
end

local function ApplyHealthFillDirection(frame, settings)
    if not frame or not frame.healthBar then return false end
    settings = settings or (frame.unitKey and GetUnitSettings(frame.unitKey))
    local reverseFill = IsTargetHealthDirectionInverted(frame.unitKey, settings)
    frame.healthBar:SetReverseFill(reverseFill)
    return reverseFill
end

local function CacheHealthBarExtents(frame, settings, frameWidth, frameHeight)
    if not frame then return end
    settings = settings or (frame.unitKey and GetUnitSettings(frame.unitKey))
    if not settings then return end

    local width = frameWidth
    local height = frameHeight
    if type(width) ~= "number" or type(height) ~= "number" then
        width = frame:GetWidth()
        height = frame:GetHeight()
    end

    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0
    local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
    local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0

    frame._healthBarExtentWidth = math_max((width or 0) - (borderSize * 2), 0)
    frame._healthBarExtentHeight = math_max((height or 0) - (borderSize * 2) - powerHeight - separatorHeight, 0)
end

local function GetCachedHealthBarExtents(frame, settings)
    if not frame then return nil, nil end

    local width = frame._healthBarExtentWidth
    local height = frame._healthBarExtentHeight

    if (not width or width <= 0 or not height or height <= 0) and not InCombatLockdown() then
        CacheHealthBarExtents(frame, settings)
        width = frame._healthBarExtentWidth
        height = frame._healthBarExtentHeight
    end

    if not width or width <= 0 or not height or height <= 0 then
        return nil, nil
    end

    return width, height
end

local function Scale(x, frame)
    if QUICore and QUICore.Scale then
        return QUICore:Scale(x, frame)
    end
    return x
end

local function ShowUnitTooltip(frame)
    local ufdb = GetDB()
    local general = ufdb and ufdb.general

    if not general or general.showTooltips == false then
        return
    end

    local unit = QUI_UF.GetFrameUnit(frame) or (frame.GetAttribute and frame:GetAttribute("unit"))
    if not unit then
        local parent = frame:GetParent()
        if parent then
            unit = parent.unit or (parent.GetAttribute and parent:GetAttribute("unit"))
        end
    end

    if not unit or not UnitExists(unit) then return end

    GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

local function HideUnitTooltip()
    GameTooltip:Hide()
end

local GetFontPath = Helpers.GetGeneralFont

local GetFontOutline = Helpers.GetGeneralFontOutline

local function GetTexturePath(textureName)
    local name = textureName
    if not name or name == "" then
        local general = GetGeneralSettings()
        name = general and general.texture or "Quazii"
    end
    return LSM:Fetch("statusbar", name) or "Interface\\Buttons\\WHITE8x8"
end

local function GetAbsorbTexturePath(textureName)
    local name = textureName
    if not name or name == "" then
        name = "QUI Stripes"
    end
    return LSM:Fetch("statusbar", name) or (Helpers.AssetPath .. "absorb_stripe")
end

local _predictionVisCurve
local function GetPredictionVisibilityCurve()
    if _predictionVisCurve then return _predictionVisCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateCurve
       or not Enum or not Enum.LuaCurveType then
        return nil
    end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0.0, 1)
    curve:AddPoint(1.0, 0)
    _predictionVisCurve = curve
    return curve
end

local GetUnitClassColor = Helpers.GetUnitClassColor

local TEXT_ANCHOR_MAP = {
    TOPLEFT     = { point = "TOPLEFT",     justify = "LEFT" },
    TOP         = { point = "TOP",         justify = "CENTER" },
    TOPRIGHT    = { point = "TOPRIGHT",    justify = "RIGHT" },
    LEFT        = { point = "LEFT",        justify = "LEFT" },
    CENTER      = { point = "CENTER",      justify = "CENTER" },
    RIGHT       = { point = "RIGHT",       justify = "RIGHT" },
    BOTTOMLEFT  = { point = "BOTTOMLEFT",  justify = "LEFT" },
    BOTTOM      = { point = "BOTTOM",      justify = "CENTER" },
    BOTTOMRIGHT = { point = "BOTTOMRIGHT", justify = "RIGHT" },
}

local function GetTextAnchorInfo(anchor)
    return TEXT_ANCHOR_MAP[anchor] or TEXT_ANCHOR_MAP.LEFT
end

local function ResolveTextFont(fontName, fallbackPath)
    if type(fontName) == "string" and fontName ~= "" and LSM and LSM.Fetch then
        local path = LSM:Fetch("font", fontName, true)
        if path then
            return path
        end
    end
    return fallbackPath or GetFontPath()
end

local function FormatUnitLevelText(unit)
    local ok, text = pcall(function()
        local level = UnitLevel(unit)
        if not level then return "" end
        if level < 0 then return "??" end
        if level == 0 then return "" end
        return tostring(level)
    end)
    return ok and text or ""
end

local TruncateName = Helpers.TruncateUTF8

QUI_UF.TruncateName = TruncateName

local function FormatHealthText(hp, hpPct, style, divider, maxHp, hidePercentSymbol)
    style = style or "both"
    divider = divider or " | "
    local pctSuffix = hidePercentSymbol and "" or "%"

    local hpSecret = IsSecretValue(hp)
    local pctSecret = IsSecretValue(hpPct)
    local maxSecret = IsSecretValue(maxHp)

    local success, hpStr = pcall(function()
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        return abbr and abbr(hp) or tostring(hp)
    end)
    if not success then hpStr = "" end

    if style == "percent" then
        if pctSecret or hpPct then
            local success, result = pcall(function() return string_format("%d%s", hpPct, pctSuffix) end)
            return success and result or ""
        end
        return ""
    elseif style == "absolute" then
        return hpStr or ""
    elseif style == "both" then
        if pctSecret or hpPct then
            local success, result = pcall(function() return string_format("%s%s%d%s", hpStr or "", divider, hpPct, pctSuffix) end)
            return success and result or hpStr or ""
        end
        return hpStr or ""
    elseif style == "both_reverse" then
        if pctSecret or hpPct then
            local success, result = pcall(function() return string_format("%d%s%s%s", hpPct, pctSuffix, divider, hpStr or "") end)
            return success and result or hpStr or ""
        end
        return hpStr or ""
    elseif style == "missing_percent" then
        if pctSecret or hpPct then
            local success, missing = pcall(function() return 100 - hpPct end)
            if not success then return "" end
            if missing > 0 then
                return string_format("-%d%s", missing, pctSuffix)
            end
            return "0" .. pctSuffix
        end
        return ""
    elseif style == "missing_value" then
        if (hpSecret or hp) and (maxSecret or maxHp) then
            local success, missing = pcall(function() return maxHp - hp end)
            if not success then return "" end
            if missing > 0 then
                local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
                local missingStr = abbr and abbr(missing) or tostring(missing)
                return "-" .. missingStr
            end
            return "0"
        end
        return ""
    end

    return hpStr or ""
end

local function FormatPowerText(power, powerPct, style, divider, hidePercentSymbol)
    style = style or "percent"
    divider = divider or " | "
    local pctSuffix = hidePercentSymbol and "" or "%"

    local powerStr = ""
    pcall(function()
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        powerStr = abbr and abbr(power) or tostring(power)
    end)

    local result = ""

    if style == "percent" then
        local fmtOk = pcall(function()
            if powerPct then
                result = string_format("%d%s", powerPct, pctSuffix)
            end
        end)
        if not fmtOk then result = "" end
    elseif style == "current" then
        result = powerStr or ""
    elseif style == "both" then
        local fmtOk = pcall(function()
            if powerPct then
                result = string_format("%s%s%d%s", powerStr or "", divider, powerPct, pctSuffix)
            else
                result = powerStr or ""
            end
        end)
        if not fmtOk then result = "" end
    else
        result = powerStr or ""
    end

    return result
end

local function GetHealthBarColor(unit, settings)
    if not UnitExists(unit) then
        return 0.5, 0.5, 0.5, 1
    end

    local general = GetGeneralSettings()

    local useClassColor = false
    if settings and settings.useClassColor ~= nil then
        useClassColor = settings.useClassColor
    else
        useClassColor = general and general.defaultUseClassColor
    end

    if useClassColor and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        -- @secret-policy: collapse-only — fall through to hostility/default color
        if issecretvalue and issecretvalue(class) then class = nil end
        if type(class) == "string" then
            local color = RAID_CLASS_COLORS[class]
            if color then
                return color.r, color.g, color.b, 1
            end
        end
    end

    if settings and settings.useHostilityColor then
        local reaction = Helpers.SafeToNumber(UnitReaction(unit, "player"), nil)
        if reaction and reaction > 0 then
            if reaction >= 5 then
                local c = general and general.hostilityColorFriendly or { 0.2, 0.8, 0.2, 1 }
                return c[1], c[2], c[3], c[4] or 1
            elseif reaction == 4 then
                local c = general and general.hostilityColorNeutral or { 1, 1, 0.2, 1 }
                return c[1], c[2], c[3], c[4] or 1
            else
                local c = general and general.hostilityColorHostile or { 0.8, 0.2, 0.2, 1 }
                return c[1], c[2], c[3], c[4] or 1
            end
        end
    end

    if settings and settings.customHealthColor then
        local c = settings.customHealthColor
        return c[1], c[2], c[3], c[4] or 1
    end

    local c = general and general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
    return c[1], c[2], c[3], c[4] or 1
end

local function GetUnitPowerColor(unit)
    local powerType = UnitPowerType(unit)
    local color = POWER_COLORS[powerType]
    if color then
        return color[1], color[2], color[3], 1
    end
    return 0.5, 0.5, 0.5, 1
end

local function UpdateHealth(frame)
    if not frame or not frame.healthBar then return end
    local unit = QUI_UF.GetFrameUnit(frame)
    if not unit then return end
    local settings = GetUnitSettings(frame.unitKey)

    if not UnitExists(unit) then
        return
    end

    ApplyHealthFillDirection(frame, settings)

    local hp = UnitHealth(unit)
    local maxHP = UnitHealthMax(unit)

    frame.healthBar:SetMinMaxValues(0, maxHP)
    frame.healthBar:SetValue(hp)

    if frame.healthText then
        if settings and settings.showHealth == false then
            frame.healthText:Hide()
        else
            local displayStyle = settings and settings.healthDisplayStyle
            if not displayStyle then
                local showAbsolute = settings and settings.showHealthAbsolute
                local showPercent = settings and settings.showHealthPercent
                if showPercent == nil then showPercent = true end

                if showAbsolute and showPercent then
                    displayStyle = "both"
                elseif showAbsolute then
                    displayStyle = "absolute"
                elseif showPercent then
                    displayStyle = "percent"
                else
                    displayStyle = "percent"
                end
            end

            local divider = settings and settings.healthDivider or " | "
            local hidePercentSymbol = settings and settings.hideHealthPercentSymbol == true

            if IsSecretValue(hp) or hp then
                local hpPct = GetHealthPct(unit, true)
                local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
                local pctFmt = hidePercentSymbol and "%.0f" or "%.0f%%"
                local ok
                if displayStyle == "percent" then
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", pctFmt, hpPct)
                elseif displayStyle == "absolute" then
                    if abbr then
                        ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetText", abbr(hp))
                    else
                        ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", "%s", hp)
                    end
                elseif displayStyle == "both" then
                    local bothFmt = hidePercentSymbol and ("%s" .. divider .. "%.0f") or ("%s" .. divider .. "%.0f%%")
                    if abbr then
                        ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", bothFmt, abbr(hp), hpPct)
                    else
                        ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", bothFmt, hp, hpPct)
                    end
                elseif displayStyle == "both_reverse" then
                    local revFmt = hidePercentSymbol and ("%.0f" .. divider .. "%s") or ("%.0f%%" .. divider .. "%s")
                    if abbr then
                        ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", revFmt, hpPct, abbr(hp))
                    else
                        ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetFormattedText", revFmt, hpPct, hp)
                    end
                else
                    local healthStr = FormatHealthText(hp, hpPct, displayStyle, divider, maxHP, hidePercentSymbol)
                    ok = ns.SafeCallMethod("sink-forward", frame.healthText, "SetText", healthStr)
                end
                if not ok then
                    frame.healthText:SetText("")
                end
                frame.healthText:Show()
            else
                frame.healthText:SetText("")
            end
        end
    end

    local general = GetGeneralSettings()

    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        local r, g, b, a = GetHealthBarColor(unit, settings)
        frame.healthBar:SetStatusBarColor(r, g, b, a)
    end
end

local function ApplyAbsorbVisAlphas(frame, clampedBool, visAlpha)
    frame.attachedVisHelper:SetAlphaFromBoolean(clampedBool, 0, visAlpha)
    frame.overflowVisHelper:SetAlphaFromBoolean(clampedBool, visAlpha, 0)
end

local function UpdateAbsorbs(frame)
    if not frame or not frame.healthBar then return end
    if not frame.absorbBar then return end

    local unit = QUI_UF.GetFrameUnit(frame)
    if not unit then return end
    local settings = GetUnitSettings(frame.unitKey)
    local healthReversed = ApplyHealthFillDirection(frame, settings)

    if not settings or not settings.absorbs or settings.absorbs.enabled == false then
        frame.absorbBar:Hide()
        if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
        if frame.healAbsorbBar then frame.healAbsorbBar:Hide() end
        return
    end

    if not UnitExists(unit) then
        frame.absorbBar:Hide()
        if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
        if frame.healAbsorbBar then frame.healAbsorbBar:Hide() end
        return
    end

    local maxHealth = UnitHealthMax(unit)
    local absorbAmount = UnitGetTotalAbsorbs(unit)
    local healthTexture = frame.healthBar:GetStatusBarTexture()

    local absorbSettings = settings.absorbs or {}
    local c = absorbSettings.color or { 1, 1, 1 }
    local a = absorbSettings.opacity or 0.7

    do
        local absorbTexturePath = GetAbsorbTexturePath(absorbSettings.texture)
        if not frame.absorbOverflowBar then
            frame.absorbOverflowBar = CreateFrame("StatusBar", nil, frame.healthBar)
            frame.absorbOverflowBar:SetStatusBarTexture(absorbTexturePath)
            local overflowBarTex = frame.absorbOverflowBar:GetStatusBarTexture()
            if overflowBarTex then
                overflowBarTex:SetHorizTile(false)
                overflowBarTex:SetVertTile(false)
                overflowBarTex:SetTexCoord(0, 1, 0, 1)
            end
            frame.absorbOverflowBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
            frame.absorbOverflowBar:EnableMouse(false)
        else
            frame.absorbOverflowBar:SetStatusBarTexture(absorbTexturePath)
        end

        if not frame.attachedVisHelper then
            frame.attachedVisHelper = frame.absorbBar:CreateTexture(nil, "BACKGROUND")
            frame.attachedVisHelper:SetSize(1, 1)
            frame.attachedVisHelper:SetColorTexture(0, 0, 0, 0)
        end
        if not frame.overflowVisHelper then
            frame.overflowVisHelper = frame.absorbOverflowBar:CreateTexture(nil, "BACKGROUND")
            frame.overflowVisHelper:SetSize(1, 1)
            frame.overflowVisHelper:SetColorTexture(0, 0, 0, 0)
        end

        local clampedAbsorbs = absorbAmount

        frame.attachedVisHelper:SetAlpha(1)
        frame.overflowVisHelper:SetAlpha(0)

        if CreateUnitHealPredictionCalculator and unit then
            if not frame.absorbCalculator then
                frame.absorbCalculator = CreateUnitHealPredictionCalculator()
            end
            local calc = frame.absorbCalculator

            ns.SafeCallMethod("sink-forward", calc, "SetDamageAbsorbClampMode", 1)

            local maximumHealthMode = Enum and Enum.UnitMaximumHealthMode
            if maximumHealthMode and calc.SetMaximumHealthMode then
                ns.SafeCallMethod("sink-forward", calc, "SetMaximumHealthMode", maximumHealthMode.Default or 0)
            end

            UnitGetDetailedHealPrediction(unit, nil, calc)

            local success, clampedAmount, clampedBool = ns.SafeCallMethod("sink-forward", calc, "GetDamageAbsorbs")

            if success then
                clampedAbsorbs = clampedAmount

                if maximumHealthMode and maximumHealthMode.WithAbsorbs and calc.SetMaximumHealthMode then
                    ns.SafeCallMethod("sink-forward", calc, "SetMaximumHealthMode", maximumHealthMode.WithAbsorbs)
                end

                local visCurve = GetPredictionVisibilityCurve()
                local visAlpha = 1
                if visCurve then
                    local visOK, visResult = ns.SafeCallMethod("sink-forward", calc, "EvaluateCurrentHealthPercent", visCurve)
                    if visOK then visAlpha = visResult end
                end

                ns.SafeCall("sink-forward", ApplyAbsorbVisAlphas, frame, clampedBool, visAlpha)
            end
        end

        local healthBarWidth, healthBarHeight = GetCachedHealthBarExtents(frame, settings)
        if not healthBarWidth or not healthBarHeight then
            frame.absorbBar:Hide()
            if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
            return
        end

        frame.absorbBar:ClearAllPoints()
        if healthReversed then
            frame.absorbBar:SetPoint("RIGHT", healthTexture, "LEFT", 0, 0)
        else
            frame.absorbBar:SetPoint("LEFT", healthTexture, "RIGHT", 0, 0)
        end
        frame.absorbBar:SetHeight(healthBarHeight)
        frame.absorbBar:SetWidth(healthBarWidth)
        frame.absorbBar:SetReverseFill(healthReversed)
        frame.absorbBar:SetMinMaxValues(0, maxHealth)
        frame.absorbBar:SetValue(clampedAbsorbs)
        frame.absorbBar:SetStatusBarTexture(absorbTexturePath)
        frame.absorbBar:SetStatusBarColor(c[1], c[2], c[3], a)
        frame.absorbBar:SetAlpha(frame.attachedVisHelper:GetAlpha())
        frame.absorbBar:Show()

        frame.absorbOverflowBar:ClearAllPoints()
        frame.absorbOverflowBar:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
        frame.absorbOverflowBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
        frame.absorbOverflowBar:SetReverseFill(not healthReversed)
        frame.absorbOverflowBar:SetMinMaxValues(0, maxHealth)
        frame.absorbOverflowBar:SetValue(absorbAmount)
        frame.absorbOverflowBar:SetStatusBarColor(c[1], c[2], c[3], a)
        frame.absorbOverflowBar:SetAlpha(frame.overflowVisHelper:GetAlpha())
        frame.absorbOverflowBar:Show()
    end

    if frame.healAbsorbBar then
        local healAbsorbAmount = UnitGetTotalHealAbsorbs(unit)
        frame.healAbsorbBar:ClearAllPoints()
        frame.healAbsorbBar:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
        frame.healAbsorbBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
        frame.healAbsorbBar:SetReverseFill(false)
        frame.healAbsorbBar:SetMinMaxValues(0, maxHealth)
        frame.healAbsorbBar:SetValue(healAbsorbAmount)

        frame.healAbsorbBar:Show()
    end
end

local function UpdateHealPrediction(frame)
    if not frame or not frame.healthBar or not frame.healPredictionBar then return end

    local unit = QUI_UF.GetFrameUnit(frame)
    if not unit then return end
    local settings = GetUnitSettings(frame.unitKey)
    local predictionSettings = settings and settings.healPrediction
    local healthReversed = ApplyHealthFillDirection(frame, settings)

    if not predictionSettings or predictionSettings.enabled == false then
        frame.healPredictionBar:Hide()
        return
    end

    if not UnitExists(unit) then
        frame.healPredictionBar:Hide()
        return
    end

    local maxHealth = UnitHealthMax(unit)
    local incomingHeals

    if CreateUnitHealPredictionCalculator then
        if not frame.healPredictionCalculator then
            frame.healPredictionCalculator = CreateUnitHealPredictionCalculator()
            local calc = frame.healPredictionCalculator
            if calc and calc.SetIncomingHealClampMode then
                local clampMode = 1
                if Enum and Enum.UnitIncomingHealClampMode and Enum.UnitIncomingHealClampMode.MissingHealth then
                    clampMode = Enum.UnitIncomingHealClampMode.MissingHealth
                end
                ns.SafeCallMethod("sink-forward", calc, "SetIncomingHealClampMode", clampMode)
            end
            ns.SafeCallMethodIfPresent("sink-forward", calc, "SetIncomingHealOverflowPercent", 1.0)
        end

        local calc = frame.healPredictionCalculator
        if calc and UnitGetDetailedHealPrediction then
            pcall(UnitGetDetailedHealPrediction, unit, nil, calc)
            local results = { pcall(function() return calc:GetIncomingHeals() end) }
            if results[1] then
                incomingHeals = results[2]
            end
        end
    end

    if not IsSecretValue(incomingHeals) then
        if not incomingHeals then
            incomingHeals = UnitGetIncomingHeals(unit)
        end
    end

    if not IsSecretValue(incomingHeals) then
        if not incomingHeals then
            frame.healPredictionBar:Hide()
            return
        end
    end

    local healthTexture = frame.healthBar:GetStatusBarTexture()
    local healthBarWidth, healthBarHeight = GetCachedHealthBarExtents(frame, settings)
    if not healthBarWidth or not healthBarHeight then
        frame.healPredictionBar:Hide()
        return
    end
    frame.healPredictionBar:ClearAllPoints()
    if healthReversed then
        frame.healPredictionBar:SetPoint("RIGHT", healthTexture, "LEFT", 0, 0)
    else
        frame.healPredictionBar:SetPoint("LEFT", healthTexture, "RIGHT", 0, 0)
    end
    frame.healPredictionBar:SetHeight(healthBarHeight)
    frame.healPredictionBar:SetWidth(healthBarWidth)
    frame.healPredictionBar:SetReverseFill(healthReversed)
    frame.healPredictionBar:SetMinMaxValues(0, maxHealth)
    frame.healPredictionBar:SetValue(incomingHeals)
    frame.healPredictionBar:SetStatusBarTexture(GetTexturePath(settings.texture))

    local c = predictionSettings.color or { 0.2, 1, 0.2 }
    local a = predictionSettings.opacity or 0.5
    frame.healPredictionBar:SetStatusBarColor(c[1] or 0.2, c[2] or 1, c[3] or 0.2, a)

    local visCurve = GetPredictionVisibilityCurve()
    if visCurve and frame.healPredictionCalculator
       and frame.healPredictionCalculator.EvaluateCurrentHealthPercent then
        local visOK, visAlpha = pcall(function()
            return frame.healPredictionCalculator:EvaluateCurrentHealthPercent(visCurve)
        end)
        if visOK then
            frame.healPredictionBar:SetAlpha(visAlpha)
        end
    end

    frame.healPredictionBar:Show()
end

local function UpdatePower(frame)
    if not frame or not frame.powerBar then return end
    local unit = QUI_UF.GetFrameUnit(frame)
    if not unit then return end

    if not UnitExists(unit) then return end

    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.showPowerBar then
        frame.powerBar:Hide()
        return
    end

    local p = UnitPower(unit)
    local pMax = UnitPowerMax(unit)

    frame.powerBar:SetMinMaxValues(0, pMax)
    frame.powerBar:SetValue(p)
    frame.powerBar:Show()

    if settings.powerBarUsePowerColor ~= false then
        local r, g, b = GetUnitPowerColor(unit)
        frame.powerBar:SetStatusBarColor(r, g, b, 1)
    else
        local c = settings.powerBarColor or { 0, 0.5, 1, 1 }
        frame.powerBar:SetStatusBarColor(c[1], c[2], c[3], 1)
    end
end

local function UpdatePowerText(frame)
    if not frame or not frame.powerText then return end

    local unit = QUI_UF.GetFrameUnit(frame)
    if not unit then return end
    local settings = GetUnitSettings(frame.unitKey)

    if not settings or not settings.showPowerText then
        frame.powerText:Hide()
        return
    end

    if not UnitExists(unit) then
        frame.powerText:Hide()
        return
    end

    local powerPct = GetPowerPct(unit)

    local power = UnitPower(unit)

    local style = settings.powerTextFormat or "percent"
    local divider = settings.healthDivider or " | "
    local hidePercentSymbol = settings.hidePowerPercentSymbol == true
    local powerStr = FormatPowerText(power, powerPct, style, divider, hidePercentSymbol)

    if powerStr then
        local setOk = pcall(function()
            frame.powerText:SetText(powerStr)
        end)

        if setOk then
            local general = GetGeneralSettings()
            if general and general.masterColorPowerText then
                local r, g, b = GetUnitClassColor(unit)
                frame.powerText:SetTextColor(r, g, b, 1)
            elseif settings.powerTextUsePowerColor then
                local r, g, b = GetUnitPowerColor(unit)
                frame.powerText:SetTextColor(r, g, b, 1)
            elseif settings.powerTextUseClassColor then
                local r, g, b = GetUnitClassColor(unit)
                frame.powerText:SetTextColor(r, g, b, 1)
            elseif settings.powerTextColor then
                local c = settings.powerTextColor
                frame.powerText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            else
                frame.powerText:SetTextColor(1, 1, 1, 1)
            end
            frame.powerText:Show()
        else
            frame.powerText:Hide()
        end
    else
        frame.powerText:Hide()
    end
end

local function UpdateIndicators(frame)
    if not frame or frame.unitKey ~= "player" then return end
    local settings = GetUnitSettings("player")
    if not settings or not settings.indicators then return end

    local indSettings = settings.indicators

    if frame.restedIndicator then
        local rested = indSettings.rested
        if rested and rested.enabled and IsResting() then
            frame.restedIndicator:Show()
        else
            frame.restedIndicator:Hide()
        end
    end

    if frame.combatIndicator then
        local combat = indSettings.combat
        if combat and combat.enabled and UnitAffectingCombat(QUI_UF.GetFrameUnit(frame) or "player") then
            frame.combatIndicator:Show()
        else
            frame.combatIndicator:Hide()
        end
    end
end

local function UpdateStance(frame)
    if not frame or frame.unitKey ~= "player" then return end
    if not frame.stanceText then return end

    local settings = GetUnitSettings("player")
    if not settings or not settings.indicators or not settings.indicators.stance then
        frame.stanceText:Hide()
        if frame.stanceIcon then frame.stanceIcon:Hide() end
        return
    end

    local stanceSettings = settings.indicators.stance
    if not stanceSettings.enabled then
        frame.stanceText:Hide()
        if frame.stanceIcon then frame.stanceIcon:Hide() end
        return
    end

    local general = GetGeneralSettings()

    local fontPath = GetFontPath()
    local fontOutline = general and general.fontOutline or "OUTLINE"
    local fontSize = stanceSettings.fontSize or 12
    CJKFont(frame.stanceText, fontPath, fontSize, fontOutline)

    local anchorInfo = GetTextAnchorInfo(stanceSettings.anchor or "BOTTOM")
    local offsetX = stanceSettings.offsetX or 0
    local offsetY = stanceSettings.offsetY or -2

    frame.stanceText:ClearAllPoints()
    frame.stanceText:SetPoint(anchorInfo.point, frame, anchorInfo.point, offsetX, offsetY)
    frame.stanceText:SetJustifyH(anchorInfo.justify)

    local formIndex = GetShapeshiftForm()
    local formName = nil
    local formIcon = nil

    if formIndex and formIndex > 0 then
        local icon, active, castable, spellID = GetShapeshiftFormInfo(formIndex)
        if spellID then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo then
                formName = spellInfo.name
            end
        end
        formIcon = icon
    end

    if not formName or formName == "" then
        frame.stanceText:Hide()
        if frame.stanceIcon then frame.stanceIcon:Hide() end
        return
    end

    frame.stanceText:SetText(formName)

    if stanceSettings.useClassColor then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — secret class keeps the current stance text color
        if issecretvalue and issecretvalue(class) then class = nil end
        if class then
            local color = RAID_CLASS_COLORS[class]
            if color then
                frame.stanceText:SetTextColor(color.r, color.g, color.b, 1)
            else
                frame.stanceText:SetTextColor(1, 1, 1, 1)
            end
        end
    else
        local c = stanceSettings.customColor or { 1, 1, 1, 1 }
        frame.stanceText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    frame.stanceText:Show()

    if frame.stanceIcon then
        local iconSize = stanceSettings.iconSize or 14
        local iconOffsetX = stanceSettings.iconOffsetX or -2
        frame.stanceIcon:SetSize(iconSize, iconSize)
        frame.stanceIcon:ClearAllPoints()
        frame.stanceIcon:SetPoint("RIGHT", frame.stanceText, "LEFT", iconOffsetX, 0)

        if stanceSettings.showIcon and formIcon then
            frame.stanceIcon:SetTexture(formIcon)
            frame.stanceIcon:Show()
        else
            frame.stanceIcon:Hide()
        end
    end
end

local function UpdateTargetMarker(frame)
    if not frame or not QUI_UF.GetFrameUnit(frame) or not frame.targetMarker then return end
    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.targetMarker or not settings.targetMarker.enabled then
        frame.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(QUI_UF.GetFrameUnit(frame))
    if not IsSecretValue(index) and index then
        SetRaidTargetIconTexture(frame.targetMarker, index)
        frame.targetMarker:Show()
    else
        frame.targetMarker:Hide()
    end
end

local function UpdateLeaderIcon(frame)
    if not frame or not QUI_UF.GetFrameUnit(frame) or not frame.leaderIcon then return end
    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.leaderIcon or not settings.leaderIcon.enabled then
        frame.leaderIcon:Hide()
        return
    end

    if not IsInGroup() then
        frame.leaderIcon:Hide()
        return
    end

    local unit = QUI_UF.GetFrameUnit(frame)
    local isLeader = UnitIsGroupLeader(unit)
    if issecretvalue(isLeader) then isLeader = false end
    local isAssist = false
    if IsInRaid() then
        isAssist = UnitIsGroupAssistant(unit)
        if issecretvalue(isAssist) then isAssist = false end
    end
    if isLeader then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:SetAlpha(1)
        frame.leaderIcon:Show()
    elseif isAssist then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:SetAlpha(0.6)
        frame.leaderIcon:Show()
    else
        frame.leaderIcon:Hide()
        frame.leaderIcon:SetAlpha(1)
    end
end

local function UpdateClassificationIcon(frame)
    if not frame or not QUI_UF.GetFrameUnit(frame) or not frame.classificationIcon then return end
    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.classificationIcon or not settings.classificationIcon.enabled then
        if frame.classificationIcon then frame.classificationIcon:Hide() end
        return
    end

    if not UnitExists(QUI_UF.GetFrameUnit(frame)) then
        frame.classificationIcon:Hide()
        return
    end

    local Classification = ns.Classification
    if not Classification then
        frame.classificationIcon:Hide()
        return
    end

    local unit = QUI_UF.GetFrameUnit(frame)
    local atlas, r, g, b = Classification.Resolve(UnitClassification(unit), UnitLevel(unit))

    if atlas then
        frame.classificationIcon:SetAtlas(atlas)
        frame.classificationIcon:SetVertexColor(r, g, b)
        frame.classificationIcon:Show()
    else
        frame.classificationIcon:Hide()
    end
end

local function UpdateHealthTextColor(frame)
    if not frame or not frame.healthText or not QUI_UF.GetFrameUnit(frame) then return end

    local settings = GetUnitSettings(frame.unitKey)
    if not settings then return end

    local general = GetGeneralSettings()

    if general and general.masterColorHealthText then
        local r, g, b = GetUnitClassColor(QUI_UF.GetFrameUnit(frame))
        frame.healthText:SetTextColor(r, g, b, 1)
    elseif settings.healthTextUseClassColor then
        local r, g, b = GetUnitClassColor(QUI_UF.GetFrameUnit(frame))
        frame.healthText:SetTextColor(r, g, b, 1)
    elseif settings.healthTextColor then
        local c = settings.healthTextColor
        frame.healthText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    elseif general and general.classColorText then
        local r, g, b = GetUnitClassColor(QUI_UF.GetFrameUnit(frame))
        frame.healthText:SetTextColor(r, g, b, 1)
    else
        frame.healthText:SetTextColor(1, 1, 1, 1)
    end
end

local function ClearToTDisplay(frame)
    if frame.nameText then frame.nameText:SetText("") end
    if frame.levelText then frame.levelText:SetText(""); frame.levelText:Hide() end
    if frame.healthText then frame.healthText:SetText("") end
    if frame.powerText then frame.powerText:Hide() end
    if frame.healthBar then frame.healthBar:SetValue(0) end
end

local function UpdateName(frame)
    if not frame or not frame.nameText then return end
    local unit = QUI_UF.GetFrameUnit(frame)
    if not unit then return end

    local settings = GetUnitSettings(frame.unitKey)
    local nameSettings = GetNameSettings(settings)
    if not settings or not nameSettings.showName then
        frame.nameText:Hide()
        return
    end

    local name = UnitName(unit)
    if not IsSecretValue(name) and not name then name = "" end

    local maxLen = nameSettings.maxNameLength
    if maxLen and maxLen > 0 then
        name = TruncateName(name, maxLen)
    end

    if (frame.unitKey == "target" or frame.unitKey == "boss") and settings.showInlineToT then
        local totUnit = (frame.unitKey == "boss") and (unit .. "target") or "targettarget"
        if UnitExists(totUnit) then
            local totName = UnitName(totUnit)
            if not IsSecretValue(totName) and not totName then totName = "" end
            local totCharLimit = settings.totNameCharLimit
            if totCharLimit and totCharLimit > 0 then
                totName = TruncateName(totName, totCharLimit)
            elseif maxLen and maxLen > 0 then
                totName = TruncateName(totName, maxLen)
            end
            local separator = settings.totSeparator or " >> "

            local dividerColorHex
            if settings.totDividerUseClassColor then
                local dR, dG, dB = GetUnitClassColor(totUnit)
                dividerColorHex = string_format("|cff%02x%02x%02x", dR * 255, dG * 255, dB * 255)
            elseif settings.totDividerColor then
                local c = settings.totDividerColor
                dividerColorHex = string_format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
            else
                dividerColorHex = "|cFFFFFFFF"
            end

            if not IsSecretValue(name) and not IsSecretValue(totName) then
                local general = GetGeneralSettings()
                if general and general.masterColorToTText then
                    local totR, totG, totB = GetUnitClassColor(totUnit)
                    local totColorHex = string_format("|cff%02x%02x%02x", totR * 255, totG * 255, totB * 255)
                    name = name .. dividerColorHex .. separator .. "|r" .. totColorHex .. totName .. "|r"
                elseif settings.totUseClassColor then
                    local totR, totG, totB = GetUnitClassColor(totUnit)
                    local totColorHex = string_format("|cff%02x%02x%02x", totR * 255, totG * 255, totB * 255)
                    name = name .. dividerColorHex .. separator .. "|r" .. totColorHex .. totName .. "|r"
                else
                    name = name .. dividerColorHex .. separator .. "|r" .. totName
                end
            end
        end
    end

    frame.nameText:SetText(name)

    local general = GetGeneralSettings()
    if general and general.masterColorNameText then
        local r, g, b = GetUnitClassColor(unit)
        frame.nameText:SetTextColor(r, g, b, 1)
    elseif nameSettings.nameTextUseClassColor then
        local r, g, b = GetUnitClassColor(unit)
        frame.nameText:SetTextColor(r, g, b, 1)
    elseif nameSettings.nameTextColor then
        local c = nameSettings.nameTextColor
        frame.nameText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    elseif general and general.classColorText then
        local r, g, b = GetUnitClassColor(unit)
        frame.nameText:SetTextColor(r, g, b, 1)
    else
        frame.nameText:SetTextColor(1, 1, 1, 1)
    end

    frame.nameText:Show()
end

local function UpdateLevelText(frame)
    if not frame or not QUI_UF.GetFrameUnit(frame) or not frame.levelText then return end

    local settings = GetUnitSettings(frame.unitKey)
    if not settings or settings.showLevel ~= true then
        frame.levelText:Hide()
        return
    end

    if not UnitExists(QUI_UF.GetFrameUnit(frame)) then
        frame.levelText:SetText("")
        frame.levelText:Hide()
        return
    end

    local text = FormatUnitLevelText(QUI_UF.GetFrameUnit(frame))
    if text == "" then
        frame.levelText:SetText("")
        frame.levelText:Hide()
        return
    end

    frame.levelText:SetText(text)
    local c = settings.levelTextColor or { 1, 1, 1, 1 }
    frame.levelText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    frame.levelText:Show()
end

local function UpdateFrame(frame)
    if not frame then return end

    if frame.healthBar then
        local general = GetGeneralSettings()
        local settings = GetUnitSettings(frame.unitKey)
        ApplyHealthFillDirection(frame, settings)

        if general and general.darkMode then
            local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
            frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        else
            local r, g, b, a = GetHealthBarColor(QUI_UF.GetFrameUnit(frame), settings)
            frame.healthBar:SetStatusBarColor(r, g, b, a)
        end
    end

    UpdateHealth(frame)
    UpdateAbsorbs(frame)
    UpdateHealPrediction(frame)
    UpdatePower(frame)
    UpdatePowerText(frame)
    UpdateName(frame)
    UpdateLevelText(frame)
    UpdateHealthTextColor(frame)
    UpdateIndicators(frame)
    UpdateStance(frame)
    UpdateTargetMarker(frame)
    UpdateLeaderIcon(frame)
    UpdateClassificationIcon(frame)

    if frame.portraitTexture and frame.portrait and frame.portrait:IsShown() then
        if UnitExists(QUI_UF.GetFrameUnit(frame)) then
            SetPortraitTexture(frame.portraitTexture, QUI_UF.GetFrameUnit(frame), true)
            frame.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
        end
    end
end

QUI_UF._GetFontPath = GetFontPath
QUI_UF._GetFontOutline = GetFontOutline
QUI_UF._GetUnitSettings = GetUnitSettings
QUI_UF._GetGeneralSettings = GetGeneralSettings
QUI_UF._UpdateFrame = UpdateFrame

local function BuildFrameBars(frame, unit, unitKey, settings, general, width, height, useClassBg)
    local skinBgR, skinBgG, skinBgB = 0.1, 0.1, 0.1
    if Helpers and Helpers.GetSkinBgColor then skinBgR, skinBgG, skinBgB = Helpers.GetSkinBgColor() end
    local bgColor = { skinBgR, skinBgG, skinBgB, 0.9 }
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
    end
    if useClassBg and settings and settings.useClassColorBg and UnitIsPlayer(unit) then
        local cr, cg, cb = GetUnitClassColor(unit)
        if cr then bgColor = { cr, cg, cb, bgColor[4] or 1 } end
    end

    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    Helpers.SetFrameBackdropColor(frame, bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    if borderSize > 0 then
        local skinBorderR, skinBorderG, skinBorderB, skinBorderA = 0, 0, 0, 1
        if Helpers and Helpers.GetSkinBorderColor then skinBorderR, skinBorderG, skinBorderB, skinBorderA = Helpers.GetSkinBorderColor(settings, "") end
        Helpers.SetFrameBackdropBorderColor(frame, skinBorderR, skinBorderG, skinBorderB, skinBorderA)
    end

    local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
    local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0
    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    healthBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:EnableMouse(false)
    frame.healthBar = healthBar
    ApplyHealthFillDirection(frame, settings)
    CacheHealthBarExtents(frame, settings, width, height)

    if unitKey == "player" or unitKey == "target" then
        local predictionSettings = settings.healPrediction or {}
        local healPredictionBar = CreateFrame("StatusBar", nil, healthBar)
        healPredictionBar:SetStatusBarTexture(GetTexturePath(settings.texture))
        healPredictionBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        healPredictionBar:SetPoint("TOP", healthBar, "TOP", 0, 0)
        healPredictionBar:SetPoint("BOTTOM", healthBar, "BOTTOM", 0, 0)
        healPredictionBar:SetMinMaxValues(0, 1)
        healPredictionBar:SetValue(0)
        local pc = predictionSettings.color or { 0.2, 1, 0.2 }
        local pa = predictionSettings.opacity or 0.5
        healPredictionBar:SetStatusBarColor(pc[1] or 0.2, pc[2] or 1, pc[3] or 0.2, pa)
        healPredictionBar:Hide()
        frame.healPredictionBar = healPredictionBar
    end

    local absorbSettings = settings.absorbs or {}
    local absorbBar = CreateFrame("StatusBar", nil, healthBar)
    absorbBar:SetStatusBarTexture(GetAbsorbTexturePath(absorbSettings.texture))
    local absorbBarTex = absorbBar:GetStatusBarTexture()
    if absorbBarTex then
        absorbBarTex:SetHorizTile(false)
        absorbBarTex:SetVertTile(false)
        absorbBarTex:SetTexCoord(0, 1, 0, 1)
    end
    local ac = absorbSettings.color or { 1, 1, 1 }
    local aa = absorbSettings.opacity or 0.7
    absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    absorbBar:SetPoint("TOP", healthBar, "TOP", 0, 0)
    absorbBar:SetPoint("BOTTOM", healthBar, "BOTTOM", 0, 0)
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:Hide()
    frame.absorbBar = absorbBar

    local healAbsorbBar = CreateFrame("StatusBar", nil, healthBar)
    healAbsorbBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    healAbsorbBar:SetAllPoints(healthBar)
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:SetStatusBarColor(0.6, 0.1, 0.1, 0.8)
    healAbsorbBar:SetReverseFill(true)
    frame.healAbsorbBar = healAbsorbBar

    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        local r, g, b, a = GetHealthBarColor(unit, settings)
        healthBar:SetStatusBarColor(r, g, b, a)
    end

    if settings.showPowerBar then
        local powerBar = CreateFrame("StatusBar", nil, frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        powerBar:SetStatusBarTexture(GetTexturePath(settings.texture))
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        local powerColor = settings.powerBarColor or { 0, 0.5, 1, 1 }
        powerBar:SetStatusBarColor(powerColor[1], powerColor[2], powerColor[3], powerColor[4] or 1)
        powerBar:EnableMouse(false)
        frame.powerBar = powerBar

        if settings.powerBarBorder ~= false then
            local separator = powerBar:CreateTexture(nil, "OVERLAY")
            separator:SetHeight(QUICore:GetPixelSize(powerBar))
            separator:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
            separator:SetTexture("Interface\\Buttons\\WHITE8x8")
            separator:SetVertexColor(0, 0, 0, 1)
            frame.powerBarSeparator = separator
        end
    end

    return healthBar
end

local UpdateBossRangeAlpha, SeedBossFrameRangeAlpha

local function CreateBossFrame(unit, frameKey, bossIndex)
    local settings = GetUnitSettings("boss")
    local general = GetGeneralSettings()

    if not settings then return nil end

    local frameName = "QUI_Boss" .. bossIndex
    local frame = CreateFrame("Button", frameName, UIParent, "SecureUnitButtonTemplate, BackdropTemplate, PingableUnitFrameTemplate")

    QUI_UF.SetFrameUnit(frame, unit)
    frame.unitKey = "boss"

    local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
    frame:SetSize(width, height)

    if not IsFrameOverridden(frame) then
        if QUICore.SetSnappedPoint then
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
        end
    end

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")

    frame:HookScript("OnEnter", function(self)
        ShowUnitTooltip(self)
    end)
    frame:HookScript("OnLeave", HideUnitTooltip)

    RegisterStateDriver(frame, "visibility", "[@" .. unit .. ",exists] show; hide")

    frame:HookScript("OnShow", function(self)
        local bossKey = "boss" .. bossIndex
        if QUI_UF.previewMode[bossKey] then return end
        UpdateFrame(self)
        SeedBossFrameRangeAlpha(self)
    end)

    local healthBar = BuildFrameBars(frame, unit, "boss", settings, general, width, height)

    local bossNameSettings = GetNameSettings(settings)
    if bossNameSettings.showName then
        local nameAnchorInfo = GetTextAnchorInfo(bossNameSettings.nameAnchor or "LEFT")
        local nameOffsetX = QUICore:PixelRound(bossNameSettings.nameOffsetX or 4, healthBar)
        local nameOffsetY = QUICore:PixelRound(bossNameSettings.nameOffsetY or 0, healthBar)
        local nameText = healthBar:CreateFontString(nil, "OVERLAY")
        Helpers.ApplyFontWithFallback(nameText, GetFontPath(), bossNameSettings.nameFontSize or 12, GetFontOutline())
        nameText:SetShadowOffset(0, 0)
        nameText:SetPoint(nameAnchorInfo.point, healthBar, nameAnchorInfo.point, nameOffsetX, nameOffsetY)
        nameText:SetJustifyH(nameAnchorInfo.justify)
        nameText:SetText(ns.L["Boss"] .. " " .. bossIndex)
        frame.nameText = nameText
    end

    if settings.showLevel == true then
        local levelAnchorInfo = GetTextAnchorInfo(settings.levelAnchor or "RIGHT")
        local levelOffsetX = QUICore:PixelRound(settings.levelOffsetX or -4, healthBar)
        local levelOffsetY = QUICore:PixelRound(settings.levelOffsetY or 0, healthBar)
        local levelText = healthBar:CreateFontString(nil, "OVERLAY")
        Helpers.ApplyFontWithFallback(levelText, ResolveTextFont(settings.levelFont, GetFontPath()), settings.levelFontSize or 12, GetFontOutline())
        levelText:SetShadowOffset(0, 0)
        levelText:SetPoint(levelAnchorInfo.point, healthBar, levelAnchorInfo.point, levelOffsetX, levelOffsetY)
        levelText:SetJustifyH(levelAnchorInfo.justify)
        levelText:SetText("??")
        frame.levelText = levelText
    end

    if settings.showHealth then
        local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
        local healthOffsetX = QUICore:PixelRound(settings.healthOffsetX or -4, healthBar)
        local healthOffsetY = QUICore:PixelRound(settings.healthOffsetY or 0, healthBar)
        local healthText = healthBar:CreateFontString(nil, "OVERLAY")
        CJKFont(healthText, GetFontPath(), settings.healthFontSize or 11, GetFontOutline())
        healthText:SetShadowOffset(0, 0)
        healthText:SetPoint(healthAnchorInfo.point, healthBar, healthAnchorInfo.point, healthOffsetX, healthOffsetY)
        healthText:SetJustifyH(healthAnchorInfo.justify)
        healthText:SetText("100%")
        frame.healthText = healthText
    end

    local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
    local powerText = healthBar:CreateFontString(nil, "OVERLAY")
    CJKFont(powerText, GetFontPath(), settings.powerTextFontSize or 10, GetFontOutline())
    powerText:SetShadowOffset(0, 0)
    local pOffX = QUICore:PixelRound(settings.powerTextOffsetX or -4, healthBar)
    local pOffY = QUICore:PixelRound(settings.powerTextOffsetY or 2, healthBar)
    powerText:SetPoint(powerAnchorInfo.point, healthBar, powerAnchorInfo.point, pOffX, pOffY)
    powerText:SetJustifyH(powerAnchorInfo.justify)
    powerText:Hide()
    frame.powerText = powerText

    if settings.targetMarker then
        local indicatorFrame = CreateFrame("Frame", nil, frame)
        indicatorFrame:SetAllPoints()
        indicatorFrame:SetFrameLevel(healthBar:GetFrameLevel() + 5)
        frame.indicatorFrame = indicatorFrame

        local marker = settings.targetMarker
        local targetMarker = indicatorFrame:CreateTexture(nil, "OVERLAY")
        targetMarker:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
        targetMarker:SetSize(marker.size or 20, marker.size or 20)
        local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
        targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
        targetMarker:Hide()
        frame.targetMarker = targetMarker
    end

    if settings.classificationIcon and settings.classificationIcon.enabled then
        if not frame.indicatorFrame then
            local indicatorFrame = CreateFrame("Frame", nil, frame)
            indicatorFrame:SetAllPoints()
            indicatorFrame:SetFrameLevel(healthBar:GetFrameLevel() + 5)
            frame.indicatorFrame = indicatorFrame
        end

        local ci = settings.classificationIcon
        local classificationIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
        classificationIcon:SetSize(ci.size or 16, ci.size or 16)
        local anchorInfo = GetTextAnchorInfo(ci.anchor or "LEFT")
        classificationIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, ci.xOffset or -8, ci.yOffset or 0)
        classificationIcon:Hide()
        frame.classificationIcon = classificationIcon
    end

    if settings.targetHighlight and settings.targetHighlight.enabled ~= false then
        local px = QUICore:PixelRound(1, frame)
        local targetHighlight = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        targetHighlight:ClearAllPoints()
        targetHighlight:SetPoint("TOPLEFT", -px, px)
        targetHighlight:SetPoint("BOTTOMRIGHT", px, -px)
        targetHighlight:SetFrameLevel(frame:GetFrameLevel() + 4)
        targetHighlight:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px * 2,
        })
        targetHighlight:Hide()
        frame.targetHighlight = targetHighlight
    end

    local _powerThrottleElapsed = 0
    local _powerThrottleDirty = false
    local POWER_THROTTLE_INTERVAL = 0.2
    local function PowerThrottleOnUpdate(self, delta)
        if not _powerThrottleDirty then
            self:SetScript("OnUpdate", nil)
            _powerThrottleElapsed = 0
            return
        end
        _powerThrottleElapsed = _powerThrottleElapsed + delta
        if _powerThrottleElapsed < POWER_THROTTLE_INTERVAL then return end
        _powerThrottleElapsed = 0
        _powerThrottleDirty = false
        UpdatePower(self)
        UpdatePowerText(self)
        self:SetScript("OnUpdate", nil)
    end

    frame:SetScript("OnEvent", function(self, event, ...)
        local frameUnit = QUI_UF.GetFrameUnit(self)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                UpdateHealth(self)
                UpdateAbsorbs(self)
            end
        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                UpdateAbsorbs(self)
            end
        elseif event == "UNIT_POWER_FREQUENT" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                _powerThrottleDirty = true
                self:SetScript("OnUpdate", PowerThrottleOnUpdate)
            end
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                UpdatePower(self)
                UpdatePowerText(self)
                _powerThrottleDirty = false
                _powerThrottleElapsed = 0
                self:SetScript("OnUpdate", nil)
            end
        elseif event == "UNIT_NAME_UPDATE" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                UpdateName(self)
                UpdateLevelText(self)
            end
        elseif event == "UNIT_LEVEL" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                UpdateLevelText(self)
            end
        elseif event == "UNIT_TARGET" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                UpdateName(self)
            end
        elseif event == "RAID_TARGET_UPDATE" then
            UpdateTargetMarker(self)
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            local eventUnit = ...
            if eventUnit == frameUnit then
                UpdateClassificationIcon(self)
                UpdateLevelText(self)
            end
        end
    end)

    frame:RegisterUnitEvent("UNIT_HEALTH", unit)
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    frame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    frame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit)
    frame:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
    frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit)
    frame:RegisterUnitEvent("UNIT_MAXPOWER", unit)
    frame:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    frame:RegisterUnitEvent("UNIT_LEVEL", unit)
    frame:RegisterUnitEvent("UNIT_TARGET", unit)
    frame:RegisterEvent("RAID_TARGET_UPDATE")

    if settings.classificationIcon and settings.classificationIcon.enabled then
        frame:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", unit)
    end

    if _G.ClickCastFrames then
        _G.ClickCastFrames[frame] = true
    end

    return frame
end

QUI_UF.PowerCoalesce = {}

function QUI_UF.PowerCoalesce.NewState()
    return { gen = 0, queuedGen = nil }
end

function QUI_UF.PowerCoalesce.OnFrequent(state)
    local schedule = (state.queuedGen == nil)
    state.queuedGen = state.gen
    return schedule
end

function QUI_UF.PowerCoalesce.OnImmediate(state)
    state.gen = state.gen + 1
end

function QUI_UF.PowerCoalesce.OnFire(state)
    local queued = state.queuedGen
    state.queuedGen = nil
    return queued ~= nil and queued == state.gen
end

function QUI_UF.PowerCoalesce.EventMatters(eventPowerType, displayedToken, anySecret)
    if anySecret then return true end
    if eventPowerType == nil or displayedToken == nil then return true end
    return eventPowerType == displayedToken
end

-- @secret-policy: collapse-only — a secret token on either side makes the
function QUI_UF.EventPowerMatters(unit, eventPowerType)
    local _, token = UnitPowerType(unit)
    local eventIsSecret = IsSecretValue(eventPowerType)
    local tokenIsSecret = IsSecretValue(token)
    return QUI_UF.PowerCoalesce.EventMatters(eventPowerType, token,
        eventIsSecret or tokenIsSecret)
end

local function ForceUpdateToT(includeIdentity)
    local totFrame = QUI_UF.frames and QUI_UF.frames.targettarget
    if not totFrame or not UnitExists("targettarget") then return end
    UpdateHealth(totFrame)
    UpdateAbsorbs(totFrame)
    UpdatePower(totFrame)
    UpdatePowerText(totFrame)
    if includeIdentity then
        UpdateName(totFrame)
        UpdateLevelText(totFrame)
    end
end

local totUpdateTicker = nil
local TOT_UPDATE_INTERVAL = 0.5

local function StartToTTicker()
    if totUpdateTicker then return end
    local TOT_IDENTITY_TICKS = 4
    local tick = 0
    totUpdateTicker = C_Timer.NewTicker(TOT_UPDATE_INTERVAL, function()
        if UnitExists("targettarget") then
            tick = (tick + 1) % TOT_IDENTITY_TICKS
            ForceUpdateToT(tick == 0)
        end
    end)
end

local function StopToTTicker()
    if totUpdateTicker then
        totUpdateTicker:Cancel()
        totUpdateTicker = nil
    end
end

local _bossTargetHighlightFrame = nil

local function UpdateBossTargetHighlight()
    local bossSettings = GetUnitSettings("boss")
    local hlSettings = bossSettings and bossSettings.targetHighlight
    local enabled = hlSettings and hlSettings.enabled ~= false

    if _bossTargetHighlightFrame and _bossTargetHighlightFrame.targetHighlight then
        _bossTargetHighlightFrame.targetHighlight:Hide()
    end
    _bossTargetHighlightFrame = nil

    if not enabled or not QUI_UF.frames then return end

    for i = 1, 5 do
        local frame = QUI_UF.frames["boss" .. i]
        local frameUnit = QUI_UF.GetFrameUnit(frame)
        if frame and frameUnit and frame.targetHighlight and UnitExists(frameUnit) then
            local isTarget = UnitIsUnit(frameUnit, "target")
            if not IsSecretValue(isTarget) and isTarget then
                local c = hlSettings.color or { 1, 1, 1, 0.6 }
                frame.targetHighlight:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.6)
                frame.targetHighlight:Show()
                _bossTargetHighlightFrame = frame
                return
            end
        end
    end
end

-- C_CurveUtil.EvaluateColorValueFromBoolean, both AllowedWhenTainted). Because
local bossRange = {
    eventFrame = nil,
}

local function GetBossRangeSettings()
    local settings = GetUnitSettings("boss")
    local range = settings and settings.range
    if range == nil then
        return { enabled = true, outOfRangeAlpha = 0.4 }
    end
    return range
end

local function ShouldApplyBossRangeAlpha()
    if (_G.QUI_IsUnitFrameEditModeActive and _G.QUI_IsUnitFrameEditModeActive())
        or Helpers.IsLayoutModeActive() then
        return false
    end

    if _G.QUI_ShouldUnitframesBeVisible and not _G.QUI_ShouldUnitframesBeVisible() then
        return false
    end

    return true
end

local function ApplyBossRangeAlpha(frame, inRange, outAlpha)
    if not frame then return end

    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        frame:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(inRange, 1, outAlpha))
    elseif frame.SetAlphaFromBoolean then
        frame:SetAlphaFromBoolean(inRange, 1, outAlpha)
    else
        frame:SetAlpha(1)
    end
end

local function ResetBossRangeAlpha()
    for i = 1, 5 do
        local frame = QUI_UF.frames and QUI_UF.frames["boss" .. i]
        if frame then
            frame:SetAlpha(1)
        end
    end
end

SeedBossFrameRangeAlpha = function(frame)
    if not frame then return end
    local range = GetBossRangeSettings()
    if not range or range.enabled == false then
        frame:SetAlpha(1)
        return
    end
    if not ShouldApplyBossRangeAlpha() then return end
    frame:SetAlpha(1)
end

UpdateBossRangeAlpha = function()
    local range = GetBossRangeSettings()
    if not range or range.enabled == false then
        ResetBossRangeAlpha()
        return
    end

    if not ShouldApplyBossRangeAlpha() then return end

    for i = 1, 5 do
        local frame = QUI_UF.frames and QUI_UF.frames["boss" .. i]
        if frame then frame:SetAlpha(1) end
    end
end

local function EnsureBossRangeEventFrame()
    if bossRange.eventFrame then return end

    local listeners = {}
    for i = 1, 5 do
        local token = "boss" .. i
        local listener = CreateFrame("Frame")
        listener:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", token)
        listener:SetScript("OnEvent", function(_, _, _, isInRange)
            local range = GetBossRangeSettings()
            if not range or range.enabled == false then return end
            if not ShouldApplyBossRangeAlpha() then return end
            local frame = QUI_UF.frames and QUI_UF.frames[token]
            local frameUnit = QUI_UF.GetFrameUnit(frame)
            if frame and frameUnit and UnitExists(frameUnit) then
                ApplyBossRangeAlpha(frame, isInRange, range.outOfRangeAlpha or 0.4)
            end
        end)
        listeners[i] = listener
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:SetScript("OnEvent", function()
        UpdateBossRangeAlpha()
    end)
    bossRange.eventFrame = eventFrame
    bossRange.rangeListeners = listeners
end

local function StartBossRangeCheck()
    local range = GetBossRangeSettings()
    if range and range.enabled == false then
        ResetBossRangeAlpha()
        return
    end

    EnsureBossRangeEventFrame()
    UpdateBossRangeAlpha()
end

local function StopBossRangeCheck()
    ResetBossRangeAlpha()
end

local function RefreshBossRangeCheck()
    local range = GetBossRangeSettings()
    if range and range.enabled == false then
        StopBossRangeCheck()
    else
        StartBossRangeCheck()
    end
end

local function CreateUnitFrame(unit, unitKey)
    local settings = GetUnitSettings(unitKey)
    local general = GetGeneralSettings()

    if not settings then return nil end

    local frameName = "QUI_" .. unitKey:gsub("^%l", string.upper)
    local frame = CreateFrame("Button", frameName, UIParent, "SecureUnitButtonTemplate, BackdropTemplate, PingableUnitFrameTemplate")

    QUI_UF.SetFrameUnit(frame, unit)
    frame.unitKey = unitKey

    local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
    frame:SetSize(width, height)

    if not IsFrameOverridden(frame) then
        if QUICore.SetSnappedPoint then
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
        end
    end

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")

    frame:HookScript("OnEnter", function(self)
        ShowUnitTooltip(self)
    end)
    frame:HookScript("OnLeave", HideUnitTooltip)

    if unit == "target" then
        RegisterStateDriver(frame, "visibility", "[@target,exists] show; hide")
    elseif unit == "focus" then
        RegisterStateDriver(frame, "visibility", "[@focus,exists] show; hide")
    elseif unit == "pet" then
        RegisterStateDriver(frame, "visibility", "[@pet,exists] show; hide")
    elseif unit == "targettarget" then
        RegisterStateDriver(frame, "visibility", "[@targettarget,exists] show; hide")
        frame:HookScript("OnShow", StartToTTicker)
        frame:HookScript("OnHide", StopToTTicker)
        if frame:IsShown() then
            StartToTTicker()
        end
    elseif unit:match("^boss%d+$") then
        RegisterStateDriver(frame, "visibility", "[@" .. unit .. ",exists] show; hide")
    end

    local healthBar = BuildFrameBars(frame, unit, unitKey, settings, general, width, height, true)

    if settings.showPortrait then
        local portrait = CreateFrame("Button", nil, frame, "SecureUnitButtonTemplate, BackdropTemplate")
        local portraitSizePx = settings.portraitSize or 40
        local portraitBorderSize = QUICore:Pixels(settings.portraitBorderSize or 1, portrait)
        portrait:SetSize(QUICore:PixelRound(portraitSizePx, portrait), QUICore:PixelRound(portraitSizePx, portrait))

        local portraitGap = QUICore:PixelRound(settings.portraitGap or 0, portrait)
        local portraitOffsetX = QUICore:PixelRound(settings.portraitOffsetX or 0, portrait)
        local portraitOffsetY = QUICore:PixelRound(settings.portraitOffsetY or 0, portrait)
        local side = settings.portraitSide or "LEFT"
        if side == "LEFT" then
            portrait:SetPoint("RIGHT", frame, "LEFT", -portraitGap + portraitOffsetX, portraitOffsetY)
        else
            portrait:SetPoint("LEFT", frame, "RIGHT", portraitGap + portraitOffsetX, portraitOffsetY)
        end

        portrait:SetAttribute("unit", unit)
        portrait:SetAttribute("*type1", "target")
        portrait:SetAttribute("*type2", "togglemenu")
        portrait:RegisterForClicks("AnyUp")

        portrait:HookScript("OnEnter", function(self)
            ShowUnitTooltip(frame)
        end)
        portrait:HookScript("OnLeave", HideUnitTooltip)

        portrait:SetBackdrop({
            bgFile = nil,
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = portraitBorderSize,
        })

        local borderR, borderG, borderB, borderA = Helpers.GetSkinBorderColor(settings, "portrait")
        portrait:SetBackdropBorderColor(borderR, borderG, borderB, borderA)

        local portraitTex = portrait:CreateTexture(nil, "ARTWORK")
        portraitTex:SetPoint("TOPLEFT", portraitBorderSize, -portraitBorderSize)
        portraitTex:SetPoint("BOTTOMRIGHT", -portraitBorderSize, portraitBorderSize)
        frame.portraitTexture = portraitTex
        frame.portrait = portrait

        SetPortraitTexture(portraitTex, unit, true)
        portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    end

    local textFrame = CreateFrame("Frame", nil, frame)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    frame.textFrame = textFrame

    local fontPath = GetFontPath()
    local fontOutline = general and general.fontOutline or "OUTLINE"
    local unitNameSettings = GetNameSettings(settings)
    local nameFontSize = unitNameSettings.nameFontSize or 12
    local nameAnchorInfo = GetTextAnchorInfo(unitNameSettings.nameAnchor or "LEFT")
    local nameOffsetX = QUICore:PixelRound(unitNameSettings.nameOffsetX or 4, frame)
    local nameOffsetY = QUICore:PixelRound(unitNameSettings.nameOffsetY or 0, frame)

    local nameText = textFrame:CreateFontString(nil, "OVERLAY")
    Helpers.ApplyFontWithFallback(nameText, fontPath, nameFontSize, fontOutline)
    nameText:SetPoint(nameAnchorInfo.point, frame, nameAnchorInfo.point, nameOffsetX, nameOffsetY)
    nameText:SetJustifyH(nameAnchorInfo.justify)
    nameText:SetTextColor(1, 1, 1, 1)
    frame.nameText = nameText

    local levelFontSize = settings.levelFontSize or nameFontSize
    local levelAnchorInfo = GetTextAnchorInfo(settings.levelAnchor or "RIGHT")
    local levelOffsetX = QUICore:PixelRound(settings.levelOffsetX or -4, frame)
    local levelOffsetY = QUICore:PixelRound(settings.levelOffsetY or 0, frame)

    local levelText = textFrame:CreateFontString(nil, "OVERLAY")
    Helpers.ApplyFontWithFallback(levelText, ResolveTextFont(settings.levelFont, fontPath), levelFontSize, fontOutline)
    levelText:SetPoint(levelAnchorInfo.point, frame, levelAnchorInfo.point, levelOffsetX, levelOffsetY)
    levelText:SetJustifyH(levelAnchorInfo.justify)
    levelText:SetTextColor(1, 1, 1, 1)
    levelText:Hide()
    frame.levelText = levelText

    local healthFontSize = settings.healthFontSize or 12
    local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
    local healthOffsetX = QUICore:PixelRound(settings.healthOffsetX or -4, frame)
    local healthOffsetY = QUICore:PixelRound(settings.healthOffsetY or 0, frame)

    local healthText = textFrame:CreateFontString(nil, "OVERLAY")
    CJKFont(healthText, fontPath, healthFontSize, fontOutline)
    healthText:SetPoint(healthAnchorInfo.point, frame, healthAnchorInfo.point, healthOffsetX, healthOffsetY)
    healthText:SetJustifyH(healthAnchorInfo.justify)
    healthText:SetTextColor(1, 1, 1, 1)
    frame.healthText = healthText

    local powerTextFontSize = settings.powerTextFontSize or 12
    local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
    local powerTextOffsetX = QUICore:PixelRound(settings.powerTextOffsetX or -4, frame)
    local powerTextOffsetY = QUICore:PixelRound(settings.powerTextOffsetY or 2, frame)

    local powerText = textFrame:CreateFontString(nil, "OVERLAY")
    CJKFont(powerText, fontPath, powerTextFontSize, fontOutline)
    powerText:SetPoint(powerAnchorInfo.point, frame, powerAnchorInfo.point, powerTextOffsetX, powerTextOffsetY)
    powerText:SetJustifyH(powerAnchorInfo.justify)
    powerText:SetTextColor(1, 1, 1, 1)
    powerText:Hide()
    frame.powerText = powerText

    if unitKey == "player" then
        local indSettings = settings.indicators

        local indicatorFrame = CreateFrame("Frame", nil, frame)
        indicatorFrame:SetAllPoints()
        indicatorFrame:SetFrameLevel(textFrame:GetFrameLevel() + 5)
        frame.indicatorFrame = indicatorFrame

        if indSettings and indSettings.rested then
            local rested = indSettings.rested
            local restedIndicator = indicatorFrame:CreateTexture(nil, "OVERLAY")
            restedIndicator:SetSize(rested.size or 16, rested.size or 16)
            local anchorInfo = GetTextAnchorInfo(rested.anchor or "TOPLEFT")
            restedIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, rested.offsetX or -2, rested.offsetY or 2)
            restedIndicator:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            restedIndicator:SetTexCoord(0.0625, 0.4375, 0.0625, 0.4375)
            restedIndicator:Hide()
            frame.restedIndicator = restedIndicator
        end

        if indSettings and indSettings.combat then
            local combat = indSettings.combat
            local combatIndicator = indicatorFrame:CreateTexture(nil, "OVERLAY")
            combatIndicator:SetSize(combat.size or 16, combat.size or 16)
            local anchorInfo = GetTextAnchorInfo(combat.anchor or "TOPLEFT")
            combatIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, combat.offsetX or -2, combat.offsetY or 2)
            combatIndicator:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            combatIndicator:SetTexCoord(0.5625, 0.9375, 0.0625, 0.4375)
            combatIndicator:Hide()
            frame.combatIndicator = combatIndicator
        end

        local general = GetGeneralSettings()
        local fontOutline = general and general.fontOutline or "OUTLINE"

        local stanceText = indicatorFrame:CreateFontString(nil, "OVERLAY")
        CJKFont(stanceText, fontPath, 12, fontOutline)
        stanceText:SetPoint("BOTTOM", frame, "BOTTOM", 0, -2)
        stanceText:SetJustifyH("CENTER")
        stanceText:SetTextColor(1, 1, 1, 1)
        stanceText:Hide()
        frame.stanceText = stanceText

        local stanceIcon = indicatorFrame:CreateTexture(nil, "OVERLAY")
        stanceIcon:SetSize(14, 14)
        stanceIcon:SetPoint("RIGHT", stanceText, "LEFT", -2, 0)
        stanceIcon:Hide()
        frame.stanceIcon = stanceIcon
    end

    if settings.targetMarker then
        if not frame.indicatorFrame then
            local indicatorFrame = CreateFrame("Frame", nil, frame)
            indicatorFrame:SetAllPoints()
            indicatorFrame:SetFrameLevel(textFrame:GetFrameLevel() + 5)
            frame.indicatorFrame = indicatorFrame
        end

        local marker = settings.targetMarker
        local targetMarker = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
        targetMarker:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
        targetMarker:SetSize(marker.size or 20, marker.size or 20)
        local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
        targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
        targetMarker:Hide()
        frame.targetMarker = targetMarker
    end

    if settings.leaderIcon and settings.leaderIcon.enabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
        if not frame.indicatorFrame then
            local indicatorFrame = CreateFrame("Frame", nil, frame)
            indicatorFrame:SetAllPoints()
            indicatorFrame:SetFrameLevel(textFrame:GetFrameLevel() + 5)
            frame.indicatorFrame = indicatorFrame
        end

        local leader = settings.leaderIcon
        local leaderIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
        leaderIcon:SetSize(leader.size or 16, leader.size or 16)
        local anchorInfo = GetTextAnchorInfo(leader.anchor or "TOPLEFT")
        leaderIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, leader.xOffset or -8, leader.yOffset or 8)
        leaderIcon:Hide()
        frame.leaderIcon = leaderIcon
    end

    if settings.classificationIcon and settings.classificationIcon.enabled and (unitKey == "target" or unitKey == "focus") then
        if not frame.indicatorFrame then
            local indicatorFrame = CreateFrame("Frame", nil, frame)
            indicatorFrame:SetAllPoints()
            indicatorFrame:SetFrameLevel(textFrame:GetFrameLevel() + 5)
            frame.indicatorFrame = indicatorFrame
        end

        local ci = settings.classificationIcon
        local classificationIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
        classificationIcon:SetSize(ci.size or 16, ci.size or 16)
        local anchorInfo = GetTextAnchorInfo(ci.anchor or "LEFT")
        classificationIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, ci.xOffset or -8, ci.yOffset or 0)
        classificationIcon:Hide()
        frame.classificationIcon = classificationIcon
    end

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterUnitEvent("UNIT_HEALTH", unit)
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    frame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit)
    frame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    frame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit)
    frame:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
    frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit)
    frame:RegisterUnitEvent("UNIT_MAXPOWER", unit)
    frame:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    frame:RegisterUnitEvent("UNIT_LEVEL", unit)
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    if unitKey == "pet" then
        frame:RegisterUnitEvent("UNIT_PET", "player")
    end
    frame:RegisterEvent("UNIT_TARGET")
    frame:RegisterEvent("RAID_TARGET_UPDATE")

    if settings.leaderIcon and settings.leaderIcon.enabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
        frame:RegisterEvent("PARTY_LEADER_CHANGED")
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    end

    if settings.classificationIcon and settings.classificationIcon.enabled and (unitKey == "target" or unitKey == "focus") then
        frame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
    end

    if unitKey == "player" then
        frame:RegisterEvent("PLAYER_UPDATE_RESTING")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    end

    local _freqPower = QUI_UF.PowerCoalesce.NewState()
    local function DrainFrequentPower()
        if not QUI_UF.PowerCoalesce.OnFire(_freqPower) then return end
        local u = QUI_UF.GetFrameUnit(frame)
        if u and UnitExists(u) then
            UpdatePower(frame)
            UpdatePowerText(frame)
        end
    end

    frame:SetScript("OnEvent", function(self, event, arg1, arg2)
        local frameUnit = QUI_UF.GetFrameUnit(self)
        if event == "PLAYER_ENTERING_WORLD" then
            local a = self:GetAlpha()
            if not Helpers.IsSecretValue(a) and a < 0.01 then return end
            UpdateFrame(self)
        elseif event == "PLAYER_TARGET_CHANGED" then
            if self.unitKey == "target" then
                if UnitExists(frameUnit) then
                    UpdateFrame(self)
                end
            elseif self.unitKey == "targettarget" then
                if UnitExists(frameUnit) then
                    UpdateFrame(self)
                else
                    ClearToTDisplay(self)
                end
            end
        elseif event == "UNIT_TARGET" then
            if arg1 == "target" then
                if self.unitKey == "target" then
                    UpdateName(self)
                elseif self.unitKey == "targettarget" then
                    if UnitExists(frameUnit) then
                        UpdateFrame(self)
                    else
                        ClearToTDisplay(self)
                    end
                end
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            if self.unitKey == "focus" then
                if UnitExists(frameUnit) then
                    UpdateFrame(self)
                end
            end
        elseif event == "UNIT_PET" then
            if self.unitKey == "pet" then
                if UnitExists(frameUnit) then
                    UpdateFrame(self)
                end
            end
        elseif event == "PLAYER_UPDATE_RESTING"
               or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            if self.unitKey == "player" then
                UpdateIndicators(self)
            end
        elseif event == "UPDATE_SHAPESHIFT_FORM" then
            if self.unitKey == "player" then
                UpdateStance(self)
            end
        elseif event == "RAID_TARGET_UPDATE" then
            UpdateTargetMarker(self)
        elseif event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
            UpdateLeaderIcon(self)
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            if arg1 == frameUnit then
                UpdateClassificationIcon(self)
                UpdateLevelText(self)
            end
        elseif arg1 == frameUnit then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                UpdateHealth(self)
                UpdateAbsorbs(self)
                UpdateHealPrediction(self)
            elseif event == "UNIT_HEAL_PREDICTION" then
                UpdateHealPrediction(self)
            elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                UpdateAbsorbs(self)
            elseif event == "UNIT_POWER_FREQUENT" then
                if QUI_UF.EventPowerMatters(frameUnit, arg2)
                   and QUI_UF.PowerCoalesce.OnFrequent(_freqPower) then
                    C_Timer.After(0.2, DrainFrequentPower)
                end
            elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
                if event == "UNIT_MAXPOWER" or QUI_UF.EventPowerMatters(frameUnit, arg2) then
                    UpdatePower(self)
                    UpdatePowerText(self)
                    QUI_UF.PowerCoalesce.OnImmediate(_freqPower)
                end
            elseif event == "UNIT_NAME_UPDATE" then
                UpdateName(self)
                UpdateLevelText(self)
            elseif event == "UNIT_LEVEL" then
                UpdateLevelText(self)
            end
        end
    end)

    if UnitExists(unit) or unitKey == "player" then
        UpdateFrame(frame)
    end
    if unitKey == "player" then
        frame:Show()
    end

    if _G.ClickCastFrames then
        _G.ClickCastFrames[frame] = true
    end

    return frame
end

local function CreateCastbar(unitFrame, unit, unitKey)
    if QUI_Castbar then
        return QUI_Castbar:CreateCastbar(unitFrame, unit, unitKey)
    end
    return nil
end

local function CreateBossCastbar(unitFrame, unit, bossIndex)
    if QUI_Castbar then
        return QUI_Castbar:CreateBossCastbar(unitFrame, unit, bossIndex)
    end
    return nil
end

function QUI_UF:ShowPreview(unitKey)
    if unitKey == "boss" then
        local general = GetGeneralSettings()
        local settings = GetUnitSettings("boss")

        self:RefreshFrame("boss")

        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                self.previewMode[bossKey] = true
                if not InCombatLockdown() then
                    UnregisterStateDriver(frame, "visibility")
                end
                frame:Show()
                frame.healthBar:SetMinMaxValues(0, 100)
                frame.healthBar:SetValue(75 - (i * 5))
                if frame.nameText then
                    frame.nameText:SetText(ns.L["Boss"] .. " " .. i)
                end
                if frame.healthText then
                    local previewHPPct = 75 - (i * 5)
                    local previewMaxHP = 100000
                    local previewHP = math_floor(previewMaxHP * (previewHPPct / 100))
                    frame.healthText:SetText(FormatHealthText(
                        previewHP,
                        previewHPPct,
                        settings and settings.healthDisplayStyle or "both",
                        settings and settings.healthDivider or " | ",
                        previewMaxHP,
                        settings and settings.hideHealthPercentSymbol == true
                    ))
                end
                if frame.powerBar and settings and settings.showPowerBar then
                    frame.powerBar:SetMinMaxValues(0, 100)
                    frame.powerBar:SetValue(60)
                    frame.powerBar:Show()
                end

                if frame.powerText then
                    if settings and settings.showPowerText then
                        frame.powerText:SetText(FormatPowerText(
                            60,
                            60,
                            settings.powerTextFormat or "percent",
                            settings.healthDivider or " | ",
                            settings.hidePowerPercentSymbol == true
                        ))
                        if settings.powerTextUsePowerColor then
                            frame.powerText:SetTextColor(0, 0.6, 1, 1)
                        elseif settings.powerTextUseClassColor then
                            frame.powerText:SetTextColor(0.96, 0.55, 0.73, 1)
                        elseif settings.powerTextColor then
                            local c = settings.powerTextColor
                            frame.powerText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
                        else
                            frame.powerText:SetTextColor(1, 1, 1, 1)
                        end
                        frame.powerText:Show()
                    else
                        frame.powerText:Hide()
                    end
                end

                if general and general.darkMode then
                    local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
                    frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                else
                    if general and general.defaultUseClassColor then
                        local _, class = UnitClass("player")
                        -- @secret-policy: collapse-only — secret class falls back to defaultHealthColor
                        if issecretvalue and issecretvalue(class) then class = nil end
                        if class and RAID_CLASS_COLORS[class] then
                            local color = RAID_CLASS_COLORS[class]
                            frame.healthBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                        else
                            local c = general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
                            frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                        end
                    else
                        local c = general and general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
                        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                    end
                end

                if frame.classificationIcon and settings.classificationIcon and settings.classificationIcon.enabled then
                    local data = ns.Classification and ns.Classification.DATA["elite"]
                    if data then
                        frame.classificationIcon:SetAtlas(data.atlas)
                        frame.classificationIcon:SetVertexColor(data.color[1], data.color[2], data.color[3])
                        frame.classificationIcon:Show()
                    end
                end

                if settings and settings.castbar and settings.castbar.previewMode then
                    local castbar = self.castbars[bossKey]
                    if castbar and QUI_Castbar then
                        QUI_Castbar:RefreshBossCastbar(castbar, bossKey, settings.castbar, frame)
                    end
                end

                if self.auraPreviewMode["boss_buff"] then
                    self:ShowAuraPreviewForFrame(frame, "boss", "buff")
                end
                if self.auraPreviewMode["boss_debuff"] then
                    self:ShowAuraPreviewForFrame(frame, "boss", "debuff")
                end
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    self.previewMode[unitKey] = true

    if not InCombatLockdown() then
        UnregisterStateDriver(frame, "visibility")
    end

    frame:Show()
    local settings = GetUnitSettings(unitKey)

    ApplyHealthFillDirection(frame, settings)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(75)

    if frame.nameText then
        local names = {
            player = SafeValue(UnitName("player")) or ns.L["Player"],
            target = ns.L["Target Dummy"],
            targettarget = ns.L["ToT Name"],
            pet = ns.L["Pet Name"],
            focus = ns.L["Focus Target"],
        }
        frame.nameText:SetText(names[unitKey] or ns.L["Preview"])
    end

    if frame.levelText then
        if settings and settings.showLevel == true then
            local levels = {
                player = "80",
                target = "82",
                targettarget = "80",
                pet = "80",
                focus = "81",
                boss = "??",
            }
            frame.levelText:SetText(levels[unitKey] or "80")
            local c = settings.levelTextColor or { 1, 1, 1, 1 }
            frame.levelText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            frame.levelText:Show()
        else
            frame.levelText:SetText("")
            frame.levelText:Hide()
        end
    end

    if frame.healthText then
        local previewHPPct = 75
        local previewMaxHP = 100000
        local previewHP = math_floor(previewMaxHP * (previewHPPct / 100))
        frame.healthText:SetText(FormatHealthText(
            previewHP,
            previewHPPct,
            settings and settings.healthDisplayStyle or "both",
            settings and settings.healthDivider or " | ",
            previewMaxHP,
            settings and settings.hideHealthPercentSymbol == true
        ))
    end

    if frame.powerBar then
        frame.powerBar:SetMinMaxValues(0, 100)
        frame.powerBar:SetValue(60)
        frame.powerBar:Show()
    end

    if frame.powerText then
        if settings and settings.showPowerText then
            frame.powerText:SetText(FormatPowerText(
                60,
                60,
                settings.powerTextFormat or "percent",
                settings.healthDivider or " | ",
                settings.hidePowerPercentSymbol == true
            ))
            if settings.powerTextUsePowerColor then
                frame.powerText:SetTextColor(0, 0.6, 1, 1)
            elseif settings.powerTextUseClassColor then
                frame.powerText:SetTextColor(0.96, 0.55, 0.73, 1)
            elseif settings.powerTextColor then
                local c = settings.powerTextColor
                frame.powerText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            else
                frame.powerText:SetTextColor(1, 1, 1, 1)
            end
            frame.powerText:Show()
        else
            frame.powerText:Hide()
        end
    end

    if frame.healPredictionBar then
        if settings and settings.healPrediction and settings.healPrediction.enabled then
            local hpMax = 100
            local incoming = 15
            local missing = hpMax - 75
            local clamped = incoming > missing and missing or incoming
            local healthTexture = frame.healthBar:GetStatusBarTexture()
            local healthReversed = IsTargetHealthDirectionInverted(unitKey, settings)
            local healthBarWidth, healthBarHeight = GetCachedHealthBarExtents(frame, settings)
            frame.healPredictionBar:ClearAllPoints()
            if healthReversed then
                frame.healPredictionBar:SetPoint("RIGHT", healthTexture, "LEFT", 0, 0)
            else
                frame.healPredictionBar:SetPoint("LEFT", healthTexture, "RIGHT", 0, 0)
            end
            if not healthBarWidth or not healthBarHeight then
                frame.healPredictionBar:Hide()
                return
            end
            frame.healPredictionBar:SetHeight(healthBarHeight)
            frame.healPredictionBar:SetWidth(healthBarWidth)
            frame.healPredictionBar:SetReverseFill(healthReversed)
            frame.healPredictionBar:SetMinMaxValues(0, hpMax)
            frame.healPredictionBar:SetValue(clamped)
            frame.healPredictionBar:SetStatusBarTexture(GetTexturePath(settings.texture))
            local c = settings.healPrediction.color or { 0.2, 1, 0.2 }
            local a = settings.healPrediction.opacity or 0.5
            frame.healPredictionBar:SetStatusBarColor(c[1] or 0.2, c[2] or 1, c[3] or 0.2, a)
            frame.healPredictionBar:Show()
        else
            frame.healPredictionBar:Hide()
        end
    end

    local general = GetGeneralSettings()

    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        if general and general.defaultUseClassColor then
            local _, class = UnitClass("player")
            -- @secret-policy: collapse-only — secret class falls back to defaultHealthColor
            if issecretvalue and issecretvalue(class) then class = nil end
            if class and RAID_CLASS_COLORS[class] then
                local color = RAID_CLASS_COLORS[class]
                frame.healthBar:SetStatusBarColor(color.r, color.g, color.b, 1)
            else
                local c = general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
                frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
            end
        else
            local c = general and general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
            frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        end
    end

    if frame.classificationIcon and settings and settings.classificationIcon and settings.classificationIcon.enabled then
        local data = ns.Classification and ns.Classification.DATA["elite"]
        if data then
            frame.classificationIcon:SetAtlas(data.atlas)
            frame.classificationIcon:SetVertexColor(data.color[1], data.color[2], data.color[3])
            frame.classificationIcon:Show()
        end
    end
end

function QUI_UF:HidePreview(unitKey)
    if unitKey == "boss" then
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                self.previewMode[bossKey] = false
                if frame.nameText then
                    frame.nameText:SetText("")
                end
                if not InCombatLockdown() then
                    RegisterStateDriver(frame, "visibility", "[@boss" .. i .. ",exists] show; hide")
                end
                if UnitExists("boss" .. i) then
                    UpdateFrame(frame)
                    frame:Show()
                else
                    frame:Hide()
                end

                if frame.classificationIcon then
                    frame.classificationIcon:Hide()
                end

                local castbar = self.castbars[bossKey]
                if castbar then
                    castbar.isPreviewSimulation = false
                    castbar:SetScript("OnUpdate", nil)
                    castbar:Hide()
                end

                self:HideAuraPreviewForFrame(frame, bossKey, "buff")
                self:HideAuraPreviewForFrame(frame, bossKey, "debuff")
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    self.previewMode[unitKey] = false

    if not InCombatLockdown() then
        local unit = QUI_UF.GetFrameUnit(frame)
        if unit == "target" then
            RegisterStateDriver(frame, "visibility", "[@target,exists] show; hide")
        elseif unit == "focus" then
            RegisterStateDriver(frame, "visibility", "[@focus,exists] show; hide")
        elseif unit == "pet" then
            RegisterStateDriver(frame, "visibility", "[@pet,exists] show; hide")
        elseif unit == "targettarget" then
            RegisterStateDriver(frame, "visibility", "[@targettarget,exists] show; hide")
        end
    end

    if frame.classificationIcon then
        frame.classificationIcon:Hide()
    end

    if UnitExists(QUI_UF.GetFrameUnit(frame)) or unitKey == "player" then
        UpdateFrame(frame)
        frame:Show()
    else
        frame:Hide()
    end
end

function QUI_UF:RefreshFrame(unitKey)
    if unitKey == "boss" then
        local settings = GetUnitSettings("boss")
        local general = GetGeneralSettings()
        local bossGrowDirection, bossSpacingX, bossSpacingY = GetBossLayoutSettings(settings)

        if not settings or (InCombatLockdown() and not inInitSafeWindow) then
            for i = 1, 5 do
                local frame = self.frames["boss" .. i]
                if frame then UpdateFrame(frame) end
            end
            RefreshBossRangeCheck()
            return
        end

        local borderPx = settings.borderSize or 1
        local texturePath = GetTexturePath(settings.texture)

        local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
        local bossLayerPriority = hudLayering and hudLayering.bossFrames or 4
        local bossFrameLevel
        if QUICore and QUICore.GetHUDFrameLevel then
            bossFrameLevel = QUICore:GetHUDFrameLevel(bossLayerPriority)
        end

        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                if bossFrameLevel then
                    frame:SetFrameLevel(bossFrameLevel)
                end

                local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0
                local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
                local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0

                local baseWidth = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
                local baseHeight = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
                local width, height = ResolveRefreshSize(frame, baseWidth, baseHeight)
                frame:SetSize(width, height)

                if i == 1 then
                    if not IsFrameOverridden(frame) then
                        frame:ClearAllPoints()
                        if QUICore.SetSnappedPoint then
                            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
                        else
                            frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
                        end
                    end
                else
                    local prevFrame = self.frames["boss" .. (i - 1)]
                    if prevFrame then
                        AnchorBossFrameToPrevious(frame, prevFrame, bossGrowDirection, bossSpacingX, bossSpacingY)
                    end
                end

                local bgColor, healthOpacity, bgOpacity
                if general and general.darkMode then
                    bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
                    healthOpacity = general.darkModeHealthOpacity or general.darkModeOpacity or 1.0
                    bgOpacity = general.darkModeBgOpacity or general.darkModeOpacity or 1.0
                else
                    local skinBgR, skinBgG, skinBgB = 0.1, 0.1, 0.1
                    if Helpers and Helpers.GetSkinBgColor then skinBgR, skinBgG, skinBgB = Helpers.GetSkinBgColor() end
                    bgColor = general and general.defaultBgColor or { skinBgR, skinBgG, skinBgB, 0.9 }
                    healthOpacity = general and general.defaultHealthOpacity or general and general.defaultOpacity or 1.0
                    bgOpacity = general and general.defaultBgOpacity or general and general.defaultOpacity or 1.0
                end
                local bgAlpha = (bgColor[4] or 1) * bgOpacity

                frame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
                    edgeSize = borderSize > 0 and borderSize or nil,
                })
                Helpers.SetFrameBackdropColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
                if borderSize > 0 then
                    local skinBorderR, skinBorderG, skinBorderB, skinBorderA = 0, 0, 0, 1
                    if Helpers and Helpers.GetSkinBorderColor then skinBorderR, skinBorderG, skinBorderB, skinBorderA = Helpers.GetSkinBorderColor(settings, "") end
                    Helpers.SetFrameBackdropBorderColor(frame, skinBorderR, skinBorderG, skinBorderB, skinBorderA)
                end

                frame.healthBar:SetAlpha(healthOpacity)
                if frame.powerBar then frame.powerBar:SetAlpha(healthOpacity) end

                frame.healthBar:SetStatusBarTexture(texturePath)
                frame.healthBar:ClearAllPoints()
                frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
                frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
                CacheHealthBarExtents(frame, settings, width, height)

                if frame.powerBar then
                    if settings.showPowerBar then
                        frame.powerBar:SetStatusBarTexture(texturePath)
                        frame.powerBar:ClearAllPoints()
                        frame.powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
                        frame.powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
                        frame.powerBar:SetHeight(powerHeight)
                        frame.powerBar:Show()
                    else
                        frame.powerBar:Hide()
                    end
                end

                if frame.powerBarSeparator then
                    if settings.showPowerBar and settings.powerBarBorder ~= false then
                        frame.powerBarSeparator:Show()
                    else
                        frame.powerBarSeparator:Hide()
                    end
                end

                local bossNS = GetNameSettings(settings)
                if bossNS.showName then
                    if not frame.nameText then
                        local nameText = frame.healthBar:CreateFontString(nil, "OVERLAY")
                        nameText:SetShadowOffset(0, 0)
                        frame.nameText = nameText
                    end
                    Helpers.ApplyFontWithFallback(frame.nameText, GetFontPath(), bossNS.nameFontSize or 11, GetFontOutline())
                    local nameAnchorInfo = GetTextAnchorInfo(bossNS.nameAnchor or "LEFT")
                    local nameOffsetX = QUICore:PixelRound(bossNS.nameOffsetX or 4, frame.healthBar)
                    local nameOffsetY = QUICore:PixelRound(bossNS.nameOffsetY or 0, frame.healthBar)
                    frame.nameText:ClearAllPoints()
                    frame.nameText:SetPoint(nameAnchorInfo.point, frame.healthBar, nameAnchorInfo.point, nameOffsetX, nameOffsetY)
                    frame.nameText:SetJustifyH(nameAnchorInfo.justify)
                    frame.nameText:Show()
                    if self.previewMode[bossKey] then
                        frame.nameText:SetText(ns.L["Boss"] .. " " .. i)
                    else
                        UpdateName(frame)
                    end
                elseif frame.nameText then
                    frame.nameText:Hide()
                end

                if settings.showLevel == true then
                    if not frame.levelText then
                        local levelText = frame.healthBar:CreateFontString(nil, "OVERLAY")
                        levelText:SetShadowOffset(0, 0)
                        frame.levelText = levelText
                    end
                    Helpers.ApplyFontWithFallback(frame.levelText, ResolveTextFont(settings.levelFont, GetFontPath()), settings.levelFontSize or 11, GetFontOutline())
                    local levelAnchorInfo = GetTextAnchorInfo(settings.levelAnchor or "RIGHT")
                    local levelOffsetX = QUICore:PixelRound(settings.levelOffsetX or -4, frame.healthBar)
                    local levelOffsetY = QUICore:PixelRound(settings.levelOffsetY or 0, frame.healthBar)
                    frame.levelText:ClearAllPoints()
                    frame.levelText:SetPoint(levelAnchorInfo.point, frame.healthBar, levelAnchorInfo.point, levelOffsetX, levelOffsetY)
                    frame.levelText:SetJustifyH(levelAnchorInfo.justify)
                    if self.previewMode[bossKey] then
                        frame.levelText:SetText("??")
                        local c = settings.levelTextColor or { 1, 1, 1, 1 }
                        frame.levelText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                        frame.levelText:Show()
                    else
                        UpdateLevelText(frame)
                    end
                elseif frame.levelText then
                    frame.levelText:Hide()
                end

                if settings.showHealth then
                    if not frame.healthText then
                        local healthText = frame.healthBar:CreateFontString(nil, "OVERLAY")
                        healthText:SetShadowOffset(0, 0)
                        frame.healthText = healthText
                    end
                    CJKFont(frame.healthText, GetFontPath(), settings.healthFontSize or 11, GetFontOutline())
                    local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
                    local healthOffsetX = QUICore:PixelRound(settings.healthOffsetX or -4, frame.healthBar)
                    local healthOffsetY = QUICore:PixelRound(settings.healthOffsetY or 0, frame.healthBar)
                    frame.healthText:ClearAllPoints()
                    frame.healthText:SetPoint(healthAnchorInfo.point, frame.healthBar, healthAnchorInfo.point, healthOffsetX, healthOffsetY)
                    frame.healthText:SetJustifyH(healthAnchorInfo.justify)
                    frame.healthText:Show()
                    if self.previewMode[bossKey] then
                        local previewHPPct = 75 - (i * 5)
                        local previewMaxHP = 100000
                        local previewHP = math_floor(previewMaxHP * (previewHPPct / 100))
                        frame.healthText:SetText(FormatHealthText(
                            previewHP,
                            previewHPPct,
                            settings.healthDisplayStyle or "both",
                            settings.healthDivider or " | ",
                            previewMaxHP,
                            settings.hideHealthPercentSymbol == true
                        ))
                    else
                        UpdateHealth(frame)
                    end
                elseif frame.healthText then
                    frame.healthText:Hide()
                end

                if settings.showPowerText then
                    if not frame.powerText then
                        local powerText = frame.healthBar:CreateFontString(nil, "OVERLAY")
                        powerText:SetShadowOffset(0, 0)
                        frame.powerText = powerText
                    end
                    local fontPath = GetFontPath()
                    local fontOutline = GetFontOutline()
                    CJKFont(frame.powerText, fontPath, settings.powerTextFontSize or 12, fontOutline)
                    frame.powerText:ClearAllPoints()
                    local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
                    local powerOffsetX = QUICore:PixelRound(settings.powerTextOffsetX or -4, frame.healthBar)
                    local powerOffsetY = QUICore:PixelRound(settings.powerTextOffsetY or 2, frame.healthBar)
                    frame.powerText:SetPoint(powerAnchorInfo.point, frame.healthBar, powerAnchorInfo.point, powerOffsetX, powerOffsetY)
                    frame.powerText:SetJustifyH(powerAnchorInfo.justify)
                    frame.powerText:Show()
                    if self.previewMode[bossKey] then
                        frame.powerText:SetText(FormatPowerText(
                            60,
                            60,
                            settings.powerTextFormat or "percent",
                            settings.healthDivider or " | ",
                            settings.hidePowerPercentSymbol == true
                        ))
                    else
                        UpdatePowerText(frame)
                    end
                elseif frame.powerText then
                    frame.powerText:Hide()
                end

                if frame.targetMarker and settings.targetMarker then
                    local marker = settings.targetMarker
                    frame.targetMarker:SetSize(marker.size or 20, marker.size or 20)
                    frame.targetMarker:ClearAllPoints()
                    local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
                    frame.targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
                    UpdateTargetMarker(frame)
                end

                if settings.classificationIcon and settings.classificationIcon.enabled then
                    if not frame.classificationIcon then
                        if not frame.indicatorFrame then
                            local indicatorFrame = CreateFrame("Frame", nil, frame)
                            indicatorFrame:SetAllPoints()
                            indicatorFrame:SetFrameLevel(frame.healthBar:GetFrameLevel() + 5)
                            frame.indicatorFrame = indicatorFrame
                        end
                        local classificationIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
                        classificationIcon:Hide()
                        frame.classificationIcon = classificationIcon
                        frame:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", QUI_UF.GetFrameUnit(frame))
                    end
                    local ci = settings.classificationIcon
                    frame.classificationIcon:SetSize(ci.size or 16, ci.size or 16)
                    frame.classificationIcon:ClearAllPoints()
                    local anchorInfo = GetTextAnchorInfo(ci.anchor or "LEFT")
                    frame.classificationIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, ci.xOffset or -8, ci.yOffset or 0)
                    if self.previewMode[bossKey] then
                        local data = ns.Classification and ns.Classification.DATA["elite"]
                        if data then
                            frame.classificationIcon:SetAtlas(data.atlas)
                            frame.classificationIcon:SetVertexColor(data.color[1], data.color[2], data.color[3])
                            frame.classificationIcon:Show()
                        end
                    else
                        UpdateClassificationIcon(frame)
                    end
                elseif frame.classificationIcon then
                    frame.classificationIcon:Hide()
                end

                if not self.previewMode[bossKey] then
                    UpdateFrame(frame)
                end

                local castbar = self.castbars[bossKey]
                if castbar and QUI_Castbar and QUI_Castbar.RefreshBossCastbar then
                    local castSettings = settings.castbar
                    if castSettings then
                        QUI_Castbar:RefreshBossCastbar(castbar, bossKey, castSettings, frame)
                    end
                end

            end
        end
        RefreshBossRangeCheck()
        return
    end

    local frame = self.frames[unitKey]
    if not frame then
        if unitKey == "player" then
            ApplyStandalonePlayerCastbarMode()
        end
        return
    end

    if InCombatLockdown() and not inInitSafeWindow then
        UpdateFrame(frame)
        ApplyExistingCastbarLiveSettings(unitKey)
        return
    end

    local settings = GetUnitSettings(unitKey)
    local general = GetGeneralSettings()
    if not settings then return end

    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority
    if unitKey == "player" then
        layerPriority = hudLayering and hudLayering.playerFrame or 4
    elseif unitKey == "target" then
        layerPriority = hudLayering and hudLayering.targetFrame or 4
    elseif unitKey == "targettarget" then
        layerPriority = hudLayering and hudLayering.totFrame or 3
    elseif unitKey == "pet" then
        layerPriority = hudLayering and hudLayering.petFrame or 3
    elseif unitKey == "focus" then
        layerPriority = hudLayering and hudLayering.focusFrame or 4
    else
        layerPriority = 4
    end
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        frame:SetFrameLevel(frameLevel)
    end

    local baseWidth = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
    local baseHeight = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
    local width, height = ResolveRefreshSize(frame, baseWidth, baseHeight)
    frame:SetSize(width, height)

    if not IsFrameOverridden(frame) then
        frame:ClearAllPoints()
        local isAnchored = settings.anchorTo and settings.anchorTo ~= "disabled"
        if isAnchored and (unitKey == "player" or unitKey == "target") then
            _G.QUI_UpdateAnchoredUnitFrames()
        else
            if QUICore.SetSnappedPoint then
                QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
            else
                frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
            end
        end
    end

    local bgColor, healthOpacity, bgOpacity
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
        healthOpacity = general.darkModeHealthOpacity or general.darkModeOpacity or 1.0
        bgOpacity = general.darkModeBgOpacity or general.darkModeOpacity or 1.0
    else
        local skinBgR, skinBgG, skinBgB = 0.1, 0.1, 0.1
        if Helpers and Helpers.GetSkinBgColor then skinBgR, skinBgG, skinBgB = Helpers.GetSkinBgColor() end
        bgColor = general and general.defaultBgColor or { skinBgR, skinBgG, skinBgB, 0.9 }
        healthOpacity = general and general.defaultHealthOpacity or general and general.defaultOpacity or 1.0
        bgOpacity = general and general.defaultBgOpacity or general and general.defaultOpacity or 1.0
    end
    if settings and settings.useClassColorBg and QUI_UF.GetFrameUnit(frame) and UnitIsPlayer(QUI_UF.GetFrameUnit(frame)) then
        local cr, cg, cb = GetUnitClassColor(QUI_UF.GetFrameUnit(frame))
        if cr then bgColor = { cr, cg, cb, bgColor[4] or 1 } end
    end
    local bgAlpha = (bgColor[4] or 1) * bgOpacity

    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    Helpers.SetFrameBackdropColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
    if borderSize > 0 then
        local skinBorderR, skinBorderG, skinBorderB, skinBorderA = 0, 0, 0, 1
        if Helpers and Helpers.GetSkinBorderColor then skinBorderR, skinBorderG, skinBorderB, skinBorderA = Helpers.GetSkinBorderColor(settings, "") end
        Helpers.SetFrameBackdropBorderColor(frame, skinBorderR, skinBorderG, skinBorderB, skinBorderA)
    end

    frame.healthBar:SetAlpha(healthOpacity)
    if frame.powerBar then frame.powerBar:SetAlpha(healthOpacity) end

    local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
    local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0

    local texturePath = GetTexturePath(settings.texture)
    frame.healthBar:SetStatusBarTexture(texturePath)

    frame.healthBar:ClearAllPoints()
    frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    CacheHealthBarExtents(frame, settings, width, height)

    if settings.showPowerBar then
        if not frame.powerBar then
            local powerBar = CreateFrame("StatusBar", nil, frame)
            powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
            powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
            powerBar:SetHeight(powerHeight)
            powerBar:SetStatusBarTexture(texturePath)
            powerBar:SetMinMaxValues(0, 100)
            powerBar:SetValue(100)
            local powerColor = settings.powerBarColor or { 0, 0.5, 1, 1 }
            powerBar:SetStatusBarColor(powerColor[1], powerColor[2], powerColor[3], powerColor[4] or 1)
            powerBar:EnableMouse(false)
            frame.powerBar = powerBar
        end
        frame.powerBar:SetStatusBarTexture(texturePath)
        frame.powerBar:ClearAllPoints()
        frame.powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        frame.powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        frame.powerBar:SetHeight(powerHeight)
        frame.powerBar:Show()
    elseif frame.powerBar then
        frame.powerBar:Hide()
    end

    if settings.showPowerBar and settings.powerBarBorder ~= false then
        if not frame.powerBarSeparator then
            local separator = frame.powerBar:CreateTexture(nil, "OVERLAY")
            separator:SetHeight(QUICore:GetPixelSize(frame.powerBar))
            separator:SetPoint("BOTTOMLEFT", frame.powerBar, "TOPLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", frame.powerBar, "TOPRIGHT", 0, 0)
            separator:SetTexture("Interface\\Buttons\\WHITE8x8")
            separator:SetVertexColor(0, 0, 0, 1)
            frame.powerBarSeparator = separator
        end
        frame.powerBarSeparator:Show()
    elseif frame.powerBarSeparator then
        frame.powerBarSeparator:Hide()
    end

    if settings.showPortrait then
        local portraitSizePx = settings.portraitSize or 40
        local side = settings.portraitSide or "LEFT"

        if not frame.portrait then
            local portrait = CreateFrame("Button", nil, frame, "SecureUnitButtonTemplate, BackdropTemplate")
            local portraitTex = portrait:CreateTexture(nil, "ARTWORK")
            frame.portraitTexture = portraitTex
            frame.portrait = portrait

            portrait:SetAttribute("unit", QUI_UF.GetFrameUnit(frame))
            portrait:SetAttribute("*type1", "target")
            portrait:SetAttribute("*type2", "togglemenu")
            portrait:RegisterForClicks("AnyUp")

            portrait:HookScript("OnEnter", function(self)
                ShowUnitTooltip(frame)
            end)
            portrait:HookScript("OnLeave", HideUnitTooltip)
        end

        local portraitBorderSize = QUICore:Pixels(settings.portraitBorderSize or 1, frame.portrait)
        local portraitGap = QUICore:PixelRound(settings.portraitGap or 0, frame.portrait)
        local portraitOffsetX = QUICore:PixelRound(settings.portraitOffsetX or 0, frame.portrait)
        local portraitOffsetY = QUICore:PixelRound(settings.portraitOffsetY or 0, frame.portrait)

        frame.portrait:SetSize(QUICore:PixelRound(portraitSizePx, frame.portrait), QUICore:PixelRound(portraitSizePx, frame.portrait))
        frame.portrait:ClearAllPoints()
        if side == "LEFT" then
            frame.portrait:SetPoint("RIGHT", frame, "LEFT", -portraitGap + portraitOffsetX, portraitOffsetY)
        else
            frame.portrait:SetPoint("LEFT", frame, "RIGHT", portraitGap + portraitOffsetX, portraitOffsetY)
        end

        local borderR, borderG, borderB, borderA = Helpers.GetSkinBorderColor(settings, "portrait")

        frame.portrait:SetBackdrop({
            bgFile = nil,
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = portraitBorderSize,
        })
        frame.portrait:SetBackdropBorderColor(borderR, borderG, borderB, borderA)

        frame.portraitTexture:ClearAllPoints()
        frame.portraitTexture:SetPoint("TOPLEFT", portraitBorderSize, -portraitBorderSize)
        frame.portraitTexture:SetPoint("BOTTOMRIGHT", -portraitBorderSize, portraitBorderSize)

        if UnitExists(QUI_UF.GetFrameUnit(frame)) then
            SetPortraitTexture(frame.portraitTexture, QUI_UF.GetFrameUnit(frame), true)
            frame.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
        end

        frame.portrait:Show()
    elseif frame.portrait then
        frame.portrait:Hide()
    end

    local fontPath = GetFontPath()
    local fontOutline = general and general.fontOutline or "OUTLINE"

    local refreshNameSettings = GetNameSettings(settings)
    if frame.nameText then
        Helpers.ApplyFontWithFallback(frame.nameText, fontPath, refreshNameSettings.nameFontSize or 12, fontOutline)
        frame.nameText:ClearAllPoints()
        local nameAnchorInfo = GetTextAnchorInfo(refreshNameSettings.nameAnchor or "LEFT")
        frame.nameText:SetPoint(nameAnchorInfo.point, frame, nameAnchorInfo.point, QUICore:PixelRound(refreshNameSettings.nameOffsetX or 4, frame), QUICore:PixelRound(refreshNameSettings.nameOffsetY or 0, frame))
        frame.nameText:SetJustifyH(nameAnchorInfo.justify)
        if refreshNameSettings.showName then
            frame.nameText:Show()
        else
            frame.nameText:Hide()
        end
    end

    if frame.levelText then
        Helpers.ApplyFontWithFallback(frame.levelText, ResolveTextFont(settings.levelFont, fontPath), settings.levelFontSize or (refreshNameSettings.nameFontSize or 12), fontOutline)
        frame.levelText:ClearAllPoints()
        local levelAnchorInfo = GetTextAnchorInfo(settings.levelAnchor or "RIGHT")
        frame.levelText:SetPoint(levelAnchorInfo.point, frame, levelAnchorInfo.point, QUICore:PixelRound(settings.levelOffsetX or -4, frame), QUICore:PixelRound(settings.levelOffsetY or 0, frame))
        frame.levelText:SetJustifyH(levelAnchorInfo.justify)
        if settings.showLevel == true then
            frame.levelText:Show()
        else
            frame.levelText:Hide()
        end
    end

    if frame.healthText then
        CJKFont(frame.healthText, fontPath, settings.healthFontSize or 12, fontOutline)
        frame.healthText:ClearAllPoints()
        local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
        frame.healthText:SetPoint(healthAnchorInfo.point, frame, healthAnchorInfo.point, QUICore:PixelRound(settings.healthOffsetX or -4, frame), QUICore:PixelRound(settings.healthOffsetY or 0, frame))
        frame.healthText:SetJustifyH(healthAnchorInfo.justify)
        if settings.showHealth == false then
            frame.healthText:Hide()
        else
            local displayStyle = settings.healthDisplayStyle
            if displayStyle and displayStyle ~= "" then
                frame.healthText:Show()
            else
                local showAbsolute = settings.showHealthAbsolute
                local showPercent = settings.showHealthPercent
                if showAbsolute or showPercent then
                    frame.healthText:Show()
                else
                    frame.healthText:Hide()
                end
            end
        end
    end

    if frame.powerText then
        CJKFont(frame.powerText, fontPath, settings.powerTextFontSize or 12, fontOutline)
        frame.powerText:ClearAllPoints()
        local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
        frame.powerText:SetPoint(powerAnchorInfo.point, frame, powerAnchorInfo.point, QUICore:PixelRound(settings.powerTextOffsetX or -4, frame), QUICore:PixelRound(settings.powerTextOffsetY or 2, frame))
        frame.powerText:SetJustifyH(powerAnchorInfo.justify)
    end

    if unitKey == "player" and settings.indicators then
        local indSettings = settings.indicators

        if frame.restedIndicator and indSettings.rested then
            local rested = indSettings.rested
            frame.restedIndicator:SetSize(rested.size or 16, rested.size or 16)
            frame.restedIndicator:ClearAllPoints()
            local anchorInfo = GetTextAnchorInfo(rested.anchor or "TOPLEFT")
            frame.restedIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, rested.offsetX or -2, rested.offsetY or 2)
        end

        if frame.combatIndicator and indSettings.combat then
            local combat = indSettings.combat
            frame.combatIndicator:SetSize(combat.size or 16, combat.size or 16)
            frame.combatIndicator:ClearAllPoints()
            local anchorInfo = GetTextAnchorInfo(combat.anchor or "TOPLEFT")
            frame.combatIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, combat.offsetX or -2, combat.offsetY or 2)
        end

        if frame.stanceText then
            UpdateStance(frame)
        end

        if frame.indicatorFrame then
            local indicatorPriority = hudLayering and hudLayering.playerIndicators or 6
            if QUICore and QUICore.GetHUDFrameLevel then
                local indicatorLevel = QUICore:GetHUDFrameLevel(indicatorPriority)
                frame.indicatorFrame:SetFrameLevel(indicatorLevel)
            end
        end
    end

    if frame.targetMarker and settings.targetMarker then
        local marker = settings.targetMarker
        frame.targetMarker:SetSize(marker.size or 20, marker.size or 20)
        frame.targetMarker:ClearAllPoints()
        local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
        frame.targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
        UpdateTargetMarker(frame)
    end

    if settings.leaderIcon and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
        local leader = settings.leaderIcon
        if leader.enabled then
            if not frame.leaderIcon then
                if not frame.indicatorFrame then
                    local indicatorFrame = CreateFrame("Frame", nil, frame)
                    indicatorFrame:SetAllPoints()
                    indicatorFrame:SetFrameLevel(frame.textFrame and (frame.textFrame:GetFrameLevel() + 5) or (frame:GetFrameLevel() + 10))
                    frame.indicatorFrame = indicatorFrame
                end
                local leaderIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
                leaderIcon:Hide()
                frame.leaderIcon = leaderIcon
                frame:RegisterEvent("PARTY_LEADER_CHANGED")
                frame:RegisterEvent("GROUP_ROSTER_UPDATE")
            end
            frame.leaderIcon:SetSize(leader.size or 16, leader.size or 16)
            frame.leaderIcon:ClearAllPoints()
            local anchorInfo = GetTextAnchorInfo(leader.anchor or "TOPLEFT")
            frame.leaderIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, leader.xOffset or -8, leader.yOffset or 8)
            UpdateLeaderIcon(frame)
        elseif frame.leaderIcon then
            frame.leaderIcon:Hide()
        end
    end

    if settings.classificationIcon and (unitKey == "target" or unitKey == "focus" or unitKey:match("^boss%d+$") or unitKey == "boss") then
        local ci = settings.classificationIcon
        if ci.enabled then
            if not frame.classificationIcon then
                if not frame.indicatorFrame then
                    local indicatorFrame = CreateFrame("Frame", nil, frame)
                    indicatorFrame:SetAllPoints()
                    indicatorFrame:SetFrameLevel(frame.textFrame and (frame.textFrame:GetFrameLevel() + 5) or (frame:GetFrameLevel() + 10))
                    frame.indicatorFrame = indicatorFrame
                end
                local classificationIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
                classificationIcon:Hide()
                frame.classificationIcon = classificationIcon
                if unitKey == "target" or unitKey == "focus" then
                    frame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
                else
                    frame:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", QUI_UF.GetFrameUnit(frame))
                end
            end
            frame.classificationIcon:SetSize(ci.size or 16, ci.size or 16)
            frame.classificationIcon:ClearAllPoints()
            local anchorInfo = GetTextAnchorInfo(ci.anchor or "LEFT")
            frame.classificationIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, ci.xOffset or -8, ci.yOffset or 0)
            UpdateClassificationIcon(frame)
        elseif frame.classificationIcon then
            frame.classificationIcon:Hide()
        end
    end

    if self.previewMode[unitKey] then
        self:ShowPreview(unitKey)
    else
        UpdateFrame(frame)
    end

    local castbar = self.castbars[unitKey]
    local castSettings = settings.castbar
    if castSettings and castSettings.enabled then
        if castbar and QUI_Castbar and QUI_Castbar.RefreshCastbar then
            QUI_Castbar:RefreshCastbar(castbar, unitKey, castSettings, frame)
        elseif not castbar and QUI_Castbar and QUI_Castbar.CreateCastbar then
            self.castbars[unitKey] = QUI_Castbar:CreateCastbar(frame, unitKey, unitKey)
        end
    end

    if Helpers.IsEditModeActive() then
        if QUI_Castbar and QUI_Castbar.RestoreEditOverlaysIfNeeded then
            QUI_Castbar:RestoreEditOverlaysIfNeeded(unitKey)
        end
    end
end

function QUI_UF:UpdateBossFrameLayout()
    local settings = GetUnitSettings("boss")
    if not settings or (InCombatLockdown() and not inInitSafeWindow) then return end

    local direction, xSpacing, ySpacing = GetBossLayoutSettings(settings)
    for i = 2, 5 do
        local frame = self.frames and self.frames["boss" .. i]
        local previousFrame = self.frames and self.frames["boss" .. (i - 1)]
        AnchorBossFrameToPrevious(frame, previousFrame, direction, xSpacing, ySpacing)
    end
end

function QUI_UF:RefreshAll()
    local bossRefreshed = false

    for unitKey, frame in pairs(self.frames) do
        if unitKey:match("^boss%d+$") then
            if not bossRefreshed then
                self:RefreshFrame("boss")
                bossRefreshed = true
            end
        else
            self:RefreshFrame(unitKey)
        end
    end

    for unitKey, castbar in pairs(self.castbars) do
        if castbar and not self.frames[unitKey] then
            self:RefreshFrame(unitKey)
        end
    end
end

function QUI_UF:Initialize()
    inInitSafeWindow = true

    local db = GetDB()
    if not db then inInitSafeWindow = false return end

    if QUI_Castbar then
        QUI_Castbar:SetHelpers({
            GetUnitSettings = GetUnitSettings,
            Scale = Scale,
            GetFontPath = GetFontPath,
            GetFontOutline = GetFontOutline,
            GetTexturePath = GetTexturePath,
            GetUnitClassColor = GetUnitClassColor,
            TruncateName = TruncateName,
            GetGeneralSettings = GetGeneralSettings,
            GetDB = GetDB,
        })
        QUI_Castbar:SetUnitFramesModule(self)
        QUI_Castbar.castbars = self.castbars
    end

    ApplyStandalonePlayerCastbarMode()

    self:HideBlizzardFrames()

    if db.player and db.player.enabled then
        self.frames.player = CreateUnitFrame("player", "player")
        if db.player.castbar and db.player.castbar.enabled then
            self.castbars.player = CreateCastbar(self.frames.player, "player", "player")
        end
        QUI_UF.SetupAuraTracking(self.frames.player)
    end

    if db.target and db.target.enabled then
        self.frames.target = CreateUnitFrame("target", "target")
        if db.target.castbar and db.target.castbar.enabled then
            self.castbars.target = CreateCastbar(self.frames.target, "target", "target")
        end
        QUI_UF.SetupAuraTracking(self.frames.target)
    end

    if db.targettarget and db.targettarget.enabled then
        self.frames.targettarget = CreateUnitFrame("targettarget", "targettarget")
        if db.targettarget.castbar and db.targettarget.castbar.enabled then
            self.castbars.targettarget = CreateCastbar(self.frames.targettarget, "targettarget", "targettarget")
        end
        QUI_UF.SetupAuraTracking(self.frames.targettarget)
    end

    if db.pet and db.pet.enabled then
        self.frames.pet = CreateUnitFrame("pet", "pet")
        if db.pet.castbar and db.pet.castbar.enabled then
            self.castbars.pet = CreateCastbar(self.frames.pet, "pet", "pet")
        end
        QUI_UF.SetupAuraTracking(self.frames.pet)
    end

    if db.focus and db.focus.enabled then
        self.frames.focus = CreateUnitFrame("focus", "focus")
        if db.focus.castbar and db.focus.castbar.enabled then
            self.castbars.focus = CreateCastbar(self.frames.focus, "focus", "focus")
        end
        QUI_UF.SetupAuraTracking(self.frames.focus)
    end

    if db.boss and db.boss.enabled then
        local bossGrowDirection, bossSpacingX, bossSpacingY = GetBossLayoutSettings(db.boss)
        for i = 1, 5 do
            local bossUnit = "boss" .. i
            local bossKey = "boss" .. i
            self.frames[bossKey] = CreateBossFrame(bossUnit, bossKey, i)

            if self.frames[bossKey] and i > 1 and not IsFrameOverridden(self.frames[bossKey]) then
                local prevFrame = self.frames["boss" .. (i - 1)]
                AnchorBossFrameToPrevious(self.frames[bossKey], prevFrame, bossGrowDirection, bossSpacingX, bossSpacingY)
            end

            if self.frames[bossKey] and db.boss.castbar and db.boss.castbar.enabled then
                self.castbars[bossKey] = CreateBossCastbar(self.frames[bossKey], bossUnit, i)
            end

            QUI_UF.SetupAuraTracking(self.frames[bossKey])
        end

        local bossTargetEventFrame = CreateFrame("Frame")
        bossTargetEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        bossTargetEventFrame:SetScript("OnEvent", function()
            UpdateBossTargetHighlight()
        end)

        RefreshBossRangeCheck()
    end

    C_Timer.After(1.5, function() self:RefreshAll() end)

    if _G.QUI_ShouldUnitframesBeVisible and not _G.QUI_ShouldUnitframesBeVisible() then
        local core = GetCore()
        local vis = core and core.db and core.db.profile and core.db.profile.unitframesVisibility
        local alpha = vis and vis.fadeOutAlpha or 0
        for _, frame in pairs(self.frames) do
            if frame then frame:SetAlpha(alpha) end
        end
        for _, castbar in pairs(self.castbars) do
            if castbar then castbar:SetAlpha(alpha) end
        end
    end
    if _G.QUI_RefreshUnitframesVisibility then
        _G.QUI_RefreshUnitframesVisibility()
    end

    inInitSafeWindow = false
end

function QUI_UF:RegisterWithClique()
    local _, cliqueLoaded = C_AddOns.IsAddOnLoaded("Clique")
    if not cliqueLoaded then return end

    _G.ClickCastFrames = _G.ClickCastFrames or {}

    for unitKey, frame in pairs(self.frames) do
        if frame and frame.GetName then
            _G.ClickCastFrames[frame] = true
        end
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        QUI_UF:Initialize()
        QUI_UF:HookBlizzardEditMode()
        C_Timer.After(0.5, function()
            QUI_UF:RegisterWithClique()
            local GFCC = ns.QUI_GroupFrameClickCast
            if GFCC then
                if not GFCC:IsEnabled() then
                    GFCC:Initialize()
                end
                if GFCC:IsEnabled() then
                    GFCC:RegisterUnitFrames()
                end
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        QUI_UF:HideBlizzardCastbars()
        if _G.QUI_ShouldUnitframesBeVisible and not _G.QUI_ShouldUnitframesBeVisible() then
            local core = GetCore()
            local vis = core and core.db and core.db.profile and core.db.profile.unitframesVisibility
            local alpha = vis and vis.fadeOutAlpha or 0
            for _, frame in pairs(QUI_UF.frames) do
                if frame then frame:SetAlpha(alpha) end
            end
            for _, castbar in pairs(QUI_UF.castbars) do
                if castbar then castbar:SetAlpha(alpha) end
            end
        end
        C_Timer.After(1.0, function()
            QUI_UF:RefreshAll()
        end)
    end
end)

_G.QUI_RefreshUnitFrames = function()
    QUI_UF:RefreshAll()
end

_G.QUI_RefreshAuras = function(unitKey)
    if unitKey then
        if unitKey == "boss" then
            for i = 1, 5 do
                local bossKey = "boss" .. i
                local frame = QUI_UF.frames[bossKey]
                if frame then
                    QUI_UF.UpdateAuras(frame)
                end
            end
        else
            local frame = QUI_UF.frames[unitKey]
            if frame then
                QUI_UF.UpdateAuras(frame)
            end
        end
    else
        for _, key in ipairs({"player", "target", "focus", "pet", "targettarget"}) do
            local frame = QUI_UF.frames[key]
            if frame then
                QUI_UF.UpdateAuras(frame)
            end
        end
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = QUI_UF.frames[bossKey]
            if frame then
                QUI_UF.UpdateAuras(frame)
            end
        end
    end
end

_G.QUI_ShowUnitFramePreview = function(unitKey)
    QUI_UF:ShowPreview(unitKey)
end

_G.QUI_HideUnitFramePreview = function(unitKey)
    QUI_UF:HidePreview(unitKey)
end

_G.QUI_ShowAuraPreview = function(unitKey, auraType)
    QUI_UF:ShowAuraPreview(unitKey, auraType)
end

_G.QUI_HideAuraPreview = function(unitKey, auraType)
    QUI_UF:HideAuraPreview(unitKey, auraType)
end

_G.QUI_ToggleStandaloneCastbar = function()
    return ApplyStandalonePlayerCastbarMode()
end

_G.QUI_UnitFrames = QUI_UF.frames
_G.QUI_Castbars = QUI_UF.castbars

local function GetAnchorFrame(anchorType)
    if anchorType == "essential" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
    elseif anchorType == "utility" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
    elseif anchorType == "primary" then
        local core = GetCore()
        return core and core.powerBar
    elseif anchorType == "secondary" then
        local core = GetCore()
        return core and core.secondaryPowerBar
    end
    return nil
end

local function GetAnchorDimensions(anchorFrame, anchorType)
    if not anchorFrame then return nil end

    local width, height
    if anchorType == "essential" or anchorType == "utility" then
        local actualViewer = GetAnchorFrame(anchorType)
        local afvs = actualViewer and _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(actualViewer)
        width = (afvs and afvs.row1Width) or anchorFrame:GetWidth()
        height = (afvs and afvs.totalHeight) or anchorFrame:GetHeight()
    else
        width = anchorFrame:GetWidth()
        height = anchorFrame:GetHeight()
    end

    local centerX, centerY = anchorFrame:GetCenter()
    if not centerX or not centerY then return nil end

    return {
        width = width,
        height = height,
        centerX = centerX,
        centerY = centerY,
        top = centerY + (height / 2),
        left = centerX - (width / 2),
        right = centerX + (width / 2),
    }
end

_G.QUI_UpdateAnchoredUnitFrames = function()
    if InCombatLockdown() then return end
    local db = GetDB()
    if not db then return end

    local playerSettings = db.player
    local playerAnchorType = playerSettings and playerSettings.anchorTo
    if playerAnchorType and playerAnchorType ~= "disabled" and QUI_UF.frames.player and not IsFrameOverridden(QUI_UF.frames.player) then
        local anchorFrame = GetAnchorFrame(playerAnchorType)
        if anchorFrame and anchorFrame:IsShown() then
            local anchor = GetAnchorDimensions(anchorFrame, playerAnchorType)
            if anchor then
                local frame = QUI_UF.frames.player
                local frameHeight = frame:GetHeight()
                local gap = QUICore:PixelRound(playerSettings.anchorGap or 10, frame)
                local yOffset = QUICore:PixelRound(playerSettings.anchorYOffset or 0, frame)

                local yShift = (anchor.height / 2) - (frameHeight / 2) + yOffset

                frame:ClearAllPoints()
                frame:SetPoint("RIGHT", anchorFrame, "LEFT", -gap, yShift)
            end
        else
            local frame = QUI_UF.frames.player
            frame:ClearAllPoints()
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER",
                playerSettings.offsetX or 0,
                playerSettings.offsetY or 0)
        end
    end

    local targetSettings = db.target
    local targetAnchorType = targetSettings and targetSettings.anchorTo
    if targetAnchorType and targetAnchorType ~= "disabled" and QUI_UF.frames.target and not IsFrameOverridden(QUI_UF.frames.target) then
        local anchorFrame = GetAnchorFrame(targetAnchorType)
        if anchorFrame and anchorFrame:IsShown() then
            local anchor = GetAnchorDimensions(anchorFrame, targetAnchorType)
            if anchor then
                local frame = QUI_UF.frames.target
                local frameHeight = frame:GetHeight()
                local gap = QUICore:PixelRound(targetSettings.anchorGap or 10, frame)
                local yOffset = QUICore:PixelRound(targetSettings.anchorYOffset or 0, frame)

                local yShift = (anchor.height / 2) - (frameHeight / 2) + yOffset

                frame:ClearAllPoints()
                frame:SetPoint("LEFT", anchorFrame, "RIGHT", gap, yShift)
            end
        else
            local frame = QUI_UF.frames.target
            frame:ClearAllPoints()
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER",
                targetSettings.offsetX or 0,
                targetSettings.offsetY or 0)
        end
    end
end

_G.QUI_UpdateCDMAnchoredUnitFrames = _G.QUI_UpdateAnchoredUnitFrames

_G.QUI_UpdateLockedCastbarToEssential = function(forceUpdate)
    local db = GetDB()
    if not db or not db.player then return end

    local castDB = db.player.castbar
    if not castDB or castDB.anchor ~= "essential" then return end

    if _G.QUI_RefreshCastbar then
        _G.QUI_RefreshCastbar("player")
    end
end

_G.QUI_UpdateLockedCastbarToUtility = function(forceUpdate)
    local db = GetDB()
    if not db or not db.player then return end

    local castDB = db.player.castbar
    if not castDB or castDB.anchor ~= "utility" then return end

    if _G.QUI_RefreshCastbar then
        _G.QUI_RefreshCastbar("player")
    end
end

_G.QUI_UpdateLockedCastbarToFrame = function()
    local db = GetDB()
    if not db or not db.player then return end

    local castDB = db.player.castbar
    if not castDB or castDB.anchor ~= "unitframe" then return end

    if _G.QUI_RefreshCastbar then
        _G.QUI_RefreshCastbar("player")
    end
end

do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local UNIT_KEYS = {
            { key = "playerFrame", label = ns.L["Player Frame"],       unit = "player",       order = 1 },
            { key = "targetFrame", label = ns.L["Target Frame"],       unit = "target",       order = 2 },
            { key = "totFrame",    label = ns.L["Target of Target"],   unit = "targettarget", order = 3 },
            { key = "focusFrame",  label = ns.L["Focus Frame"],        unit = "focus",        order = 4 },
            { key = "petFrame",    label = ns.L["Pet Frame"],          unit = "pet",          order = 5 },
        }

        local function GetUFDB()
            local core = ns.Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.quiUnitFrames
        end

        local function RefreshUF()
            if _G.QUI_RefreshUnitframesVisibility then _G.QUI_RefreshUnitframesVisibility() end
        end

        for _, info in ipairs(UNIT_KEYS) do
            um:RegisterElement({
                key = info.key,
                label = info.label,
                group = ns.L["Unit Frames"],
                order = info.order,
                isOwned = true,
                isEnabled = function()
                    local ufdb = GetUFDB()
                    if not ufdb then return false end
                    return ufdb[info.unit] and ufdb[info.unit].enabled ~= false
                end,
                setEnabled = function(val)
                    local ufdb = GetUFDB()
                    if not ufdb or not ufdb[info.unit] then return end
                    local old = ufdb[info.unit].enabled ~= false
                    ufdb[info.unit].enabled = val
                    RefreshUF()
                    if (val ~= false) ~= old then
                        local QUI = _G.QUI
                        local GUI = QUI and QUI.GUI
                        if GUI and GUI.ShowConfirmation then
                            GUI:ShowConfirmation({
                                title = "Reload UI?",
                                message = "Enabling or disabling unit frames requires a UI reload to take effect.",
                                acceptText = "Reload",
                                cancelText = "Later",
                                onAccept = function() QUI:SafeReload() end,
                            })
                        end
                    end
                end,
                setGameplayHidden = function(hide)
                    local f = QUI_UF.frames and QUI_UF.frames[info.unit]
                    if not f then return end
                    if hide then
                        f:SetAlpha(0)
                        f:EnableMouse(false)
                    else
                        f:SetAlpha(1)
                        f:EnableMouse(true)
                    end
                end,
                getFrame = function()
                    return QUI_UF.frames and QUI_UF.frames[info.unit]
                end,
                onOpen = function()
                    if _G.QUI_ShowUnitFramePreview then _G.QUI_ShowUnitFramePreview(info.unit) end
                end,
                onClose = function()
                    if _G.QUI_HideUnitFramePreview then _G.QUI_HideUnitFramePreview(info.unit) end
                end,
            })
        end

        um:RegisterElement({
            key = "bossFrames",
            label = ns.L["Boss Frames"],
            group = ns.L["Unit Frames"],
            order = 10,
            isOwned = true,
            isEnabled = function()
                local ufdb = GetUFDB()
                if not ufdb then return false end
                return ufdb.boss and ufdb.boss.enabled ~= false
            end,
            setEnabled = function(val)
                local ufdb = GetUFDB()
                if not ufdb or not ufdb.boss then return end
                local old = ufdb.boss.enabled ~= false
                ufdb.boss.enabled = val
                RefreshUF()
                if (val ~= false) ~= old then
                    local QUI = _G.QUI
                    local GUI = QUI and QUI.GUI
                    if GUI and GUI.ShowConfirmation then
                        GUI:ShowConfirmation({
                            title = "Reload UI?",
                            message = "Enabling or disabling unit frames requires a UI reload to take effect.",
                            acceptText = "Reload",
                            cancelText = "Later",
                            onAccept = function() QUI:SafeReload() end,
                        })
                    end
                end
            end,
            getFrame = function()
                return QUI_UF.frames and QUI_UF.frames.boss1
            end,
            getSize = function()
                if not QUI_UF.frames or not QUI_UF.frames.boss1 then return nil end
                local left, right, top, bottom = ComputeBossExtent()
                if not left or not right or not top or not bottom then return nil end
                return right - left, top - bottom
            end,
            getCenterOffset = function()
                if not QUI_UF.frames or not QUI_UF.frames.boss1 then return 0, 0 end
                local boss1 = QUI_UF.frames.boss1
                local boss1CX, boss1CY = boss1:GetCenter()
                if not boss1CX or not boss1CY then return 0, 0 end
                local left, right, top, bottom = ComputeBossExtent()
                if not left or not right or not top or not bottom then return 0, 0 end
                return ((left + right) / 2) - boss1CX, ((top + bottom) / 2) - boss1CY
            end,
            setGameplayHidden = function(hide)
                for i = 1, 5 do
                    local f = QUI_UF.frames and QUI_UF.frames["boss" .. i]
                    if f then
                        if hide then
                            f:SetAlpha(0)
                            f:EnableMouse(false)
                        else
                            f:SetAlpha(1)
                            f:EnableMouse(true)
                        end
                    end
                end
            end,
            onOpen = function()
                if _G.QUI_ShowUnitFramePreview then _G.QUI_ShowUnitFramePreview("boss") end
            end,
            onClose = function()
                if _G.QUI_HideUnitFramePreview then _G.QUI_HideUnitFramePreview("boss") end
            end,
        })
    end

    C_Timer.After(2, RegisterLayoutModeElements)
end

if Helpers and Helpers.BorderRegistry then
    local CASTBAR_UNITS = { "player", "target", "targettarget", "pet", "focus", "boss" }
    local PORTRAIT_UNITS = { "player", "target", "focus" }

    local function CollectCastbars(profile)
        local out = {}
        local uf = profile and profile.quiUnitFrames
        if type(uf) ~= "table" then return out end
        for _, unit in ipairs(CASTBAR_UNITS) do
            local u = uf[unit]
            if type(u) == "table" and type(u.castbar) == "table" then
                out[#out + 1] = u.castbar
            end
        end
        return out
    end

    local function CollectPortraitUnits(profile)
        local out = {}
        local uf = profile and profile.quiUnitFrames
        if type(uf) ~= "table" then return out end
        for _, unit in ipairs(PORTRAIT_UNITS) do
            local u = uf[unit]
            if type(u) == "table" then
                out[#out + 1] = u
            end
        end
        return out
    end

    local FRAME_UNITS = { "player", "target", "targettarget", "pet", "focus", "boss" }
    local function CollectFrameUnits(profile)
        local out = {}
        local uf = profile and profile.quiUnitFrames
        if type(uf) ~= "table" then return out end
        for _, unit in ipairs(FRAME_UNITS) do
            local u = uf[unit]
            if type(u) == "table" then out[#out + 1] = u end
        end
        return out
    end

    Helpers.BorderRegistry.Register({
        key       = "castbar",
        label     = "Castbar",
        category  = "Unit Frames",
        prefix    = "",
        multi     = true,
        db        = function(p) local i = CollectCastbars(p); return i and i[1] end,
        instances = CollectCastbars,
        refresh   = _G.QUI_RefreshUnitFrames,
        legacy    = {},
    })

    Helpers.BorderRegistry.Register({
        key       = "castbarIcon",
        label     = "Castbar Icon",
        category  = "Unit Frames",
        prefix    = "icon",
        multi     = true,
        db        = function(p) local i = CollectCastbars(p); return i and i[1] end,
        instances = CollectCastbars,
        refresh   = _G.QUI_RefreshUnitFrames,
        legacy    = {},
    })

    Helpers.BorderRegistry.Register({
        key       = "portrait",
        label     = "Portrait Ring",
        category  = "Unit Frames",
        prefix    = "portrait",
        multi     = true,
        db        = function(p) local i = CollectPortraitUnits(p); return i and i[1] end,
        instances = CollectPortraitUnits,
        refresh   = _G.QUI_RefreshUnitFrames,
        legacy    = { useClass = "portraitBorderUseClassColor" },
    })

    Helpers.BorderRegistry.Register({
        key       = "unitFrame",
        label     = "Frame",
        category  = "Unit Frames",
        prefix    = "",
        multi     = true,
        db        = function(p) local i = CollectFrameUnits(p); return i and i[1] end,
        instances = CollectFrameUnits,
        refresh   = _G.QUI_RefreshUnitFrames,
        legacy    = { defaultSource = "inherit" },
    })
end

if ns.Registry then
    ns.Registry:Register("unitframes", {
        refresh = _G.QUI_RefreshUnitFrames,
        priority = 20,
        group = "frames",
        importCategories = { "unitFrames" },
    })
    ns.Registry:Register("unitframesSkin", {
        refresh = _G.QUI_RefreshUnitFrames,
        priority = 20,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
