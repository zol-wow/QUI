local addonName, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local UIKit = ns.UIKit

local GetCore = ns.Helpers.GetCore

local InspectSkinning = {}
local CONFIG = {
    PANEL_WIDTH_EXTENSION = 0,
    PANEL_HEIGHT_EXTENSION = 50,
}

local customBg = nil

local GetSkinColors = Helpers.CreateSkinColorGetter("inspectFrame")

local function IsSkinningEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if settings and settings.skinInspectFrame == nil then
        return true
    end
    return settings and settings.skinInspectFrame
end

local function IsInspectOverlaysEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.character
    if settings and settings.enabled == false then
        return false
    end
    if settings and settings.inspectEnabled == nil then
        return true
    end
    return settings and settings.inspectEnabled
end

local function CreateOrUpdateBackground()
    if not InspectFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    if not customBg then
        customBg = CreateFrame("Frame", "QUI_InspectFrameBg_Skin", InspectFrame, "BackdropTemplate")
        customBg:SetFrameLevel(0)
        customBg:EnableMouse(false)
        customBg:SetAllPoints(InspectFrame)
    end

    SkinBase.ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

    return customBg
end

local function HideBlizzardDecorations()
    if not InspectFrame then return end

    SkinBase.HidePortraitFrameChrome(InspectFrame)

    if InspectFramePortrait then InspectFramePortrait:Hide() end
    if InspectFrameBg then InspectFrameBg:Hide() end

    if InspectModelFrameBorderTopLeft then InspectModelFrameBorderTopLeft:Hide() end
    if InspectModelFrameBorderTopRight then InspectModelFrameBorderTopRight:Hide() end
    if InspectModelFrameBorderTop then InspectModelFrameBorderTop:Hide() end
    if InspectModelFrameBorderLeft then InspectModelFrameBorderLeft:Hide() end
    if InspectModelFrameBorderRight then InspectModelFrameBorderRight:Hide() end
    if InspectModelFrameBorderBottomLeft then InspectModelFrameBorderBottomLeft:Hide() end
    if InspectModelFrameBorderBottomRight then InspectModelFrameBorderBottomRight:Hide() end
    if InspectModelFrameBorderBottom then InspectModelFrameBorderBottom:Hide() end
    if InspectModelFrameBorderBottom2 then InspectModelFrameBorderBottom2:Hide() end

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

local function SkinInspectFrameTabs()
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("InspectFrame", 3), InspectFrame, { font = true })
end

local function SkinInspectButtons()
    if not SkinBase then return end

    if InspectFrame and InspectFrame.CloseButton and SkinBase.SkinChromeCloseButton then
        SkinBase.SkinChromeCloseButton(InspectFrame.CloseButton, {
            prefix = "inspectFrame",
            stateKey = "inspectClose",
            fontFlags = "OUTLINE",
            insetPixels = 2,
        })
    end

    if SkinBase.SkinButton then
        local paperDoll = _G.InspectPaperDollFrame
        local viewButton = paperDoll and paperDoll.ViewButton
        if viewButton then SkinBase.SkinButton(viewButton, { font = true }) end

        local itemsFrame = _G.InspectPaperDollItemsFrame
        local talentsButton = itemsFrame and itemsFrame.InspectTalents
        if talentsButton then SkinBase.SkinButton(talentsButton, { font = true }) end
    end
end

local function SetupInspectFrameSkinning()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    if not InspectFrame then return end

    CreateOrUpdateBackground()
    SkinInspectFrameTabs()
    SkinInspectButtons()

    InspectFrame:HookScript("OnShow", function()
        SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
        SkinInspectFrameTabs()
        SkinInspectButtons()
    end)

    if InspectFrame:IsShown() then
        SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
        SkinInspectFrameTabs()
        SkinInspectButtons()
    end
end

local function RefreshInspectFrameColors()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    if customBg then
        SkinBase.ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    SkinInspectFrameTabs()
end

local function RefreshInspectFrameScale()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    if not InspectFrame then return end

    SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
    SkinInspectFrameTabs()
    if UIKit and UIKit.QueueScaleRefresh then
        UIKit.QueueScaleRefresh(2)
    end
end

local api = _G.QUI_InspectFrameSkinning or {}
api.CONFIG = CONFIG
api.IsEnabled = IsSkinningEnabled
api.SetExtended = SetInspectFrameBgExtended
api.Refresh = RefreshInspectFrameColors
api.RefreshScale = RefreshInspectFrameScale
_G.QUI_InspectFrameSkinning = api

_G.QUI_RefreshInspectColors = RefreshInspectFrameColors

if ns.Registry then
    ns.Registry:Register("skinInspect", {
        refresh = _G.QUI_RefreshInspectColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_InspectUI", SetupInspectFrameSkinning)
