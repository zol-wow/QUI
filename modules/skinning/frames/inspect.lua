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

local function GetWindowColors()
    local profile = Helpers.GetProfile and Helpers.GetProfile()
    return SkinBase.GetWindowColors(profile and profile.general, "inspectFrame")
end

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

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetWindowColors()

    if not customBg then
        customBg = CreateFrame("Frame", "QUI_InspectFrameBg_Skin", InspectFrame, "BackdropTemplate")
        customBg:SetFrameLevel(0)
        customBg:EnableMouse(false)
        customBg:SetAllPoints(InspectFrame)
    end

    SkinBase.ApplyChromeBackdrop(customBg, { radius = 8, withBackground = true, borderColor = { sr, sg, sb, sa }, bgColor = { bgr, bgg, bgb, bga } })

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
    if InspectFrame and InspectFrame.ModeTabs and InspectFrame.ModeTabs.Tabs then
        SkinBase.SkinTabGroup(InspectFrame.ModeTabs.Tabs, InspectFrame, { font = false })
        return
    end
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("InspectFrame", 3), InspectFrame, { font = true, resizeToText = true, dockBottom = true })
end

local function StyleNativeInspectSlot(slot)
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() or not slot or (slot.IsForbidden and slot:IsForbidden()) then return end
    local fallback = SkinBase.GetFrameData(slot, "qInspectFallbackBorder")
    if IsInspectOverlaysEnabled() then
        if fallback then fallback:Hide() end
        return
    end
    local icon = slot.Icon or slot.icon
    if not icon then return end
    local preserve = {
        [icon] = true,
        [slot.IconBorder or false] = true,
        [slot.ItemContextOverlay or false] = true,
        [slot.IconOverlay or false] = true,
        [slot.IconOverlay2 or false] = true,
        [slot.searchOverlay or false] = true,
        [slot.IconQuestTexture or false] = true,
    }
    local highlight = slot.GetHighlightTexture and slot:GetHighlightTexture()
    if highlight then preserve[highlight] = true end
    SkinBase.StripTexturesExcept(slot, preserve)
    if slot.BorderFrame then SkinBase.StripTextures(slot.BorderFrame) end
    SkinBase.RoundIconTexture(slot, icon)
    local r, g, b, a = GetWindowColors()
    local native = slot.IconBorder
    if native and native:IsShown() and native.GetVertexColor then r, g, b, a = native:GetVertexColor() end
    fallback = SkinBase.SkinIcon(icon, { parent = slot, border = { r, g, b, a or 1 } })
    SkinBase.ApplyChromeBackdrop(fallback, { radius = 4, withBackground = false, borderColor = { r, g, b, a or 1 } })
    SkinBase.SetFrameData(slot, "qInspectFallbackBorder", fallback)
    fallback:Show()
    local custom = SkinBase.GetFrameData(slot, "qInspectCustomBorder")
    if custom then custom:Hide() end
    SkinBase.ClampTextureHidden(native, true)
    SkinBase.SkinFontString(slot.Count, { fontOnly = true })
    SkinBase.LockFontObject(slot.Count, { fontOnly = true })
    if highlight then
        highlight:SetColorTexture(1, 1, 1, 0.12)
        highlight:SetAllPoints(icon)
        SkinBase.RoundIconTexture(slot, highlight)
    end
end

local function StyleNativeInspectEquipment()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    local items = _G.InspectPaperDollItemsFrame or _G.InspectPaperDollFrame
    if not items or (items.IsForbidden and items:IsForbidden()) then return end
    for _, slot in ipairs({ items:GetChildren() }) do
        local name = slot.GetName and slot:GetName()
        if slot:IsObjectType("Button") and name and name:match("^Inspect.+Slot$") then
            StyleNativeInspectSlot(slot)
        end
    end
    if _G.InspectPaperDollItemSlotButton_Update and not SkinBase.GetFrameData(items, "qInspectFallbackUpdateHooked") then
        hooksecurefunc("InspectPaperDollItemSlotButton_Update", StyleNativeInspectSlot)
        SkinBase.SetFrameData(items, "qInspectFallbackUpdateHooked", true)
    end
end

local function StyleInspectModelControls()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    local model = _G.InspectModelFrame
    if not model or (model.IsForbidden and model:IsForbidden()) then return end
    local controls = model.controlFrame
    if not controls or (controls.IsForbidden and controls:IsForbidden()) then return end
    SkinBase.StripTextures(controls)
    for _, button in ipairs({ controls:GetChildren() }) do
        if button:IsObjectType("Button") and button.icon and not (button.IsForbidden and button:IsForbidden()) then
            local alpha = button.icon:GetAlpha()
            SkinBase.SkinButton(button, { font = false, strip = true, belowChildren = true })
            button.icon:SetAlpha(alpha)
            SkinBase.ClampTextureHidden(button.bg, true)
            SkinBase.RefreshWidget(button)
        end
    end
end

local function SkinInspectButtons()
    if not SkinBase then return end
    StyleInspectModelControls()
    StyleNativeInspectEquipment()

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
        local talentsButton = (itemsFrame and itemsFrame.InspectTalents) or (paperDoll and paperDoll.InspectTalents)
        if talentsButton then SkinBase.SkinButton(talentsButton, { font = true }) end
    end
end

local function StyleInspectText(text)
    if not text or (text.IsForbidden and text:IsForbidden()) then return end
    SkinBase.SkinFontString(text, { fontOnly = true })
    SkinBase.LockFontObject(text, { fontOnly = true })
    local r, g, b, a = text:GetTextColor()
    local normal = NORMAL_FONT_COLOR
    if normal and r == normal.r and g == normal.g and b == normal.b then
        text:SetTextColor(0.92, 0.92, 0.92, a)
    end
end

local function StyleInspectPvpTalentSlot(slot)
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() or not slot or (slot.IsForbidden and slot:IsForbidden()) then return end
    local icon = slot.Texture
    if not icon then return end
    if slot.CircleMask and icon.RemoveMaskTexture and not SkinBase.GetFrameData(slot, "qInspectTalentMaskRemoved") then
        icon:RemoveMaskTexture(slot.CircleMask)
        SkinBase.SetFrameData(slot, "qInspectTalentMaskRemoved", true)
    end
    SkinBase.RoundIconTexture(slot, icon)
    local r, g, b, a = GetWindowColors()
    local border = SkinBase.SkinIcon(icon, { parent = slot, crop = false, border = { r, g, b, a } })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
    SkinBase.ClampTextureHidden(slot.Border, true)
    local hover = SkinBase.GetFrameData(slot, "qInspectTalentHover")
    if not hover then
        hover = slot:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(icon)
        hover:SetColorTexture(1, 1, 1, 0.12)
        SkinBase.RoundIconTexture(slot, hover)
        hover:Hide()
        SkinBase.SetFrameData(slot, "qInspectTalentHover", hover)
        slot:HookScript("OnEnter", function() hover:Show() end)
        slot:HookScript("OnLeave", function() hover:Hide() end)
        slot:HookScript("OnHide", function() hover:Hide() end)
    end
    if slot.Update and not SkinBase.GetFrameData(slot, "qInspectTalentUpdateHooked") then
        hooksecurefunc(slot, "Update", StyleInspectPvpTalentSlot)
        SkinBase.SetFrameData(slot, "qInspectTalentUpdateHooked", true)
    end
end

local function StyleInspectSupplementalFrames()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    local guild = _G.InspectGuildFrame
    if guild and not (guild.IsForbidden and guild:IsForbidden()) then
        SkinBase.ClampTextureHidden(_G.InspectGuildFrameBG, true)
        for _, key in ipairs({ "guildName", "guildRealmName", "guildLevel", "guildNumMembers" }) do
            StyleInspectText(guild[key])
        end
        local points = guild.Points
        if points and not (points.IsForbidden and points:IsForbidden()) then
            SkinBase.ClampTextureHidden(points.LeftCap, true)
            SkinBase.ClampTextureHidden(points.RightCap, true)
            StyleInspectText(points.SumText)
        end
    end
    local pvp = _G.InspectPVPFrame
    if pvp and not (pvp.IsForbidden and pvp:IsForbidden()) then
        SkinBase.ClampTextureHidden(pvp.BG, true)
        StyleInspectText(pvp.HKs)
        StyleInspectText(pvp.HonorLevel)
        for _, slot in ipairs(pvp.Slots or {}) do
            StyleInspectPvpTalentSlot(slot)
        end
        for _, key in ipairs({ "RatedBG", "Arena2v2", "Arena3v3", "RatedSoloShuffle", "RatedBGBlitz" }) do
            local row = pvp[key]
            if row and not (row.IsForbidden and row:IsForbidden()) then
                for _, field in ipairs({ "BGType", "RatingLabel", "Rating", "RecordLabel", "Record" }) do
                    StyleInspectText(row[field])
                end
            end
        end
    end
end

local function SetupInspectFrameSkinning()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    if not InspectFrame then return end

    CreateOrUpdateBackground()
    SkinInspectFrameTabs()
    SkinInspectButtons()
    StyleInspectSupplementalFrames()

    InspectFrame:HookScript("OnShow", function()
        SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
        SkinInspectFrameTabs()
        SkinInspectButtons()
        StyleInspectSupplementalFrames()
    end)

    if InspectFrame:IsShown() then
        SetInspectFrameBgExtended(IsInspectOverlaysEnabled())
        SkinInspectFrameTabs()
        SkinInspectButtons()
        StyleInspectSupplementalFrames()
    end
end

local function RefreshInspectFrameColors()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetWindowColors()

    if customBg then
        SkinBase.ApplyChromeBackdrop(customBg, { radius = 8, withBackground = true, borderColor = { sr, sg, sb, sa }, bgColor = { bgr, bgg, bgb, bga } })
    end

    SkinInspectFrameTabs()
    StyleInspectModelControls()
    StyleNativeInspectEquipment()
    StyleInspectSupplementalFrames()
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
    ns.Registry:Register("skinInspectFrame", {
        refresh = _G.QUI_RefreshInspectColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_InspectUI", SetupInspectFrameSkinning)
