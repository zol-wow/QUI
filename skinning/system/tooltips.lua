local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- TOOLTIP SKINNING
-- Applies QUI theme to Blizzard tooltips (GameTooltip, ItemRefTooltip, etc.)
--
-- TAINT-SAFE OVERLAY APPROACH: A QUI-owned BackdropTemplate overlay frame
-- renders the flat border/background at the NineSlice's frame level. The
-- overlay visually covers the NineSlice without writing to ANY Blizzard
-- frame (no SetAlpha, no SetSize, no Lua table writes). ANY addon write to
-- a Blizzard frame — even SetAlpha or setting a Lua key — taints the frame,
-- causing GetWidth()/GetHeight() to return secret values and breaking
-- Blizzard's Backdrop.lua arithmetic (SetupTextureCoordinates).
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
-- A QUI-owned BackdropTemplate frame covers the NineSlice at its frame
-- level, rendering QUI's flat border/background on top. No Blizzard frame
-- is modified in any way (no SetAlpha, no SetSize, no table writes).
-- Falls back to SetBackdrop for tooltips that still use BackdropTemplate.
---------------------------------------------------------------------------

-- TAINT SAFETY: Track skinned state in local tables, NOT on Blizzard frames.
local skinnedTooltips = Helpers.CreateStateTable()   -- tooltip → true
local hookedTooltips = Helpers.CreateStateTable()    -- tooltip → true (OnShow hooked)

-- QUI-owned overlay frames for tooltip skinning (weak-keyed to allow GC)
local skinFrames = Helpers.CreateStateTable()

-- Embedded tooltip backdrop (no border, background only — blends with parent)
local _embeddedBackdropInsets = { left = 0, right = 0, top = 0, bottom = 0 }
local _embeddedBackdrop = {
    bgFile = FLAT_TEXTURE,
    edgeFile = FLAT_TEXTURE,
    edgeSize = 0,
    insets = _embeddedBackdropInsets,
}

-- Get or create a QUI-owned BackdropTemplate overlay frame for a tooltip.
-- Addon-owned frames are never taint-restricted.
local function GetOrCreateSkinFrame(tooltip)
    if skinFrames[tooltip] then return skinFrames[tooltip] end
    local frame = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    frame:SetAllPoints(tooltip)
    -- Match the NineSlice's frame level so the overlay covers it in the same
    -- rendering plane. The tooltip's own regions (text) render at the tooltip's
    -- frame level, which is higher — text stays on top of the overlay.
    -- TAINT SAFETY: GetFrameLevel is read-only — safe on Blizzard frames.
    local ns = tooltip.NineSlice
    if ns then
        local ok, nsLevel = pcall(ns.GetFrameLevel, ns)
        if ok and type(nsLevel) == "number" then
            frame:SetFrameLevel(nsLevel)
        end
    end
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
    skinFrame:SetBackdrop(_cachedBackdrop)
    skinFrame:SetBackdropColor(bgr, bgg, bgb, bga)
    skinFrame:SetBackdropBorderColor(sr, sg, sb, sa)
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
        -- TAINT SAFETY: Do NOT write to the NineSlice frame (SetAlpha, SetSize,
        -- or even Lua table keys like layoutType/backdropInfo). ANY addon write
        -- to a Blizzard frame taints it — GetWidth()/GetHeight() then return
        -- secret values, causing Backdrop.lua arithmetic errors on Show().
        -- The overlay covers the NineSlice visually at its frame level.
        local skinFrame = GetOrCreateSkinFrame(tooltip)
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = (thickness or 1) * px
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
        -- Update overlay backdrop and colors (overlay covers NineSlice visually)
        local skinFrame = GetOrCreateSkinFrame(tooltip)
        local px = SkinBase.GetPixelSize(tooltip, 1)
        local edge = (thickness or 1) * px
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
end

---------------------------------------------------------------------------
-- Combat-safe reapply: refresh overlay colors only.
-- Only targets QUI-owned overlay frames (addon frames are never
-- taint-restricted). No Blizzard frame writes of any kind.
---------------------------------------------------------------------------
local function CombatSafeReapply(tooltip)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not IsEnabled() then return end
    -- Only act on tooltips we've actually skinned (overlay exists)
    if not skinnedTooltips[tooltip] then return end

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
-- We hook that function and cover the NineSlice with an overlay that matches
-- the parent tooltip's background color, blending it seamlessly.
-- Overlay is addon-owned and taint-safe even during combat.
---------------------------------------------------------------------------

local function StripEmbeddedBorder(frame)
    if not frame then return end
    -- TAINT SAFETY: Do NOT call SetAlpha or any method on Blizzard's NineSlice.
    -- Instead, cover it with an overlay that matches the parent tooltip's
    -- background color (blends seamlessly, no visible embedded border).
    if frame.NineSlice then
        local skinFrame = GetOrCreateSkinFrame(frame)
        local _, _, _, _, bgr, bgg, bgb, bga = GetEffectiveColors()
        skinFrame:SetBackdrop(_embeddedBackdrop)
        skinFrame:SetBackdropColor(bgr, bgg, bgb, bga)
        skinFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if frame.ItemTooltip and frame.ItemTooltip.NineSlice then
        local itemSkin = GetOrCreateSkinFrame(frame.ItemTooltip)
        local _, _, _, _, bgr, bgg, bgb, bga = GetEffectiveColors()
        itemSkin:SetBackdrop(_embeddedBackdrop)
        itemSkin:SetBackdropColor(bgr, bgg, bgb, bga)
        itemSkin:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

local function RestoreEmbeddedBorder(frame)
    if not frame then return end
    -- Clear overlay backdrops so Blizzard's NineSlice is visible again
    local skinFrame = skinFrames[frame]
    if skinFrame then
        skinFrame:SetBackdrop(nil)
    end
    if frame.ItemTooltip then
        local itemSkin = skinFrames[frame.ItemTooltip]
        if itemSkin then
            itemSkin:SetBackdrop(nil)
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
            if self.NineSlice then
                local itemSkin = GetOrCreateSkinFrame(self)
                local _, _, _, _, bgr, bgg, bgb, bga = GetEffectiveColors()
                itemSkin:SetBackdrop(_embeddedBackdrop)
                itemSkin:SetBackdropColor(bgr, bgg, bgb, bga)
                itemSkin:SetBackdropBorderColor(0, 0, 0, 0)
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
