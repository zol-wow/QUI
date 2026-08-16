local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local Helpers = ns.Helpers
local UIKit = ns.UIKit
local QUICore = ns.Addon
local CastEngine = ns.CastEngine

local type = type
local pcall = pcall
local GetTime = GetTime
local CreateFrame = CreateFrame
local UnitExists = UnitExists

local NPCastbar = {}
NP.Castbar = NPCastbar

local WHITE8X8 = "Interface\\Buttons\\WHITE8x8"
local SHIELD_TEXTURE = "Interface\\RaidFrame\\Shield-Overshield"

local GetBarTexture = NP.GetBarTexture

local activeCastPlates = {}

local UpdateCastTarget
local activeCount = 0
local textTicker = nil

local function TickCastText()
    for plate in pairs(activeCastPlates) do
        local castBar = plate.castBar
        if castBar and plate.npCasting and plate.npCastStart and plate.npCastEnd then
            local now = GetTime()
            if plate.npChanneled then
                castBar:SetValue(plate.npCastStart + plate.npCastEnd - now)
            else
                castBar:SetValue(now)
            end
            if plate.npShowCastTimer then
                local remaining = plate.npCastEnd - now
                if remaining < 0 then remaining = 0 end
                castBar.timeText:SetFormattedText("%.1f", remaining)
            end
        end
        if castBar and plate.npShowCastTimer then
            CastEngine.UpdateTimerText(castBar)
        end
        if plate.npShowCastTarget then
            UpdateCastTarget(plate)
        end
        local unit = plate.unit
        if not unit or not UnitExists(unit) then
            NPCastbar.StopCast(plate)
        end
    end
end

local function CastTickerAcquire(plate)
    if activeCastPlates[plate] then return end
    activeCastPlates[plate] = true
    activeCount = activeCount + 1
    if not textTicker and C_Timer and C_Timer.NewTicker then
        textTicker = C_Timer.NewTicker(0.1, TickCastText)
    end
end

local function CastTickerRelease(plate)
    if not activeCastPlates[plate] then return end
    activeCastPlates[plate] = nil
    activeCount = activeCount - 1
    if activeCount <= 0 then
        activeCount = 0
        if textTicker then
            textTicker:Cancel()
            textTicker = nil
        end
    end
end

local INTERRUPT_SPELLS = {
    1766,
    6552,
    2139,
    57994,
    96231,
    47528,
    106839,
    116705,
    183752,
    147362,
    187707,
    351338,
    15487,
    119910,
}

local interruptSpellID = nil
local interruptResolved = false

local function ResolveInterruptSpell()
    interruptResolved = true
    interruptSpellID = nil
    local isKnown = IsSpellKnown
    local isPlayerSpell = IsPlayerSpell
    for i = 1, #INTERRUPT_SPELLS do
        local id = INTERRUPT_SPELLS[i]
        local known = false
        if isPlayerSpell then
            local ok, v = pcall(isPlayerSpell, id)
            known = ok and NP.Plain(v, "boolean") == true
        end
        if not known and isKnown then
            local ok, v = pcall(isKnown, id)
            known = ok and NP.Plain(v, "boolean") == true
        end
        if known then
            interruptSpellID = id
            return id
        end
    end
    return nil
end

local function GetInterruptSpell()
    if not interruptResolved then
        ResolveInterruptSpell()
    end
    return interruptSpellID
end

local SafeToNumber = Helpers.SafeToNumber
local function GetInterruptRemaining()
    local spellID = GetInterruptSpell()
    if not spellID or not (C_Spell and C_Spell.GetSpellCooldown) then return 0 end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return 0 end
    local start = SafeToNumber(info.startTime, 0)
    local duration = SafeToNumber(info.duration, 0)
    if duration <= 1.6 then return 0 end
    local remaining = (start + duration) - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function PinKickTick(plate)
    local castBar = plate.castBar
    local kickBar = plate.kickBar
    if not kickBar or not plate.npCasting or not plate.npKickTickEnabled then return end

    if GetInterruptRemaining() <= 0 then
        kickBar:Hide()
        return
    end
    local durationObj = castBar.durationObj
    if durationObj == nil then
        kickBar:Hide()
        return
    end

    local fillTex = castBar:GetStatusBarTexture()
    if not fillTex then
        kickBar:Hide()
        return
    end
    kickBar:ClearAllPoints()
    kickBar:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
    kickBar:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)

    local okTotal, total = pcall(function()
        local getter = durationObj.GetTotalDuration or durationObj.GetDuration or durationObj.GetMaxDuration
        return getter and getter(durationObj) or nil
    end)
    if not okTotal or total == nil then
        kickBar:Hide()
        return
    end
    pcall(kickBar.SetMinMaxValues, kickBar, 0, total)

    local armed = false
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local spellID = GetInterruptSpell()
        local okCD, cdObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if okCD and cdObj ~= nil then
            armed = CastEngine.ApplyTimerDriven(kickBar, cdObj, 1)
        end
    end
    if not armed then
        kickBar:SetValue(GetInterruptRemaining())
    end
    kickBar:Show()
end

local kickEventFrame = CreateFrame("Frame")
kickEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
kickEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
kickEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
kickEventFrame:RegisterEvent("SPELLS_CHANGED")
kickEventFrame:RegisterEvent("UI_SCALE_CHANGED")
kickEventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
kickEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
        interruptResolved = false
        return
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        for _, plate in pairs(NP.plates) do
            if plate.npLiftOverlay and NPCastbar.ApplyLift then
                NPCastbar.ApplyLift(plate)
            end
        end
        return
    end
    if activeCount == 0 then return end
    for plate in pairs(activeCastPlates) do
        if plate.npKickTickEnabled and plate.npCasting then
            PinKickTick(plate)
        end
        if plate.npInterruptReadyTint and plate.npCasting
            and plate.npPlainNotInterruptible ~= nil and NPCastbar.ReapplyInterruptibleVisuals then
            NPCastbar.ReapplyInterruptibleVisuals(plate)
        end
    end
end)

local ApplyLift

function NPCastbar.Build(plate)
    local castBar = CreateFrame("StatusBar", nil, plate)
    castBar:SetStatusBarTexture(WHITE8X8)
    castBar:SetMinMaxValues(0, 1)
    castBar:SetValue(0)
    castBar:EnableMouse(false)
    castBar:Hide()
    plate.castBar = castBar

    plate.castBg = UIKit.CreateBackground(castBar, 0.1, 0.1, 0.1, 0.9)
    UIKit.CreateBorderLines(castBar)

    local overlay = castBar:CreateTexture(nil, "ARTWORK", nil, 2)
    local fill = castBar:GetStatusBarTexture()
    if fill then
        overlay:SetAllPoints(fill)
    else
        overlay:SetAllPoints(castBar)
    end
    overlay:SetColorTexture(0.45, 0.45, 0.45, 0.85)
    overlay:SetAlpha(0)
    plate.castUninterruptibleOverlay = overlay

    local shield = castBar:CreateTexture(nil, "OVERLAY")
    shield:SetTexture(SHIELD_TEXTURE)
    shield:SetAlpha(0)
    plate.castShield = shield

    local icon = castBar:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    plate.castIcon = icon

    plate.castSpellText = UIKit.CreateText(castBar, 10, nil, "OUTLINE", "OVERLAY")
    plate.castSpellText:SetPoint("LEFT", castBar, "LEFT", 2, 0)
    plate.castSpellText:SetJustifyH("LEFT")

    castBar.timeText = UIKit.CreateText(castBar, 10, nil, "OUTLINE", "OVERLAY")
    castBar.timeText:SetPoint("RIGHT", castBar, "RIGHT", -2, 0)
    castBar.timeText:SetJustifyH("RIGHT")

    local kickBar = CreateFrame("StatusBar", nil, castBar)
    kickBar:SetStatusBarTexture(WHITE8X8)
    kickBar:SetStatusBarColor(0, 0, 0, 0)
    kickBar:SetFrameLevel(castBar:GetFrameLevel() + 2)
    kickBar:EnableMouse(false)
    kickBar:Hide()
    plate.kickBar = kickBar

    local kickTick = kickBar:CreateTexture(nil, "OVERLAY", nil, 6)
    kickTick:SetColorTexture(0.92, 0.35, 0.20, 1)
    local kickFill = kickBar:GetStatusBarTexture()
    if kickFill then
        kickTick:SetPoint("CENTER", kickFill, "RIGHT", 0, 0)
    end
    plate.kickTick = kickTick

    plate.castTargetText = UIKit.CreateText(castBar, 9, nil, "OUTLINE", "OVERLAY")
    plate.castTargetText:SetPoint("TOP", castBar, "BOTTOM", 0, -1)
    plate.castTargetText:SetJustifyH("CENTER")
    plate.castTargetText:Hide()
end

function NPCastbar.ApplyAppearance(plate, settings)
    local cast = settings.castbar or {}
    local health = settings.health or {}
    local castBar = plate.castBar

    plate.npCastEnabled = cast.enabled ~= false
    plate.npShowCastTimer = cast.showTimer ~= false
    plate.npKickTickEnabled = cast.kickTick ~= false
    plate.npLiftOverlay = cast.liftOverlay == true

    local width = health.width or 210
    local height = cast.height or 17
    QUICore:SetPixelPerfectSize(plate.kickTick, 2, height + 4)
    plate.kickBar:SetWidth(QUICore:Pixels(width, plate))
    QUICore:SetPixelPerfectSize(castBar, width, height)
    castBar:ClearAllPoints()
    local castAnchorTo = (plate.npPowerBarEnabled and plate.powerBar) or plate.healthBar
    castBar:SetPoint("TOP", castAnchorTo, "BOTTOM", 0, -QUICore:Pixels((cast.gap or 0) + 1, plate))
    local castTexName = (cast.texture and cast.texture ~= "") and cast.texture or health.texture
    castBar:SetStatusBarTexture(GetBarTexture(castTexName))
    local tex = castBar:GetStatusBarTexture()
    if tex then
        tex:SetHorizTile(false)
        tex:SetVertTile(false)
        plate.castUninterruptibleOverlay:ClearAllPoints()
        plate.castUninterruptibleOverlay:SetAllPoints(tex)
    end
    local bc = health.borderColor or { 0, 0, 0 }
    UIKit.UpdateBorderLines(castBar, health.borderSize or 1, bc[1] or 0, bc[2] or 0, bc[3] or 0, 1,
        (health.borderSize or 1) <= 0)
    local bg = (settings.colors or {}).castBg or { 0.1, 0.1, 0.1, 0.9 }
    plate.castBg:SetVertexColor(bg[1] or 0.1, bg[2] or 0.1, bg[3] or 0.1, bg[4] or 0.9)

    local iconSize = height
    plate.castIcon:ClearAllPoints()
    plate.castIcon:SetPoint("RIGHT", castBar, "LEFT", -QUICore:Pixels(2, plate), 0)
    QUICore:SetPixelPerfectSize(plate.castIcon, iconSize, iconSize)
    if cast.showIcon == false then plate.castIcon:Hide() else plate.castIcon:Show() end

    plate.castShield:ClearAllPoints()
    plate.castShield:SetPoint("CENTER", plate.castIcon, "CENTER", 0, 0)
    QUICore:SetPixelPerfectSize(plate.castShield, iconSize + 6, iconSize + 6)

    local fontPath, fontOutline = NP.ResolveFont(plate)
    QUICore:ApplyFont(plate.castSpellText, nil, cast.nameSize or 10, fontPath, fontOutline)
    QUICore:ApplyFont(plate.castBar.timeText, nil, cast.timerSize or 10, fontPath, fontOutline)
    if cast.showSpellName == false then plate.castSpellText:Hide() else plate.castSpellText:Show() end
    if cast.showTimer == false then castBar.timeText:Hide() else castBar.timeText:Show() end

    plate.castSpellText:SetWidth(QUICore:Pixels(width - 34, plate))

    plate.npShowCastTarget = cast.showCastTarget == true
    plate.npInterruptReadyTint = cast.interruptReadyTint == true
    if plate.castTargetText then
        QUICore:ApplyFont(plate.castTargetText, nil, cast.castTargetSize or 9, fontPath, fontOutline)
        if not plate.npShowCastTarget then plate.castTargetText:Hide() end
    end

    ApplyLift(plate)
end

ApplyLift = function(plate)
    local castBar = plate.castBar
    if not castBar then return end

    if not plate.npLiftOverlay then
        if plate.npLiftContainer then
            plate.npLiftContainer:Hide()
        end
        if castBar:GetParent() ~= plate then
            castBar:SetParent(plate)
        end
        return
    end

    local container = plate.npLiftContainer
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        container:SetFrameStrata("HIGH")
        container:SetSize(1, 1)
        if container.SetIgnoreParentScale then
            container:SetIgnoreParentScale(true)
        end
        plate.npLiftContainer = container
        plate:HookScript("OnHide", function() container:Hide() end)
        plate:HookScript("OnShow", function()
            if plate.npLiftOverlay then container:Show() end
        end)
    end

    local okScale, scale = pcall(plate.GetEffectiveScale, plate)
    scale = okScale and NP.Plain(scale, "number") or nil
    if scale and scale > 0 then
        container:SetScale(scale)
    end
    container:ClearAllPoints()
    container:SetPoint("TOP", plate.healthBar, "BOTTOM", 0, 0)
    container:SetShown(plate:IsShown())

    castBar:SetParent(container)
end
NPCastbar.ApplyLift = ApplyLift

local function ResolveCastBaseColor(plate, colors)
    if plate.npCastImportant == true then
        return colors.castImportant or { 1, 0.25, 0.25 }
    end
    if plate.npCastKind == "channel" then
        return colors.castChannel or { 0.35, 0.60, 0.90 }
    elseif plate.npCastKind == "empower" then
        return colors.castEmpowered or { 0.90, 0.55, 0.15 }
    end
    return colors.castInterruptible or { 0.70, 0.40, 0.90 }
end

local function ApplyInterruptibleVisuals(plate, notInterruptible, settings)
    local colors = (settings or NP.GetTypeSettings(plate) or {}).colors or {}
    local castBar = plate.castBar

    local cu = colors.castUninterruptible or { 0.45, 0.45, 0.45 }
    plate.castUninterruptibleOverlay:SetColorTexture(cu[1], cu[2], cu[3], 0.85)

    local plainNI = NP.Plain(notInterruptible, "boolean")
    plate.npPlainNotInterruptible = plainNI
    if plainNI ~= nil then
        local c
        if plainNI then
            c = colors.castUninterruptible or { 0.45, 0.45, 0.45 }
        elseif plate.npInterruptReadyTint and GetInterruptRemaining() <= 0 then
            c = colors.castInterruptReady or { 0.30, 0.85, 0.40 }
        else
            c = ResolveCastBaseColor(plate, colors)
        end
        castBar:SetStatusBarColor(c[1], c[2], c[3])
        plate.castUninterruptibleOverlay:SetAlpha(0)
        plate.castShield:SetAlpha(plainNI and 1 or 0)
        return
    end

    local c = ResolveCastBaseColor(plate, colors)
    castBar:SetStatusBarColor(c[1], c[2], c[3])
    if type(notInterruptible) ~= "nil"
        and plate.castUninterruptibleOverlay.SetAlphaFromBoolean then
        pcall(plate.castUninterruptibleOverlay.SetAlphaFromBoolean,
            plate.castUninterruptibleOverlay, notInterruptible, 1, 0)
        pcall(plate.castShield.SetAlphaFromBoolean, plate.castShield, notInterruptible, 1, 0)
    else
        plate.castUninterruptibleOverlay:SetAlpha(0)
        plate.castShield:SetAlpha(0)
    end
end

UpdateCastTarget = function(plate)
    local text = plate.castTargetText
    if not text then return end
    if not plate.npShowCastTarget or not plate.npCasting then
        text:Hide()
        return
    end
    local unit = plate.unit
    if not unit or type(UnitShouldDisplaySpellTargetName) ~= "function"
        or type(UnitSpellTargetName) ~= "function" then
        text:Hide()
        return
    end
    local okShould, should = pcall(UnitShouldDisplaySpellTargetName, unit)
    if not (okShould and NP.Plain(should, "boolean") == true) then
        text:Hide()
        return
    end
    local okName, targetName = pcall(UnitSpellTargetName, unit)
    if okName and type(targetName) ~= "nil" then
        local okSet = pcall(text.SetFormattedText, text, "%s", targetName) -- @secret-safe: SecretReturns name rides the C-side %s sink
        if okSet then text:Show() else text:Hide() end
    else
        text:Hide()
    end
end

function NPCastbar.ReapplyInterruptibleVisuals(plate)
    ApplyInterruptibleVisuals(plate, plate.npPlainNotInterruptible)
end

local function StartCast(plate)
    if not plate.npCastEnabled then return end
    local unit = plate.unit
    if not unit then return end

    local spellName, text, texture, startTimeMS, endTimeMS, notInterruptible,
        unitSpellID, isChanneled, channelStages, durationObj, hasSecretTiming = CastEngine.GetCastInfo(unit)

    local castBar = plate.castBar
    local canShow, useTimerDriven, startTime, endTime = CastEngine.ResolveNonPlayerTiming(
        spellName, startTimeMS, endTimeMS, durationObj, castBar, hasSecretTiming)
    if not canShow then
        NPCastbar.StopCast(plate)
        return
    end

    local plainStages = NP.Plain(channelStages, "number") or 0
    if isChanneled then
        plate.npCastKind = (plainStages > 0) and "empower" or "channel"
    else
        plate.npCastKind = "cast"
    end

    plate.npCastImportant = false
    local colorsS = ((NP.GetTypeSettings(plate) or {}).colors) or {}
    if colorsS.castImportantEnabled == true and C_Spell and C_Spell.IsSpellImportant
        and type(unitSpellID) ~= "nil" then
        local okI, important = pcall(C_Spell.IsSpellImportant, unitSpellID)
        if okI and NP.Plain(important, "boolean") == true then
            plate.npCastImportant = true
        end
    end

    plate.npCasting = true
    plate.npInterrupted = nil
    plate.npChanneled = isChanneled
    castBar.durationObj = durationObj

    if useTimerDriven then
        CastEngine.ApplyTimerDriven(castBar, durationObj, isChanneled and 1 or 0)
        plate.npCastStart, plate.npCastEnd = nil, nil
    elseif durationObj then
        CastEngine.ApplyTimerDriven(castBar, durationObj, isChanneled and 1 or 0)
        plate.npCastStart, plate.npCastEnd = nil, nil
    else
        plate.npCastStart, plate.npCastEnd = startTime, endTime
        castBar:SetMinMaxValues(startTime or 0, endTime or 1)
        castBar:SetValue(startTime or 0)
    end

    pcall(plate.castIcon.SetTexture, plate.castIcon, texture)
    local castLabel = text
    if type(castLabel) == "nil" then castLabel = spellName end
    local okName = pcall(plate.castSpellText.SetFormattedText, plate.castSpellText, "%s", castLabel) -- @secret-safe: SecretReturns name rides the C-side %s sink
    if not okName then plate.castSpellText:SetText("") end
    castBar.timeText:SetText("")

    ApplyInterruptibleVisuals(plate, notInterruptible)
    UpdateCastTarget(plate)

    castBar:Show()
    CastTickerAcquire(plate)

    if plate.npKickTickEnabled then
        PinKickTick(plate)
    end
end

local function RearmCast(plate)
    if not plate.npCasting then return end
    local unit = plate.unit
    if not unit then return end
    local spellName, _, _, startTimeMS, endTimeMS, _, _, isChanneled, _, durationObj, hasSecretTiming =
        CastEngine.GetCastInfo(unit)
    local castBar = plate.castBar
    local canShow, useTimerDriven, startTime, endTime = CastEngine.ResolveNonPlayerTiming(
        spellName, startTimeMS, endTimeMS, durationObj, castBar, hasSecretTiming)
    if not canShow then return end
    castBar.durationObj = durationObj
    if useTimerDriven or durationObj then
        CastEngine.ApplyTimerDriven(castBar, durationObj, isChanneled and 1 or 0)
        plate.npCastStart, plate.npCastEnd = nil, nil
    else
        plate.npCastStart, plate.npCastEnd = startTime, endTime
        castBar:SetMinMaxValues(startTime or 0, endTime or 1)
    end
    if plate.npKickTickEnabled then
        PinKickTick(plate)
    end
    UpdateCastTarget(plate)
end

function NPCastbar.StopCast(plate)
    plate.npCasting = nil
    plate.npInterrupted = nil
    plate.npChanneled = nil
    plate.npCastKind = nil
    plate.npCastImportant = nil
    plate.npPlainNotInterruptible = nil
    plate.npCastStart, plate.npCastEnd = nil, nil
    local castBar = plate.castBar
    if castBar then
        castBar.durationObj = nil
        castBar._durationGetter = nil
        castBar._durationGetterObj = nil
        castBar:Hide()
    end
    if plate.kickBar then
        plate.kickBar:Hide()
    end
    if plate.castTargetText then
        plate.castTargetText:Hide()
    end
    CastTickerRelease(plate)
end

local INTERRUPT_HOLD_FALLBACK = 1.0

local function ShowInterrupted(plate, interrupterGUID)
    local settings = NP.GetTypeSettings(plate) or {}
    local colors = settings.colors or {}
    local castBar = plate.castBar
    if not plate.npCastEnabled then return end

    plate.npCasting = nil
    plate.npInterrupted = true
    castBar.durationObj = nil

    local c = colors.castInterrupted or { 0.8, 0, 0 }
    castBar:SetStatusBarColor(c[1], c[2], c[3])
    castBar:SetMinMaxValues(0, 1)
    castBar:SetValue(1)
    plate.castUninterruptibleOverlay:SetAlpha(0)
    plate.castShield:SetAlpha(0)
    castBar.timeText:SetText("")

    local label = _G.INTERRUPTED or "Interrupted"
    local plainGUID = NP.Plain(interrupterGUID, "string")
    if plainGUID and plainGUID ~= "" then
        local okInfo, _, classToken, _, _, _, interrupterName = pcall(GetPlayerInfoByGUID, plainGUID)
        interrupterName = NP.Plain(interrupterName, "string")
        classToken = NP.Plain(classToken, "string")
        if okInfo and interrupterName and interrupterName ~= "" then
            local cc = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
            if cc and cc.colorStr then
                label = label .. ": |c" .. cc.colorStr .. interrupterName .. "|r"
            else
                label = label .. ": " .. interrupterName
            end
        end
    end
    plate.castSpellText:SetText(label)
    castBar:Show()

    local holdFor = (settings.castbar and settings.castbar.interruptedHoldTime) or INTERRUPT_HOLD_FALLBACK
    local unitAtFlash = plate.unit
    C_Timer.After(holdFor, function()
        if plate.npInterrupted and plate.unit == unitAtFlash then
            NPCastbar.StopCast(plate)
        end
    end)
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local dispatcher = CreateFrame("Frame")
for i = 1, #CAST_EVENTS do
    dispatcher:RegisterEvent(CAST_EVENTS[i])
end

dispatcher:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    local unitToken = NP.Plain(unit, "string")
    if not unitToken then return end
    local plate = NP.plates[unitToken]
    if not plate then return end

    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        StartCast(plate)
    elseif event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        RearmCast(plate)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        local interrupterGUID = arg4
        if type(interrupterGUID) == "nil" then interrupterGUID = arg3 end
        ShowInterrupted(plate, interrupterGUID)
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
        or event == "UNIT_SPELLCAST_FAILED" then
        if not plate.npInterrupted then
            NPCastbar.StopCast(plate)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        if plate.npCasting then ApplyInterruptibleVisuals(plate, false) end
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if plate.npCasting then ApplyInterruptibleVisuals(plate, true) end
    end
end)

function NPCastbar.ProbeCast(plate)
    if plate.npCasting or plate.npInterrupted then return end
    StartCast(plate)
end

local function SetupDebugInstrumentation()
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "NameplateCast", frame = dispatcher }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end
