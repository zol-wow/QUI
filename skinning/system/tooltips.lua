local addonName, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Applies QUI theme to Blizzard tooltips (GameTooltip, ItemRefTooltip, etc.)
--
-- Since WoW 9.1.5, GameTooltip (via SharedTooltipTemplate) no longer
-- inherits BackdropTemplate. tooltip:SetBackdrop() is nil.
-- Instead, tooltips use a NineSlice sub-frame for their appearance.
-- We skin tooltips by manipulating the NineSlice directly:
--   NineSlice:SetCenterColor(r, g, b, a)  — background
--   NineSlice:SetBorderColor(r, g, b, a)  — border
-- And by applying flat textures to the NineSlice pieces for the QUI look.
---------------------------------------------------------------------------

local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Memory optimization: reusable backdrop table for legacy BackdropTemplate tooltips.
-- Updated in-place instead of allocating a new table on every tooltip show.
local _cachedBackdropInsets = { left = 1, right = 1, top = 1, bottom = 1 }
local _cachedBackdrop = {
    bgFile = FLAT_TEXTURE,
    edgeFile = FLAT_TEXTURE,
    edgeSize = 1,
    insets = _cachedBackdropInsets,
}

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
    local tooltipName
    if tooltip.GetName then
        local ok, name = pcall(tooltip.GetName, tooltip)
        if ok then
            tooltipName = name
        end
    end

    if tooltipName and tooltip.NumLines then
        local lineCount = 0
        local ok, count = pcall(tooltip.NumLines, tooltip)
        if ok then
            lineCount = count or 0
        end
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
    -- Use select() iteration to avoid allocating a temporary 30-element table per call
    local numRegions = tooltip.GetNumRegions and tooltip:GetNumRegions() or 0
    local isFirst = true
    for i = 1, numRegions do
        local region = select(i, tooltip:GetRegions())
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

---------------------------------------------------------------------------
-- NineSlice-based tooltip skinning
-- Works with modern WoW tooltips that use NineSlice instead of BackdropTemplate.
-- Also falls back to SetBackdrop for any tooltips that still support it.
---------------------------------------------------------------------------

-- TAINT SAFETY: Track skinned state in local tables, NOT on Blizzard frames.
local skinnedTooltips = Helpers.CreateStateTable()   -- tooltip → true
local hookedTooltips = Helpers.CreateStateTable()    -- tooltip → true (OnShow hooked)
local pendingCombatSkinTooltips = Helpers.CreateStateTable() -- tooltip → true (deferred reskin queued)

-- NineSlice piece names used by Blizzard tooltips
local NINE_SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

-- Apply flat QUI textures to all NineSlice pieces
local function ApplyFlatNineSlice(nineSlice, edgeSize)
    if not nineSlice then return end

    local core = GetCore()
    local px = core and core.GetPixelSize and core:GetPixelSize(nineSlice) or 1
    local edge = (edgeSize or 1) * px

    for _, pieceName in ipairs(NINE_SLICE_PIECES) do
        local piece = nineSlice[pieceName]
        if piece and piece.SetTexture then
            piece:SetTexture(FLAT_TEXTURE)
            piece:SetTexCoord(0, 1, 0, 1)
        end
    end

    -- Size the corners and edges to match our border thickness
    local tl = nineSlice.TopLeftCorner
    local tr = nineSlice.TopRightCorner
    local bl = nineSlice.BottomLeftCorner
    local br = nineSlice.BottomRightCorner

    if tl then tl:SetSize(edge, edge) end
    if tr then tr:SetSize(edge, edge) end
    if bl then bl:SetSize(edge, edge) end
    if br then br:SetSize(edge, edge) end

    -- Edge thickness
    local te = nineSlice.TopEdge
    local be = nineSlice.BottomEdge
    local le = nineSlice.LeftEdge
    local re = nineSlice.RightEdge

    if te then te:SetHeight(edge) end
    if be then be:SetHeight(edge) end
    if le then le:SetWidth(edge) end
    if re then re:SetWidth(edge) end

    -- Inset the center piece so the background doesn't bleed past the border.
    -- By default Blizzard anchors Center to fill between corners, but with thin
    -- borders the background can extend beyond the visible edge.
    local center = nineSlice.Center
    if center then
        center:ClearAllPoints()
        center:SetPoint("TOPLEFT", nineSlice, "TOPLEFT", edge, -edge)
        center:SetPoint("BOTTOMRIGHT", nineSlice, "BOTTOMRIGHT", -edge, edge)
    end
end

-- Apply QUI skin colors to a tooltip's NineSlice
local function ApplyNineSliceColors(nineSlice, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not nineSlice then return end

    -- Background (center piece)
    if nineSlice.SetCenterColor then
        nineSlice:SetCenterColor(bgr, bgg, bgb, bga)
    elseif nineSlice.Center then
        nineSlice.Center:SetVertexColor(bgr, bgg, bgb, bga)
    end

    -- Border (edge + corner pieces)
    if nineSlice.SetBorderColor then
        nineSlice:SetBorderColor(sr, sg, sb, sa)
    else
        -- Manual fallback: color each border piece individually
        for _, pieceName in ipairs(NINE_SLICE_PIECES) do
            if pieceName ~= "Center" then
                local piece = nineSlice[pieceName]
                if piece and piece.SetVertexColor then
                    piece:SetVertexColor(sr, sg, sb, sa)
                end
            end
        end
    end
end

-- Prevent Blizzard from re-applying the default NineSlice layout on Show
-- NOTE: Only call outside combat — tooltip OnShow runs inside a securecall chain
-- and modifying frame properties during combat propagates taint to line FontStrings.
local function ClearNineSliceLayoutInfo(tooltip)
    if not tooltip then return end

    -- Clear layout info that Blizzard uses to re-apply defaults
    local ns = tooltip.NineSlice
    if ns then
        ns.layoutType = nil
        ns.layoutTextureKit = nil
        ns.backdropInfo = nil
    end

    tooltip.layoutType = nil
    tooltip.layoutTextureKit = nil
    tooltip.backdropInfo = nil
end

-- Full skin application for a tooltip
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if skinnedTooltips[tooltip] then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    local ns = tooltip.NineSlice
    if ns then
        -- NineSlice path (modern WoW 9.1.5+)
        ClearNineSliceLayoutInfo(tooltip)
        ApplyFlatNineSlice(ns, thickness)
        ApplyNineSliceColors(ns, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        ns:Show()
    elseif tooltip.SetBackdrop then
        -- Legacy BackdropTemplate path (fallback)
        -- Memory optimization: reuse cached backdrop table (updated in-place)
        local core = GetCore()
        local px = core and core.GetPixelSize and core:GetPixelSize(tooltip) or 1
        local edge = thickness * px
        _cachedBackdrop.edgeSize = edge
        _cachedBackdropInsets.left = edge
        _cachedBackdropInsets.right = edge
        _cachedBackdropInsets.top = edge
        _cachedBackdropInsets.bottom = edge
        tooltip:SetBackdrop(_cachedBackdrop)
        tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
        tooltip:SetBackdropBorderColor(sr, sg, sb, sa)
    else
        -- No NineSlice and no BackdropTemplate — cannot skin this tooltip
        return
    end

    skinnedTooltips[tooltip] = true
end

-- Re-apply skin to an already-skinned tooltip (called on every Show)
local function ReapplySkin(tooltip)
    if not tooltip then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    local ns = tooltip.NineSlice
    if ns then
        ClearNineSliceLayoutInfo(tooltip)
        -- Re-apply flat textures/geometry every show because Blizzard can restore
        -- default rounded NineSlice piece settings between tooltip displays.
        ApplyFlatNineSlice(ns, thickness)
        ApplyNineSliceColors(ns, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        ns:Show()
    elseif tooltip.SetBackdrop then
        -- Memory optimization: reuse cached backdrop table (updated in-place)
        local core = GetCore()
        local px = core and core.GetPixelSize and core:GetPixelSize(tooltip) or 1
        local edge = thickness * px
        _cachedBackdrop.edgeSize = edge
        _cachedBackdropInsets.left = edge
        _cachedBackdropInsets.right = edge
        _cachedBackdropInsets.top = edge
        _cachedBackdropInsets.bottom = edge
        tooltip:SetBackdrop(_cachedBackdrop)
        tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
        tooltip:SetBackdropBorderColor(sr, sg, sb, sa)
    end
end

-- During combat, avoid mutating tooltip internals directly inside the secure
-- OnShow/PostCall chain. Queue skinning to the next frame instead.
local function QueueCombatTooltipSkin(tooltip)
    if not tooltip or pendingCombatSkinTooltips[tooltip] then return end
    pendingCombatSkinTooltips[tooltip] = true

    C_Timer.After(0, function()
        pendingCombatSkinTooltips[tooltip] = nil
        if not tooltip then return end
        if tooltip.IsShown and not tooltip:IsShown() then return end
        if not IsEnabled() then return end

        if not skinnedTooltips[tooltip] then
            SkinTooltip(tooltip)
        else
            ReapplySkin(tooltip)
        end
    end)
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
    -- NOTE: NamePlateTooltip intentionally omitted. Skinning it taints the frame
    -- in Midnight's taint model, causing nameplate errors.
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

-- Refresh colors/geometry on all skinned tooltips
local function RefreshAllTooltipColors()
    -- Refresh named tooltips from the static list
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip and skinnedTooltips[tooltip] then
            ReapplySkin(tooltip)
        end
    end
    -- Also refresh dynamically skinned tooltips (via TooltipDataProcessor)
    for tooltip in pairs(skinnedTooltips) do
        ReapplySkin(tooltip)
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

-- Hook OnShow to ensure skin stays applied (Blizzard resets NineSlice on show)
local function HookTooltipOnShow(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end

    -- NOTE: Tooltip OnShow runs synchronously — deferring causes unskinned tooltip flash.
    -- Tooltip skinning is NOT in the Edit Mode taint chain.
    tooltip:HookScript("OnShow", function(self)
        -- In combat, queue skinning out of the secure OnShow chain to avoid
        -- taint propagation to tooltip line FontStrings.
        if InCombatLockdown() then
            if IsEnabled() then
                QueueCombatTooltipSkin(self)
            end
            return
        end

        ApplyTooltipFontSize()
        ApplyTooltipFontSizeToFrame(self)
        if not IsEnabled() then return end
        if not skinnedTooltips[self] then
            SkinTooltip(self)
        else
            -- Re-apply full skin — Blizzard resets NineSlice layout on every Show
            ReapplySkin(self)
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
    if InCombatLockdown() then return end

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
    -- NOTE: These callbacks run inside Blizzard's securecallfunction chain.
    -- Modifying tooltip line properties (SetFont, SetTextColor, etc.) during combat
    -- taints the line objects and breaks other addons (e.g. Altoholic).
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if not tooltip then return end
        HookTooltipOnShow(tooltip)
        if not InCombatLockdown() then
            ApplyTooltipFontSizeToFrame(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
        elseif IsEnabled() then
            QueueCombatTooltipSkin(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
        if not tooltip then return end
        HookTooltipOnShow(tooltip)
        if not InCombatLockdown() then
            ApplyTooltipFontSizeToFrame(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
        elseif IsEnabled() then
            QueueCombatTooltipSkin(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not tooltip then return end
        HookTooltipOnShow(tooltip)
        if not InCombatLockdown() then
            ApplyTooltipFontSizeToFrame(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
        elseif IsEnabled() then
            QueueCombatTooltipSkin(tooltip)
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
-- This rebuilds textures (for thickness changes) and recolors
_G.QUI_RefreshTooltipSkinColors = RefreshAllTooltipColors
_G.QUI_RefreshTooltipFontSize = RefreshAllTooltipFonts
