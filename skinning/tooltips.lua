local addonName, ns = ...
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Applies QUI theme to Blizzard tooltips (GameTooltip, ItemRefTooltip, etc.)
---------------------------------------------------------------------------

-- Get skinning colors (uses unified color system)
local function GetTooltipColors()
    return Helpers.GetSkinColors()
end

-- Get tooltip settings
local function GetSettings()
    local QUICore = _G.QUI and _G.QUI.QUICore
    return QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.tooltip
end

-- Check if tooltip skinning is enabled
local function IsEnabled()
    local settings = GetSettings()
    return settings and settings.skinTooltips
end

-- Check if health bar hiding is enabled
local function ShouldHideHealthBar()
    local settings = GetSettings()
    return settings and settings.hideHealthBar
end

-- Backdrop definition for tooltips
local tooltipBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
}

-- Store original backdrops for unskinning
local originalBackdrops = {}

-- Apply QUI skin to a tooltip frame
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if tooltip.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetTooltipColors()

    -- Store original backdrop info if available
    if tooltip.GetBackdrop then
        local ok, backdrop = pcall(tooltip.GetBackdrop, tooltip)
        if ok and backdrop then
            originalBackdrops[tooltip] = backdrop
        end
    end

    -- Apply BackdropTemplate if needed
    if not tooltip.SetBackdrop then
        Mixin(tooltip, BackdropTemplateMixin)
    end

    -- Set the QUI backdrop
    tooltip:SetBackdrop(tooltipBackdrop)
    tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
    tooltip:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide NineSlice if present (Blizzard's default tooltip border)
    if tooltip.NineSlice then
        tooltip.NineSlice:SetAlpha(0)
    end

    tooltip.quiSkinned = true
    tooltip.quiColors = { sr, sg, sb, sa, bgr, bgg, bgb, bga }
end

-- Update colors on an already-skinned tooltip
local function UpdateTooltipColors(tooltip)
    if not tooltip or not tooltip.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetTooltipColors()

    if tooltip.SetBackdropColor then
        tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
    end
    if tooltip.SetBackdropBorderColor then
        tooltip:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    tooltip.quiColors = { sr, sg, sb, sa, bgr, bgg, bgb, bga }
end

-- List of tooltips to skin
local tooltipsToSkin = {
    "GameTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "EmbeddedItemTooltip",
    "GameTooltipTooltip",
    "WorldMapTooltip",
    "WorldMapCompareTooltip1",
    "WorldMapCompareTooltip2",
    "SmallTextTooltip",
    "ReputationParagonTooltip",
    "NamePlateTooltip",
    "QueueStatusFrame",
    "FloatingGarrisonFollowerTooltip",
    "FloatingGarrisonFollowerAbilityTooltip",
    "FloatingGarrisonMissionTooltip",
    "GarrisonFollowerTooltip",
    "GarrisonFollowerAbilityTooltip",
    "GarrisonMissionTooltip",
    "BattlePetTooltip",
    "FloatingBattlePetTooltip",
    "PetBattlePrimaryUnitTooltip",
    "PetBattlePrimaryAbilityTooltip",
    "FloatingPetBattleAbilityTooltip",
    "IMECandidatesFrame",
}

-- Skin all known tooltips
local function SkinAllTooltips()
    if not IsEnabled() then return end

    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip then
            SkinTooltip(tooltip)
        end
    end
end

-- Refresh colors on all skinned tooltips
local function RefreshAllTooltipColors()
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip and tooltip.quiSkinned then
            UpdateTooltipColors(tooltip)
        end
    end
end

-- Hook OnShow to ensure colors stay applied (some tooltips reset on show)
local function HookTooltipOnShow(tooltip)
    if not tooltip or tooltip.quiOnShowHooked then return end

    tooltip:HookScript("OnShow", function(self)
        if not IsEnabled() then return end
        if not self.quiSkinned then
            SkinTooltip(self)
        else
            -- Re-apply colors in case they were reset
            local colors = self.quiColors
            if colors and self.SetBackdropColor and self.SetBackdropBorderColor then
                local sr, sg, sb, sa, bgr, bgg, bgb, bga = unpack(colors)
                self:SetBackdropColor(bgr, bgg, bgb, bga)
                self:SetBackdropBorderColor(sr, sg, sb, sa)
            end

            -- Keep NineSlice hidden
            if self.NineSlice then
                self.NineSlice:SetAlpha(0)
            end
        end
    end)

    tooltip.quiOnShowHooked = true
end

-- Hook all tooltips for OnShow
local function HookAllTooltips()
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip then
            HookTooltipOnShow(tooltip)
        end
    end
end

-- Hide the health bar on a tooltip if option is enabled
local function UpdateHealthBarVisibility(tooltip)
    if not ShouldHideHealthBar() then return end
    if not tooltip then return end

    local statusBar = tooltip.StatusBar or (tooltip == GameTooltip and GameTooltipStatusBar)
    if statusBar then
        statusBar:Hide()
    end
end

-- Handle dynamically created tooltips via TooltipDataProcessor
local function SetupTooltipPostProcessor()
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then
        return
    end

    -- This fires after any tooltip is populated with data
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if not IsEnabled() then return end
        if tooltip and not tooltip.quiSkinned then
            SkinTooltip(tooltip)
            HookTooltipOnShow(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
        if not IsEnabled() then return end
        if tooltip and not tooltip.quiSkinned then
            SkinTooltip(tooltip)
            HookTooltipOnShow(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if IsEnabled() and tooltip and not tooltip.quiSkinned then
            SkinTooltip(tooltip)
            HookTooltipOnShow(tooltip)
        end
        -- Health bar hiding works independently of skinning
        UpdateHealthBarVisibility(tooltip)
    end)
end

-- Setup health bar hook (works independently of skinning)
local function SetupHealthBarHook()
    if not GameTooltip then return end

    -- Hook the status bar's Show method to catch when it tries to display
    local statusBar = GameTooltip.StatusBar or GameTooltipStatusBar
    if statusBar then
        hooksecurefunc(statusBar, "Show", function(self)
            if ShouldHideHealthBar() then
                self:Hide()
            end
        end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Defer slightly to ensure all tooltips are created
        C_Timer.After(0.5, function()
            -- Skinning (only if enabled)
            if IsEnabled() then
                SkinAllTooltips()
                HookAllTooltips()
            end

            -- Post processor handles both skinning and health bar
            SetupTooltipPostProcessor()

            -- Health bar hook works independently of skinning
            SetupHealthBarHook()
        end)
    end
end)

-- Expose refresh function globally for live color updates
_G.QUI_RefreshTooltipSkinColors = RefreshAllTooltipColors
