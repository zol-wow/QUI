local addonName, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Applies QUI theme to Blizzard tooltips (GameTooltip, ItemRefTooltip, etc.)
---------------------------------------------------------------------------

-- Get skinning colors (uses unified color system)
local function GetTooltipColors()
    local sr, sg, sb, sa = Helpers.GetSkinBorderColor()
    local bgr, bgg, bgb, bga = Helpers.GetSkinBgColor()
    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

-- Get tooltip settings
local function GetSettings()
    local core = GetCore()
    return core and core.db and core.db.profile and core.db.profile.tooltip
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

local DEFAULT_TOOLTIP_FONT_SIZE = 12
local MIN_TOOLTIP_FONT_SIZE = 8
local MAX_TOOLTIP_FONT_SIZE = 24

local function GetEffectiveFontSize()
    local settings = GetSettings()
    local size = (settings and settings.fontSize) or DEFAULT_TOOLTIP_FONT_SIZE
    size = tonumber(size) or DEFAULT_TOOLTIP_FONT_SIZE
    size = math.floor(size + 0.5)
    if size < MIN_TOOLTIP_FONT_SIZE then
        size = MIN_TOOLTIP_FONT_SIZE
    elseif size > MAX_TOOLTIP_FONT_SIZE then
        size = MAX_TOOLTIP_FONT_SIZE
    end
    return size
end

local function SetTooltipFontObjectSize(fontObject, size)
    if not fontObject or not fontObject.GetFont or not fontObject.SetFont then return end
    local fontPath, _, flags = fontObject:GetFont()
    if not fontPath then
        fontPath = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
        flags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
    end
    fontObject:SetFont(fontPath, size, flags or "")
end

local function ApplyTooltipFontSize()
    local baseSize = GetEffectiveFontSize()
    SetTooltipFontObjectSize(_G.GameTooltipText, baseSize)
    SetTooltipFontObjectSize(_G.GameTooltipTextSmall, math.max(baseSize - 1, MIN_TOOLTIP_FONT_SIZE))
    SetTooltipFontObjectSize(_G.GameTooltipHeaderText, baseSize + 2)
end

local function SetFontStringSize(fontString, size)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    local fontPath, _, flags = fontString:GetFont()
    if not fontPath then
        fontPath = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
        flags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
    end
    fontString:SetFont(fontPath, size, flags or "")
end

local function ApplyTooltipFontSizeToFrame(tooltip)
    if not tooltip then return end
    local baseSize = GetEffectiveFontSize()
    local headerSize = baseSize + 2
    local tooltipName = tooltip.GetName and tooltip:GetName()

    if tooltipName and tooltip.NumLines then
        local lineCount = tooltip:NumLines() or 0
        if lineCount > 0 then
            for i = 1, lineCount do
                local left = _G[tooltipName .. "TextLeft" .. i]
                local right = _G[tooltipName .. "TextRight" .. i]
                local size = (i == 1) and headerSize or baseSize
                SetFontStringSize(left, size)
                SetFontStringSize(right, size)
            end
            return
        end
    end

    -- Fallback for unnamed tooltips and named-but-empty tooltips
    local regions = { tooltip:GetRegions() }
    local isFirst = true
    for _, region in ipairs(regions) do
        if region and region.IsObjectType and region:IsObjectType("FontString") then
            SetFontStringSize(region, isFirst and headerSize or baseSize)
            isFirst = false
        end
    end
end

-- Get player class color from RAID_CLASS_COLORS
local function GetPlayerClassColor()
    local _, classToken = UnitClass("player")
    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        local c = RAID_CLASS_COLORS[classToken]
        return c.r, c.g, c.b, 1
    end
    return 0.2, 1.0, 0.6, 1 -- fallback to mint
end

-- Build a backdrop table with the given edge size (pixel-perfect)
local function BuildTooltipBackdrop(edgeSize, frame)
    edgeSize = edgeSize or 1
    local core = GetCore()
    local px = core and core.GetPixelSize and core:GetPixelSize(frame) or 1
    local edge = edgeSize * px
    return {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edge,
        insets = { left = edge, right = edge, top = edge, bottom = edge }
    }
end

-- Resolve the effective colors from settings (or fall back to skin colors)
local function GetEffectiveColors()
    local settings = GetSettings()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetTooltipColors()

    if settings then
        -- Background color
        if settings.bgColor then
            bgr = settings.bgColor[1] or bgr
            bgg = settings.bgColor[2] or bgg
            bgb = settings.bgColor[3] or bgb
        end
        -- Background opacity
        if settings.bgOpacity then
            bga = settings.bgOpacity
        end

        -- Border color
        if settings.borderUseClassColor then
            sr, sg, sb, sa = GetPlayerClassColor()
        elseif settings.borderUseAccentColor then
            local QUI = _G.QUI
            if QUI and QUI.GetAddonAccentColor then
                sr, sg, sb, sa = QUI:GetAddonAccentColor()
            end
        elseif settings.borderColor then
            sr = settings.borderColor[1] or sr
            sg = settings.borderColor[2] or sg
            sb = settings.borderColor[3] or sb
            sa = settings.borderColor[4] or sa
        end

        -- Border visibility
        if settings.showBorder == false then
            sr, sg, sb, sa = 0, 0, 0, 0
        end
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

-- Get the effective border thickness from settings
local function GetEffectiveBorderThickness()
    local settings = GetSettings()
    if settings and settings.borderThickness then
        return settings.borderThickness
    end
    return 1
end

-- Store original backdrops for unskinning
local originalBackdrops = {}

-- TAINT SAFETY: Track skinned state in local tables, NOT on Blizzard frames.
-- Writing addon properties (quiSkinned, quiColors, etc.) to secure frames
-- taints them in Midnight's taint model.
local skinnedTooltips = setmetatable({}, { __mode = "k" })   -- tooltip → { colors = {...} }
local hookedTooltips = setmetatable({}, { __mode = "k" })    -- tooltip → true (OnShow hooked)

-- Apply QUI skin to a tooltip frame
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if skinnedTooltips[tooltip] then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    -- Store original backdrop info if available
    if tooltip.GetBackdrop then
        local ok, backdrop = pcall(tooltip.GetBackdrop, tooltip)
        if ok and backdrop then
            originalBackdrops[tooltip] = backdrop
        end
    end

    -- Skip tooltips that don't have BackdropTemplate — Mixin() from addon context
    -- would taint the tooltip permanently in Midnight's taint model.
    -- In 12.0, virtually all tooltips already have BackdropTemplate.
    if not tooltip.SetBackdrop then
        return
    end

    -- Set the QUI backdrop
    tooltip:SetBackdrop(BuildTooltipBackdrop(thickness, tooltip))
    tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
    tooltip:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide NineSlice if present (Blizzard's default tooltip border)
    if tooltip.NineSlice then
        tooltip.NineSlice:SetAlpha(0)
    end

    skinnedTooltips[tooltip] = { colors = { sr, sg, sb, sa, bgr, bgg, bgb, bga } }
end

-- Update colors on an already-skinned tooltip
local function UpdateTooltipColors(tooltip)
    if not tooltip or not skinnedTooltips[tooltip] then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()

    if tooltip.SetBackdropColor then
        tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
    end
    if tooltip.SetBackdropBorderColor then
        tooltip:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    skinnedTooltips[tooltip].colors = { sr, sg, sb, sa, bgr, bgg, bgb, bga }
end

-- Re-skin a tooltip (rebuild backdrop for thickness changes)
local function ReskinTooltip(tooltip)
    if not tooltip or not skinnedTooltips[tooltip] then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    -- Skip if no SetBackdrop — Mixin() from addon context taints (see SkinTooltip)
    if not tooltip.SetBackdrop then
        return
    end

    -- Rebuild backdrop with current thickness
    tooltip:SetBackdrop(BuildTooltipBackdrop(thickness, tooltip))
    tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
    tooltip:SetBackdropBorderColor(sr, sg, sb, sa)

    skinnedTooltips[tooltip].colors = { sr, sg, sb, sa, bgr, bgg, bgb, bga }
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
    -- NOTE: NamePlateTooltip intentionally omitted. Skinning it (Mixin,
    -- SetBackdrop, property writes) taints the frame in Midnight's taint
    -- model, causing nameplate errors (SetNamePlateHitTestFrame, etc.).
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

-- Refresh colors on all skinned tooltips (rebuilds backdrop for thickness)
local function RefreshAllTooltipColors()
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip and skinnedTooltips[tooltip] then
            ReskinTooltip(tooltip)
        end
    end
end

local function RefreshAllTooltipFonts()
    ApplyTooltipFontSize()
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip then
            ApplyTooltipFontSizeToFrame(tooltip)
        end
    end
end

-- Hook OnShow to ensure colors stay applied (some tooltips reset on show)
local function HookTooltipOnShow(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end

    -- NOTE: Tooltip OnShow runs synchronously — deferring causes unskinned tooltip flash.
    -- Tooltip skinning is NOT in the Edit Mode taint chain.
    tooltip:HookScript("OnShow", function(self)
        ApplyTooltipFontSize()
        ApplyTooltipFontSizeToFrame(self)
        if not IsEnabled() then return end
        if not skinnedTooltips[self] then
            SkinTooltip(self)
        else
            -- Re-apply colors in case they were reset
            local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
            if self.SetBackdropColor and self.SetBackdropBorderColor then
                self:SetBackdropColor(bgr, bgg, bgb, bga)
                self:SetBackdropBorderColor(sr, sg, sb, sa)
            end

            -- Keep NineSlice hidden
            if self.NineSlice then
                self.NineSlice:SetAlpha(0)
            end
        end
    end)

    hookedTooltips[tooltip] = true
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
        if not tooltip then return end
        HookTooltipOnShow(tooltip)
        ApplyTooltipFontSizeToFrame(tooltip)
        if IsEnabled() and not skinnedTooltips[tooltip] then
            SkinTooltip(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
        if not tooltip then return end
        HookTooltipOnShow(tooltip)
        ApplyTooltipFontSizeToFrame(tooltip)
        if IsEnabled() and not skinnedTooltips[tooltip] then
            SkinTooltip(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not tooltip then return end
        HookTooltipOnShow(tooltip)
        ApplyTooltipFontSizeToFrame(tooltip)
        if IsEnabled() and not skinnedTooltips[tooltip] then
            SkinTooltip(tooltip)
        end
        -- Health bar hiding works independently of skinning
        UpdateHealthBarVisibility(tooltip)
    end)
end

-- Setup health bar hook (works independently of skinning)
local function SetupHealthBarHook()
    if not GameTooltip then return end

    -- Hook the status bar's Show method to catch when it tries to display
    -- NOTE: Synchronous — deferring causes visible health bar flash before hide.
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
            -- Font size is independent from skinning and applies globally to tooltips
            RefreshAllTooltipFonts()
            HookAllTooltips()

            -- Skinning (only if enabled)
            if IsEnabled() then
                SkinAllTooltips()
            end

            -- Post processor handles both skinning and health bar
            SetupTooltipPostProcessor()

            -- Health bar hook works independently of skinning
            SetupHealthBarHook()
        end)
    end
end)

-- Expose refresh function globally for live color updates
-- This rebuilds backdrops (for thickness changes) and recolors
_G.QUI_RefreshTooltipSkinColors = RefreshAllTooltipColors
_G.QUI_RefreshTooltipFontSize = RefreshAllTooltipFonts
