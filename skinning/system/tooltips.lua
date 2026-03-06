local addonName, ns = ...
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

-- Forward declaration: QueueCombatTooltipSkin is used by SkinTooltip/ReapplySkin
-- but defined after them (circular dependency with FlushCombatSkinQueue).
local QueueCombatTooltipSkin

-- NineSlice piece names used by Blizzard tooltips
local NINE_SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

-- TAINT SAFETY: Check if tooltip dimensions are tainted (secret values).
-- Calling SetBackdrop/NineSlice geometry math when dimensions are tainted
-- permanently infects the tooltip's layout state. pcall does NOT prevent this.
local function HasTaintedDimensions(tooltip)
    local ok, result = pcall(function()
        local w = tooltip:GetWidth()
        local h = tooltip:GetHeight()
        if Helpers.IsSecretValue(w) or Helpers.IsSecretValue(h) then
            return true
        end
        local _ = w + h  -- arithmetic test: errors if either is secret
        return false
    end)
    return not ok or result == true
end

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

-- Full skin application for a tooltip
local function SkinTooltip(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if skinnedTooltips[tooltip] then return end

    -- TAINT SAFETY: Defer if tooltip dimensions are secret values.
    -- Geometry math with tainted dimensions permanently infects layout state.
    if HasTaintedDimensions(tooltip) then
        QueueCombatTooltipSkin(tooltip)
        return
    end
    -- TAINT SAFETY: Defer if GameTooltip has a tainted widget container child
    -- (e.g. from WorldQuestsList tainting shownWidgetCount).
    if tooltip == GameTooltip and Helpers.HasTaintedWidgetContainer(tooltip) then
        QueueCombatTooltipSkin(tooltip)
        return
    end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetEffectiveColors()
    local thickness = GetEffectiveBorderThickness()

    local ns = tooltip.NineSlice
    if ns then
        -- Clear Blizzard's cached layout properties to prevent re-application
        -- of default styles during tooltip resize/re-layout. Safe in addon context.
        ns.layoutType = nil
        ns.layoutTextureKit = nil
        ns.backdropInfo = nil
        if tooltip.layoutType ~= nil then tooltip.layoutType = nil end
        if tooltip.layoutTextureKit ~= nil then tooltip.layoutTextureKit = nil end

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

-- Re-apply skin to an already-skinned tooltip (called on every Show)
local function ReapplySkin(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    -- TAINT SAFETY: Defer if dimensions are tainted to avoid infecting layout state.
    if HasTaintedDimensions(tooltip) then
        QueueCombatTooltipSkin(tooltip)
        return
    end
    if tooltip == GameTooltip and Helpers.HasTaintedWidgetContainer(tooltip) then
        QueueCombatTooltipSkin(tooltip)
        return
    end

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

-- During combat, avoid mutating tooltip internals directly inside the secure
-- OnShow/PostCall chain. Defer all skinning until combat ends via PLAYER_REGEN_ENABLED.
-- C_Timer.After(0) does NOT escape taint propagation — it fires on the same frame.
local combatSkinQueue = {}
local combatSkinEventFrame

local function FlushCombatSkinQueue()
    if InCombatLockdown() then return end
    for tooltip in pairs(combatSkinQueue) do
        if tooltip and tooltip.IsShown and tooltip:IsShown() and IsEnabled() then
            if not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            else
                ReapplySkin(tooltip)
            end
            ApplyTooltipFontSizeToFrame(tooltip)
        end
    end
    wipe(combatSkinQueue)
    combatSkinEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

QueueCombatTooltipSkin = function(tooltip)
    if not tooltip or combatSkinQueue[tooltip] then return end
    combatSkinQueue[tooltip] = true
    if not combatSkinEventFrame then
        combatSkinEventFrame = CreateFrame("Frame")
        combatSkinEventFrame:SetScript("OnEvent", FlushCombatSkinQueue)
    end
    combatSkinEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
                -- Embedded tooltip (e.g. EmbeddedItemTooltip): hide its NineSlice
                StripEmbeddedBorder(tooltip)
            elseif skinnedTooltips[tooltip] then
                -- Blizzard just re-applied a backdrop style to a skinned tooltip.
                -- Re-apply QUI skin so our flat look wins without needing to nil
                -- out layoutType/backdropInfo (which taints the frame).
                -- ReapplySkin only touches NineSlice textures/colors (C-side ops),
                -- so it's safe to call even in combat — no taint propagation.
                pcall(ReapplySkin, tooltip)
            end
        end)
    end

    -- Direct OnShow hook on EmbeddedItemTooltip as fallback — catches cases
    -- where OnShow fires without SharedTooltip_SetBackdropStyle being called.
    if EmbeddedItemTooltip then
        EmbeddedItemTooltip:HookScript("OnShow", function(self)
            if not IsEnabled() then return end
            StripEmbeddedBorder(self)
        end)
        -- Initial strip if already visible
        if IsEnabled() then
            StripEmbeddedBorder(EmbeddedItemTooltip)
        end
    end

    -- Also handle GameTooltip.ItemTooltip sub-frame if present
    if GameTooltip and GameTooltip.ItemTooltip and GameTooltip.ItemTooltip.NineSlice then
        GameTooltip.ItemTooltip:HookScript("OnShow", function(self)
            if not IsEnabled() then return end
            local nineSlice = self.NineSlice
            if nineSlice then
                pcall(nineSlice.SetAlpha, nineSlice, 0)
            end
        end)
    end
end

-- List of tooltips to skin
local tooltipsToSkin = {
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

-- Hook OnShow to ensure skin stays applied (Blizzard resets NineSlice on show)
local function HookTooltipOnShow(tooltip)
    if not tooltip or hookedTooltips[tooltip] then return end

    -- NOTE: Tooltip OnShow runs synchronously — deferring causes unskinned tooltip flash.
    -- Tooltip skinning is NOT in the Edit Mode taint chain.
    tooltip:HookScript("OnShow", function(self)
        -- TAINT SAFETY: Font sizing (SetFont) changes FontString intrinsic metrics,
        -- tainting the tooltip's auto-sized width. Blizzard's GameTooltip_InsertFrame
        -- then fails comparing the tainted frameWidth. Defer font sizing to after the
        -- show chain completes — the 1-frame delay is imperceptible since the previous
        -- font size is usually already correct.
        C_Timer.After(0, function()
            if self:IsShown() then
                pcall(ApplyTooltipFontSizeToFrame, self)
            end
        end)

        if InCombatLockdown() then
            -- NineSlice skin (textures, colors, sizes) uses C-side ops only and
            -- doesn't affect tooltip width calculations — safe in combat.
            -- EXCEPTION: Skip embedded tooltips (e.g. EmbeddedItemTooltip) — their
            -- OnShow fires inside a securecallfunction chain (TooltipDataHandler →
            -- SetSpellByID). Any addon frame mutations inside that chain taint the
            -- execution path, causing subsequent SetAttribute calls to fail with
            -- "Attempt to access forbidden object." Their NineSlice is already hidden
            -- (alpha 0) via StripEmbeddedBorder, so skinning is unnecessary.
            if IsEnabled() and not self.IsEmbedded then
                if skinnedTooltips[self] then
                    pcall(ReapplySkin, self)
                end
            end
            return
        end

        if not IsEnabled() then return end
        if not skinnedTooltips[self] then
            pcall(SkinTooltip, self)
        else
            pcall(ReapplySkin, self)
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
        if not InCombatLockdown() then
            DeferFontSizing(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
        elseif IsEnabled() then
            QueueCombatTooltipSkin(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        if not InCombatLockdown() then
            DeferFontSizing(tooltip)
            if IsEnabled() and not skinnedTooltips[tooltip] then
                SkinTooltip(tooltip)
            end
        elseif IsEnabled() then
            QueueCombatTooltipSkin(tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not tooltip or tooltip == EmbeddedItemTooltip then return end
        SafeHookTooltipOnShow(tooltip)
        if not InCombatLockdown() then
            DeferFontSizing(tooltip)
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
                -- TAINT SAFETY: Use SafeHide to avoid calling Hide() inside a secure
                -- call chain during combat, which would propagate taint.
                Helpers.SafeHide(self)
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

            -- Strip embedded item tooltip border (World Quest item rewards)
            SetupEmbeddedTooltipHooks()

            -- Post processor handles both skinning and health bar
            SetupTooltipPostProcessor()

            -- Health bar hook works independently of skinning
            SetupHealthBarHook()
        end)
    end
end)

-- Expose refresh functions on the addon namespace for live color updates.
-- Avoids writing to _G which can introduce taint if Blizzard code touches those keys
-- during secure execution.
ns.QUI_RefreshTooltipSkinColors = RefreshAllTooltipColors
ns.QUI_RefreshTooltipFontSize = RefreshAllTooltipFonts
