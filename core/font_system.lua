local ADDON_NAME, ns = ...
local QUICore = ns.Addon

local LSM = ns.LSM
local Helpers = ns.Helpers

function QUICore:SafeSetFont(fontString, fontPath, size, flags)
    if not fontString then return end
    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fontString, fontPath, size, flags or "")
    else
        fontString:SetFont(fontPath, size, flags or "")
    end
    local actualFont = fontString:GetFont()
    if not actualFont then
        fontString:SetFont("Fonts\\FRIZQT__.TTF", size, flags or "")
    end
end

local QUAZII_FONT_PATH = ((Helpers and Helpers.AssetPath) or [[Interface\AddOns\QUI\assets\]]) .. "Quazii.ttf"

local chatFontHooksInitialized = false
local originalChatFonts = ns.Helpers.CreateStateTable()
local originalDamageTextFont = false

local originalStandardTextFont = false

local function GetGlobalFontPath()
    if not QUICore.db or not QUICore.db.profile or not QUICore.db.profile.general then
        return QUAZII_FONT_PATH
    end
    local fontName = QUICore.db.profile.general.font or "Quazii"
    local fontPath = LSM:Fetch("font", fontName)
    return fontPath or QUAZII_FONT_PATH
end

local function IsGlobalFontEnabled()
    return QUICore.db
        and QUICore.db.profile
        and QUICore.db.profile.general
        and QUICore.db.profile.general.applyGlobalFontToBlizzard
end

local FONT_OBJECT_SET = {
    "AchievementFont_Small", "ChatBubbleFont", "CoreAbilityFont",
    "DestinyFontHuge", "DestinyFontMed", "ErrorFont",
    "Fancy12Font", "Fancy14Font", "Fancy22Font", "Fancy24Font",
    "FriendsFont_11", "FriendsFont_Large", "FriendsFont_Normal", "FriendsFont_Small", "FriendsFont_UserText",
    "Game10Font_o1", "Game120Font", "Game12Font", "Game13FontShadow",
    "Game15Font_o1", "Game15Font_Shadow", "Game16Font", "Game17Font_Shadow", "Game18Font",
    "Game20Font", "Game22Font", "Game24Font", "Game30Font", "Game40Font", "Game42Font",
    "Game46Font", "Game48Font", "Game48FontShadow", "Game60Font", "Game72Font", "GameFont_Gigantic",
    "GameFontHighlightHuge2", "GameFontHighlightMedium", "GameFontHighlightSmall2",
    "GameFontNormalHuge", "GameFontNormalHuge2", "GameFontNormalLarge", "GameFontNormalLarge2",
    "GameFontNormalMed1", "GameFontNormalMed2", "GameFontNormalMed3", "GameFontNormalSmall2",
    "InvoiceFont_Med", "InvoiceFont_Small", "MailFont_Large", "MailTextFontNormal",
    "Number11Font", "Number12Font", "Number12Font_o1", "Number13Font", "Number13FontGray",
    "Number13FontWhite", "Number13FontYellow", "Number14FontGray", "Number14FontWhite",
    "Number15Font", "Number18Font", "Number18FontWhite", "NumberFontNormal", "NumberFontNormalSmall",
    "NumberFont_Outline_Huge", "NumberFont_Outline_Large", "NumberFont_Outline_Med",
    "NumberFont_OutlineThick_Mono_Small", "NumberFont_Shadow_Med", "NumberFont_Shadow_Small", "NumberFont_Small",
    "ObjectiveFont", "ObjectiveTrackerFont12", "ObjectiveTrackerFont13", "ObjectiveTrackerFont14",
    "ObjectiveTrackerFont15", "ObjectiveTrackerFont16", "ObjectiveTrackerFont17", "ObjectiveTrackerFont18",
    "ObjectiveTrackerFont19", "ObjectiveTrackerFont20", "ObjectiveTrackerFont21", "ObjectiveTrackerFont22",
    "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont", "PriceFont",
    "QuestFont", "QuestFont_39", "QuestFont_Enormous", "QuestFont_Huge", "QuestFont_Large",
    "QuestFont_Larger", "QuestFontNormalSmall", "QuestFont_Shadow_Enormous", "QuestFont_Shadow_Huge",
    "QuestFont_Shadow_Small", "QuestFont_Shadow_Super_Huge", "QuestFont_Super_Huge", "QuestTitleFont",
    "ReputationDetailFont", "SpellFont_Small", "SubSpellFont", "SubZoneTextFont",
    "SystemFont16_Shadow_ThickOutline", "SystemFont_Huge1", "SystemFont_Huge1_Outline", "SystemFont_Huge2",
    "SystemFont_Large", "SystemFont_LargeNamePlate", "SystemFont_LargeNamePlateFixed",
    "SystemFont_Med1", "SystemFont_Med2", "SystemFont_Med3",
    "SystemFont_NamePlate", "SystemFont_NamePlateCastBar", "SystemFont_NamePlateFixed", "SystemFont_NamePlate_Outlined",
    "SystemFont_Outline", "SystemFont_Outline_Small", "SystemFont_OutlineThick_Huge2", "SystemFont_OutlineThick_WTF",
    "SystemFont_Shadow_Huge1", "SystemFont_Shadow_Huge2", "SystemFont_Shadow_Huge3", "SystemFont_Shadow_Huge4",
    "SystemFont_Shadow_Large", "SystemFont_Shadow_Large2", "SystemFont_Shadow_Large_Outline",
    "SystemFont_Shadow_Med1", "SystemFont_Shadow_Med2", "SystemFont_Shadow_Med3", "SystemFont_Shadow_Small",
    "SystemFont_Small", "SystemFont_Small2", "SystemFont_Tiny",
    "WorldMapTextFont", "ZoneTextFont",
}

local originalFontObjects = ns.Helpers.CreateStateTable()

function QUICore:ApplyGlobalFontObjects(shouldApply)
    local fontPath = GetGlobalFontPath()
    local outline = (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    for _, name in ipairs(FONT_OBJECT_SET) do
        local obj = _G[name]
        if obj and obj.GetFont and obj.SetFont then
            if shouldApply then
                local _, size = obj:GetFont()
                if size and size > 0 then
                    if not originalFontObjects[obj] then
                        local f, s, fl = obj:GetFont()
                        originalFontObjects[obj] = { font = f, size = s, flags = fl }
                    end
                    local nativeFlags = originalFontObjects[obj].flags or ""
                    local applied = nativeFlags:find("OUTLINE") and outline or nativeFlags
                    obj:SetFont(fontPath, size, applied)
                end
            else
                local c = originalFontObjects[obj]
                if c and c.font and c.size and c.size > 0 then
                    obj:SetFont(c.font, c.size, c.flags or "")
                    originalFontObjects[obj] = nil
                end
            end
        end
    end
end

local function SetChatFontObject(chatFrame, fontObject, justifyH, justifyV)
    if not (chatFrame and chatFrame.SetFontObject and fontObject) then return false end
    if not ns.SafeCallMethod("best-effort-style", chatFrame, "SetFontObject", fontObject) then return false end
    if justifyH and chatFrame.SetJustifyH then ns.SafeCallMethod("best-effort-style", chatFrame, "SetJustifyH", justifyH) end
    if justifyV and chatFrame.SetJustifyV then ns.SafeCallMethod("best-effort-style", chatFrame, "SetJustifyV", justifyV) end
    return true
end

local function CaptureOriginalChatFont(chatFrame, currentFont, flags)
    local snap = originalChatFonts[chatFrame]
    if snap then return snap end
    snap = {
        font = currentFont,
        flags = flags,
        object = chatFrame.GetFontObject and chatFrame:GetFontObject(),
        justifyH = chatFrame.GetJustifyH and chatFrame:GetJustifyH(),
        justifyV = chatFrame.GetJustifyV and chatFrame:GetJustifyV(),
    }
    originalChatFonts[chatFrame] = snap
    return snap
end

function QUICore:ApplyGlobalFontToChatFrames(fontPath, shouldApply)
    for i = 1, (NUM_CHAT_WINDOWS or 0) do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame.GetFont and chatFrame.SetFont then
            local currentFont, size, flags = chatFrame:GetFont()
            if size then
                if shouldApply then
                    local snap = CaptureOriginalChatFont(chatFrame, currentFont, flags)
                    if currentFont ~= fontPath then
                        local family = Helpers and Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(fontPath, size, flags or "")
                        if not SetChatFontObject(chatFrame, family, snap.justifyH, snap.justifyV) then
                            chatFrame:SetFont(fontPath, size, flags or "")
                        end
                    end
                else
                    local original = originalChatFonts[chatFrame]
                    if original and original.object and chatFrame.SetFontObject then
                        SetChatFontObject(chatFrame, original.object, original.justifyH, original.justifyV)
                        originalChatFonts[chatFrame] = nil
                    elseif original and original.font then
                        chatFrame:SetFont(original.font, size, flags or original.flags or "")
                        if original.justifyH and chatFrame.SetJustifyH then
                            ns.SafeCallMethod("best-effort-style", chatFrame, "SetJustifyH", original.justifyH)
                        end
                        originalChatFonts[chatFrame] = nil
                    end
                end
            end
        end
    end
end

function QUICore:ApplyGlobalDefaultFont()
    if not self.db or not self.db.profile or not self.db.profile.general then return end
    local glyphFallback = Helpers and Helpers.GetLocaleGlyphFallback and Helpers.GetLocaleGlyphFallback()
    if IsGlobalFontEnabled() and not glyphFallback then
        if originalStandardTextFont == false then
            originalStandardTextFont = _G.STANDARD_TEXT_FONT
        end
        _G.STANDARD_TEXT_FONT = GetGlobalFontPath()
    elseif originalStandardTextFont ~= false then
        _G.STANDARD_TEXT_FONT = originalStandardTextFont
        originalStandardTextFont = false
    end
end

function QUICore:ApplyGlobalFont()
    if not self.db or not self.db.profile or not self.db.profile.general then return end
    local shouldApply = IsGlobalFontEnabled()

    local fontPath = GetGlobalFontPath()

    if not chatFontHooksInitialized then
        chatFontHooksInitialized = true

        if FCF_SetChatWindowFontSize then
            hooksecurefunc("FCF_SetChatWindowFontSize", function(_self, chatFrame, fontSize)
                C_Timer.After(0, function()
                    if not IsGlobalFontEnabled() then return end
                    local fp = GetGlobalFontPath()
                    if not chatFrame and FCF_GetCurrentChatFrame then
                        chatFrame = FCF_GetCurrentChatFrame()
                    end
                    if chatFrame and type(chatFrame.GetFont) == "function" and type(chatFrame.SetFont) == "function" then
                        local currentFont, size, flags = chatFrame:GetFont()
                        local snap = CaptureOriginalChatFont(chatFrame, currentFont, flags)
                        local targetSize = fontSize or size or 14
                        local family = Helpers and Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(fp, targetSize, flags or "")
                        if not SetChatFontObject(chatFrame, family, snap.justifyH, snap.justifyV) then
                            chatFrame:SetFont(fp, targetSize, flags or "")
                        end
                    end
                end)
            end)
        end

        local chatFontEventFrame = CreateFrame("Frame")
        chatFontEventFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
        chatFontEventFrame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
        chatFontEventFrame:SetScript("OnEvent", function()
            if not QUICore.db or not QUICore.db.profile then return end
            if not IsGlobalFontEnabled() then return end
            C_Timer.After(0.05, function()
                local fp = GetGlobalFontPath()
                QUICore:ApplyGlobalFontToChatFrames(fp, true)
            end)
        end)
    end

    do
        local glyphFallback = Helpers and Helpers.GetLocaleGlyphFallback and Helpers.GetLocaleGlyphFallback()
        self:ApplyGlobalFontObjects(shouldApply and not glyphFallback)
    end

    self:ApplyGlobalFontToChatFrames(fontPath, shouldApply)

    if shouldApply and self.db.profile.general.overrideSCTFont then
        if originalDamageTextFont == false then
            originalDamageTextFont = _G.DAMAGE_TEXT_FONT
        end
        _G.DAMAGE_TEXT_FONT = fontPath
    elseif originalDamageTextFont ~= false then
        _G.DAMAGE_TEXT_FONT = originalDamageTextFont
        originalDamageTextFont = false
    end

    local gui = QUI and QUI.GUI
    if gui and gui.OnFontChanged then
        gui:OnFontChanged()
    end
end
