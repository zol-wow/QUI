local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local CreateOnUpdateThrottle = Helpers and Helpers.CreateOnUpdateThrottle

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end
local floor = math.floor
local format = string.format

local CombatTimerState = {
    combatStartTime = 0,
    timerFrame = nil,
    isInCombat = false,
    isPreviewMode = false,
    isInEncounter = false,
}

local TIMER_UPDATE_INTERVAL = 0.1
local eventFrame = CreateFrame("Frame")
local RUNTIME_EVENTS = {
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
    ENCOUNTER_START = true,
    ENCOUNTER_END = true,
}
local runtimeEventsRegistered = false

local GetSettings = Helpers.CreateDBGetter("combatTimer")

local function CreateTimerFrame()
    if CombatTimerState.timerFrame then return end

    local frame = CreateFrame("Frame", "QUI_CombatTimer", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    frame:SetSize(80, 30)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)

    frame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, frame))
    local _cbgr, _cbgg, _cbgb = 0, 0, 0
    if Helpers and Helpers.GetSkinBgColor then
        _cbgr, _cbgg, _cbgb = Helpers.GetSkinBgColor()
    end
    frame:SetBackdropColor(_cbgr, _cbgg, _cbgb, 0.6)

    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, 1, 0, 0, 0, 1)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    CJKFont(text, (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or "Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    text:SetTextColor(1, 1, 1, 1)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetText("00:00")
    frame.text = text

    frame:Hide()
    CombatTimerState.timerFrame = frame
end

local _lastTimerSecs = -1
local _lastTimerText = "00:00"

local function FormatTime(seconds)
    local total = floor(seconds)
    if total == _lastTimerSecs then return _lastTimerText end
    _lastTimerSecs = total
    _lastTimerText = Helpers.FormatMMSS(total, true)
    return _lastTimerText
end

local function UpdateTimerDisplay()
    if not CombatTimerState.isInCombat then return end

    local now = GetTime()
    local elapsedTime = now - CombatTimerState.combatStartTime

    if CombatTimerState.timerFrame and CombatTimerState.timerFrame.text then
        CombatTimerState.timerFrame.text:SetText(FormatTime(elapsedTime))
    end
end

local OnTimerUpdate
if CreateOnUpdateThrottle then
    OnTimerUpdate = CreateOnUpdateThrottle(TIMER_UPDATE_INTERVAL, function()
        UpdateTimerDisplay()
    end)
else
    local fallbackElapsed = 0
    OnTimerUpdate = function(_, elapsed)
        fallbackElapsed = fallbackElapsed + (elapsed or 0)
        if fallbackElapsed >= TIMER_UPDATE_INTERVAL then
            fallbackElapsed = 0
            UpdateTimerDisplay()
        end
    end
end

local function GetGlobalFont()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general and QUICore.db.profile.general.font then
        return QUICore.db.profile.general.font
    end
    return "Quazii"
end

local function GetClassColor()
    local r, g, b = Helpers.GetPlayerClassColor()
    return {r, g, b, 1}
end

local function UpdateTimerAppearance()
    if not CombatTimerState.timerFrame then
        CreateTimerFrame()
    end

    local settings = GetSettings()
    if not settings then return end

    local frame = CombatTimerState.timerFrame

    local width = settings.width or 80
    local height = settings.height or 30
    frame:SetSize(width, height)

    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or -150
    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("combatTimer")) then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)
    end

    local fontSize = settings.fontSize or 16
    local fontName = settings.useCustomFont and settings.font or GetGlobalFont()
    local fontPath = UIKit.ResolveFontPath(fontName)
    CJKFont(frame.text, fontPath, fontSize, "OUTLINE")

    local textColor
    if settings.useClassColorText then
        textColor = GetClassColor()
    else
        textColor = settings.textColor or {1, 1, 1, 1}
    end
    frame.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)

    local showBackdrop = settings.showBackdrop
    if showBackdrop == nil then showBackdrop = true end

    local borderSize = settings.borderSize or 1
    local borderTexture = settings.borderTexture or "None"
    local useLSMBorder = borderTexture ~= "None" and borderSize > 0

    local bR, bG, bB, bA = Helpers.GetSkinBorderColor(settings, "")

    local hideBorder = settings.hideBorder
    local effectiveUseLSMBorder = useLSMBorder and not hideBorder

    local SSB = QUICore and QUICore.SafeSetBackdrop
    if showBackdrop or effectiveUseLSMBorder then
        local borderColorTable = effectiveUseLSMBorder and { bR, bG, bB, bA } or nil
        local backdropInfo = UIKit.GetBackdropInfo(hideBorder and "None" or borderTexture, hideBorder and 0 or borderSize, frame)
        if SSB then
            SSB(frame, backdropInfo, borderColorTable)
        else
            frame:SetBackdrop(backdropInfo)
        end

        if showBackdrop then
            local bgColor = settings.backdropColor or {0, 0, 0, 0.6}
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
        else
            frame:SetBackdropColor(0, 0, 0, 0)
        end

        if effectiveUseLSMBorder and not SSB then
            frame:SetBackdropBorderColor(bR, bG, bB, bA)
        end
    else
        if SSB then
            SSB(frame, nil)
        else
            frame:SetBackdrop(nil)
        end
    end

    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, borderSize, bR, bG, bB, bA, useLSMBorder or hideBorder)

    frame.text:ClearAllPoints()
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 1)
end

local function OnCombatStart()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    if CombatTimerState.isPreviewMode then return end

    if settings.onlyShowInEncounters and not CombatTimerState.isInEncounter then
        CombatTimerState.isInCombat = true
        return
    end

    CreateTimerFrame()
    UpdateTimerAppearance()

    CombatTimerState.combatStartTime = GetTime()
    CombatTimerState.isInCombat = true

    if CombatTimerState.timerFrame then
        CombatTimerState.timerFrame.text:SetText("00:00")
        CombatTimerState.timerFrame:Show()
        CombatTimerState.timerFrame:SetScript("OnUpdate", OnTimerUpdate)
    end
end

local function OnCombatEnd()
    if CombatTimerState.isPreviewMode then return end

    CombatTimerState.isInCombat = false

    if CombatTimerState.timerFrame then
        CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
        CombatTimerState.timerFrame:Hide()
    end
end

local function OnEncounterStart()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    CombatTimerState.isInEncounter = true

    if CombatTimerState.isPreviewMode then return end

    if settings.onlyShowInEncounters and CombatTimerState.isInCombat then
        CreateTimerFrame()
        UpdateTimerAppearance()

        CombatTimerState.combatStartTime = GetTime()

        if CombatTimerState.timerFrame then
            CombatTimerState.timerFrame.text:SetText("00:00")
            CombatTimerState.timerFrame:Show()
            CombatTimerState.timerFrame:SetScript("OnUpdate", OnTimerUpdate)
        end
    end
end

local function OnEncounterEnd()
    CombatTimerState.isInEncounter = false

    local settings = GetSettings()
    if not settings then return end

    if CombatTimerState.isPreviewMode then return end

    if settings.onlyShowInEncounters and CombatTimerState.timerFrame then
        CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
        CombatTimerState.timerFrame:Hide()
    end
end

local function SetRuntimeEventsRegistered(shouldRegister)
    if shouldRegister and not runtimeEventsRegistered then
        for eventName in pairs(RUNTIME_EVENTS) do
            eventFrame:RegisterEvent(eventName)
        end
        runtimeEventsRegistered = true
    elseif not shouldRegister and runtimeEventsRegistered then
        for eventName in pairs(RUNTIME_EVENTS) do
            eventFrame:UnregisterEvent(eventName)
        end
        runtimeEventsRegistered = false
    end
end

local function UpdateEventRegistrations()
    local settings = GetSettings()
    local shouldRegister = settings and settings.enabled
    SetRuntimeEventsRegistered(shouldRegister)
end

local function RefreshCombatTimer()
    local settings = GetSettings()
    UpdateEventRegistrations()

    if (not settings or not settings.enabled) and not CombatTimerState.isPreviewMode then
        CombatTimerState.isInCombat = false
        if CombatTimerState.timerFrame then
            CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
            CombatTimerState.timerFrame:Hide()
        end
        return
    end

    UpdateTimerAppearance()

    if InCombatLockdown() and CombatTimerState.timerFrame and not CombatTimerState.isPreviewMode then
        if not CombatTimerState.isInCombat then
            CombatTimerState.combatStartTime = GetTime()
            CombatTimerState.isInCombat = true
            CombatTimerState.timerFrame.text:SetText("00:00")
            CombatTimerState.timerFrame:Show()
            CombatTimerState.timerFrame:SetScript("OnUpdate", OnTimerUpdate)
        end
    end
end

local function TogglePreview(enable)
    CreateTimerFrame()
    if not CombatTimerState.timerFrame then return end

    CombatTimerState.isPreviewMode = enable

    if enable then
        UpdateTimerAppearance()
        CombatTimerState.timerFrame.text:SetText("01:23")
        CombatTimerState.timerFrame:Show()
        CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
    else
        local settings = GetSettings()
        if settings and settings.enabled and InCombatLockdown() then
            CombatTimerState.isInCombat = true
            CombatTimerState.combatStartTime = GetTime()
            CombatTimerState.timerFrame.text:SetText("00:00")
            CombatTimerState.timerFrame:SetScript("OnUpdate", OnTimerUpdate)
        else
            CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
            CombatTimerState.timerFrame:Hide()
        end
    end
end

local function IsPreviewMode()
    return CombatTimerState.isPreviewMode
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "ENCOUNTER_START" then
        OnEncounterStart()
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd()
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        CreateTimerFrame()
        UpdateEventRegistrations()
    end)
end

_G.QUI_RefreshCombatTimer = RefreshCombatTimer
_G.QUI_ToggleCombatTimerPreview = TogglePreview

QUI.CombatTimer = {
    Refresh = RefreshCombatTimer,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}

if ns.Registry then
    ns.Registry:Register("combatTimer", {
        refresh = _G.QUI_RefreshCombatTimer,
        priority = 40,
        group = "trackers",
        importCategories = { "trackersTimers" },
    })
    ns.Registry:Register("combatTimerSkin", {
        refresh = _G.QUI_RefreshCombatTimer,
        priority = 40,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

if Helpers and Helpers.BorderRegistry then
    Helpers.BorderRegistry.Register({
        key = "combatTimer", label = "Combat Timer", category = "Trackers", prefix = "",
        db = function(p) return p.combatTimer end,
        refresh = function() if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end end,
        legacy = { useClass = "useClassColorBorder", accent = "useAccentColorBorder" },
    })
end
