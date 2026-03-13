local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Applies QUI theme to Blizzard tooltips (GameTooltip, ItemRefTooltip, etc.)
--
-- TAINT-SAFE APPROACH: NineSlice piece textures are stripped (region ops)
-- and layout keys cleared (Lua writes). Backdrop is applied directly to
-- the tooltip frame via BackdropTemplateMixin. This avoids calling C-side
-- WRITE methods (SetAlpha, SetSize, SetPoint) on the NineSlice frame,
-- which would taint GetWidth()/GetHeight() and break Blizzard's
-- Backdrop.lua arithmetic (SetupTextureCoordinates on Show).
---------------------------------------------------------------------------

local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Per-tooltip backdrop info tables. BackdropTemplateMixin:SetBackdrop stores
-- a REFERENCE to the backdrop table (not a copy). A shared table causes one
-- tooltip's edgeSize to overwrite another's when OnBackdropSizeChanged fires
-- asynchronously — the border renders at the wrong size (often sub-pixel and
-- invisible). Each tooltip gets its own table, auto-cleaned via weak keys.
local tooltipBackdrops = Helpers.CreateStateTable()
local tooltipBorders = Helpers.CreateStateTable()

local function GetTooltipBackdrop(tooltip)
    local info = tooltipBackdrops[tooltip]
    if not info then
        local insets = { left = 1, right = 1, top = 1, bottom = 1 }
        info = {
            bgFile = FLAT_TEXTURE,
            edgeFile = FLAT_TEXTURE,
            edgeSize = 1,
            insets = insets,
        }
        tooltipBackdrops[tooltip] = info
    end
    return info
end

local function GetTooltipBorder(tooltip)
    local border = tooltipBorders[tooltip]
    if border then return border end
    if not tooltip or not tooltip.CreateTexture then return nil end

    border = {
        top = tooltip:CreateTexture(nil, "BORDER"),
        bottom = tooltip:CreateTexture(nil, "BORDER"),
        left = tooltip:CreateTexture(nil, "BORDER"),
        right = tooltip:CreateTexture(nil, "BORDER"),
    }

    local core = GetCore and GetCore()
    for _, edge in pairs(border) do
        edge:SetTexture(FLAT_TEXTURE)
        if core and core.ApplyPixelSnapping then
            pcall(core.ApplyPixelSnapping, core, edge)
        end
    end

    tooltipBorders[tooltip] = border
    return border
end

-- Snap an edge size to the nearest physical pixel boundary so thin borders
-- always render as whole pixels. Without this, fractional virtual-coord sizes
-- can round to 0 pixels at certain UI scales, making borders invisible.
local function SnapToPixel(tooltip, edge)
    if not PixelUtil or not PixelUtil.GetNearestPixelSize then return edge end
    local ok, scale = pcall(tooltip.GetEffectiveScale, tooltip)
    if not ok or type(scale) ~= "number" or scale <= 0 then return edge end
    if Helpers.IsSecretValue and Helpers.IsSecretValue(scale) then return edge end
    return PixelUtil.GetNearestPixelSize(edge, scale)
end

-- Snap the shown tooltip rect to the pixel grid so the far edges of a 1px
-- backdrop do not land on fractional coordinates and disappear intermittently.
-- This only mutates the tooltip frame itself, never its NineSlice child.
local function SnapTooltipRect(tooltip)
    if not tooltip or not tooltip.SetSize or not tooltip.GetWidth or not tooltip.GetHeight then return end
    local core = GetCore and GetCore()
    if not core then return end

    if core.ApplyPixelSnapping then
        pcall(core.ApplyPixelSnapping, core, tooltip)
    end

    if not core.PixelRound then return end

    local okW, width = pcall(tooltip.GetWidth, tooltip)
    local okH, height = pcall(tooltip.GetHeight, tooltip)
    if not okW or not okH then return end
    if type(width) ~= "number" or type(height) ~= "number" then return end
    if width <= 0 or height <= 0 then return end
    if Helpers.IsSecretValue and (Helpers.IsSecretValue(width) or Helpers.IsSecretValue(height)) then return end

    local snappedWidth = core:PixelRound(width, tooltip)
    local snappedHeight = core:PixelRound(height, tooltip)
    if snappedWidth <= 0 or snappedHeight <= 0 then return end

    if math.abs(snappedWidth - width) > 0.001 or math.abs(snappedHeight - height) > 0.001 then
        pcall(tooltip.SetSize, tooltip, snappedWidth, snappedHeight)
    end
end

local function ApplyTooltipBorder(tooltip, edgeSize, sr, sg, sb, sa)
    local border = GetTooltipBorder(tooltip)
    if not border then return end

    border.top:ClearAllPoints()
    border.top:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", 0, 0)
    border.top:SetHeight(edgeSize)

    border.bottom:ClearAllPoints()
    border.bottom:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(edgeSize)

    border.left:ClearAllPoints()
    border.left:SetPoint("TOPLEFT", border.top, "BOTTOMLEFT", 0, 0)
    border.left:SetPoint("BOTTOMLEFT", border.bottom, "TOPLEFT", 0, 0)
    border.left:SetWidth(edgeSize)

    border.right:ClearAllPoints()
    border.right:SetPoint("TOPRIGHT", border.top, "BOTTOMRIGHT", 0, 0)
    border.right:SetPoint("BOTTOMRIGHT", border.bottom, "TOPRIGHT", 0, 0)
    border.right:SetWidth(edgeSize)

    for _, edge in pairs(border) do
        edge:SetVertexColor(sr or 1, sg or 1, sb or 1, sa or 1)
    end
end

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
-- Tooltip skinning (strip NineSlice + backdrop on tooltip frame)
--
-- NineSlice pieces are stripped via SetTexture/SetAtlas on texture REGIONS
-- (does not taint the parent frame's geometry). Layout keys are cleared
-- via Lua table writes (taints those specific keys, NOT C-side geometry).
-- Backdrop is applied to the tooltip frame itself — BACKGROUND draw layer
-- renders below text at ARTWORK, guaranteed by same-frame draw ordering.
--
-- CRITICAL: Never call C-side WRITE methods (SetAlpha, SetSize, SetWidth,
-- SetHeight, SetPoint) on Blizzard's NineSlice frame. These taint the
-- frame's execution context, causing GetWidth()/GetHeight() to return
-- secret values and breaking Blizzard's Backdrop.lua arithmetic.
-- Lua table writes and texture region ops are safe.
---------------------------------------------------------------------------

-- TAINT SAFETY: Track skinned state in local tables, NOT on Blizzard frames.
local skinnedTooltips = Helpers.CreateStateTable()   -- tooltip → true
local hookedTooltips = Helpers.CreateStateTable()    -- tooltip → true (OnShow hooked)

-- NineSlice piece names (standard 9-slice layout)
local NINE_SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center"
}

-- Strip NineSlice piece textures. These are texture REGIONS, not frames —
-- SetTexture/SetAtlas on regions does not taint the parent frame's geometry.
local function StripNineSlicePieces(nineSlice)
    if not nineSlice then return end
    for _, key in ipairs(NINE_SLICE_PIECES) do
        local piece = nineSlice[key]
        if piece then
            if piece.SetTexture then pcall(piece.SetTexture, piece, nil) end
            if piece.SetAtlas then pcall(piece.SetAtlas, piece, "") end
        end
    end
end

-- Disable Blizzard's automatic NineSlice layout. Lua table writes only —
-- taints these specific keys but NOT C-side geometry (GetWidth/GetHeight).
-- Prevents Blizzard from re-applying default NineSlice styles on show.
local function DisableNineSliceLayout(nineSlice)
    if not nineSlice then return end
    nineSlice.layoutType = nil
    nineSlice.layoutTextureKit = nil
    nineSlice.backdropInfo = nil
end

-- Ensure tooltip has BackdropTemplateMixin (NineSlice tooltips may not).
-- Mixin writes function refs to the tooltip's Lua table — taints those keys
-- but Blizzard's NineSlice code doesn't read them, so this is safe.
local function EnsureBackdropTemplate(tooltip)
    if tooltip.SetBackdrop then return end
    Mixin(tooltip, BackdropTemplateMixin)
end

-- Apply QUI's flat backdrop directly to the tooltip frame.
-- BACKGROUND draw layer renders below ARTWORK (text) — same-frame guarantee.
-- Uses per-tooltip backdrop table so OnBackdropSizeChanged reads the correct edgeSize.
local function ApplyTooltipBackdrop(tooltip, edgeSize, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local backdrop = GetTooltipBackdrop(tooltip)
    backdrop.edgeSize = edgeSize
    backdrop.insets.left = edgeSize
    backdrop.insets.right = edgeSize
    backdrop.insets.top = edgeSize
    backdrop.insets.bottom = edgeSize
    pcall(tooltip.SetBackdrop, tooltip, backdrop)
    pcall(tooltip.SetBackdropColor, tooltip, bgr, bgg, bgb, bga)
    -- Keep the backdrop border itself transparent and render the visible border
    -- with addon-owned textures. This avoids inconsistent edge rasterization on
    -- Blizzard tooltip backdrops while preserving background insets/padding.
    pcall(tooltip.SetBackdropBorderColor, tooltip, 0, 0, 0, 0)
    ApplyTooltipBorder(tooltip, edgeSize, sr, sg, sb, sa)
end

---------------------------------------------------------------------------
-- NineSlice "locking" hooks. After QUI strips a tooltip's NineSlice,
-- Blizzard can restore it via code paths we don't intercept (ApplyLayout,
-- SetBackdrop on the NineSlice child). These hooks fire AFTER Blizzard's
-- call and re-strip, giving QUI the last word. Without them, shopping/
-- comparison tooltips and dynamically-created tooltips (e.g. from other
-- addons) show a mix of QUI's backdrop and Blizzard's restored NineSlice.
---------------------------------------------------------------------------
local hookedNineSlices = Helpers.CreateStateTable()
local nineSliceLockActive = false

local function HookNineSliceLocking(tooltip)
    local ns = tooltip.NineSlice
    if not ns or hookedNineSlices[ns] then return end
    hookedNineSlices[ns] = true

    -- Hook SetBackdrop: Blizzard may apply a BackdropTemplate backdrop to the
    -- NineSlice. Re-strip pieces and clear the backdrop after.
    if ns.SetBackdrop then
        hooksecurefunc(ns, "SetBackdrop", function(self)
            if nineSliceLockActive then return end
            if not IsEnabled() then return end
            if not skinnedTooltips[tooltip] then return end
            nineSliceLockActive = true
            DisableNineSliceLayout(self)
            StripNineSlicePieces(self)
            if self.ClearBackdrop then
                pcall(self.ClearBackdrop, self)
            end
            nineSliceLockActive = false
        end)
    end

    -- Hook SetBackdropBorderColor: prevent Blizzard from making stripped
    -- NineSlice border pieces visible again with a non-zero alpha.
    if ns.SetBackdropBorderColor then
        hooksecurefunc(ns, "SetBackdropBorderColor", function(self)
            if nineSliceLockActive then return end
            if not IsEnabled() then return end
            if not skinnedTooltips[tooltip] then return end
            nineSliceLockActive = true
            pcall(self.SetBackdropBorderColor, self, 0, 0, 0, 0)
            nineSliceLockActive = false
        end)
    end
end

-- Full skin application for a tooltip (called outside combat only)
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if skinnedTooltips[tooltip] then return end

    SnapTooltipRect(tooltip)

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    local ns = tooltip.NineSlice
    if ns then
        -- Strip NineSlice: disable layout (Lua writes) + clear textures (region ops)
        DisableNineSliceLayout(ns)
        StripNineSlicePieces(ns)
        if ns.ClearBackdrop then pcall(ns.ClearBackdrop, ns) end
        -- Install locking hooks to prevent Blizzard from restoring NineSlice
        HookNineSliceLocking(tooltip)
        -- Apply backdrop to tooltip frame (text renders on top via draw layers)
        EnsureBackdropTemplate(tooltip)
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = SnapToPixel(tooltip, (thickness or 1) * px)
        ApplyTooltipBackdrop(tooltip, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    elseif tooltip.SetBackdrop then
        -- Legacy BackdropTemplate path (fallback)
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = SnapToPixel(tooltip, thickness * px)
        ApplyTooltipBackdrop(tooltip, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
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

    SnapTooltipRect(tooltip)

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    local ns = tooltip.NineSlice
    if ns then
        -- Re-strip NineSlice (Blizzard may restore styles between shows)
        DisableNineSliceLayout(ns)
        StripNineSlicePieces(ns)
        if ns.ClearBackdrop then pcall(ns.ClearBackdrop, ns) end
        -- Refresh backdrop on tooltip
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = SnapToPixel(tooltip, (thickness or 1) * px)
        ApplyTooltipBackdrop(tooltip, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    elseif tooltip.SetBackdrop then
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = SnapToPixel(tooltip, thickness * px)
        ApplyTooltipBackdrop(tooltip, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
end

---------------------------------------------------------------------------
-- Combat-safe reapply: re-strip NineSlice + refresh backdrop colors.
-- NineSlice ops are Lua writes + region texture ops (safe in combat).
-- Backdrop color ops are on a tooltip with BackdropTemplateMixin (safe).
---------------------------------------------------------------------------
local function CombatSafeReapply(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end
    if not skinnedTooltips[tooltip] then return end

    -- Re-strip NineSlice (Lua writes + region ops — safe in combat)
    local ns = tooltip.NineSlice
    if ns then
        DisableNineSliceLayout(ns)
        StripNineSlicePieces(ns)
        if ns.ClearBackdrop then pcall(ns.ClearBackdrop, ns) end
    end

    -- Refresh backdrop colors on tooltip
    if tooltip.SetBackdropColor then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
        pcall(tooltip.SetBackdropColor, tooltip, bgr, bgg, bgb, bga)
        pcall(tooltip.SetBackdropBorderColor, tooltip, 0, 0, 0, 0)
        local thickness = GetEffectiveBorderThickness()
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = SnapToPixel(tooltip, (thickness or 1) * px)
        ApplyTooltipBorder(tooltip, edge, sr, sg, sb, sa)
    end
end

---------------------------------------------------------------------------
-- Embedded tooltip border stripping
-- EmbeddedItemTooltip lives inside GameTooltip for World Quest item rewards.
-- Blizzard applies GAME_TOOLTIP_BACKDROP_STYLE_EMBEDDED via
-- SharedTooltip_SetBackdropStyle, creating a visible "box within a box."
-- We strip the embedded NineSlice pieces (region ops — taint-safe) so the
-- embedded tooltip blends seamlessly into the already-skinned parent.
---------------------------------------------------------------------------

local function StripEmbeddedBorder(frame)
    if not frame then return end
    local ns = frame.NineSlice
    if ns then
        DisableNineSliceLayout(ns)
        StripNineSlicePieces(ns)
        if ns.ClearBackdrop then pcall(ns.ClearBackdrop, ns) end
    end
    if frame.ItemTooltip then
        local itemNS = frame.ItemTooltip.NineSlice
        if itemNS then
            DisableNineSliceLayout(itemNS)
            StripNineSlicePieces(itemNS)
            if itemNS.ClearBackdrop then pcall(itemNS.ClearBackdrop, itemNS) end
        end
    end
end

local function RestoreEmbeddedBorder(frame)
    -- NineSlice pieces are restored naturally by Blizzard's
    -- SharedTooltip_SetBackdropStyle on the next tooltip show.
    -- No explicit restore needed.
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
                -- Embedded tooltip: cover its NineSlice with matching background.
                StripEmbeddedBorder(tooltip)
            elseif InCombatLockdown() then
                -- Combat: refresh overlay colors only.
                pcall(CombatSafeReapply, tooltip)
            elseif skinnedTooltips[tooltip] then
                -- Out of combat: full reapply (overlay backdrop + colors).
                pcall(ReapplySkin, tooltip)
            else
                -- First encounter with this tooltip — skin it now.
                pcall(SkinTooltip, tooltip)
            end
        end)
    end

    -- TAINT SAFETY: Use hooksecurefunc on Show instead of HookScript("OnShow")
    -- to prevent tainting the frame's script handler.
    -- StripEmbeddedBorder uses addon-owned overlay — safe in combat.
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
            local itemNS = self.NineSlice
            if itemNS then
                DisableNineSliceLayout(itemNS)
                StripNineSlicePieces(itemNS)
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
            -- Combat: refresh overlay colors only.
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
                        -- Combat: refresh overlay colors only.
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
