local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Applies QUI theme to Blizzard tooltips (GameTooltip, ItemRefTooltip, etc.)
--
-- TAINT-SAFE OVERLAY APPROACH: Blizzard's NineSlice sub-frame is hidden
-- via SetAlpha(0) (C-side, no geometry taint). A QUI-owned BackdropTemplate
-- overlay frame renders the flat border/background instead. This avoids
-- writing geometry (SetSize/SetPoint) to Blizzard NineSlice pieces, which
-- would taint their dimensions and cause secret-value arithmetic errors
-- in Blizzard code (e.g. EmbeddedItemTooltip_UpdateSize -> GetWidth()).
---------------------------------------------------------------------------

local FLAT_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local issecretvalue = issecretvalue

-- Named NineSlice border parts for targeted clearing.
-- More reliable than iterating GetRegions() which may miss Center or
-- return parts in unpredictable order.
local NINE_SLICE_BORDER_PARTS = {
    "TopLeftCorner", "TopRightCorner",
    "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge",
    "LeftEdge", "RightEdge",
}

-- Per-tooltip backdrop info tables. BackdropTemplateMixin:SetBackdrop stores
-- a REFERENCE to the backdrop table (not a copy). A shared table causes one
-- tooltip's edgeSize to overwrite another's when OnBackdropSizeChanged fires
-- asynchronously — the border renders at the wrong size (often sub-pixel and
-- invisible). Each tooltip gets its own table, auto-cleaned via weak keys.
local tooltipBackdrops = Helpers.CreateStateTable()
local overlayBackdrops = Helpers.CreateStateTable()
local tooltipBorders = Helpers.CreateStateTable()

local function CreateBackdropInfo()
    local insets = { left = 1, right = 1, top = 1, bottom = 1 }
    return {
        bgFile = FLAT_TEXTURE,
        edgeFile = FLAT_TEXTURE,
        edgeSize = 1,
        insets = insets,
    }
end

local function GetTooltipBackdrop(tooltip)
    local info = tooltipBackdrops[tooltip]
    if not info then
        info = CreateBackdropInfo()
        tooltipBackdrops[tooltip] = info
    end
    return info
end

local function GetOverlayBackdrop(skinFrame)
    local info = overlayBackdrops[skinFrame]
    if not info then
        info = CreateBackdropInfo()
        overlayBackdrops[skinFrame] = info
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
    return 0.376, 0.647, 0.980, 1 -- fallback to sky blue
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
-- Overlay-based tooltip skinning
-- Blizzard's NineSlice is hidden (SetAlpha 0) and a QUI-owned
-- BackdropTemplate frame renders the flat border/background instead.
-- This avoids writing geometry to Blizzard frames (taint-safe).
-- Falls back to SetBackdrop for tooltips that still use BackdropTemplate.
---------------------------------------------------------------------------

-- TAINT SAFETY: Track skinned state in local tables, NOT on Blizzard frames.
local skinnedTooltips = Helpers.CreateStateTable()   -- tooltip → true
local hookedTooltips = Helpers.CreateStateTable()    -- tooltip → true (OnShow hooked)
local reapplyingTooltip = Helpers.CreateStateTable() -- tooltip → true (reentrancy guard)

-- Forward declarations (assigned later, used in closures that run at runtime)
local SafeHookTooltipOnShow
local HookTooltipOnShow

-- QUI-owned overlay frames for tooltip skinning (weak-keyed to allow GC)
local skinFrames = Helpers.CreateStateTable()

-- Hide Blizzard's NineSlice visually without modifying its geometry.
-- SetAlpha is C-side and doesn't taint frame dimensions.
-- Also clears any backdrop set via BackdropTemplateMixin on the NineSlice,
-- which is the primary source of "doubled border" artifacts -- the NineSlice
-- backdrop renders at the NineSlice's frame level (above our overlay at level 0).
local function HideNineSlice(nineSlice)
    if not nineSlice then return end
    pcall(nineSlice.SetAlpha, nineSlice, 0)
    -- Clear BackdropTemplateMixin backdrop on the NineSlice itself.
    if nineSlice.SetBackdrop then
        pcall(nineSlice.SetBackdrop, nineSlice, nil)
    end
    -- Explicitly clear NineSlice.Center (background texture).
    -- Parent SetAlpha(0) should hide children via alpha inheritance, but
    -- WoW 12.0 NineSlice textures can render through parent alpha.
    -- Clearing Center directly ensures the background never bleeds through.
    local center = nineSlice.Center
    if center then
        if center.SetTexture then pcall(center.SetTexture, center, nil) end
        if center.SetAtlas then pcall(center.SetAtlas, center, nil) end
        if center.SetAlpha then pcall(center.SetAlpha, center, 0) end
    end
    -- Hide named border parts explicitly.  More targeted than iterating
    -- GetRegions() which can miss named sub-textures or return parts in
    -- unpredictable order.
    for _, partName in ipairs(NINE_SLICE_BORDER_PARTS) do
        local region = nineSlice[partName]
        if region then
            if region.SetTexture then pcall(region.SetTexture, region, nil) end
            if region.SetAtlas then pcall(region.SetAtlas, region, nil) end
            pcall(region.Hide, region)
        end
    end
end

-- Sync the overlay frame level so its BACKGROUND draw layer covers any
-- backdrop the tooltip frame itself may have (Blizzard can re-apply backdrop
-- styles through code paths we don't hook).  At the same frame level, child
-- BACKGROUND textures render after (on top of) parent BACKGROUND textures,
-- while parent ARTWORK (text) still renders above both.
local function SyncOverlayLevel(skinFrame, tooltip)
    local ok, level = pcall(tooltip.GetFrameLevel, tooltip)
    if not ok or type(level) ~= "number" then return end
    if issecretvalue and issecretvalue(level) then return end
    skinFrame:SetFrameLevel(level)
end

-- Get or create a QUI-owned BackdropTemplate overlay frame for a tooltip.
-- Addon-owned frames are never taint-restricted.
local function GetOrCreateSkinFrame(tooltip)
    if skinFrames[tooltip] then return skinFrames[tooltip] end
    local frame = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    frame:SetAllPoints(tooltip)
    frame.ignoreInLayout = true
    -- Match tooltip's frame level so overlay BACKGROUND covers any backdrop
    -- on the tooltip frame itself, while tooltip ARTWORK (text) renders on top.
    SyncOverlayLevel(frame, tooltip)
    -- Snap overlay to pixel grid so backdrop edges land on exact pixel
    -- boundaries. Without this, a 1-physical-pixel edge can round to 0px
    -- on some sides depending on the tooltip's sub-pixel position.
    if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(true) end
    if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end

    -- TAINT + COLOR SAFETY: Override BackdropTemplate's OnSizeChanged.
    -- 1) Secret-value guard: when the world map's secure context processes
    --    GameTooltip (via AreaPoiUtil), layout propagates to this child.
    --    GetWidth() returns secret values — bail to prevent arithmetic errors.
    -- 2) Color re-application: OnBackdropSizeChanged → SetupPieceVisuals
    --    re-creates backdrop pieces with default WHITE8x8 color but does NOT
    --    re-apply the stored backdropColor/backdropBorderColor. Without this,
    --    any tooltip resize after ApplyOverlayBackdrop (common after combat
    --    ends in raids/instances) leaves the overlay white until /reload.
    frame:SetScript("OnSizeChanged", function(self)
        if issecretvalue then
            local w = self:GetWidth()
            if issecretvalue(w) then return end
        end
        if self.OnBackdropSizeChanged then
            self:OnBackdropSizeChanged()
        end
        -- Re-apply stored colors after piece recreation.
        -- Primary: use BackdropTemplateMixin's backdropColor (set by SetBackdropColor).
        -- Fallback: use _qui* fields stored by ApplyOverlayBackdrop, which survive
        -- SetBackdrop(nil) and cover the case where backdropColor was cleared by an
        -- error between SetBackdrop(info) and SetBackdropColor in ApplyOverlayBackdrop.
        if self.backdropColor then
            self:SetBackdropColor(self.backdropColor:GetRGBA())
        elseif self._quiBgR then
            self:SetBackdropColor(self._quiBgR, self._quiBgG, self._quiBgB, self._quiBgA)
        end
        if self.backdropBorderColor then
            self:SetBackdropBorderColor(self.backdropBorderColor:GetRGBA())
        elseif self._quiBorderR then
            self:SetBackdropBorderColor(self._quiBorderR, self._quiBorderG, self._quiBorderB, self._quiBorderA)
        end
    end)

    skinFrames[tooltip] = frame

    return frame
end

-- Apply QUI backdrop directly to a legacy BackdropTemplate tooltip (no NineSlice).
-- Uses per-tooltip backdrop tables (GetTooltipBackdrop) to avoid cross-tooltip
-- edgeSize overwrites from shared table references.
local function ApplyTooltipBackdrop(tooltip, edgeSize, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local info = GetTooltipBackdrop(tooltip)
    info.edgeSize = edgeSize
    info.insets.left = edgeSize
    info.insets.right = edgeSize
    info.insets.top = edgeSize
    info.insets.bottom = edgeSize
    tooltip:SetBackdrop(nil)
    tooltip:SetBackdrop(info)
    tooltip:SetBackdropColor(bgr, bgg, bgb, bga)
    tooltip:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Apply QUI backdrop to an overlay frame.
-- Uses per-overlay backdrop tables (GetOverlayBackdrop) to avoid the same
-- shared-table reference bug that GetTooltipBackdrop prevents for legacy
-- tooltips: BackdropTemplateMixin stores a REFERENCE, so a shared table
-- causes OnBackdropSizeChanged to read stale edgeSize values from another
-- overlay's update, leaving backdrop pieces at wrong sizes with default
-- WHITE8x8 color (the SetBackdropColor call already returned).
local function ApplyOverlayBackdrop(skinFrame, edgeSize, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local info = GetOverlayBackdrop(skinFrame)
    info.edgeSize = edgeSize
    info.insets.left = edgeSize
    info.insets.right = edgeSize
    info.insets.top = edgeSize
    info.insets.bottom = edgeSize
    -- Store desired colors independently of BackdropTemplateMixin's backdropColor.
    -- SetBackdrop(nil) clears backdropColor; if SetBackdropColor errors (caught by
    -- an outer pcall), backdropColor stays nil and OnSizeChanged can't re-apply.
    -- These fields survive SetBackdrop(nil) and give OnSizeChanged a fallback.
    skinFrame._quiBgR = bgr or 0.05
    skinFrame._quiBgG = bgg or 0.05
    skinFrame._quiBgB = bgb or 0.05
    skinFrame._quiBgA = bga or 0.95
    skinFrame._quiBorderR = sr or 0
    skinFrame._quiBorderG = sg or 0
    skinFrame._quiBorderB = sb or 0
    skinFrame._quiBorderA = sa or 1
    -- Clear first -- SetBackdrop short-circuits when passed the same table
    -- reference, even if the table's contents changed.
    skinFrame:SetBackdrop(nil)
    skinFrame:SetBackdrop(info)
    skinFrame:SetBackdropColor(skinFrame._quiBgR, skinFrame._quiBgG, skinFrame._quiBgB, skinFrame._quiBgA)
    skinFrame:SetBackdropBorderColor(skinFrame._quiBorderR, skinFrame._quiBorderG, skinFrame._quiBorderB, skinFrame._quiBorderA)
end

-- Strip CompareHeader textures on shopping tooltips (TWW 11.2.7+)
-- The CompareHeader ("Equipped" label area) has its own NineSlice/backdrop
-- and child textures that create a visible "header border" on comparison tooltips.
local function StripCompareHeader(tooltip)
    if not tooltip.CompareHeader then return end
    local header = tooltip.CompareHeader
    -- Clear backdrop on the header itself
    if header.SetBackdrop then pcall(header.SetBackdrop, header, nil) end
    -- Hide NineSlice on the header if present
    if header.NineSlice then
        pcall(header.NineSlice.SetAlpha, header.NineSlice, 0)
        if header.NineSlice.SetBackdrop then
            pcall(header.NineSlice.SetBackdrop, header.NineSlice, nil)
        end
    end
    -- Hide any child textures (border pieces, backgrounds).
    -- Use select() to iterate GetRegions without allocating a table.
    local numRegions = select("#", header:GetRegions())
    for i = 1, numRegions do
        local region = select(i, header:GetRegions())
        if region then
            if region.SetTexture then
                pcall(region.SetTexture, region, nil)
            end
            if region.SetAtlas then
                pcall(region.SetAtlas, region, nil)
            end
            if region.SetAlpha then
                pcall(region.SetAlpha, region, 0)
            end
        end
    end
end

-- Full skin application for a tooltip (called outside combat only)
-- GUARD SAFETY: The body is wrapped in pcall so that reapplyingTooltip is
-- always cleared even if an inner operation errors (e.g. taint from the
-- loot roll secure context). Without this, a single error permanently
-- blocks all future skin attempts for the tooltip → white backdrop.
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if skinnedTooltips[tooltip] then return end
    if reapplyingTooltip[tooltip] then return end
    reapplyingTooltip[tooltip] = true

    pcall(function()
        -- Detect embedded tooltips: they live inside another tooltip-like parent
        -- and should NOT get their own QUI overlay (the parent already has one).
        -- Creating an overlay here causes a "border within border" flash on first
        -- show, before StripEmbeddedBorder hides it on the next frame.
        -- IMPORTANT: Only treat as embedded when the parent tooltip is actually
        -- visible. EmbeddedItemTooltip is shown standalone by the objective
        -- tracker (parent GameTooltip is hidden) — it needs its own QUI overlay.
        local parent = tooltip.GetParent and tooltip:GetParent()
        local parentVisible = parent and parent.IsShown and parent:IsShown()
        local isEmbedded = parentVisible
            and (tooltip.IsEmbedded
                or (parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame))
        if isEmbedded then
            local ns = tooltip.NineSlice
            if ns then HideNineSlice(ns) end
            if tooltip.SetBackdrop then pcall(tooltip.SetBackdrop, tooltip, nil) end
            -- Mark as skinned so we don't re-process, but no overlay created
            skinnedTooltips[tooltip] = true
            return
        end

        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
        local thickness = GetEffectiveBorderThickness()

        local ns = tooltip.NineSlice
        if ns then
            -- Clear Blizzard's cached layout properties on the NineSlice to prevent
            -- re-application of default styles during tooltip resize/re-layout.
            -- TAINT SAFETY: Only clear on the NineSlice sub-frame, NEVER on the
            -- tooltip frame itself. Writing to tooltip.layoutType/layoutTextureKit
            -- taints the GameTooltip frame.
            ns.layoutType = nil
            ns.layoutTextureKit = nil
            ns.backdropInfo = nil

            -- Hide Blizzard's NineSlice (no geometry modification -- avoids taint)
            HideNineSlice(ns)

            -- Clear any backdrop on the tooltip frame itself (some tooltips have both
            -- NineSlice AND BackdropTemplate, creating a second border layer).
            if tooltip.SetBackdrop then
                pcall(tooltip.SetBackdrop, tooltip, nil)
            end

            -- Create QUI-owned overlay with BackdropTemplate
            local skinFrame = GetOrCreateSkinFrame(tooltip)
            SyncOverlayLevel(skinFrame, tooltip)
            local px = SkinBase.GetPixelSize(ns, 1)
            -- Minimum 2 physical pixels ensures the border survives pixel-grid
            -- rounding at any tooltip position / effective scale.
            local edge = math.max((thickness or 1), 2) * px
            ApplyOverlayBackdrop(skinFrame, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            -- Ensure overlay is visible (StripEmbeddedBorder may have hidden it
            -- if this tooltip was previously shown in an embedded context).
            skinFrame:Show()
        elseif tooltip.SetBackdrop then
            -- Legacy BackdropTemplate path (fallback)
            local px = SkinBase.GetPixelSize(tooltip, 1)
            local edge = SnapToPixel(tooltip, thickness * px)
            ApplyTooltipBackdrop(tooltip, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        StripCompareHeader(tooltip)
        skinnedTooltips[tooltip] = true
    end)

    reapplyingTooltip[tooltip] = nil
end

-- Re-apply skin to an already-skinned tooltip (called on every Show, out of combat)
-- GUARD SAFETY: Same pcall wrapper as SkinTooltip — ensures reapplyingTooltip is
-- always cleared even if an inner operation errors.
local function ReapplySkin(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if reapplyingTooltip[tooltip] then return end
    reapplyingTooltip[tooltip] = true

    pcall(function()
        -- Embedded tooltips: only strip border, never create overlay.
        -- Only treat as embedded when the parent tooltip is actually visible —
        -- standalone contexts (e.g. objective tracker) need their own overlay.
        local parent = tooltip.GetParent and tooltip:GetParent()
        local parentVisible = parent and parent.IsShown and parent:IsShown()
        local isEmbedded = parentVisible
            and (tooltip.IsEmbedded
                or (parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame))
        if isEmbedded then
            local ns = tooltip.NineSlice
            if ns then HideNineSlice(ns) end
            if tooltip.SetBackdrop then pcall(tooltip.SetBackdrop, tooltip, nil) end
            return
        end

        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
        local thickness = GetEffectiveBorderThickness()

        local ns = tooltip.NineSlice
        if ns then
            -- Clear Blizzard's cached layout properties (prevents NineSlice from
            -- resurfacing after Blizzard re-applies backdrop styles)
            ns.layoutType = nil
            ns.layoutTextureKit = nil
            ns.backdropInfo = nil

            -- Re-hide NineSlice every show (Blizzard may restore styles between displays)
            HideNineSlice(ns)

            -- Clear any backdrop on the tooltip frame itself (belt-and-suspenders
            -- with HideNineSlice — prevents doubled borders on tooltips with both
            -- NineSlice AND BackdropTemplate).
            if tooltip.SetBackdrop then
                pcall(tooltip.SetBackdrop, tooltip, nil)
            end

            -- Update overlay backdrop and colors
            local skinFrame = GetOrCreateSkinFrame(tooltip)
            SyncOverlayLevel(skinFrame, tooltip)
            local px = SkinBase.GetPixelSize(ns, 1)
            local edge = math.max((thickness or 1), 2) * px
            ApplyOverlayBackdrop(skinFrame, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            skinFrame:Show()
        elseif tooltip.SetBackdrop then
            local px = SkinBase.GetPixelSize(tooltip, 1)
            local edge = SnapToPixel(tooltip, thickness * px)
            ApplyTooltipBackdrop(tooltip, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        StripCompareHeader(tooltip)
    end)

    reapplyingTooltip[tooltip] = nil
end

---------------------------------------------------------------------------
-- Combat-safe first skin: create overlay for a never-before-skinned tooltip
-- during combat. All operations target NineSlice (C-side SetAlpha/SetTexture)
-- or addon-owned overlay frames — never taint-restricted.
-- Mirrors the pattern used for EmbeddedItemTooltip first-show-in-combat.
---------------------------------------------------------------------------
local function CombatSafeFirstSkin(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end
    if skinnedTooltips[tooltip] then return end

    local ns = tooltip.NineSlice
    if ns then
        pcall(ns.SetAlpha, ns, 0)
        if ns.SetBackdrop then pcall(ns.SetBackdrop, ns, nil) end
        local center = ns.Center
        if center then
            if center.SetTexture then pcall(center.SetTexture, center, nil) end
            if center.SetAtlas then pcall(center.SetAtlas, center, nil) end
            if center.SetAlpha then pcall(center.SetAlpha, center, 0) end
        end
    end
    local skinFrame = GetOrCreateSkinFrame(tooltip)
    SyncOverlayLevel(skinFrame, tooltip)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()
    local px = ns and SkinBase.GetPixelSize(ns, 1) or 1
    local edge = math.max((thickness or 1), 2) * px
    ApplyOverlayBackdrop(skinFrame, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    skinFrame:Show()
    skinnedTooltips[tooltip] = true
    -- SafeHookTooltipOnShow is a forward declaration, safe to call here
    -- because this function is only invoked at runtime (never during load).
    if SafeHookTooltipOnShow then SafeHookTooltipOnShow(tooltip) end
end

---------------------------------------------------------------------------
-- Combat-safe reapply: re-hide NineSlice and refresh overlay colors.
-- All operations target either the NineSlice (SetAlpha -- C-side) or the
-- QUI-owned overlay frame (addon frames are never taint-restricted).
-- No geometry writes to Blizzard frames, no pixel size math needed.
---------------------------------------------------------------------------
local function CombatSafeReapply(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end
    if not skinnedTooltips[tooltip] then return end

    -- Re-hide Blizzard NineSlice (C-side, taint-safe)
    local ns = tooltip.NineSlice
    if ns then
        pcall(ns.SetAlpha, ns, 0)
        -- Also clear NineSlice backdrop (BackdropTemplateMixin) -- the mixin's
        -- SetBackdrop is Lua but runs on a child frame, not the tooltip itself.
        if ns.SetBackdrop then
            pcall(ns.SetBackdrop, ns, nil)
        end
        -- Clear NineSlice Center texture directly — WoW 12.0 NineSlice textures
        -- can render through parent alpha (see HideNineSlice comment).
        -- SetTexture/SetAtlas/SetAlpha are C-side, taint-safe.
        local center = ns.Center
        if center then
            if center.SetTexture then pcall(center.SetTexture, center, nil) end
            if center.SetAtlas then pcall(center.SetAtlas, center, nil) end
            if center.SetAlpha then pcall(center.SetAlpha, center, 0) end
        end
    end

    -- Refresh overlay colors (addon-owned frame, always safe)
    local skinFrame = skinFrames[tooltip]
    if skinFrame then
        SyncOverlayLevel(skinFrame, tooltip)
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
        -- Update resilient color fields for OnSizeChanged fallback
        skinFrame._quiBgR = bgr or 0.05
        skinFrame._quiBgG = bgg or 0.05
        skinFrame._quiBgB = bgb or 0.05
        skinFrame._quiBgA = bga or 0.95
        skinFrame._quiBorderR = sr or 0
        skinFrame._quiBorderG = sg or 0
        skinFrame._quiBorderB = sb or 0
        skinFrame._quiBorderA = sa or 1
        skinFrame:SetBackdropColor(skinFrame._quiBgR, skinFrame._quiBgG, skinFrame._quiBgB, skinFrame._quiBgA)
        skinFrame:SetBackdropBorderColor(skinFrame._quiBorderR, skinFrame._quiBorderG, skinFrame._quiBorderB, skinFrame._quiBorderA)
        -- Ensure overlay is visible — Show is C-side (taint-safe).
        -- StripEmbeddedBorder hides the overlay when the tooltip is embedded
        -- inside a parent; re-show it when it's standalone again.
        skinFrame:Show()
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
    local nineSlice = frame.NineSlice
    if nineSlice then
        pcall(nineSlice.SetAlpha, nineSlice, 0)
        if nineSlice.SetBackdrop then
            pcall(nineSlice.SetBackdrop, nineSlice, nil)
        end
    end
    -- Also clear backdrop on the embedded frame itself
    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end
    -- Hide QUI overlay on embedded tooltips -- they live inside a parent
    -- tooltip that already has its own QUI overlay. Showing both creates
    -- a visible "border within border."
    local sf = skinFrames[frame]
    if sf then
        sf:Hide()
    end
    if frame.ItemTooltip then
        local itemNS = frame.ItemTooltip.NineSlice
        if itemNS then
            pcall(itemNS.SetAlpha, itemNS, 0)
            if itemNS.SetBackdrop then
                pcall(itemNS.SetBackdrop, itemNS, nil)
            end
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
            -- Trust Blizzard's isEmbedded parameter — it's the authoritative
            -- signal that this tooltip is being styled as embedded inside a
            -- parent. Parent-visibility checks have timing issues here because
            -- the parent tooltip may not be shown yet when this fires.
            if isEmbedded or tooltip.IsEmbedded then
                StripEmbeddedBorder(tooltip)
            elseif InCombatLockdown() then
                if skinnedTooltips[tooltip] then
                    pcall(CombatSafeReapply, tooltip)
                else
                    pcall(CombatSafeFirstSkin, tooltip)
                end
            elseif skinnedTooltips[tooltip] then
                pcall(ReapplySkin, tooltip)
            else
                -- First encounter with this tooltip -- skin it now.
                -- Catches world quest POIs, campaign tooltips, addon-created frames,
                -- and any other tooltip Blizzard restyled at runtime.
                pcall(SkinTooltip, tooltip)
                SafeHookTooltipOnShow(tooltip)
            end
        end)
    end

    -- Hook GameTooltip_SetBackdropStyle in addition to SharedTooltip.
    -- Blizzard can call this directly on GameTooltip, bypassing the shared hook.
    if GameTooltip_SetBackdropStyle then
        hooksecurefunc("GameTooltip_SetBackdropStyle", function(tooltip, style)
            if not IsEnabled() then return end
            if not tooltip then return end
            if InCombatLockdown() then
                if skinnedTooltips[tooltip] then
                    pcall(CombatSafeReapply, tooltip)
                else
                    pcall(CombatSafeFirstSkin, tooltip)
                end
            elseif skinnedTooltips[tooltip] then
                pcall(ReapplySkin, tooltip)
            else
                pcall(SkinTooltip, tooltip)
                SafeHookTooltipOnShow(tooltip)
            end
        end)
    end

    -- TAINT SAFETY: Use hooksecurefunc on Show instead of HookScript("OnShow")
    -- to prevent tainting the frame's script handler.
    -- EmbeddedItemTooltip can appear in two contexts:
    --   1. Embedded inside GameTooltip (world quest item rewards) — strip border
    --   2. Standalone (objective tracker hover) — needs its own QUI overlay
    -- At Show time for embedded context, GameTooltip may not be visible yet
    -- (Blizzard shows embedded tooltip before the parent). In that case,
    -- SkinTooltip runs here (parent not visible → not detected as embedded),
    -- but SharedTooltip_SetBackdropStyle(isEmbedded=true) fires immediately
    -- after in the same frame and calls StripEmbeddedBorder to correct it.
    if EmbeddedItemTooltip then
        hooksecurefunc(EmbeddedItemTooltip, "Show", function(self)
            if not IsEnabled() then return end
            local ok, parent = pcall(self.GetParent, self)
            if not ok then parent = nil end
            local parentVisible = parent and parent.IsShown and parent:IsShown()
            if parentVisible and parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame then
                StripEmbeddedBorder(self)
            else
                -- Standalone or pre-parent-show: apply full skin.
                -- For embedded context, SharedTooltip_SetBackdropStyle will
                -- fire with isEmbedded=true in the same frame and strip it.
                if InCombatLockdown() then
                    if skinnedTooltips[self] then
                        pcall(CombatSafeReapply, self)
                    else
                        -- First standalone show during combat (e.g. delve
                        -- objective hover). The tooltip was only
                        -- StripEmbeddedBorder'd at init, never fully
                        -- skinned, so CombatSafeReapply would bail out.
                        -- Create the overlay now — all operations target
                        -- addon-owned frames (always safe in combat).
                        local ns = self.NineSlice
                        if ns then
                            pcall(ns.SetAlpha, ns, 0)
                            if ns.SetBackdrop then pcall(ns.SetBackdrop, ns, nil) end
                            local center = ns.Center
                            if center then
                                if center.SetTexture then pcall(center.SetTexture, center, nil) end
                                if center.SetAtlas then pcall(center.SetAtlas, center, nil) end
                                if center.SetAlpha then pcall(center.SetAlpha, center, 0) end
                            end
                        end
                        local skinFrame = GetOrCreateSkinFrame(self)
                        SyncOverlayLevel(skinFrame, self)
                        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
                        local thickness = GetEffectiveBorderThickness()
                        local px = ns and SkinBase.GetPixelSize(ns, 1) or 1
                        local edge = math.max((thickness or 1), 2) * px
                        ApplyOverlayBackdrop(skinFrame, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                        skinFrame:Show()
                        skinnedTooltips[self] = true
                    end
                else
                    skinnedTooltips[self] = nil
                    pcall(SkinTooltip, self)
                end
            end
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
                HideNineSlice(itemNS)
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
    "SmallTextTooltip",
    "ReputationParagonTooltip",
    "NamePlateTooltip",
    "FriendsTooltip",
    "SettingsTooltip",
    "GameSmallHeaderTooltip",
    "QuickKeybindTooltip",
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

-- Tooltips accessed via dot-path (not direct _G keys)
local dotPathTooltips = {
    {"QuestScrollFrame", "StoryTooltip"},
    {"QuestScrollFrame", "CampaignTooltip"},
}

-- Addon-created tooltip frames (discovered when their addon loads)
local addonTooltipFrames = {
    "WQLTooltip",
    "WQLTooltipItemRef1",
    "WQLTooltipItemRef2",
    "WQLAreaPOITooltip",
    "WorldQuestTrackerGameTooltip",
    "WQT_ShoppingTooltip1",
    "WQT_ShoppingTooltip2",
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

-- Resolve a dot-path tooltip (e.g. {"QuestScrollFrame", "StoryTooltip"})
local function ResolveDotPath(path)
    local obj = _G[path[1]]
    for i = 2, #path do
        if not obj then return nil end
        obj = obj[path[i]]
    end
    return obj
end

-- Skin and hook a single tooltip frame if it exists and hasn't been skinned
local function DiscoverAndSkinTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if skinnedTooltips[tooltip] then return end
    if not IsEnabled() then
        SafeHookTooltipOnShow(tooltip)
        return
    end
    pcall(SkinTooltip, tooltip)
    SafeHookTooltipOnShow(tooltip)
end

-- Discover dot-path and addon tooltips (called after relevant frames exist)
local function DiscoverExtraTooltips()
    for _, path in ipairs(dotPathTooltips) do
        DiscoverAndSkinTooltip(ResolveDotPath(path))
    end
    for _, name in ipairs(addonTooltipFrames) do
        DiscoverAndSkinTooltip(_G[name])
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
    -- Single pass over all skinned tooltips (covers both static and dynamic)
    for tooltip in pairs(skinnedTooltips) do
        ReapplySkin(tooltip)
    end

    -- Handle embedded tooltip border visibility on settings change.
    -- Only strip when truly embedded (parent visible); standalone contexts
    -- are handled by SkinTooltip/ReapplySkin through the skinnedTooltips loop.
    if EmbeddedItemTooltip then
        if not IsEnabled() then
            RestoreEmbeddedBorder(EmbeddedItemTooltip)
        else
            local parent = EmbeddedItemTooltip:GetParent()
            local parentVisible = parent and parent.IsShown and parent:IsShown()
            if parentVisible and parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame then
                StripEmbeddedBorder(EmbeddedItemTooltip)
            end
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

-- TAINT SAFETY: HookTooltipOnShow calls hooksecurefunc which modifies the
-- frame's script table.  Inside Blizzard's securecallfunction chain
-- (TooltipDataProcessor callbacks, SharedTooltip_SetBackdropStyle), this taints
-- the execution context.  Defer hook installation out of the secure chain
-- during combat.  The hook is a one-time install (guarded by hookedTooltips),
-- so the 1-frame deferral is harmless.
SafeHookTooltipOnShow = function(tooltip)
    if hookedTooltips[tooltip] then return end
    if InCombatLockdown() then
        C_Timer.After(0, function()
            if tooltip then HookTooltipOnShow(tooltip) end
        end)
    else
        HookTooltipOnShow(tooltip)
    end
end

local function ClearNineSliceRegion(region)
    if region.SetTexture then pcall(region.SetTexture, region, nil) end
    if region.SetAtlas then pcall(region.SetAtlas, region, nil) end
    pcall(region.Hide, region)
end

-- Hook Show to ensure skin stays applied (Blizzard resets NineSlice on show)
HookTooltipOnShow = function(tooltip)
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
        -- IMMEDIATE NineSlice clearing (synchronous, before any deferral).
        -- On first show, NineSlice textures from the XML template are visible.
        -- Deferring ALL work to C_Timer.After(0) leaves them visible for one
        -- frame, creating a flash of Blizzard borders on first hover.
        -- SetAlpha + texture clearing are C-side / safe in any context.
        local ns = self.NineSlice
        if ns then
            pcall(ns.SetAlpha, ns, 0)
            if ns.SetBackdrop then pcall(ns.SetBackdrop, ns, nil) end
            local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = pcall(ns.GetRegions, ns)
            if ok then
                if r1 then ClearNineSliceRegion(r1) end
                if r2 then ClearNineSliceRegion(r2) end
                if r3 then ClearNineSliceRegion(r3) end
                if r4 then ClearNineSliceRegion(r4) end
                if r5 then ClearNineSliceRegion(r5) end
                if r6 then ClearNineSliceRegion(r6) end
                if r7 then ClearNineSliceRegion(r7) end
                if r8 then ClearNineSliceRegion(r8) end
                if r9 then ClearNineSliceRegion(r9) end
                if r10 then ClearNineSliceRegion(r10) end
            end
        end

        if InCombatLockdown() then
            if skinnedTooltips[self] then
                pcall(CombatSafeReapply, self)
            else
                pcall(CombatSafeFirstSkin, self)
            end
            return
        end

        C_Timer.After(0, function()
            if not self:IsShown() then return end
            if InCombatLockdown() then
                if skinnedTooltips[self] then
                    pcall(CombatSafeReapply, self)
                else
                    pcall(CombatSafeFirstSkin, self)
                end
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

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        if InCombatLockdown() then
            if skinnedTooltips[tooltip] then
                pcall(CombatSafeReapply, tooltip)
            else
                pcall(CombatSafeFirstSkin, tooltip)
            end
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
            if skinnedTooltips[tooltip] then
                pcall(CombatSafeReapply, tooltip)
            else
                pcall(CombatSafeFirstSkin, tooltip)
            end
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
            if skinnedTooltips[tooltip] then
                pcall(CombatSafeReapply, tooltip)
            else
                pcall(CombatSafeFirstSkin, tooltip)
            end
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
local tooltipSystemInitialized = false
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    -- After initialization, use ADDON_LOADED to discover addon tooltips
    if event == "ADDON_LOADED" and tooltipSystemInitialized then
        if not InCombatLockdown() then
            DiscoverExtraTooltips()
        end
        return
    end

    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
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
            -- GameTooltip visibility watcher (separate OnUpdate frame).
            --
            -- TAINT SAFETY: Do NOT use HookScript("OnShow") or
            -- hooksecurefunc(GameTooltip, "Show") here.  Both modify
            -- GameTooltip's dispatch tables, permanently tainting the
            -- frame.  When the world map's secure context later uses
            -- GameTooltip (secureexecuterange → AreaPoiUtil →
            -- GameTooltip_AddWidgetSet → RegisterForWidgetSet →
            -- ProcessWidget), it encounters the tainted frame and
            -- produces secret-value arithmetic errors in UIWidget
            -- Setup functions (TextWithState, ItemDisplay, etc.).
            --
            -- Instead, a tiny watcher frame polls IsShown() each
            -- OnUpdate to detect visibility transitions without
            -- touching GameTooltip's internals.  The 1-frame detection
            -- delay is imperceptible and the primary skin application
            -- already happens synchronously via SharedTooltip_
            -- SetBackdropStyle and TooltipDataProcessor hooks.
            -----------------------------------------------------------------
            do
                local gtWasShown = false
                local watcher = CreateFrame("Frame")
                watcher:Hide()  -- Start hidden: no OnUpdate cost when tooltip not shown
                -- Event-driven activation: only poll during show transitions.
                -- OnShow fires before data setup, so the watcher's 1-frame delay
                -- is still needed — but now it only runs while the tooltip is visible.
                GameTooltip:HookScript("OnShow", function() watcher:Show() end)
                GameTooltip:HookScript("OnHide", function()
                    gtWasShown = false
                    watcher:Hide()
                end)
                watcher:SetScript("OnUpdate", function()
                    local shown = GameTooltip:IsShown()
                    if shown == gtWasShown then
                        -- Already processed this transition; stop polling
                        if shown then watcher:Hide() end
                        return
                    end
                    gtWasShown = shown
                    if not shown then watcher:Hide() return end
                    -- GameTooltip just became visible
                    if not IsEnabled() then return end
                    if InCombatLockdown() then
                        pcall(CombatSafeReapply, GameTooltip)
                        return
                    end
                    if not skinnedTooltips[GameTooltip] then
                        pcall(SkinTooltip, GameTooltip)
                    else
                        pcall(ReapplySkin, GameTooltip)
                    end
                    C_Timer.After(0, function()
                        if GameTooltip:IsShown() then
                            pcall(ApplyTooltipFontSizeToFrame, GameTooltip)
                        end
                        -- Discover comparison tooltips (ShoppingTooltip1/2).
                        -- These may be lazily created by C-side code without
                        -- triggering SharedTooltip_SetBackdropStyle, leaving
                        -- them unskinned (white background).
                        for i = 1, 2 do
                            local st = _G["ShoppingTooltip" .. i]
                            if st and st:IsShown() then
                                if not hookedTooltips[st] then
                                    SafeHookTooltipOnShow(st)
                                end
                                if not skinnedTooltips[st] then
                                    if InCombatLockdown() then
                                        pcall(CombatSafeFirstSkin, st)
                                    else
                                        pcall(SkinTooltip, st)
                                    end
                                elseif not InCombatLockdown() then
                                    pcall(ReapplySkin, st)
                                else
                                    pcall(CombatSafeReapply, st)
                                end
                            end
                        end
                    end)
                end)
            end

            -- All tooltip modifications gated by master toggle + skinTooltips
            if not IsEnabled() then
                -- Still hook Show so enabling live takes effect on next show
                HookAllTooltips()
                SetupEmbeddedTooltipHooks()
                SetupHealthBarHook()
                SetupTooltipPostProcessor()
                DiscoverExtraTooltips()
                tooltipSystemInitialized = true
                return
            end

            RefreshAllTooltipFonts()
            HookAllTooltips()
            SkinAllTooltips()

            SetupEmbeddedTooltipHooks()
            SetupHealthBarHook()

            -- Post processor handles both skinning and health bar
            SetupTooltipPostProcessor()

            -- Discover dot-path and addon tooltips
            DiscoverExtraTooltips()
            tooltipSystemInitialized = true
        end
    end
end)

-- Expose refresh functions on the addon namespace for live color updates.
-- Avoids writing to _G which can introduce taint if Blizzard code touches those keys
-- during secure execution.
ns.QUI_RefreshTooltipSkinColors = RefreshAllTooltipColors
ns.QUI_RefreshTooltipFontSize = RefreshAllTooltipFonts
