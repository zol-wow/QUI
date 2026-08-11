local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local C_Timer = C_Timer
local SetCVar = SetCVar
local InCombatLockdown = InCombatLockdown

local CombatTextState = {
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 0,
    fadeFrame = nil,
    textFrame = nil,
    displayTimer = nil,
}

local GetSettings = Helpers.CreateDBGetter("combatText")

local function GetGlobalFont()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general and QUICore.db.profile.general.font then
        return QUICore.db.profile.general.font
    end
    return "Quazii"
end

local function RefreshCombatText()
    local settings = GetSettings()

    if not settings or not settings.enabled then
        if CombatTextState.displayTimer then
            CombatTextState.displayTimer:Cancel()
            CombatTextState.displayTimer = nil
        end
        if CombatTextState.fadeFrame then
            CombatTextState.fadeFrame:SetScript("OnUpdate", nil)
        end
        if CombatTextState.textFrame then
            CombatTextState.textFrame:Hide()
        end
        return
    end

    local frame = CombatTextState.textFrame
    if not frame then return end

    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or 100
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)

    local fontSize = settings.fontSize or 24
    local fontName = settings.useCustomFont and settings.font or GetGlobalFont()
    local fontPath = UIKit.ResolveFontPath(fontName)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(frame.text, fontPath, fontSize, "OUTLINE")
    else
        frame.text:SetFont(fontPath, fontSize, "OUTLINE")
    end
end

local function CreateTextFrame()
    if CombatTextState.textFrame then return end

    local frame = CreateFrame("Frame", "QUI_CombatText", UIParent)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetSize(200, 50)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(text, Helpers.GetGeneralFont(), 24, Helpers.GetGeneralFontOutline())
    else
        text:SetFont(Helpers.GetGeneralFont(), 24, Helpers.GetGeneralFontOutline())
    end
    text:SetTextColor(0.376, 0.647, 0.980, 1)
    text:SetJustifyH("CENTER")
    frame.text = text

    frame:Hide()
    CombatTextState.textFrame = frame

    RefreshCombatText()
end

local _cachedFadeDuration = 0.3

local function OnFadeUpdate(self, elapsed)
    local duration = _cachedFadeDuration

    local now = GetTime()
    local progress = math.min((now - CombatTextState.fadeStart) / duration, 1)

    local alpha = CombatTextState.fadeStartAlpha +
        (CombatTextState.fadeTargetAlpha - CombatTextState.fadeStartAlpha) * progress

    if CombatTextState.textFrame then
        CombatTextState.textFrame:SetAlpha(alpha)
    end

    if progress >= 1 then
        if CombatTextState.textFrame then
            CombatTextState.textFrame:Hide()
        end
        self:SetScript("OnUpdate", nil)
    end
end

local function StartFade()
    if not CombatTextState.textFrame then return end

    local currentAlpha = CombatTextState.textFrame:GetAlpha()

    CombatTextState.fadeStart = GetTime()
    CombatTextState.fadeStartAlpha = currentAlpha
    CombatTextState.fadeTargetAlpha = 0

    local settings = GetSettings()
    _cachedFadeDuration = (settings and settings.fadeTime) or 0.3

    if not CombatTextState.fadeFrame then
        CombatTextState.fadeFrame = CreateFrame("Frame")
    end
    CombatTextState.fadeFrame:SetScript("OnUpdate", OnFadeUpdate)
end

local function RenderCombatText(settings, message)
    message = message or ns.L["+Combat"]

    if CombatTextState.displayTimer then
        CombatTextState.displayTimer:Cancel()
        CombatTextState.displayTimer = nil
    end

    if CombatTextState.fadeFrame then
        CombatTextState.fadeFrame:SetScript("OnUpdate", nil)
    end

    local color
    if message == ns.L["+Combat"] then
        color = settings.enterCombatColor or {0.376, 0.647, 0.980, 1}
    else
        color = settings.leaveCombatColor or {0.376, 0.647, 0.980, 1}
    end
    CombatTextState.textFrame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    CombatTextState.textFrame.text:SetText(message)
    CombatTextState.textFrame:SetAlpha(1)
    CombatTextState.textFrame:Show()

    local displayTime = settings.displayTime or 0.8
    CombatTextState.displayTimer = C_Timer.NewTimer(displayTime, function()
        StartFade()
        CombatTextState.displayTimer = nil
    end)
end

local function ShowCombatText(message)
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    CreateTextFrame()

    if not CombatTextState.textFrame then return end

    RenderCombatText(settings, message)
end

local function OnCombatStart()
    ShowCombatText(ns.L["+Combat"])
end

local function OnCombatEnd()
    ShowCombatText(ns.L["-Combat"])
end

local _sctApplyPending = false
local _sctApplyPendingFromOnChange = false

local function WantsScrollingCombatTextDisabled()
    return QUICore and QUICore.db and QUICore.db.profile
        and QUICore.db.profile.general
        and QUICore.db.profile.general.disableScrollingCombatText == true
end

local function ApplyScrollingCombatText(fromOnChange)
    if InCombatLockdown() then
        _sctApplyPending = true
        _sctApplyPendingFromOnChange = fromOnChange
        return
    end
    _sctApplyPending = false

    if WantsScrollingCombatTextDisabled() then
        SetCVar("enableFloatingCombatText", "0")
    elseif fromOnChange then
        SetCVar("enableFloatingCombatText", "1")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
        if _sctApplyPending then
            ApplyScrollingCombatText(_sctApplyPendingFromOnChange)
        end
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(CreateTextFrame)
    ns.WhenLoggedIn(function() ApplyScrollingCombatText(false) end)
end

_G.QUI_RefreshCombatText = RefreshCombatText

if QUICore then
    QUICore.RefreshScrollingCombatText = function()
        ApplyScrollingCombatText(true)
    end
end

_G.QUI_PreviewCombatText = function(message)
    local settings = GetSettings()
    if not settings then return end

    CreateTextFrame()

    RenderCombatText(settings, message)
end

QUI.CombatText = {
    Refresh = RefreshCombatText,
    Show = ShowCombatText,
    Preview = _G.QUI_PreviewCombatText,
}

if ns.Registry then
    ns.Registry:Register("combatText", {
        refresh = _G.QUI_RefreshCombatText,
        priority = 40,
        group = "combat",
        importCategories = { "trackersTimers" },
    })
end
