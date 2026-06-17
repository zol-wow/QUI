local addonName, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local UIKit = ns.UIKit

local GetCore = ns.Helpers.GetCore

---------------------------------------------------------------------------
-- INSPECT FRAME SKINNING
-- Skins InspectFrame to match CharacterFrame appearance
---------------------------------------------------------------------------

-- Module reference
local InspectSkinning = {}
-- Configuration constants
local CONFIG = {
    PANEL_WIDTH_EXTENSION = 0,    -- No stats panel, no width extension needed
    PANEL_HEIGHT_EXTENSION = 50,  -- Height extension for tabs area at bottom
}

-- Module state
local customBg = nil
local inspectTabsHooked = false

---------------------------------------------------------------------------
-- Helper: Get skin colors from QUI system
---------------------------------------------------------------------------
local GetSkinColors = Helpers.CreateSkinColorGetter("inspectFrame")

---------------------------------------------------------------------------
-- Helper: Check if skinning is enabled
-- Note: Uses general.skinInspectFrame for visual skinning (background, borders)
-- This is separate from character.inspectEnabled which controls overlays/stats
---------------------------------------------------------------------------
local function IsSkinningEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    -- Default to true if not explicitly set
    if settings and settings.skinInspectFrame == nil then
        return true
    end
    return settings and settings.skinInspectFrame
end

---------------------------------------------------------------------------
-- Helper: Check if inspect overlays are enabled (from character settings)
-- Note: Uses character.inspectEnabled for layout/overlays/stats panel
-- This is separate from general.skinInspectFrame which controls visual skinning
---------------------------------------------------------------------------
local function IsInspectOverlaysEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.character
    if settings and settings.enabled == false then
        return false
    end
    -- Default to true if not explicitly set
    if settings and settings.inspectEnabled == nil then
        return true
    end
    return settings and settings.inspectEnabled
end

---------------------------------------------------------------------------
-- Create/update the custom background frame
---------------------------------------------------------------------------
local function CreateOrUpdateBackground()
    if not InspectFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    if not customBg then
        customBg = CreateFrame("Frame", "QUI_InspectFrameBg_Skin", InspectFrame, "BackdropTemplate")
        -- Inherit parent strata (MEDIUM); use FrameLevel 0 so we draw
        -- behind InspectFrame's children but not below UIParent/WorldFrame.
        -- Setting strata lower than parent causes intermittent render-order
        -- issues where customBg can end up drawn behind the world.
        customBg:SetFrameLevel(0)
        customBg:EnableMouse(false)  -- Don't steal clicks
        -- Default anchor to the inspect frame so the backdrop always has a
        -- valid rect. SetInspectFrameBgExtended overrides this when the stats
        -- panel extension is needed.
        customBg:SetAllPoints(InspectFrame)
    end

    SkinBase.ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    customBg:SetBackdropColor(bgr, bgg, bgb, bga)
    customBg:SetBackdropBorderColor(sr, sg, sb, sa)

    return customBg
end

---------------------------------------------------------------------------
-- Hide Blizzard decorative elements on InspectFrame
---------------------------------------------------------------------------
local function HideBlizzardDecorations()
    if not InspectFrame then return end

    SkinBase.HidePortraitFrameChrome(InspectFrame)

    -- Legacy globals that the InspectFrame xml also exposes alongside the
    -- templated chrome.
    if InspectFramePortrait then InspectFramePortrait:Hide() end
    if InspectFrameBg then InspectFrameBg:Hide() end

    -- Hide model frame borders
    if InspectModelFrameBorderTopLeft then InspectModelFrameBorderTopLeft:Hide() end
    if InspectModelFrameBorderTopRight then InspectModelFrameBorderTopRight:Hide() end
    if InspectModelFrameBorderTop then InspectModelFrameBorderTop:Hide() end
    if InspectModelFrameBorderLeft then InspectModelFrameBorderLeft:Hide() end
    if InspectModelFrameBorderRight then InspectModelFrameBorderRight:Hide() end
    if InspectModelFrameBorderBottomLeft then InspectModelFrameBorderBottomLeft:Hide() end
    if InspectModelFrameBorderBottomRight then InspectModelFrameBorderBottomRight:Hide() end
    if InspectModelFrameBorderBottom then InspectModelFrameBorderBottom:Hide() end
    if InspectModelFrameBorderBottom2 then InspectModelFrameBorderBottom2:Hide() end

    -- Hide model frame background textures
    if InspectModelFrame then
        if InspectModelFrame.BackgroundOverlay then
            InspectModelFrame.BackgroundOverlay:SetAlpha(0)
        end
    end
    for _, corner in pairs({ "TopLeft", "TopRight", "BotLeft", "BotRight" }) do
        local bg = _G["InspectModelFrameBackground" .. corner]
        if bg then bg:Hide() end
    end
end

---------------------------------------------------------------------------
-- API: Set background extended mode (for stats panel)
---------------------------------------------------------------------------
local function SetInspectFrameBgExtended(extended)
    if not IsSkinningEnabled() then return end
    if not customBg then
        CreateOrUpdateBackground()
    end
    if not customBg then return end

    customBg:ClearAllPoints()

    if extended then
        customBg:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 0, 0)
        customBg:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT",
            CONFIG.PANEL_WIDTH_EXTENSION, -CONFIG.PANEL_HEIGHT_EXTENSION)
    else
        customBg:SetAllPoints(InspectFrame)
    end

    customBg:Show()
    HideBlizzardDecorations()
end

---------------------------------------------------------------------------
-- Skin bottom tabs: Character, PvP, Guild
---------------------------------------------------------------------------
local function StyleInspectFrameTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not SkinBase or not tab then return end

    if not SkinBase.IsStyled(tab) then
        -- Clamp the Blizzard tab art hidden against re-assertion (see the matching
        -- comment in frames/character.lua StyleCharacterFrameTab).
        SkinBase.ClampAllTextures(tab)
        local highlight = tab.GetHighlightTexture and tab:GetHighlightTexture()
        SkinBase.ClampTextureHidden(highlight)

        SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
        local tabBackdrop = SkinBase.GetBackdrop(tab)
        if tabBackdrop then
            SkinBase.SetPixelInsetPoints(tabBackdrop, tab, 3, 3, 3, 0)
        end

        -- Re-assert the art clamp + font synchronously on every selection via
        -- the shared global PanelTemplates hook.
        SkinBase.RegisterTabArtClamp(tab)

        SkinBase.MarkStyled(tab)
    end

    -- Drive the QUI font via the button's font OBJECTS so hover/select can't
    -- revert it (a direct SetFont is clobbered by the button's state objects).
    SkinBase.ApplyTabFontObjects(tab)

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })
end

local function GetInspectFrameSelectedTab()
    if not InspectFrame then return nil end
    if PanelTemplates_GetSelectedTab then
        local selected = PanelTemplates_GetSelectedTab(InspectFrame)
        if selected then return selected end
    end
    return InspectFrame.selectedTab
end

local function UpdateInspectFrameTabSelectedState()
    if not SkinBase then return end

    local selectedTab = GetInspectFrameSelectedTab()

    for i = 1, 3 do
        local tab = _G["InspectFrameTab" .. i]
        local bd = tab and SkinBase.GetBackdrop(tab)
        local sc = tab and SkinBase.GetFrameData(tab, "skinColor")
        local bg = tab and SkinBase.GetFrameData(tab, "bgColor")
        if bd and sc and bg then
            local tabID = tab.GetID and tab:GetID()
            local isSelected = selectedTab == i or selectedTab == tabID
            if isSelected then
                bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
                bd:SetBackdropColor(math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1)
            else
                bd:SetBackdropBorderColor(sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6)
                bd:SetBackdropColor(bg[1], bg[2], bg[3], 0.7)
            end
        end
    end
end

local function SkinInspectFrameTabs()
    if not SkinBase then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    for i = 1, 3 do
        local tab = _G["InspectFrameTab" .. i]
        if tab then
            StyleInspectFrameTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    if not inspectTabsHooked and PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(frame)
            if frame == InspectFrame then
                C_Timer.After(0, SkinInspectFrameTabs)
            end
        end)
        inspectTabsHooked = true
    end

    UpdateInspectFrameTabSelectedState()
end

---------------------------------------------------------------------------
-- Skin the close button + paper-doll action buttons (were unskinned: stock
-- red close X, plain View/Talents buttons showed through the chrome).
--
-- InspectFrame inherits ButtonFrameTemplate, so its close button is
-- InspectFrame.CloseButton (UIPanelCloseButtonDefaultAnchors). The two
-- paper-doll actions are UIPanelButtonTemplate buttons:
--   InspectPaperDollFrame.ViewButton            ("View in Dressing Room")
--   InspectPaperDollItemsFrame.InspectTalents   ("Talents")
-- Route the close button through SkinChromeCloseButton (matches the character
-- frame; its 2px border inset keeps the box from overhanging the corner) and
-- the action buttons through the shared UIPanelButton skinner. Every helper is
-- idempotent (IsStyled / Hooked guards), so re-running on each show is cheap.
---------------------------------------------------------------------------
local function SkinInspectButtons()
    if not SkinBase then return end

    if InspectFrame and InspectFrame.CloseButton and SkinBase.SkinChromeCloseButton then
        SkinBase.SkinChromeCloseButton(InspectFrame.CloseButton, {
            prefix = "inspectFrame",
            stateKey = "inspectClose",
            label = "X",
            fontSize = 11,
            fontFlags = "OUTLINE",
            insetPixels = 2,
        })
    end

    if SkinBase.SkinButton then
        local paperDoll = _G.InspectPaperDollFrame
        local viewButton = paperDoll and paperDoll.ViewButton
        if viewButton then SkinBase.SkinButton(viewButton) end

        local itemsFrame = _G.InspectPaperDollItemsFrame
        local talentsButton = itemsFrame and itemsFrame.InspectTalents
        if talentsButton then SkinBase.SkinButton(talentsButton) end
    end
end

---------------------------------------------------------------------------
-- Main skinning setup
-- Note: OnShow hook is handled by qui_character.lua which calls SetExtended()
-- This avoids duplicate hooks and ensures proper coordination with layout code
---------------------------------------------------------------------------
local function SetupInspectFrameSkinning()
    if not IsSkinningEnabled() then return end
    if not InspectFrame then return end

    SkinBase.SkinFrameText(InspectFrame, { recurse = true })
    CreateOrUpdateBackground()
    SkinInspectFrameTabs()
    SkinInspectButtons()

    -- Position backdrop on every show, independent of the overlay module.
    -- Previously only SetInspectExtendedMode / SetInspectNormalMode (in the
    -- overlay hook path) called SetExtended, so with inspectEnabled=false the
    -- backdrop never got its height extension and tabs below InspectFrame
    -- rendered without a skin behind them.
    InspectFrame:HookScript("OnShow", function()
        SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
        SkinInspectFrameTabs()
        SkinInspectButtons()
    end)

    -- First-show race: if InspectFrame is already shown when this runs, the
    -- OnShow hook won't fire for the current open. Apply once directly.
    if InspectFrame:IsShown() then
        SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
        SkinInspectFrameTabs()
        SkinInspectButtons()
    end
end

---------------------------------------------------------------------------
-- Refresh colors on already-skinned elements (for live preview)
---------------------------------------------------------------------------
local function RefreshInspectFrameColors()
    if not IsSkinningEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    -- Update main background
    if customBg then
        SkinBase.ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        customBg:SetBackdropColor(bgr, bgg, bgb, bga)
        customBg:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    SkinInspectFrameTabs()
end

---------------------------------------------------------------------------
-- Rebuild pixel borders after the inspect panel scale changes.
--
-- The "Panel Scale" slider calls InspectFrame:SetScale(), which does NOT fire
-- the global UI scale-refresh event. QUI's 1px borders are computed from each
-- frame's EFFECTIVE scale, so without a rebuild the customBg border and the
-- tab insets stay sized for the old scale and render wrong (missing / blurred /
-- sub-pixel). Re-assert the backdrop (ApplyPixelBackdrop recomputes the border
-- at the new scale) and queue a pixel-border rebuild so every registered border
-- (tab insets, etc.) re-snaps too.
---------------------------------------------------------------------------
local function RefreshInspectFrameScale()
    if not IsSkinningEnabled() then return end
    if not InspectFrame then return end

    SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
    SkinInspectFrameTabs()
    if UIKit and UIKit.QueueScaleRefresh then
        UIKit.QueueScaleRefresh(2)
    end
end

---------------------------------------------------------------------------
-- CONSOLIDATED API TABLE
---------------------------------------------------------------------------
_G.QUI_InspectFrameSkinning = {
    -- Configuration
    CONFIG = CONFIG,

    -- Core functions
    IsEnabled = IsSkinningEnabled,
    SetExtended = SetInspectFrameBgExtended,
    Refresh = RefreshInspectFrameColors,
    RefreshScale = RefreshInspectFrameScale,
}

-- Legacy compatibility alias
_G.QUI_RefreshInspectColors = RefreshInspectFrameColors

if ns.Registry then
    ns.Registry:Register("skinInspect", {
        refresh = _G.QUI_RefreshInspectColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == "Blizzard_InspectUI" then
        -- Run immediately: Blizzard's own code shows InspectFrame in the same
        -- tick as ADDON_LOADED fires, so deferring here races the first OnShow.
        SetupInspectFrameSkinning()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

if InspectFrame and InspectFrameTab1 then
    SetupInspectFrameSkinning()
end
