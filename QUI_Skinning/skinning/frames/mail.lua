---------------------------------------------------------------------------
-- MAIL FRAME SKINNING
--
-- Blizzard_MailFrame is split across MailFrame, InboxFrame, SendMailFrame,
-- and OpenMailFrame, with decorative art on child frames outside the root
-- ButtonFrameTemplate chrome. This file owns that full surface.
---------------------------------------------------------------------------

local _, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore
local min = math.min
local max = math.max

local ICON_BUTTON_BG_BOOST = 0.04
local mailRefreshHooksInstalled = false

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors

local function CollectNumberedTabs(prefix, count)
    local tabs = {}
    for i = 1, count do
        local tab = _G[prefix .. "Tab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    return tabs
end

local function ClampTexture(texture)
    if not texture then return end
    if SkinBase.ClampTextureHidden then
        SkinBase.ClampTextureHidden(texture)
    elseif texture.SetAlpha then
        texture:SetAlpha(0)
    end
end

local function HideFrameTexturesExcept(frame, preserved)
    if not frame or not frame.GetNumRegions then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("Texture")
            and not (preserved and preserved[region]) then
            ClampTexture(region)
        end
    end
end

local function HideMailArtwork(artwork)
    if not artwork then return end
    if artwork.IsObjectType and artwork:IsObjectType("Texture") then
        ClampTexture(artwork)
        return
    end

    HideFrameTexturesExcept(artwork)
    if artwork.NineSlice then artwork.NineSlice:Hide() end
    if artwork.Left then ClampTexture(artwork.Left) end
    if artwork.Right then ClampTexture(artwork.Right) end
    if artwork.Middle then ClampTexture(artwork.Middle) end
    if artwork.Center then ClampTexture(artwork.Center) end
end

local function PreserveButtonTexture(preserved, texture)
    if texture then preserved[texture] = true end
end

local function PreserveRegion(region)
    local preserved = {}
    if region then preserved[region] = true end
    return preserved
end

local function HideButtonStateTextures(button)
    if not button then return end
    if button.GetHighlightTexture then ClampTexture(button:GetHighlightTexture()) end
    if button.GetPushedTexture then ClampTexture(button:GetPushedTexture()) end
    if button.GetCheckedTexture then ClampTexture(button:GetCheckedTexture()) end
    if button.GetDisabledTexture then ClampTexture(button:GetDisabledTexture()) end
end

local function InsetButtonBackdrop(button, inset)
    if not button then return end
    local backdrop = SkinBase.GetBackdrop(button)
    if not backdrop then return end

    inset = inset or 0
    if SkinBase.SetInsetPointsPx then
        SkinBase.SetInsetPointsPx(backdrop, button, inset, inset, inset, inset)
        return
    end

    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    backdrop:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
end

local function LowerFrameBackdrop(frame)
    if not frame or not frame.GetFrameLevel then return end
    local backdrop = SkinBase.GetBackdrop(frame)
    if not backdrop or not backdrop.SetFrameLevel then return end
    backdrop:SetFrameLevel(max(0, (frame:GetFrameLevel() or 1) - 1))
end

local function HideMailButtonDecor(button)
    if not button then return end

    local preserved = {}
    if button.GetNormalTexture then PreserveButtonTexture(preserved, button:GetNormalTexture()) end
    PreserveButtonTexture(preserved, button.Icon)
    PreserveButtonTexture(preserved, button.icon)
    PreserveButtonTexture(preserved, button.IconBorder)
    PreserveButtonTexture(preserved, button.IconOverlay)
    PreserveButtonTexture(preserved, button.IconOverlay2)

    HideFrameTexturesExcept(button, preserved)

    local name = button.GetName and button:GetName()
    if name then
        HideMailArtwork(_G[name .. "Slot"])
        HideMailArtwork(_G[name .. "CODBackground"])
    end
end

local function SkinMailIconButton(button)
    if not button then return end

    HideButtonStateTextures(button)
    HideMailButtonDecor(button)

    if SkinBase.IsStyled(button) then
        SkinBase.RefreshWidget(button)
    else
        local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetSkinColors()
        SkinBase.CreateBackdrop(button, sr, sg, sb, sa,
            min(bgr + ICON_BUTTON_BG_BOOST, 1),
            min(bgg + ICON_BUTTON_BG_BOOST, 1),
            min(bgb + ICON_BUTTON_BG_BOOST, 1),
            1)
        SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
        SkinBase.SetFrameData(button, "skinKind", "button")
        SkinBase.SetFrameData(button, "bgBoost", ICON_BUTTON_BG_BOOST)
        SkinBase.MarkStyled(button)
    end

    SkinBase.SkinFrameText(button, { recurse = true })
    SkinBase.LockFrameTextObjects(button, 2)
end

local function SkinInboxArtwork()
    HideMailArtwork(_G.InboxFrameBg)

    SkinBase.SkinButton(_G.InboxPrevPageButton)
    SkinBase.SkinButton(_G.InboxNextPageButton)
    InsetButtonBackdrop(_G.InboxPrevPageButton, 4)
    InsetButtonBackdrop(_G.InboxNextPageButton, 4)
    if _G.InboxPrevPageButton and _G.InboxPrevPageButton.GetNormalTexture then
        ClampTexture(_G.InboxPrevPageButton:GetNormalTexture())
    end
    if _G.InboxNextPageButton and _G.InboxNextPageButton.GetNormalTexture then
        ClampTexture(_G.InboxNextPageButton:GetNormalTexture())
    end
    HideButtonStateTextures(_G.InboxPrevPageButton)
    HideButtonStateTextures(_G.InboxNextPageButton)
end

local function SkinMailItems()
    SkinInboxArtwork()

    for i = 1, 7 do
        local item = _G["MailItem" .. i]
        if item then
            SkinBase.SkinScrollRow(item, { hover = false })
            SkinBase.SkinFrameText(item, { recurse = true })
            SkinBase.LockFrameTextObjects(item, 3)
            SkinBase.SkinButton(_G["MailItem" .. i .. "ExpireTime"])
            SkinMailIconButton(_G["MailItem" .. i .. "Button"])
        end
    end

    SkinBase.SkinButton(_G.OpenAllMail)
end

local function SkinMoneyInputFrame(moneyInput)
    if not moneyInput then return end
    if moneyInput.GoldBox then SkinBase.SkinEditBox(moneyInput.GoldBox) end
    if moneyInput.SilverBox then SkinBase.SkinEditBox(moneyInput.SilverBox) end
    if moneyInput.CopperBox then SkinBase.SkinEditBox(moneyInput.CopperBox) end
end

local function SkinSendMailArtwork()
    HideFrameTexturesExcept(_G.SendMailFrame, PreserveRegion(_G.SendMailErrorCoin))
    HideMailArtwork(_G.SendMailHorizontalBarLeft)
    HideMailArtwork(_G.SendMailHorizontalBarLeft2)
    HideMailArtwork(_G.SendStationeryBackgroundLeft)
    HideMailArtwork(_G.SendStationeryBackgroundRight)
    HideMailArtwork(_G.SendMailMoneyInset)
    HideMailArtwork(_G.SendMailMoneyBg)
end

local function SkinSendMailControls()
    SkinSendMailArtwork()

    if _G.SendMailNameEditBox then SkinBase.SkinEditBox(_G.SendMailNameEditBox) end
    if _G.SendMailSubjectEditBox then SkinBase.SkinEditBox(_G.SendMailSubjectEditBox) end
    if _G.SendMailBodyEditBox then SkinBase.SkinEditBox(_G.SendMailBodyEditBox) end

    SkinMoneyInputFrame(_G.SendMailMoney)
    SkinBase.SkinButton(_G.SendMailCancelButton)
    SkinBase.SkinButton(_G.SendMailMailButton)
    SkinBase.SkinButton(_G.SendMailSendMoneyButton)
    SkinBase.SkinButton(_G.SendMailCODButton)

    if _G.SendMailFrame then
        SkinBase.SkinFrameText(_G.SendMailFrame, { recurse = true })
        SkinBase.LockFrameTextObjects(_G.SendMailFrame, 5)
        SkinBase.ApplyButtonFontObjectsDeep(_G.SendMailFrame, 4)
    end

    for i = 1, 16 do
        SkinMailIconButton(_G["SendMailAttachment" .. i])
    end
end

local function SkinOpenMailArtwork()
    HideFrameTexturesExcept(_G.OpenMailFrame)
    HideMailArtwork(_G.OpenMailHorizontalBarLeft)
    HideMailArtwork(_G.OpenStationeryBackgroundLeft)
    HideMailArtwork(_G.OpenStationeryBackgroundRight)
    HideMailArtwork(_G.OpenMailArithmeticLine)

    if _G.ConsortiumMailFrame and _G.ConsortiumMailFrame.CommissionPaidDisplay then
        HideMailArtwork(_G.ConsortiumMailFrame.CommissionPaidDisplay)
    end
end

local function SkinOpenMailFrame()
    local frame = _G.OpenMailFrame
    if not frame then return end

    if not SkinBase.IsSkinned(frame) then
        SkinBase.SkinButtonFrameTemplate(frame)
        SkinBase.MarkSkinned(frame)
    end

    LowerFrameBackdrop(frame)
    SkinOpenMailArtwork()
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 5)
    SkinBase.ApplyButtonFontObjectsDeep(frame, 4)
    SkinBase.SkinButton(_G.OpenMailReportSpamButton)
    SkinBase.SkinButton(_G.OpenMailCancelButton)
    SkinBase.SkinButton(_G.OpenMailDeleteButton)
    SkinBase.SkinButton(_G.OpenMailReplyButton)
    SkinMailIconButton(_G.OpenMailLetterButton)
    SkinMailIconButton(_G.OpenMailMoneyButton)

    for i = 1, 16 do
        SkinMailIconButton(_G["OpenMailAttachmentButton" .. i])
    end
end

local function HookMailRefreshes()
    if mailRefreshHooksInstalled then return end
    if _G.InboxFrame_Update then hooksecurefunc("InboxFrame_Update", SkinMailItems) end
    if _G.SendMailFrame_Update then hooksecurefunc("SendMailFrame_Update", SkinSendMailControls) end
    if _G.OpenMail_Update then hooksecurefunc("OpenMail_Update", SkinOpenMailFrame) end
    mailRefreshHooksInstalled = true
end

local function SkinMail()
    if not IsSettingEnabled("skinMail") then return end
    HookMailRefreshes()

    local frame = _G.MailFrame
    if frame and not SkinBase.IsSkinned(frame) then
        SkinBase.SkinButtonFrameTemplate(frame)
        SkinBase.SkinTabGroup(CollectNumberedTabs("MailFrame", 2), frame)
        SkinBase.MarkSkinned(frame)
    end
    if frame then
        LowerFrameBackdrop(frame)
        SkinBase.SkinFrameText(frame, { recurse = true })
        SkinBase.LockFrameTextObjects(frame, 4)
        SkinBase.ApplyButtonFontObjectsDeep(frame, 4)
    end

    SkinMailItems()
    SkinSendMailControls()
    SkinOpenMailFrame()
end

local function RefreshMail()
    RefreshBackdropColors(_G.MailFrame)
    RefreshBackdropColors(_G.OpenMailFrame)
    if IsSettingEnabled("skinMail") then
        SkinMailItems()
        SkinSendMailControls()
        SkinOpenMailFrame()
    end
end

_G.QUI_RefreshMailColors = RefreshMail
if ns.Registry then
    ns.Registry:Register("skinMail", {
        refresh = RefreshMail,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_MailFrame", SkinMail, 0)
