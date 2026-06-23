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

    -- ApplyPixelBackdrop persists these colors in the backdrop data and applies
    -- them now; a bare follow-up setter would be redundant and gets discarded on
    -- the next scale-refresh rebuild.
    SkinBase.ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

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
-- Routes through the canonical SkinBase.SkinTabGroup. The former private
-- StyleInspectFrameTab + UpdateInspectFrameTabSelectedState pair forked
-- SkinTabButton/RefreshTabSelected and, worse, used live-only SetBackdropColors
-- for the selected highlight, so the selection tint was LOST on any scale/theme
-- rebuild. The shared verb persists it via ApplyPixelBackdrop and keeps these
-- tabs byte-identical to CharacterFrame's. font=true opts into the QUI tab font +
-- the canonical selected/unselected label recolor.
local function SkinInspectFrameTabs()
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("InspectFrame", 3), InspectFrame, { font = true })
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
            -- glyph + size inherit the unified "×"/14 default (matches every other
            -- QUI close button); only the chrome inset/palette stay pane-specific.
            fontFlags = "OUTLINE",
            insetPixels = 2,
        })
    end

    if SkinBase.SkinButton then
        local paperDoll = _G.InspectPaperDollFrame
        local viewButton = paperDoll and paperDoll.ViewButton
        -- { font = true } drives ViewButton's Normal/Highlight/Disabled font
        -- objects so the QUI face survives the engine hover/disable swap.
        if viewButton then SkinBase.SkinButton(viewButton, { font = true }) end

        local itemsFrame = _G.InspectPaperDollItemsFrame
        local talentsButton = itemsFrame and itemsFrame.InspectTalents
        if talentsButton then SkinBase.SkinButton(talentsButton, { font = true }) end
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
        -- ApplyPixelBackdrop persists + renders both colors; bare follow-up setters only
        -- touch live textures and are discarded on the next scale-refresh rebuild.
        SkinBase.ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
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
local api = _G.QUI_InspectFrameSkinning or {}
api.CONFIG = CONFIG
api.IsEnabled = IsSkinningEnabled
api.SetExtended = SetInspectFrameBgExtended
api.Refresh = RefreshInspectFrameColors
api.RefreshScale = RefreshInspectFrameScale
_G.QUI_InspectFrameSkinning = api

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
-- Skin as soon as Blizzard_InspectUI is available. OnAddOnLoaded fires
-- immediately if the addon already loaded (catch-up), otherwise synchronously on
-- its ADDON_LOADED. Run immediately (no defer): Blizzard shows InspectFrame in
-- the same tick as ADDON_LOADED fires, so deferring would race the first OnShow.
SkinBase.OnAddOnLoaded("Blizzard_InspectUI", SetupInspectFrameSkinning)
