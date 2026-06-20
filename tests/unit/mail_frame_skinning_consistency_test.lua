-- tests/unit/mail_frame_skinning_consistency_test.lua
-- Run: lua tests/unit/mail_frame_skinning_consistency_test.lua
--
-- Source guard for Blizzard_MailFrame coverage. MailFrame, SendMailFrame,
-- fixed inbox rows, and OpenMailFrame are separate enough that a single
-- recursive pass from MailFrame leaves visible native controls behind.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local function assertBefore(text, first, second, reason)
    local a = text:find(first, 1, true)
    local b = text:find(second, 1, true)
    assert(a and b and a < b, reason)
end

local mailXml = readFile("tests/framexml/Interface/AddOns/Blizzard_MailFrame/MailFrame.xml")
local mailLua = readFile("tests/framexml/Interface/AddOns/Blizzard_MailFrame/MailFrame.lua")

assertContains(mailXml, "<Frame name=\"MailItem1\" inherits=\"MailItemTemplate\">",
    "local FrameXML must expose fixed inbox rows")
assertContains(mailXml, "<Size x=\"305\" y=\"45\"/>",
    "local FrameXML must keep mail rows at the audited height")
assertContains(mailXml, "<Anchor point=\"TOPLEFT\" x=\"13\" y=\"-70\"/>",
    "local FrameXML must keep the first inbox row at the audited offset")
assertContains(mailXml, "<Anchor point=\"CENTER\" relativePoint=\"BOTTOMLEFT\" x=\"30\" y=\"114\"/>",
    "local FrameXML must keep the previous-page button at the audited offset")
assertContains(mailXml, "<Anchor point=\"CENTER\" relativePoint=\"BOTTOMLEFT\" x=\"305\" y=\"114\"/>",
    "local FrameXML must keep the next-page button at the audited offset")
assertContains(mailXml, "<Size x=\"32\" y=\"32\"/>",
    "local FrameXML must keep inbox page buttons at the audited hitbox size")
assertContains(mailXml, "<Button name=\"OpenAllMail\" text=\"OPEN_ALL_MAIL_BUTTON\"",
    "local FrameXML must expose the inbox Open All button")
assertContains(mailXml, "<EditBox name=\"SendMailBodyEditBox\"",
    "local FrameXML must expose the send body editbox")
assertContains(mailXml, "<EditBox name=\"SendMailNameEditBox\"",
    "local FrameXML must expose the recipient editbox")
assertContains(mailXml, "<EditBox name=\"SendMailSubjectEditBox\"",
    "local FrameXML must expose the subject editbox")
assertContains(mailXml, "<Frame name=\"OpenMailFrame\" toplevel=\"true\" hidden=\"true\" parent=\"UIParent\"",
    "local FrameXML must expose OpenMailFrame as a separate top-level frame")
assertContains(mailLua, "function InboxFrame_Update()",
    "local FrameXML must expose inbox refresh")
assertContains(mailLua, "function SendMailFrame_Update()",
    "local FrameXML must expose send-mail refresh")
assertContains(mailLua, "function OpenMail_Update()",
    "local FrameXML must expose open-mail refresh")

local toc = readFile("QUI_Skinning/QUI_Skinning.toc")
local interaction = readFile("QUI_Skinning/skinning/frames/interaction.lua")
local mail = readFile("QUI_Skinning/skinning/frames/mail.lua")

assertBefore(toc, "skinning\\frames\\interaction.lua", "skinning\\frames\\mail.lua",
    "Mail skinning must load as a dedicated file after shared interaction-frame skinning")
assertAbsent(interaction, "Blizzard_MailFrame",
    "interaction.lua must not own dedicated MailFrame skinning")
assertAbsent(interaction, "local function SkinMail",
    "interaction.lua must not keep MailFrame helpers after mail.lua split")

for _, needle in ipairs({
    "local function SkinMail()",
    "local function SkinMailItems()",
    "for i = 1, 7 do",
    "_G[\"MailItem\" .. i]",
    "_G[\"MailItem\" .. i .. \"ExpireTime\"]",
    "_G[\"MailItem\" .. i .. \"Button\"]",
    "SkinBase.LockFrameTextObjects(item, 3)",
    "SkinBase.SkinButton(_G.OpenAllMail",
    "local function SkinSendMailControls()",
    "SkinBase.SkinEditBox(_G.SendMailNameEditBox)",
    "SkinBase.SkinEditBox(_G.SendMailSubjectEditBox)",
    "SkinBase.SkinEditBox(_G.SendMailBodyEditBox)",
    "SkinBase.SkinButton(_G.SendMailCancelButton",
    "SkinBase.SkinButton(_G.SendMailMailButton",
    "SkinBase.SkinButton(_G.SendMailSendMoneyButton",
    "SkinBase.SkinButton(_G.SendMailCODButton",
    "_G[\"SendMailAttachment\" .. i]",
    "local function SkinOpenMailFrame()",
    "_G.OpenMailFrame",
    "SkinBase.SkinButtonFrameTemplate(frame)",
    "SkinBase.SkinButton(_G.OpenMailReportSpamButton",
    "SkinBase.SkinButton(_G.OpenMailCancelButton",
    "SkinBase.SkinButton(_G.OpenMailDeleteButton",
    "SkinBase.SkinButton(_G.OpenMailReplyButton",
    "_G[\"OpenMailAttachmentButton\" .. i]",
    "SkinMailIconButton(_G.OpenMailLetterButton",
    "SkinMailIconButton(_G.OpenMailMoneyButton",
    "local function HookMailRefreshes()",
    "hooksecurefunc(\"InboxFrame_Update\", SkinMailItems)",
    "hooksecurefunc(\"SendMailFrame_Update\", SkinSendMailControls)",
    "hooksecurefunc(\"OpenMail_Update\", SkinOpenMailFrame)",
    "SkinBase.OnAddOnLoaded(\"Blizzard_MailFrame\", SkinMail, 0)",
}) do
    assertContains(mail, needle, "Mail skinning must include: " .. needle)
end

for _, needle in ipairs({
    "local function SkinMailIconButton(button)",
    "local function HideMailButtonDecor(button)",
    "local function HideButtonStateTextures(button)",
    "local function InsetButtonBackdrop(button, inset)",
    "local function LowerFrameBackdrop(frame)",
    "local function SkinInboxArtwork()",
    "local function SkinSendMailArtwork()",
    "local function SkinOpenMailArtwork()",
    "HideFrameTexturesExcept(_G.SendMailFrame",
    "_G.SendMailErrorCoin",
    "_G.InboxFrameBg",
    "_G.InboxPrevPageButton",
    "_G.InboxNextPageButton",
    "InsetButtonBackdrop(_G.InboxPrevPageButton, 4)",
    "InsetButtonBackdrop(_G.InboxNextPageButton, 4)",
    "_G.SendMailHorizontalBarLeft",
    "_G.SendMailHorizontalBarLeft2",
    "_G.SendStationeryBackgroundLeft",
    "_G.SendStationeryBackgroundRight",
    "_G.SendMailMoneyInset",
    "_G.SendMailMoneyBg",
    "_G.OpenMailHorizontalBarLeft",
    "_G.OpenStationeryBackgroundLeft",
    "_G.OpenStationeryBackgroundRight",
    "_G.OpenMailArithmeticLine",
    "_G.ConsortiumMailFrame",
    "LowerFrameBackdrop(frame)",
}) do
    assertContains(mail, needle, "Mail artwork skinning must include: " .. needle)
end

assertAbsent(mail, "SkinBase.SkinButton(button, { font = false })",
    "mail item/attachment helpers must not use generic SkinButton because send attachments use normal texture as item icon")
assertContains(mailLua, "sendMailAttachmentButton:SetNormalTexture(itemTexture or",
    "FrameXML must still prove send attachments use normal texture as semantic item icon")

print("OK: mail_frame_skinning_consistency_test")
