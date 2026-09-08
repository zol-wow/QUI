local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local function GeneralFontFace()
    return (ns.Helpers and ns.Helpers.GetGeneralFont and ns.Helpers.GetGeneralFont()) or STANDARD_TEXT_FONT
end

local function GetSkinBase()
    return ns.SkinBase
end

local inspectPaneInitialized = false
local inspectOverlays = {}
local inspectLayoutApplied = false
local currentInspectTab = 1

local pendingInspectMode = nil
local pendingInspectTab  = nil
local pendingInspectScale = nil
local pendingInspectLayout = false
local pendingInspectRosterRefresh = false
local ApplyInspectPaneLayout
local RefreshInspectUnitAfterRosterUpdate
local InspectModeHandlers = {}

local inspectCombatFrame = CreateFrame("Frame")
inspectCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
inspectCombatFrame:SetScript("OnEvent", function()
    if not pendingInspectMode and not pendingInspectScale and not pendingInspectLayout and not pendingInspectRosterRefresh then return end
    if not InspectFrame or not InspectFrame:IsShown() then
        pendingInspectMode = nil
        pendingInspectTab  = nil
        pendingInspectScale = nil
        pendingInspectLayout = false
        pendingInspectRosterRefresh = false
        return
    end

    if pendingInspectMode then
        local handler = InspectModeHandlers[pendingInspectMode]
        if handler then handler() end
        pendingInspectMode = nil
        pendingInspectTab  = nil
    end

    if pendingInspectScale then
        InspectFrame:SetScale(pendingInspectScale)
        pendingInspectScale = nil
        if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.RefreshScale then
            _G.QUI_InspectFrameSkinning.RefreshScale()
        end
    end

    if pendingInspectLayout then
        pendingInspectLayout = false
        if ApplyInspectPaneLayout then
            ApplyInspectPaneLayout(true)
        end
    end

    if pendingInspectRosterRefresh then
        pendingInspectRosterRefresh = false
        if RefreshInspectUnitAfterRosterUpdate then
            RefreshInspectUnitAfterRosterUpdate()
        end
    end
end)
local inspectSettingsPanel = nil
local currentInspectGUID = nil
local pendingInspectReadyGUID = nil
local inspectSessionGUID = nil
local inspectSessionUnit = nil
local RefreshCurrentInspectGUID

local function SetInsetPixelPoints(region, relativeTo, pixels)
    local skinBase = GetSkinBase()
    if skinBase and skinBase.SetInsetPixelPoints then
        skinBase.SetInsetPixelPoints(region, relativeTo, pixels)
    end
end

local function DisablePixelSnap(region)
    local skinBase = GetSkinBase()
    if skinBase and skinBase.DisablePixelSnap then
        skinBase.DisablePixelSnap(region)
    end
end

local function ApplyOnePixelBorder(frame, withBackground, borderColor, bgColor)
    local skinBase = GetSkinBase()
    if skinBase and skinBase.ApplyChromeBackdrop then
        skinBase.ApplyChromeBackdrop(frame, {
            withBackground = withBackground,
            withInsets = withBackground,
            borderColor = borderColor,
            bgColor = bgColor,
        })
    end
end

local function SetOnePixelBorderColors(frame, borderColor, bgColor)
    local skinBase = GetSkinBase()
    if skinBase and skinBase.SetBackdropColors then
        skinBase.SetBackdropColors(frame, borderColor, bgColor)
    end
end

local function SetInspectScaleDeferred(scale)
    if not InspectFrame then return end
    if InCombatLockdown() then
        pendingInspectScale = scale
    else
        InspectFrame:SetScale(scale)
        if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.RefreshScale then
            _G.QUI_InspectFrameSkinning.RefreshScale()
        end
    end
end

local liteOverlays = {}
local liteOverallDisplay = nil

local frameState, GetState = Helpers.CreateStateTable()
local inspectGuildNilGuard = Helpers.CreateStateTable()
local EMPTY = {}

local function GetShared()
    return ns.QUI.CharacterShared or {}
end

local function GetSettings()
    local shared = GetShared()
    if shared.GetSettings then
        return shared.GetSettings()
    end
    return {
        inspectEnabled = true,
        showInspectItemName = true,
        showInspectItemLevel = true,
        showInspectEnchants = true,
        showInspectGems = true,
        inspectPanelScale = 1.0,
        inspectSlotTextSize = 12,
        inspectEnchantClassColor = true,
        inspectEnchantTextColor = {0.376, 0.647, 0.980},
        inspectNoEnchantTextColor = {0.5, 0.5, 0.5},
        inspectUpgradeTrackColor = {0.98, 0.60, 0.35, 1},
        inspectLiteMode = false,
        inspectLiteShowPerSlot = true,
        inspectLiteShowOverall = true,
        inspectLiteFontSize = 15,
        inspectLiteOverallFontSize = 11,
        inspectLiteOverallOffsetX = 0,
        inspectLiteOverallOffsetY = -8,
    }
end

local function IsCharacterModuleEnabled(settings)
    settings = settings or GetSettings()
    return not (settings and settings.enabled == false)
end

local function IsFullInspectEnabled(settings)
    settings = settings or GetSettings()
    return IsCharacterModuleEnabled(settings) and settings.inspectEnabled ~= false
end

local function GetColors()
    local shared = GetShared()
    return shared.C or {
        bg = { 0.067, 0.094, 0.153, 0.95 },
        accent = { 0.376, 0.647, 0.980, 1 },
        text = { 0.953, 0.957, 0.965, 1 },
        border = { 0.2, 0.25, 0.3, 1 },
    }
end

local COUNTED_SLOTS = {
    [INVSLOT_HEAD] = true,
    [INVSLOT_NECK] = true,
    [INVSLOT_SHOULDER] = true,
    [INVSLOT_BACK] = true,
    [INVSLOT_CHEST] = true,
    [INVSLOT_WAIST] = true,
    [INVSLOT_LEGS] = true,
    [INVSLOT_FEET] = true,
    [INVSLOT_WRIST] = true,
    [INVSLOT_HAND] = true,
    [INVSLOT_FINGER1] = true,
    [INVSLOT_FINGER2] = true,
    [INVSLOT_TRINKET1] = true,
    [INVSLOT_TRINKET2] = true,
    [INVSLOT_MAINHAND] = true,
    [INVSLOT_OFFHAND] = true,
}

local TOOLTIP_LINE_TYPE_ITEM_LEVEL = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemLevel or 31

local CleanTooltipText = GetShared().CleanTooltipText
local ReadableNumber = GetShared().ReadableNumber

local function GetReadableUnitGUID(unit)
    if not unit or not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or Helpers.IsSecretValue(guid) then
        return nil
    end
    return guid
end

local function TrackInspectSessionUnit(unit)
    local guid = GetReadableUnitGUID(unit)
    if guid then
        inspectSessionGUID = guid
        inspectSessionUnit = unit
    end
    return guid
end

local function IsInspectGUIDMatch(unit, guid)
    if not unit or not guid then return false end
    local unitGUID = GetReadableUnitGUID(unit)
    return unitGUID == guid
end

local function ResolveInspectUnitByGUID(guid)
    if not guid then return nil end

    local function match(unit)
        return IsInspectGUIDMatch(unit, guid) and unit or nil
    end

    local unit = InspectFrame and InspectFrame.unit
    unit = match(unit)
    if unit then return unit end

    unit = match(inspectSessionUnit)
    if unit then return unit end

    unit = match("target")
    if unit then return unit end

    unit = match("focus")
    if unit then return unit end

    unit = match("mouseover")
    if unit then return unit end

    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            unit = "raid" .. i
            if match(unit) then return unit end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            unit = "party" .. i
            if match(unit) then return unit end
        end
    end

    return nil
end

RefreshInspectUnitAfterRosterUpdate = function()
    if not IsCharacterModuleEnabled(GetSettings()) then return false end
    if not InspectFrame or not InspectFrame:IsShown() then return false end

    local guid = inspectSessionGUID or currentInspectGUID or pendingInspectReadyGUID
    if not guid then
        guid = TrackInspectSessionUnit(InspectFrame.unit or inspectSessionUnit or "target")
    end
    if not guid then return false end

    local resolvedUnit = ResolveInspectUnitByGUID(guid)
    if not resolvedUnit then return false end

    inspectSessionUnit = resolvedUnit

    if InspectFrame.unit ~= resolvedUnit then
        if InCombatLockdown() then
            pendingInspectRosterRefresh = true
            return false
        end

        InspectFrame.unit = resolvedUnit
        _G.INSPECTED_UNIT = resolvedUnit
    end

    RefreshCurrentInspectGUID(resolvedUnit)

    if not InCombatLockdown() then
        ns.SafeCallMethodIfPresent("best-effort-style", InspectFrame, "SetPortraitToUnit", resolvedUnit)
        if InspectFrame.SetTitle and GetUnitName then
            local ok, name = pcall(GetUnitName, resolvedUnit, true)
            if ok and name and not Helpers.IsSecretValue(name) then
                ns.SafeCallMethod("best-effort-style", InspectFrame, "SetTitle", name)
            end
        end
        if type(_G.InspectFrame_UpdateTabs) == "function" then
            ns.SafeCall("best-effort-style", _G.InspectFrame_UpdateTabs)
        end
    end

    local shared = GetShared()
    if shared.ScheduleUpdate then
        C_Timer.After(0, shared.ScheduleUpdate)
    end

    return true
end

RefreshCurrentInspectGUID = function(unit)
    local guid = TrackInspectSessionUnit(unit)
    if not guid then
        currentInspectGUID = nil
        return false
    end

    if currentInspectGUID == guid then
        return true
    end

    if pendingInspectReadyGUID == guid then
        currentInspectGUID = guid
        pendingInspectReadyGUID = nil
        return true
    end

    currentInspectGUID = nil
    return false
end

local function IsCurrentInspectUnit(unit)
    return RefreshCurrentInspectGUID(unit)
end

local GetReadableInventoryItemLink = GetShared().GetReadableInventoryItemLink
local GetInventoryTooltipData = GetShared().GetInventoryTooltipData
local MatchItemLevelText = GetShared().MatchItemLevelText

local function GetSlotItemLevel(unit, slotId)
    if not unit or not slotId then return nil end

    local itemLink = GetReadableInventoryItemLink(unit, slotId)
    if itemLink and C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, actualItemLevel, _, sparseItemLevel = ns.SafeCall("best-effort-style", C_Item.GetDetailedItemLevelInfo, itemLink)
        if ok then
            actualItemLevel = ReadableNumber(actualItemLevel)
            if actualItemLevel and actualItemLevel > 0 then
                return actualItemLevel
            end
            sparseItemLevel = ReadableNumber(sparseItemLevel)
            if sparseItemLevel and sparseItemLevel > 0 then
                return sparseItemLevel
            end
        end
    end

    local tooltipData = GetInventoryTooltipData(unit, slotId)
    if tooltipData then
        for _, line in ipairs(tooltipData.lines) do
            local lineType = ReadableNumber(line.type)
            if lineType == TOOLTIP_LINE_TYPE_ITEM_LEVEL then
                local ilvl = MatchItemLevelText(line.leftText)
                if ilvl then return ilvl end
            end
        end
        for _, line in ipairs(tooltipData.lines) do
            local ilvl = MatchItemLevelText(line.leftText)
            if ilvl then
                return ilvl
            end
        end
    end

    return nil
end

local function GetSlotItemQuality(unit, slotId)
    if not unit or not slotId then return nil end

    local itemLink = GetReadableInventoryItemLink(unit, slotId)
    if not itemLink then return nil end

    local ok, quality = pcall(C_Item.GetItemQualityByID, itemLink)
    if ok and not Helpers.IsSecretValue(quality) then return quality end

    return nil
end

local function IsMainHand2H(unit)
    local itemLink = GetReadableInventoryItemLink(unit, INVSLOT_MAINHAND)
    if not itemLink then return false end

    if not (C_Item and C_Item.GetItemInfo) then return false end

    local ok, equipSlot = pcall(function()
        return select(9, C_Item.GetItemInfo(itemLink))
    end)
    if not ok or Helpers.IsSecretValue(equipSlot) then return false end
    return equipSlot == "INVTYPE_2HWEAPON"
end

local function CalculateAverageILvl(unit)
    if unit and unit ~= "player" and IsCurrentInspectUnit(unit)
        and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
    then
        local ok, equippedItemLevel = ns.SafeCall("best-effort-style", C_PaperDollInfo.GetInspectItemLevel, unit)
        equippedItemLevel = ok and ReadableNumber(equippedItemLevel) or nil
        if equippedItemLevel and equippedItemLevel > 0 then
            return equippedItemLevel
        end
    end

    local totalIlvl = 0
    local slotCount = 0
    local is2H = IsMainHand2H(unit)

    for slotId, counted in pairs(COUNTED_SLOTS) do
        if counted then
            if slotId == INVSLOT_OFFHAND and is2H then
                local mainIlvl = GetSlotItemLevel(unit, INVSLOT_MAINHAND)
                if mainIlvl and mainIlvl > 0 then
                    totalIlvl = totalIlvl + mainIlvl
                    slotCount = slotCount + 1
                end
            else
                local ilvl = GetSlotItemLevel(unit, slotId)
                if ilvl and ilvl > 0 then
                    totalIlvl = totalIlvl + ilvl
                    slotCount = slotCount + 1
                end
            end
        end
    end

    if slotCount > 0 then
        return totalIlvl / slotCount
    end
    return 0
end

local function CalculateAverageEquippedQuality(unit)
    local totalQuality = 0
    local itemCount = 0
    local is2H = IsMainHand2H(unit)

    for slotId, counted in pairs(COUNTED_SLOTS) do
        if counted then
            if slotId == INVSLOT_OFFHAND and is2H then
                local mainQuality = GetSlotItemQuality(unit, INVSLOT_MAINHAND)
                if mainQuality and mainQuality >= 1 then
                    totalQuality = totalQuality + mainQuality
                    itemCount = itemCount + 1
                end
            else
                local quality = GetSlotItemQuality(unit, slotId)
                if quality and quality >= 1 then
                    totalQuality = totalQuality + quality
                    itemCount = itemCount + 1
                end
            end
        end
    end

    if itemCount > 0 then
        return math.floor((totalQuality / itemCount) + 0.5)
    end
    return 1
end

local function GetOverallILvlColor(unit)
    local avgQuality = CalculateAverageEquippedQuality(unit)
    avgQuality = math.max(1, math.min(avgQuality, 7))
    local r, g, b = C_Item.GetItemQualityColor(avgQuality)
    return r, g, b
end

local INSPECT_CONFIG = {
    FRAME_TARGET_WIDTH = 500,
    FRAME_DEFAULT_WIDTH = 338,
    CLOSE_BUTTON_EXTENDED_X = -2,
    CLOSE_BUTTON_NORMAL_X = -2,
    CLOSE_BUTTON_Y = -2,
    MAINHAND_X_OFFSET = -25,
    MAINHAND_Y_OFFSET = -42,
    OFFHAND_SPACING = 30,
    BASE_SCALE = 1.30,
}

local INSPECT_SLOT_NAMES = {
    "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot",
    "InspectBackSlot", "InspectChestSlot", "InspectShirtSlot",
    "InspectTabardSlot", "InspectWristSlot", "InspectHandsSlot",
    "InspectWaistSlot", "InspectLegsSlot", "InspectFeetSlot",
    "InspectFinger0Slot", "InspectFinger1Slot",
    "InspectTrinket0Slot", "InspectTrinket1Slot",
    "InspectMainHandSlot", "InspectSecondaryHandSlot",
}

local function GetCurrentInspectTab()
    return currentInspectTab
end

local function RepositionInspectTabs()
    local tabs = { InspectFrameTab1, InspectFrameTab2, InspectFrameTab3 }
    local firstTab = tabs[1]

    if firstTab then
        firstTab:ClearAllPoints()
        firstTab:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", 15, -81)
    end

    local talentsBtn = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame.InspectTalents
    if talentsBtn and InspectTrinket1Slot then
        talentsBtn:ClearAllPoints()
        talentsBtn:SetPoint("TOP", InspectTrinket1Slot, "BOTTOM", -12, -31)
    end
end

local function ResetInspectTabsPosition()
    local firstTab = InspectFrameTab1
    if firstTab then
        firstTab:ClearAllPoints()
        firstTab:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", 15, -30)
    end
end

local function RepositionInspectSlots()
    if not InspectFrame then return end

    local vpad = 14
    local SLOT_SCALE = 0.90
    local TOP_OFFSET = -75
    local LEFT_X = 20
    local RIGHT_X = 493

    local allSlots = {
        InspectHeadSlot, InspectNeckSlot, InspectShoulderSlot,
        InspectBackSlot, InspectChestSlot, InspectShirtSlot,
        InspectTabardSlot, InspectWristSlot,
        InspectHandsSlot, InspectWaistSlot, InspectLegsSlot,
        InspectFeetSlot, InspectFinger0Slot, InspectFinger1Slot,
        InspectTrinket0Slot, InspectTrinket1Slot,
        InspectMainHandSlot, InspectSecondaryHandSlot,
    }

    for _, slot in ipairs(allSlots) do
        if slot then slot:SetScale(SLOT_SCALE) end
    end

    if InspectHeadSlot then
        InspectHeadSlot:ClearAllPoints()
        InspectHeadSlot:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", LEFT_X, TOP_OFFSET)
    end

    if InspectNeckSlot then
        InspectNeckSlot:ClearAllPoints()
        InspectNeckSlot:SetPoint("TOPLEFT", InspectHeadSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectShoulderSlot then
        InspectShoulderSlot:ClearAllPoints()
        InspectShoulderSlot:SetPoint("TOPLEFT", InspectNeckSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectBackSlot then
        InspectBackSlot:ClearAllPoints()
        InspectBackSlot:SetPoint("TOPLEFT", InspectShoulderSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectChestSlot then
        InspectChestSlot:ClearAllPoints()
        InspectChestSlot:SetPoint("TOPLEFT", InspectBackSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectShirtSlot then
        InspectShirtSlot:ClearAllPoints()
        InspectShirtSlot:SetPoint("TOPLEFT", InspectChestSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectTabardSlot then
        InspectTabardSlot:ClearAllPoints()
        InspectTabardSlot:SetPoint("TOPLEFT", InspectShirtSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectHandsSlot then
        InspectHandsSlot:ClearAllPoints()
        InspectHandsSlot:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", RIGHT_X, TOP_OFFSET)
    end

    if InspectWaistSlot then
        InspectWaistSlot:ClearAllPoints()
        InspectWaistSlot:SetPoint("TOPLEFT", InspectHandsSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectLegsSlot then
        InspectLegsSlot:ClearAllPoints()
        InspectLegsSlot:SetPoint("TOPLEFT", InspectWaistSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectFeetSlot then
        InspectFeetSlot:ClearAllPoints()
        InspectFeetSlot:SetPoint("TOPLEFT", InspectLegsSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectFinger0Slot then
        InspectFinger0Slot:ClearAllPoints()
        InspectFinger0Slot:SetPoint("TOPLEFT", InspectFeetSlot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectFinger1Slot then
        InspectFinger1Slot:ClearAllPoints()
        InspectFinger1Slot:SetPoint("TOPLEFT", InspectFinger0Slot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectTrinket0Slot then
        InspectTrinket0Slot:ClearAllPoints()
        InspectTrinket0Slot:SetPoint("TOPLEFT", InspectFinger1Slot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectTrinket1Slot then
        InspectTrinket1Slot:ClearAllPoints()
        InspectTrinket1Slot:SetPoint("TOPLEFT", InspectTrinket0Slot, "BOTTOMLEFT", 0, -vpad)
    end

    if InspectWristSlot and InspectTrinket1Slot and InspectHeadSlot then
        InspectWristSlot:ClearAllPoints()
        InspectWristSlot:SetPoint("TOP", InspectTrinket1Slot, "TOP", 0, 0)
        InspectWristSlot:SetPoint("LEFT", InspectHeadSlot, "LEFT", 0, 0)
    end

    if InspectMainHandSlot then
        InspectMainHandSlot:ClearAllPoints()
        InspectMainHandSlot:SetPoint("BOTTOM", InspectFrame, "BOTTOM", INSPECT_CONFIG.MAINHAND_X_OFFSET, INSPECT_CONFIG.MAINHAND_Y_OFFSET)
    end

    if InspectSecondaryHandSlot and InspectMainHandSlot then
        InspectSecondaryHandSlot:ClearAllPoints()
        InspectSecondaryHandSlot:SetPoint("LEFT", InspectMainHandSlot, "RIGHT", INSPECT_CONFIG.OFFHAND_SPACING, 0)
    end

    RepositionInspectTabs()
end

local function BlockInspectIconBorder(iconBorder)
    if not iconBorder or (frameState[iconBorder] or EMPTY).blocked then return end
    GetState(iconBorder).blocked = true
    iconBorder:SetAlpha(0)
    if iconBorder.SetTexture then iconBorder:SetTexture(nil) end
    Helpers.DeferredSetAtlasBlock(iconBorder, false)
end

local function SkinInspectEquipmentSlot(slot)
    if not slot or (frameState[slot] or EMPTY).skinned then return end
    GetState(slot).skinned = true

    local normalTex = slot:GetNormalTexture()
    if normalTex then normalTex:SetAlpha(0) end

    if slot.BottomRightSlotTexture then
        slot.BottomRightSlotTexture:Hide()
    end

    local preserve = {
        [slot.icon or false] = true,
        [slot.Icon or false] = true,
        [slot.ItemContextOverlay or false] = true,
        [slot.IconOverlay or false] = true,
        [slot.IconOverlay2 or false] = true,
        [slot.searchOverlay or false] = true,
        [slot.IconQuestTexture or false] = true,
    }
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            if not preserve[region] then
                region:SetAlpha(0)
            end
        end
    end

    if slot.IconBorder then
        BlockInspectIconBorder(slot.IconBorder)
    end

    local iconTex = slot.icon or slot.Icon
    if iconTex and iconTex.SetTexCoord then
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local slotState = GetState(slot)
    if not slotState.borderFrame then
        slotState.borderFrame = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        slotState.borderFrame:SetFrameLevel(slot:GetFrameLevel() + 10)
        slotState.borderFrame:SetAllPoints(slot)
        ApplyOnePixelBorder(slotState.borderFrame, false)
    end
end

local function UpdateInspectSlotBorder(slot, unit)
    local borderFrame = slot and (frameState[slot] or EMPTY).borderFrame
    if not borderFrame then return end

    local slotID = slot:GetID()
    unit = unit or "target"

    local itemLink = GetReadableInventoryItemLink(unit, slotID)
    local quality = nil
    if itemLink then
        local ok, q = pcall(C_Item.GetItemQualityByID, itemLink)
        if ok and not Helpers.IsSecretValue(q) then quality = q end
    end

    if quality and quality >= 1 then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        SetOnePixelBorderColors(borderFrame, { r, g, b, 1 })
        borderFrame:Show()
    else
        borderFrame:Hide()
    end
end

local inspectSlotUpdateHooked = false
local function HookInspectSlotUpdate()
    if inspectSlotUpdateHooked then return end
    if type(_G.InspectPaperDollItemSlotButton_Update) ~= "function" then return end
    inspectSlotUpdateHooked = true
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        if button and button.IconBorder then button.IconBorder:SetAlpha(0) end
    end)
end

local function SkinAllInspectSlots()
    HookInspectSlotUpdate()
    for _, slotName in ipairs(INSPECT_SLOT_NAMES) do
        local slot = _G[slotName]
        if slot then
            SkinInspectEquipmentSlot(slot)
        end
    end
end

local function UpdateAllInspectSlotBorders(unit)
    for _, slotName in ipairs(INSPECT_SLOT_NAMES) do
        local slot = _G[slotName]
        if slot then
            UpdateInspectSlotBorder(slot, unit)
        end
    end
end

local function PositionInspectModelScene()
    if not InspectModelFrame then return end

    InspectModelFrame:ClearAllPoints()
    InspectModelFrame:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 55, -85)
    InspectModelFrame:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT", -55, 65)
    InspectModelFrame:SetFrameLevel(2)

    if InspectModelFrame.controlFrame then
        InspectModelFrame.controlFrame:Hide()
    end

    if InspectModelFrame.ResetModel then
        InspectModelFrame:ResetModel()
    end

    InspectModelFrame:Show()
end

local function CalculateInspectAverageILvl(unit)
    return CalculateAverageILvl(unit)
end

local LITE_SLOT_IDS = {
    InspectHeadSlot = INVSLOT_HEAD,
    InspectNeckSlot = INVSLOT_NECK,
    InspectShoulderSlot = INVSLOT_SHOULDER,
    InspectBackSlot = INVSLOT_BACK,
    InspectChestSlot = INVSLOT_CHEST,
    InspectWristSlot = INVSLOT_WRIST,
    InspectHandsSlot = INVSLOT_HAND,
    InspectWaistSlot = INVSLOT_WAIST,
    InspectLegsSlot = INVSLOT_LEGS,
    InspectFeetSlot = INVSLOT_FEET,
    InspectFinger0Slot = INVSLOT_FINGER1,
    InspectFinger1Slot = INVSLOT_FINGER2,
    InspectTrinket0Slot = INVSLOT_TRINKET1,
    InspectTrinket1Slot = INVSLOT_TRINKET2,
    InspectMainHandSlot = INVSLOT_MAINHAND,
    InspectSecondaryHandSlot = INVSLOT_OFFHAND,
}

local function CreateLiteSlotText(slotFrame)
    if not slotFrame then return nil end

    local shared = GetShared()
    local font = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
    local settings = GetSettings()
    local fontSize = settings.inspectLiteFontSize or 15

    local text = slotFrame:CreateFontString(nil, "OVERLAY")
    CJKFont(text, font, fontSize, "OUTLINE")
    text:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:Hide()

    return text
end

local function CreateLiteOverallDisplay()
    if liteOverallDisplay then return liteOverallDisplay end
    if not InspectFrame or not InspectWristSlot then return nil end

    local shared = GetShared()
    local font = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
    local settings = GetSettings()
    local fontSize = settings.inspectLiteOverallFontSize or 11
    local offsetX = settings.inspectLiteOverallOffsetX or 0
    local offsetY = settings.inspectLiteOverallOffsetY or -8

    local frame = CreateFrame("Frame", nil, InspectFrame)
    frame:SetSize(80, 24)
    frame:SetPoint("TOP", InspectWristSlot, "BOTTOM", offsetX, offsetY)
    frame:SetFrameLevel(InspectFrame:GetFrameLevel() + 15)

    local label = frame:CreateFontString(nil, "OVERLAY")
    CJKFont(label, font, fontSize, "OUTLINE")
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    label:SetText(ns.L["iLvL:"])
    label:SetTextColor(0.8, 0.8, 0.8, 1)

    local value = frame:CreateFontString(nil, "OVERLAY")
    CJKFont(value, font, fontSize, "OUTLINE")
    value:SetPoint("LEFT", label, "RIGHT", 4, 0)

    frame.label = label
    frame.value = value
    frame:Hide()

    liteOverallDisplay = frame
    return frame
end

local function UpdateLiteSlotText(slotName, unit, settings, cachedFont)
    local slotFrame = _G[slotName]
    if not slotFrame then return end

    local slotId = LITE_SLOT_IDS[slotName]
    if not slotId then return end

    if not liteOverlays[slotName] then
        liteOverlays[slotName] = CreateLiteSlotText(slotFrame)
    end

    local text = liteOverlays[slotName]
    if not text then return end

    settings = settings or GetSettings()
    local font = cachedFont or (function()
        local shared = GetShared()
        return shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
    end)()

    local fontSize = settings.inspectLiteFontSize or 15
    CJKFont(text, font, fontSize, "OUTLINE")

    if not settings.inspectLiteShowPerSlot then
        text:Hide()
        return
    end

    local itemLink = GetReadableInventoryItemLink(unit, slotId)
    if not itemLink then
        text:Hide()
        return
    end

    local ilvl = GetSlotItemLevel(unit, slotId)
    if not ilvl or ilvl <= 0 then
        text:Hide()
        return
    end

    local quality = GetSlotItemQuality(unit, slotId)

    text:SetText(tostring(math.floor(ilvl)))

    if quality and quality >= 1 then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        text:SetTextColor(r, g, b, 1)
    else
        text:SetTextColor(1, 1, 1, 1)
    end

    text:Show()
end

local function UpdateLiteOverallDisplay(unit, settings, cachedFont)
    local frame = liteOverallDisplay or CreateLiteOverallDisplay()
    if not frame then return end

    settings = settings or GetSettings()
    local font = cachedFont or (function()
        local shared = GetShared()
        return shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
    end)()

    local fontSize = settings.inspectLiteOverallFontSize or 11
    if frame.label then
        CJKFont(frame.label, font, fontSize, "OUTLINE")
    end
    if frame.value then
        CJKFont(frame.value, font, fontSize, "OUTLINE")
    end

    local offsetX = settings.inspectLiteOverallOffsetX or 0
    local offsetY = settings.inspectLiteOverallOffsetY or -8
    frame:ClearAllPoints()
    frame:SetPoint("TOP", InspectWristSlot, "BOTTOM", offsetX, offsetY)

    if not settings.inspectLiteShowOverall then
        frame:Hide()
        return
    end

    local avgIlvl = CalculateInspectAverageILvl(unit)
    if avgIlvl <= 0 then
        frame:Hide()
        return
    end

    local r, g, b = GetOverallILvlColor(unit)

    frame.value:SetText(string.format("%.1f", avgIlvl))
    frame.value:SetTextColor(r, g, b, 1)

    frame:Show()
end

local function UpdateAllLiteDisplays(unit)
    local settings = GetSettings()

    local shared = GetShared()
    local cachedFont = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"

    if settings.inspectLiteShowPerSlot then
        for _, slotName in ipairs(INSPECT_SLOT_NAMES) do
            UpdateLiteSlotText(slotName, unit, settings, cachedFont)
        end
    else
        for slotName, text in pairs(liteOverlays) do
            if text then text:Hide() end
        end
    end

    UpdateLiteOverallDisplay(unit, settings, cachedFont)
end

local function HideLiteDisplays()
    for slotName, text in pairs(liteOverlays) do
        if text then
            text:Hide()
        end
    end
    if liteOverallDisplay then
        liteOverallDisplay:Hide()
    end
end

local function HideDetailedOverlays()
    for _, overlay in pairs(inspectOverlays) do
        if overlay then
            overlay:Hide()
        end
    end
end

local function SetupInspectTitleArea()
    if not InspectFrame then return end

    local shared = GetShared()
    local font = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"

    if InspectFrame.TitleContainer and InspectFrame.TitleContainer.TitleText then
        InspectFrame.TitleContainer.TitleText:Hide()
    end

    if InspectLevelText then
        InspectLevelText:Hide()
    end

    local inspState = GetState(InspectFrame)
    if not inspState.ilvlDisplay then
        local displayFrame = CreateFrame("Frame", nil, InspectFrame)
        displayFrame:SetSize(400, 30)
        displayFrame:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 19, -10)
        displayFrame:SetFrameLevel(InspectFrame:GetFrameLevel() + 10)

        local nameText = displayFrame:CreateFontString(nil, "OVERLAY")
        CJKFont(nameText, font, 12, "")
        nameText:SetPoint("TOPLEFT", displayFrame, "TOPLEFT", 0, 0)
        nameText:SetJustifyH("LEFT")

        local specText = InspectFrame:CreateFontString(nil, "OVERLAY")
        CJKFont(specText, font, 12, "")
        specText:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", -70, -10)
        specText:SetJustifyH("RIGHT")

        displayFrame.text = nameText
        displayFrame.specText = specText
        inspState.ilvlDisplay = displayFrame
    end

    if not inspState.centerILvl then
        local centerFrame = CreateFrame("Frame", nil, InspectFrame)
        centerFrame:SetSize(200, 20)
        centerFrame:SetPoint("TOP", InspectFrame, "TOP", 0, -10)
        centerFrame:SetFrameLevel(InspectFrame:GetFrameLevel() + 10)

        local centerText = centerFrame:CreateFontString(nil, "OVERLAY")
        CJKFont(centerText, font, 21, "OUTLINE")
        centerText:SetPoint("CENTER")
        centerText:SetJustifyH("CENTER")

        centerFrame.text = centerText
        inspState.centerILvl = centerFrame
    end
end

local function UpdateInspectILvlDisplay()
    local inspS = InspectFrame and frameState[InspectFrame] or EMPTY
    if not InspectFrame or not inspS.ilvlDisplay then return end

    local settings = GetSettings()
    if not IsFullInspectEnabled(settings) then return end

    local displayFrame = inspS.ilvlDisplay
    if not displayFrame.text then return end

    local shared = GetShared()
    local unit = InspectFrame.unit or "target"

    if not IsCurrentInspectUnit(unit) then
        displayFrame.text:SetText("")
        if displayFrame.specText then
            displayFrame.specText:SetText("")
        end
        local centerFrame = inspS.centerILvl
        if centerFrame and centerFrame.text then
            centerFrame.text:SetText("")
        end
        return
    end

    local ok, name = pcall(UnitName, unit)
    if Helpers.IsSecretValue(name) then name = nil end
    if not ok then name = nil end
    name = name or "Unknown"

    local level
    ok, level = ns.SafeCall("best-effort-style", UnitLevel, unit)
    level = ok and ReadableNumber(level) or nil
    level = level or 0

    local className = ""
    local _, classToken, classIndex
    ok, _, classToken, classIndex = pcall(UnitClass, unit)
    -- @secret-policy: collapse-only
    if Helpers.IsSecretValue(classToken) then classToken = nil end
    if not ok then classToken = nil end
    classIndex = ok and ReadableNumber(classIndex) or nil
    classIndex = classIndex or 0
    if classToken and classIndex > 0 and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local classInfo = C_CreatureInfo.GetClassInfo(classIndex)
        className = classInfo and classInfo.className or classToken
    elseif classToken then
        className = classToken
    end

    local specName = ""
    local specID
    ok, specID = ns.SafeCall("best-effort-style", GetInspectSpecialization, unit)
    specID = ok and ReadableNumber(specID) or nil
    specID = specID or 0
    if specID > 0 then
        local specOk, specNameLocal = pcall(function()
            return select(2, GetSpecializationInfoByID(specID))
        end)
        if specOk and not Helpers.IsSecretValue(specNameLocal) then
            specName = specNameLocal or ""
        end
    end

    local classColor = Helpers.GetClassColorTable(classToken)
    local r, g, b = 1, 1, 1
    if classColor then
        r, g, b = classColor.r, classColor.g, classColor.b
    end

    displayFrame.text:SetText(name)
    displayFrame.text:SetTextColor(r, g, b, 1)

    if displayFrame.specText then
        local abbreviatedClass = shared.AbbreviateClassName and shared.AbbreviateClassName(className) or className
        local specLine = string.format("%d %s %s", level, specName, abbreviatedClass)
        displayFrame.specText:SetText(specLine)
        displayFrame.specText:SetTextColor(r, g, b, 1)
    end

    local centerFrame = inspS.centerILvl
    if centerFrame and centerFrame.text then
        local equipped = CalculateInspectAverageILvl(unit)

        if equipped > 0 and shared.GetILvlColor then
            local eR, eG, eB = shared.GetILvlColor(equipped, unit)
            local equippedHex = string.format("%02x%02x%02x", math.floor(eR*255), math.floor(eG*255), math.floor(eB*255))
            local equippedStr = string.format("%.1f", equipped)
            centerFrame.text:SetText(string.format("|cff%s%s|r", equippedHex, equippedStr))
        else
            centerFrame.text:SetText("")
        end
    end
end

local function RepositionInspectCloseButton(extended)
    local closeButton = InspectFrame and (InspectFrame.CloseButton or InspectFrameCloseButton)
    if closeButton then
        closeButton:ClearAllPoints()
        local xOffset = extended and INSPECT_CONFIG.CLOSE_BUTTON_EXTENDED_X or INSPECT_CONFIG.CLOSE_BUTTON_NORMAL_X
        closeButton:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", xOffset, INSPECT_CONFIG.CLOSE_BUTTON_Y)
    end
end

local function SetInspectExtendedMode(tabNum)
    if not InspectFrame then return end
    currentInspectTab = tabNum

    if InCombatLockdown() then
        pendingInspectMode = "extended"
        pendingInspectTab  = tabNum
    else
        InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_TARGET_WIDTH)
        RepositionInspectTabs()
        RepositionInspectCloseButton(true)
    end

    if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.SetExtended then
        _G.QUI_InspectFrameSkinning.SetExtended(true)
    end
    local centerILvl = (frameState[InspectFrame] or EMPTY).centerILvl
    if centerILvl then
        centerILvl:Show()
    end
end

local function SetInspectNormalMode()
    if not InspectFrame then return end
    currentInspectTab = 3

    if InCombatLockdown() then
        pendingInspectMode = "normal"
        pendingInspectTab  = nil
    else
        InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_DEFAULT_WIDTH)
        ResetInspectTabsPosition()
        RepositionInspectCloseButton(false)
    end

    if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.SetExtended then
        _G.QUI_InspectFrameSkinning.SetExtended(false)
    end
    local centerILvl = (frameState[InspectFrame] or EMPTY).centerILvl
    if centerILvl then
        centerILvl:Hide()
    end
end

InspectModeHandlers["extended"] = function() SetInspectExtendedMode(pendingInspectTab or 1) end
InspectModeHandlers["normal"]   = SetInspectNormalMode

local function CreateInspectSettingsButton()
    if not InspectFrame then return end
    if (frameState[InspectFrame] or EMPTY).gearBtn then return end

    local core = GetCore()
    if not (core and core.db and core.db.profile and core.db.profile.character) then
        C_Timer.After(0.5, CreateInspectSettingsButton)
        return
    end
    local charDB = core.db.profile.character

    if charDB.inspectEnchantTextColor == nil then
        charDB.inspectEnchantTextColor = {0.376, 0.647, 0.980}
    end
    if charDB.inspectNoEnchantTextColor == nil then
        charDB.inspectNoEnchantTextColor = {0.5, 0.5, 0.5}
    end
    if charDB.inspectUpgradeTrackColor == nil then
        charDB.inspectUpgradeTrackColor = {0.98, 0.60, 0.35, 1}
    end
    if charDB.inspectSlotTextSize == nil then
        charDB.inspectSlotTextSize = 12
    end
    if charDB.inspectLiteMode == nil then
        charDB.inspectLiteMode = false
    end
    if charDB.inspectLiteShowPerSlot == nil then
        charDB.inspectLiteShowPerSlot = true
    end
    if charDB.inspectLiteShowOverall == nil then
        charDB.inspectLiteShowOverall = true
    end
    if charDB.inspectLiteFontSize == nil then
        charDB.inspectLiteFontSize = 15
    end
    if charDB.inspectLiteOverallFontSize == nil then
        charDB.inspectLiteOverallFontSize = 11
    end
    if charDB.inspectLiteOverallOffsetX == nil then
        charDB.inspectLiteOverallOffsetX = 0
    end
    if charDB.inspectLiteOverallOffsetY == nil then
        charDB.inspectLiteOverallOffsetY = -8
    end

    local shared = GetShared()
    local chrome = ns.CharacterChrome
    if not (chrome and chrome.CreateSettingsFlyout) then return end

    local function RefreshInspect()
        if InspectFrame and InspectFrame:IsShown() and shared.ScheduleUpdate then
            shared.ScheduleUpdate()
        end
    end

    local function RefreshInspectFonts()
        local settings = GetSettings()
        local slotTextSize = settings.inspectSlotTextSize or 12
        local slotFont = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
        local FONT_FLAGS = "OUTLINE"

        for _, overlay in pairs(inspectOverlays) do
            if overlay then
                if overlay.itemName and overlay.itemName.SetFont then
                    CJKFont(overlay.itemName, slotFont, slotTextSize, FONT_FLAGS)
                end
                if overlay.itemLevel and overlay.itemLevel.SetFont then
                    CJKFont(overlay.itemLevel, slotFont, slotTextSize, FONT_FLAGS)
                end
                if overlay.enchant and overlay.enchant.SetFont then
                    CJKFont(overlay.enchant, slotFont, slotTextSize, FONT_FLAGS)
                end
            end
        end

        RefreshInspect()
    end

    -- Same builder as the Character flyout: trigger width, offset, close and
    -- scrolling are the chrome owner's; only title and content differ.
    local flyout = chrome.CreateSettingsFlyout(InspectFrame, {
        title = ns.L["QUI Inspect Panel"],
        name = "QUI_InspectSettingsPanel",
        triggerName = "QUI_InspectSettingsBtn",
        triggerPoint = { "TOPRIGHT", InspectFrame, "TOPRIGHT", -5, -28 },
        extension = 0,
        provider = function(ctx)
        local GUI = ctx.GUI
        local scrollChild = ctx.scrollChild
        local PlaceRow, ResetRows, PAD = ctx.PlaceRow, ctx.ResetRows, ctx.PAD
        local y = ctx.y

    local appearHeader = GUI:CreateSectionHeader(scrollChild, ns.L["Appearance"])
    appearHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - appearHeader.gap
    ResetRows()

    local scaleSlider = GUI:CreateFormSlider(scrollChild, ns.L["Panel Scale"], 0.75, 1.5, 0.05, "inspectPanelScale", charDB, function()
        local multiplier = charDB.inspectPanelScale or 1.0
        SetInspectScaleDeferred(INSPECT_CONFIG.BASE_SCALE * multiplier)
    end, { deferOnDrag = true },
        { description = ns.L["Zoom factor applied to the inspect panel on top of the base scale. 1.0 leaves the panel at the default QUI size."] })
    y = PlaceRow(scaleSlider, y)

    local generalDB = core and core.db and core.db.profile and core.db.profile.general
    local bgColorPicker = nil
    if generalDB then
        bgColorPicker = GUI:CreateFormColorPicker(scrollChild, ns.L["Background Color"], "skinBgColor", generalDB, function()
            if _G.QUI_RefreshInspectColors then
                _G.QUI_RefreshInspectColors()
            end
            if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.Refresh then
                _G.QUI_InspectFrameSkinning.Refresh()
            end
        end, nil,
            { description = ns.L["Background color applied to the inspect panel. Shared with the global skinning background so character and inspect panels match."] })
        y = PlaceRow(bgColorPicker, y)

        ctx.HookShow(function()
            if bgColorPicker and bgColorPicker.swatch and generalDB and generalDB.skinBgColor then
                local col = generalDB.skinBgColor
                bgColorPicker.swatch:SetBackdropColor(col[1], col[2], col[3], col[4] or 1)
            end
        end)
    end

    y = y - 10

    local overlayHeader = GUI:CreateSectionHeader(scrollChild, ns.L["Slot Overlays"])
    overlayHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - overlayHeader.gap
    ResetRows()

    local showItemName = GUI:CreateFormCheckbox(scrollChild, ns.L["Show Equipment Name"], "showInspectItemName", charDB, RefreshInspect,
        { description = ns.L["Show the equipped item's name on each inspect slot overlay."] })
    y = PlaceRow(showItemName, y)

    local showIlvl = GUI:CreateFormCheckbox(scrollChild, ns.L["Show Item Level"], "showInspectItemLevel", charDB, RefreshInspect,
        { description = ns.L["Show the item level on each inspect slot overlay."] })
    y = PlaceRow(showIlvl, y)

    local showEnchants = GUI:CreateFormCheckbox(scrollChild, ns.L["Show Enchant Status"], "showInspectEnchants", charDB, RefreshInspect,
        { description = ns.L["Show the enchant name on each inspect slot, or a missing-enchant marker if the slot has no enchant."] })
    y = PlaceRow(showEnchants, y)

    local showGems = GUI:CreateFormCheckbox(scrollChild, ns.L["Show Gem Indicators"], "showInspectGems", charDB, RefreshInspect,
        { description = ns.L["Show colored gem dots indicating how many gem slots the item has and whether each is filled."] })
    y = PlaceRow(showGems, y)

    y = y - 10

    local textSizeHeader = GUI:CreateSectionHeader(scrollChild, ns.L["Text Sizes"])
    textSizeHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - textSizeHeader.gap
    ResetRows()

    local slotTextSize = GUI:CreateFormSlider(scrollChild, ns.L["Slot Text Size"], 6, 40, 1, "inspectSlotTextSize", charDB, RefreshInspectFonts, nil,
        { description = ns.L["Font size used for the text labels on each inspect slot overlay (item name, item level, enchant status)."] })
    y = PlaceRow(slotTextSize, y)

    y = y - 10

    local textColorHeader = GUI:CreateSectionHeader(scrollChild, ns.L["Text Colors"])
    textColorHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - textColorHeader.gap
    ResetRows()

    local widgetRefs = {}

    local enchantClassColor = GUI:CreateFormCheckbox(scrollChild, ns.L["Enchant Class Color"], "inspectEnchantClassColor", charDB, function()
        RefreshInspect()
        if widgetRefs.enchantColor then
            local alpha = charDB.inspectEnchantClassColor and 0.4 or 1.0
            widgetRefs.enchantColor:SetAlpha(alpha)
        end
    end, { description = ns.L["Color the enchant text using the inspected character's class color instead of the Enchant Text Color below."] })
    y = PlaceRow(enchantClassColor, y)

    local enchantColor = GUI:CreateFormColorPicker(scrollChild, ns.L["Enchant Text Color"], "inspectEnchantTextColor", charDB, RefreshInspect, nil,
        { description = ns.L["Fallback color for the enchant text when Enchant Class Color is off."] })
    widgetRefs.enchantColor = enchantColor
    enchantColor:SetAlpha(charDB.inspectEnchantClassColor and 0.4 or 1.0)
    y = PlaceRow(enchantColor, y)

    local noEnchantColor = GUI:CreateFormColorPicker(scrollChild, ns.L["No Enchant Color"], "inspectNoEnchantTextColor", charDB, RefreshInspect, nil,
        { description = ns.L["Color used for the missing-enchant marker on slots that are not enchanted."] })
    y = PlaceRow(noEnchantColor, y)

    local upgradeTrackColor = GUI:CreateFormColorPicker(scrollChild, ns.L["Upgrade Track Color"], "inspectUpgradeTrackColor", charDB, RefreshInspect, nil,
        { description = ns.L["Color used for the upgrade-track label (e.g. Explorer 2/8) next to item level."] })
    y = PlaceRow(upgradeTrackColor, y)

    y = y - 10

    local resetBtn = GUI:CreateButton(ctx.panel, ns.L["Reset"], 80, 24, function()
        charDB.inspectPanelScale = 1.0
        charDB.showInspectItemName = true
        charDB.showInspectItemLevel = true
        charDB.showInspectEnchants = true
        charDB.showInspectGems = true
        charDB.inspectSlotTextSize = 12
        charDB.inspectEnchantClassColor = true
        charDB.inspectEnchantTextColor = {0.376, 0.647, 0.980}
        charDB.inspectNoEnchantTextColor = {0.5, 0.5, 0.5}
        charDB.inspectUpgradeTrackColor = {0.98, 0.60, 0.35, 1}

        SetInspectScaleDeferred(INSPECT_CONFIG.BASE_SCALE)

        RefreshInspectFonts()
        ctx.Reopen()
    end)
    resetBtn:SetPoint("BOTTOM", ctx.panel, "BOTTOM", 0, 10)

        return y
        end,
    })

    if not flyout then return end
    inspectSettingsPanel = flyout.panel
    GetState(InspectFrame).gearBtn = flyout.trigger
    GetState(InspectFrame).settingsPanel = inspectSettingsPanel
end

ApplyInspectPaneLayout = function(force)
    local settings = GetSettings()
    if not IsFullInspectEnabled(settings) then return end
    if not InspectFrame then return end

    local scaleMultiplier = settings.inspectPanelScale or 1.0
    local targetScale = INSPECT_CONFIG.BASE_SCALE * scaleMultiplier

    if InCombatLockdown() then
        pendingInspectLayout = true
        pendingInspectMode = "extended"
        pendingInspectTab = currentInspectTab or 1
        pendingInspectScale = targetScale
        return
    end

    if inspectLayoutApplied and not force then return end

    InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_TARGET_WIDTH)
    RepositionInspectCloseButton(true)

    SetInspectScaleDeferred(targetScale)

    -- FrameXML InspectFrame_OnEvent calls ShowUIPanel(InspectFrame) before InspectFrame_UpdateTabs()
    C_Timer.After(0.1, function()
        if InCombatLockdown() then
            pendingInspectLayout = true
            return
        end
        RepositionInspectSlots()
        PositionInspectModelScene()
        SetupInspectTitleArea()
        CreateInspectSettingsButton()
        SkinAllInspectSlots()

        if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.SetExtended then
            _G.QUI_InspectFrameSkinning.SetExtended(true)
        end

        C_Timer.After(0.05, function()
            if InCombatLockdown() then
                pendingInspectLayout = true
                return
            end
            RepositionInspectSlots()
            PositionInspectModelScene()
            local unit = InspectFrame and InspectFrame.unit or "target"
            if IsCurrentInspectUnit(unit) then
                UpdateAllInspectSlotBorders(unit)
            end
        end)
    end)

    inspectLayoutApplied = true
end

local function InitializeInspectOverlays()
    if inspectPaneInitialized then return end

    local shared = GetShared()
    if not shared.CreateSlotOverlay or not shared.EQUIPMENT_SLOTS then return end

    local unit = (InspectFrame and InspectFrame.unit) or "target"
    for _, slotInfo in ipairs(shared.EQUIPMENT_SLOTS) do
        local slotFrame = _G["Inspect" .. slotInfo.name .. "Slot"]
        if slotFrame then
            inspectOverlays[slotInfo.id] = shared.CreateSlotOverlay(slotFrame, slotInfo, unit)
        end
    end

    inspectPaneInitialized = true
end

local function UpdateInspectFrame()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not InspectFrame or not InspectFrame:IsShown() then return end

    local settings = GetSettings()
    local shared = GetShared()

    if not IsCharacterModuleEnabled(settings) then
        HideLiteDisplays()
        HideDetailedOverlays()
        return
    end

    local unit = InspectFrame.unit or "target"
    local dataReady = IsCurrentInspectUnit(unit)

    if IsFullInspectEnabled(settings) then
        HideLiteDisplays()
        if dataReady and shared.UpdateAllSlotOverlays then
            shared.UpdateAllSlotOverlays(unit, inspectOverlays)
        else
            HideDetailedOverlays()
        end
    elseif settings.inspectLiteShowPerSlot or settings.inspectLiteShowOverall then
        HideDetailedOverlays()
        if dataReady then
            UpdateAllLiteDisplays(unit)
        else
            HideLiteDisplays()
        end
    else
        HideLiteDisplays()
        HideDetailedOverlays()
    end

    UpdateInspectILvlDisplay()

    if dataReady then
        UpdateAllInspectSlotBorders(unit)
    end
end

local function HookInspectFrame()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not InspectFrame then return end

    local core = QUICore or ns.Addon
    local generalDB = core and core.db and core.db.profile and core.db.profile.general
    if generalDB and generalDB.skinInspectFrame == false then return end

    local settings = GetSettings()
    if not IsCharacterModuleEnabled(settings) then return end

    if InspectFrame.UnregisterEvent then
        InspectFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    end

    local hasLiteFeature = settings.inspectLiteShowPerSlot or settings.inspectLiteShowOverall
    if settings.inspectEnabled == false and not hasLiteFeature then return end

    local shared = GetShared()

    InspectFrame:HookScript("OnShow", function()
        local currentSettings = GetSettings()
        local unit = InspectFrame.unit or "target"
        currentInspectTab = 1
        RefreshCurrentInspectGUID(unit)

        if IsFullInspectEnabled(currentSettings) then
            ApplyInspectPaneLayout()
            InitializeInspectOverlays()
        end

        if shared.ScheduleUpdate then
            C_Timer.After(0.3, shared.ScheduleUpdate)
        end
    end)

    if InspectFrame:IsShown() then
        local unit = InspectFrame.unit or "target"
        currentInspectTab = 1
        RefreshCurrentInspectGUID(unit)
        local currentSettings = GetSettings()
        if IsFullInspectEnabled(currentSettings) then
            ApplyInspectPaneLayout()
            InitializeInspectOverlays()
        end
        if shared.ScheduleUpdate then
            C_Timer.After(0.3, shared.ScheduleUpdate)
        end
    end

    InspectFrame:HookScript("OnHide", function()
        inspectLayoutApplied = false
        if not InCombatLockdown() then
            InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_DEFAULT_WIDTH)
        end
        pendingInspectMode = nil
        pendingInspectTab  = nil
        pendingInspectScale = nil
        pendingInspectLayout = false
        pendingInspectRosterRefresh = false
        currentInspectGUID = nil
        pendingInspectReadyGUID = nil
        inspectSessionGUID = nil
        inspectSessionUnit = nil
        GameTooltip:Hide()
    end)

    if InspectFrameTab1 then
        InspectFrameTab1:HookScript("OnClick", function()
            SetInspectExtendedMode(1)
        end)
    end

    if InspectFrameTab2 then
        InspectFrameTab2:HookScript("OnClick", function()
            SetInspectExtendedMode(2)
        end)
    end

    if InspectFrameTab3 then
        InspectFrameTab3:HookScript("OnClick", function()
            SetInspectNormalMode()
        end)
    end
end

local function ClearInspectGuildFrame()
    if InspectGuildFrame.guildName then InspectGuildFrame.guildName:SetText("") end
    if InspectGuildFrame.guildRealmName then InspectGuildFrame.guildRealmName:SetText("") end
    if InspectGuildFrame.guildLevel then InspectGuildFrame.guildLevel:SetText("") end
    if InspectGuildFrame.guildNumMembers then InspectGuildFrame.guildNumMembers:SetText("") end
    local points = InspectGuildFrame.Points
    if points and points.SumText then points.SumText:SetText("") end
end

local function ShouldSkipInspectGuildUpdate()
    local unit = InspectFrame and InspectFrame.unit
    if not unit or not (C_PaperDollInfo and C_PaperDollInfo.GetInspectGuildInfo) then
        return false
    end

    local ok, _, _, guildName = pcall(C_PaperDollInfo.GetInspectGuildInfo, unit)
    if not ok then
        return false
    end

    if Helpers.IsSecretValue(guildName) then
        return true -- @secret-policy: skip-update-when-unknown
    end

    return not guildName or guildName == ""
end

local function PatchInspectGuildNilGuard()
    if not InspectGuildFrame or inspectGuildNilGuard[InspectGuildFrame] then
        return
    end
    if not (InspectGuildFrame.GetScript and InspectGuildFrame.SetScript) then
        return
    end

    local originalOnShow = InspectGuildFrame:GetScript("OnShow")
    local originalOnEvent = InspectGuildFrame:GetScript("OnEvent")
    if not originalOnShow and not originalOnEvent then
        return
    end

    inspectGuildNilGuard[InspectGuildFrame] = true

    if originalOnShow then
        InspectGuildFrame:SetScript("OnShow", function(self, ...)
            if ShouldSkipInspectGuildUpdate() then
                if ButtonFrameTemplate_ShowButtonBar then
                    ButtonFrameTemplate_ShowButtonBar(InspectFrame)
                end
                ClearInspectGuildFrame()
                return
            end
            return originalOnShow(self, ...)
        end)
    end

    if originalOnEvent then
        InspectGuildFrame:SetScript("OnEvent", function(self, event, unit, ...)
            if event == "INSPECT_READY"
                and InspectFrame and InspectFrame.unit
                and not Helpers.IsSecretValue(unit)
                and IsInspectGUIDMatch(InspectFrame.unit, unit)
                and ShouldSkipInspectGuildUpdate()
            then
                ClearInspectGuildFrame()
                return
            end
            return originalOnEvent(self, event, unit, ...)
        end)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("INSPECT_READY")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then
            HookInspectFrame()
            PatchInspectGuildNilGuard()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not InspectFrame or not InspectFrame:IsShown() then return end
        if InCombatLockdown() then
            pendingInspectRosterRefresh = true
            return
        end

        RefreshInspectUnitAfterRosterUpdate()
        C_Timer.After(0, RefreshInspectUnitAfterRosterUpdate)
        C_Timer.After(0.2, RefreshInspectUnitAfterRosterUpdate)
    elseif event == "INSPECT_READY" then
        if Helpers.IsSecretValue(arg1) then
            arg1 = nil
        end
        if not arg1 then return end

        pendingInspectReadyGUID = arg1
        local unit = InspectFrame and InspectFrame.unit or "target"
        if RefreshCurrentInspectGUID(unit) then
            local shared = GetShared()
            if shared.ScheduleUpdate then
                shared.ScheduleUpdate()
            end
        end
    end
end)

local skinBase = GetSkinBase()
if skinBase and skinBase.IsAddOnFullyLoaded and skinBase.IsAddOnFullyLoaded("Blizzard_InspectUI") then
    HookInspectFrame()
    PatchInspectGuildNilGuard()
end

QUI.InspectPane = {
    UpdateInspectFrame = UpdateInspectFrame,
    GetCurrentTab = GetCurrentInspectTab,
    INSPECT_CONFIG = INSPECT_CONFIG,
}

ns.InspectPane = QUI.InspectPane
