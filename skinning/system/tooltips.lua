local ADDON_NAME, ns = ...
local QUICore = ns.Addon
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
-- in Blizzard code (e.g. EmbeddedItemTooltip_UpdateSize → GetWidth()).
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
-- Overlay-based tooltip skinning
-- Blizzard's NineSlice is hidden (SetAlpha 0) and a QUI-owned
-- BackdropTemplate frame renders the flat border/background instead.
-- This avoids writing geometry to Blizzard frames (taint-safe).
-- Falls back to SetBackdrop for tooltips that still use BackdropTemplate.
---------------------------------------------------------------------------

-- TAINT SAFETY: Track skinned state in local tables, NOT on Blizzard frames.
local skinnedTooltips = Helpers.CreateStateTable()   -- tooltip → true
local hookedTooltips = Helpers.CreateStateTable()    -- tooltip → true (OnShow hooked)

-- Forward declarations (assigned later, used in closures that run at runtime)
local SafeHookTooltipOnShow
local HookTooltipOnShow

-- QUI-owned overlay frames for tooltip skinning (weak-keyed to allow GC)
local skinFrames = Helpers.CreateStateTable()

-- Hide Blizzard's NineSlice visually without modifying its geometry.
-- SetAlpha is C-side and doesn't taint frame dimensions.
-- Also clears any backdrop set via BackdropTemplateMixin on the NineSlice,
-- which is the primary source of "doubled border" artifacts — the NineSlice
-- backdrop renders at the NineSlice's frame level (above our overlay at level 0).
local function HideNineSlice(nineSlice)
    if not nineSlice then return end
    pcall(nineSlice.SetAlpha, nineSlice, 0)
    -- Clear BackdropTemplateMixin backdrop on the NineSlice itself.
    if nineSlice.SetBackdrop then
        pcall(nineSlice.SetBackdrop, nineSlice, nil)
    end
    -- Hide individual NineSlice texture pieces.  Parent SetAlpha(0) should
    -- make children invisible via alpha inheritance, but WoW 12.0 NineSlice
    -- textures render through the parent alpha.  Clearing each texture
    -- directly ensures nothing renders.
    for i = 1, select("#", nineSlice:GetRegions()) do
        local region = select(i, nineSlice:GetRegions())
        if region then
            if region.SetTexture then pcall(region.SetTexture, region, nil) end
            if region.SetAtlas then pcall(region.SetAtlas, region, nil) end
            pcall(region.Hide, region)
        end
    end
end

-- Get or create a QUI-owned BackdropTemplate overlay frame for a tooltip.
-- Addon-owned frames are never taint-restricted.
local function GetOrCreateSkinFrame(tooltip)
    if skinFrames[tooltip] then return skinFrames[tooltip] end
    local frame = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    frame:SetAllPoints(tooltip)
    -- Level 0 ensures backdrop renders below tooltip content (text at ARTWORK,
    -- backdrop bg at BACKGROUND / edges at BORDER).
    frame:SetFrameLevel(0)
    -- Snap overlay to pixel grid so backdrop edges land on exact pixel
    -- boundaries. Without this, a 1-physical-pixel edge can round to 0px
    -- on some sides depending on the tooltip's sub-pixel position.
    if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(true) end
    if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end
    skinFrames[tooltip] = frame

    return frame
end

-- Apply QUI backdrop to an overlay frame.
-- Reuses the cached backdrop table (updated in-place) for zero allocation.
local function ApplyOverlayBackdrop(skinFrame, edgeSize, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    _cachedBackdrop.edgeSize = edgeSize
    _cachedBackdropInsets.left = edgeSize
    _cachedBackdropInsets.right = edgeSize
    _cachedBackdropInsets.top = edgeSize
    _cachedBackdropInsets.bottom = edgeSize
    -- Clear first — SetBackdrop short-circuits when passed the same table
    -- reference, even if the table's contents changed.
    skinFrame:SetBackdrop(nil)
    skinFrame:SetBackdrop(_cachedBackdrop)
    skinFrame:SetBackdropColor(bgr, bgg, bgb, bga)
    skinFrame:SetBackdropBorderColor(sr, sg, sb, sa)
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
    -- Hide any child textures (border pieces, backgrounds)
    for _, region in pairs({header:GetRegions()}) do
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

-- Full skin application for a tooltip (called outside combat only)
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if skinnedTooltips[tooltip] then return end

    -- Detect embedded tooltips: they live inside another tooltip-like parent
    -- and should NOT get their own QUI overlay (the parent already has one).
    -- Creating an overlay here causes a "border within border" flash on first
    -- show, before StripEmbeddedBorder hides it on the next frame.
    local parent = tooltip.GetParent and tooltip:GetParent()
    local isEmbedded = tooltip.IsEmbedded
        or (parent and parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame)
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

        -- Hide Blizzard's NineSlice (no geometry modification — avoids taint)
        HideNineSlice(ns)

        -- Clear any backdrop on the tooltip frame itself (some tooltips have both
        -- NineSlice AND BackdropTemplate, creating a second border layer above
        -- our overlay at frame level 0).
        if tooltip.SetBackdrop then
            pcall(tooltip.SetBackdrop, tooltip, nil)
        end

        -- Create QUI-owned overlay with BackdropTemplate
        local skinFrame = GetOrCreateSkinFrame(tooltip)
        local px = SkinBase.GetPixelSize(ns, 1)
        -- Minimum 2 physical pixels ensures the border survives pixel-grid
        -- rounding at any tooltip position / effective scale.
        local edge = math.max((thickness or 1), 2) * px
        ApplyOverlayBackdrop(skinFrame, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    elseif tooltip.SetBackdrop then
        -- Legacy BackdropTemplate path (fallback)
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

    StripCompareHeader(tooltip)
    skinnedTooltips[tooltip] = true
end

-- Re-apply skin to an already-skinned tooltip (called on every Show, out of combat)
local function ReapplySkin(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    -- Embedded tooltips: only strip border, never create overlay
    local parent = tooltip.GetParent and tooltip:GetParent()
    local isEmbedded = tooltip.IsEmbedded
        or (parent and parent.NineSlice and parent ~= UIParent and parent ~= WorldFrame)
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
        local px = SkinBase.GetPixelSize(ns, 1)
        local edge = math.max((thickness or 1), 2) * px
        ApplyOverlayBackdrop(skinFrame, edge, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    elseif tooltip.SetBackdrop then
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

    StripCompareHeader(tooltip)
end

---------------------------------------------------------------------------
-- Combat-safe reapply: re-hide NineSlice and refresh overlay colors.
-- All operations target either the NineSlice (SetAlpha — C-side) or the
-- QUI-owned overlay frame (addon frames are never taint-restricted).
-- No geometry writes to Blizzard frames, no pixel size math needed.
---------------------------------------------------------------------------
local function CombatSafeReapply(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end

    -- Re-hide Blizzard NineSlice (C-side, taint-safe)
    local ns = tooltip.NineSlice
    if ns then
        pcall(ns.SetAlpha, ns, 0)
        -- Also clear NineSlice backdrop (BackdropTemplateMixin) — the mixin's
        -- SetBackdrop is Lua but runs on a child frame, not the tooltip itself.
        if ns.SetBackdrop then
            pcall(ns.SetBackdrop, ns, nil)
        end
    end

    -- Refresh overlay colors (addon-owned frame, always safe)
    local skinFrame = skinFrames[tooltip]
    if skinFrame then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
        skinFrame:SetBackdropColor(bgr, bgg, bgb, bga)
        skinFrame:SetBackdropBorderColor(sr, sg, sb, sa)
    end
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
        if nineSlice.SetBackdrop then
            pcall(nineSlice.SetBackdrop, nineSlice, nil)
        end
    end
    -- Also clear backdrop on the embedded frame itself
    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end
    -- Hide QUI overlay on embedded tooltips — they live inside a parent
    -- tooltip that already has its own QUI overlay. Showing both creates
    -- a visible "border within border."
    local sf = skinFrames[frame]
    if sf then
        sf:Hide()
    end
    -- Also strip ItemTooltip sub-frame border if present
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
                StripEmbeddedBorder(tooltip)
            elseif InCombatLockdown() then
                pcall(CombatSafeReapply, tooltip)
            elseif skinnedTooltips[tooltip] then
                pcall(ReapplySkin, tooltip)
            else
                -- First encounter with this tooltip — skin it now.
                -- Catches world quest POIs, campaign tooltips, addon-created frames,
                -- and any other tooltip Blizzard restyled at runtime.
                pcall(SkinTooltip, tooltip)
                SafeHookTooltipOnShow(tooltip)
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
            for i = 1, select("#", ns:GetRegions()) do
                local region = select(i, ns:GetRegions())
                if region then
                    if region.SetTexture then pcall(region.SetTexture, region, nil) end
                    if region.SetAtlas then pcall(region.SetAtlas, region, nil) end
                    pcall(region.Hide, region)
                end
            end
        end

        if InCombatLockdown() then
            pcall(CombatSafeReapply, self)
            return
        end

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
            -- GameTooltip visibility watcher (OnUpdate on a SEPARATE frame).
            -----------------------------------------------------------------
            local gtWatcher = CreateFrame("Frame")
            local gtWasShown = GameTooltip:IsShown()
            gtWatcher:SetScript("OnUpdate", function()
                local shown = GameTooltip:IsShown()
                if shown and not gtWasShown then
                    if not IsEnabled() then
                        -- nothing
                    elseif InCombatLockdown() then
                        -- Combat: re-hide NineSlice + refresh overlay colors only.
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
