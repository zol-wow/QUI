---------------------------------------------------------------------------
-- QUI Character Pane Module
-- Custom character panel styling with equipment overlays and stats panel
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local QUICore = ns.Addon

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- COMBAT DEFERRAL — CharacterFrame is a managed panel; SetScale,
-- ClearAllPoints, SetPoint on it or its children are protected during
-- combat.  Track desired state and apply on PLAYER_REGEN_ENABLED.
---------------------------------------------------------------------------
local pendingCharScale = nil     -- deferred SetScale value
local pendingTabMode   = nil     -- "character" or "other"
local pendingDecorMode = nil     -- "character" or "other"
local pendingStatsPanelRefresh = false
local ScheduleUpdate

local charCombatFrame = CreateFrame("Frame")
charCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
charCombatFrame:SetScript("OnEvent", function()
    -- If CharacterFrame closed during combat, nothing to apply
    if not CharacterFrame or not CharacterFrame:IsShown() then
        pendingCharScale = nil
        pendingTabMode   = nil
        pendingDecorMode = nil
        pendingStatsPanelRefresh = false
        return
    end

    if pendingCharScale then
        CharacterFrame:SetScale(pendingCharScale)
        pendingCharScale = nil
    end

    if pendingTabMode then
        -- These functions are defined inside HookCharacterFrame; use the
        -- deferred wrappers below instead of direct calls.
        if pendingTabMode == "other" then
            if CharacterFrameTab1 then
                CharacterFrameTab1:ClearAllPoints()
                CharacterFrameTab1:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 11, 2)
            end
            if CharacterFrame.CloseButton then
                CharacterFrame.CloseButton:ClearAllPoints()
                CharacterFrame.CloseButton:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -3, -5)
            end
        elseif pendingTabMode == "character" then
            if CharacterFrameTab1 then
                CharacterFrameTab1:ClearAllPoints()
                CharacterFrameTab1:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 11, -48)
            end
            if CharacterFrame.CloseButton then
                CharacterFrame.CloseButton:ClearAllPoints()
                CharacterFrame.CloseButton:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", 52, -5)
            end
        end
        pendingTabMode = nil
    end

    if pendingDecorMode then
        local skinHandles = _G.QUI_CharacterFrameSkinning
        if pendingDecorMode == "other" then
            if not (skinHandles and skinHandles.SetExtended) then
                if CharacterFramePortrait then CharacterFramePortrait:Show() end
                if CharacterFrame.Background then CharacterFrame.Background:Show() end
                if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Show() end
                if CharacterFrameBg then CharacterFrameBg:Show() end
            end
        elseif pendingDecorMode == "character" then
            if not (skinHandles and skinHandles.SetExtended) then
                if CharacterFramePortrait then CharacterFramePortrait:Hide() end
                if CharacterFrame.Background then CharacterFrame.Background:Hide() end
                if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Hide() end
                if CharacterFrameBg then CharacterFrameBg:Hide() end
            end
        end
        pendingDecorMode = nil
    end

    if pendingStatsPanelRefresh then
        pendingStatsPanelRefresh = false
        if ScheduleUpdate then
            C_Timer.After(0, ScheduleUpdate)
        end
    end
end)

--- Safe wrapper: set CharacterFrame scale, deferring during combat.
local function SafeSetCharScale(scale)
    if InCombatLockdown() then
        pendingCharScale = scale
    else
        CharacterFrame:SetScale(scale)
    end
end

-- Blizzard can return protected "secret" stat values in combat and some
-- restricted contexts. Probe the actual stat APIs instead of assuming a whole
-- activity type (for example active Mythic+) is unreadable.
local function AreCharacterStatsSecretsDisabled()
    local ok, healthMax = pcall(UnitHealthMax, "player")
    if not ok or Helpers.IsSecretValue(healthMax) then
        return true
    end

    local statBase, healthStat
    ok, statBase, healthStat = pcall(UnitStat, "player", 3)
    if not ok or Helpers.IsSecretValue(statBase) or Helpers.IsSecretValue(healthStat) then
        return true
    end

    if GetCombatRating and CR_CRIT_SPELL then
        local critRating
        ok, critRating = pcall(GetCombatRating, CR_CRIT_SPELL)
        if not ok or Helpers.IsSecretValue(critRating) then
            return true
        end
    end

    return false
end

---------------------------------------------------------------------------
-- Module Constants
---------------------------------------------------------------------------

-- Equipment slot mapping: slotName -> slotID
local EQUIPMENT_SLOTS = {
    { name = "Head", id = INVSLOT_HEAD, side = "left" },
    { name = "Neck", id = INVSLOT_NECK, side = "left" },
    { name = "Shoulder", id = INVSLOT_SHOULDER, side = "left" },
    { name = "Back", id = INVSLOT_BACK, side = "left" },
    { name = "Chest", id = INVSLOT_CHEST, side = "left" },
    { name = "Shirt", id = INVSLOT_BODY, side = "left" },
    { name = "Tabard", id = INVSLOT_TABARD, side = "left" },
    { name = "Wrist", id = INVSLOT_WRIST, side = "left" },
    { name = "MainHand", id = INVSLOT_MAINHAND, side = "bottom" },
    { name = "SecondaryHand", id = INVSLOT_OFFHAND, side = "bottom" },
    { name = "Hands", id = INVSLOT_HAND, side = "right" },
    { name = "Waist", id = INVSLOT_WAIST, side = "right" },
    { name = "Legs", id = INVSLOT_LEGS, side = "right" },
    { name = "Feet", id = INVSLOT_FEET, side = "right" },
    { name = "Finger0", id = INVSLOT_FINGER1, side = "right" },
    { name = "Finger1", id = INVSLOT_FINGER2, side = "right" },
    { name = "Trinket0", id = INVSLOT_TRINKET1, side = "right" },
    { name = "Trinket1", id = INVSLOT_TRINKET2, side = "right" },
}

-- Color palette (QUI brand colors)
local C = {
    bg = { 0.067, 0.094, 0.153, 0.95 },        -- Deep Cool Grey
    bgLight = { 0.122, 0.161, 0.216, 1 },      -- Dark Slate
    accent = { 0.376, 0.647, 0.980, 1 },         -- Sky Blue
    text = { 0.953, 0.957, 0.965, 1 },         -- Off-White
    textMuted = { 0.6, 0.65, 0.7, 1 },         -- Grey
    border = { 0.2, 0.25, 0.3, 1 },            -- Cool Grey

    -- Stat bar colors
    health = { 0.937, 0.267, 0.267, 1 },       -- Soft Red
    mana = { 0.231, 0.510, 0.965, 1 },         -- Soft Blue
    crit = { 0.976, 0.451, 0.086, 1 },         -- Orange
    haste = { 0.918, 0.702, 0.031, 1 },        -- Yellow
    mastery = { 0.545, 0.361, 0.965, 1 },      -- Purple
    versatility = { 0.024, 0.714, 0.831, 1 },  -- Cyan

    -- Status colors
    enchanted = { 0.376, 0.647, 0.980, 1 },      -- Sky Blue (enchanted)
    missing = { 0.6, 0.6, 0.6, 0.7 },          -- Muted grey (missing enchant)
}

-- Gem type colors (standard WoW gem socket colors)
local GEM_COLORS = {
    Red = { 1, 0.2, 0.2, 1 },
    Blue = { 0.2, 0.4, 1, 1 },
    Yellow = { 1, 0.8, 0.2, 1 },
    Meta = { 0.8, 0.8, 0.8, 1 },
    Prismatic = { 1, 1, 1, 1 },
    Hydraulic = { 0.2, 0.8, 0.8, 1 },
    Cogwheel = { 0.7, 0.7, 0.7, 1 },
    Domination = { 0.6, 0.2, 0.8, 1 },
    Tinker = { 0.4, 0.8, 0.4, 1 },
    Primordial = { 0.4, 0.6, 0.8, 1 },
}

-- Class name abbreviations for long names that overflow title area
local CLASS_ABBREVIATIONS = {
    ["Demon Hunter"] = "DH",
    ["Death Knight"] = "DK",
}

local function AbbreviateClassName(className)
    return CLASS_ABBREVIATIONS[className] or className
end

---------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------
local characterPaneInitialized = false
local slotOverlays = {}  -- Stores overlay frames for each slot
local statsPanel = nil
local pendingUpdate = false
local updatingStatsPanel = false  -- Guard to prevent multiple simultaneous updates

-- TAINT SAFETY: Store per-frame state in weak-keyed table instead of writing properties
-- to Blizzard frames, which taints them in Midnight (12.0)
local frameState, GetState = Helpers.CreateStateTable()
local EMPTY = {}

-- Forward declarations (for functions called before definition)
local CreateStatsPanel

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
-- Shared defaults table (reused when DB isn't ready to prevent reference issues)
local defaultSettings = {
    enabled = true,
    showItemName = true,
    showItemLevel = true,
    showEnchants = true,
    showGems = true,
    showDurability = false,
    inspectEnabled = true,
    showModelBackground = true,
    secondaryStatFormat = "both",
    showTooltips = false,
    -- Inspect-specific overlay settings (separate from character)
    showInspectItemName = true,
    showInspectItemLevel = true,
    showInspectEnchants = true,
    showInspectGems = true,
}

local function GetSettings()
    local settings = Helpers.GetModuleDB("character")
    return settings or defaultSettings
end

---------------------------------------------------------------------------
-- Forward declarations for font tracking (used by CreateSlotOverlay)
---------------------------------------------------------------------------
local trackedEnchantFonts = {}
local trackedILvlFonts = {}
local trackedItemNameFonts = {}  -- For item name text (line 1)

---------------------------------------------------------------------------
-- Get global font from QUI settings
---------------------------------------------------------------------------
local function GetGlobalFont()
    return Helpers.GetGeneralFont()
end

---------------------------------------------------------------------------
-- Shared styling helpers (character panel widgets)
---------------------------------------------------------------------------
local styledCloseButtons = Helpers.CreateStateTable()
local closeButtonBorders = Helpers.CreateStateTable()
local closeButtonLabels = Helpers.CreateStateTable()
local sidebarTabBorders = Helpers.CreateStateTable()
local sidebarTabHooked = Helpers.CreateStateTable()
local sidebarTabBaseWidth = nil
local sidebarTabBaseHeight = nil

local function ApplyOnePixelBorder(frame, withBackground)
    if not frame or not frame.SetBackdrop then return end
    local px = QUICore:GetPixelSize(frame)
    local backdrop = {
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    }

    if withBackground then
        backdrop.bgFile = "Interface\\Buttons\\WHITE8x8"
        backdrop.insets = { left = px, right = px, top = px, bottom = px }
    end

    frame:SetBackdrop(backdrop)
end

local function GetCharacterBorderColor()
    local globalQUI = _G.QUI
    if globalQUI and globalQUI.GetSkinColor then
        local r, g, b, a = globalQUI:GetSkinColor()
        if r and g and b then
            return r, g, b, a or 1
        end
    end
    return C.border[1], C.border[2], C.border[3], 1
end

local function GetCharacterAccentColor()
    local globalQUI = _G.QUI
    if globalQUI and globalQUI.GetSkinColor then
        local r, g, b, a = globalQUI:GetSkinColor()
        if r and g and b then
            return r, g, b, a or 1
        end
    end
    return C.accent[1], C.accent[2], C.accent[3], 1
end

local function StyleCloseButton(button)
    if not button then return end

    if button.Border then button.Border:SetAlpha(0) end
    if button.GetNormalTexture and button:GetNormalTexture() then button:GetNormalTexture():SetAlpha(0) end
    if button.GetPushedTexture and button:GetPushedTexture() then button:GetPushedTexture():SetAlpha(0) end
    if button.GetHighlightTexture and button:GetHighlightTexture() then button:GetHighlightTexture():SetAlpha(0) end
    if button.GetDisabledTexture and button:GetDisabledTexture() then button:GetDisabledTexture():SetAlpha(0) end

    local border = closeButtonBorders[button]
    if not border then
        border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        border:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        border:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 1))
        border:EnableMouse(false)
        ApplyOnePixelBorder(border, true)
        closeButtonBorders[button] = border
    end
    border:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 1))
    ApplyOnePixelBorder(border, true)

    local br, bg, bb = GetCharacterBorderColor()
    border:SetBackdropColor(0.08, 0.10, 0.14, 0.96)
    border:SetBackdropBorderColor(br, bg, bb, 1)

    local label = closeButtonLabels[button]
    if not label then
        label = button:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", button, "CENTER", 0, 0)
        if label.SetDrawLayer then
            label:SetDrawLayer("OVERLAY", 7)
        end
        closeButtonLabels[button] = label
    end
    label:SetFont(GetGlobalFont(), 11, "OUTLINE")
    label:SetText("X")
    label:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    if styledCloseButtons[button] then return end
    button:HookScript("OnEnter", function(self)
        local r, g, b = GetCharacterAccentColor()
        local bd = closeButtonBorders[self]
        if bd then bd:SetBackdropBorderColor(r, g, b, 1) end
    end)
    button:HookScript("OnLeave", function(self)
        local r, g, b = GetCharacterBorderColor()
        local bd = closeButtonBorders[self]
        if bd then bd:SetBackdropBorderColor(r, g, b, 1) end
    end)
    styledCloseButtons[button] = true
end

local function GetSidebarTabIcon(tab, index)
    if not tab then return nil end
    if tab.Icon then
        return tab.Icon
    end

    if index then
        local explicitIcon = _G["PaperDollSidebarTab" .. index .. "Icon"]
        if explicitIcon then
            return explicitIcon
        end
    end

    local name = tab.GetName and tab:GetName()
    local namedIcon = name and _G[name .. "Icon"]
    return namedIcon or tab.icon or (tab.GetNormalTexture and tab:GetNormalTexture())
end

local function IsSidebarTabActive(tab)
    if not tab then return false end
    if tab.GetChecked and tab:GetChecked() then return true end
    if tab.IsSelected and tab:IsSelected() then return true end
    if tab.SelectedTexture and tab.SelectedTexture.IsShown and tab.SelectedTexture:IsShown() then return true end
    return false
end

local function UpdateSidebarTabBorder(tab)
    local border = tab and sidebarTabBorders[tab]
    if not border then return end

    if IsSidebarTabActive(tab) then
        local r, g, b = GetCharacterAccentColor()
        border:SetBackdropBorderColor(r, g, b, 1)
    else
        local r, g, b = GetCharacterBorderColor()
        border:SetBackdropBorderColor(r, g, b, 1)
    end
end

local function FixSidebarTabRegionCoords(tex, x1)
    if x1 ~= 0.16001 then
        tex:SetTexCoord(0.16001, 0.86, 0.16, 0.86)
    end
end

local function StyleSidebarTab(tab, index, uniformWidth, uniformHeight)
    if not tab then return end

    -- Keep tab sizing consistent with tab 1 (ElvUI-style).
    if uniformWidth and uniformHeight and uniformWidth > 0 and uniformHeight > 0 then
        QUICore:SetPixelPerfectSize(tab, uniformWidth, uniformHeight)
    end

    local icon = GetSidebarTabIcon(tab, index)
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints()
        QUICore:ApplyPixelSnapping(icon)
    end

    if tab.Highlight then
        tab.Highlight:SetColorTexture(1, 1, 1, 0.3)
        tab.Highlight:ClearAllPoints()
        tab.Highlight:SetAllPoints(tab)
    end

    if tab.Hider then
        tab.Hider:SetColorTexture(0, 0, 0, 0.8)
    end

    if tab.TabBg and tab.TabBg.Hide then
        tab.TabBg:Hide()
    end

    local border = sidebarTabBorders[tab]
    if not border then
        border = CreateFrame("Frame", nil, tab, "BackdropTemplate")
        border:SetFrameLevel(tab:GetFrameLevel() + 15)
        border:EnableMouse(false)
        ApplyOnePixelBorder(border, false)
        sidebarTabBorders[tab] = border
    end
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", tab, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 1, -1)

    if tab.Hider then
        tab.Hider:ClearAllPoints()
        tab.Hider:SetAllPoints(border)
    end

    ApplyOnePixelBorder(border, false)
    UpdateSidebarTabBorder(tab)

    -- Match ElvUI behavior: first tab's native regions keep fixed texcoords.
    if index == 1 and not (frameState[tab] or EMPTY).sidebarTexCoordHooked then
        for _, region in next, { tab:GetRegions() } do
            if region and region.SetTexCoord then
                region:SetTexCoord(0.16, 0.86, 0.16, 0.86)
                hooksecurefunc(region, "SetTexCoord", FixSidebarTabRegionCoords)
            end
        end
        GetState(tab).sidebarTexCoordHooked = true
    end

    if sidebarTabHooked[tab] then return end
    tab:HookScript("OnEnter", function(self)
        local r, g, b = GetCharacterAccentColor()
        local bd = sidebarTabBorders[self]
        if bd then bd:SetBackdropBorderColor(r, g, b, 1) end
    end)
    tab:HookScript("OnLeave", function(self)
        UpdateSidebarTabBorder(self)
    end)
    tab:HookScript("OnClick", function()
        C_Timer.After(0, function()
            for i = 1, 3 do
                UpdateSidebarTabBorder(_G["PaperDollSidebarTab" .. i])
            end
        end)
    end)
    sidebarTabHooked[tab] = true
end

local function StyleSidebarTabs()
    local tabs = { _G.PaperDollSidebarTab1, _G.PaperDollSidebarTab2, _G.PaperDollSidebarTab3 }

    -- Determine and cache a stable one-time reference size to prevent
    -- cumulative shrink when Blizzard refreshes sidebar tabs on click.
    if not sidebarTabBaseWidth or not sidebarTabBaseHeight then
        local refTab = tabs[1]
        if refTab and refTab.GetWidth and refTab.GetHeight then
            sidebarTabBaseWidth = math.floor((refTab:GetWidth() or 24) + 0.5)
            sidebarTabBaseHeight = math.floor((refTab:GetHeight() or 24) + 0.5)
        else
            sidebarTabBaseWidth, sidebarTabBaseHeight = 24, 24
        end
    end

    -- Force a centered, stable layout over the stats column.
    -- Stats panel center is approximately -38px from CharacterFrame TOPRIGHT.
    if CharacterFrame and sidebarTabBaseWidth and sidebarTabBaseHeight then
        local spacing = 0
        local totalWidth = (sidebarTabBaseWidth * 3) + (spacing * 2)
        local leftX = -38 - math.floor(totalWidth / 2)
        local topY = -40

        for index, tab in ipairs(tabs) do
            if tab then
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", leftX + ((index - 1) * (sidebarTabBaseWidth + spacing)), topY)
            end
        end

        if PaperDollSidebarTabs and tabs[1] and tabs[3] then
            PaperDollSidebarTabs:ClearAllPoints()
            PaperDollSidebarTabs:SetPoint("TOPLEFT", tabs[1], "TOPLEFT", 0, 0)
            PaperDollSidebarTabs:SetPoint("BOTTOMRIGHT", tabs[3], "BOTTOMRIGHT", 0, 0)
        end
    end

    for index, tab in ipairs(tabs) do
        if tab then
            StyleSidebarTab(tab, index, sidebarTabBaseWidth, sidebarTabBaseHeight)
        end
    end
end

---------------------------------------------------------------------------
-- Utility: Get item quality color
---------------------------------------------------------------------------
local function GetItemQualityColorRGB(quality)
    return Helpers.GetItemQualityColor(quality)
end

---------------------------------------------------------------------------
-- Utility: Format large numbers (17257920 -> "17.2M")
---------------------------------------------------------------------------
local function FormatNumber(num)
    if Helpers.IsSecretValue(num) then
        return "--"
    end

    num = Helpers.SafeToNumber(num, 0)
    if num == 0 then return "0" end

    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

---------------------------------------------------------------------------
-- Utility: Format stat percentage
---------------------------------------------------------------------------
local function FormatPercent(value, decimals)
    decimals = decimals or 2

    if Helpers.IsSecretValue(value) then
        return "--"
    end

    return string.format("%." .. decimals .. "f%%", Helpers.SafeToNumber(value, 0))
end

---------------------------------------------------------------------------
-- Get item level for a slot (tooltip-first approach for accuracy)
---------------------------------------------------------------------------
local function GetSlotItemLevel(unit, slotId)
    local itemLink = GetInventoryItemLink(unit, slotId)
    if not itemLink then return nil end

    local itemLevel = nil

    -- Ensure item data is cached
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
        if not C_Item.IsItemDataCachedByID(itemID) then
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end

    -- Try C_Item.GetItemInfo first (position 4 is ilvl)
    if C_Item and C_Item.GetItemInfo then
        local _, _, _, ilvl = C_Item.GetItemInfo(itemLink)
        if ilvl then
            itemLevel = ilvl
        end
    end

    -- Parse tooltip for actual displayed ilvl (this is the authoritative source)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local tooltipData = C_TooltipInfo.GetInventoryItem(unit, slotId)
        if tooltipData and tooltipData.lines then
            -- Use localized ITEM_LEVEL global or fallback pattern
            local pattern
            if ITEM_LEVEL then
                pattern = ITEM_LEVEL:gsub("%%d", "(%%d+)")
            else
                pattern = "Item Level (%d+)"  -- Fallback for English
            end
            for _, line in ipairs(tooltipData.lines) do
                local text = line.leftText or ""
                local tooltipIlvl = text:match(pattern)
                if tooltipIlvl then
                    local parsed = tonumber(tooltipIlvl)
                    if parsed then
                        itemLevel = parsed  -- Tooltip is authoritative, always use it
                    end
                    break
                end
            end
        end
    end

    return itemLevel
end

---------------------------------------------------------------------------
-- Get item quality for a slot
---------------------------------------------------------------------------
local function GetSlotItemQuality(unit, slotId)
    local ok, quality = pcall(function()
        return GetInventoryItemQuality(unit, slotId)
    end)
    if ok then
        return quality
    end
    return nil
end

---------------------------------------------------------------------------
-- Get enchant text for a slot (returns actual enchant name)
---------------------------------------------------------------------------
local function GetEnchantText(unit, slotId)
    local itemLink = GetInventoryItemLink(unit, slotId)
    if not itemLink then return nil, nil end  -- No item

    -- Not all slots can be enchanted - only check enchantable slots
    local enchantableSlots = {
        [INVSLOT_HEAD] = true,
        [INVSLOT_SHOULDER] = true,
        [INVSLOT_CHEST] = true,
        [INVSLOT_LEGS] = true,
        [INVSLOT_FEET] = true,
        [INVSLOT_FINGER1] = true,
        [INVSLOT_FINGER2] = true,
        [INVSLOT_MAINHAND] = true,
        [INVSLOT_OFFHAND] = true,
    }

    if not enchantableSlots[slotId] then
        return nil, false  -- Not enchantable
    end

    -- Use tooltip info API if available (Midnight+)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local tooltipData = C_TooltipInfo.GetInventoryItem(unit, slotId)
        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                local text = line.leftText or ""
                -- Try to match "Enchanted: X" pattern using WoW's localized constant
                local enchant
                if ENCHANTED_TOOLTIP_LINE then
                    -- Use localized pattern: "Enchanted: %s"
                    local pattern = ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.+)")
                    enchant = text:match(pattern)
                end
                -- Fallback pattern matching
                if not enchant then
                    enchant = text:match("Enchanted:%s*(.+)")
                end
                if enchant then
                    -- Strip "Enchant X - " prefix to get clean name
                    enchant = enchant:gsub("Enchant%s+%w+%s*%-%s*", "")
                    -- Strip any remaining formatting codes
                    enchant = enchant:gsub("|c%x%x%x%x%x%x%x%x", "")
                    enchant = enchant:gsub("|r", "")
                    enchant = enchant:gsub("|A.-|a", "")
                    enchant = enchant:gsub("|T.-|t", "")
                    -- Trim whitespace
                    enchant = enchant:match("^%s*(.-)%s*$")
                    if enchant and enchant ~= "" then
                        return enchant, true  -- Return enchant text, slot is enchantable
                    end
                end
            end
        end
        return nil, true  -- Missing enchant, slot is enchantable
    end

    -- Fallback: assume no enchant detection available
    return nil, true
end

---------------------------------------------------------------------------
-- Get upgrade track info for a slot (e.g., "Myth 6/6", "Hero 4/6")
-- Uses localized global string ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING
---------------------------------------------------------------------------
local function GetUpgradeTrack(unit, slotId)
    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then
        return nil, nil, nil
    end

    local tooltipData = C_TooltipInfo.GetInventoryItem(unit, slotId)
    if not tooltipData or not tooltipData.lines then
        return nil, nil, nil
    end

    for _, line in ipairs(tooltipData.lines) do
        local text = line.leftText or ""

        -- Use the localized global format string for upgrade level
        -- ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING = "Upgrade Level: %s %d/%d"
        if ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING then
            local pattern = ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
            local track, current, max = text:match(pattern)
            if track and current and max then
                return track, current, max
            end
        end

        -- Fallback: try English "Upgrade Level: Track X/Y" pattern
        local track, current, max = text:match("Upgrade Level:%s*(.+)%s+(%d+)%s*/%s*(%d+)")
        if track and current and max then
            return track, current, max
        end

        -- Fallback: colon-prefixed pattern for other locales
        track, current, max = text:match(": (.+)%s+(%d+)%s*/%s*(%d+)")
        if track and current and max then
            return track, current, max
        end
    end

    return nil, nil, nil
end

---------------------------------------------------------------------------
-- Get gem info for a slot (returns gems and total socket count)
---------------------------------------------------------------------------
local function GetGemInfo(unit, slotId)
    local itemLink = GetInventoryItemLink(unit, slotId)
    if not itemLink then return {}, 0 end

    local gems = {}
    local totalSockets = 0

    -- First, detect total socket count by parsing tooltip
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local tooltipData = C_TooltipInfo.GetInventoryItem(unit, slotId)
        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                -- Socket lines have type 3 in tooltip data
                if line.type == 3 then
                    totalSockets = totalSockets + 1
                end
            end
        end
    end

    -- Get filled gems (up to 4 slots)
    local filledCount = 0
    for i = 1, 4 do
        -- GetItemGem returns TWO values: gemName, gemLink (we need the link for icon lookup)
        local gemName, gemLink = GetItemGem(itemLink, i)

        if gemLink then
            filledCount = filledCount + 1
            -- Get gem icon texture from item info (icon is the 10th return value)
            local _, _, _, _, _, _, gemSubType, _, _, gemIcon = GetItemInfo(gemLink)

            -- If GetItemInfo didn't return icon yet (item not cached), try C_Item API
            if not gemIcon and C_Item and C_Item.GetItemIconByID then
                local itemID = GetItemInfoInstant(gemLink)
                if itemID then
                    gemIcon = C_Item.GetItemIconByID(itemID)
                end
            end

            table.insert(gems, {
                link = gemLink,
                icon = gemIcon,
                type = gemSubType or "Prismatic",
                filled = true,
            })
        end
    end

    -- If tooltip detection failed, use filled count as minimum
    if totalSockets < filledCount then
        totalSockets = filledCount
    end

    -- Add empty socket entries
    local emptySockets = totalSockets - filledCount
    for i = 1, emptySockets do
        table.insert(gems, {
            link = nil,
            icon = nil,
            type = "Empty",
            filled = false,
        })
    end

    return gems, totalSockets
end

---------------------------------------------------------------------------
-- Get durability for a slot
---------------------------------------------------------------------------
local function GetSlotDurability(slotId)
    local current, max = GetInventoryItemDurability(slotId)
    if current and max and max > 0 then
        return current, max, (current / max) * 100
    end
    return nil, nil, nil
end

---------------------------------------------------------------------------
-- Create overlay frame for an equipment slot
-- @param slotFrame: The slot frame to overlay
-- @param slotInfo: Slot configuration (id, name, side, etc.)
-- @param unit: Optional unit type ("player" or "target") for settings lookup
---------------------------------------------------------------------------
local function CreateSlotOverlay(slotFrame, slotInfo, unit)
    if not slotFrame then return nil end

    -- Get scale setting
    local settings = GetSettings()
    local scale = 1.0

    -- Base sizes (will be multiplied by scale)
    local ITEM_LEVEL_FONT = math.floor(12 * scale)
    local ENCHANT_FONT = math.floor(9 * scale)
    local ENCHANT_WIDTH_LEFT = math.floor(110 * scale)
    local ENCHANT_WIDTH_RIGHT = math.floor(75 * scale)
    local GEM_SIZE = math.floor(12 * scale)
    local GEM_SPACING = math.floor(2 * scale)

    local overlay = CreateFrame("Frame", nil, slotFrame)
    overlay:SetAllPoints(slotFrame)
    overlay:SetFrameLevel(slotFrame:GetFrameLevel() + 10)
    overlay:SetClipsChildren(false)
    overlay.unit = unit or "player"  -- Store unit for font refresh

    -- === 3-LINE TEXT LAYOUT ===
    -- Line 1: Item Name
    -- Line 2: ilvl + upgrade track (e.g., "289 (Myth 6/6)")
    -- Line 3: Enchant (single line)
    -- Text on INNER side, Gems on OUTER side
    -- Weapons: Name BELOW icon, Enchant ABOVE icon

    -- Unified font and size for all 3 lines (controlled by single slider)
    -- Use inspect-specific setting for target unit
    local slotFont = GetGlobalFont()
    local slotTextSize
    if unit == "target" then
        slotTextSize = settings.inspectSlotTextSize or 12
    else
        slotTextSize = settings.slotTextSize or ENCHANT_FONT
    end
    local TEXT_WIDTH = math.floor(140 * scale)
    local FONT_FLAGS = "OUTLINE"  -- Thin black outline for readability

    -- Line 1: Item Name
    overlay.itemName = overlay:CreateFontString(nil, "OVERLAY")
    overlay.itemName:SetFont(slotFont, slotTextSize, FONT_FLAGS)
    overlay.itemName:SetTextColor(1, 1, 1, 1)  -- Will be colored by quality
    overlay.itemName:SetWordWrap(false)
    overlay.itemName:SetWidth(TEXT_WIDTH)
    -- Only track character panel fonts (not inspect) for font refresh
    if unit ~= "target" then
        table.insert(trackedItemNameFonts, overlay.itemName)
    end

    -- Line 2: Item Level + Upgrade Track
    overlay.itemLevel = overlay:CreateFontString(nil, "OVERLAY")
    overlay.itemLevel:SetFont(slotFont, slotTextSize, FONT_FLAGS)
    overlay.itemLevel:SetTextColor(1, 1, 1, 1)
    overlay.itemLevel:SetWordWrap(false)
    if unit ~= "target" then
        table.insert(trackedILvlFonts, overlay.itemLevel)
    end

    -- Line 3: Enchant text (single line, truncated)
    -- Compute enchant color respecting class color toggle
    -- Use inspect-specific settings when unit is target
    local enchantColor
    local useClassColor = unit == "target" and settings.inspectEnchantClassColor or settings.enchantClassColor
    local customEnchantColor = unit == "target" and settings.inspectEnchantTextColor or settings.enchantTextColor
    if useClassColor then
        local _, class = UnitClass(unit or "player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            enchantColor = {classColor.r, classColor.g, classColor.b}
        else
            enchantColor = customEnchantColor or C.enchanted
        end
    else
        enchantColor = customEnchantColor or C.enchanted
    end
    overlay.enchant = overlay:CreateFontString(nil, "OVERLAY")
    overlay.enchant:SetFont(slotFont, slotTextSize, FONT_FLAGS)
    overlay.enchant:SetTextColor(enchantColor[1], enchantColor[2], enchantColor[3], 1)
    overlay.enchant:SetWordWrap(false)
    overlay.enchant:SetWidth(TEXT_WIDTH)
    if unit ~= "target" then
        table.insert(trackedEnchantFonts, overlay.enchant)
    end

    -- Position text on INNER side of column (3-line vertical stack)
    if slotInfo.side == "left" then
        -- Text on RIGHT (inner side)
        overlay.itemName:SetPoint("TOPLEFT", overlay, "TOPRIGHT", 4, 2)
        overlay.itemName:SetJustifyH("LEFT")
        overlay.itemLevel:SetPoint("TOPLEFT", overlay.itemName, "BOTTOMLEFT", 0, -1)
        overlay.itemLevel:SetJustifyH("LEFT")
        overlay.enchant:SetPoint("TOPLEFT", overlay.itemLevel, "BOTTOMLEFT", 0, -1)
        overlay.enchant:SetJustifyH("LEFT")
    elseif slotInfo.side == "right" then
        -- Text on LEFT (inner side)
        overlay.itemName:SetPoint("TOPRIGHT", overlay, "TOPLEFT", -4, 2)
        overlay.itemName:SetJustifyH("RIGHT")
        overlay.itemLevel:SetPoint("TOPRIGHT", overlay.itemName, "BOTTOMRIGHT", 0, -1)
        overlay.itemLevel:SetJustifyH("RIGHT")
        overlay.enchant:SetPoint("TOPRIGHT", overlay.itemLevel, "BOTTOMRIGHT", 0, -1)
        overlay.enchant:SetJustifyH("RIGHT")
    elseif slotInfo.id == INVSLOT_MAINHAND then
        -- MainHand weapon: Text on LEFT side (3-line stack)
        overlay.itemName:SetPoint("TOPRIGHT", overlay, "TOPLEFT", -4, 2)
        overlay.itemName:SetJustifyH("RIGHT")
        overlay.itemLevel:SetPoint("TOPRIGHT", overlay.itemName, "BOTTOMRIGHT", 0, -1)
        overlay.itemLevel:SetJustifyH("RIGHT")
        overlay.enchant:SetPoint("TOPRIGHT", overlay.itemLevel, "BOTTOMRIGHT", 0, -1)
        overlay.enchant:SetJustifyH("RIGHT")
    else
        -- SecondaryHand weapon: Text on RIGHT side (3-line stack)
        overlay.itemName:SetPoint("TOPLEFT", overlay, "TOPRIGHT", 4, 2)
        overlay.itemName:SetJustifyH("LEFT")
        overlay.itemLevel:SetPoint("TOPLEFT", overlay.itemName, "BOTTOMLEFT", 0, -1)
        overlay.itemLevel:SetJustifyH("LEFT")
        overlay.enchant:SetPoint("TOPLEFT", overlay.itemLevel, "BOTTOMLEFT", 0, -1)
        overlay.enchant:SetJustifyH("LEFT")
    end

    -- Gem icons on OUTER side of column (reversed from before)
    overlay.gems = {}
    for i = 1, 4 do
        local gem = overlay:CreateTexture(nil, "OVERLAY")
        gem:SetSize(GEM_SIZE, GEM_SIZE)
        gem:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Position gems on OUTER side
        if slotInfo.side == "left" then
            -- Gems on LEFT (outer side) - stack vertically
            local yOffset = (i - 1) * (GEM_SIZE + GEM_SPACING)
            gem:SetPoint("TOPRIGHT", overlay, "TOPLEFT", -2, -yOffset)
        elseif slotInfo.side == "right" then
            -- Gems on RIGHT (outer side) - stack vertically
            local yOffset = (i - 1) * (GEM_SIZE + GEM_SPACING)
            gem:SetPoint("TOPLEFT", overlay, "TOPRIGHT", 2, -yOffset)
        elseif slotInfo.id == INVSLOT_MAINHAND then
            -- MainHand: gems on RIGHT (text is on LEFT)
            local yOffset = (i - 1) * (GEM_SIZE + GEM_SPACING)
            gem:SetPoint("TOPLEFT", overlay, "TOPRIGHT", 2, -yOffset)
        else
            -- SecondaryHand: gems on LEFT (text is on RIGHT)
            local yOffset = (i - 1) * (GEM_SIZE + GEM_SPACING)
            gem:SetPoint("TOPRIGHT", overlay, "TOPLEFT", -2, -yOffset)
        end
        gem:Hide()

        overlay.gems[i] = gem
    end

    -- Store scale for later reference
    overlay.currentScale = scale

    -- Durability bar (optional, vertical bar on side)
    overlay.durabilityBar = CreateFrame("StatusBar", nil, overlay)
    overlay.durabilityBar:SetSize(3, slotFrame:GetHeight() - 4)
    overlay.durabilityBar:SetPoint("LEFT", overlay, "LEFT", 2, 0)
    overlay.durabilityBar:SetOrientation("VERTICAL")
    overlay.durabilityBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    overlay.durabilityBar:SetMinMaxValues(0, 100)
    overlay.durabilityBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
    overlay.durabilityBar:Hide()

    -- Background for durability bar
    local duraBg = overlay.durabilityBar:CreateTexture(nil, "BACKGROUND")
    duraBg:SetAllPoints()
    duraBg:SetColorTexture(0, 0, 0, 0.5)

    overlay.slotInfo = slotInfo
    return overlay
end

---------------------------------------------------------------------------
-- Update a single slot overlay
---------------------------------------------------------------------------
local function UpdateSlotOverlay(overlay, unit)
    if not overlay or not overlay.slotInfo then return end

    local settings = GetSettings()
    if not settings.enabled then
        overlay:Hide()
        return
    end

    -- Use inspect-specific settings when not player
    -- Use ~= false pattern so nil (missing from saved vars) defaults to true (show)
    local isInspect = unit ~= "player"
    local showItemName, showItemLevel, showEnchants, showGems
    if isInspect then
        showItemName = settings.showInspectItemName ~= false
        showItemLevel = settings.showInspectItemLevel ~= false
        showEnchants = settings.showInspectEnchants ~= false
        showGems = settings.showInspectGems ~= false
    else
        showItemName = settings.showItemName ~= false
        showItemLevel = settings.showItemLevel ~= false
        showEnchants = settings.showEnchants ~= false
        showGems = settings.showGems ~= false
    end

    local slotId = overlay.slotInfo.id
    local itemLink = GetInventoryItemLink(unit, slotId)

    if not itemLink then
        overlay:Hide()
        return
    end

    overlay:Show()

    -- Get item info for name and quality
    local itemName = GetItemInfo(itemLink)
    local quality = GetSlotItemQuality(unit, slotId)
    local r, g, b = GetItemQualityColorRGB(quality)

    -- Update item name (Line 1)
    if overlay.itemName then
        if showItemName and itemName then
            overlay.itemName:SetText(itemName)
            overlay.itemName:SetTextColor(r, g, b, 1)
            overlay.itemName:Show()
        else
            overlay.itemName:Hide()
        end
    end

    -- Update item level + upgrade track (Line 2)
    -- ilvl is always white, track is customizable color
    -- Left column: "289 (Myth 6/6)" | Right column: "(Myth 6/6) 289"
    if showItemLevel then
        local itemLevel = GetSlotItemLevel(unit, slotId)

        if itemLevel then
            -- Get upgrade track (e.g., "Myth", "6", "6")
            local track, current, max = GetUpgradeTrack(unit, slotId)
            local ilvlText
            if track and current and max then
                -- Get track color from settings or default to orange
                -- Use inspect-specific color when unit is target
                local trackColor = unit == "target" and settings.inspectUpgradeTrackColor or settings.upgradeTrackColor
                trackColor = trackColor or {0.98, 0.60, 0.35, 1}
                local trackHex = string.format("%02x%02x%02x",
                    math.floor(trackColor[1] * 255),
                    math.floor(trackColor[2] * 255),
                    math.floor(trackColor[3] * 255))
                -- Mirror format based on column side
                -- Text on right side of slot = ilvl (Track)
                -- Text on left side of slot = (Track) ilvl
                local slotSide = overlay.slotInfo and overlay.slotInfo.side
                local slotId = overlay.slotInfo and overlay.slotInfo.id
                if slotSide == "right" or slotId == INVSLOT_MAINHAND then
                    -- Right column & MainHand (text on left): (Track) ilvl
                    ilvlText = string.format("|cff%s(%s %s/%s)|r %d", trackHex, track, current, max, itemLevel)
                else
                    -- Left column & SecondaryHand (text on right): ilvl (Track)
                    ilvlText = string.format("%d |cff%s(%s %s/%s)|r", itemLevel, trackHex, track, current, max)
                end
            else
                ilvlText = tostring(itemLevel)
            end
            overlay.itemLevel:SetText(ilvlText)
            overlay.itemLevel:SetTextColor(1, 1, 1, 1)  -- Always white base
            overlay.itemLevel:Show()
        else
            overlay.itemLevel:Hide()
        end
    else
        overlay.itemLevel:Hide()
    end

    -- Update enchant text (shows actual enchant name)
    if showEnchants then
        local enchantText, isEnchantable = GetEnchantText(unit, slotId)
        -- Compute enchant color respecting class color toggle
        -- Use inspect-specific settings when unit is target
        local enchantColor
        local useClassColor = unit == "target" and settings.inspectEnchantClassColor or settings.enchantClassColor
        local customEnchantColor = unit == "target" and settings.inspectEnchantTextColor or settings.enchantTextColor
        local noEnchantColor = unit == "target" and settings.inspectNoEnchantTextColor or settings.noEnchantTextColor
        noEnchantColor = noEnchantColor or {0.5, 0.5, 0.5}
        if useClassColor then
            local _, class = UnitClass(unit)
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                enchantColor = {classColor.r, classColor.g, classColor.b}
            else
                enchantColor = customEnchantColor or C.enchanted
            end
        else
            enchantColor = customEnchantColor or C.enchanted
        end

        if isEnchantable then
            if enchantText then
                overlay.enchant:SetText(enchantText)
                overlay.enchant:SetTextColor(enchantColor[1], enchantColor[2], enchantColor[3], 1)
            else
                -- Enchantable slot but no enchant - show "No Enchant" in customizable color
                overlay.enchant:SetText("No Enchant")
                overlay.enchant:SetTextColor(noEnchantColor[1], noEnchantColor[2], noEnchantColor[3], 1)
            end
            overlay.enchant:Show()
        else
            overlay.enchant:Hide()
        end
    else
        overlay.enchant:Hide()
    end

    -- Update gem icons (actual textures, including empty sockets)
    if showGems then
        local gems, totalSockets = GetGemInfo(unit, slotId)
        for i, gemTex in ipairs(overlay.gems) do
            if gems[i] then
                if gems[i].filled then
                    -- Filled socket: show gem icon
                    local gemIcon = gems[i].icon
                    -- Must be valid icon (non-nil, non-zero, and numeric)
                    if gemIcon and gemIcon ~= 0 and type(gemIcon) == "number" then
                        gemTex:SetTexture(gemIcon)
                        gemTex:SetDesaturated(false)
                        gemTex:SetVertexColor(1, 1, 1, 1)
                        gemTex:Show()
                    else
                        -- Fallback to colored square if icon not available
                        local gemType = gems[i].type or "Prismatic"
                        local color = GEM_COLORS[gemType] or GEM_COLORS.Prismatic
                        gemTex:SetColorTexture(color[1], color[2], color[3], color[4])
                        gemTex:SetDesaturated(false)
                        gemTex:Show()
                    end
                else
                    -- Empty socket: show grey socket icon
                    gemTex:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
                    gemTex:SetDesaturated(true)
                    gemTex:SetVertexColor(0.6, 0.6, 0.6, 0.9)
                    gemTex:Show()
                end
            else
                gemTex:Hide()
            end
        end
    else
        for _, gemTex in ipairs(overlay.gems) do
            gemTex:Hide()
        end
    end

    -- Update durability bar
    if settings.showDurability and unit == "player" then
        local current, max, pct = GetSlotDurability(slotId)
        if pct then
            overlay.durabilityBar:SetValue(pct)
            -- Color: green > yellow > red based on durability
            if pct > 50 then
                overlay.durabilityBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            elseif pct > 25 then
                overlay.durabilityBar:SetStatusBarColor(0.8, 0.8, 0.2, 1)
            else
                overlay.durabilityBar:SetStatusBarColor(0.8, 0.2, 0.2, 1)
            end
            overlay.durabilityBar:Show()
        else
            overlay.durabilityBar:Hide()
        end
    else
        overlay.durabilityBar:Hide()
    end
end

---------------------------------------------------------------------------
-- LAYOUT REARRANGEMENT FUNCTIONS
-- These rearrange Blizzard's CharacterFrame into a portrait-style layout
---------------------------------------------------------------------------

-- Track if layout has been applied
local layoutApplied = false
local repositionPending = false  -- Debounce for slot repositioning hook
local customBg = nil
local equipMgrPopup = nil  -- Floating Equipment Manager container
local titlesPopup = nil      -- Floating Titles container
local allEquipmentSlots = {}  -- Stores all equipment slot frames for border updates
local UpdateEquipmentSlotBorder = nil  -- Function to update slot borders (set in HideBlizzardDecorations)

---------------------------------------------------------------------------
-- Helper: Check if skinning module is handling the background
---------------------------------------------------------------------------
local function IsSkinningHandlingBackground()
    local skinningAPI = _G.QUI_CharacterFrameSkinning
    return skinningAPI and skinningAPI.IsEnabled and skinningAPI.IsEnabled()
end

---------------------------------------------------------------------------
-- Hide Blizzard CharacterFrame decorations
---------------------------------------------------------------------------
local function HideBlizzardDecorations()
    local settings = GetSettings()

    -- Main frame decorations (only hide elements specific to Character tab)
    -- NOTE: Don't hide CharacterFrame.NineSlice, CharacterFrame.Bg, or CharacterFramePortrait globally
    -- Portrait visibility is handled in tab switching hooks
    if CharacterFrame.TopTileStreaks then CharacterFrame.TopTileStreaks:Hide() end

    -- Hide Blizzard's center character name text (we show ilvl in center instead)
    if CharacterFrameTitleText then CharacterFrameTitleText:Hide() end
    if CharacterFrame.TitleText then CharacterFrame.TitleText:Hide() end

    -- Hide sidebar tab decorations (ornate corner textures in top-right)
    if PaperDollSidebarTabs then
        if PaperDollSidebarTabs.DecorLeft then PaperDollSidebarTabs.DecorLeft:Hide() end
        if PaperDollSidebarTabs.DecorRight then PaperDollSidebarTabs.DecorRight:Hide() end
        -- Sidebar tab positions are normalized in StyleSidebarTabs().
        PaperDollSidebarTabs:ClearAllPoints()
        PaperDollSidebarTabs:SetPoint("TOP", CharacterFrame, "TOPRIGHT", -38, -30)
        StyleSidebarTabs()
    end

    -- Move close button 30px right to align with extended panel
    if CharacterFrame.CloseButton then
        CharacterFrame.CloseButton:ClearAllPoints()
        CharacterFrame.CloseButton:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", 52, -5)
        StyleCloseButton(CharacterFrame.CloseButton)
    end

    -- Move bottom tabs (Character/Reputation/Currency) down 50px
    if CharacterFrameTab1 then
        CharacterFrameTab1:ClearAllPoints()
        CharacterFrameTab1:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 11, -48)
    end

    -- Character frame inset decorations
    if CharacterFrameInset then
        if CharacterFrameInset.NineSlice then CharacterFrameInset.NineSlice:Hide() end
        if CharacterFrameInset.Bg then CharacterFrameInset.Bg:SetAlpha(0) end
    end

    -- Stats pane background
    if CharacterFrameInsetRight then
        if CharacterFrameInsetRight.Bg then CharacterFrameInsetRight.Bg:SetAlpha(0) end
        if CharacterFrameInsetRight.NineSlice then CharacterFrameInsetRight.NineSlice:Hide() end
    end

    -- Mask Blizzard's stats pane (we replace it visually). Keep it Shown so
    -- Blizzard's unrestricted code keeps updating its FontStrings — we mirror
    -- those into our panel during combat / encounters / M+ / PvP, when API
    -- reads from addon code return secret values.
    if CharacterStatsPane then
        pcall(CharacterStatsPane.SetAlpha, CharacterStatsPane, 0)
        if CharacterStatsPane.EnableMouse then
            pcall(CharacterStatsPane.EnableMouse, CharacterStatsPane, false)
        end
        if CharacterStatsPane.ClassBackground then
            pcall(CharacterStatsPane.ClassBackground.SetAlpha, CharacterStatsPane.ClassBackground, 0)
        end
    end

    -- PaperDoll inner borders
    local innerBorders = {
        "PaperDollInnerBorderBottom", "PaperDollInnerBorderBottom2",
        "PaperDollInnerBorderBottomLeft", "PaperDollInnerBorderBottomRight",
        "PaperDollInnerBorderLeft", "PaperDollInnerBorderRight",
        "PaperDollInnerBorderTop", "PaperDollInnerBorderTopLeft",
        "PaperDollInnerBorderTopRight",
    }
    for _, borderName in ipairs(innerBorders) do
        local border = _G[borderName]
        if border then border:Hide() end
    end

    -- Slot frame decorations (the colored borders around slots)
    local slotFrames = {
        "CharacterBackSlotFrame", "CharacterChestSlotFrame", "CharacterFeetSlotFrame",
        "CharacterFinger0SlotFrame", "CharacterFinger1SlotFrame", "CharacterHandsSlotFrame",
        "CharacterHeadSlotFrame", "CharacterLegsSlotFrame", "CharacterMainHandSlotFrame",
        "CharacterNeckSlotFrame", "CharacterSecondaryHandSlotFrame", "CharacterShirtSlotFrame",
        "CharacterShoulderSlotFrame", "CharacterTabardSlotFrame", "CharacterTrinket0SlotFrame",
        "CharacterTrinket1SlotFrame", "CharacterWaistSlotFrame", "CharacterWristSlotFrame",
    }
    for _, frameName in ipairs(slotFrames) do
        local frame = _G[frameName]
        if frame then
            frame:Hide()
            -- Hook to keep hidden (Blizzard may re-show on updates)
            if not (frameState[frame] or EMPTY).hideHooked then
                hooksecurefunc(frame, "Show", function(self)
                    C_Timer.After(0, function()
                        if self and self.Hide then self:Hide() end
                    end)
                end)
                GetState(frame).hideHooked = true
            end
        end
    end

    -- Block Blizzard's IconBorder from showing (prevent double borders)
    local function BlockIconBorder(iconBorder)
        if not iconBorder or (frameState[iconBorder] or EMPTY).blocked then return end
        GetState(iconBorder).blocked = true
        iconBorder:SetAlpha(0)
        if iconBorder.SetTexture then iconBorder:SetTexture(nil) end
        Helpers.DeferredSetAtlasBlock(iconBorder, false)
    end

    -- Skin equipment slot icons (same pattern as CDM/buff bar)
    local function SkinEquipmentSlot(slot)
        if not slot then return end

        -- Hide NormalTexture (decorative frame)
        local normalTex = slot:GetNormalTexture()
        if normalTex then normalTex:SetAlpha(0) end

        -- Hide BottomRightSlotTexture if exists (decorative corner on weapon slots)
        if slot.BottomRightSlotTexture then
            slot.BottomRightSlotTexture:Hide()
        end

        -- Hide non-icon decorative regions, but preserve runtime-state overlays
        -- that Blizzard toggles on filter contexts (upgrade vendor dim/dither
        -- via ItemContextOverlay, bag search via searchOverlay, status badges
        -- via IconOverlay/2, quest border via IconQuestTexture).
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

        -- Block Blizzard's IconBorder (we use custom border frame instead)
        if slot.IconBorder then
            BlockIconBorder(slot.IconBorder)
        end

        -- Apply base crop to icon texture (0.08/0.92 pattern - removes grey edges)
        local iconTex = slot.icon or slot.Icon
        if iconTex and iconTex.SetTexCoord then
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        -- Create border frame as child of slot (won't be affected by Blizzard's texture updates)
        if not (frameState[slot] or EMPTY).borderFrame then
            local borderFrame = CreateFrame("Frame", nil, slot, "BackdropTemplate")
            borderFrame:SetFrameLevel(slot:GetFrameLevel() + 10)
            borderFrame:SetAllPoints(slot)
            local px = QUICore:GetPixelSize(borderFrame)
            borderFrame:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = px,
            })
            GetState(slot).borderFrame = borderFrame
        end
    end

    -- Update border color based on equipped item quality
    local function UpdateSlotBorder(slot)
        local borderFrame = slot and (frameState[slot] or EMPTY).borderFrame
        if not borderFrame then return end

        local slotID = slot:GetID()

        -- Use GetInventoryItemQuality (more reliable than C_Item.GetItemInfo which can return nil)
        local quality = GetInventoryItemQuality("player", slotID)

        if quality and quality >= 1 then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            borderFrame:SetBackdropBorderColor(r, g, b, 1)
            borderFrame:Show()
        else
            borderFrame:Hide()
        end
    end

    -- All equipment slot names
    local equipmentSlotNames = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
        "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
        "CharacterTabardSlot", "CharacterWristSlot", "CharacterHandsSlot",
        "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot",
        "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
    }

    -- Skin all equipment slots
    local allSlots = {}
    for _, slotName in ipairs(equipmentSlotNames) do
        local slot = _G[slotName]
        if slot then
            SkinEquipmentSlot(slot)
            UpdateSlotBorder(slot)
            table.insert(allSlots, slot)
        end
    end

    -- Expose to module scope for OnShow refresh
    allEquipmentSlots = allSlots
    UpdateEquipmentSlotBorder = UpdateSlotBorder

    -- Hook equipment changes to update all borders
    local firstSlot = allSlots[1]
    if firstSlot and not (frameState[firstSlot] or EMPTY).equipHooked then
        firstSlot:HookScript("OnEvent", function(self, event)
            if event == "PLAYER_EQUIPMENT_CHANGED" then
                C_Timer.After(0.1, function()
                    for _, slot in ipairs(allSlots) do
                        UpdateSlotBorder(slot)
                    end
                end)
            end
        end)
        GetState(firstSlot).equipHooked = true
    end

    -- Model scene background elements
    local modelBgs = {
        "CharacterModelFrameBackgroundTopLeft", "CharacterModelFrameBackgroundBotLeft",
        "CharacterModelFrameBackgroundTopRight", "CharacterModelFrameBackgroundBotRight",
        "CharacterModelFrameBackgroundOverlay",
    }
    for _, bgName in ipairs(modelBgs) do
        local bg = _G[bgName]
        if bg then bg:Hide() end
    end

    -- Hide model control frame (rotate/zoom buttons)
    if CharacterModelScene and CharacterModelScene.ControlFrame then
        CharacterModelScene.ControlFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- Create custom QUI background
---------------------------------------------------------------------------
local function CreateCustomBackground()
    local settings = GetSettings()

    -- Check if skinning module is handling the background
    local skinningAPI = _G.QUI_CharacterFrameSkinning
    if skinningAPI and skinningAPI.IsEnabled and skinningAPI.IsEnabled() then
        -- Use skinning module's background with extended dimensions
        if skinningAPI.SetExtended then
            skinningAPI.SetExtended(true)
        end
    else
        -- Skinning disabled - create our own background for character pane
        -- Use global skinning colors for consistency
        local QUI = _G.QUI
        local sr, sg, sb, sa = C.border[1], C.border[2], C.border[3], 1
        local bgr, bgg, bgb, bga = C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 0.95

        if QUI and QUI.GetSkinColor then
            sr, sg, sb, sa = QUI:GetSkinColor()
        end
        if QUI and QUI.GetSkinBgColor then
            bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
        end

        if not customBg then
            customBg = CreateFrame("Frame", "QUI_CharacterFrameBg_CharPane", CharacterFrame, "BackdropTemplate")
            local px = QUICore:GetPixelSize(customBg)
            customBg:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = px,
            })
            customBg:SetFrameStrata("BACKGROUND")
            customBg:SetFrameLevel(0)
            customBg:EnableMouse(false)
        end

        -- Extend background beyond CharacterFrame bounds (can't resize CharacterFrame directly)
        local PANEL_HEIGHT_EXTENSION = 50
        local PANEL_WIDTH_EXTENSION = 55
        customBg:ClearAllPoints()
        customBg:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
        customBg:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", PANEL_WIDTH_EXTENSION, -PANEL_HEIGHT_EXTENSION)

        -- Use global skinning background color
        customBg:SetBackdropColor(bgr, bgg, bgb, bga)
        customBg:SetBackdropBorderColor(sr, sg, sb, sa)
        customBg:Show()
    end

    -- Note: Model area uses customBg background (no separate modelBg needed)
    -- Creating a child frame of CharacterModelScene would render in front of the 3D model

    -- Apply panel scale from settings (base scale 1.30, slider is multiplier)
    local BASE_SCALE = 1.30
    local scaleMultiplier = settings.panelScale or 1.0
    SafeSetCharScale(BASE_SCALE * scaleMultiplier)
end

---------------------------------------------------------------------------
-- Slot column definitions for portrait layout
---------------------------------------------------------------------------
local LEFT_COLUMN_SLOTS = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterBackSlot",
    "CharacterChestSlot",
    "CharacterWristSlot",
}

local RIGHT_COLUMN_SLOTS = {
    "CharacterHandsSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
}

---------------------------------------------------------------------------
-- Reposition equipment slots into portrait layout
---------------------------------------------------------------------------
local function RepositionSlots()
    local settings = GetSettings()
    if not CharacterFrameBg then return end  -- Need this frame as anchor

    local vpad = 14  -- Vertical padding between slots
    local SLOT_SCALE = 0.90  -- Scale down slots to 90%

    -- All slots to scale
    local allSlots = {
        CharacterHeadSlot, CharacterNeckSlot, CharacterShoulderSlot,
        CharacterBackSlot, CharacterChestSlot, CharacterShirtSlot,
        CharacterTabardSlot, CharacterWristSlot,
        CharacterHandsSlot, CharacterWaistSlot, CharacterLegsSlot,
        CharacterFeetSlot, CharacterFinger0Slot, CharacterFinger1Slot,
        CharacterTrinket0Slot, CharacterTrinket1Slot,
        CharacterMainHandSlot, CharacterSecondaryHandSlot,
    }

    -- Apply scale to all slots
    for _, slot in ipairs(allSlots) do
        if slot then slot:SetScale(SLOT_SCALE) end
    end

    -- LEFT COLUMN: Head is anchor, others chain below
    CharacterHeadSlot:ClearAllPoints()
    CharacterHeadSlot:SetPoint("TOPLEFT", CharacterFrameBg, "TOPLEFT", 20, -30)

    CharacterNeckSlot:ClearAllPoints()
    CharacterNeckSlot:SetPoint("TOPLEFT", CharacterHeadSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterShoulderSlot:ClearAllPoints()
    CharacterShoulderSlot:SetPoint("TOPLEFT", CharacterNeckSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterBackSlot:ClearAllPoints()
    CharacterBackSlot:SetPoint("TOPLEFT", CharacterShoulderSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterChestSlot:ClearAllPoints()
    CharacterChestSlot:SetPoint("TOPLEFT", CharacterBackSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterShirtSlot:ClearAllPoints()
    CharacterShirtSlot:SetPoint("TOPLEFT", CharacterChestSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterTabardSlot:ClearAllPoints()
    CharacterTabardSlot:SetPoint("TOPLEFT", CharacterShirtSlot, "BOTTOMLEFT", 0, -vpad)

    -- RIGHT COLUMN: Hands is anchor, others chain below (closer to stats panel)
    CharacterHandsSlot:ClearAllPoints()
    CharacterHandsSlot:SetPoint("TOPLEFT", CharacterFrameBg, "TOPLEFT", 413, -30)

    CharacterWaistSlot:ClearAllPoints()
    CharacterWaistSlot:SetPoint("TOPLEFT", CharacterHandsSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterLegsSlot:ClearAllPoints()
    CharacterLegsSlot:SetPoint("TOPLEFT", CharacterWaistSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterFeetSlot:ClearAllPoints()
    CharacterFeetSlot:SetPoint("TOPLEFT", CharacterLegsSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterFinger0Slot:ClearAllPoints()
    CharacterFinger0Slot:SetPoint("TOPLEFT", CharacterFeetSlot, "BOTTOMLEFT", 0, -vpad)

    CharacterFinger1Slot:ClearAllPoints()
    CharacterFinger1Slot:SetPoint("TOPLEFT", CharacterFinger0Slot, "BOTTOMLEFT", 0, -vpad)

    CharacterTrinket0Slot:ClearAllPoints()
    CharacterTrinket0Slot:SetPoint("TOPLEFT", CharacterFinger1Slot, "BOTTOMLEFT", 0, -vpad)

    CharacterTrinket1Slot:ClearAllPoints()
    CharacterTrinket1Slot:SetPoint("TOPLEFT", CharacterTrinket0Slot, "BOTTOMLEFT", 0, -vpad)

    -- LEFT COLUMN BOTTOM: Wrist aligned horizontally with Trinket2
    CharacterWristSlot:ClearAllPoints()
    CharacterWristSlot:SetPoint("TOP", CharacterTrinket1Slot, "TOP", 0, 0)
    CharacterWristSlot:SetPoint("LEFT", CharacterHeadSlot, "LEFT", 0, 0)

    -- BOTTOM: Weapons centered between columns
    -- Panel extended by 50px, weapons moved 40px lower than before (yOffset: 21 + 50 - 40 = 31)
    CharacterMainHandSlot:ClearAllPoints()
    CharacterMainHandSlot:SetPoint("BOTTOM", CharacterFrameBg, "BOTTOM", -102, -29)

    CharacterSecondaryHandSlot:ClearAllPoints()
    CharacterSecondaryHandSlot:SetPoint("LEFT", CharacterMainHandSlot, "RIGHT", 30, 0)
end

---------------------------------------------------------------------------
-- Position CharacterModelScene
---------------------------------------------------------------------------
local function PositionModelScene()
    local settings = GetSettings()
    if not CharacterModelScene then return end

    -- Position model scene between slot columns
    CharacterModelScene:ClearAllPoints()
    CharacterModelScene:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 86, -85)
    CharacterModelScene:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -204, 65)
    CharacterModelScene:SetFrameLevel(2)
    CharacterModelScene:Show()

end

---------------------------------------------------------------------------
-- Position stats panel for portrait layout
---------------------------------------------------------------------------
local function PositionStatsPanelForLayout()
    local settings = GetSettings()

    -- Create stats panel if not exists
    local justCreated = false
    if not statsPanel then
        statsPanel = CreateStatsPanel(CharacterFrame, "player")
        justCreated = true
    end

    if statsPanel then
        statsPanel:ClearAllPoints()
        statsPanel:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", 42, -70)
        statsPanel:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", 42, -45)
        statsPanel:SetWidth(160)
        statsPanel:SetFrameLevel(10)
        statsPanel:Show()

        -- If just created, trigger ScheduleUpdate to populate content
        if justCreated then
            C_Timer.After(0.05, ScheduleUpdate)
        end
    end
end

---------------------------------------------------------------------------
-- Shared average ilvl accessor (overall / equipped / pvp)
---------------------------------------------------------------------------
local function GetPlayerAverageItemLevels()
    local overall, equipped, pvp = GetAverageItemLevel()
    overall = tonumber(overall) or 0
    equipped = tonumber(equipped) or overall
    pvp = tonumber(pvp)
    return overall, equipped, pvp
end

---------------------------------------------------------------------------
-- Hover tooltip for center ilvl display
---------------------------------------------------------------------------
local function ShowCenterILvlTooltip(self)
    if not self then return end

    local overall = tonumber(self.cachedOverallILvl)
    local equipped = tonumber(self.cachedEquippedILvl)
    local pvp = tonumber(self.cachedPvpILvl)

    if not overall or not equipped then
        overall, equipped, pvp = GetPlayerAverageItemLevels()
    end

    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText("Average Item Level")
    GameTooltip:AddDoubleLine("Equipped", string.format("%.1f", equipped), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Overall", string.format("%.1f", overall), 1, 1, 1, 1, 1, 1)
    if pvp then
        GameTooltip:AddDoubleLine("PvP iLvl", string.format("%.1f", pvp), 1, 1, 1, 0, 1, 0)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Setup title area: Top-left display with [Name] [ilvl] [Spec Class]
---------------------------------------------------------------------------
local function SetupTitleArea()
    local font = GetGlobalFont()

    -- Hide Blizzard's level text (we'll show our own combined display)
    if CharacterLevelText then
        CharacterLevelText:Hide()
    end

    -- Create top-left two-line display: Line 1 = Name, Line 2 = Level + Spec
    if not (frameState[CharacterFrame] or EMPTY).ilvlDisplay then
        local displayFrame = CreateFrame("Frame", nil, CharacterFrame)
        displayFrame:SetSize(400, 30)
        displayFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 19, -10)  -- Aligned with first slot
        displayFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 10)

        -- Line 1: Character name
        local nameText = displayFrame:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(font, 12, "")
        nameText:SetPoint("TOPLEFT", displayFrame, "TOPLEFT", 0, 0)
        nameText:SetJustifyH("LEFT")

        -- Line 2: Level + Spec (right-aligned near right icons)
        local specText = CharacterFrame:CreateFontString(nil, "OVERLAY")
        specText:SetFont(font, 12, "")
        specText:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -132, -10)  -- Aligned with right slot column
        specText:SetJustifyH("RIGHT")

        displayFrame.text = nameText
        displayFrame.specText = specText
        GetState(CharacterFrame).ilvlDisplay = displayFrame
    end

    -- Create center ilvl display (title bar) - shows equipped | overall
    if not (frameState[CharacterFrame] or EMPTY).centerILvl then
        local centerFrame = CreateFrame("Frame", nil, CharacterFrame)
        centerFrame:SetSize(200, 20)
        centerFrame:SetPoint("TOP", CharacterFrame, "TOP", -62, -10)  -- Title bar, shifted left over model
        centerFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 10)

        local centerText = centerFrame:CreateFontString(nil, "OVERLAY")
        centerText:SetFont(font, 21, "OUTLINE")  -- Large font
        centerText:SetPoint("CENTER")
        centerText:SetJustifyH("CENTER")

        centerFrame:EnableMouse(true)
        centerFrame:SetScript("OnEnter", ShowCenterILvlTooltip)
        centerFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        centerFrame.text = centerText
        GetState(CharacterFrame).centerILvl = centerFrame
    end
end

---------------------------------------------------------------------------
-- Master function: Apply portrait layout
---------------------------------------------------------------------------
local function ApplyCharacterPaneLayout()
    local settings = GetSettings()
    if not settings.enabled then return end

    -- Only apply once per session (unless forced)
    if layoutApplied then return end

    HideBlizzardDecorations()
    CreateCustomBackground()
    SetupTitleArea()
    -- Delay repositioning to allow Blizzard to finish slot setup first
    C_Timer.After(0.1, function()
        RepositionSlots()
        PositionModelScene()
        PositionStatsPanelForLayout()
    end)

    layoutApplied = true
end

---------------------------------------------------------------------------
-- Initialize slot overlays for character frame
---------------------------------------------------------------------------
local currentOverlayScale = nil

local function InitializeCharacterOverlays(forceRecreate)
    local settings = GetSettings()
    local newScale = 1.0

    -- Check if scale changed - need to recreate overlays
    if characterPaneInitialized and currentOverlayScale == newScale and not forceRecreate then
        return
    end

    -- If scale changed, destroy existing overlays
    if characterPaneInitialized and currentOverlayScale ~= newScale then
        for slotId, overlay in pairs(slotOverlays) do
            if overlay then
                overlay:Hide()
                overlay:SetParent(nil)
            end
        end
        slotOverlays = {}
        characterPaneInitialized = false
    end

    if characterPaneInitialized then return end

    for _, slotInfo in ipairs(EQUIPMENT_SLOTS) do
        local slotFrame = _G["Character" .. slotInfo.name .. "Slot"]
        if slotFrame then
            slotOverlays[slotInfo.id] = CreateSlotOverlay(slotFrame, slotInfo)
        end
    end

    currentOverlayScale = newScale
    characterPaneInitialized = true
end

---------------------------------------------------------------------------
-- Update all slot overlays
---------------------------------------------------------------------------
local function UpdateAllSlotOverlays(unit, overlayTable)
    overlayTable = overlayTable or slotOverlays
    unit = unit or "player"

    for _, overlay in pairs(overlayTable) do
        UpdateSlotOverlay(overlay, unit)
    end
end

---------------------------------------------------------------------------
-- Create stats panel (replaces CharacterFrameInsetRight)
---------------------------------------------------------------------------
CreateStatsPanel = function(parent, unit)
    local settings = GetSettings()

    -- Create main panel frame
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(200, 400)

    -- No backdrop - let customBg show through (avoids double-layered background)
    panel:SetBackdrop(nil)

    -- Plain ScrollFrame (no template). UIPanelScrollFrameTemplate inherits from
    -- SecureScrollFrameTemplate; addon-side geometry mods (SetSize on the child,
    -- SetWidth on the thumb, etc.) taint the secure template's xrange/yrange
    -- reads in 12.0+, producing "secret number value" errors. Plain ScrollFrames
    -- have no secure inheritance, so they're safe to size from addon code.
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        local new = math.max(0, math.min(maxScroll, current - delta * 20))
        self:SetVerticalScroll(new)
    end)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(130, 1)  -- Width matches scroll area (160 - 30 padding), height set dynamically
    scrollFrame:SetScrollChild(scrollChild)

    panel.scrollFrame = scrollFrame
    panel.scrollChild = scrollChild
    panel.unit = unit

    return panel
end

---------------------------------------------------------------------------
-- Track font strings and underlines for refresh
---------------------------------------------------------------------------
local trackedFontStrings = {}
local trackedUnderlines = {}
-- Note: trackedEnchantFonts is declared earlier (before CreateSlotOverlay)

local function TrackFontString(fontString, category)
    table.insert(trackedFontStrings, { fs = fontString, cat = category })
end

---------------------------------------------------------------------------
-- Refresh all character panel fonts
---------------------------------------------------------------------------
local function RefreshCharacterPanelFonts()
    local settings = GetSettings()
    local font = GetGlobalFont()

    -- Get pixel-based sizes (with fallback to old multiplier settings for migration)
    local statsSize = settings.statsTextSize or (settings.textSize and math.floor(11 * settings.textSize)) or 11
    local statsColor = settings.statsTextColor or settings.textColor or {0.953, 0.957, 0.965}
    local headerSize = settings.headerTextSize or (settings.headerSize and math.floor(12 * settings.headerSize)) or 12

    -- Header color: use class color if enabled, otherwise use custom color
    local headerColor
    if settings.headerClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            headerColor = {classColor.r, classColor.g, classColor.b}
        else
            headerColor = settings.headerColor or {0.376, 0.647, 0.980}
        end
    else
        headerColor = settings.headerColor or {0.376, 0.647, 0.980}
    end

    -- Clean up invalid references
    local validStrings = {}
    for _, entry in ipairs(trackedFontStrings) do
        if entry.fs and entry.fs.SetFont then
            table.insert(validStrings, entry)
        end
    end
    trackedFontStrings = validStrings

    -- Update all tracked font strings
    for _, entry in ipairs(trackedFontStrings) do
        local fs = entry.fs
        local cat = entry.cat

        if cat == "sectionHeader" then
            fs:SetFont(font, math.max(headerSize - 2, 10), "THINOUTLINE")
            fs:SetTextColor(headerColor[1], headerColor[2], headerColor[3], 1)
            fs:SetShadowOffset(0, 0)
            fs:SetText(fs:GetText() or "")
        elseif cat == "statLabel" or cat == "barLabel" then
            local size = (cat == "barLabel") and math.max(statsSize - 2, 7) or math.max(statsSize - 1, 8)
            fs:SetFont(font, size, "")
            fs:SetTextColor(statsColor[1], statsColor[2], statsColor[3], 1)
            fs:SetShadowOffset(0, 0)
        elseif cat == "statValue" or cat == "barValue" then
            local size = (cat == "barValue") and math.max(statsSize - 2, 7) or math.max(statsSize - 1, 8)
            fs:SetFont(font, size, "")
            fs:SetShadowOffset(0, 0)
        end
    end

    -- Update section header underlines with header color
    if trackedUnderlines then
        for _, line in ipairs(trackedUnderlines) do
            if line and line.SetColorTexture then
                line:SetColorTexture(headerColor[1], headerColor[2], headerColor[3], 0.3)
            end
        end
    end

    -- Update enchant text (slot overlays)
    local enchantSize = settings.enchantTextSize or 10
    local noEnchantColor = settings.noEnchantTextColor or {0.5, 0.5, 0.5}

    -- Enchant color: use class color if enabled, otherwise use custom color
    local enchantColor
    if settings.enchantClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            enchantColor = {classColor.r, classColor.g, classColor.b}
        else
            enchantColor = settings.enchantTextColor or {0.376, 0.647, 0.980}
        end
    else
        enchantColor = settings.enchantTextColor or {0.376, 0.647, 0.980}
    end

    -- Enchant font: use custom font if specified, otherwise global font
    local enchantFont = font
    if settings.enchantFont then
        local LSM = ns.LSM
        if LSM then
            local fontPath = LSM:Fetch("font", settings.enchantFont)
            if fontPath then
                enchantFont = fontPath
            end
        end
    end

    -- Unified slot text size for all 3 lines (same font, size, and outline)
    local slotTextSize = settings.slotTextSize or 10
    local FONT_FLAGS = "OUTLINE"  -- Thin black outline for readability

    -- Update item name text (Line 1)
    local validItemNames = {}
    for _, fs in ipairs(trackedItemNameFonts) do
        if fs and fs.SetFont then
            fs:SetFont(font, slotTextSize, FONT_FLAGS)
            table.insert(validItemNames, fs)
        end
    end
    trackedItemNameFonts = validItemNames

    -- Update item level text (Line 2)
    local validILvl = {}
    for _, fs in ipairs(trackedILvlFonts) do
        if fs and fs.SetFont then
            fs:SetFont(font, slotTextSize, FONT_FLAGS)
            table.insert(validILvl, fs)
        end
    end
    trackedILvlFonts = validILvl

    -- Update enchant text (Line 3) - use same font as other lines for consistency
    local validEnchants = {}
    for _, fs in ipairs(trackedEnchantFonts) do
        if fs and fs.SetFont then
            fs:SetFont(font, slotTextSize, FONT_FLAGS)
            -- Color based on text content
            local text = fs:GetText()
            if text and text == "No Enchant" then
                fs:SetTextColor(noEnchantColor[1], noEnchantColor[2], noEnchantColor[3], 1)
            elseif text then
                fs:SetTextColor(enchantColor[1], enchantColor[2], enchantColor[3], 1)
            end
            table.insert(validEnchants, fs)
        end
    end
    trackedEnchantFonts = validEnchants
end

-- Expose globally for settings panel
_G.QUI_RefreshCharacterPanelFonts = RefreshCharacterPanelFonts

---------------------------------------------------------------------------
-- Show stat tooltip (similar to Blizzard's PaperDollStatTooltip)
---------------------------------------------------------------------------
local function ShowStatTooltip(self)
    local settings = GetSettings()
    if not settings.showTooltips then
        return
    end
    if not self.tooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltip)
    if self.tooltip2 then
        GameTooltip:AddLine(self.tooltip2, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    end
    if self.tooltip3 then
        GameTooltip:AddLine(self.tooltip3, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Create a stat row (label + value)
---------------------------------------------------------------------------
local function CreateStatRow(parent, yOffset)
    local settings = GetSettings()
    local font = GetGlobalFont()
    local statsSize = settings.statsTextSize or 11
    local statsColor = settings.statsTextColor or {0.953, 0.957, 0.965}
    local rowHeight = 14
    local fontSize = math.max(statsSize - 1, 8)

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - 10, rowHeight)
    row:SetPoint("TOPLEFT", 5, yOffset)

    -- Enable mouse for tooltips (only if setting is enabled)
    if settings.showTooltips then
        row:EnableMouse(true)
        row:SetScript("OnEnter", ShowStatTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        row:EnableMouse(false)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
    end

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFont(font, fontSize, "")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetTextColor(statsColor[1], statsColor[2], statsColor[3], 1)
    row.label:SetShadowOffset(0, 0)
    TrackFontString(row.label, "statLabel")

    row.value = row:CreateFontString(nil, "OVERLAY")
    row.value:SetFont(font, fontSize, "")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetTextColor(1, 1, 1, 1)
    row.value:SetShadowOffset(0, 0)
    TrackFontString(row.value, "statValue")

    return row
end

---------------------------------------------------------------------------
-- Create a section header
---------------------------------------------------------------------------
local function CreateSectionHeader(parent, text, yOffset)
    local settings = GetSettings()
    local font = GetGlobalFont()
    local headerSize = settings.headerTextSize or 12
    local fontSize = math.max(headerSize - 2, 10)
    local headerHeight = 14
    -- Compute header color respecting class color toggle
    local headerColor
    if settings.headerClassColor then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            headerColor = {classColor.r, classColor.g, classColor.b}
        else
            headerColor = settings.headerColor or {0.376, 0.647, 0.980}
        end
    else
        headerColor = settings.headerColor or {0.376, 0.647, 0.980}
    end

    local header = parent:CreateFontString(nil, "OVERLAY")
    header:SetFont(font, fontSize, "THINOUTLINE")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
    header:SetTextColor(headerColor[1], headerColor[2], headerColor[3], 1)
    header:SetText(text)
    header:SetShadowOffset(0, 0)
    TrackFontString(header, "sectionHeader")

    -- Underline (uses headerColor)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -5, 0)
    line:SetColorTexture(headerColor[1], headerColor[2], headerColor[3], 0.3)
    table.insert(trackedUnderlines, line)

    local spacingAfterHeader = 4
    return header, headerHeight + spacingAfterHeader
end

---------------------------------------------------------------------------
-- Create a stat bar (for secondary stats)
---------------------------------------------------------------------------
local function CreateStatBar(parent, yOffset, color)
    local settings = GetSettings()
    local font = GetGlobalFont()
    local statsSize = settings.statsTextSize or 11
    local statsColor = settings.statsTextColor or {0.953, 0.957, 0.965}
    local barTextSize = math.max(statsSize - 2, 7)
    local rowHeight = 16
    local barHeight = 3
    local labelOffset = 2
    local barOffset = 1

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth() - 10, rowHeight)
    row:SetPoint("TOPLEFT", 5, yOffset)

    -- Enable mouse for tooltips (only if setting is enabled)
    if settings.showTooltips then
        row:EnableMouse(true)
        row:SetScript("OnEnter", ShowStatTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        row:EnableMouse(false)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
    end

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFont(font, barTextSize, "")
    row.label:SetPoint("LEFT", row, "LEFT", 0, labelOffset)
    row.label:SetTextColor(statsColor[1], statsColor[2], statsColor[3], 1)
    row.label:SetShadowOffset(0, 0)
    TrackFontString(row.label, "barLabel")

    row.value = row:CreateFontString(nil, "OVERLAY")
    row.value:SetFont(font, barTextSize, "")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, labelOffset)
    row.value:SetTextColor(1, 1, 1, 1)
    row.value:SetShadowOffset(0, 0)
    TrackFontString(row.value, "barValue")

    -- Progress bar
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetSize(row:GetWidth(), barHeight)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, barOffset)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, barOffset)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetMinMaxValues(0, 100)
    row.bar:SetStatusBarColor(color[1], color[2], color[3], color[4])

    -- Bar background
    local barBg = row.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.4)

    return row
end

---------------------------------------------------------------------------
-- Finalize stats panel layout after rows are populated
---------------------------------------------------------------------------
local function FinalizeStatsPanelLayout(panel, scrollChild, yOffset)
    -- Set scroll child height
    local contentHeight = math.abs(yOffset) + 20
    scrollChild:SetHeight(contentHeight)

    -- Scale the stats panel to fit without scrollbar
    panel:SetScale(0.92)

    -- Reset scroll position when content fits in viewport. No scrollbar to
    -- show/hide (the plain ScrollFrame has none — wheel-only scrolling).
    local scrollFrame = panel.scrollFrame
    if scrollFrame then
        C_Timer.After(0.01, function()
            local okScroll, maxScroll = pcall(scrollFrame.GetVerticalScrollRange, scrollFrame)
            if okScroll and not Helpers.IsSecretValue(maxScroll) then
                if Helpers.SafeToNumber(maxScroll, 0) <= 1 then
                    scrollFrame:SetVerticalScroll(0)
                end
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Native CharacterStatsPane mirror: when secret values prevent us from
-- reading stat APIs from addon code, mirror Blizzard's already-formatted
-- FontString text (built in unrestricted code, so the strings are safe to
-- copy via SetText) into our curated rows.
---------------------------------------------------------------------------

-- Ensures Blizzard's CharacterStatsPane stays visually masked but Shown so
-- its unrestricted update path keeps writing fresh values into its
-- FontStrings — which we then mirror.
local function MaskNativeStatsPane()
    if not CharacterStatsPane then return end
    -- Show explicitly: if anything (skinning, our own past hide path, Blizzard
    -- tab transitions) left the pane :Hide()'d, its update path won't run and
    -- our mirror reads stale text. Keep it Shown but visually invisible.
    pcall(CharacterStatsPane.Show, CharacterStatsPane)
    pcall(CharacterStatsPane.SetAlpha, CharacterStatsPane, 0)
    if CharacterStatsPane.EnableMouse then
        pcall(CharacterStatsPane.EnableMouse, CharacterStatsPane, false)
    end
    if CharacterStatsPane.ClassBackground then
        pcall(CharacterStatsPane.ClassBackground.SetAlpha, CharacterStatsPane.ClassBackground, 0)
    end
end

---------------------------------------------------------------------------
-- Update stats panel content
---------------------------------------------------------------------------
local function UpdateStatsPanel(panel, unit)
    if not panel or not panel.scrollChild then return end

    if InCombatLockdown() then
        pendingStatsPanelRefresh = true
    end

    if updatingStatsPanel then return end
    updatingStatsPanel = true

    local success, err = pcall(function()
        local settings = GetSettings()
        MaskNativeStatsPane()
        panel:Show()

        local scrollChild = panel.scrollChild
        unit = unit or panel.unit or "player"

        -- First, hide all tracked FontStrings (headers, labels, values)
        for _, entry in ipairs(trackedFontStrings) do
            if entry.fs and entry.fs.Hide then
                entry.fs:Hide()
                entry.fs:SetText("")
            end
        end

        -- Hide all tracked underlines (Textures)
        for _, line in ipairs(trackedUnderlines) do
            if line and line.Hide then
                line:Hide()
            end
        end

        -- Clear the tracking tables
        wipe(trackedFontStrings)
        wipe(trackedUnderlines)

        -- Clear child frames (stat rows, stat bars)
        local children = {scrollChild:GetChildren()}
        for i = #children, 1, -1 do
            local frame = children[i]
            if frame then
                frame:Hide()
                frame:SetParent(nil)
                if frame.SetScript then
                    frame:SetScript("OnShow", nil)
                    frame:SetScript("OnHide", nil)
                    frame:SetScript("OnUpdate", nil)
                end
            end
        end

        -- Also clear any remaining regions (FontStrings, Textures) on scrollChild
        local regions = {scrollChild:GetRegions()}
        for i = #regions, 1, -1 do
            local region = regions[i]
            if region then
                region:Hide()
                if region.SetText then
                    region:SetText("")
                end
            end
        end

        local y = -5
        local ROW_HEIGHT = 14
        local SECTION_GAP = 8
        local BAR_HEIGHT = 16

        -- Helper to safely get stats (pcall for Midnight protection)
        local function SafeGetStat(func, ...)
            if type(func) ~= "function" then
                return 0
            end
            local ok, result = pcall(func, ...)
            if not ok then
                return 0
            end
            return Helpers.SafeToNumber(result, 0)
        end

        local function SafeGetStatValues(func, ...)
            if type(func) ~= "function" then
                return 0, 0, 0, 0
            end

            local ok, a, b, c, d = pcall(func, ...)
            if not ok then
                return 0, 0, 0, 0
            end

            return Helpers.SafeToNumber(a, 0),
                   Helpers.SafeToNumber(b, 0),
                   Helpers.SafeToNumber(c, 0),
                   Helpers.SafeToNumber(d, 0)
        end

        -- Returns the raw value (secret-checked) or nil if unavailable. Used
        -- by freeze rows that need to distinguish "real zero" from "secret".
        local function GetStatOrNil(func, ...)
            if type(func) ~= "function" then return nil end
            local ok, result = pcall(func, ...)
            if not ok or Helpers.IsSecretValue(result) then return nil end
            return result
        end

        -- Combat / encounter / M+ / PvP gate. When true, we cannot do Lua
        -- arithmetic on API returns (they're secret-tainted); rich tooltips
        -- and value-derived calculations are skipped. Direct API +
        -- SetFormattedText still renders live values via the C-side printf.
        local secretsOff = (unit == "player") and AreCharacterStatsSecretsDisabled() or false

        -- HEALTH & RESOURCE
        local row = CreateStatRow(scrollChild, y)
        row.label:SetText("Health")
        do
            local hOk, healthMax = pcall(UnitHealthMax, unit)
            if hOk and healthMax then
                row.value:SetFormattedText("%s", healthMax)
            end
        end
        row.value:SetTextColor(C.health[1], C.health[2], C.health[3], 1)
        row.tooltip = HEALTH
        row.tooltip2 = (unit == "player") and STAT_HEALTH_TOOLTIP or STAT_HEALTH_PET_TOOLTIP
        if not secretsOff then
            local healthMaxRaw = GetStatOrNil(UnitHealthMax, unit)
            if healthMaxRaw then
                row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, HEALTH).." "..BreakUpLargeNumbers(healthMaxRaw)..FONT_COLOR_CODE_CLOSE
            end
        end
        y = y - ROW_HEIGHT

        local powerType, powerToken = UnitPowerType(unit)
        local powerName = _G[powerToken] or (powerToken and powerToken:gsub("_", " "):lower():gsub("(%a)([%w]*)", function(a, b) return a:upper()..b end)) or "Power"

        row = CreateStatRow(scrollChild, y)
        row.label:SetText(powerName)
        do
            local pOk, powerMax = pcall(UnitPowerMax, unit, powerType)
            if pOk and powerMax then
                row.value:SetFormattedText("%s", powerMax)
            end
        end
        row.value:SetTextColor(C.mana[1], C.mana[2], C.mana[3], 1)
        row.tooltip = _G[powerToken] or powerName
        row.tooltip2 = _G["STAT_"..powerToken.."_TOOLTIP"]
        if not secretsOff then
            local powerMaxRaw = GetStatOrNil(UnitPowerMax, unit, powerType)
            if powerMaxRaw then
                row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, row.tooltip).." "..BreakUpLargeNumbers(powerMaxRaw)..FONT_COLOR_CODE_CLOSE
            end
        end
        y = y - ROW_HEIGHT

        y = y - 5

        -- ATTRIBUTES
        local _, headerHeight = CreateSectionHeader(scrollChild, "Attributes", y)
        y = y - headerHeight

        -- Primary stats vary by class, but we show all and let WoW hide irrelevant ones
        local stats = {
            { label = "Strength", statIndex = 1, func = function() return UnitStat(unit, 1) end },
            { label = "Agility", statIndex = 2, func = function() return UnitStat(unit, 2) end },
            { label = "Stamina", statIndex = 3, func = function() return UnitStat(unit, 3) end },
            { label = "Intellect", statIndex = 4, func = function() return UnitStat(unit, 4) end },
        }
        -- Pull spec primary stat once via non-secret API for visibility filter.
        local specPrimaryStat
        if unit == "player" and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
            local sp = C_SpecializationInfo.GetSpecialization()
            if sp and C_SpecializationInfo.GetSpecializationInfo then
                local okSI, _, _, _, _, _, primary = pcall(C_SpecializationInfo.GetSpecializationInfo, sp, false, false, nil, UnitSex(unit))
                if okSI then specPrimaryStat = primary end
            end
        end

        for _, stat in ipairs(stats) do
            local statValue, effectiveStat, posBuff, negBuff = SafeGetStatValues(UnitStat, unit, stat.statIndex)

            -- Visibility filter:
            --   OOC: render only when value > 0 (Blizzard hides irrelevant attrs)
            --   Combat: render Stamina + spec primary stat (non-secret signals).
            --     If spec primary is unknown, fall back to all 4.
            local shouldShow
            if secretsOff then
                shouldShow = stat.statIndex == 3
                    or (specPrimaryStat and specPrimaryStat == stat.statIndex)
                    or (not specPrimaryStat)
            else
                shouldShow = effectiveStat and effectiveStat > 0
            end

            if shouldShow then
                row = CreateStatRow(scrollChild, y)
                row.label:SetText(stat.label)

                -- Direct API → SetFormattedText. UnitStat returns 5 values;
                -- the 2nd is the effective stat we display.
                local uOk, _, eff = pcall(UnitStat, unit, stat.statIndex)
                if uOk and eff then
                    row.value:SetFormattedText("%s", eff)
                end

                -- Static lore tooltip (works in combat)
                row.tooltip = _G["SPELL_STAT"..stat.statIndex.."_NAME"] or stat.label
                row.tooltip2 = _G["DEFAULT_STAT"..stat.statIndex.."_TOOLTIP"]

                if not secretsOff then
                    -- Set tooltip (Blizzard format)
                    local statName = _G["SPELL_STAT"..stat.statIndex.."_NAME"]
                    local tooltipText = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, statName).." "
                    local effectiveStatDisplay = BreakUpLargeNumbers(effectiveStat)

                    if (posBuff == 0) and (negBuff == 0) then
                        row.tooltip = tooltipText..effectiveStatDisplay..FONT_COLOR_CODE_CLOSE
                    else
                        tooltipText = tooltipText..effectiveStatDisplay
                        if (posBuff > 0 or negBuff < 0) then
                            tooltipText = tooltipText.." ("..BreakUpLargeNumbers(statValue - posBuff - negBuff)..FONT_COLOR_CODE_CLOSE
                        end
                        if (posBuff > 0) then
                            tooltipText = tooltipText..FONT_COLOR_CODE_CLOSE..GREEN_FONT_COLOR_CODE.."+"..BreakUpLargeNumbers(posBuff)..FONT_COLOR_CODE_CLOSE
                        end
                        if (negBuff < 0) then
                            tooltipText = tooltipText..RED_FONT_COLOR_CODE.." "..BreakUpLargeNumbers(negBuff)..FONT_COLOR_CODE_CLOSE
                        end
                        if (posBuff > 0 or negBuff < 0) then
                            tooltipText = tooltipText..HIGHLIGHT_FONT_COLOR_CODE..")"..FONT_COLOR_CODE_CLOSE
                        end
                        row.tooltip = tooltipText
                    end

                    row.tooltip2 = _G["DEFAULT_STAT"..stat.statIndex.."_TOOLTIP"]

                    -- Add class-specific tooltip info (similar to Blizzard's PaperDollFrame_SetStat)
                    if unit == "player" then
                        local _success, _result = pcall(function()
                            local _, unitClass = UnitClass("player")
                            unitClass = strupper(unitClass)
                            local primaryStat, spec, role
                            spec = C_SpecializationInfo.GetSpecialization()
                            if spec then
                                role = GetSpecializationRole(spec)
                                primaryStat = select(6, C_SpecializationInfo.GetSpecializationInfo(spec, false, false, nil, UnitSex("player")))
                            end

                            if stat.statIndex == 1 then -- Strength
                                if GetAttackPowerForStat then
                                    local attackPower = GetAttackPowerForStat(1, effectiveStat)
                                    if HasAPEffectsSpellPower and HasAPEffectsSpellPower() then
                                        row.tooltip2 = STAT_TOOLTIP_BONUS_AP_SP
                                    end
                                    if (not primaryStat or primaryStat == 1) then
                                        row.tooltip2 = format(row.tooltip2 or STAT_TOOLTIP_BONUS_AP, BreakUpLargeNumbers(attackPower))
                                        if role == "TANK" and GetParryChanceFromAttribute then
                                            local increasedParryChance = GetParryChanceFromAttribute()
                                            if increasedParryChance and increasedParryChance > 0 then
                                                row.tooltip2 = row.tooltip2.."|n|n"..format(CR_PARRY_BASE_STAT_TOOLTIP, increasedParryChance)
                                            end
                                        end
                                    else
                                        row.tooltip2 = STAT_NO_BENEFIT_TOOLTIP
                                    end
                                end
                            elseif stat.statIndex == 2 then -- Agility
                                if (not primaryStat or primaryStat == 2) then
                                    if HasAPEffectsSpellPower and HasAPEffectsSpellPower() then
                                        row.tooltip2 = STAT_TOOLTIP_BONUS_AP_SP
                                    else
                                        row.tooltip2 = STAT_TOOLTIP_BONUS_AP
                                    end
                                    if role == "TANK" and GetDodgeChanceFromAttribute then
                                        local increasedDodgeChance = GetDodgeChanceFromAttribute()
                                        if increasedDodgeChance and increasedDodgeChance > 0 then
                                            row.tooltip2 = row.tooltip2.."|n|n"..format(CR_DODGE_BASE_STAT_TOOLTIP, increasedDodgeChance)
                                        end
                                    end
                                else
                                    row.tooltip2 = STAT_NO_BENEFIT_TOOLTIP
                                end
                            elseif stat.statIndex == 3 then -- Stamina
                                if UnitHPPerStamina and GetUnitMaxHealthModifier then
                                    row.tooltip2 = format(row.tooltip2, BreakUpLargeNumbers(((effectiveStat*UnitHPPerStamina("player")))*GetUnitMaxHealthModifier("player")))
                                end
                            elseif stat.statIndex == 4 then -- Intellect
                                if HasAPEffectsSpellPower and HasAPEffectsSpellPower() then
                                    row.tooltip2 = STAT_NO_BENEFIT_TOOLTIP
                                elseif HasSPEffectsAttackPower and HasSPEffectsAttackPower() then
                                    row.tooltip2 = STAT_TOOLTIP_BONUS_AP_SP
                                elseif (not primaryStat or primaryStat == 4) then
                                    row.tooltip2 = format(row.tooltip2, max(0, effectiveStat))
                                else
                                    row.tooltip2 = STAT_NO_BENEFIT_TOOLTIP
                                end
                            end
                        end)
                        -- If pcall failed, keep the default tooltip2
                    end
                end

                y = y - ROW_HEIGHT
            end
        end

        y = y - 5

    -- SECONDARY STATS
    _, headerHeight = CreateSectionHeader(scrollChild, "Secondary", y)
    y = y - headerHeight

    local secondaryStats = {
        { label = "Crit", statKey = "CRIT", percentFunc = function() return GetSpellCritChance("player") end, ratingFunc = function() return GetCombatRating(CR_CRIT_SPELL) end, color = C.crit },
        { label = "Haste", statKey = "HASTE", percentFunc = function() return UnitSpellHaste("player") end, ratingFunc = function() return GetCombatRating(CR_HASTE_SPELL) end, color = C.haste },
        { label = "Mastery", statKey = "MASTERY", percentFunc = GetMasteryEffect, ratingFunc = function() return GetCombatRating(CR_MASTERY) end, color = C.mastery },
        { label = "Versatility", statKey = "VERSATILITY", percentFunc = function() return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) end, ratingFunc = function() return GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) end, color = C.versatility },
    }

    local statFormat = settings.secondaryStatFormat or "percent"

    for _, stat in ipairs(secondaryStats) do
        row = CreateStatBar(scrollChild, y, stat.color)
        row.label:SetText(stat.label)

        -- Direct API + C-side SetFormattedText. Secret values pass through
        -- to the C printf without ever entering Lua arithmetic, so this
        -- works the same in combat / encounters / M+ / PvP as it does OOC.
        local pctOk, pct = pcall(stat.percentFunc)
        local ratingOk, rating = pcall(stat.ratingFunc)
        if statFormat == "percent" then
            if pctOk and pct then row.value:SetFormattedText("%.2f%%", pct) end
        elseif statFormat == "rating" then
            if ratingOk and rating then row.value:SetFormattedText("%s", rating) end
        else  -- "both"
            if pctOk and ratingOk and pct and rating then
                row.value:SetFormattedText("%s (%.2f%%)", rating, pct)
            elseif pctOk and pct then
                row.value:SetFormattedText("%.2f%%", pct)
            end
        end

        -- Bar fill: SetValue is C-side and accepts secret numbers, but it
        -- silently clamps to whatever the bar's max is. Forward directly
        -- without comparison — out of range just clips harmlessly.
        if pctOk and pct then
            pcall(row.bar.SetValue, row.bar, pct)
        end

        -- Static lore tooltip works in combat (no API math). Rich tooltip
        -- with live numbers / deltas only when secret-free.
        row.tooltip = stat.label
        if stat.statKey == "CRIT" then
            row.tooltip2 = STAT_CRITICAL_STRIKE_TOOLTIP
        elseif stat.statKey == "HASTE" then
            local _, class = UnitClass(unit)
            row.tooltip2 = _G["STAT_HASTE_"..class.."_TOOLTIP"] or STAT_HASTE_TOOLTIP
        elseif stat.statKey == "MASTERY" then
            row.tooltip2 = STAT_MASTERY_TOOLTIP
        elseif stat.statKey == "VERSATILITY" then
            row.tooltip2 = STAT_VERSATILITY_TOOLTIP
        end

        if not secretsOff then
            -- Rich tooltips read live values via Lua arithmetic — only safe OOC.
            local percentValue = SafeGetStat(stat.percentFunc)
            local ratingValue = SafeGetStat(stat.ratingFunc)
            if stat.statKey == "CRIT" then
                local extraCritChance = SafeGetStat(GetCombatRatingBonus, CR_CRIT_SPELL)
                local extraCritRating = SafeGetStat(GetCombatRating, CR_CRIT_SPELL)
                row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_CRITICAL_STRIKE)..FONT_COLOR_CODE_CLOSE
                if GetCritChanceProvidesParryEffect and GetCritChanceProvidesParryEffect() and GetCombatRatingBonusForCombatRatingValue then
                    local critParryBonus = SafeGetStat(GetCombatRatingBonusForCombatRatingValue, CR_PARRY, extraCritRating)
                    row.tooltip2 = format(CR_CRIT_PARRY_RATING_TOOLTIP, BreakUpLargeNumbers(extraCritRating), extraCritChance, critParryBonus)
                        .. "\n\n" .. format(CR_CRIT_TOOLTIP, BreakUpLargeNumbers(extraCritRating), extraCritChance)
                else
                    row.tooltip2 = format(CR_CRIT_TOOLTIP, BreakUpLargeNumbers(extraCritRating), extraCritChance)
                end
            elseif stat.statKey == "HASTE" then
                local _, class = UnitClass(unit)
                local hasteRating = SafeGetStat(GetCombatRating, CR_HASTE_SPELL)
                local hasteBonus = SafeGetStat(GetCombatRatingBonus, CR_HASTE_SPELL)
                row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_HASTE)..FONT_COLOR_CODE_CLOSE
                row.tooltip2 = _G["STAT_HASTE_"..class.."_TOOLTIP"] or STAT_HASTE_TOOLTIP
                row.tooltip2 = row.tooltip2 .. format(STAT_HASTE_BASE_TOOLTIP, BreakUpLargeNumbers(hasteRating), hasteBonus)
            elseif stat.statKey == "MASTERY" then
                local mastery, bonusCoeff = SafeGetStatValues(GetMasteryEffect)
                local masteryRating = SafeGetStat(GetCombatRating, CR_MASTERY)
                local masteryBonus = SafeGetStat(GetCombatRatingBonus, CR_MASTERY) * (bonusCoeff or 1)
                local primaryTalentTree = GetSpecialization and GetSpecialization()
                row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_MASTERY)..FONT_COLOR_CODE_CLOSE
                local spellDesc = ""
                if primaryTalentTree and GetSpecializationMasterySpells then
                    local masterySpell, masterySpell2 = GetSpecializationMasterySpells(primaryTalentTree)
                    if masterySpell and C_Spell and C_Spell.GetSpellDescription then
                        spellDesc = C_Spell.GetSpellDescription(masterySpell) or ""
                    end
                    if masterySpell2 and C_Spell and C_Spell.GetSpellDescription then
                        local desc2 = C_Spell.GetSpellDescription(masterySpell2)
                        if desc2 and desc2 ~= "" then
                            spellDesc = spellDesc .. "\n" .. desc2
                        end
                    end
                end
                local ratingText
                if STAT_MASTERY_TOOLTIP then
                    local ok, result = pcall(format, STAT_MASTERY_TOOLTIP, BreakUpLargeNumbers(masteryRating), masteryBonus)
                    if ok then ratingText = result end
                end
                if not ratingText then
                    ratingText = format("Your %s Mastery rating adds an additional %.2F%% mastery.", BreakUpLargeNumbers(masteryRating), masteryBonus)
                end
                if spellDesc ~= "" then
                    row.tooltip2 = spellDesc .. "\n\n" .. ratingText
                else
                    row.tooltip2 = ratingText
                end
            elseif stat.statKey == "VERSATILITY" then
                local versatility = SafeGetStat(GetCombatRating, CR_VERSATILITY_DAMAGE_DONE)
                local versatilityDamageBonus = SafeGetStat(GetCombatRatingBonus, CR_VERSATILITY_DAMAGE_DONE) + SafeGetStat(GetVersatilityBonus, CR_VERSATILITY_DAMAGE_DONE)
                local versatilityDamageTakenReduction = SafeGetStat(GetCombatRatingBonus, CR_VERSATILITY_DAMAGE_TAKEN) + SafeGetStat(GetVersatilityBonus, CR_VERSATILITY_DAMAGE_TAKEN)
                row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_VERSATILITY)..FONT_COLOR_CODE_CLOSE
                row.tooltip2 = format(CR_VERSATILITY_TOOLTIP, versatilityDamageBonus, versatilityDamageTakenReduction, BreakUpLargeNumbers(versatility), versatilityDamageBonus, versatilityDamageTakenReduction)
            end
        end
        
        y = y - BAR_HEIGHT
    end

    y = y - 5

    -- TERTIARY
    _, headerHeight = CreateSectionHeader(scrollChild, "Tertiary", y)
    y = y - headerHeight

    local leech = SafeGetStat(GetLifesteal)
    local speed = SafeGetStat(GetSpeed)
    local avoidance = 0
    if GetAvoidance then
        avoidance = SafeGetStat(GetAvoidance)
    elseif GetCombatRatingBonus and CR_AVOIDANCE then
        avoidance = SafeGetStat(GetCombatRatingBonus, CR_AVOIDANCE)
    end

    local tertiaryStats = {
        { label = "Avoidance", value = FormatPercent(avoidance), statKey = "AVOIDANCE" },
        { label = "Leech", value = FormatPercent(leech), statKey = "LIFESTEAL" },
        { label = "Speed", value = FormatPercent(speed), statKey = "SPEED" },
    }

    for _, stat in ipairs(tertiaryStats) do
        -- Tertiary rows are gear-dependent. OOC, hide when zero. In combat
        -- we always render — can't compare secrets, and showing 0% briefly
        -- is preferable to a row appearing/disappearing on combat boundary.
        local hasOocValue = (stat.label == "Avoidance" and avoidance > 0)
            or (stat.label == "Leech" and leech > 0)
            or (stat.label == "Speed" and speed > 0)
        local shouldShow = secretsOff or hasOocValue
        if shouldShow then
            row = CreateStatRow(scrollChild, y)
            row.label:SetText(stat.label)

            -- Direct API → SetFormattedText. Pulls live values whether
            -- secret or not — C-side printf forwards them transparently.
            local valueFn
            if stat.statKey == "AVOIDANCE" and GetAvoidance then
                valueFn = GetAvoidance
            elseif stat.statKey == "AVOIDANCE" then
                valueFn = function() return GetCombatRatingBonus(CR_AVOIDANCE) end
            elseif stat.statKey == "LIFESTEAL" then
                valueFn = GetLifesteal
            elseif stat.statKey == "SPEED" then
                valueFn = GetSpeed
            end
            if valueFn then
                local vOk, v = pcall(valueFn)
                if vOk and v then row.value:SetFormattedText("%.2f%%", v) end
            end

            -- Static lore tooltip
            if stat.statKey == "AVOIDANCE" then
                row.tooltip = _G.STAT_AVOIDANCE or "Avoidance"
                row.tooltip2 = _G.CR_AVOIDANCE_TOOLTIP_BASE or "Reduces damage taken from area effects."
            elseif stat.statKey == "LIFESTEAL" then
                row.tooltip = STAT_LIFESTEAL
                row.tooltip2 = _G.STAT_LIFESTEAL_TOOLTIP or _G.CR_LIFESTEAL_TOOLTIP
            elseif stat.statKey == "SPEED" then
                row.tooltip = STAT_SPEED
                row.tooltip2 = _G.STAT_SPEED_TOOLTIP or _G.CR_SPEED_TOOLTIP
            end

            if not secretsOff then
                -- Set tooltips (Blizzard format)
                if stat.statKey == "AVOIDANCE" then
                    local avoidanceValue = 0
                    if GetAvoidance then
                        avoidanceValue = SafeGetStat(GetAvoidance)
                    elseif GetCombatRatingBonus and CR_AVOIDANCE then
                        avoidanceValue = SafeGetStat(GetCombatRatingBonus, CR_AVOIDANCE)
                    end

                    local avoidanceLabel = _G.STAT_AVOIDANCE or "Avoidance"
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, avoidanceLabel) .. " " .. format("%.2F%%", avoidanceValue) .. FONT_COLOR_CODE_CLOSE

                    local avoidanceRating = (GetCombatRating and CR_AVOIDANCE) and SafeGetStat(GetCombatRating, CR_AVOIDANCE) or 0
                    local avoidanceBonus = (GetCombatRatingBonus and CR_AVOIDANCE) and SafeGetStat(GetCombatRatingBonus, CR_AVOIDANCE) or avoidanceValue
                    if _G.CR_AVOIDANCE_TOOLTIP then
                        row.tooltip2 = format(CR_AVOIDANCE_TOOLTIP, BreakUpLargeNumbers(avoidanceRating), avoidanceBonus)
                    else
                        row.tooltip2 = format("Reduces damage taken from area effects by %.2F%%.", avoidanceBonus)
                    end
                elseif stat.statKey == "LIFESTEAL" then
                    local lifesteal = SafeGetStat(GetLifesteal)
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_LIFESTEAL) .. " " .. format("%.2F%%", lifesteal) .. FONT_COLOR_CODE_CLOSE
                    row.tooltip2 = format(CR_LIFESTEAL_TOOLTIP, BreakUpLargeNumbers(SafeGetStat(GetCombatRating, CR_LIFESTEAL)), SafeGetStat(GetCombatRatingBonus, CR_LIFESTEAL))
                elseif stat.statKey == "SPEED" then
                    local speedValue = SafeGetStat(GetSpeed)
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_SPEED) .. " " .. format("%.2F%%", speedValue) .. FONT_COLOR_CODE_CLOSE
                    row.tooltip2 = format(CR_SPEED_TOOLTIP, BreakUpLargeNumbers(SafeGetStat(GetCombatRating, CR_SPEED)), SafeGetStat(GetCombatRatingBonus, CR_SPEED))
                end
            end

            y = y - ROW_HEIGHT
        end
    end

    y = y - 5

    -- ATTACK
    _, headerHeight = CreateSectionHeader(scrollChild, "Attack", y)
    y = y - headerHeight

    local attackStats = {
        { label = "Attack Power", func = function() return UnitAttackPower(unit) end, format = FormatNumber, statKey = "ATTACK_POWER" },
        { label = "Spell Power", func = function() return GetSpellBonusDamage(2) end, format = FormatNumber, statKey = "SPELLPOWER" },  -- 2 = Holy, generic spell power
        { label = "Attack Speed", func = function() return UnitAttackSpeed(unit) end, format = function(v) return string.format("%.2fs", v or 0) end, statKey = "ATTACK_SPEED" },
    }

    -- Class-based filter for attack rows so we don't show Spell Power for
    -- a Warrior or skip Attack Power for a Mage. Non-secret signals only.
    local classFilter = {}
    do
        local _, cls = UnitClass(unit)
        local casterClasses = { MAGE = true, PRIEST = true, WARLOCK = true }
        local hybridClasses = { DRUID = true, PALADIN = true, SHAMAN = true, EVOKER = true, MONK = true }
        classFilter.ATTACK_POWER = not casterClasses[cls]
        classFilter.SPELLPOWER   = casterClasses[cls] or hybridClasses[cls]
        classFilter.ATTACK_SPEED = true  -- always relevant
    end

    for _, stat in ipairs(attackStats) do
        local value = SafeGetStat(stat.func)
        local shouldShow
        if secretsOff then
            shouldShow = classFilter[stat.statKey] ~= false
        else
            shouldShow = value and value > 0
        end
        if shouldShow then
            row = CreateStatRow(scrollChild, y)
            row.label:SetText(stat.label)

            -- Direct API → SetFormattedText. AttackSpeed wants "%.2fs", others
            -- want raw integer; pick spec from statKey.
            local fmtStr = (stat.statKey == "ATTACK_SPEED") and "%.2fs" or "%s"
            local vOk, v = pcall(stat.func)
            if vOk and v then row.value:SetFormattedText(fmtStr, v) end

            -- Static lore tooltip (combat-safe)
            if stat.statKey == "ATTACK_POWER" then
                row.tooltip = MELEE_ATTACK_POWER
                row.tooltip2 = MELEE_ATTACK_POWER_TOOLTIP
            elseif stat.statKey == "SPELLPOWER" then
                row.tooltip = STAT_SPELLPOWER
                row.tooltip2 = STAT_SPELLPOWER_TOOLTIP
            elseif stat.statKey == "ATTACK_SPEED" then
                row.tooltip = ATTACK_SPEED
                row.tooltip2 = _G.STAT_ATTACK_SPEED_BASE_TOOLTIP
            end

            if not secretsOff then
                -- Set tooltips (Blizzard format)
                if stat.statKey == "ATTACK_POWER" then
                    if PaperDollFormatStat then
                        local base, posBuff, negBuff = SafeGetStatValues(UnitAttackPower, unit)
                        local damageBonus = BreakUpLargeNumbers(max((base+posBuff+negBuff), 0)/ATTACK_POWER_MAGIC_NUMBER)
                        local tag, tooltip = MELEE_ATTACK_POWER, MELEE_ATTACK_POWER_TOOLTIP
                        local valueText, tooltipText = PaperDollFormatStat(tag, base, posBuff, negBuff)
                        row.tooltip = tooltipText
                        row.tooltip2 = format(tooltip, damageBonus)
                    end
                elseif stat.statKey == "SPELLPOWER" then
                    row.tooltip = STAT_SPELLPOWER
                    row.tooltip2 = STAT_SPELLPOWER_TOOLTIP
                elseif stat.statKey == "ATTACK_SPEED" then
                    local speed = SafeGetStat(UnitAttackSpeed, unit)
                    local displaySpeed = format("%.2F", speed)
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, ATTACK_SPEED).." "..displaySpeed..FONT_COLOR_CODE_CLOSE
                    local meleeHaste = SafeGetStat(GetMeleeHaste)
                    row.tooltip2 = format(STAT_ATTACK_SPEED_BASE_TOOLTIP, BreakUpLargeNumbers(meleeHaste))
                end
            end

            y = y - ROW_HEIGHT
        end
    end

    y = y - 5

    -- DEFENSE
    _, headerHeight = CreateSectionHeader(scrollChild, "Defense", y)
    y = y - headerHeight

    local baselineArmor, effectiveArmor = SafeGetStatValues(UnitArmor, unit)
    local dodge = SafeGetStat(GetDodgeChance)
    local parry = SafeGetStat(GetParryChance)
    local block = SafeGetStat(GetBlockChance)
    local staggerPercent = 0
    local _, classTag = UnitClass(unit)
    local isBrewmaster = false

    if classTag == "MONK" and unit == "player" and GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local specID = select(1, GetSpecializationInfo(specIndex))
            isBrewmaster = (specID == 268)
        end
    end

    if isBrewmaster then
        if C_PaperDollInfo and C_PaperDollInfo.GetStaggerPercentage then
            staggerPercent = SafeGetStat(C_PaperDollInfo.GetStaggerPercentage, unit)
        elseif GetStaggerPercentage then
            staggerPercent = SafeGetStat(GetStaggerPercentage, unit)
        elseif UnitStagger then
            local staggerAmount = SafeGetStat(UnitStagger, unit)
            local maxHealth = SafeGetStat(UnitHealthMax, unit)
            if maxHealth > 0 then
                staggerPercent = (staggerAmount / maxHealth) * 100
            end
        end
    end

    local defenseStats = {
        { label = "Armor", value = FormatNumber(effectiveArmor or 0), statKey = "ARMOR" },
        { label = "Dodge", value = FormatPercent(dodge), statKey = "DODGE" },
        { label = "Parry", value = FormatPercent(parry), statKey = "PARRY" },
        { label = "Block", value = FormatPercent(block), statKey = "BLOCK" },
    }

    if isBrewmaster then
        tinsert(defenseStats, { label = "Stagger", value = FormatPercent(staggerPercent), statKey = "STAGGER" })
    end

    -- Class-based defense filter for combat (non-secret signal). OOC we
    -- still render everything so users can see their actual values.
    local defenseFilter = {}
    do
        local plate = (classTag == "WARRIOR" or classTag == "PALADIN" or classTag == "DEATHKNIGHT")
        local shieldUser = (classTag == "WARRIOR" or classTag == "PALADIN" or classTag == "SHAMAN")
        defenseFilter.ARMOR   = true
        defenseFilter.DODGE   = (classTag ~= "WARLOCK" and classTag ~= "MAGE" and classTag ~= "PRIEST")
        defenseFilter.PARRY   = plate or (classTag == "ROGUE") or (classTag == "DEATHKNIGHT") or (classTag == "MONK") or (classTag == "DEMONHUNTER")
        defenseFilter.BLOCK   = shieldUser
        defenseFilter.STAGGER = isBrewmaster
    end

    for _, stat in ipairs(defenseStats) do
        local shouldShow
        if secretsOff then
            shouldShow = defenseFilter[stat.statKey] ~= false
        else
            shouldShow = true
        end
        if shouldShow then
            row = CreateStatRow(scrollChild, y)
            row.label:SetText(stat.label)

            -- Direct API → SetFormattedText. Different format per stat.
            if stat.statKey == "ARMOR" then
                local _, eff = SafeGetStatValues(UnitArmor, unit)
                local aOk, aBase, aEff = pcall(UnitArmor, unit)
                if aOk and aEff then row.value:SetFormattedText("%s", aEff) end
            elseif stat.statKey == "STAGGER" then
                if C_PaperDollInfo and C_PaperDollInfo.GetStaggerPercentage then
                    local sOk, s = pcall(C_PaperDollInfo.GetStaggerPercentage, unit)
                    if sOk and s then row.value:SetFormattedText("%.2f%%", s) end
                end
            else
                local valueFn = stat.statKey == "DODGE" and GetDodgeChance
                            or  stat.statKey == "PARRY" and GetParryChance
                            or  stat.statKey == "BLOCK" and GetBlockChance
                if valueFn then
                    local vOk, v = pcall(valueFn)
                    if vOk and v then row.value:SetFormattedText("%.2f%%", v) end
                end
            end

            -- Static lore tooltip (combat-safe)
            if stat.statKey == "ARMOR" then
                row.tooltip = ARMOR
                row.tooltip2 = _G.STAT_ARMOR_TOOLTIP
            elseif stat.statKey == "DODGE" then
                row.tooltip = DODGE_CHANCE
                row.tooltip2 = _G.STAT_DODGE_TOOLTIP or _G.CR_DODGE_TOOLTIP
            elseif stat.statKey == "PARRY" then
                row.tooltip = PARRY_CHANCE
                row.tooltip2 = _G.STAT_PARRY_TOOLTIP or _G.CR_PARRY_TOOLTIP
            elseif stat.statKey == "BLOCK" then
                row.tooltip = BLOCK_CHANCE
                row.tooltip2 = _G.STAT_BLOCK_TOOLTIP or _G.CR_BLOCK_TOOLTIP
            elseif stat.statKey == "STAGGER" then
                row.tooltip = _G.STAT_STAGGER or "Stagger"
                row.tooltip2 = _G.STAT_STAGGER_TOOLTIP or "Percentage of incoming Physical damage delayed by Stagger."
            end

            if not secretsOff then
                -- Set tooltips (Blizzard format)
                if stat.statKey == "ARMOR" then
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, ARMOR).." "..BreakUpLargeNumbers(effectiveArmor)..FONT_COLOR_CODE_CLOSE
                    if PaperDollFrame_GetArmorReduction then
                        local armorReduction = PaperDollFrame_GetArmorReduction(effectiveArmor, UnitEffectiveLevel(unit))
                        row.tooltip2 = format(STAT_ARMOR_TOOLTIP, armorReduction)
                        if PaperDollFrame_GetArmorReductionAgainstTarget then
                            local armorReductionAgainstTarget = PaperDollFrame_GetArmorReductionAgainstTarget(effectiveArmor)
                            if armorReductionAgainstTarget then
                                row.tooltip3 = format(STAT_ARMOR_TARGET_TOOLTIP, armorReductionAgainstTarget)
                            end
                        end
                    end
                elseif stat.statKey == "DODGE" then
                    local chance = SafeGetStat(GetDodgeChance)
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, DODGE_CHANCE).." "..string.format("%.2F", chance).."%"..FONT_COLOR_CODE_CLOSE
                    row.tooltip2 = format(CR_DODGE_TOOLTIP, SafeGetStat(GetCombatRating, CR_DODGE), SafeGetStat(GetCombatRatingBonus, CR_DODGE))
                elseif stat.statKey == "PARRY" then
                    local chance = SafeGetStat(GetParryChance)
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, PARRY_CHANCE).." "..string.format("%.2F", chance).."%"..FONT_COLOR_CODE_CLOSE
                    row.tooltip2 = format(CR_PARRY_TOOLTIP, SafeGetStat(GetCombatRating, CR_PARRY), SafeGetStat(GetCombatRatingBonus, CR_PARRY))
                elseif stat.statKey == "BLOCK" then
                    local chance = SafeGetStat(GetBlockChance)
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE..format(PAPERDOLLFRAME_TOOLTIP_FORMAT, BLOCK_CHANCE).." "..string.format("%.2F", chance).."%"..FONT_COLOR_CODE_CLOSE
                    if GetShieldBlock and PaperDollFrame_GetArmorReduction then
                        local shieldBlockArmor = SafeGetStat(GetShieldBlock)
                        local blockArmorReduction = PaperDollFrame_GetArmorReduction(shieldBlockArmor, UnitEffectiveLevel(unit))
                        row.tooltip2 = CR_BLOCK_TOOLTIP:format(blockArmorReduction)
                        if PaperDollFrame_GetArmorReductionAgainstTarget then
                            local blockArmorReductionAgainstTarget = PaperDollFrame_GetArmorReductionAgainstTarget(shieldBlockArmor)
                            if blockArmorReductionAgainstTarget then
                                row.tooltip3 = format(STAT_BLOCK_TARGET_TOOLTIP, blockArmorReductionAgainstTarget)
                            end
                        end
                    end
                elseif stat.statKey == "STAGGER" then
                    local staggerLabel = _G.STAT_STAGGER or "Stagger"
                    row.tooltip = HIGHLIGHT_FONT_COLOR_CODE .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, staggerLabel) .. " " .. format("%.2F%%", staggerPercent) .. FONT_COLOR_CODE_CLOSE
                    row.tooltip2 = _G.STAT_STAGGER_TOOLTIP or "Percentage of incoming Physical damage delayed by Stagger."
                end
            end

            y = y - ROW_HEIGHT
        end
    end

        FinalizeStatsPanelLayout(panel, scrollChild, y)
    end)  -- End pcall

    updatingStatsPanel = false

    if not success then
        -- Last-resort: panel update threw. Hide our panel and let Blizzard's
        -- native stats pane render (un-mask it) so the user still sees stats.
        if panel then pcall(panel.Hide, panel) end
        if CharacterStatsPane then
            pcall(CharacterStatsPane.SetAlpha, CharacterStatsPane, 1)
            if CharacterStatsPane.EnableMouse then
                pcall(CharacterStatsPane.EnableMouse, CharacterStatsPane, true)
            end
            if CharacterStatsPane.ClassBackground then
                pcall(CharacterStatsPane.ClassBackground.SetAlpha, CharacterStatsPane.ClassBackground, 1)
            end
        end
        print("QUI: Error updating stats panel:", err)
    end
end

---------------------------------------------------------------------------
-- Get color for item level (tiered based on gear quality)
---------------------------------------------------------------------------
local function GetILvlColor(ilvl)
    -- Color tiers for Midnight beta (~240-290 range)
    if ilvl >= 285 then
        return 1, 0.5, 0           -- Orange (Mythic raid tier)
    elseif ilvl >= 275 then
        return 0.64, 0.21, 0.93    -- Purple (Heroic raid)
    elseif ilvl >= 265 then
        return 0, 0.44, 0.87       -- Blue (Mythic dungeon)
    elseif ilvl >= 255 then
        return 0, 1, 0             -- Green (Heroic dungeon)
    elseif ilvl >= 245 then
        return 1, 1, 1             -- White (Normal)
    else
        return 0.62, 0.62, 0.62    -- Grey (Below normal)
    end
end

---------------------------------------------------------------------------
-- Update Item Level Display: [Name] [ilvl] [Spec Class]
---------------------------------------------------------------------------
local function UpdateILvlDisplay()
    if not CharacterFrame or not (frameState[CharacterFrame] or EMPTY).ilvlDisplay then return end

    local settings = GetSettings()
    if not settings.enabled then return end

    local displayFrame = (frameState[CharacterFrame] or EMPTY).ilvlDisplay
    if not displayFrame.text then return end

    -- Get player info
    local name = UnitName("player") or "Unknown"
    local level = UnitLevel("player") or 0
    local overall, equipped, pvp = GetPlayerAverageItemLevels()
    local ilvlStr = string.format("%.0f", equipped)

    -- Get spec and class
    local specName = ""
    local className = ""
    local specIndex = GetSpecialization()
    if specIndex then
        local _, specNameLocal = GetSpecializationInfo(specIndex)
        specName = specNameLocal or ""
    end
    local _, classNameLocal = UnitClass("player")
    if classNameLocal then
        -- Get localized class name
        local classInfo = C_CreatureInfo.GetClassInfo(select(3, UnitClass("player")))
        className = classInfo and classInfo.className or classNameLocal
    end

    -- Get class color
    local classColor = RAID_CLASS_COLORS[classNameLocal]
    local r, g, b = 1, 1, 1  -- Default white
    if classColor then
        r, g, b = classColor.r, classColor.g, classColor.b
    end

    -- Line 1: Character name (class colored)
    displayFrame.text:SetText(name)
    displayFrame.text:SetTextColor(r, g, b, 1)

    -- Line 2: Level + Spec (class colored)
    if displayFrame.specText then
        local specLine = string.format("%d %s %s", level, specName, AbbreviateClassName(className))
        displayFrame.specText:SetText(specLine)
        displayFrame.specText:SetTextColor(r, g, b, 1)
    end

    -- Update center ilvl display (above model) - shows equipped | overall with color coding
    local centerFrame = (frameState[CharacterFrame] or EMPTY).centerILvl
    if centerFrame and centerFrame.text then
        centerFrame.cachedOverallILvl = overall
        centerFrame.cachedEquippedILvl = equipped
        centerFrame.cachedPvpILvl = pvp

        -- Get colors for each ilvl tier
        local eR, eG, eB = GetILvlColor(equipped)
        local oR, oG, oB = GetILvlColor(overall)

        -- Format with color codes (one decimal point)
        local equippedHex = string.format("%02x%02x%02x", math.floor(eR*255), math.floor(eG*255), math.floor(eB*255))
        local overallHex = string.format("%02x%02x%02x", math.floor(oR*255), math.floor(oG*255), math.floor(oB*255))
        local equippedStr = string.format("%.1f", equipped)
        local overallStr = string.format("%.1f", overall)

        local centerStr = string.format("|cff%s%s  |  |cff%s%s|r", equippedHex, equippedStr, overallHex, overallStr)
        centerFrame.text:SetText(centerStr)
    end
end

---------------------------------------------------------------------------
-- Debounce update function
---------------------------------------------------------------------------
ScheduleUpdate = function()
    if pendingUpdate then return end
    pendingUpdate = true

    C_Timer.After(0.05, function()
        pendingUpdate = false

        -- Update character frame if visible AND on Character tab (not Reputation/Currency)
        if CharacterFrame and CharacterFrame:IsShown() and PaperDollFrame and PaperDollFrame:IsShown() then
            UpdateAllSlotOverlays("player", slotOverlays)
            UpdateILvlDisplay()
            if statsPanel then
                -- Don't update/show stats panel if Equipment Manager is open
                local equipMgrOpen = PaperDollFrame.EquipmentManagerPane
                                     and PaperDollFrame.EquipmentManagerPane:IsShown()
                if not equipMgrOpen then
                    UpdateStatsPanel(statsPanel, "player")
                end
            end
        end

        -- Update inspect frame if visible (delegated to qui_inspect.lua)
        if ns.QUI.InspectPane and ns.QUI.InspectPane.UpdateInspectFrame then
            ns.QUI.InspectPane.UpdateInspectFrame()
        end
    end)
end

---------------------------------------------------------------------------
-- Create floating Equipment Manager container (positioning only - skinning in skinning/character.lua)
---------------------------------------------------------------------------
local function CreateEquipMgrPopup()
    if equipMgrPopup then return equipMgrPopup end

    -- Position accounts for extended character pane (55px width extension + 10px gap)
    local PANEL_WIDTH_EXTENSION = 55
    equipMgrPopup = CreateFrame("Frame", "QUI_EquipMgrPopup", UIParent, "BackdropTemplate")
    equipMgrPopup:SetSize(205, 400)
    equipMgrPopup:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", PANEL_WIDTH_EXTENSION + 10, 0)
    equipMgrPopup:SetFrameStrata("DIALOG")
    equipMgrPopup:EnableMouse(true)
    equipMgrPopup:SetMovable(true)
    equipMgrPopup:RegisterForDrag("LeftButton")
    equipMgrPopup:SetScript("OnDragStart", equipMgrPopup.StartMoving)
    equipMgrPopup:SetScript("OnDragStop", equipMgrPopup.StopMovingOrSizing)
    equipMgrPopup:Hide()

    -- Default Blizzard backdrop (skinning module will override if enabled)
    equipMgrPopup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    -- Title bar (text only - styling in skinning module)
    local title = equipMgrPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Equipment Manager")
    equipMgrPopup.title = title

    -- Expose globally for skinning module to access
    _G.QUI_EquipMgrPopup = equipMgrPopup

    return equipMgrPopup
end

---------------------------------------------------------------------------
-- Create floating Titles container (positioning only - skinning in skinning/character.lua)
---------------------------------------------------------------------------
local function CreateTitlesPopup()
    if titlesPopup then return titlesPopup end

    -- Position accounts for extended character pane (55px width extension + 10px gap)
    local PANEL_WIDTH_EXTENSION = 55
    titlesPopup = CreateFrame("Frame", "QUI_TitlesPopup", UIParent, "BackdropTemplate")
    titlesPopup:SetSize(205, 400)
    titlesPopup:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", PANEL_WIDTH_EXTENSION + 10, 0)
    titlesPopup:SetFrameStrata("DIALOG")
    titlesPopup:EnableMouse(true)
    titlesPopup:SetMovable(true)
    titlesPopup:RegisterForDrag("LeftButton")
    titlesPopup:SetScript("OnDragStart", titlesPopup.StartMoving)
    titlesPopup:SetScript("OnDragStop", titlesPopup.StopMovingOrSizing)
    titlesPopup:Hide()

    -- Default Blizzard backdrop (skinning module will override if enabled)
    titlesPopup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    -- Title bar (text only - styling in skinning module)
    local title = titlesPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Titles")
    titlesPopup.title = title

    -- Expose globally for skinning module to access
    _G.QUI_TitlesPopup = titlesPopup

    return titlesPopup
end

---------------------------------------------------------------------------
-- Hook character frame
---------------------------------------------------------------------------
local characterFrameHooked = false  -- Prevent duplicate hook registration

local function HookCharacterFrame()
    if not CharacterFrame then return end
    if characterFrameHooked then return end
    characterFrameHooked = true

    -- Forward declarations for settings button and panel (used by HideCustomElements)
    local gearBtn, settingsPanel

    -- Initialize when character frame first shows
    CharacterFrame:HookScript("OnShow", function()
        -- Delay check to allow tab frames to initialize their visibility
        C_Timer.After(0.01, function()
            if PaperDollFrame and PaperDollFrame:IsShown() then
                -- Character tab is active - apply custom layout
                ApplyCharacterPaneLayout()
                InitializeCharacterOverlays()
                ScheduleUpdate()
            else
                -- Opening Currency/Reputation directly via hotkey - hide custom elements and reset scale
                -- Only hide our customBg if skinning module isn't handling it
                if not IsSkinningHandlingBackground() and customBg then
                    customBg:Hide()
                end
                if statsPanel then statsPanel:Hide() end
                for _, overlay in pairs(slotOverlays) do
                    if overlay then overlay:Hide() end
                end
                if equipMgrPopup then equipMgrPopup:Hide() end
                if (frameState[CharacterFrame] or EMPTY).ilvlDisplay then (frameState[CharacterFrame] or EMPTY).ilvlDisplay:Hide() end
                if (frameState[CharacterFrame] or EMPTY).centerILvl then (frameState[CharacterFrame] or EMPTY).centerILvl:Hide() end
                SafeSetCharScale(1.0)
            end
        end)
    end)

    CharacterFrame:HookScript("OnHide", function()
        -- Reset layout flag so repositioning runs on next show
        layoutApplied = false

        -- Cleanup tooltips
        GameTooltip:Hide()

        -- Hide floating Equipment Manager popup and restore pane to original parent
        if equipMgrPopup then
            equipMgrPopup:Hide()
        end

        local equipPane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
        if equipPane and (frameState[equipPane] or EMPTY).originalParent then
            equipPane:SetParent((frameState[equipPane] or EMPTY).originalParent)
        end

        -- Hide floating Titles popup and restore pane to original parent
        if titlesPopup then
            titlesPopup:Hide()
        end

        local titlesPane = PaperDollFrame and PaperDollFrame.TitleManagerPane
        if titlesPane and (frameState[titlesPane] or EMPTY).originalParent then
            titlesPane:SetParent((frameState[titlesPane] or EMPTY).originalParent)
        end
    end)

    -- Re-mask Blizzard's stats pane every time Blizzard re-Shows it (e.g. when
    -- clicking "Character Stats" button or on tab transitions). We keep it
    -- Shown so its FontStrings stay current — we just render alpha 0.
    if CharacterStatsPane then
        hooksecurefunc(CharacterStatsPane, "Show", function()
            C_Timer.After(0, function()
                local settings = GetSettings()
                if settings.enabled and CharacterStatsPane then
                    MaskNativeStatsPane()
                end
            end)
        end)
    end

    -- Re-apply sidebar tab skin when Blizzard refreshes tab visuals.
    if type(_G.PaperDollFrame_UpdateSidebarTabs) == "function" and not (frameState[CharacterFrame] or EMPTY).sidebarSkinHooked then
        hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", function()
            C_Timer.After(0, function()
                local settings = GetSettings()
                if settings.enabled and CharacterFrame and CharacterFrame:IsShown() and PaperDollFrame and PaperDollFrame:IsShown() then
                    StyleSidebarTabs()
                end
            end)
        end)
        GetState(CharacterFrame).sidebarSkinHooked = true
    end

    -- Equipment Manager tab: Reparent to floating popup (Blizzard native appearance)
    if PaperDollSidebarTab3 and not (frameState[PaperDollSidebarTab3] or EMPTY).hooked then
        PaperDollSidebarTab3:HookScript("OnClick", function()
            local settings = GetSettings()
            if not settings.enabled then return end

            -- Hide Titles popup first (they share same position)
            if titlesPopup then
                titlesPopup:Hide()
            end
            local titlesPane = PaperDollFrame and PaperDollFrame.TitleManagerPane
            if titlesPane and (frameState[titlesPane] or EMPTY).originalParent then
                titlesPane:SetParent((frameState[titlesPane] or EMPTY).originalParent)
            end

            -- Create floating container if needed
            local popup = CreateEquipMgrPopup()

            -- Reparent Equipment Manager pane to floating popup
            local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
            if pane then
                -- Store original parent for restoration
                if not (frameState[pane] or EMPTY).originalParent then
                    GetState(pane).originalParent = pane:GetParent()
                end

                -- Reparent to floating popup (Blizzard appearance preserved)
                pane:SetParent(popup)
                pane:ClearAllPoints()
                pane:SetPoint("TOPLEFT", popup, "TOPLEFT", 5, -30)  -- Below title
                pane:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -5, 5)
                pane:Show()

                -- CRITICAL: ScrollBox has independent anchors - must reposition it too
                if pane.ScrollBox then
                    pane.ScrollBox:ClearAllPoints()
                    pane.ScrollBox:SetPoint("TOPLEFT", pane, "TOPLEFT", 5, -35)  -- Below buttons
                    pane.ScrollBox:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -25, 5)  -- Extra right margin to hide scrollbar area
                end

                popup:Show()

                -- Trigger skinning module to apply styles (if enabled)
                local skinningAPI = _G.QUI_CharacterFrameSkinning
                if skinningAPI and skinningAPI.SkinEquipmentManager then
                    skinningAPI.SkinEquipmentManager()
                end
            end

            -- Keep stats panel visible so user can see stats while managing gear
        end)
        GetState(PaperDollSidebarTab3).hooked = true
    end

    -- Titles tab (Tab2): Reparent to floating popup
    if PaperDollSidebarTab2 and not (frameState[PaperDollSidebarTab2] or EMPTY).hooked then
        PaperDollSidebarTab2:HookScript("OnClick", function()
            local settings = GetSettings()
            if not settings.enabled then return end

            -- Hide Equipment Manager popup first (they share same position)
            if equipMgrPopup then
                equipMgrPopup:Hide()
            end
            local equipPane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
            if equipPane and (frameState[equipPane] or EMPTY).originalParent then
                equipPane:SetParent((frameState[equipPane] or EMPTY).originalParent)
            end

            -- Create floating container if needed
            local popup = CreateTitlesPopup()

            -- Reparent Title Manager pane to floating popup
            local pane = PaperDollFrame and PaperDollFrame.TitleManagerPane
            if pane then
                -- Store original parent for restoration
                if not (frameState[pane] or EMPTY).originalParent then
                    GetState(pane).originalParent = pane:GetParent()
                end

                -- Reparent to floating popup
                pane:SetParent(popup)
                pane:ClearAllPoints()
                pane:SetPoint("TOPLEFT", popup, "TOPLEFT", 5, -30)  -- Below title
                pane:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -5, 5)
                pane:Show()

                -- ScrollBox has independent anchors - must reposition it too
                if pane.ScrollBox then
                    pane.ScrollBox:ClearAllPoints()
                    pane.ScrollBox:SetPoint("TOPLEFT", pane, "TOPLEFT", 5, -5)
                    pane.ScrollBox:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -25, 5)
                end

                popup:Show()

                -- Trigger skinning module to apply styles (if enabled)
                local skinningAPI = _G.QUI_CharacterFrameSkinning
                if skinningAPI and skinningAPI.SkinTitleManager then
                    skinningAPI.SkinTitleManager()
                end
            end
        end)
        GetState(PaperDollSidebarTab2).hooked = true
    end

    -- Ensure Equipment Manager popups appear above custom layout
    if GearManagerPopupFrame then
        GearManagerPopupFrame:SetFrameStrata("DIALOG")
        if GearManagerPopupFrame.IconSelector then
            GearManagerPopupFrame.IconSelector:SetFrameStrata("FULLSCREEN")
        end

        -- Reposition icon selector popup next to our floating popup
        hooksecurefunc(GearManagerPopupFrame, "Show", function(self)
            C_Timer.After(0, function()
                if self and equipMgrPopup and equipMgrPopup:IsShown() then
                    self:ClearAllPoints()
                    self:SetPoint("TOPLEFT", equipMgrPopup, "TOPRIGHT", 5, 0)
                end
            end)
        end)
    end

    -- Character Stats tab (Tab1): Show stats panel and restore Equipment Manager/Titles
    if PaperDollSidebarTab1 then
        PaperDollSidebarTab1:HookScript("OnClick", function()
            local settings = GetSettings()

            -- Hide Equipment Manager popup and restore pane to original parent
            if equipMgrPopup then
                equipMgrPopup:Hide()
            end

            local equipPane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
            if equipPane and (frameState[equipPane] or EMPTY).originalParent then
                equipPane:SetParent((frameState[equipPane] or EMPTY).originalParent)
            end

            -- Hide Titles popup and restore pane to original parent
            if titlesPopup then
                titlesPopup:Hide()
            end

            local titlesPane = PaperDollFrame and PaperDollFrame.TitleManagerPane
            if titlesPane and (frameState[titlesPane] or EMPTY).originalParent then
                titlesPane:SetParent((frameState[titlesPane] or EMPTY).originalParent)
            end

            -- Show stats panel
            if settings.enabled and statsPanel then
                statsPanel:Show()
            end
        end)
    end

    -- TAB SWITCHING: Hide custom elements when switching to other tabs
    -- This prevents stats panel/overlays from showing over Reputation/Currency

    -- Helper to adjust tab and close button positions for Reputation/Currency tabs
    local function AdjustForNonCharacterTab()
        -- Move tabs up 50 pixels: -48 → +2
        if CharacterFrameTab1 then
            CharacterFrameTab1:ClearAllPoints()
            CharacterFrameTab1:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 11, 2)
        end
        -- Move close button left 55 pixels: 52 → -3
        if CharacterFrame.CloseButton then
            CharacterFrame.CloseButton:ClearAllPoints()
            CharacterFrame.CloseButton:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -3, -5)
        end
    end

    local function RestoreCharacterTabPositions()
        -- Restore original tab position
        if CharacterFrameTab1 then
            CharacterFrameTab1:ClearAllPoints()
            CharacterFrameTab1:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 11, -48)
        end
        -- Restore original close button position
        if CharacterFrame.CloseButton then
            CharacterFrame.CloseButton:ClearAllPoints()
            CharacterFrame.CloseButton:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", 52, -5)
        end
    end

    -- Helper to hide all custom elements (when leaving Character tab)
    local function HideCustomElements()
        -- QUI-owned frames — always safe to hide
        if statsPanel then statsPanel:Hide() end
        for _, overlay in pairs(slotOverlays) do
            if overlay then overlay:Hide() end
        end
        if equipMgrPopup then equipMgrPopup:Hide() end
        if (frameState[CharacterFrame] or EMPTY).ilvlDisplay then (frameState[CharacterFrame] or EMPTY).ilvlDisplay:Hide() end
        if (frameState[CharacterFrame] or EMPTY).centerILvl then (frameState[CharacterFrame] or EMPTY).centerILvl:Hide() end
        if (frameState[CharacterFrame] or EMPTY).gearBtn then (frameState[CharacterFrame] or EMPTY).gearBtn:Hide() end
        if (frameState[CharacterFrame] or EMPTY).settingsPanel then (frameState[CharacterFrame] or EMPTY).settingsPanel:Hide() end

        -- Handle background and decorations based on skinning state
        if IsSkinningHandlingBackground() then
            local skinningAPI = _G.QUI_CharacterFrameSkinning
            if skinningAPI and skinningAPI.SetExtended then
                skinningAPI.SetExtended(false)
            end
        else
            if customBg then customBg:Hide() end
            -- Blizzard decoration Show calls — defer if in combat
            if InCombatLockdown() then
                pendingDecorMode = "other"
            else
                if CharacterFramePortrait then CharacterFramePortrait:Show() end
                if CharacterFrame.Background then CharacterFrame.Background:Show() end
                if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Show() end
                if CharacterFrameBg then CharacterFrameBg:Show() end
            end
        end

        -- Protected: SetScale + tab/button repositioning
        SafeSetCharScale(1.0)
        if InCombatLockdown() then
            pendingTabMode = "other"
        else
            AdjustForNonCharacterTab()
        end
    end

    -- Hide when Reputation tab opens
    if ReputationFrame then
        ReputationFrame:HookScript("OnShow", HideCustomElements)
    end

    -- Hide when Currency tab opens
    if TokenFrame then
        TokenFrame:HookScript("OnShow", HideCustomElements)
    end

    -- Show when Character tab (PaperDollFrame) opens
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            local settings = GetSettings()
            if settings.enabled then
                -- Protected: restore tab positions and scale
                if InCombatLockdown() then
                    pendingTabMode = "character"
                else
                    RestoreCharacterTabPositions()
                end
                local BASE_SCALE = 1.30
                local scaleMultiplier = settings.panelScale or 1.0
                SafeSetCharScale(BASE_SCALE * scaleMultiplier)

                -- Ensure layout is applied (creates statsPanel if needed)
                if not layoutApplied then
                    ApplyCharacterPaneLayout()
                    InitializeCharacterOverlays()
                end

                -- Handle background based on skinning state
                if IsSkinningHandlingBackground() then
                    local skinningAPI = _G.QUI_CharacterFrameSkinning
                    if skinningAPI and skinningAPI.SetExtended then
                        skinningAPI.SetExtended(true)
                    end
                else
                    if customBg then customBg:Show() end
                    -- Blizzard decoration Hide calls — defer if in combat
                    if InCombatLockdown() then
                        pendingDecorMode = "character"
                    else
                        if CharacterFramePortrait then CharacterFramePortrait:Hide() end
                        if CharacterFrame.Background then CharacterFrame.Background:Hide() end
                        if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Hide() end
                        if CharacterFrameBg then CharacterFrameBg:Hide() end
                    end
                end

                -- Mask Blizzard's stats pane (keep it Shown so it keeps
                -- updating its FontStrings, just render alpha 0).
                MaskNativeStatsPane()
                if statsPanel then statsPanel:Show() end
                for _, overlay in pairs(slotOverlays) do
                    if overlay then overlay:Show() end
                end
                -- Show ilvl display, center ilvl, and settings button on Character tab
                if (frameState[CharacterFrame] or EMPTY).ilvlDisplay then (frameState[CharacterFrame] or EMPTY).ilvlDisplay:Show() end
                if (frameState[CharacterFrame] or EMPTY).centerILvl then (frameState[CharacterFrame] or EMPTY).centerILvl:Show() end
                if (frameState[CharacterFrame] or EMPTY).gearBtn then (frameState[CharacterFrame] or EMPTY).gearBtn:Show() end
                ScheduleUpdate()
                -- Refresh equipment slot borders (may be reset by Blizzard on reopen)
                if #allEquipmentSlots > 0 and UpdateEquipmentSlotBorder then
                    C_Timer.After(0.05, function()
                        for _, slot in ipairs(allEquipmentSlots) do
                            UpdateEquipmentSlotBorder(slot)
                        end
                    end)
                end
                -- Ensure stats panel shows (may not exist yet on first load due to delayed creation)
                C_Timer.After(0.15, function()
                    if statsPanel then
                        statsPanel:Show()
                    end
                end)
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Settings gear icon and mini-panel (in-pane customization)
    ---------------------------------------------------------------------------

    -- Only create settings button if module is enabled
    local settings = GetSettings()
    if not settings.enabled then
        -- Hide existing button if module was disabled
        if (frameState[CharacterFrame] or EMPTY).gearBtn then
            (frameState[CharacterFrame] or EMPTY).gearBtn:Hide()
        end
        if (frameState[CharacterFrame] or EMPTY).settingsPanel then
            (frameState[CharacterFrame] or EMPTY).settingsPanel:Hide()
        end
        return
    end

    -- Create gear icon (more prominent position in title bar)
    if not (frameState[CharacterFrame] or EMPTY).gearBtn then
        gearBtn = CreateFrame("Button", "QUI_CharacterSettingsBtn", CharacterFrame, "BackdropTemplate")
        -- Width 118 keeps the icon and label inside one bordered button across UI scales.
        -- Do NOT call gearLabel:GetStringWidth() to drive this — it returns 0 before
        -- the FontString has been laid out, which collapses the button to icon-only width).
        QUICore:SetPixelPerfectSize(gearBtn, 118, 20)
        QUICore:SetPixelPerfectPoint(gearBtn, "TOPRIGHT", CharacterFrame, "TOPRIGHT", 6, -6)
        local br, bg, bb = GetCharacterBorderColor()
        ApplyOnePixelBorder(gearBtn, true)
        Helpers.SetFrameBackdropColor(gearBtn, 0.1, 0.1, 0.1, 0.8)
        Helpers.SetFrameBackdropBorderColor(gearBtn, br, bg, bb, 1)
        gearBtn:SetFrameStrata("HIGH")
        gearBtn:SetFrameLevel(100)

        -- Gear icon inside button
        local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
        gearIcon:SetSize(14, 14)
        gearIcon:SetPoint("LEFT", gearBtn, "LEFT", 5, 0)
        gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")

        -- "Settings" label
        local gearLabel = gearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gearLabel:SetPoint("LEFT", gearIcon, "RIGHT", 4, 0)
        gearLabel:SetPoint("RIGHT", gearBtn, "RIGHT", -6, 0)
        gearLabel:SetJustifyH("LEFT")
        gearLabel:SetText("Settings")
        gearLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Hover effect
        gearBtn:SetScript("OnEnter", function(self)
            local r, g, b = GetCharacterAccentColor()
            self:SetBackdropBorderColor(r, g, b, 1)
        end)
        gearBtn:SetScript("OnLeave", function(self)
            local r, g, b = GetCharacterBorderColor()
            self:SetBackdropBorderColor(r, g, b, 1)
        end)

        GetState(CharacterFrame).gearBtn = gearBtn

        -- Settings panel (positioned to the right of CharacterFrame)
        settingsPanel = CreateFrame("Frame", "QUI_CharSettingsPanel", CharacterFrame, "BackdropTemplate")
        settingsPanel:SetSize(450, 600)
        settingsPanel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 53, 0)
        local settingsPx = QUICore:GetPixelSize(settingsPanel)
        settingsPanel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = settingsPx,
        })
        Helpers.SetFrameBackdropColor(settingsPanel, C.bg[1], C.bg[2], C.bg[3], 0.98)
        Helpers.SetFrameBackdropBorderColor(settingsPanel, C.border[1], C.border[2], C.border[3], 1)
        settingsPanel:SetFrameStrata("DIALOG")
        settingsPanel:SetFrameLevel(200)
        settingsPanel:EnableMouse(true)
        settingsPanel:Hide()
        GetState(CharacterFrame).settingsPanel = settingsPanel

        -- Title
        local title = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", settingsPanel, "TOP", 0, -8)
        title:SetText("QUI Character Panel")
        title:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)

        -- Close button (X)
        local closeBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -3, -3)
        closeBtn:SetScript("OnClick", function() settingsPanel:Hide() end)
        StyleCloseButton(closeBtn)

        -- Plain ScrollFrame (no template). See comment on the stats-panel scroll
        -- frame: UIPanelScrollFrameTemplate inherits from SecureScrollFrameTemplate,
        -- and addon-side geometry mods taint its xrange/yrange reads in 12.0+.
        local scrollFrame = CreateFrame("ScrollFrame", nil, settingsPanel)
        scrollFrame:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 5, -28)
        scrollFrame:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMRIGHT", -5, 40)
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll() or 0
            local maxScroll = self:GetVerticalScrollRange() or 0
            local new = math.max(0, math.min(maxScroll, current - delta * 30))
            self:SetVerticalScroll(new)
        end)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(440)  -- settingsPanel(450) - left(5) - right(5)
        scrollChild:SetHeight(1)  -- Will be updated after adding widgets
        scrollFrame:SetScrollChild(scrollChild)

        -- Get GUI reference and settings
        local GUI = _G.QUI and _G.QUI.GUI
        if not GUI then return end
        local settings = GetSettings()
        local charDB = settings

        -- Layout constants
        local PAD = 8
        local FORM_ROW = 28
        local y = -5

        -- Refresh callback for overlay toggles
        local function RefreshAll()
            if _G.QUI_RefreshCharacterPanelFonts then
                _G.QUI_RefreshCharacterPanelFonts()
            end
            ScheduleUpdate()
        end

        -- Widget references for conditional disable
        local widgetRefs = {}

        ---------------------------------------------------------------------------
        -- APPEARANCE Section
        ---------------------------------------------------------------------------
        local appearHeader = GUI:CreateSectionHeader(scrollChild, "Appearance")
        appearHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - appearHeader.gap

        -- Scale slider (multiplier on base 1.30 scale, range 0.75-1.5)
        local BASE_SCALE = 1.30
        local scaleSlider = GUI:CreateFormSlider(scrollChild, "Panel Scale", 0.75, 1.5, 0.05, "panelScale", charDB, function()
            local multiplier = charDB.panelScale or 1.0
            SafeSetCharScale(BASE_SCALE * multiplier)
        end, { deferOnDrag = true },
            { description = "Zoom factor applied to the character panel on top of the base scale. 1.0 leaves the panel at the default QUI size." })
        scaleSlider:SetPoint("TOPLEFT", PAD, y)
        scaleSlider:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Background color (uses shared skinning background color)
        local core = GetCore()
        local generalDB = core and core.db and core.db.profile and core.db.profile.general
        local bgColorPicker = nil
        if generalDB then
            bgColorPicker = GUI:CreateFormColorPicker(scrollChild, "Background Color", "skinBgColor", generalDB, function()
                -- Update local customBg if we own it
                if customBg and not IsSkinningHandlingBackground() then
                    local col = generalDB.skinBgColor or C.bg
                    customBg:SetBackdropColor(col[1], col[2], col[3], col[4] or 0.95)
                end
                -- Also refresh skinning module if it's active
                if _G.QUI_RefreshCharacterFrameColors then
                    _G.QUI_RefreshCharacterFrameColors()
                end
            end, nil,
                { description = "Background color applied to the character panel. Shared with the global skinning background so character and inspect panels match." })
            bgColorPicker:SetPoint("TOPLEFT", PAD, y)
            bgColorPicker:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Refresh color picker when panel shows (in case color changed in main QUI options)
            settingsPanel:HookScript("OnShow", function()
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

        local showItemName = GUI:CreateFormCheckbox(scrollChild, "Show Equipment Name", "showItemName", charDB, RefreshAll,
            { description = "Show the equipped item's name on each character panel slot overlay." })
        showItemName:SetPoint("TOPLEFT", PAD, y)
        showItemName:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showIlvl = GUI:CreateFormCheckbox(scrollChild, "Show Item Level & Track", "showItemLevel", charDB, RefreshAll,
            { description = "Show the item level and upgrade track label on each slot overlay." })
        showIlvl:SetPoint("TOPLEFT", PAD, y)
        showIlvl:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showEnchants = GUI:CreateFormCheckbox(scrollChild, "Show Enchant Status", "showEnchants", charDB, RefreshAll,
            { description = "Show the enchant name on each slot, or a missing-enchant marker if the slot has no enchant." })
        showEnchants:SetPoint("TOPLEFT", PAD, y)
        showEnchants:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showGems = GUI:CreateFormCheckbox(scrollChild, "Show Gem Indicators", "showGems", charDB, RefreshAll,
            { description = "Show colored gem dots indicating how many gem slots the item has and whether each is filled." })
        showGems:SetPoint("TOPLEFT", PAD, y)
        showGems:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showDura = GUI:CreateFormCheckbox(scrollChild, "Show Durability Bars", "showDurability", charDB, RefreshAll,
            { description = "Show a small durability bar on each slot overlay that has durability damage." })
        showDura:SetPoint("TOPLEFT", PAD, y)
        showDura:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        ---------------------------------------------------------------------------
        -- STATS PANEL Section
        ---------------------------------------------------------------------------
        local statsPanelHeader = GUI:CreateSectionHeader(scrollChild, "Stats Panel")
        statsPanelHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - statsPanelHeader.gap

        local showTooltips = GUI:CreateFormCheckbox(scrollChild, "Show Stat Tooltips", "showTooltips", charDB, function()
            RefreshAll()
            -- Force update stats panel to apply tooltip changes
            if statsPanel then
                UpdateStatsPanel(statsPanel, "player")
            end
        end, { description = "Show Blizzard's detailed stat tooltip when hovering any row in the QUI stats panel." })
        showTooltips:SetPoint("TOPLEFT", PAD, y)
        showTooltips:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        ---------------------------------------------------------------------------
        -- SECONDARY STATS Section
        ---------------------------------------------------------------------------
        local secondaryStatsHeader = GUI:CreateSectionHeader(scrollChild, "Secondary Stats")
        secondaryStatsHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - secondaryStatsHeader.gap

        local formatOptions = {
            { value = "percent", text = "Percentage (19.52%)" },
            { value = "rating", text = "Rating (1,234)" },
            { value = "both", text = "Both (1,234 (19.5%))" },
        }
        local secondaryFormat = GUI:CreateFormDropdown(scrollChild, "Display Format", formatOptions, "secondaryStatFormat", charDB, RefreshAll,
            { description = "How secondary stats (Crit, Haste, Mastery, Versatility) are formatted: percent only, rating only, or both side by side." })
        secondaryFormat:SetPoint("TOPLEFT", PAD, y)
        secondaryFormat:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        ---------------------------------------------------------------------------
        -- TEXT SIZES Section
        ---------------------------------------------------------------------------
        local textSizeHeader = GUI:CreateSectionHeader(scrollChild, "Text Sizes")
        textSizeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - textSizeHeader.gap

        local slotTextSize = GUI:CreateFormSlider(scrollChild, "Slot Text Size", 6, 40, 1, "slotTextSize", charDB, RefreshAll, nil,
            { description = "Font size for the text labels on each equipment slot overlay (item name, item level, enchant status)." })
        slotTextSize:SetPoint("TOPLEFT", PAD, y)
        slotTextSize:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local headerTextSize = GUI:CreateFormSlider(scrollChild, "Header Text Size", 6, 40, 1, "headerTextSize", charDB, RefreshAll, nil,
            { description = "Font size for section headers in the stats panel (Attributes, Secondary Stats, etc.)." })
        headerTextSize:SetPoint("TOPLEFT", PAD, y)
        headerTextSize:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local statsTextSize = GUI:CreateFormSlider(scrollChild, "Stats Text Size", 6, 40, 1, "statsTextSize", charDB, RefreshAll, nil,
            { description = "Font size for the stat rows under each section header." })
        statsTextSize:SetPoint("TOPLEFT", PAD, y)
        statsTextSize:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        ---------------------------------------------------------------------------
        -- TEXT COLORS Section
        ---------------------------------------------------------------------------
        local textColorHeader = GUI:CreateSectionHeader(scrollChild, "Text Colors")
        textColorHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - textColorHeader.gap

        local statsTextColor = GUI:CreateFormColorPicker(scrollChild, "Stats Text Color", "statsTextColor", charDB, RefreshAll, nil,
            { description = "Color used for the stat values in the stats panel." })
        statsTextColor:SetPoint("TOPLEFT", PAD, y)
        statsTextColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Header Class Color toggle
        local headerClassColor = GUI:CreateFormCheckbox(scrollChild, "Header Class Color", "headerClassColor", charDB, function()
            RefreshAll()
            if widgetRefs.headerColor then
                local alpha = charDB.headerClassColor and 0.4 or 1.0
                widgetRefs.headerColor:SetAlpha(alpha)
            end
        end, { description = "Color the stats-panel section headers with your class color instead of the Header Color below." })
        headerClassColor:SetPoint("TOPLEFT", PAD, y)
        headerClassColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local headerColor = GUI:CreateFormColorPicker(scrollChild, "Header Color", "headerColor", charDB, RefreshAll, nil,
            { description = "Fallback color for the stats-panel section headers when Header Class Color is off." })
        headerColor:SetPoint("TOPLEFT", PAD, y)
        headerColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        widgetRefs.headerColor = headerColor
        headerColor:SetAlpha(charDB.headerClassColor and 0.4 or 1.0)
        y = y - FORM_ROW

        -- Enchant Class Color toggle
        local enchantClassColor = GUI:CreateFormCheckbox(scrollChild, "Enchant Class Color", "enchantClassColor", charDB, function()
            RefreshAll()
            if widgetRefs.enchantColor then
                local alpha = charDB.enchantClassColor and 0.4 or 1.0
                widgetRefs.enchantColor:SetAlpha(alpha)
            end
        end, { description = "Color the enchant text using your class color instead of the Enchant Text Color below." })
        enchantClassColor:SetPoint("TOPLEFT", PAD, y)
        enchantClassColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local enchantColor = GUI:CreateFormColorPicker(scrollChild, "Enchant Text Color", "enchantTextColor", charDB, RefreshAll, nil,
            { description = "Fallback color for the enchant text when Enchant Class Color is off." })
        enchantColor:SetPoint("TOPLEFT", PAD, y)
        enchantColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        widgetRefs.enchantColor = enchantColor
        enchantColor:SetAlpha(charDB.enchantClassColor and 0.4 or 1.0)
        y = y - FORM_ROW

        local noEnchantColor = GUI:CreateFormColorPicker(scrollChild, "No Enchant Color", "noEnchantTextColor", charDB, RefreshAll, nil,
            { description = "Color used for the missing-enchant marker on slots that are not enchanted." })
        noEnchantColor:SetPoint("TOPLEFT", PAD, y)
        noEnchantColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local upgradeTrackColor = GUI:CreateFormColorPicker(scrollChild, "Upgrade Track Color", "upgradeTrackColor", charDB, RefreshAll, nil,
            { description = "Color used for the upgrade-track label (e.g. Explorer 2/8) next to item level." })
        upgradeTrackColor:SetPoint("TOPLEFT", PAD, y)
        upgradeTrackColor:SetPoint("RIGHT", scrollChild, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        -- Update scroll child height
        scrollChild:SetHeight(math.abs(y) + 20)

        ---------------------------------------------------------------------------
        -- Reset Button (at bottom of panel, outside scroll)
        ---------------------------------------------------------------------------
        local resetBtn = GUI:CreateButton(settingsPanel, "Reset", 80, 24, function()
            -- Reset all settings to defaults (background color is shared via Skinning tab)
            charDB.panelScale = 1.0
            charDB.showItemName = true
            charDB.showItemLevel = true
            charDB.showEnchants = true
            charDB.showGems = true
            charDB.showDurability = false
            charDB.secondaryStatFormat = "both"
            charDB.slotTextSize = 12
            charDB.headerTextSize = 12
            charDB.statsTextSize = 12
            charDB.statsTextColor = {0.953, 0.957, 0.965}
            charDB.headerClassColor = true
            charDB.headerColor = {0.376, 0.647, 0.980}
            charDB.enchantClassColor = true
            charDB.enchantTextColor = {0.376, 0.647, 0.980}
            charDB.noEnchantTextColor = {0.5, 0.5, 0.5}
            charDB.upgradeTrackColor = {0.98, 0.60, 0.35, 1}

            -- Apply scale (base 1.30 * multiplier 1.0)
            SafeSetCharScale(1.30)

            -- Refresh and reload the settings panel to reflect reset values
            RefreshAll()

            -- Reload the settings panel to update widget states
            settingsPanel:Hide()
            C_Timer.After(0.1, function()
                settingsPanel:Show()
            end)
        end)
        resetBtn:SetPoint("BOTTOM", settingsPanel, "BOTTOM", 0, 10)

        -- Toggle panel on gear click
        gearBtn:SetScript("OnClick", function()
            settingsPanel:SetShown(not settingsPanel:IsShown())
        end)
    end

    -- Hide settings panel when character frame closes (outside creation block)
    CharacterFrame:HookScript("OnHide", function()
        if (frameState[CharacterFrame] or EMPTY).settingsPanel then
            (frameState[CharacterFrame] or EMPTY).settingsPanel:Hide()
        end
    end)
end

---------------------------------------------------------------------------
-- Event frame for initialization
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
eventFrame:RegisterEvent("SOCKET_INFO_UPDATE")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UNIT_STATS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:RegisterEvent("PVP_MATCH_ACTIVE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        -- Note: Blizzard_InspectUI is now hooked by qui_inspect.lua
        if arg1 == "Blizzard_CharacterFrame" then
            C_Timer.After(0.1, function()
                HookCharacterFrame()
            end)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UPDATE_INVENTORY_DURABILITY" or
           event == "SOCKET_INFO_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" or
           event == "UNIT_STATS" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" or
           event == "ENCOUNTER_START" or event == "ENCOUNTER_END" or
           event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED" or
           event == "CHALLENGE_MODE_RESET" or event == "PVP_MATCH_ACTIVE" then
        ScheduleUpdate()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Delayed init check
        C_Timer.After(0.5, function()
            if CharacterFrame then
                HookCharacterFrame()
                ScheduleUpdate()
            end
        end)
    elseif event == "INSPECT_READY" then
        ScheduleUpdate()
    end
end)

---------------------------------------------------------------------------
-- Global refresh function
---------------------------------------------------------------------------
_G.QUI_RefreshCharacterPane = function()
    ScheduleUpdate()
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------
QUI.CharacterPane = {
    Refresh = function()
        ScheduleUpdate()
    end,

    GetSettings = GetSettings,
}

ns.CharacterPane = QUI.CharacterPane

---------------------------------------------------------------------------
-- Shared exports for qui_inspect.lua
-- These functions/tables are exported for the inspect module to use
---------------------------------------------------------------------------
QUI.CharacterShared = {
    -- Constants
    EQUIPMENT_SLOTS = EQUIPMENT_SLOTS,
    C = C,

    -- Settings/DB access
    GetSettings = GetSettings,
    GetGlobalFont = GetGlobalFont,

    -- Core functions
    CreateSlotOverlay = CreateSlotOverlay,
    UpdateAllSlotOverlays = UpdateAllSlotOverlays,
    ScheduleUpdate = ScheduleUpdate,
    GetSlotItemLevel = GetSlotItemLevel,
    GetILvlColor = GetILvlColor,
    AbbreviateClassName = AbbreviateClassName,
}

if ns.Registry then
    ns.Registry:Register("character", {
        refresh = _G.QUI_RefreshCharacterPane,
        priority = 45,
        group = "character",
        importCategories = { "skinning" },
    })
end
