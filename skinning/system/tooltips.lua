local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

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

-- Check if tooltip skinning is enabled (requires master tooltip toggle AND skinTooltips)
local function IsEnabled()
    local settings = GetSettings()
    return settings and settings.enabled and settings.skinTooltips
end

-- Check if health bar hiding is enabled (requires master tooltip toggle)
local function ShouldHideHealthBar()
    local settings = GetSettings()
    return settings and settings.enabled and settings.hideHealthBar
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

-- NOTE: Do NOT modify the shared global font objects (GameTooltipText,
-- GameTooltipTextSmall, GameTooltipHeaderText) here.  Blizzard's UIWidget
-- templates (e.g. UIWidgetTemplateTextWithState) inherit their FontStrings
-- from these same objects.  Calling SetFont() on the shared template taints
-- every derived FontString, so GetStringHeight() returns a secret value and
-- Blizzard's widget Setup code errors out.
-- Font sizing is applied per-tooltip via ApplyTooltipFontSizeToFrame() instead.

local function SetFontStringSize(fontString, size)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    if fontString.IsForbidden and fontString:IsForbidden() then return end
    local ok, fontPath, _, flags = pcall(fontString.GetFont, fontString)
    if not ok or not fontPath then
        fontPath = Helpers.GetGeneralFont and Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
        flags = Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline() or ""
    end
    pcall(fontString.SetFont, fontString, fontPath, size, flags or "")
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
            if tooltip.GetLeftLine and tooltip.GetRightLine then
                for i = 1, lineCount do
                    local left = tooltip:GetLeftLine(i)
                    local right = tooltip:GetRightLine(i)
                    local size = (i == 1) and headerSize or baseSize
                    SetFontStringSize(left, size)
                    SetFontStringSize(right, size)
                end
            else
                -- Fallback for non-GameTooltip frames without GetLeftLine/GetRightLine
                for i = 1, lineCount do
                    local left = _G[tooltipName .. "TextLeft" .. i]
                    local right = _G[tooltipName .. "TextRight" .. i]
                    local size = (i == 1) and headerSize or baseSize
                    SetFontStringSize(left, size)
                    SetFontStringSize(right, size)
                end
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

-- NineSlice piece names used by Blizzard tooltips
local NINE_SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

-- NineSlice color locking state (weak-keyed to avoid preventing GC)
local colorLockedNineSlices = Helpers.CreateStateTable()
local isApplyingLockedColors = false

-- Apply flat QUI textures to all NineSlice pieces
local function ApplyFlatNineSlice(nineSlice, edgeSize)
    if not nineSlice then return end
    if nineSlice.IsForbidden and nineSlice:IsForbidden() then return end

    local px = SkinBase.GetPixelSize(nineSlice, 1)
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

    isApplyingLockedColors = true

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

    isApplyingLockedColors = false
end

-- Lock NineSlice colors so Blizzard overrides (e.g. quality-colored borders
-- for rare/epic items) get immediately reverted to QUI's skin colors.
local function LockNineSliceColors(nineSlice)
    if not nineSlice or colorLockedNineSlices[nineSlice] then return end
    colorLockedNineSlices[nineSlice] = true

    if nineSlice.SetCenterColor then
        hooksecurefunc(nineSlice, "SetCenterColor", function(self)
            if isApplyingLockedColors or not IsEnabled() then return end
            isApplyingLockedColors = true
            local _, _, _, _, bgr, bgg, bgb, bga = GetEffectiveColors()
            pcall(self.SetCenterColor, self, bgr, bgg, bgb, bga)
            isApplyingLockedColors = false
        end)
    end

    if nineSlice.SetBorderColor then
        hooksecurefunc(nineSlice, "SetBorderColor", function(self)
            if isApplyingLockedColors or not IsEnabled() then return end
            isApplyingLockedColors = true
            local sr, sg, sb, sa = GetEffectiveColors()
            pcall(self.SetBorderColor, self, sr, sg, sb, sa)
            isApplyingLockedColors = false
        end)
    end
end

-- Full skin application for a tooltip (called outside combat only)
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if skinnedTooltips[tooltip] then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    local ns = tooltip.NineSlice
    if ns then
        -- Clear Blizzard's cached layout properties on the NineSlice to prevent
        -- re-application of default styles during tooltip resize/re-layout.
        -- TAINT SAFETY: Only clear on the NineSlice sub-frame, NEVER on the
        -- tooltip frame itself. Writing to tooltip.layoutType/layoutTextureKit
        -- taints the GameTooltip frame. During combat, Blizzard's widget code
        -- (GameTooltip_AddWidgetSet → RegisterForWidgetSet → ProcessWidget →
        -- UIWidgetTemplateTextWithState:Setup) reads tainted keys, propagating
        -- taint to the execution context. GetStringHeight() then returns a
        -- secret value, breaking widget arithmetic. The SharedTooltip_SetBackdropStyle
        -- hook and OnShow hook handle re-styling without needing tooltip-level clears.
        ns.layoutType = nil
        ns.layoutTextureKit = nil
        ns.backdropInfo = nil

        -- NineSlice path (modern WoW 9.1.5+)
        ApplyFlatNineSlice(ns, thickness)
        ApplyNineSliceColors(ns, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        LockNineSliceColors(ns)
        pcall(ns.Show, ns)
    elseif tooltip.SetBackdrop then
        -- Legacy BackdropTemplate path (fallback)
        -- Memory optimization: reuse cached backdrop table (updated in-place)
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = thickness * px
        _cachedBackdrop.edgeSize = edge
        _cachedBackdropInsets.left = edge
        _cachedBackdropInsets.right = edge
        _cachedBackdropInsets.top = edge
        _cachedBackdropInsets.bottom = edge
        pcall(tooltip.SetBackdrop, tooltip, _cachedBackdrop)
        pcall(tooltip.SetBackdropColor, tooltip, bgr, bgg, bgb, bga)
        pcall(tooltip.SetBackdropBorderColor, tooltip, sr, sg, sb, sa)
    else
        -- No NineSlice and no BackdropTemplate — cannot skin this tooltip
        return
    end

    skinnedTooltips[tooltip] = true
end

-- Re-apply skin to an already-skinned tooltip (called on every Show, out of combat)
local function ReapplySkin(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    local ns = tooltip.NineSlice
    if ns then
        -- Re-apply flat textures/geometry every show because Blizzard can restore
        -- default rounded NineSlice piece settings between tooltip displays.
        ApplyFlatNineSlice(ns, thickness)
        ApplyNineSliceColors(ns, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        pcall(ns.Show, ns)
    elseif tooltip.SetBackdrop then
        -- Memory optimization: reuse cached backdrop table (updated in-place)
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = thickness * px
        _cachedBackdrop.edgeSize = edge
        _cachedBackdropInsets.left = edge
        _cachedBackdropInsets.right = edge
        _cachedBackdropInsets.top = edge
        _cachedBackdropInsets.bottom = edge
        pcall(tooltip.SetBackdrop, tooltip, _cachedBackdrop)
        pcall(tooltip.SetBackdropColor, tooltip, bgr, bgg, bgb, bga)
        pcall(tooltip.SetBackdropBorderColor, tooltip, sr, sg, sb, sa)
    end
end

---------------------------------------------------------------------------
-- Cached pixel size for combat-safe NineSlice geometry.
-- GetEffectiveScale() returns secret values during combat, so
-- SkinBase.GetPixelSize() falls back to 1 (wrong — makes borders huge).
-- We cache the correct pixel size on UI_SCALE_CHANGED (same pattern as
-- the cached UIParent scale in tooltip_provider.lua). NineSlice inherits
-- UIParent's scale chain (tooltips don't use custom SetScale), so using
-- UIParent-based pixel size is correct.
---------------------------------------------------------------------------
local cachedPixelSize = 1

local function UpdateCachedPixelSize()
    local core = GetCore()
    if core and core.GetPixelSize then
        local px = core:GetPixelSize() -- nil frame → UIParent scale
        if type(px) == "number" and px > 0 then
            cachedPixelSize = px
        end
    end
end

local pixelCacheFrame = CreateFrame("Frame")
pixelCacheFrame:RegisterEvent("UI_SCALE_CHANGED")
pixelCacheFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
pixelCacheFrame:RegisterEvent("ADDON_LOADED")
pixelCacheFrame:SetScript("OnEvent", UpdateCachedPixelSize)

---------------------------------------------------------------------------
-- Combat-safe reapply: full NineSlice skin using cached pixel size.
-- All operations are C-side visual calls on the NineSlice sub-frame
-- (not on GameTooltip itself), so they don't propagate taint to widget
-- containers. Geometry uses cachedPixelSize instead of live
-- GetEffectiveScale() to avoid secret values.
---------------------------------------------------------------------------
local function CombatSafeReapply(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    local ns = tooltip.NineSlice
    if not ns then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()
    local edge = (thickness or 1) * cachedPixelSize

    -- Flat textures (Blizzard may have re-applied default textures via
    -- SharedTooltip_SetBackdropStyle between tooltip shows)
    for _, pieceName in ipairs(NINE_SLICE_PIECES) do
        local piece = ns[pieceName]
        if piece and piece.SetTexture then
            pcall(piece.SetTexture, piece, FLAT_TEXTURE)
            pcall(piece.SetTexCoord, piece, 0, 1, 0, 1)
        end
    end

    -- Geometry (corners, edges, center inset)
    local tl, tr = ns.TopLeftCorner, ns.TopRightCorner
    local bl, br = ns.BottomLeftCorner, ns.BottomRightCorner
    if tl then pcall(tl.SetSize, tl, edge, edge) end
    if tr then pcall(tr.SetSize, tr, edge, edge) end
    if bl then pcall(bl.SetSize, bl, edge, edge) end
    if br then pcall(br.SetSize, br, edge, edge) end

    local te, be = ns.TopEdge, ns.BottomEdge
    local le, re = ns.LeftEdge, ns.RightEdge
    if te then pcall(te.SetHeight, te, edge) end
    if be then pcall(be.SetHeight, be, edge) end
    if le then pcall(le.SetWidth, le, edge) end
    if re then pcall(re.SetWidth, re, edge) end

    local center = ns.Center
    if center then
        pcall(center.ClearAllPoints, center)
        pcall(center.SetPoint, center, "TOPLEFT", ns, "TOPLEFT", edge, -edge)
        pcall(center.SetPoint, center, "BOTTOMRIGHT", ns, "BOTTOMRIGHT", -edge, edge)
    end

    -- Colors
    ApplyNineSliceColors(ns, sr, sg, sb, sa, bgr, bgg, bgb, bga)
end

---------------------------------------------------------------------------
-- Embedded tooltip border stripping
-- EmbeddedItemTooltip lives inside GameTooltip for World Quest item rewards.
-- Blizzard applies GAME_TOOLTIP_BACKDROP_STYLE_EMBEDDED via
-- SharedTooltip_SetBackdropStyle, creating a visible "box within a box."
-- We hook that function and hide the NineSlice entirely (alpha 0) so the
-- embedded tooltip blends seamlessly into the already-skinned parent.
-- SetAlpha is C-side and taint-safe even during combat.
---------------------------------------------------------------------------

local function StripEmbeddedBorder(frame)
    if not frame then return end
    local nineSlice = frame.NineSlice
    if nineSlice then
        pcall(nineSlice.SetAlpha, nineSlice, 0)
    end
    -- Also strip ItemTooltip sub-frame border if present
    if frame.ItemTooltip then
        local itemNS = frame.ItemTooltip.NineSlice
        if itemNS then
            pcall(itemNS.SetAlpha, itemNS, 0)
        end
    end
end

local function RestoreEmbeddedBorder(frame)
    if not frame then return end
    local nineSlice = frame.NineSlice
    if nineSlice then
        pcall(nineSlice.SetAlpha, nineSlice, 1)
    end
    if frame.ItemTooltip then
        local itemNS = frame.ItemTooltip.NineSlice
        if itemNS then
            pcall(itemNS.SetAlpha, itemNS, 1)
        end
    end
end

local function SetupEmbeddedTooltipHooks()
    -- Hook SharedTooltip_SetBackdropStyle to catch Blizzard re-applying the
    -- embedded backdrop style. Fires AFTER Blizzard's function, giving us
    -- the last word on the NineSlice appearance.
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip, style, isEmbedded)
            if not IsEnabled() then return end
            if not tooltip then return end
            if isEmbedded or tooltip.IsEmbedded then
                -- Embedded tooltip (e.g. EmbeddedItemTooltip): hide its NineSlice.
                -- SetAlpha is C-side, safe in combat.
                StripEmbeddedBorder(tooltip)
            elseif InCombatLockdown() then
                -- Combat: textures + colors only (no geometry — GetEffectiveScale
                -- can return secret values). These are C-side visual ops on the
                -- NineSlice sub-frame, not on GameTooltip itself.
                pcall(CombatSafeReapply, tooltip)
            elseif skinnedTooltips[tooltip] then
                -- Out of combat: full reapply including geometry.
                pcall(ReapplySkin, tooltip)
            end
        end)
    end

    -- TAINT SAFETY: Use hooksecurefunc on Show instead of HookScript("OnShow")
    -- to prevent tainting the frame's script handler (same rationale as
    -- HookTooltipOnShow above).
    -- SetAlpha is C-side, safe in combat — no need for InCombatLockdown guard.
    if EmbeddedItemTooltip then
        hooksecurefunc(EmbeddedItemTooltip, "Show", function(self)
            if not IsEnabled() then return end
            StripEmbeddedBorder(self)
        end)
        if IsEnabled() then
            StripEmbeddedBorder(EmbeddedItemTooltip)
        end
    end

    if GameTooltip and GameTooltip.ItemTooltip and GameTooltip.ItemTooltip.NineSlice then
        hooksecurefunc(GameTooltip.ItemTooltip, "Show", function(self)
            if not IsEnabled() then return end
            local nineSlice = self.NineSlice
            if nineSlice then
                pcall(nineSlice.SetAlpha, nineSlice, 0)
            end
        end)
    end
end

-- GameTooltip-family frames
local gameTooltipFamily = {
    "GameTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "GameTooltipTooltip",
    "WorldMapTooltip",
    "WorldMapCompareTooltip1",
    "WorldMapCompareTooltip2",
    "SmallTextTooltip",
    "ReputationParagonTooltip",
    "NamePlateTooltip",
}

-- Specialized frames with custom layouts — always skinned (no taint risk)
local specializedTooltips = {
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

-- Build the active tooltip list
local tooltipsToSkin = {}
local function RebuildTooltipList()
    wipe(tooltipsToSkin)
    for _, name in ipairs(specializedTooltips) do
        tooltipsToSkin[#tooltipsToSkin + 1] = name
    end
    for _, name in ipairs(gameTooltipFamily) do
        -- NamePlateTooltip excluded (causes taint)
        if name ~= "NamePlateTooltip" then
            tooltipsToSkin[#tooltipsToSkin + 1] = name
        end
    end
end

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
    -- Defer to next tooltip show if in combat — C-side calls (SetTexture, SetFont)
    -- propagate taint through the securecall chain to other addons' tooltip hooks.
    if InCombatLockdown() then return end
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

    -- Handle embedded tooltip border visibility on settings change
    if EmbeddedItemTooltip then
        if IsEnabled() then
            StripEmbeddedBorder(EmbeddedItemTooltip)
        else
            RestoreEmbeddedBorder(EmbeddedItemTooltip)
        end
    end
end

local function RefreshAllTooltipFonts()
    -- Defer to next tooltip show if in combat — font mutations propagate taint.
    if InCombatLockdown() then return end
    for _, name in ipairs(tooltipsToSkin) do
        local tooltip = _G[name]
        if tooltip then
            ApplyTooltipFontSizeToFrame(tooltip)
        end
    end
end

-- Hook Show to ensure skin stays applied (Blizzard resets NineSlice on show)
local function HookTooltipOnShow(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end

    -- TAINT SAFETY: Do NOT install ANY hooks (HookScript, hooksecurefunc) on
    -- GameTooltip itself. In Midnight's taint model, both HookScript("OnShow")
    -- and hooksecurefunc(frame, "Show") modify the frame's dispatch tables,
    -- permanently tainting the GameTooltip frame. When the world map's secure
    -- context (secureexecuterange → AreaPoiUtil → GameTooltip_AddWidgetSet →
    -- RegisterForWidgetSet → ProcessWidget) uses GameTooltip, it encounters
    -- the tainted frame, causing UIWidget arithmetic errors, InsertFrame
    -- failures, and ADDON_ACTION_BLOCKED on SetPassThroughButtons.
    --
    -- GameTooltip is skinned via:
    --   1. SharedTooltip_SetBackdropStyle hooksecurefunc (global fn, taint-safe)
    --   2. TooltipDataProcessor callbacks (securecallfunction, taint-safe)
    --   3. GameTooltipVisibilityWatcher OnUpdate (separate frame, no taint on GT)
    -- Font sizing for GameTooltip uses the same OnUpdate watcher.
    if tooltip == GameTooltip then
        hookedTooltips[tooltip] = true
        return
    end

    hooksecurefunc(tooltip, "Show", function(self)
        if not IsEnabled() then return end

        if InCombatLockdown() then
            -- Combat: textures + colors only (C-side visual ops on NineSlice).
            -- Skip geometry (GetEffectiveScale can return secret values) and
            -- font sizing (modifying FontStrings propagates taint).
            pcall(CombatSafeReapply, self)
            return
        end

        -- Out of combat: defer full skin work out of the hooksecurefunc
        -- execution context.  Running synchronously here means GetWidth()/
        -- GetHeight() calls execute in addon context, triggering OnSizeChanged
        -- on child frames and producing secret value arithmetic errors.
        C_Timer.After(0, function()
            if not self:IsShown() then return end
            if InCombatLockdown() then
                pcall(CombatSafeReapply, self)
                return
            end
            pcall(ApplyTooltipFontSizeToFrame, self)
            if not skinnedTooltips[self] then
                pcall(SkinTooltip, self)
            else
                pcall(ReapplySkin, self)
            end
        end)
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
    if statusBar and not (statusBar.IsForbidden and statusBar:IsForbidden()) then
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
    -- Helper: defer font sizing out of the securecall chain to avoid tainting
    -- tooltip width calculations (see OnShow hook comment for details).
    local function DeferFontSizing(tooltip)
        if not IsEnabled() then return end
        C_Timer.After(0, function()
            if tooltip and tooltip.IsShown and tooltip:IsShown() then
                pcall(ApplyTooltipFontSizeToFrame, tooltip)
            end
        end)
    end

    -- TAINT SAFETY: HookTooltipOnShow calls HookScript which modifies the
    -- frame's script table.  Inside Blizzard's securecallfunction chain
    -- (TooltipDataProcessor callbacks), this taints the execution context
    -- and causes subsequent SetAttribute calls to fail with "Attempt to
    -- access forbidden object."  Defer hook installation out of the secure
    -- chain during combat.  The hook is a one-time install (guarded by
    -- hookedTooltips), so the 1-frame deferral is harmless.
    local function SafeHookTooltipOnShow(tooltip)
        if hookedTooltips[tooltip] then return end
        if InCombatLockdown() then
            C_Timer.After(0, function()
                if tooltip then HookTooltipOnShow(tooltip) end
            end)
        else
            HookTooltipOnShow(tooltip)
        end
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        if InCombatLockdown() then
            pcall(CombatSafeReapply, tooltip)
        else
            DeferFontSizing(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        if InCombatLockdown() then
            pcall(CombatSafeReapply, tooltip)
        else
            DeferFontSizing(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        if InCombatLockdown() then
            pcall(CombatSafeReapply, tooltip)
        else
            DeferFontSizing(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
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
            -- TAINT SAFETY: Combat check first to avoid tainting execution context.
            if InCombatLockdown() then return end
            if ShouldHideHealthBar() then
                Helpers.SafeHide(self)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        do
            -----------------------------------------------------------------
            -- TAINT SAFETY: Do NOT replace global Blizzard functions with
            -- addon wrappers (pcall or otherwise). Direct replacement
            -- permanently taints the function in Midnight's taint model,
            -- causing ADDON_ACTION_BLOCKED errors (SetPassThroughButtons,
            -- Edit Mode, etc.) and secret-value arithmetic failures
            -- (MoneyFrame_Update) throughout unrelated secure code paths.
            --
            -- EmbeddedItemTooltip_UpdateSize, GameTooltip_AddWidgetSet,
            -- and widget container RegisterForWidgetSet wrappers were
            -- previously here but removed — same lesson as the
            -- MoneyFrame_Update/SetTooltipMoney wrappers removed from
            -- modules/qol/tooltips.lua. If Blizzard's own functions error
            -- on secret values, that is a Blizzard bug.
            --
            -- The UIWidget taint that prompted these wrappers is now
            -- addressed at the source: core/font_system.lua skips
            -- UIWidget frames (widgetType / RegisterForWidgetSet) during
            -- recursive font application, and tooltip OnShow defers all
            -- work during combat (InCombatLockdown guard).
            -----------------------------------------------------------------

            -- Build the tooltip list based on active engine
            RebuildTooltipList()

            -----------------------------------------------------------------
            -- GameTooltip visibility watcher (OnUpdate on a SEPARATE frame).
            -----------------------------------------------------------------
            local gtWatcher = CreateFrame("Frame")
            local gtWasShown = GameTooltip:IsShown()
            gtWatcher:SetScript("OnUpdate", function()
                local shown = GameTooltip:IsShown()
                if shown and not gtWasShown then
                    -- GameTooltip just became visible
                    if not IsEnabled() then
                        -- nothing
                    elseif InCombatLockdown() then
                        -- Combat: textures + colors only (C-side ops on NineSlice).
                        -- Skip geometry and font sizing during combat.
                        pcall(CombatSafeReapply, GameTooltip)
                    else
                        if not skinnedTooltips[GameTooltip] then
                            pcall(SkinTooltip, GameTooltip)
                        else
                            pcall(ReapplySkin, GameTooltip)
                        end
                        -- Defer font sizing to avoid tainting FontString metrics
                        -- while Blizzard's tooltip chain is still running.
                        C_Timer.After(0, function()
                            if GameTooltip:IsShown() then
                                pcall(ApplyTooltipFontSizeToFrame, GameTooltip)
                            end
                        end)
                    end
                end
                gtWasShown = shown
            end)

            -- All tooltip modifications gated by master toggle + skinTooltips
            if not IsEnabled() then
                -- Still hook Show so enabling live takes effect on next show
                HookAllTooltips()
                SetupEmbeddedTooltipHooks()
                SetupHealthBarHook()
                SetupTooltipPostProcessor()
                return
            end

            RefreshAllTooltipFonts()
            HookAllTooltips()
            SkinAllTooltips()

            SetupEmbeddedTooltipHooks()
            SetupHealthBarHook()

            -- Post processor handles both skinning and health bar
            SetupTooltipPostProcessor()
        end
    end
end)

-- Expose refresh functions on the addon namespace for live color updates.
-- Avoids writing to _G which can introduce taint if Blizzard code touches those keys
-- during secure execution.
ns.QUI_RefreshTooltipSkinColors = RefreshAllTooltipColors
ns.QUI_RefreshTooltipFontSize = RefreshAllTooltipFonts
