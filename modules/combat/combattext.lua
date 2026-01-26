---------------------------------------------------------------------------
-- QUI Combat Text Indicator
-- Displays +Combat or -Combat when entering/leaving combat
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- State tracking for fade animation
---------------------------------------------------------------------------
local CombatTextState = {
    fadeStart = 0,
    fadeStartAlpha = 1,
    fadeTargetAlpha = 0,
    fadeFrame = nil,
    textFrame = nil,
    displayTimer = nil,
}

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("combatText")
end

---------------------------------------------------------------------------
-- Create the text frame (one-time setup)
---------------------------------------------------------------------------
local function CreateTextFrame()
    if CombatTextState.textFrame then return end

    local frame = CreateFrame("Frame", "QUI_CombatText", UIParent)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetSize(200, 50)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    text:SetTextColor(0.204, 0.827, 0.6, 1)  -- QUI mint accent
    text:SetJustifyH("CENTER")
    frame.text = text

    frame:Hide()
    CombatTextState.textFrame = frame
end

---------------------------------------------------------------------------
-- OnUpdate handler for fade animation
---------------------------------------------------------------------------
local function OnFadeUpdate(self, elapsed)
    local settings = GetSettings()
    local duration = (settings and settings.fadeTime) or 0.3

    local now = GetTime()
    local progress = math.min((now - CombatTextState.fadeStart) / duration, 1)

    -- Linear interpolation
    local alpha = CombatTextState.fadeStartAlpha +
        (CombatTextState.fadeTargetAlpha - CombatTextState.fadeStartAlpha) * progress

    if CombatTextState.textFrame then
        CombatTextState.textFrame:SetAlpha(alpha)
    end

    -- Check if fade complete
    if progress >= 1 then
        if CombatTextState.textFrame then
            CombatTextState.textFrame:Hide()
        end
        self:SetScript("OnUpdate", nil)
    end
end

---------------------------------------------------------------------------
-- Start fade animation
---------------------------------------------------------------------------
local function StartFade()
    if not CombatTextState.textFrame then return end

    local currentAlpha = CombatTextState.textFrame:GetAlpha()

    CombatTextState.fadeStart = GetTime()
    CombatTextState.fadeStartAlpha = currentAlpha
    CombatTextState.fadeTargetAlpha = 0

    -- Create fade frame if needed
    if not CombatTextState.fadeFrame then
        CombatTextState.fadeFrame = CreateFrame("Frame")
    end
    CombatTextState.fadeFrame:SetScript("OnUpdate", OnFadeUpdate)
end

---------------------------------------------------------------------------
-- Show combat text with message
---------------------------------------------------------------------------
local function ShowCombatText(message)
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    -- Create frame if needed
    CreateTextFrame()

    if not CombatTextState.textFrame then return end

    -- Cancel any pending display timer
    if CombatTextState.displayTimer then
        CombatTextState.displayTimer:Cancel()
        CombatTextState.displayTimer = nil
    end

    -- Stop any ongoing fade
    if CombatTextState.fadeFrame then
        CombatTextState.fadeFrame:SetScript("OnUpdate", nil)
    end

    -- Update position
    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or 100
    CombatTextState.textFrame:ClearAllPoints()
    CombatTextState.textFrame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)

    -- Update font size
    local fontSize = settings.fontSize or 24
    CombatTextState.textFrame.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

    -- Determine and apply color based on message
    local color
    if message == "+Combat" then
        color = settings.enterCombatColor or {0.204, 0.827, 0.6, 1}
    else
        color = settings.leaveCombatColor or {0.204, 0.827, 0.6, 1}
    end
    CombatTextState.textFrame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    -- Set text and show
    CombatTextState.textFrame.text:SetText(message)
    CombatTextState.textFrame:SetAlpha(1)
    CombatTextState.textFrame:Show()

    -- Schedule fade after display time
    local displayTime = settings.displayTime or 0.8
    CombatTextState.displayTimer = C_Timer.NewTimer(displayTime, function()
        StartFade()
        CombatTextState.displayTimer = nil
    end)
end

---------------------------------------------------------------------------
-- Combat event handlers
---------------------------------------------------------------------------
local function OnCombatStart()
    ShowCombatText("+Combat")
end

local function OnCombatEnd()
    ShowCombatText("-Combat")
end

---------------------------------------------------------------------------
-- Refresh function (called when settings change)
---------------------------------------------------------------------------
local function RefreshCombatText()
    local settings = GetSettings()

    -- If disabled, hide any visible text
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
    end
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            CreateTextFrame()
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    end
end)

---------------------------------------------------------------------------
-- Global refresh function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshCombatText = RefreshCombatText

---------------------------------------------------------------------------
-- Global preview function for options panel
---------------------------------------------------------------------------
_G.QUI_PreviewCombatText = function(message)
    -- Temporarily bypass enabled check for preview
    local settings = GetSettings()
    if not settings then return end

    -- Create frame if needed
    CreateTextFrame()

    if not CombatTextState.textFrame then return end

    -- Cancel any pending display timer
    if CombatTextState.displayTimer then
        CombatTextState.displayTimer:Cancel()
        CombatTextState.displayTimer = nil
    end

    -- Stop any ongoing fade
    if CombatTextState.fadeFrame then
        CombatTextState.fadeFrame:SetScript("OnUpdate", nil)
    end

    -- Update position
    local xOffset = settings.xOffset or 0
    local yOffset = settings.yOffset or 100
    CombatTextState.textFrame:ClearAllPoints()
    CombatTextState.textFrame:SetPoint("CENTER", UIParent, "CENTER", xOffset, yOffset)

    -- Update font size
    local fontSize = settings.fontSize or 24
    CombatTextState.textFrame.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

    -- Determine and apply color based on message
    local color
    if message == "+Combat" then
        color = settings.enterCombatColor or {0.204, 0.827, 0.6, 1}
    else
        color = settings.leaveCombatColor or {0.204, 0.827, 0.6, 1}
    end
    CombatTextState.textFrame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    -- Set text and show
    CombatTextState.textFrame.text:SetText(message or "+Combat")
    CombatTextState.textFrame:SetAlpha(1)
    CombatTextState.textFrame:Show()

    -- Schedule fade after display time
    local displayTime = settings.displayTime or 0.8
    CombatTextState.displayTimer = C_Timer.NewTimer(displayTime, function()
        StartFade()
        CombatTextState.displayTimer = nil
    end)
end

QUI.CombatText = {
    Refresh = RefreshCombatText,
    Show = ShowCombatText,
    Preview = _G.QUI_PreviewCombatText,
}
