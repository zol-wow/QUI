---------------------------------------------------------------------------
-- QUI Mythic+ Progress
-- Per-unit enemy forces values for tooltips and nameplates.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("mplusProgress")

local MPlusProgress = {}
ns.MPlusProgress = MPlusProgress

local DIFFICULTY_MYTHIC_PLUS = DIFFICULTY_MYTHIC_PLUS or 8

local DEFAULTS = {
    enabled = true,
    tooltipEnabled = true,
    tooltipIncludeCount = true,
    tooltipShowNoProgress = false,
    nameplateEnabled = true,
    nameplateTextFormat = "+$percent$%",
    nameplateTextColor = { 1, 1, 1, 1 },
    nameplateTextScale = 1.0,
    nameplateOffsetX = 0,
    nameplateOffsetY = 0,
}

local State = {
    activeNameplates = {},
    framePool = {},
    tooltipHooked = false,
    challengeCompleted = false,
}

local function Settings()
    local db = GetSettings()
    if db then
        Helpers.EnsureDefaults(db, DEFAULTS)
        return db
    end
    return DEFAULTS
end

local function IsEnabled()
    local settings = Settings()
    return settings.enabled ~= false
end

local function IsMythicPlus()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == DIFFICULTY_MYTHIC_PLUS
end

local function IsActiveScenario()
    return IsEnabled() and IsMythicPlus() and not State.challengeCompleted
end

local function IsNameplateEnabled()
    local settings = Settings()
    return IsActiveScenario() and settings.nameplateEnabled ~= false
end

local function IsTooltipEnabled()
    local settings = Settings()
    return IsActiveScenario() and settings.tooltipEnabled ~= false
end

local function GetPlateUnitToken(plate)
    if type(plate) ~= "table" or not Helpers.CanAccessTable(plate) then return nil end
    local unitFrame = plate.UnitFrame
    if type(unitFrame) ~= "table" or not Helpers.CanAccessTable(unitFrame) then return nil end
    return unitFrame.unit
end

local function GetUnitProgress(unit)
    if not unit or not C_ScenarioInfo or not C_ScenarioInfo.GetUnitCriteriaProgressValues then
        return nil, nil, nil
    end

    return C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)
end

local function GetRequiredCount()
    if not C_ScenarioInfo or not C_ScenarioInfo.GetScenarioStepInfo or not C_ScenarioInfo.GetCriteriaInfo then
        return nil
    end

    local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
    local numCriteria = stepInfo and stepInfo.numCriteria or 0
    if Helpers.IsSecretValue(numCriteria) or type(numCriteria) ~= "number" then
        return nil
    end

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info and info.isWeightedProgress then
            local totalQuantity = info.totalQuantity
            if not Helpers.IsSecretValue(totalQuantity) and type(totalQuantity) == "number" then
                return totalQuantity
            end
            return nil
        end
    end

    return nil
end

local function UnitCanShowNoProgress(unit)
    if not unit or not UnitCanAttack then return false end
    local canAttack = UnitCanAttack("player", unit)
    if Helpers.IsSecretValue(canAttack) then
        return false
    end
    return canAttack == true
end

local function BuildNameplateText(percentString)
    if percentString == nil then return nil, false end
    if Helpers.IsSecretValue(percentString) then
        return percentString, true
    end

    local text = tostring(percentString)
    if text == "" then return nil, false end

    local format = Settings().nameplateTextFormat or DEFAULTS.nameplateTextFormat
    if type(format) ~= "string" or format == "" then
        format = DEFAULTS.nameplateTextFormat
    end

    local rendered = format:gsub("%$percent%$", function() return text end)
    return rendered, true
end

local function ApplyNameplateStyle(frame)
    if not frame or not frame.text then return end

    local settings = Settings()
    local color = settings.nameplateTextColor or DEFAULTS.nameplateTextColor
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    local scale = settings.nameplateTextScale or 1

    frame:SetScale(scale)
    frame.text:SetFont(Helpers.GetGeneralFont(), 12, Helpers.GetGeneralFontOutline())
    frame.text:SetTextColor(r, g, b, a)
end

local function AcquireNameplateFrame()
    local frame = table.remove(State.framePool)
    if frame then
        frame:Show()
        return frame
    end

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(120, 22)
    frame:SetFrameStrata("HIGH")

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetAllPoints(frame)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    text:SetText("")
    frame.text = text

    return frame
end

local function ReleaseNameplateFrame(frame)
    if not frame then return end
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    if frame.text then
        frame.text:SetText("")
    end
    State.framePool[#State.framePool + 1] = frame
end

function MPlusProgress:RemoveNameplate(unit)
    local frame = unit and State.activeNameplates[unit]
    if not frame then return end

    State.activeNameplates[unit] = nil
    ReleaseNameplateFrame(frame)
end

function MPlusProgress:RemoveAllNameplates()
    for unit in pairs(State.activeNameplates) do
        self:RemoveNameplate(unit)
    end
end

function MPlusProgress:UpdateNameplatePosition(unit)
    local frame = unit and State.activeNameplates[unit]
    if not frame then return false end

    local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then
        self:RemoveNameplate(unit)
        return false
    end

    local settings = Settings()
    frame:SetParent(nameplate)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", nameplate, "RIGHT", settings.nameplateOffsetX or 0, settings.nameplateOffsetY or 0)
    frame:SetSize(120, 22)
    ApplyNameplateStyle(frame)
    return true
end

function MPlusProgress:UpdateNameplateValue(unit)
    if not unit or not IsNameplateEnabled() then
        self:RemoveNameplate(unit)
        return false
    end

    local _, _, percentString = GetUnitProgress(unit)
    local text, hasText = BuildNameplateText(percentString)
    local frame = State.activeNameplates[unit]

    if not hasText then
        if frame then
            frame:Hide()
        end
        return false
    end

    if not frame then
        local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        if not nameplate then return false end
        frame = AcquireNameplateFrame()
        State.activeNameplates[unit] = frame
    end

    if not self:UpdateNameplatePosition(unit) then return false end
    frame.text:SetText(text)
    frame:Show()
    return true
end

function MPlusProgress:UpdateNameplates()
    if not IsNameplateEnabled() then
        self:RemoveAllNameplates()
        return
    end

    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = GetPlateUnitToken(plate)
            if unit then
                self:UpdateNameplateValue(unit)
            end
        end
    end

    for unit in pairs(State.activeNameplates) do
        self:UpdateNameplateValue(unit)
    end
end

function MPlusProgress:OnNameplateAdded(unit)
    if not unit or not IsNameplateEnabled() then return end
    C_Timer.After(0, function()
        MPlusProgress:UpdateNameplateValue(unit)
    end)
end

function MPlusProgress:OnNameplateRemoved(unit)
    self:RemoveNameplate(unit)
end

function MPlusProgress:AddTooltipProgress(tooltip, unit)
    if not tooltip or not unit or not IsTooltipEnabled() then return end

    local count, _, percentString = GetUnitProgress(unit)
    if percentString == nil then
        local settings = Settings()
        if settings.tooltipShowNoProgress and UnitCanShowNoProgress(unit) then
            tooltip:AddDoubleLine("M+ Progress:", "No progress", 0.204, 1, 0.6, 0.8, 0.8, 0.8)
            tooltip:Show()
        end
        return
    end

    if Helpers.IsSecretValue(percentString) then
        tooltip:AddDoubleLine("M+ Progress:", percentString, 0.204, 1, 0.6, 1, 1, 1)
    else
        local text = tostring(percentString)
        if text == "" then return end
        text = text .. "%"

        local settings = Settings()
        if settings.tooltipIncludeCount ~= false
            and not Helpers.IsSecretValue(count)
            and type(count) == "number" then
            local required = GetRequiredCount()
            if required and required > 0 then
                text = string.format("%s %d/%d", text, count, required)
            end
        end

        tooltip:AddDoubleLine("M+ Progress:", text, 0.204, 1, 0.6, 1, 1, 1)
    end
    tooltip:Show()
end

function MPlusProgress:RegisterTooltipHook()
    if State.tooltipHooked then return end
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then return end
    if not Enum or not Enum.TooltipDataType or not Enum.TooltipDataType.Unit then return end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        MPlusProgress:AddTooltipProgress(tooltip, "mouseover")
    end)
    State.tooltipHooked = true
end

function MPlusProgress:Refresh()
    if not IsActiveScenario() then
        self:RemoveAllNameplates()
        return
    end

    self:UpdateNameplates()
end

function MPlusProgress:SetChallengeCompleted(completed)
    State.challengeCompleted = completed == true
    self:Refresh()
end

local eventFrame = CreateFrame("Frame")

local function OnEvent(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        MPlusProgress:RegisterTooltipHook()
        C_Timer.After(0.5, function()
            MPlusProgress:Refresh()
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        State.challengeCompleted = false
        C_Timer.After(0.5, function()
            MPlusProgress:Refresh()
        end)
    elseif event == "CHALLENGE_MODE_START" then
        State.challengeCompleted = false
        MPlusProgress:Refresh()
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        MPlusProgress:SetChallengeCompleted(true)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        MPlusProgress:OnNameplateAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        MPlusProgress:OnNameplateRemoved(arg1)
    elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_POI_UPDATE" or event == "SCENARIO_UPDATE" then
        MPlusProgress:UpdateNameplates()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(0.5, function()
            MPlusProgress:Refresh()
        end)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
eventFrame:RegisterEvent("SCENARIO_POI_UPDATE")
eventFrame:RegisterEvent("SCENARIO_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

_G.QUI_MPlusProgress = MPlusProgress
_G.QUI_RefreshMPlusProgress = function()
    MPlusProgress:Refresh()
end
