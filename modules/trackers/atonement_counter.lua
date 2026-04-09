---------------------------------------------------------------------------
-- QUI Atonement Counter
-- Displays the number of active player-cast Atonements in the current group.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local IsSecretValue = Helpers.IsSecretValue

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsUnit = UnitIsUnit
local UnitGUID = UnitGUID
local type = type
local ipairs = ipairs
local pcall = pcall
local string_format = string.format

local ATONEMENT_SPELL_ID = 194384
local DISCIPLINE_SPEC_ID = 256
local PLAYER_HELPFUL_FILTER = "PLAYER|HELPFUL"
local HELPFUL_FILTER = "HELPFUL"
local PREVIEW_COUNT = 7

local CounterState = {
    frame = nil,
    count = 0,
    isPreviewMode = false,
}

local DEFAULTS = {
    enabled = true,
    locked = true,
    showOnlyInInstance = false,
    hideIcon = false,
    width = 50,
    height = 50,
    fontSize = 24,
    xOffset = 500,
    yOffset = 10,
    showBackdrop = true,
    backdropColor = { 0, 0, 0, 0.6 },
    activeCountColor = { 1.0, 0.82, 0.2, 1 },
    zeroCountColor = { 1, 1, 1, 0.55 },
    useClassColorText = false,
    borderSize = 1,
    hideBorder = false,
    borderColor = { 0, 0, 0, 1 },
    useClassColorBorder = false,
    useAccentColorBorder = false,
    borderTexture = "None",
    useCustomFont = false,
    font = nil,
}

local GetSettings = Helpers.CreateDBGetter("atonementCounter")
local cachedAtonementSpellName
local cachedAtonementTexture

local refreshQueued = false
local refreshFrame = CreateFrame("Frame")
refreshFrame:Hide()

local function SafeBoolean(value)
    if value == nil or IsSecretValue(value) then
        return nil
    end
    return value and true or false
end

local function SafeAuraField(auraData, key)
    if not auraData then return nil end
    local value = auraData[key]
    if value == nil or IsSecretValue(value) then
        return nil
    end
    return value
end

local function GetAtonementSpellName()
    if cachedAtonementSpellName then
        return cachedAtonementSpellName
    end

    if C_Spell and C_Spell.GetSpellName then
        local ok, spellName = pcall(C_Spell.GetSpellName, ATONEMENT_SPELL_ID)
        if ok and type(spellName) == "string" and spellName ~= "" then
            cachedAtonementSpellName = spellName
            return cachedAtonementSpellName
        end
    end
    if GetSpellInfo then
        local ok, spellName = pcall(GetSpellInfo, ATONEMENT_SPELL_ID)
        if ok and type(spellName) == "string" and spellName ~= "" then
            cachedAtonementSpellName = spellName
            return cachedAtonementSpellName
        end
    end
    cachedAtonementSpellName = "Atonement"
    return cachedAtonementSpellName
end

local function GetAtonementTexture()
    if cachedAtonementTexture then
        return cachedAtonementTexture
    end

    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, ATONEMENT_SPELL_ID)
        if ok and texture then
            cachedAtonementTexture = texture
            return cachedAtonementTexture
        end
    end
    if GetSpellTexture then
        local ok, texture = pcall(GetSpellTexture, ATONEMENT_SPELL_ID)
        if ok and texture then
            cachedAtonementTexture = texture
            return cachedAtonementTexture
        end
    end
    cachedAtonementTexture = 134400
    return cachedAtonementTexture
end

local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex or specIndex <= 0 then
        return nil
    end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if IsSecretValue(specID) then
        return nil
    end
    return specID
end

local function IsDisciplinePriest()
    return GetPlayerSpecID() == DISCIPLINE_SPEC_ID
end

local function GetClassColor()
    local r, g, b = Helpers.GetPlayerClassColor()
    return { r, g, b, 1 }
end

local function IsRelevantUnit(unit)
    if type(unit) ~= "string" or unit == "" then
        return false
    end
    return unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$")
end

local function UnitAvailable(unit)
    if not unit then return false end
    local exists = SafeBoolean(UnitExists(unit))
    if not exists then return false end
    local connected = SafeBoolean(UnitIsConnected(unit))
    return connected ~= false
end

local function AuraMatchesAtonement(auraData)
    if not auraData then return false end
    local auraSpellID = SafeAuraField(auraData, "spellId")
    if auraSpellID and auraSpellID == ATONEMENT_SPELL_ID then
        return true
    end
    local auraName = SafeAuraField(auraData, "name")
    return auraName and auraName == GetAtonementSpellName() or false
end

local function AuraBelongsToPlayer(auraData, unit)
    if not auraData then return false end
    if unit == "player" then
        return true
    end

    local sourceUnit = SafeAuraField(auraData, "sourceUnit")
    if sourceUnit and type(sourceUnit) == "string" then
        if sourceUnit == "player" then
            return true
        end
        local ok, isPlayer = pcall(UnitIsUnit, sourceUnit, "player")
        if ok and not IsSecretValue(isPlayer) and isPlayer then
            return true
        end
    end

    local sourceGUID = SafeAuraField(auraData, "sourceGUID")
    local playerGUID = UnitGUID and UnitGUID("player")
    if sourceGUID and playerGUID and sourceGUID == playerGUID then
        return true
    end

    return false
end

local function ScanAuraListForAtonement(unit, auraList, filteredToPlayer)
    if not auraList then return false end
    for _, auraData in ipairs(auraList) do
        if AuraMatchesAtonement(auraData) then
            if filteredToPlayer or AuraBelongsToPlayer(auraData, unit) then
                return true
            end
        end
    end
    return false
end

local function UnitHasPlayerAtonement(unit)
    if not UnitAvailable(unit) then
        return false
    end

    -- Fast path by spell ID, then verify the source so another Disc Priest
    -- does not count toward the player's total.
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, ATONEMENT_SPELL_ID)
        if ok and auraData and AuraMatchesAtonement(auraData) and AuraBelongsToPlayer(auraData, unit) then
            return true
        end
    end

    local spellName = GetAtonementSpellName()
    if spellName and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, PLAYER_HELPFUL_FILTER)
        if ok and auraData and AuraMatchesAtonement(auraData) then
            return true
        end
    end

    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ok, helpfulAuras = pcall(C_UnitAuras.GetUnitAuras, unit, PLAYER_HELPFUL_FILTER, 40)
        if ok and helpfulAuras and ScanAuraListForAtonement(unit, helpfulAuras, true) then
            return true
        end
    end

    if AuraUtil and AuraUtil.ForEachAura then
        local found = false
        AuraUtil.ForEachAura(unit, PLAYER_HELPFUL_FILTER, nil, function(auraData)
            if AuraMatchesAtonement(auraData) then
                found = true
                return true
            end
        end, true)
        if found then
            return true
        end
    end

    -- Last resort: some builds may not support PLAYER filtering on point queries,
    -- so scan all helpful auras and verify the source manually.
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ok, helpfulAuras = pcall(C_UnitAuras.GetUnitAuras, unit, HELPFUL_FILTER, 40)
        if ok and helpfulAuras and ScanAuraListForAtonement(unit, helpfulAuras, false) then
            return true
        end
    end

    return false
end

local function CountActiveAtonements()
    if not IsDisciplinePriest() then
        return 0
    end

    local count = 0
    if UnitHasPlayerAtonement("player") then
        count = count + 1
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local ok, isPlayer = pcall(UnitIsUnit, unit, "player")
            if not ok or IsSecretValue(isPlayer) then
                isPlayer = false
            end
            if not isPlayer and UnitHasPlayerAtonement(unit) then
                count = count + 1
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if UnitHasPlayerAtonement(unit) then
                count = count + 1
            end
        end
    end

    return count
end

local function CreateCounterFrame()
    if CounterState.frame then return end

    local frame = CreateFrame("Frame", "QUI_AtonementCounter", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULTS.xOffset, DEFAULTS.yOffset)
    frame:SetSize(DEFAULTS.width, DEFAULTS.height)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(50)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local settings = GetSettings()
        local locked = settings and settings.locked ~= false
        local isOverridden = _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("atonementCounter")
        if not locked and not isOverridden and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local settings = GetSettings()
        if settings then
            local _, _, _, xOfs, yOfs = self:GetPoint()
            settings.xOffset = QUICore:PixelRound(xOfs)
            settings.yOffset = QUICore:PixelRound(yOfs)
        end
    end)

    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(frame)
    icon:SetTexture(GetAtonementTexture())
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetVertexColor(1, 1, 1, 0.45)
    frame.icon = icon

    local countText = frame:CreateFontString(nil, "OVERLAY")
    countText:SetPoint("CENTER", frame, "CENTER", 0, 1)
    countText:SetFont(UIKit.ResolveFontPath(), DEFAULTS.fontSize, "OUTLINE")
    countText:SetJustifyH("CENTER")
    countText:SetJustifyV("MIDDLE")
    countText:SetText("0")
    frame.countText = countText

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Atonement Counter", 1, 0.82, 0.2)
        GameTooltip:AddLine(string_format("Active: %d", CounterState.count or 0), 1, 1, 1)
        GameTooltip:AddLine("Counts only your active Atonements.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UIKit.CreateBorderLines(frame)
    CounterState.frame = frame
end

local function GetTextColor(settings, count)
    if settings.useClassColorText then
        return GetClassColor()
    end
    if count > 0 then
        return settings.activeCountColor or DEFAULTS.activeCountColor
    end
    return settings.zeroCountColor or DEFAULTS.zeroCountColor
end

local function GetBorderColor(settings)
    if settings.useClassColorBorder then
        return GetClassColor()
    end
    if settings.useAccentColorBorder then
        local addon = _G.QUI
        if addon and addon.GetAddonAccentColor then
            local r, g, b, a = addon:GetAddonAccentColor()
            return { r, g, b, a }
        end
    end
    return settings.borderColor or DEFAULTS.borderColor
end

local function ApplyAppearance()
    CreateCounterFrame()

    local settings = GetSettings()
    if not settings then return end

    local frame = CounterState.frame
    frame:SetSize(settings.width or DEFAULTS.width, settings.height or DEFAULTS.height)

    if not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("atonementCounter")) then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.xOffset or DEFAULTS.xOffset, settings.yOffset or DEFAULTS.yOffset)
    end

    local fontName = settings.useCustomFont and settings.font or nil
    local fontPath = UIKit.ResolveFontPath(fontName)
    frame.countText:SetFont(fontPath, settings.fontSize or DEFAULTS.fontSize, "OUTLINE")

    if settings.hideIcon then
        frame.icon:Hide()
    else
        frame.icon:Show()
    end

    local borderSize = settings.borderSize or DEFAULTS.borderSize
    local borderTexture = settings.borderTexture or DEFAULTS.borderTexture
    local hideBorder = settings.hideBorder
    local useLSMBorder = borderTexture ~= "None" and borderSize > 0 and not hideBorder
    local borderColor = GetBorderColor(settings)
    local showBackdrop = settings.showBackdrop
    if showBackdrop == nil then showBackdrop = true end

    local SSB = QUICore and QUICore.SafeSetBackdrop
    if showBackdrop or useLSMBorder then
        local backdropInfo = UIKit.GetBackdropInfo(hideBorder and "None" or borderTexture, hideBorder and 0 or borderSize, frame)
        if SSB then
            SSB(frame, backdropInfo, useLSMBorder and borderColor or nil)
        else
            frame:SetBackdrop(backdropInfo)
        end

        if showBackdrop then
            local bgColor = settings.backdropColor or DEFAULTS.backdropColor
            frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
        else
            frame:SetBackdropColor(0, 0, 0, 0)
        end

        if useLSMBorder and not SSB then
            frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
    else
        if SSB then
            SSB(frame, nil)
        else
            frame:SetBackdrop(nil)
        end
    end

    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, borderSize, borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1, useLSMBorder or hideBorder)
end

local function ShouldShowCounter(settings)
    if CounterState.isPreviewMode then
        return true
    end
    if not settings or not settings.enabled then
        return false
    end
    if not IsDisciplinePriest() then
        return false
    end
    if not IsInGroup() then
        return false
    end
    if settings.showOnlyInInstance and ns.Utils and ns.Utils.IsInInstancedContent and not ns.Utils.IsInInstancedContent() then
        return false
    end
    return true
end

local function UpdateCounterDisplay()
    CreateCounterFrame()

    local settings = GetSettings()
    if not settings then
        CounterState.frame:Hide()
        return
    end

    ApplyAppearance()

    if not ShouldShowCounter(settings) then
        CounterState.frame:Hide()
        return
    end

    CounterState.count = CounterState.isPreviewMode and PREVIEW_COUNT or CountActiveAtonements()

    local textColor = GetTextColor(settings, CounterState.count)
    CounterState.frame.countText:SetText(CounterState.count)
    CounterState.frame.countText:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)

    if not settings.hideIcon then
        if CounterState.count > 0 or CounterState.isPreviewMode then
            CounterState.frame.icon:SetDesaturated(false)
            CounterState.frame.icon:SetVertexColor(1, 1, 1, 0.8)
        else
            CounterState.frame.icon:SetDesaturated(true)
            CounterState.frame.icon:SetVertexColor(1, 1, 1, 0.35)
        end
    end

    local locked = settings.locked ~= false
    CounterState.frame:SetMovable(not locked and not InCombatLockdown())
    CounterState.frame:Show()
end

local function RefreshAtonementCounter()
    refreshQueued = false
    UpdateCounterDisplay()
end

local function QueueRefresh()
    if refreshQueued then
        return
    end
    refreshQueued = true
    refreshFrame:Show()
end

refreshFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    RefreshAtonementCounter()
end)

local function TogglePreview(enable)
    CounterState.isPreviewMode = enable and true or false
    RefreshAtonementCounter()
end

local function IsPreviewMode()
    return CounterState.isPreviewMode
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- UNIT_AURA: subscribe to centralized dispatcher instead of global RegisterEvent.
-- Avoids duplicate Lua dispatch for every unit aura event in raids.
-- Roster filter handles player/party/raid membership at the dispatcher level,
-- so we skip target/focus/boss/nameplate/arena/mouseover events entirely.
ns.AuraEvents:Subscribe("roster", function(unit)
    if not IsDisciplinePriest() then return end
    QueueRefresh()
end)
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit ~= "player" then
            return
        end
    end

    QueueRefresh()
end)

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AtonementCounter", frame = eventFrame }

_G.QUI_RefreshAtonementCounter = RefreshAtonementCounter
_G.QUI_ToggleAtonementCounterPreview = TogglePreview

QUI.AtonementCounter = {
    Refresh = RefreshAtonementCounter,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}

if ns.Registry then
    ns.Registry:Register("atonementCounter", {
        refresh = _G.QUI_RefreshAtonementCounter,
        priority = 40,
        group = "trackers",
        importCategories = { "trackersTimers" },
    })
end

C_Timer.After(0, RefreshAtonementCounter)
