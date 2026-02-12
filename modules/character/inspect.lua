---------------------------------------------------------------------------
-- QUI Inspect Pane Module
-- Custom inspect panel styling with equipment overlays and stats panel
-- Split from qui_character.lua for better organization
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local QUICore = ns.Addon

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------
local inspectPaneInitialized = false
local inspectOverlays = {}  -- Stores overlay frames for inspect slots
local inspectLayoutApplied = false
local currentInspectTab = 1  -- 1=Character, 2=PvP, 3=Guild
local inspectSettingsPanel = nil
local currentInspectGUID = nil  -- Tracks inspected unit's GUID for validation

-- Lite mode state
local liteOverlays = {}           -- FontStrings for per-slot ilvl
local liteOverallDisplay = nil    -- Overall ilvl frame

---------------------------------------------------------------------------
-- Import shared functions from qui_character.lua
-- These will be available after qui_character.lua loads
---------------------------------------------------------------------------
local function GetShared()
    return ns.QUI.CharacterShared or {}
end

---------------------------------------------------------------------------
-- Get settings from database (wrapper for shared function)
---------------------------------------------------------------------------
local function GetSettings()
    local shared = GetShared()
    if shared.GetSettings then
        return shared.GetSettings()
    end
    -- Fallback defaults if shared not ready
    return {
        inspectEnabled = true,
        showInspectItemName = true,
        showInspectItemLevel = true,
        showInspectEnchants = true,
        showInspectGems = true,
        inspectPanelScale = 1.0,
        inspectSlotTextSize = 12,
        inspectEnchantClassColor = true,
        inspectEnchantTextColor = {0.204, 0.827, 0.6},
        inspectNoEnchantTextColor = {0.5, 0.5, 0.5},
        inspectUpgradeTrackColor = {0.98, 0.60, 0.35, 1},
        -- Lite mode defaults
        inspectLiteMode = false,
        inspectLiteShowPerSlot = true,
        inspectLiteShowOverall = true,
        inspectLiteFontSize = 15,
        inspectLiteOverallFontSize = 11,
        inspectLiteOverallOffsetX = 0,
        inspectLiteOverallOffsetY = -8,
    }
end

---------------------------------------------------------------------------
-- Get colors (from shared module)
---------------------------------------------------------------------------
local function GetColors()
    local shared = GetShared()
    return shared.C or {
        bg = { 0.067, 0.094, 0.153, 0.95 },
        accent = { 0.204, 0.827, 0.6, 1 },
        text = { 0.953, 0.957, 0.965, 1 },
        border = { 0.2, 0.25, 0.3, 1 },
    }
end

---------------------------------------------------------------------------
-- Slots counted for average ilvl calculation
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Get slot item level using C_TooltipInfo (like LuheyUI)
-- Works reliably for inspected units
---------------------------------------------------------------------------
local function GetSlotItemLevel(unit, slotId)
    if not unit or not slotId then return nil end

    -- Use C_TooltipInfo for reliable ilvl extraction (works for inspect)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local info = C_TooltipInfo.GetInventoryItem(unit, slotId)
        if info and info.lines then
            for _, line in ipairs(info.lines) do
                local text = line.leftText
                if text then
                    -- Strip color codes and textures
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    text = text:gsub("|T.-|t", "")  -- Strip texture escapes
                    -- Match "Item Level X" pattern using the localized ITEM_LEVEL global
                    local pattern = ITEM_LEVEL:gsub("%%d", "(%%d+)")
                    local ilvl = text:match(pattern)
                    if ilvl then
                        return tonumber(ilvl)
                    end
                end
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Get slot item quality
---------------------------------------------------------------------------
local function GetSlotItemQuality(unit, slotId)
    if not unit or not slotId then return nil end

    local itemLink = GetInventoryItemLink(unit, slotId)
    if not itemLink then return nil end

    local ok, quality = pcall(C_Item.GetItemQualityByID, itemLink)
    if ok then return quality end

    return nil
end

---------------------------------------------------------------------------
-- Check if mainhand is a 2H weapon (like LuheyUI)
---------------------------------------------------------------------------
local function IsMainHand2H(unit)
    local itemLink = GetInventoryItemLink(unit, INVSLOT_MAINHAND)
    if not itemLink then return false end

    local ok, _, _, _, _, _, _, _, _, equipSlot = pcall(C_Item.GetItemInfo, itemLink)
    if not ok then return false end
    return equipSlot == "INVTYPE_2HWEAPON"
end

---------------------------------------------------------------------------
-- Calculate average item level (like LuheyUI)
-- Handles 2H weapons by counting mainhand twice
---------------------------------------------------------------------------
local function CalculateAverageILvl(unit)
    local totalIlvl = 0
    local slotCount = 0
    local is2H = IsMainHand2H(unit)

    for slotId, counted in pairs(COUNTED_SLOTS) do
        if counted then
            if slotId == INVSLOT_OFFHAND and is2H then
                -- 2H weapon counts twice - add mainhand ilvl again
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

---------------------------------------------------------------------------
-- Calculate average equipped quality (like LuheyUI)
-- Used for coloring the overall ilvl display
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Get overall ilvl color based on average equipped quality (like LuheyUI)
---------------------------------------------------------------------------
local function GetOverallILvlColor(unit)
    local avgQuality = CalculateAverageEquippedQuality(unit)
    avgQuality = math.max(1, math.min(avgQuality, 7))
    local r, g, b = C_Item.GetItemQualityColor(avgQuality)
    return r, g, b
end

---------------------------------------------------------------------------
-- Inspect Frame Configuration Constants
---------------------------------------------------------------------------
local INSPECT_CONFIG = {
    FRAME_TARGET_WIDTH = 500,      -- Narrower than CharacterFrame (no stats panel)
    FRAME_DEFAULT_WIDTH = 338,     -- Default InspectFrame width (Guild tab)
    CLOSE_BUTTON_EXTENDED_X = -2,  -- Close button X offset
    CLOSE_BUTTON_NORMAL_X = -2,    -- Close button X offset when normal
    CLOSE_BUTTON_Y = -2,           -- Close button Y offset
    -- Weapon slot positioning (centered for 500px frame)
    MAINHAND_X_OFFSET = -25,       -- Main hand X offset from center (+10px right)
    MAINHAND_Y_OFFSET = -42,       -- Main hand Y offset from bottom
    OFFHAND_SPACING = 30,          -- Spacing between main and off hand
    -- Scale settings
    BASE_SCALE = 1.30,             -- Base scale (same as character panel)
}

-- All inspect slot names (used for skinning and border updates)
local INSPECT_SLOT_NAMES = {
    "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot",
    "InspectBackSlot", "InspectChestSlot", "InspectShirtSlot",
    "InspectTabardSlot", "InspectWristSlot", "InspectHandsSlot",
    "InspectWaistSlot", "InspectLegsSlot", "InspectFeetSlot",
    "InspectFinger0Slot", "InspectFinger1Slot",
    "InspectTrinket0Slot", "InspectTrinket1Slot",
    "InspectMainHandSlot", "InspectSecondaryHandSlot",
}

---------------------------------------------------------------------------
-- Track current inspect tab
---------------------------------------------------------------------------
local function GetCurrentInspectTab()
    return currentInspectTab
end

---------------------------------------------------------------------------
-- Reposition inspect frame tabs for wider frame
---------------------------------------------------------------------------
local function RepositionInspectTabs()
    local tabs = { InspectFrameTab1, InspectFrameTab2, InspectFrameTab3 }
    local firstTab = tabs[1]

    if firstTab then
        firstTab:ClearAllPoints()
        firstTab:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", 15, -75)
    end

    -- Reposition Talents button just below last slot (Trinket1)
    local talentsBtn = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame.InspectTalents
    if talentsBtn and InspectTrinket1Slot then
        talentsBtn:ClearAllPoints()
        talentsBtn:SetPoint("TOP", InspectTrinket1Slot, "BOTTOM", -12, -31)
    end
end

---------------------------------------------------------------------------
-- Reset inspect tabs to default position (for Guild tab)
---------------------------------------------------------------------------
local function ResetInspectTabsPosition()
    local firstTab = InspectFrameTab1
    if firstTab then
        firstTab:ClearAllPoints()
        firstTab:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", 15, -30)
    end
end

---------------------------------------------------------------------------
-- Reposition INSPECT equipment slots into portrait layout
---------------------------------------------------------------------------
local function RepositionInspectSlots()
    if not InspectFrame then return end

    local vpad = 14  -- Vertical padding between slots
    local SLOT_SCALE = 0.90
    local TOP_OFFSET = -75
    local LEFT_X = 20
    local RIGHT_X = 493  -- Push right column further to edge (+2px more)

    -- All inspect slots to scale
    local allSlots = {
        InspectHeadSlot, InspectNeckSlot, InspectShoulderSlot,
        InspectBackSlot, InspectChestSlot, InspectShirtSlot,
        InspectTabardSlot, InspectWristSlot,
        InspectHandsSlot, InspectWaistSlot, InspectLegsSlot,
        InspectFeetSlot, InspectFinger0Slot, InspectFinger1Slot,
        InspectTrinket0Slot, InspectTrinket1Slot,
        InspectMainHandSlot, InspectSecondaryHandSlot,
    }

    -- Apply scale to all slots
    for _, slot in ipairs(allSlots) do
        if slot then slot:SetScale(SLOT_SCALE) end
    end

    -- LEFT COLUMN
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

    -- RIGHT COLUMN
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

    -- LEFT COLUMN BOTTOM: Wrist aligned horizontally with Trinket1
    if InspectWristSlot and InspectTrinket1Slot and InspectHeadSlot then
        InspectWristSlot:ClearAllPoints()
        InspectWristSlot:SetPoint("TOP", InspectTrinket1Slot, "TOP", 0, 0)
        InspectWristSlot:SetPoint("LEFT", InspectHeadSlot, "LEFT", 0, 0)
    end

    -- BOTTOM: Weapons centered
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

---------------------------------------------------------------------------
-- Inspect Slot Border Skinning (match character pane style)
---------------------------------------------------------------------------

-- Block Blizzard's IconBorder from showing
local function BlockInspectIconBorder(iconBorder)
    if not iconBorder or iconBorder._quiBlocked then return end
    iconBorder._quiBlocked = true
    iconBorder:SetAlpha(0)
    if iconBorder.SetTexture then iconBorder:SetTexture(nil) end
    if iconBorder.SetAtlas then
        hooksecurefunc(iconBorder, "SetAtlas", function(self)
            if self.SetTexture then self:SetTexture(nil) end
            if self.SetAlpha then self:SetAlpha(0) end
        end)
    end
end

-- Skin a single inspect equipment slot
local function SkinInspectEquipmentSlot(slot)
    if not slot or slot._quiSkinned then return end
    slot._quiSkinned = true

    -- Hide NormalTexture (decorative frame)
    local normalTex = slot:GetNormalTexture()
    if normalTex then normalTex:SetAlpha(0) end

    -- Hide BottomRightSlotTexture if exists
    if slot.BottomRightSlotTexture then
        slot.BottomRightSlotTexture:Hide()
    end

    -- Hide ALL non-icon regions (decorative textures)
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            local isIcon = region == slot.icon or region == slot.Icon
            if not isIcon then
                region:SetAlpha(0)
            end
        end
    end

    -- Block Blizzard's IconBorder
    if slot.IconBorder then
        BlockInspectIconBorder(slot.IconBorder)
    end

    -- Apply base crop to icon texture
    local iconTex = slot.icon or slot.Icon
    if iconTex and iconTex.SetTexCoord then
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Create custom border frame
    if not slot._quiBorderFrame then
        slot._quiBorderFrame = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        slot._quiBorderFrame:SetFrameLevel(slot:GetFrameLevel() + 10)
        slot._quiBorderFrame:SetAllPoints(slot)
        local core = GetCore()
        local px = (core and core.GetPixelSize and core:GetPixelSize(slot._quiBorderFrame)) or 1
        slot._quiBorderFrame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = px,
        })
    end
end

-- Update border color based on inspected item quality
local function UpdateInspectSlotBorder(slot, unit)
    if not slot or not slot._quiBorderFrame then return end

    local slotID = slot:GetID()
    unit = unit or "target"

    -- Get item quality for inspected target (pcall for edge cases where item data isn't cached)
    local itemLink = GetInventoryItemLink(unit, slotID)
    local quality = nil
    if itemLink then
        local ok, q = pcall(C_Item.GetItemQualityByID, itemLink)
        if ok then quality = q end
    end

    if quality and quality >= 1 then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        slot._quiBorderFrame:SetBackdropBorderColor(r, g, b, 1)
        slot._quiBorderFrame:Show()
    else
        slot._quiBorderFrame:Hide()
    end
end

-- Skin all inspect equipment slots
local function SkinAllInspectSlots()
    for _, slotName in ipairs(INSPECT_SLOT_NAMES) do
        local slot = _G[slotName]
        if slot then
            SkinInspectEquipmentSlot(slot)
        end
    end
end

-- Update all inspect slot borders
local function UpdateAllInspectSlotBorders(unit)
    for _, slotName in ipairs(INSPECT_SLOT_NAMES) do
        local slot = _G[slotName]
        if slot then
            UpdateInspectSlotBorder(slot, unit)
        end
    end
end

---------------------------------------------------------------------------
-- Position InspectModelFrame
---------------------------------------------------------------------------
local function PositionInspectModelScene()
    if not InspectModelFrame then return end

    -- Center model between slot columns
    -- For 500px frame with slots at x=20 and x=493
    InspectModelFrame:ClearAllPoints()
    InspectModelFrame:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 55, -85)
    InspectModelFrame:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT", -55, 65)
    InspectModelFrame:SetFrameLevel(2)

    -- Hide control frame like character pane does
    if InspectModelFrame.ControlFrame then
        InspectModelFrame.ControlFrame:Hide()
    end

    -- Reset model to zoomed out state (uses ModelFrameMixin)
    -- minZoom = 0 (fully zoomed out), resets position to 0,0,0
    if InspectModelFrame.ResetModel then
        InspectModelFrame:ResetModel()
    end

    InspectModelFrame:Show()
end

---------------------------------------------------------------------------
-- Calculate average item level for inspect target
-- Wrapper for the new CalculateAverageILvl function
---------------------------------------------------------------------------
local function CalculateInspectAverageILvl(unit)
    return CalculateAverageILvl(unit)
end

---------------------------------------------------------------------------
-- Lite Mode Functions
---------------------------------------------------------------------------

-- Slot ID mapping for lite mode (slot name to slot ID)
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

-- Create centered FontString on slot for lite mode
local function CreateLiteSlotText(slotFrame)
    if not slotFrame then return nil end

    local shared = GetShared()
    local font = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
    local settings = GetSettings()
    local fontSize = settings.inspectLiteFontSize or 15

    local text = slotFrame:CreateFontString(nil, "OVERLAY")
    text:SetFont(font, fontSize, "OUTLINE")
    text:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:Hide()

    return text
end

-- Create overall iLvL display frame (positioned below wrist slot with offsets)
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

    -- Label text "iLvL:"
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont(font, fontSize, "OUTLINE")
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    label:SetText("iLvL:")
    label:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Value text (colored by quality)
    local value = frame:CreateFontString(nil, "OVERLAY")
    value:SetFont(font, fontSize, "OUTLINE")
    value:SetPoint("LEFT", label, "RIGHT", 4, 0)

    frame.label = label
    frame.value = value
    frame:Hide()

    liteOverallDisplay = frame
    return frame
end

-- Update single slot's lite text
local function UpdateLiteSlotText(slotName, unit, settings, cachedFont)
    local slotFrame = _G[slotName]
    if not slotFrame then return end

    local slotId = LITE_SLOT_IDS[slotName]
    if not slotId then return end

    -- Create overlay if needed
    if not liteOverlays[slotName] then
        liteOverlays[slotName] = CreateLiteSlotText(slotFrame)
    end

    local text = liteOverlays[slotName]
    if not text then return end

    -- Use cached settings/font if provided, otherwise fetch
    settings = settings or GetSettings()
    local font = cachedFont or (function()
        local shared = GetShared()
        return shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
    end)()

    -- Update font size in case it changed
    local fontSize = settings.inspectLiteFontSize or 15
    text:SetFont(font, fontSize, "OUTLINE")

    -- Check if we should show per-slot ilvl
    if not settings.inspectLiteShowPerSlot then
        text:Hide()
        return
    end

    -- Get item link
    local itemLink = GetInventoryItemLink(unit, slotId)
    if not itemLink then
        text:Hide()
        return
    end

    -- Get ilvl using new C_TooltipInfo-based function
    local ilvl = GetSlotItemLevel(unit, slotId)
    if not ilvl or ilvl <= 0 then
        text:Hide()
        return
    end

    -- Get item quality for coloring
    local quality = GetSlotItemQuality(unit, slotId)

    -- Set text
    text:SetText(tostring(math.floor(ilvl)))

    -- Color by quality
    if quality and quality >= 1 then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        text:SetTextColor(r, g, b, 1)
    else
        text:SetTextColor(1, 1, 1, 1)
    end

    text:Show()
end

-- Update overall iLvL display
local function UpdateLiteOverallDisplay(unit, settings, cachedFont)
    local frame = liteOverallDisplay or CreateLiteOverallDisplay()
    if not frame then return end

    -- Use cached settings/font if provided, otherwise fetch
    settings = settings or GetSettings()
    local font = cachedFont or (function()
        local shared = GetShared()
        return shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
    end)()

    -- Update font sizes in case they changed
    local fontSize = settings.inspectLiteOverallFontSize or 11
    if frame.label then
        frame.label:SetFont(font, fontSize, "OUTLINE")
    end
    if frame.value then
        frame.value:SetFont(font, fontSize, "OUTLINE")
    end

    -- Update position in case offsets changed
    local offsetX = settings.inspectLiteOverallOffsetX or 0
    local offsetY = settings.inspectLiteOverallOffsetY or -8
    frame:ClearAllPoints()
    frame:SetPoint("TOP", InspectWristSlot, "BOTTOM", offsetX, offsetY)

    -- Check if we should show overall ilvl
    if not settings.inspectLiteShowOverall then
        frame:Hide()
        return
    end

    -- Calculate average ilvl
    local avgIlvl = CalculateInspectAverageILvl(unit)
    if avgIlvl <= 0 then
        frame:Hide()
        return
    end

    -- Get color based on average equipped quality (like LuheyUI)
    local r, g, b = GetOverallILvlColor(unit)

    -- Set value text
    frame.value:SetText(string.format("%.1f", avgIlvl))
    frame.value:SetTextColor(r, g, b, 1)

    frame:Show()
end

-- Master update for all lite displays
-- Per-slot and overall displays are independent - each checks its own toggle
local function UpdateAllLiteDisplays(unit)
    local settings = GetSettings()

    -- Cache font lookup once for all updates
    local shared = GetShared()
    local cachedFont = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"

    -- Update per-slot displays (controlled by inspectLiteShowPerSlot, checked inside UpdateLiteSlotText)
    if settings.inspectLiteShowPerSlot then
        for _, slotName in ipairs(INSPECT_SLOT_NAMES) do
            UpdateLiteSlotText(slotName, unit, settings, cachedFont)
        end
    else
        -- Hide per-slot overlays if disabled
        for slotName, text in pairs(liteOverlays) do
            if text then text:Hide() end
        end
    end

    -- Update overall display (controlled by inspectLiteShowOverall, checked inside UpdateLiteOverallDisplay)
    UpdateLiteOverallDisplay(unit, settings, cachedFont)
end

-- Hide all lite displays
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

-- Show detailed overlays (restore visibility)
local function ShowDetailedOverlays()
    for _, overlay in pairs(inspectOverlays) do
        if overlay then
            overlay:Show()
        end
    end
end

-- Hide detailed overlays
local function HideDetailedOverlays()
    for _, overlay in pairs(inspectOverlays) do
        if overlay then
            overlay:Hide()
        end
    end
end

-- Mode toggle handler - switches between lite and detailed mode
local function RefreshInspectDisplayMode()
    local settings = GetSettings()

    if settings.inspectEnabled then
        -- Full overlay mode: always use detailed overlays
        HideLiteDisplays()
        ShowDetailedOverlays()
    elseif settings.inspectLiteShowPerSlot or settings.inspectLiteShowOverall then
        -- Lite mode (only when full overlays disabled): show enabled lite displays
        HideDetailedOverlays()
        UpdateAllLiteDisplays("target")
    else
        -- Both disabled: hide everything
        HideLiteDisplays()
        HideDetailedOverlays()
    end
end

---------------------------------------------------------------------------
-- Setup inspect title area (header display)
-- Creates: [Name] [iLvl] [Level Spec Class]
---------------------------------------------------------------------------
local function SetupInspectTitleArea()
    if not InspectFrame then return end

    local shared = GetShared()
    local font = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"

    -- Hide Blizzard's title text
    if InspectFrame.TitleContainer and InspectFrame.TitleContainer.TitleText then
        InspectFrame.TitleContainer.TitleText:Hide()
    end

    -- Hide Blizzard's level/class text (shows "Level XX Spec Class" below model)
    if InspectLevelText then
        InspectLevelText:Hide()
    end

    -- Create top-left display: Name (class-colored)
    if not InspectFrame._quiILvlDisplay then
        local displayFrame = CreateFrame("Frame", nil, InspectFrame)
        displayFrame:SetSize(400, 30)
        displayFrame:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 19, -10)
        displayFrame:SetFrameLevel(InspectFrame:GetFrameLevel() + 10)

        -- Line 1: Target name
        local nameText = displayFrame:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(font, 12, "")
        nameText:SetPoint("TOPLEFT", displayFrame, "TOPLEFT", 0, 0)
        nameText:SetJustifyH("LEFT")

        -- Line 2: Level + Spec (right-aligned, spread evenly)
        local specText = InspectFrame:CreateFontString(nil, "OVERLAY")
        specText:SetFont(font, 12, "")
        specText:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", -70, -10)
        specText:SetJustifyH("RIGHT")

        displayFrame.text = nameText
        displayFrame.specText = specText
        InspectFrame._quiILvlDisplay = displayFrame
    end

    -- Create center ilvl display (title bar)
    if not InspectFrame._quiCenterILvl then
        local centerFrame = CreateFrame("Frame", nil, InspectFrame)
        centerFrame:SetSize(200, 20)
        centerFrame:SetPoint("TOP", InspectFrame, "TOP", 0, -10)
        centerFrame:SetFrameLevel(InspectFrame:GetFrameLevel() + 10)

        local centerText = centerFrame:CreateFontString(nil, "OVERLAY")
        centerText:SetFont(font, 21, "OUTLINE")
        centerText:SetPoint("CENTER")
        centerText:SetJustifyH("CENTER")

        centerFrame.text = centerText
        InspectFrame._quiCenterILvl = centerFrame
    end
end

---------------------------------------------------------------------------
-- Update inspect iLvl display with target's info
---------------------------------------------------------------------------
local function UpdateInspectILvlDisplay()
    if not InspectFrame or not InspectFrame._quiILvlDisplay then return end

    local settings = GetSettings()
    if settings.inspectEnabled == false then return end

    local displayFrame = InspectFrame._quiILvlDisplay
    if not displayFrame.text then return end

    local shared = GetShared()
    local unit = InspectFrame.unit or "target"

    -- Validate that unit matches our stored GUID (handles target changes mid-inspect)
    if currentInspectGUID and UnitGUID(unit) ~= currentInspectGUID then
        return  -- Unit changed, skip stale update
    end

    -- Get target info
    local name = UnitName(unit) or "Unknown"
    local level = UnitLevel(unit) or 0

    -- Get class info
    local className = ""
    local _, classToken = UnitClass(unit)
    if classToken then
        local classInfo = C_CreatureInfo.GetClassInfo(select(3, UnitClass(unit)))
        className = classInfo and classInfo.className or classToken
    end

    -- Get spec info (requires inspect data)
    local specName = ""
    local specID = GetInspectSpecialization(unit)
    if specID and specID > 0 then
        local _, specNameLocal = GetSpecializationInfoByID(specID)
        specName = specNameLocal or ""
    end

    -- Get class color
    local classColor = RAID_CLASS_COLORS[classToken]
    local r, g, b = 1, 1, 1
    if classColor then
        r, g, b = classColor.r, classColor.g, classColor.b
    end

    -- Line 1: Target name (class colored)
    displayFrame.text:SetText(name)
    displayFrame.text:SetTextColor(r, g, b, 1)

    -- Line 2: Level + Spec + Class (class colored)
    if displayFrame.specText then
        local abbreviatedClass = shared.AbbreviateClassName and shared.AbbreviateClassName(className) or className
        local specLine = string.format("%d %s %s", level, specName, abbreviatedClass)
        displayFrame.specText:SetText(specLine)
        displayFrame.specText:SetTextColor(r, g, b, 1)
    end

    -- Update center ilvl display
    local centerFrame = InspectFrame._quiCenterILvl
    if centerFrame and centerFrame.text then
        local equipped = CalculateInspectAverageILvl(unit)

        if equipped > 0 and shared.GetILvlColor then
            local eR, eG, eB = shared.GetILvlColor(equipped)
            local equippedHex = string.format("%02x%02x%02x", math.floor(eR*255), math.floor(eG*255), math.floor(eB*255))
            local equippedStr = string.format("%.1f", equipped)
            centerFrame.text:SetText(string.format("|cff%s%s|r", equippedHex, equippedStr))
        else
            centerFrame.text:SetText("")
        end
    end
end


---------------------------------------------------------------------------
-- Reposition inspect close button for extended/normal mode
---------------------------------------------------------------------------
local function RepositionInspectCloseButton(extended)
    local closeButton = InspectFrame and (InspectFrame.CloseButton or InspectFrameCloseButton)
    if closeButton then
        closeButton:ClearAllPoints()
        local xOffset = extended and INSPECT_CONFIG.CLOSE_BUTTON_EXTENDED_X or INSPECT_CONFIG.CLOSE_BUTTON_NORMAL_X
        closeButton:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", xOffset, INSPECT_CONFIG.CLOSE_BUTTON_Y)
    end
end

---------------------------------------------------------------------------
-- Set inspect frame to extended mode (Character/PvP tabs)
---------------------------------------------------------------------------
local function SetInspectExtendedMode(tabNum)
    if not InspectFrame then return end
    currentInspectTab = tabNum
    InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_TARGET_WIDTH)
    RepositionInspectTabs()
    RepositionInspectCloseButton(true)
    if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.SetExtended then
        _G.QUI_InspectFrameSkinning.SetExtended(true)
    end
    -- Show iLvl display on Character/PvP tabs
    if InspectFrame._quiCenterILvl then
        InspectFrame._quiCenterILvl:Show()
    end
end

---------------------------------------------------------------------------
-- Set inspect frame to normal mode (Guild tab)
---------------------------------------------------------------------------
local function SetInspectNormalMode()
    if not InspectFrame then return end
    currentInspectTab = 3
    InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_DEFAULT_WIDTH)
    ResetInspectTabsPosition()
    RepositionInspectCloseButton(false)
    if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.SetExtended then
        _G.QUI_InspectFrameSkinning.SetExtended(false)
    end
    -- Hide iLvl display on Guild tab (not relevant)
    if InspectFrame._quiCenterILvl then
        InspectFrame._quiCenterILvl:Hide()
    end
end

---------------------------------------------------------------------------
-- Inspect Settings Button and Panel
-- Mirrors character panel settings structure
---------------------------------------------------------------------------
local function CreateInspectSettingsButton()
    if not InspectFrame then return end
    if InspectFrame._quiGearBtn then return end

    local GUI = _G.QUI and _G.QUI.GUI
    if not GUI then return end

    local core = GetCore()
    if not (core and core.db and core.db.profile and core.db.profile.character) then
        C_Timer.After(0.5, CreateInspectSettingsButton)
        return
    end
    local charDB = core.db.profile.character

    -- Initialize inspect color defaults if not set (ensures color pickers show correct values)
    if charDB.inspectEnchantTextColor == nil then
        charDB.inspectEnchantTextColor = {0.204, 0.827, 0.6}
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
    -- Initialize lite mode defaults
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

    local C = GetColors()
    local shared = GetShared()

    -- Create gear icon button
    local gearBtn = CreateFrame("Button", "QUI_InspectSettingsBtn", InspectFrame, "BackdropTemplate")
    gearBtn:SetSize(70, 20)
    gearBtn:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", -5, -28)
    local gearPx = (core and core.GetPixelSize and core:GetPixelSize(gearBtn)) or 1
    gearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = gearPx,
    })
    gearBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    gearBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    gearBtn:SetFrameStrata("HIGH")
    gearBtn:SetFrameLevel(100)

    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetSize(14, 14)
    gearIcon:SetPoint("LEFT", gearBtn, "LEFT", 5, 0)
    gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")

    local gearLabel = gearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gearLabel:SetPoint("LEFT", gearIcon, "RIGHT", 4, 0)
    gearLabel:SetText("Settings")
    gearLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    gearBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    gearBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)

    InspectFrame._quiGearBtn = gearBtn

    -- Settings panel (matches character panel size: 450x600)
    inspectSettingsPanel = CreateFrame("Frame", "QUI_InspectSettingsPanel", InspectFrame, "BackdropTemplate")
    inspectSettingsPanel:SetSize(450, 600)
    inspectSettingsPanel:SetPoint("TOPLEFT", InspectFrame, "TOPRIGHT", 5, 0)
    local settingsPx = (core and core.GetPixelSize and core:GetPixelSize(inspectSettingsPanel)) or 1
    inspectSettingsPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = settingsPx,
    })
    inspectSettingsPanel:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.98)
    inspectSettingsPanel:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    inspectSettingsPanel:SetFrameStrata("DIALOG")
    inspectSettingsPanel:SetFrameLevel(200)
    inspectSettingsPanel:EnableMouse(true)
    inspectSettingsPanel:Hide()
    InspectFrame._quiSettingsPanel = inspectSettingsPanel

    -- Title
    local title = inspectSettingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", inspectSettingsPanel, "TOP", 0, -8)
    title:SetText("QUI Inspect Panel")
    title:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, inspectSettingsPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function() inspectSettingsPanel:Hide() end)

    -- Scroll frame for settings
    local scrollFrame = CreateFrame("ScrollFrame", nil, inspectSettingsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", inspectSettingsPanel, "TOPLEFT", 5, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", inspectSettingsPanel, "BOTTOMRIGHT", -26, 40)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(419)  -- settingsPanel(450) - left(5) - right(26)
    scrollChild:SetHeight(1)   -- Will be updated after adding widgets
    scrollFrame:SetScrollChild(scrollChild)

    -- Style the scroll bar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 16)
    end

    -- Layout constants
    local PAD = 8
    local FORM_ROW = 28
    local y = -5

    -- Refresh callback
    local function RefreshInspect()
        if InspectFrame and InspectFrame:IsShown() and shared.ScheduleUpdate then
            shared.ScheduleUpdate()
        end
    end

    -- Refresh inspect overlay fonts (for live text size updates)
    local function RefreshInspectFonts()
        local settings = GetSettings()
        local slotTextSize = settings.inspectSlotTextSize or 12
        local slotFont = shared.GetGlobalFont and shared.GetGlobalFont() or "Fonts\\FRIZQT__.TTF"
        local FONT_FLAGS = "OUTLINE"

        for _, overlay in pairs(inspectOverlays) do
            if overlay then
                if overlay.itemName and overlay.itemName.SetFont then
                    overlay.itemName:SetFont(slotFont, slotTextSize, FONT_FLAGS)
                end
                if overlay.itemLevel and overlay.itemLevel.SetFont then
                    overlay.itemLevel:SetFont(slotFont, slotTextSize, FONT_FLAGS)
                end
                if overlay.enchant and overlay.enchant.SetFont then
                    overlay.enchant:SetFont(slotFont, slotTextSize, FONT_FLAGS)
                end
            end
        end

        RefreshInspect()
    end

    ---------------------------------------------------------------------------
    -- APPEARANCE Section
    ---------------------------------------------------------------------------
    local appearHeader = GUI:CreateSectionHeader(scrollChild, "Appearance")
    appearHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - appearHeader.gap

    -- Scale slider (multiplier on base 1.30 scale, range 0.75-1.5)
    local scaleSlider = GUI:CreateFormSlider(scrollChild, "Panel Scale", 0.75, 1.5, 0.05, "inspectPanelScale", charDB, function()
        local multiplier = charDB.inspectPanelScale or 1.0
        if InspectFrame then
            InspectFrame:SetScale(INSPECT_CONFIG.BASE_SCALE * multiplier)
        end
    end, { deferOnDrag = true })
    scaleSlider:SetPoint("TOPLEFT", PAD, y)
    scaleSlider:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Background color (uses shared skinning background color)
    local generalDB = core and core.db and core.db.profile and core.db.profile.general
    local bgColorPicker = nil
    if generalDB then
        bgColorPicker = GUI:CreateFormColorPicker(scrollChild, "Background Color", "skinBgColor", generalDB, function()
            -- Refresh inspect skinning module
            if _G.QUI_RefreshInspectColors then
                _G.QUI_RefreshInspectColors()
            end
            if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.Refresh then
                _G.QUI_InspectFrameSkinning.Refresh()
            end
        end)
        bgColorPicker:SetPoint("TOPLEFT", PAD, y)
        bgColorPicker:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Refresh color picker when panel shows
        inspectSettingsPanel:HookScript("OnShow", function()
            if bgColorPicker and bgColorPicker.swatch and generalDB and generalDB.skinBgColor then
                local col = generalDB.skinBgColor
                bgColorPicker.swatch:SetBackdropColor(col[1], col[2], col[3], col[4] or 1)
            end
        end)
    end

    y = y - 10

    ---------------------------------------------------------------------------
    -- SLOT OVERLAYS Section
    ---------------------------------------------------------------------------
    local overlayHeader = GUI:CreateSectionHeader(scrollChild, "Slot Overlays")
    overlayHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - overlayHeader.gap

    local showItemName = GUI:CreateFormCheckbox(scrollChild, "Show Equipment Name", "showInspectItemName", charDB, RefreshInspect)
    showItemName:SetPoint("TOPLEFT", PAD, y)
    showItemName:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local showIlvl = GUI:CreateFormCheckbox(scrollChild, "Show Item Level", "showInspectItemLevel", charDB, RefreshInspect)
    showIlvl:SetPoint("TOPLEFT", PAD, y)
    showIlvl:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local showEnchants = GUI:CreateFormCheckbox(scrollChild, "Show Enchant Status", "showInspectEnchants", charDB, RefreshInspect)
    showEnchants:SetPoint("TOPLEFT", PAD, y)
    showEnchants:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local showGems = GUI:CreateFormCheckbox(scrollChild, "Show Gem Indicators", "showInspectGems", charDB, RefreshInspect)
    showGems:SetPoint("TOPLEFT", PAD, y)
    showGems:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10

    ---------------------------------------------------------------------------
    -- TEXT SIZES Section
    ---------------------------------------------------------------------------
    local textSizeHeader = GUI:CreateSectionHeader(scrollChild, "Text Sizes")
    textSizeHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - textSizeHeader.gap

    local slotTextSize = GUI:CreateFormSlider(scrollChild, "Slot Text Size", 6, 40, 1, "inspectSlotTextSize", charDB, RefreshInspectFonts)
    slotTextSize:SetPoint("TOPLEFT", PAD, y)
    slotTextSize:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10

    ---------------------------------------------------------------------------
    -- TEXT COLORS Section
    ---------------------------------------------------------------------------
    local textColorHeader = GUI:CreateSectionHeader(scrollChild, "Text Colors")
    textColorHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - textColorHeader.gap

    -- Widget references for conditional disable
    local widgetRefs = {}

    -- Enchant Class Color toggle
    local enchantClassColor = GUI:CreateFormCheckbox(scrollChild, "Enchant Class Color", "inspectEnchantClassColor", charDB, function()
        RefreshInspect()
        if widgetRefs.enchantColor then
            local alpha = charDB.inspectEnchantClassColor and 0.4 or 1.0
            widgetRefs.enchantColor:SetAlpha(alpha)
        end
    end)
    enchantClassColor:SetPoint("TOPLEFT", PAD, y)
    enchantClassColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local enchantColor = GUI:CreateFormColorPicker(scrollChild, "Enchant Text Color", "inspectEnchantTextColor", charDB, RefreshInspect)
    enchantColor:SetPoint("TOPLEFT", PAD, y)
    enchantColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    widgetRefs.enchantColor = enchantColor
    enchantColor:SetAlpha(charDB.inspectEnchantClassColor and 0.4 or 1.0)
    y = y - FORM_ROW

    local noEnchantColor = GUI:CreateFormColorPicker(scrollChild, "No Enchant Color", "inspectNoEnchantTextColor", charDB, RefreshInspect)
    noEnchantColor:SetPoint("TOPLEFT", PAD, y)
    noEnchantColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local upgradeTrackColor = GUI:CreateFormColorPicker(scrollChild, "Upgrade Track Color", "inspectUpgradeTrackColor", charDB, RefreshInspect)
    upgradeTrackColor:SetPoint("TOPLEFT", PAD, y)
    upgradeTrackColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(y) + 20)

    ---------------------------------------------------------------------------
    -- Reset Button (at bottom of panel, outside scroll)
    ---------------------------------------------------------------------------
    local resetBtn = GUI:CreateButton(inspectSettingsPanel, "Reset", 80, 24, function()
        -- Reset all inspect settings to defaults
        charDB.inspectPanelScale = 1.0
        charDB.showInspectItemName = true
        charDB.showInspectItemLevel = true
        charDB.showInspectEnchants = true
        charDB.showInspectGems = true
        charDB.inspectSlotTextSize = 12
        charDB.inspectEnchantClassColor = true
        charDB.inspectEnchantTextColor = {0.204, 0.827, 0.6}
        charDB.inspectNoEnchantTextColor = {0.5, 0.5, 0.5}
        charDB.inspectUpgradeTrackColor = {0.98, 0.60, 0.35, 1}

        -- Apply scale (base 1.30 * multiplier 1.0)
        if InspectFrame then
            InspectFrame:SetScale(INSPECT_CONFIG.BASE_SCALE)
        end

        -- Refresh and reload the settings panel
        RefreshInspectFonts()
        inspectSettingsPanel:Hide()
        C_Timer.After(0.1, function()
            inspectSettingsPanel:Show()
        end)
    end)
    resetBtn:SetPoint("BOTTOM", inspectSettingsPanel, "BOTTOM", 0, 10)

    -- Toggle panel on gear click
    gearBtn:SetScript("OnClick", function()
        inspectSettingsPanel:SetShown(not inspectSettingsPanel:IsShown())
    end)
end

---------------------------------------------------------------------------
-- Master function: Apply inspect portrait layout
---------------------------------------------------------------------------
local function ApplyInspectPaneLayout()
    local settings = GetSettings()
    if settings.inspectEnabled == false then return end
    if not InspectFrame then return end

    if inspectLayoutApplied then return end

    InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_TARGET_WIDTH)
    RepositionInspectCloseButton(true)

    -- Apply panel scale from settings (base scale 1.30, slider is multiplier)
    local scaleMultiplier = settings.inspectPanelScale or 1.0
    InspectFrame:SetScale(INSPECT_CONFIG.BASE_SCALE * scaleMultiplier)

    C_Timer.After(0.1, function()
        RepositionInspectSlots()
        PositionInspectModelScene()
        SetupInspectTitleArea()
        CreateInspectSettingsButton()
        SkinAllInspectSlots()

        if _G.QUI_InspectFrameSkinning and _G.QUI_InspectFrameSkinning.SetExtended then
            _G.QUI_InspectFrameSkinning.SetExtended(true)
        end

        -- Second pass to ensure positions stick after Blizzard code
        C_Timer.After(0.05, function()
            RepositionInspectSlots()
            PositionInspectModelScene()
            UpdateAllInspectSlotBorders("target")
        end)
    end)

    inspectLayoutApplied = true
end

---------------------------------------------------------------------------
-- Initialize slot overlays for inspect frame
---------------------------------------------------------------------------
local function InitializeInspectOverlays()
    if inspectPaneInitialized then return end

    local shared = GetShared()
    if not shared.CreateSlotOverlay or not shared.EQUIPMENT_SLOTS then return end

    for _, slotInfo in ipairs(shared.EQUIPMENT_SLOTS) do
        local slotFrame = _G["Inspect" .. slotInfo.name .. "Slot"]
        if slotFrame then
            inspectOverlays[slotInfo.id] = shared.CreateSlotOverlay(slotFrame, slotInfo, "target")
        end
    end

    inspectPaneInitialized = true
end

---------------------------------------------------------------------------
-- Update inspect frame (called from qui_character.lua's ScheduleUpdate)
---------------------------------------------------------------------------
local function UpdateInspectFrame()
    if not InspectFrame or not InspectFrame:IsShown() then return end

    local settings = GetSettings()
    local shared = GetShared()

    if settings.inspectEnabled then
        -- Full overlay mode: always use detailed overlays, never lite mode
        HideLiteDisplays()
        if shared.UpdateAllSlotOverlays then
            shared.UpdateAllSlotOverlays("target", inspectOverlays)
        end
    elseif settings.inspectLiteShowPerSlot or settings.inspectLiteShowOverall then
        -- Lite mode (only when full overlays disabled): show enabled lite displays
        HideDetailedOverlays()
        UpdateAllLiteDisplays("target")
    else
        -- All disabled: hide everything
        HideLiteDisplays()
        HideDetailedOverlays()
    end

    -- Update header display (name, ilvl, spec)
    UpdateInspectILvlDisplay()

    -- Update slot borders based on item quality
    UpdateAllInspectSlotBorders("target")
end

---------------------------------------------------------------------------
-- Hook inspect frame
---------------------------------------------------------------------------
local function HookInspectFrame()
    if not InspectFrame then return end

    local settings = GetSettings()
    -- Skip if full overlays are disabled AND no lite features are enabled
    local hasLiteFeature = settings.inspectLiteShowPerSlot or settings.inspectLiteShowOverall
    if settings.inspectEnabled == false and not hasLiteFeature then return end

    local shared = GetShared()

    InspectFrame:HookScript("OnShow", function()
        local currentSettings = GetSettings()
        currentInspectTab = 1

        -- Only apply full layout/overlays when full overlay mode is enabled
        if currentSettings.inspectEnabled then
            ApplyInspectPaneLayout()
            InitializeInspectOverlays()
        end

        C_Timer.After(0.1, function()
            local unit = InspectFrame.unit or "target"
            -- Use pcall to protect against edge cases (unit out of range mid-check)
            local ok, canInspect = pcall(function() return UnitExists(unit) and CanInspect(unit) end)
            if ok and canInspect then
                NotifyInspect(unit)
            end
        end)

        if shared.ScheduleUpdate then
            C_Timer.After(0.3, shared.ScheduleUpdate)
        end
    end)

    InspectFrame:HookScript("OnHide", function()
        inspectLayoutApplied = false
        InspectFrame:SetWidth(INSPECT_CONFIG.FRAME_DEFAULT_WIDTH)
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

---------------------------------------------------------------------------
-- Event frame for inspect-specific events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("INSPECT_READY")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then
            C_Timer.After(0.1, function()
                HookInspectFrame()
            end)
        end
    elseif event == "INSPECT_READY" then
        -- arg1 is the GUID of the inspected unit
        currentInspectGUID = arg1
        local shared = GetShared()
        if shared.ScheduleUpdate then
            shared.ScheduleUpdate()
        end
    end
end)

---------------------------------------------------------------------------
-- Module API (exported for qui_character.lua to call)
---------------------------------------------------------------------------
QUI.InspectPane = {
    UpdateInspectFrame = UpdateInspectFrame,
    GetCurrentTab = GetCurrentInspectTab,
    INSPECT_CONFIG = INSPECT_CONFIG,
}

ns.InspectPane = QUI.InspectPane
