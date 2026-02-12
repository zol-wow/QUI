---------------------------------------------------------------------------
-- QUI Combat Timer
-- Displays elapsed time in combat (resets on combat exit)
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- State tracking
---------------------------------------------------------------------------
local CombatTimerState = {
    combatStartTime = 0,
    timerFrame = nil,
    isInCombat = false,
    isPreviewMode = false,
    isInEncounter = false,  -- Track boss encounter state
}

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("combatTimer")
end

---------------------------------------------------------------------------
-- Create the timer frame (one-time setup)
---------------------------------------------------------------------------
local function CreateTimerFrame()
    if CombatTimerState.timerFrame then return end

    local frame = CreateFrame("Frame", "QUI_CombatTimer", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    frame:SetSize(80, 30)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)

    -- Set up backdrop (background only)
    frame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, frame))
    frame:SetBackdropColor(0, 0, 0, 0.6)

    -- Create manual border lines for uniform edges
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, 1, 0, 0, 0, 1)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    text:SetTextColor(1, 1, 1, 1)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetText("0:00")
    frame.text = text

    frame:Hide()
    CombatTimerState.timerFrame = frame
end

---------------------------------------------------------------------------
-- Format elapsed time as MM:SS
---------------------------------------------------------------------------
local function FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

---------------------------------------------------------------------------
-- OnUpdate handler for timer
---------------------------------------------------------------------------
local function OnTimerUpdate(self, elapsed)
    if not CombatTimerState.isInCombat then return end

    local now = GetTime()
    local elapsedTime = now - CombatTimerState.combatStartTime

    if CombatTimerState.timerFrame and CombatTimerState.timerFrame.text then
        CombatTimerState.timerFrame.text:SetText(FormatTime(elapsedTime))
    end
end

---------------------------------------------------------------------------
-- Get global addon font setting
---------------------------------------------------------------------------
local function GetGlobalFont()
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general and QUICore.db.profile.general.font then
        return QUICore.db.profile.general.font
    end
    return "Quazii"
end

---------------------------------------------------------------------------
-- Get player class color
---------------------------------------------------------------------------
local function GetClassColor()
    local r, g, b = Helpers.GetPlayerClassColor()
    return {r, g, b, 1}
end

---------------------------------------------------------------------------
-- Update timer appearance from settings
---------------------------------------------------------------------------
local function UpdateTimerAppearance()
    if not CombatTimerState.timerFrame then
        CreateTimerFrame()
    end

    local settings = GetSettings()
    if not settings then return end

    local frame = CombatTimerState.timerFrame

    -- Update size
    local width = settings.width or 80
    local height = settings.height or 30
    frame:SetSize(width, height)

    -- Update position
    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or -150
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)

    -- Update font (using LSM) - check if using custom font or global
    local fontSize = settings.fontSize or 16
    local fontName = settings.useCustomFont and settings.font or GetGlobalFont()
    local fontPath = UIKit.ResolveFontPath(fontName)
    frame.text:SetFont(fontPath, fontSize, "OUTLINE")

    -- Update text color (use class color or custom color)
    local textColor
    if settings.useClassColorText then
        textColor = GetClassColor()
    else
        textColor = settings.textColor or {1, 1, 1, 1}
    end
    frame.text:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)

    -- Update backdrop and border
    local showBackdrop = settings.showBackdrop
    if showBackdrop == nil then showBackdrop = true end

    local borderSize = settings.borderSize or 1
    local borderTexture = settings.borderTexture or "None"
    local useLSMBorder = borderTexture ~= "None" and borderSize > 0

    -- Get border color
    local borderColor
    if settings.useClassColorBorder then
        borderColor = GetClassColor()
    elseif settings.useAccentColorBorder then
        local QUI = _G.QUI
        if QUI and QUI.GetAddonAccentColor then
            local ar, ag, ab, aa = QUI:GetAddonAccentColor()
            borderColor = { ar, ag, ab, aa }
        else
            borderColor = settings.borderColor or {0, 0, 0, 1}
        end
    else
        borderColor = settings.borderColor or {0, 0, 0, 1}
    end

    -- Set up backdrop with or without LSM border
    -- Skip LSM border if hideBorder is enabled
    local hideBorder = settings.hideBorder
    local effectiveUseLSMBorder = useLSMBorder and not hideBorder
    
    if showBackdrop or effectiveUseLSMBorder then
        frame:SetBackdrop(UIKit.GetBackdropInfo(hideBorder and "None" or borderTexture, hideBorder and 0 or borderSize, frame))

        if showBackdrop then
            local bgColor = settings.backdropColor or {0, 0, 0, 0.6}
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
        else
            frame:SetBackdropColor(0, 0, 0, 0)
        end

        if effectiveUseLSMBorder then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
    else
        frame:SetBackdrop(nil)
    end

    -- Update manual border lines (only used when no LSM border is selected)
    -- Hide all borders if hideBorder is enabled
    local hideBorder = settings.hideBorder
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, borderSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1, useLSMBorder or hideBorder)

    -- Ensure text is always centered
    frame.text:ClearAllPoints()
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 1)
end

---------------------------------------------------------------------------
-- Combat start handler
---------------------------------------------------------------------------
local function OnCombatStart()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    -- Don't start combat timer if we're in preview mode
    if CombatTimerState.isPreviewMode then return end

    -- If encounters-only mode is enabled and we're not in an encounter, don't show
    if settings.onlyShowInEncounters and not CombatTimerState.isInEncounter then
        CombatTimerState.isInCombat = true  -- Track combat state but don't show timer
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

---------------------------------------------------------------------------
-- Combat end handler
---------------------------------------------------------------------------
local function OnCombatEnd()
    -- Don't hide if in preview mode
    if CombatTimerState.isPreviewMode then return end

    CombatTimerState.isInCombat = false

    if CombatTimerState.timerFrame then
        CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
        CombatTimerState.timerFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- Encounter start handler (boss encounters)
---------------------------------------------------------------------------
local function OnEncounterStart()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    CombatTimerState.isInEncounter = true

    -- Don't interfere with preview mode
    if CombatTimerState.isPreviewMode then return end

    -- If encounters-only mode and we're in combat but timer not shown, show it now
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

---------------------------------------------------------------------------
-- Encounter end handler
---------------------------------------------------------------------------
local function OnEncounterEnd()
    CombatTimerState.isInEncounter = false

    local settings = GetSettings()
    if not settings then return end

    -- Don't hide if in preview mode
    if CombatTimerState.isPreviewMode then return end

    -- If encounters-only mode is enabled, hide the timer when encounter ends
    -- (even if still in combat)
    if settings.onlyShowInEncounters and CombatTimerState.timerFrame then
        CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
        CombatTimerState.timerFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- Refresh function (called when settings change)
---------------------------------------------------------------------------
local function RefreshCombatTimer()
    local settings = GetSettings()

    -- If disabled and not in preview mode, hide the timer
    if (not settings or not settings.enabled) and not CombatTimerState.isPreviewMode then
        CombatTimerState.isInCombat = false
        if CombatTimerState.timerFrame then
            CombatTimerState.timerFrame:SetScript("OnUpdate", nil)
            CombatTimerState.timerFrame:Hide()
        end
        return
    end

    -- Update appearance if settings changed
    UpdateTimerAppearance()

    -- If currently in combat (and not preview), make sure it's visible
    if InCombatLockdown() and CombatTimerState.timerFrame and not CombatTimerState.isPreviewMode then
        if not CombatTimerState.isInCombat then
            -- Entered combat while feature was disabled, start now
            CombatTimerState.combatStartTime = GetTime()
            CombatTimerState.isInCombat = true
            CombatTimerState.timerFrame.text:SetText("0:00")
            CombatTimerState.timerFrame:Show()
            CombatTimerState.timerFrame:SetScript("OnUpdate", OnTimerUpdate)
        end
    end
end

---------------------------------------------------------------------------
-- Toggle preview mode (for options panel)
---------------------------------------------------------------------------
local function TogglePreview(enable)
    CreateTimerFrame()
    if not CombatTimerState.timerFrame then return end

    CombatTimerState.isPreviewMode = enable

    if enable then
        -- Show preview
        UpdateTimerAppearance()
        CombatTimerState.timerFrame.text:SetText("01:23")
        CombatTimerState.timerFrame:Show()
        CombatTimerState.timerFrame:SetScript("OnUpdate", nil)  -- No counting in preview
    else
        -- Hide preview (unless actually in combat with feature enabled)
        local settings = GetSettings()
        if settings and settings.enabled and InCombatLockdown() then
            -- Don't hide, we're in combat with feature enabled
            CombatTimerState.isInCombat = true
            CombatTimerState.combatStartTime = GetTime()
            CombatTimerState.timerFrame.text:SetText("0:00")
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

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            CreateTimerFrame()
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "ENCOUNTER_START" then
        OnEncounterStart()
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd()
    end
end)

---------------------------------------------------------------------------
-- Global functions for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshCombatTimer = RefreshCombatTimer
_G.QUI_ToggleCombatTimerPreview = TogglePreview
_G.QUI_IsCombatTimerPreviewMode = IsPreviewMode

QUI.CombatTimer = {
    Refresh = RefreshCombatTimer,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}
