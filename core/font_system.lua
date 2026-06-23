---------------------------------------------------------------------------
-- QUI Global Font System
-- SafeSetFont helper and Blizzard UI font override system.
-- Extracted from core/main.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

local LSM = ns.LSM
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- SAFE FONT HELPER
---------------------------------------------------------------------------

function QUICore:SafeSetFont(fontString, fontPath, size, flags)
    if not fontString then return end
    -- Route through the CJK-aware family setter so QUI text renders Chinese/
    -- Korean glyphs regardless of the selected locale (the family keeps the
    -- given roman font and only adds CJK members — appearance is unchanged for
    -- Latin users). Degrades to a single-file SetFont when the family API is
    -- unavailable. This is the addon-wide font choke point, so fixing it here
    -- gives every SafeSetFont caller (datatext panels, minimap clock, etc.)
    -- CJK fallback for free.
    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fontString, fontPath, size, flags or "")
    else
        fontString:SetFont(fontPath, size, flags or "")
    end
    -- Check if font was actually set (GetFont returns nil if failed)
    local actualFont = fontString:GetFont()
    if not actualFont then
        -- Fallback to guaranteed Blizzard font
        fontString:SetFont("Fonts\\FRIZQT__.TTF", size, flags or "")
    end
end

---------------------------------------------------------------------------
-- GLOBAL FONT OVERRIDE FOR BLIZZARD UI
---------------------------------------------------------------------------

-- Fallback to bundled Quazii font (always available, loaded early in media.lua).
-- Derive the assets dir from Helpers.AssetPath so a folder rename can't strand it.
local QUAZII_FONT_PATH = ((Helpers and Helpers.AssetPath) or [[Interface\AddOns\QUI\assets\]]) .. "Quazii.ttf"

-- TAINT SAFETY: Some shared Font objects are unsafe to modify.
-- Calling SetFont() on Font objects used by secure UI systems (e.g.,
-- GameFontNormal → UIWidgetTemplateTextWithState, NumberFontNormal →
-- ActionButton Count) taints ALL derived FontStrings. During combat,
-- Blizzard's secure code calls GetStringHeight()/GetStringWidth() on
-- those FontStrings and gets secret/tainted values → arithmetic errors.
--
-- EXCEPTION: Tooltip-specific Font objects (GameTooltipHeaderText,
-- GameTooltipText) are safe to modify. Their derived FontStrings are
-- NOT read by secure UIWidget code, so GetStringWidth() remains
-- non-secret. Calling SetFont() on the Font object (NOT on individual
-- FontStrings) propagates size changes without per-FontString taint.
-- See skinning/system/tooltips.lua ApplyFontSizeViaFontObjects().
--
-- Directly calling SetFont() on individual FontStrings (e.g.,
-- GameTooltipTextLeft1) DOES taint them — avoid this for GameTooltip.
--
-- All non-tooltip font overrides are applied PER-INSTANCE:
--   - Chat frames: per-frame SetFont below
--   - ObjectiveTracker/GameMenu: covered by ApplyGlobalFontObjects (font-object override)

-- Track if hooks are already set up (one-time per API; some Blizzard frames
-- are loaded lazily, so hook setup is retried until each target exists).
local chatFontHooksInitialized = false
local originalChatFonts = ns.Helpers.CreateStateTable()
-- Pristine Blizzard DAMAGE_TEXT_FONT captured once before any QUI override, so
-- the SCT font can be restored when the toggle is turned off (mirrors the
-- chat/objective restore paths). false = not yet captured.
local originalDamageTextFont = false

-- Pristine Blizzard STANDARD_TEXT_FONT captured once before any QUI override, so
-- the engine default can be restored when the global font is turned off (mirrors
-- the DAMAGE_TEXT_FONT capture below). false = not yet captured.
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

-- Shared Blizzard font OBJECTS overridden when the global font is enabled.
-- Reference-proven leaf set. The bare roots GameFontNormal/GameFontHighlight/
-- GameFontDisable/GameFontNormalSmall are DELIBERATELY excluded — they are the
-- most-inherited secure-template roots; the reference avoids them and so do we.
-- Each name is _G-guarded, so cross-version entries that do not exist on 12.0.7
-- are silently skipped.
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

-- Pristine {font,size,flags} per object, captured once before first override so
-- restore (toggle off) is lossless.
local originalFontObjects = ns.Helpers.CreateStateTable()

-- Apply (shouldApply=true) or restore (false) QUI face + general.fontOutline on
-- every shared font OBJECT in FONT_OBJECT_SET. Native SIZE is preserved. The
-- object carries the face, so inheriting FontStrings update without a walk and
-- survive Blizzard's hover/disable swaps. CJK locales are skipped by the caller.
function QUICore:ApplyGlobalFontObjects(shouldApply)
    local fontPath = GetGlobalFontPath()
    local outline = (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    for _, name in ipairs(FONT_OBJECT_SET) do
        local obj = _G[name]
        if obj and obj.GetFont and obj.SetFont then
            if shouldApply then
                local _, size = obj:GetFont()
                if size and size > 0 then
                    -- Capture pristine {font,size,flags} only when we actually
                    -- apply, so the capture/restore size>0 guards stay symmetric
                    -- (a size-0 object is never captured, never leaks an entry).
                    if not originalFontObjects[obj] then
                        local f, s, fl = obj:GetFont()
                        originalFontObjects[obj] = { font = f, size = s, flags = fl }
                    end
                    -- Outline TIERING: apply the user's outline ONLY to fonts that
                    -- NATIVELY carry an outline (large/display text — zone, numbers,
                    -- nameplates). Fonts Blizzard ships WITHOUT an outline (quest,
                    -- mail, parchment and other dark-fill body text) keep their
                    -- native flags, so a forced black outline never turns dark body
                    -- text into a black-on-black blob on a skinned backdrop. Mirrors
                    -- the reference, which only outlines its display-font tier and
                    -- leaves body/quest/mail at NONE/SHADOW.
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

-- SetFontObject re-bases a frame's inherited layout props. On a chat
-- ScrollingMessageFrame a freshly built FontFamily carries no justification,
-- so the frame falls back to the WoW default (CENTER) and renders every line
-- centered once the Blizzard frame is visible again (e.g. the QUI chat takeover
-- is off). Blizzard's own ChatFrameMixin:OnLoad sets the font object THEN
-- re-asserts SetJustifyH("LEFT") for exactly this reason — mirror it here.
-- justifyH/justifyV come from the capture-time snapshot (the frame's real
-- justification before any QUI font was applied); GetJustifyH/V are never secret
-- (JustifyHorizontal/Vertical enums), so the getter result feeds the setter.
local function SetChatFontObject(chatFrame, fontObject, justifyH, justifyV)
    if not (chatFrame and chatFrame.SetFontObject and fontObject) then return false end
    if not pcall(chatFrame.SetFontObject, chatFrame, fontObject) then return false end
    if justifyH and chatFrame.SetJustifyH then pcall(chatFrame.SetJustifyH, chatFrame, justifyH) end
    if justifyV and chatFrame.SetJustifyV then pcall(chatFrame.SetJustifyV, chatFrame, justifyV) end
    return true
end

-- Snapshot a chat frame's pristine font + justification exactly once, before
-- any QUI font is applied, so both the SetFontObject re-base above and the
-- flip-back restore can put the original justification back.
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
                        -- SetFont leaves justify alone, but a prior SetFontObject
                        -- may have re-based it — restore the captured justification.
                        if original.justifyH and chatFrame.SetJustifyH then
                            pcall(chatFrame.SetJustifyH, chatFrame, original.justifyH)
                        end
                        originalChatFonts[chatFrame] = nil
                    end
                end
            end
        end
    end
end

-- TAINT SAFETY: STANDARD_TEXT_FONT is a path-string global read by the engine
-- when CREATING fonts; setting it never mutates an existing (secure) font
-- object, so no FontString is tainted. This is the safe alternative to mutating
-- shared font objects directly. Gated by the global-font toggle AND the locale
-- glyph gate — on CJK clients the Latin-only QUI font would render boxes, so we
-- leave the Blizzard default there.
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
    -- Check if feature is enabled
    if not self.db or not self.db.profile or not self.db.profile.general then return end
    local shouldApply = IsGlobalFontEnabled()

    local fontPath = GetGlobalFontPath()

    -- Set up chat hooks (one-time)
    if not chatFontHooksInitialized then
        chatFontHooksInitialized = true

        -- Tooltip font display is handled per-instance by
        -- skinning/system/tooltips.lua (ApplyTooltipFontSizeToFrame).
        -- Do NOT walk tooltip FontStrings directly — UIWidget child containers
        -- inherit from shared font objects; tainting them breaks GetStringHeight() in combat.

        -- Hook chat frame font size changes
        if FCF_SetChatWindowFontSize then
            -- TAINT SAFETY: Defer to break taint chain from secure context.
            -- Live signature is FCF_SetChatWindowFontSize(self, chatFrame, fontSize)
            -- (Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua:882). hooksecurefunc
            -- forwards the real call args, so the callback must absorb the leading
            -- self/slider arg — otherwise `chatFrame` receives `self` and the global-font
            -- re-apply silently targets the wrong object. Mirror Blizzard's nil fallback.
            hooksecurefunc("FCF_SetChatWindowFontSize", function(_self, chatFrame, fontSize)
                C_Timer.After(0, function()
                    if not IsGlobalFontEnabled() then return end
                    local fp = GetGlobalFontPath()
                    if not chatFrame and FCF_GetCurrentChatFrame then
                        chatFrame = FCF_GetCurrentChatFrame()
                    end
                    if chatFrame and type(chatFrame.GetFont) == "function" and type(chatFrame.SetFont) == "function" then
                        -- Apply global font directly to ScrollingMessageFrame (not just children)
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

        -- Event handler for chat window resets (font persistence across new messages)
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

    -- Shared font-OBJECT override (static text face+outline). CJK clients skip:
    -- the Latin-only QUI font would render boxes, so leave Blizzard objects.
    do
        local glyphFallback = Helpers and Helpers.GetLocaleGlyphFallback and Helpers.GetLocaleGlyphFallback()
        self:ApplyGlobalFontObjects(shouldApply and not glyphFallback)
    end

    -- Apply to existing chat frames (SetFont on the frame itself for new message persistence)
    self:ApplyGlobalFontToChatFrames(fontPath, shouldApply)

    -- Tooltip fonts are applied per-instance by skinning/system/tooltips.lua.
    -- Recursive application here would taint UIWidget child FontStrings.

    -- Override scrolling combat text (floating damage/heal numbers) font.
    -- DAMAGE_TEXT_FONT is a simple global string variable used by Blizzard's
    -- CombatText system — safe to override without taint concerns.
    if shouldApply and self.db.profile.general.overrideSCTFont then
        if originalDamageTextFont == false then
            originalDamageTextFont = _G.DAMAGE_TEXT_FONT
        end
        _G.DAMAGE_TEXT_FONT = fontPath
    elseif originalDamageTextFont ~= false then
        _G.DAMAGE_TEXT_FONT = originalDamageTextFont
        originalDamageTextFont = false
    end

    -- Notify the options panel so its own FontStrings pick up the new font
    -- immediately if the panel is currently open.  GUI:OnFontChanged() is a
    -- no-op when the panel is hidden, so this is safe to call unconditionally.
    local gui = QUI and QUI.GUI
    if gui and gui.OnFontChanged then
        gui:OnFontChanged()
    end
end
