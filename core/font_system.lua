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
--   - ObjectiveTracker: per-frame ApplyFontToFrameRecursive below

-- Track if hooks are already set up (one-time per API; some Blizzard frames
-- are loaded lazily, so hook setup is retried until each target exists).
local objectiveTrackerFrameHooked = false
local objectiveTrackerAddObjectiveHooked = false
local objectiveTrackerSetHeaderHooked = false
local chatFontHooksInitialized = false
local originalGlobalFonts = ns.Helpers.CreateStateTable()
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

local function GetGeneralSettings()
    return QUICore.db and QUICore.db.profile and QUICore.db.profile.general
end

-- Apply font to a single FontString (preserving size/flags)
local function ApplyFontToFontString(fontString, fontPath)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    if fontString.IsForbidden and fontString:IsForbidden() then return end
    local currentFont, size, flags = fontString:GetFont()
    if size and size > 0 then
        if not originalGlobalFonts[fontString] then
            -- Capture the original font OBJECT (not just the file) so restore
            -- can put Blizzard's real FontFamily back losslessly, preserving
            -- its per-script (CJK) fallback.
            local originalObject = fontString.GetFontObject and fontString:GetFontObject()
            originalGlobalFonts[fontString] = { font = currentFont, flags = flags, object = originalObject }
        end
        if currentFont ~= fontPath then
            -- Use a per-script family so Blizzard UI keeps CJK fallback under
            -- the QUI font; fall back to the single file when unavailable.
            local family = Helpers and Helpers.GetFontFamilyObject and Helpers.GetFontFamilyObject(fontPath, size, flags or "")
            if family and fontString.SetFontObject then
                fontString:SetFontObject(family)
            else
                fontString:SetFont(fontPath, size, flags or "")
            end
        end
    end
end

local function RestoreFontString(fontString)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    if fontString.IsForbidden and fontString:IsForbidden() then return end

    local original = originalGlobalFonts[fontString]
    if not original then return end

    -- Prefer restoring the original font OBJECT so Blizzard's FontFamily (and
    -- its CJK fallback) comes back intact; fall back to the file otherwise.
    if original.object and fontString.SetFontObject then
        pcall(fontString.SetFontObject, fontString, original.object)
        originalGlobalFonts[fontString] = nil
        return
    end

    if not original.font then
        originalGlobalFonts[fontString] = nil
        return
    end

    local _, size, flags = fontString:GetFont()
    if size and size > 0 then
        fontString:SetFont(original.font, size, flags or original.flags or "")
    end
    originalGlobalFonts[fontString] = nil
end

local function ForEachFontStringInFrame(frame, callback)
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    -- Skip UIWidget template frames (have widgetType) and widget containers
    -- (have RegisterForWidgetSet). Their FontStrings are read by secure
    -- Blizzard code that fails on tainted GetStringHeight() results.
    if frame.widgetType or frame.RegisterForWidgetSet then return end

    local okRegions, regions = pcall(function()
        return { frame:GetRegions() }
    end)
    if okRegions then
        for _, region in ipairs(regions) do
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                callback(region)
            end
        end
    end

    local okChildren, children = pcall(function()
        return { frame:GetChildren() }
    end)
    if okChildren then
        for _, child in ipairs(children) do
            ForEachFontStringInFrame(child, callback)
        end
    end
end

-- Recursively apply font to all FontStrings in a frame
-- TAINT SAFETY: Skips UIWidget containers and widget template frames.
-- Calling SetFont() on widget FontStrings taints them; Blizzard's
-- ProcessWidget → Setup() then gets secret values from GetStringHeight().
local function ApplyFontToFrameRecursive(frame, fontPath)
    ForEachFontStringInFrame(frame, function(fontString)
        ApplyFontToFontString(fontString, fontPath)
    end)
end

local function RestoreFontInFrameRecursive(frame)
    ForEachFontStringInFrame(frame, RestoreFontString)
end

local function ApplyOrRestoreGlobalFontForFrame(frame, fontPath, shouldApply)
    if shouldApply then
        ApplyFontToFrameRecursive(frame, fontPath)
    else
        RestoreFontInFrameRecursive(frame)
    end
end

function QUICore:ApplyGlobalFontToObjectiveTracker()
    if not ObjectiveTrackerFrame then return end
    local settings = GetGeneralSettings()
    local shouldApply = IsGlobalFontEnabled()

    -- If the objective tracker skin is enabled, its skin module owns tracker
    -- typography. The global font system should not restore over it when the
    -- global Blizzard font toggle is turned off.
    if not shouldApply and settings and settings.skinObjectiveTracker then
        return
    end

    ApplyOrRestoreGlobalFontForFrame(ObjectiveTrackerFrame, GetGlobalFontPath(), shouldApply)
end

function QUICore:ApplyGlobalFontToGameMenu()
    if not GameMenuFrame then return end
    local settings = GetGeneralSettings()
    local shouldApply = IsGlobalFontEnabled()

    -- Game menu skinning has its own font sizing and overlay text. When that
    -- skin is active, disabling the global font should not undo the skin.
    if not shouldApply and settings and settings.skinGameMenu then
        return
    end

    ApplyOrRestoreGlobalFontForFrame(GameMenuFrame, GetGlobalFontPath(), shouldApply)
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

    -- Hook ObjectiveTracker updates (check if function exists - API varies by expansion)
    if not objectiveTrackerFrameHooked and ObjectiveTrackerFrame then
        -- TAINT SAFETY: Defer all work to break taint chain from secure context.
        if type(ObjectiveTracker_Update) == "function" then
            hooksecurefunc("ObjectiveTracker_Update", function()
                C_Timer.After(0, function()
                    QUICore:ApplyGlobalFontToObjectiveTracker()
                end)
            end)
        else
            -- Fallback: hook frame's OnShow for expansion versions without ObjectiveTracker_Update
            ObjectiveTrackerFrame:HookScript("OnShow", function(self)
                C_Timer.After(0, function()
                    QUICore:ApplyGlobalFontToObjectiveTracker()
                end)
            end)
        end
        objectiveTrackerFrameHooked = true
    end

    if not objectiveTrackerAddObjectiveHooked and ObjectiveTrackerBlockMixin and ObjectiveTrackerBlockMixin.AddObjective then
        hooksecurefunc(ObjectiveTrackerBlockMixin, "AddObjective", function()
            C_Timer.After(0, function()
                QUICore:ApplyGlobalFontToObjectiveTracker()
            end)
        end)
        objectiveTrackerAddObjectiveHooked = true
    end

    if not objectiveTrackerSetHeaderHooked and ObjectiveTrackerBlockMixin and ObjectiveTrackerBlockMixin.SetHeader then
        hooksecurefunc(ObjectiveTrackerBlockMixin, "SetHeader", function()
            C_Timer.After(0, function()
                QUICore:ApplyGlobalFontToObjectiveTracker()
            end)
        end)
        objectiveTrackerSetHeaderHooked = true
    end

    -- Set up chat hooks (one-time)
    if not chatFontHooksInitialized then
        chatFontHooksInitialized = true

        -- Tooltip font display is handled per-instance by
        -- skinning/system/tooltips.lua (ApplyTooltipFontSizeToFrame).
        -- Do NOT use ApplyFontToFrameRecursive on tooltips — it walks into
        -- UIWidget child containers whose FontStrings inherit from shared
        -- font objects; tainting them breaks GetStringHeight() in combat.

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

    self:ApplyGlobalFontToObjectiveTracker()
    self:ApplyGlobalFontToGameMenu()

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
