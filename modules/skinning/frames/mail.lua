local _, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
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
    if button.GetPushedTexture then ClampTexture(button:GetPushedTexture()) end
    if button.GetDisabledTexture then ClampTexture(button:GetDisabledTexture()) end
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
    if button.GetHighlightTexture then PreserveButtonTexture(preserved, button:GetHighlightTexture()) end
    if button.GetCheckedTexture then PreserveButtonTexture(preserved, button:GetCheckedTexture()) end

    HideFrameTexturesExcept(button, preserved)

    local name = button.GetName and button:GetName()
    if name then
        HideMailArtwork(_G[name .. "Slot"])
        HideMailArtwork(_G[name .. "CODBackground"])
    end
end

local function RefreshMailIconBorder(button)
    if not IsSettingEnabled("skinMail") or (button.IsForbidden and button:IsForbidden()) then return end
    local nativeBorder = button.IconBorder
    local backdrop = SkinBase.GetBackdrop(button)
    if not nativeBorder or not backdrop then return end
    local r, g, b, a = SkinBase.GetWindowColors()
    if nativeBorder:IsShown() and nativeBorder.GetVertexColor then
        r, g, b, a = nativeBorder:GetVertexColor()
    end
    SkinBase.SetBackdropColors(backdrop, { r, g, b, a or 1 }, nil)
end

local function SkinMailIconButton(button)
    if not button or (button.IsForbidden and button:IsForbidden()) then return end

    HideButtonStateTextures(button)
    HideMailButtonDecor(button)

    local icon = button.Icon or button.icon or (button.GetNormalTexture and button:GetNormalTexture())
    if icon then SkinBase.RoundIconTexture(button, icon) end
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetColorTexture(1, 1, 1, 0.12)
        highlight:SetAllPoints(button)
        SkinBase.RoundIconTexture(button, highlight)
    end
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        local r, g, b = SkinBase.GetSkinColors()
        checked:SetColorTexture(r, g, b, 0.25)
        checked:SetAllPoints(button)
        SkinBase.RoundIconTexture(button, checked)
    end

    if SkinBase.IsStyled(button) then
        SkinBase.RefreshWidget(button)
    else
        local sr, sg, sb, sa, bgr, bgg, bgb = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(button, sr, sg, sb, sa,
            min(bgr + ICON_BUTTON_BG_BOOST, 1),
            min(bgg + ICON_BUTTON_BG_BOOST, 1),
            min(bgb + ICON_BUTTON_BG_BOOST, 1),
            1)
        SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
        SkinBase.SetFrameData(button, "skinKind", "button")
        SkinBase.SetFrameData(button, "bgBoost", ICON_BUTTON_BG_BOOST)
        SkinBase.SetFrameData(button, "skinFont", true)
        SkinBase.MarkStyled(button)
    end

    if button.IconBorder then
        if not SkinBase.GetFrameData(button, "qMailQualityHooked") then
            for _, method in ipairs({ "SetVertexColor", "Show", "Hide", "SetShown" }) do
                if button.IconBorder[method] then
                    hooksecurefunc(button.IconBorder, method, function() RefreshMailIconBorder(button) end)
                end
            end
            SkinBase.SetFrameData(button, "qMailQualityHooked", true)
        end
        SkinBase.ClampTextureHidden(button.IconBorder, true)
        RefreshMailIconBorder(button)
    end
    SkinBase.LockPooledRowText(button, 2)
end

local function SkinInboxArtwork()
    HideMailArtwork(_G.InboxFrameBg)

    if _G.InboxPrevPageButton then SkinBase.SkinNextPrevButton(_G.InboxPrevPageButton, "prev") end
    if _G.InboxNextPageButton then SkinBase.SkinNextPrevButton(_G.InboxNextPageButton, "next") end
end

local function SkinMailItems()
    if not IsSettingEnabled("skinMail") then return end
    SkinInboxArtwork()

    for i = 1, 7 do
        local item = _G["MailItem" .. i]
        if item then
            SkinBase.SkinScrollRow(item, { hover = false })
            SkinBase.LockPooledRowText(item, 3)
            SkinBase.SkinButton(_G["MailItem" .. i .. "ExpireTime"])
            SkinMailIconButton(_G["MailItem" .. i .. "Button"])
        end
    end

    SkinBase.SkinButton(_G.OpenAllMail)
end

local function SkinMoneyInputFrame(moneyInput)
    if not moneyInput or (moneyInput.IsForbidden and moneyInput:IsForbidden()) then return end
    local fields = {
        moneyInput.gold or moneyInput.GoldBox,
        moneyInput.silver or moneyInput.SilverBox,
        moneyInput.copper or moneyInput.CopperBox,
    }
    for i = 1, 3 do
        local field = fields[i]
        if field and not (field.IsForbidden and field:IsForbidden()) then
            local coin = field.texture or field.Icon
            local alpha = coin and coin:GetAlpha()
            SkinBase.SkinEditBox(field, { font = false })
            if coin then coin:SetAlpha(alpha) end
            SkinBase.SkinFontString(field, { fontOnly = true })
            SkinBase.LockFontObject(field, { fontOnly = true })
            local symbol = field.label or field.CurrencySymbol
            SkinBase.SkinFontString(symbol, { fontOnly = true })
            SkinBase.LockFontObject(symbol, { fontOnly = true })
            SkinBase.RefreshWidget(field)
        end
    end
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
    if not IsSettingEnabled("skinMail") then return end
    SkinSendMailArtwork()

    if _G.SendMailNameEditBox then SkinBase.SkinEditBox(_G.SendMailNameEditBox) end
    if _G.SendMailSubjectEditBox then SkinBase.SkinEditBox(_G.SendMailSubjectEditBox) end
    if _G.SendMailBodyEditBox then SkinBase.SkinEditBox(_G.SendMailBodyEditBox) end

    SkinMoneyInputFrame(_G.SendMailMoney)
    SkinBase.SkinButton(_G.SendMailCancelButton)
    SkinBase.SkinButton(_G.SendMailMailButton)
    if _G.SendMailSendMoneyButton then SkinBase.SkinCheckBox(_G.SendMailSendMoneyButton) end
    if _G.SendMailCODButton then SkinBase.SkinCheckBox(_G.SendMailCODButton) end

    if _G.SendMailFrame then
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

local BODY_TEXT_TYPES = { "P", "H1", "H2", "H3" }
local INVOICE_TEXT = {
    "OpenMailInvoiceItemLabel", "OpenMailInvoicePurchaser", "OpenMailInvoiceSalePrice",
    "OpenMailInvoiceDeposit", "OpenMailInvoiceHouseCut", "OpenMailInvoiceAmountReceived",
    "OpenMailInvoiceNotYetSent", "OpenMailInvoiceMoneyDelay",
}
local CONSORTIUM_TEXT = {
    "OpeningText", "CrafterText", "CommissionReceived", "CrafterNote", "ConsortiumNote",
}

local function RecolorLetterFontString(fs)
    if not fs or (fs.IsForbidden and fs:IsForbidden()) then return end
    SkinBase.SkinFontString(fs)
end

local function RecolorOpenMailText()
    local html = _G.OpenMailBodyText
    if html and html.SetTextColor then
        local helpers = ns.Helpers
        local fontPath = helpers.GetGeneralFont and helpers.GetGeneralFont()
        local outline = (helpers.GetGeneralFontOutline and helpers.GetGeneralFontOutline()) or ""
        for i = 1, #BODY_TEXT_TYPES do
            local el = BODY_TEXT_TYPES[i]
            if fontPath and html.GetFont then
                local _, size = html:GetFont(el)
                if not (issecretvalue and issecretvalue(size))
                    and type(size) == "number" and size > 0 then
                    local family = helpers.GetFontFamilyObject
                        and helpers.GetFontFamilyObject(fontPath, size, outline)
                    if family and html.SetFontObject then
                        html:SetFontObject(el, family)
                    elseif html.SetFont then
                        html:SetFont(el, fontPath, size, outline)
                    end
                end
            end
            html:SetTextColor(el, 0.95, 0.95, 0.95)
        end
    end

    RecolorLetterFontString(_G.OpenMailSubject)
    local sender = _G.OpenMailSender
    if sender and sender.Name then RecolorLetterFontString(sender.Name) end

    for i = 1, #INVOICE_TEXT do RecolorLetterFontString(_G[INVOICE_TEXT[i]]) end
    if _G.InvoiceTextFontNormal then _G.InvoiceTextFontNormal:SetTextColor(0.95, 0.95, 0.95) end
    if _G.InvoiceTextFontSmall then _G.InvoiceTextFontSmall:SetTextColor(0.95, 0.95, 0.95) end

    local cm = _G.ConsortiumMailFrame
    if cm and not (cm.IsForbidden and cm:IsForbidden()) then
        for i = 1, #CONSORTIUM_TEXT do RecolorLetterFontString(cm[CONSORTIUM_TEXT[i]]) end
        local paid = cm.CommissionPaidDisplay
        if paid then RecolorLetterFontString(paid.CommissionPaidText) end
    end
end

local function SkinOpenMailFrame()
    if not IsSettingEnabled("skinMail") then return end
    local frame = _G.OpenMailFrame
    if not frame then return end

    if not SkinBase.IsSkinned(frame) then
        SkinBase.SkinButtonFrameTemplate(frame)
        SkinBase.MarkSkinned(frame)
    end

    LowerFrameBackdrop(frame)
    SkinOpenMailArtwork()
    RecolorOpenMailText()
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
        SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("MailFrame", 2), frame, { resizeToText = true, dockBottom = true })
        SkinBase.MarkSkinned(frame)
    end
    if frame then
        LowerFrameBackdrop(frame)
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
