---------------------------------------------------------------------------
-- QUI Global Font System
-- SafeSetFont helper and Blizzard UI font override system.
-- Extracted from core/main.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

local LSM = LibStub("LibSharedMedia-3.0")

---------------------------------------------------------------------------
-- SAFE FONT HELPER
---------------------------------------------------------------------------

function QUICore:SafeSetFont(fontString, fontPath, size, flags)
    if not fontString then return end
    fontString:SetFont(fontPath, size, flags or "")
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

-- Fallback to bundled Quazii font (always available, loaded early in media.lua)
local QUAZII_FONT_PATH = [[Interface\AddOns\QUI\assets\Quazii.ttf]]

-- TAINT SAFETY: Shared Font object modification is FUNDAMENTALLY UNSAFE.
-- Calling SetFont() on ANY shared Font object from addon code permanently
-- taints that object and ALL derived FontStrings for the entire session.
-- During combat, Blizzard's secure code calls GetStringHeight(),
-- GetStringWidth(), etc. on those FontStrings and gets secret/tainted
-- values, causing arithmetic errors in:
--   - UIWidgetTemplateTextWithState (inherits GameFontNormal) — tooltip
--     widget Setup() fails with "secret number value tainted by 'QUI'"
--   - ActionButton Count/Name text (inherits NumberFontNormal)
--   - Any other secure frame that reads FontString metrics during combat
--
-- All font overrides are applied PER-INSTANCE instead:
--   - Tooltips: skinning/system/tooltips.lua (ApplyTooltipFontSizeToFrame)
--   - Chat frames: per-frame SetFont below
--   - ObjectiveTracker: per-frame ApplyFontToFrameRecursive below
local BLIZZARD_FONT_OBJECTS = {
    -- ALL shared Font objects are excluded — see taint safety note above.
    -- Game fonts: taint UIWidgetTemplateTextWithState (GetStringHeight)
    -- Number fonts: taint ActionButton text metrics
    -- Quest fonts: may be inherited by secure UI elements
    -- Tooltip fonts: handled per-instance by skinning/system/tooltips.lua
    -- Chat fonts: handled per-frame below (SetFont on ScrollingMessageFrame)
}

-- Track if hooks are already set up (one-time)
local globalFontHooksInitialized = false

-- Debounce for hook callbacks
local globalFontPending = false

local function GetGlobalFontPath()
    if not QUICore.db or not QUICore.db.profile or not QUICore.db.profile.general then
        return QUAZII_FONT_PATH
    end
    local fontName = QUICore.db.profile.general.font or "Quazii"
    local fontPath = LSM:Fetch("font", fontName)
    return fontPath or QUAZII_FONT_PATH
end

-- Apply font to a single FontString (preserving size/flags)
local function ApplyFontToFontString(fontString, fontPath)
    if not fontString or not fontString.GetFont or not fontString.SetFont then return end
    local _, size, flags = fontString:GetFont()
    if size and size > 0 then
        fontString:SetFont(fontPath, size, flags or "")
    end
end

-- Recursively apply font to all FontStrings in a frame
local function ApplyFontToFrameRecursive(frame, fontPath)
    if not frame then return end

    -- Apply to direct regions
    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("FontString") then
            ApplyFontToFontString(region, fontPath)
        end
    end

    -- Recurse into children
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        ApplyFontToFrameRecursive(child, fontPath)
    end
end

-- Schedule debounced font application (for hooks)
local function ScheduleGlobalFontApply()
    if globalFontPending then return end
    globalFontPending = true
    C_Timer.After(0.05, function()
        globalFontPending = false
        if QUICore.ApplyGlobalFont then
            QUICore:ApplyGlobalFont()
        end
    end)
end

function QUICore:ApplyGlobalFont()
    -- Check if feature is enabled
    if not self.db or not self.db.profile or not self.db.profile.general then return end
    if not self.db.profile.general.applyGlobalFontToBlizzard then return end

    local fontPath = GetGlobalFontPath()

    -- Override Blizzard font objects
    for _, fontObjName in ipairs(BLIZZARD_FONT_OBJECTS) do
        local fontObj = _G[fontObjName]
        if fontObj and fontObj.GetFont and fontObj.SetFont then
            local _, size, flags = fontObj:GetFont()
            if size then
                fontObj:SetFont(fontPath, size, flags or "")
            end
        end
    end

    -- Set up hooks (one-time)
    if not globalFontHooksInitialized then
        globalFontHooksInitialized = true

        -- Hook ObjectiveTracker updates (check if function exists - API varies by expansion)
        if ObjectiveTrackerFrame then
            -- TAINT SAFETY: Defer all work to break taint chain from secure context.
            if type(ObjectiveTracker_Update) == "function" then
                hooksecurefunc("ObjectiveTracker_Update", function()
                    C_Timer.After(0, function()
                        if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
                        local fp = GetGlobalFontPath()
                        ApplyFontToFrameRecursive(ObjectiveTrackerFrame, fp)
                    end)
                end)
            else
                -- Fallback: hook frame's OnShow for expansion versions without ObjectiveTracker_Update
                ObjectiveTrackerFrame:HookScript("OnShow", function(self)
                    C_Timer.After(0, function()
                        if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
                        local fp = GetGlobalFontPath()
                        ApplyFontToFrameRecursive(self, fp)
                    end)
                end)
            end
        end

        -- Tooltip font display is handled per-instance by
        -- skinning/system/tooltips.lua (ApplyTooltipFontSizeToFrame).
        -- Do NOT use ApplyFontToFrameRecursive on tooltips — it walks into
        -- UIWidget child containers whose FontStrings inherit from shared
        -- font objects; tainting them breaks GetStringHeight() in combat.

        -- Hook chat frame font size changes
        if FCF_SetChatWindowFontSize then
            -- TAINT SAFETY: Defer to break taint chain from secure context.
            hooksecurefunc("FCF_SetChatWindowFontSize", function(chatFrame, fontSize)
                C_Timer.After(0, function()
                    if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
                    local fp = GetGlobalFontPath()
                    if chatFrame and type(chatFrame.GetFont) == "function" and type(chatFrame.SetFont) == "function" then
                        -- Apply global font directly to ScrollingMessageFrame (not just children)
                        local _, size, flags = chatFrame:GetFont()
                        chatFrame:SetFont(fp, fontSize or size or 14, flags or "")
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
            if not QUICore.db.profile.general.applyGlobalFontToBlizzard then return end
            C_Timer.After(0.05, function()
                local fp = GetGlobalFontPath()
                for i = 1, NUM_CHAT_WINDOWS do
                    local chatFrame = _G["ChatFrame" .. i]
                    if chatFrame and chatFrame.SetFont then
                        local _, size, flags = chatFrame:GetFont()
                        if size then
                            chatFrame:SetFont(fp, size, flags or "")
                        end
                    end
                end
            end)
        end)
    end

    -- Apply to existing chat frames (SetFont on the frame itself for new message persistence)
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame.SetFont then
            local _, size, flags = chatFrame:GetFont()
            if size then
                chatFrame:SetFont(fontPath, size, flags or "")
            end
        end
    end

    -- Tooltip fonts are applied per-instance by skinning/system/tooltips.lua.
    -- Recursive application here would taint UIWidget child FontStrings.
end
