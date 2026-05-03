---------------------------------------------------------------------------
-- QUI Chat Module — Copy
-- URL copy popup, full-history copy frame, per-frame copy button
-- (always/hover/disabled modes), URL click handler routing through
-- the EventRegistry SetItemRef callback.
--
-- Extracted from chat.lua during Phase 0 refactor.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

-- Defensive: assert _internals exists before reading state through it.
-- Set up by chat.lua, which loads first per chat.xml.
local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: copy.lua loaded before chat.lua. Check chat.xml — chat.lua must precede copy.lua.")

ns.QUI.Chat.Copy = ns.QUI.Chat.Copy or {}
local Copy = ns.QUI.Chat.Copy

-- Localized table functions for performance
local tinsert = table.insert
local tconcat = table.concat

local COPY_BUTTON_SIZE = 24
local COPY_BUTTON_RIGHT_INSET = 0
local COPY_BUTTON_TOP_INSET = 0
local COPY_BUTTON_IDLE_ALPHA = 0
local COPY_BUTTON_ALWAYS_IDLE_ALPHA = 0.18
local COPY_BUTTON_CHAT_ALPHA = 0.92
local COPY_BUTTON_HOVER_ALPHA = 1
local COPY_BUTTON_FADE_IN = 0.12
local COPY_BUTTON_FADE_OUT = 0.2
local COPY_GLYPH_STROKE = 2

---------------------------------------------------------------------------
-- Module-local state
---------------------------------------------------------------------------
local urlPopup = nil            -- Copy popup frame (created on demand)
local chatCopyFrame = nil       -- Chat history copy frame (created on demand)
local copyButtons = {}          -- Track copy buttons per chat frame

-- Shared color palette (defined in chat.lua, hoisted to _internals).
-- bg/text values are chat-module-specific and intentionally diverge from the
-- options framework palette; accent is resolved live via I.GetAccent so a
-- theme preset switch propagates to popup chrome on next Show.
local QUI_COLORS = I.QUI_COLORS

local function ResolveAccent()
    return (I.GetAccent and I.GetAccent()) or QUI_COLORS.accent
end

local function ResolveTheme()
    if I.GetThemeColors then
        return I.GetThemeColors()
    end
    local accent = ResolveAccent()
    return {
        bg = QUI_COLORS.bg,
        bgDark = {0.03, 0.04, 0.06, 1},
        text = QUI_COLORS.text,
        textDim = QUI_COLORS.textDim,
        textMuted = QUI_COLORS.textDim,
        border = {1, 1, 1, 0.08},
        accent = accent,
        accentHover = accent,
    }
end

local function ColorTexture(texture, color)
    if texture and texture.SetColorTexture and color then
        texture:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function CreateThemedButton(parent, text, width, height, onClick, variant)
    local gui = _G.QUI and _G.QUI.GUI
    if gui and gui.CreateButton then
        return gui:CreateButton(parent, text, width, height, onClick, variant)
    end

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 100, height or 22)
    if UIKit and UIKit.CreateBorderLines then
        UIKit.CreateBorderLines(button)
    end

    button._hoverBg = button:CreateTexture(nil, "BACKGROUND")
    button._hoverBg:SetAllPoints(button)
    button._hoverBg:Hide()

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("CENTER", 0, 0)
    button.text:SetText(text or "")

    button:SetScript("OnEnter", function(self)
        local theme = ResolveTheme()
        if UIKit and UIKit.UpdateBorderLines then
            UIKit.UpdateBorderLines(self, 1, theme.accent[1], theme.accent[2], theme.accent[3], 1)
        end
        if self.text then
            self.text:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
        end
        if self._hoverBg then
            self._hoverBg:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.08)
            self._hoverBg:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        local theme = ResolveTheme()
        if UIKit and UIKit.UpdateBorderLines then
            UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.2)
        end
        if self.text then
            self.text:SetTextColor(theme.textDim[1], theme.textDim[2], theme.textDim[3], theme.textDim[4] or 1)
        end
        if self._hoverBg then
            self._hoverBg:Hide()
        end
    end)
    button:SetScript("OnMouseDown", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, -1) end
    end)
    button:SetScript("OnMouseUp", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, 0) end
    end)
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    return button
end

local function StyleThemedButton(button, variant)
    if not button then return end
    local theme = ResolveTheme()
    local isPrimary = variant == "primary"

    if button.SetBorderColor then
        if isPrimary then
            button:SetBorderColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.55)
        else
            button:SetBorderColor(1, 1, 1, 0.2)
        end
    elseif UIKit and UIKit.UpdateBorderLines then
        if isPrimary then
            UIKit.UpdateBorderLines(button, 1, theme.accent[1], theme.accent[2], theme.accent[3], 0.55)
        else
            UIKit.UpdateBorderLines(button, 1, 1, 1, 1, 0.2)
        end
    end

    if button.text then
        local c = isPrimary and theme.accent or theme.textDim
        button.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function CreateCloseButton(parent, onClick)
    local button = CreateThemedButton(parent, "x", 22, 22, onClick, "ghost")
    return button
end

local function GetScrollBar(scrollFrame)
    if not scrollFrame then return nil end
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then return scrollBar end
    local name = scrollFrame.GetName and scrollFrame:GetName()
    if name then
        return _G[name .. "ScrollBar"]
    end
    return nil
end

local function HideButtonArtwork(button)
    if not button then return end
    button:SetAlpha(0)
    button:SetSize(1, 1)
    if button.GetRegions then
        for _, region in ipairs({button:GetRegions()}) do
            if region and region.SetAlpha then
                region:SetAlpha(0)
            end
        end
    end
end

local function HideFrameTextures(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
end

local function StyleScrollFrame(scrollFrame)
    local scrollBar = GetScrollBar(scrollFrame)
    if not scrollBar then return end

    local theme = ResolveTheme()
    HideFrameTextures(scrollBar)
    if scrollBar.Track then
        scrollBar.Track:SetAlpha(0)
    end
    if scrollBar.Background then
        scrollBar.Background:SetAlpha(0)
    end
    if scrollBar.BG then
        scrollBar.BG:SetAlpha(0)
    end
    if scrollBar.SetWidth then
        scrollBar:SetWidth(8)
    end

    local thumb = scrollBar.ThumbTexture or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture())
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
        thumb:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.7)
        if thumb.SetAlpha then thumb:SetAlpha(1) end
        if thumb.SetSize then
            thumb:SetSize(8, 40)
        end
    end

    HideButtonArtwork(scrollBar.ScrollUpButton)
    HideButtonArtwork(scrollBar.ScrollDownButton)

    local name = scrollFrame.GetName and scrollFrame:GetName()
    if name then
        HideButtonArtwork(_G[name .. "ScrollBarScrollUpButton"])
        HideButtonArtwork(_G[name .. "ScrollBarScrollDownButton"])
    end
end

local function StyleResizeButton(button)
    if not button then return end
    local theme = ResolveTheme()
    local textures = {
        button.GetNormalTexture and button:GetNormalTexture(),
        button.GetHighlightTexture and button:GetHighlightTexture(),
        button.GetPushedTexture and button:GetPushedTexture(),
    }
    for i, texture in ipairs(textures) do
        if texture then
            if texture.SetDesaturated then texture:SetDesaturated(true) end
            local alpha = (i == 2) and 0.9 or 0.55
            texture:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3], alpha)
        end
    end
end

-- Re-apply the current theme accent to a popup's surface and title text so
-- a user who switched themes after the popup was first created sees the new
-- color the next time they open it (popups are created once, reused).
local function RefreshPopupAccent(popup)
    if not popup then return end
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(popup, theme.bg, accent, 2)
    if popup.title then
        popup.title:SetTextColor(accent[1], accent[2], accent[3], 1)
    end
    if popup.hint then
        popup.hint:SetTextColor(theme.textDim[1], theme.textDim[2], theme.textDim[3], theme.textDim[4] or 1)
    end
    if popup.editBg then
        I.ApplySurfaceStyle(popup.editBg, theme.bgDark, theme.border, 1)
    end
    if popup.editBox then
        popup.editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
    end
    if popup.scrollFrame then
        StyleScrollFrame(popup.scrollFrame)
    end
    StyleThemedButton(popup.selectAllButton, "primary")
    StyleThemedButton(popup.closeButton, "ghost")
    StyleThemedButton(popup.cornerCloseButton, "ghost")
    StyleResizeButton(popup.resizeButton)
end

---------------------------------------------------------------------------
-- URL copy popup
---------------------------------------------------------------------------
local function CreateCopyPopup()
    if urlPopup then return urlPopup end

    urlPopup = CreateFrame("Frame", "QUI_ChatCopyPopup", UIParent)
    urlPopup:SetSize(420, 90)
    urlPopup:SetPoint("CENTER")
    urlPopup:SetFrameStrata("DIALOG")
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(urlPopup, theme.bg, accent, 2)
    urlPopup:EnableMouse(true)
    urlPopup:SetMovable(true)
    urlPopup:RegisterForDrag("LeftButton")
    urlPopup:SetScript("OnDragStart", urlPopup.StartMoving)
    urlPopup:SetScript("OnDragStop", urlPopup.StopMovingOrSizing)
    urlPopup:Hide()

    -- Title text with accent color. Stored on the popup so RefreshPopupAccent
    -- can repaint it when the user has switched theme presets between opens.
    local title = urlPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Press Ctrl+C to copy")
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    urlPopup.title = title

    local editBg = CreateFrame("Frame", nil, urlPopup)
    editBg:SetPoint("LEFT", 18, 0)
    editBg:SetPoint("RIGHT", -34, 0)
    editBg:SetHeight(26)
    editBg:SetPoint("CENTER", 0, -9)
    I.ApplySurfaceStyle(editBg, theme.bgDark, theme.border, 1)
    urlPopup.editBg = editBg

    -- EditBox for URL
    local editBox = CreateFrame("EditBox", nil, editBg)
    editBox:SetPoint("LEFT", 8, 0)
    editBox:SetPoint("RIGHT", -8, 0)
    editBox:SetHeight(22)
    editBox:SetAutoFocus(true)
    editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetScript("OnEscapePressed", function() urlPopup:Hide() end)
    editBox:SetScript("OnEnterPressed", function() urlPopup:Hide() end)
    urlPopup.editBox = editBox

    -- Close button
    local closeBtn = CreateCloseButton(urlPopup, function() urlPopup:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    urlPopup.cornerCloseButton = closeBtn
    StyleThemedButton(closeBtn, "ghost")

    -- Add to special frames so ESC closes it
    if not tContains(UISpecialFrames, "QUI_ChatCopyPopup") then
        tinsert(UISpecialFrames, "QUI_ChatCopyPopup")
    end

    return urlPopup
end

---------------------------------------------------------------------------
-- Show copy popup with URL
---------------------------------------------------------------------------
local function ShowCopyPopup(url)
    local popup = CreateCopyPopup()
    RefreshPopupAccent(popup)
    popup.editBox:SetText(url)
    popup.editBox:HighlightText()
    popup:Show()
    popup.editBox:SetFocus()
end

---------------------------------------------------------------------------
-- URL click handler — routes addon:quaziiuichat:url:* hyperlinks to the popup
---------------------------------------------------------------------------
local function ExtractURLFromLink(link)
    if type(link) ~= "string" then return nil end

    local url = link:match("^addon:quaziiuichat:url:(.*)")
    if url then return url end

    local legacy = link:match("^addon:quaziiuichat:(.*)")
    if legacy
        and not legacy:find("^waypoint:")
        and not legacy:find("^player:") then
        return legacy
    end
    return nil
end

local function SetupURLClickHandler()
    -- Register for hyperlink clicks
    EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button)
        local url = ExtractURLFromLink(link)
        if url then
            ShowCopyPopup(url)
            return true
        end
    end)
end

---------------------------------------------------------------------------
-- Full-history copy frame
---------------------------------------------------------------------------
local function IsMessageProtected(message)
    if Helpers.IsSecretValue(message) then return true end
    if type(message) ~= "string" then return false end
    -- Protected content uses |K...|k pattern
    if message:find("|K") then return true end
    return false
end

-- Strip textures, icons, and hyperlink formatting from message
local function CleanMessage(message)
    if Helpers.IsSecretValue(message) or type(message) ~= "string" then return "" end

    local cleaned = message
    -- Remove texture escapes |T...|t
    cleaned = cleaned:gsub("|T[^|]*|t", "")
    -- Remove atlas textures |A...|a
    cleaned = cleaned:gsub("|A[^|]*|a", "")
    -- Convert raid icons to text
    cleaned = cleaned:gsub("|TInterface\\TargetingFrame\\UI%-RaidTargetingIcon_(%d):[^|]*|t", "{rt%1}")
    -- Strip hyperlink formatting but keep visible text |H...|h[text]|h -> text
    cleaned = cleaned:gsub("|H[^|]*|h%[?([^%]|]*)%]?|h", "%1")
    -- Remove color codes (strip start and end separately for robustness)
    cleaned = cleaned:gsub("|c%x%x%x%x%x%x%x%x", "")
    cleaned = cleaned:gsub("|r", "")
    cleaned = cleaned:gsub("|n", "\n")

    return cleaned
end

-- Extract all messages from a chat frame
local function GetLiveChatLines(chatFrame)
    local lines = {}
    local numMessages = chatFrame:GetNumMessages()

    for i = 1, numMessages do
        local message, r, g, b = chatFrame:GetMessageInfo(i)
        if type(message) == "string" and not IsMessageProtected(message) then
            local cleaned = CleanMessage(message)
            if cleaned and cleaned ~= "" then
                tinsert(lines, cleaned)
            end
        end
    end

    return lines
end

local function GetChatFrameID(chatFrame)
    if chatFrame and chatFrame.GetID then
        local frameID = chatFrame:GetID()
        if type(frameID) == "number" then
            return frameID
        end
    end

    local frameName = chatFrame and chatFrame.GetName and chatFrame:GetName()
    if type(frameName) == "string" then
        return tonumber(frameName:match("^ChatFrame(%d+)$"))
    end
    return nil
end

local function GetPersistedChatLines(chatFrame)
    local settings = I.GetSettings and I.GetSettings()
    if not settings or not settings.history or not settings.history.enabled then
        return {}
    end

    local frameID = GetChatFrameID(chatFrame)
    if not frameID then return {} end

    local history = ns.QUI.Chat and ns.QUI.Chat.History
    if not history or not history.GetMessagesForFrame then return {} end

    local messages = history.GetMessagesForFrame(frameID)
    local lines = {}
    for i = 1, #messages do
        local message = messages[i]
        if type(message) == "string" and not IsMessageProtected(message) then
            local cleaned = CleanMessage(message)
            if cleaned and cleaned ~= "" then
                tinsert(lines, cleaned)
            end
        end
    end
    return lines
end

local function GetConfiguredChatLines(chatFrame)
    local settings = I.GetSettings and I.GetSettings()
    local source = settings and settings.copyHistorySource or "live"

    if source == "persisted" then
        return GetPersistedChatLines(chatFrame), "persisted"
    end

    return GetLiveChatLines(chatFrame), "live"
end

-- Create the chat copy frame (on demand)
local function CreateChatCopyFrame()
    if chatCopyFrame then return chatCopyFrame end

    chatCopyFrame = CreateFrame("Frame", "QUI_ChatCopyFrame", UIParent)
    chatCopyFrame:SetSize(500, 400)
    chatCopyFrame:SetPoint("CENTER")
    chatCopyFrame:SetFrameStrata("DIALOG")
    local theme = ResolveTheme()
    local accent = theme.accent
    I.ApplySurfaceStyle(chatCopyFrame, theme.bg, accent, 2)
    chatCopyFrame:EnableMouse(true)
    chatCopyFrame:SetMovable(true)
    chatCopyFrame:SetResizable(true)
    chatCopyFrame:SetResizeBounds(300, 200, 800, 600)
    chatCopyFrame:RegisterForDrag("LeftButton")
    chatCopyFrame:SetScript("OnDragStart", chatCopyFrame.StartMoving)
    chatCopyFrame:SetScript("OnDragStop", chatCopyFrame.StopMovingOrSizing)
    chatCopyFrame:Hide()

    -- Title (stored for RefreshPopupAccent on subsequent opens after a theme switch).
    local title = chatCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Chat History - Select and Ctrl+C to copy")
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    chatCopyFrame.title = title

    local hint = chatCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetText("Select all (Ctrl+A) then copy (Ctrl+C)")
    hint:SetTextColor(theme.textDim[1], theme.textDim[2], theme.textDim[3], theme.textDim[4] or 1)
    chatCopyFrame.hint = hint

    local editBg = CreateFrame("Frame", nil, chatCopyFrame)
    editBg:SetPoint("TOPLEFT", 12, -55)
    editBg:SetPoint("BOTTOMRIGHT", -12, 45)
    I.ApplySurfaceStyle(editBg, theme.bgDark, theme.border, 1)
    chatCopyFrame.editBg = editBg

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "QUI_ChatCopyFrameScroll", editBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 8)
    StyleScrollFrame(scrollFrame)

    -- Edit box for text selection
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(math.max(1, scrollFrame:GetWidth() - 10))
    editBox:SetAutoFocus(false)
    editBox:SetTextColor(theme.text[1], theme.text[2], theme.text[3], theme.text[4] or 1)
    editBox:SetScript("OnEscapePressed", function() chatCopyFrame:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    scrollFrame:SetScript("OnSizeChanged", function(self)
        editBox:SetWidth(math.max(1, self:GetWidth() - 10))
    end)
    if ns.ApplyScrollWheel then
        ns.ApplyScrollWheel(scrollFrame)
    end
    chatCopyFrame.editBox = editBox
    chatCopyFrame.scrollFrame = scrollFrame

    -- Close button
    local closeBtn = CreateCloseButton(chatCopyFrame, function() chatCopyFrame:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    chatCopyFrame.cornerCloseButton = closeBtn
    StyleThemedButton(closeBtn, "ghost")

    -- Select All button
    local selectAllBtn = CreateThemedButton(chatCopyFrame, "Select All", 100, 24, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end, "primary")
    selectAllBtn:SetPoint("BOTTOMLEFT", 12, 10)
    chatCopyFrame.selectAllButton = selectAllBtn
    StyleThemedButton(selectAllBtn, "primary")

    local closeBottomBtn = CreateThemedButton(chatCopyFrame, "Close", 80, 24, function()
        chatCopyFrame:Hide()
    end, "ghost")
    closeBottomBtn:SetPoint("BOTTOMRIGHT", -32, 10)
    chatCopyFrame.closeButton = closeBottomBtn
    StyleThemedButton(closeBottomBtn, "ghost")

    -- Resize grip
    local resizeBtn = CreateFrame("Button", nil, chatCopyFrame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    chatCopyFrame.resizeButton = resizeBtn
    StyleResizeButton(resizeBtn)
    resizeBtn:SetScript("OnMouseDown", function() chatCopyFrame:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function()
        chatCopyFrame:StopMovingOrSizing()
        editBox:SetWidth(scrollFrame:GetWidth())
    end)

    -- Add to special frames so ESC closes it
    if not tContains(UISpecialFrames, "QUI_ChatCopyFrame") then
        tinsert(UISpecialFrames, "QUI_ChatCopyFrame")
    end

    return chatCopyFrame
end

-- Show the chat copy frame with messages from a chat frame
local function ShowChatCopyFrame(chatFrame)
    local frame = CreateChatCopyFrame()
    RefreshPopupAccent(frame)
    local lines, source = GetConfiguredChatLines(chatFrame)

    local text
    if #lines == 0 then
        if source == "persisted" then
            text = "(No copyable messages in persisted chat history)"
        else
            text = "(No copyable messages in chat history)"
        end
    else
        text = tconcat(lines, "\n")
    end

    frame.editBox:SetText(text)
    frame.editBox:SetWidth(math.max(1, frame.scrollFrame:GetWidth() - 10))
    frame:Show()
    frame.editBox:SetFocus()
    frame.editBox:HighlightText()
end

---------------------------------------------------------------------------
-- Copy Button (per chat frame)
---------------------------------------------------------------------------

local function AddGlyphLine(parent, layer)
    local line = parent:CreateTexture(nil, layer or "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8x8")
    return line
end

local function CreateCopyGlyph(button)
    if button._quiGlyphParts then return end

    local parts = {}
    local back = CreateFrame("Frame", nil, button)
    back:SetSize(10, 12)
    back:SetPoint("CENTER", -3, 3)
    parts.backTop = AddGlyphLine(back)
    parts.backBottom = AddGlyphLine(back)
    parts.backLeft = AddGlyphLine(back)
    parts.backRight = AddGlyphLine(back)
    parts.backTop:SetPoint("TOPLEFT")
    parts.backTop:SetPoint("TOPRIGHT")
    parts.backTop:SetHeight(COPY_GLYPH_STROKE)
    parts.backBottom:SetPoint("BOTTOMLEFT")
    parts.backBottom:SetPoint("BOTTOMRIGHT")
    parts.backBottom:SetHeight(COPY_GLYPH_STROKE)
    parts.backLeft:SetPoint("TOPLEFT")
    parts.backLeft:SetPoint("BOTTOMLEFT")
    parts.backLeft:SetWidth(COPY_GLYPH_STROKE)
    parts.backRight:SetPoint("TOPRIGHT")
    parts.backRight:SetPoint("BOTTOMRIGHT")
    parts.backRight:SetWidth(COPY_GLYPH_STROKE)

    local front = CreateFrame("Frame", nil, button)
    front:SetSize(12, 14)
    front:SetPoint("CENTER", 2, -2)
    parts.frontTop = AddGlyphLine(front)
    parts.frontBottom = AddGlyphLine(front)
    parts.frontLeft = AddGlyphLine(front)
    parts.frontRight = AddGlyphLine(front)
    parts.frontTop:SetPoint("TOPLEFT")
    parts.frontTop:SetPoint("TOPRIGHT", -4, 0)
    parts.frontTop:SetHeight(COPY_GLYPH_STROKE)
    parts.frontBottom:SetPoint("BOTTOMLEFT")
    parts.frontBottom:SetPoint("BOTTOMRIGHT")
    parts.frontBottom:SetHeight(COPY_GLYPH_STROKE)
    parts.frontLeft:SetPoint("TOPLEFT")
    parts.frontLeft:SetPoint("BOTTOMLEFT")
    parts.frontLeft:SetWidth(COPY_GLYPH_STROKE)
    parts.frontRight:SetPoint("TOPRIGHT", 0, -4)
    parts.frontRight:SetPoint("BOTTOMRIGHT")
    parts.frontRight:SetWidth(COPY_GLYPH_STROKE)
    parts.foldA = AddGlyphLine(front)
    parts.foldB = AddGlyphLine(front)
    parts.foldA:SetPoint("TOPRIGHT", 0, -4)
    parts.foldA:SetSize(4, COPY_GLYPH_STROKE)
    parts.foldB:SetPoint("TOPRIGHT", -4, 0)
    parts.foldB:SetSize(COPY_GLYPH_STROKE, 4)

    button._quiGlyphParts = parts
end

local function HideCopyButtonBorder(button)
    if UIKit and UIKit.UpdateBorderLines then
        UIKit.UpdateBorderLines(button, 0, 0, 0, 0, 0, true)
    end
end

local function FadeCopyButton(button, alpha, duration)
    if not button then return end
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(button) end

    if UIFrameFadeIn and UIFrameFadeOut and duration and duration > 0 then
        local startAlpha = button:GetAlpha() or alpha
        if alpha > startAlpha then
            UIFrameFadeIn(button, duration, startAlpha, alpha)
        elseif alpha < startAlpha then
            UIFrameFadeOut(button, duration, startAlpha, alpha)
        else
            button:SetAlpha(alpha)
        end
    else
        button:SetAlpha(alpha)
    end
end

local function RefreshCopyButtonTheme(button, hovered, chatHovered)
    if not button then return end
    local theme = ResolveTheme()
    CreateCopyGlyph(button)
    HideCopyButtonBorder(button)

    local active = hovered or chatHovered
    if button._hoverBg then
        if active then
            button._hoverBg:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], hovered and 0.18 or 0.12)
            button._hoverBg:Show()
        else
            button._hoverBg:Hide()
        end
    end

    local parts = button._quiGlyphParts
    for key, part in pairs(parts) do
        if key:find("^back") then
            ColorTexture(part, {theme.text[1], theme.text[2], theme.text[3], active and 0.72 or 0.55})
        else
            ColorTexture(part, {theme.accent[1], theme.accent[2], theme.accent[3], hovered and 1 or 0.95})
        end
    end
end

local function UpdateCopyButtonVisibility(button, chatFrame, immediate)
    if not button or not chatFrame then return end

    local settings = I.GetSettings()
    local mode = settings and settings.copyButtonMode or "always"
    local buttonHovered = button.IsMouseOver and button:IsMouseOver()
    local chatHovered = chatFrame.IsMouseOver and chatFrame:IsMouseOver()
    local targetAlpha = (mode == "always") and COPY_BUTTON_ALWAYS_IDLE_ALPHA or COPY_BUTTON_IDLE_ALPHA

    if buttonHovered then
        targetAlpha = COPY_BUTTON_HOVER_ALPHA
    elseif chatHovered then
        targetAlpha = COPY_BUTTON_CHAT_ALPHA
    end

    RefreshCopyButtonTheme(button, buttonHovered, chatHovered)
    FadeCopyButton(button, targetAlpha, immediate and 0 or (targetAlpha > 0 and COPY_BUTTON_FADE_IN or COPY_BUTTON_FADE_OUT))
end

local function LayoutCopyButton(button, chatFrame)
    if not button or not chatFrame then return end

    button:ClearAllPoints()
    button:SetSize(COPY_BUTTON_SIZE, COPY_BUTTON_SIZE)
    button:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -COPY_BUTTON_RIGHT_INSET, -COPY_BUTTON_TOP_INSET)
end

-- Create or get the copy button for a chat frame
local function GetOrCreateCopyButton(chatFrame)
    local frameName = chatFrame:GetName()
    if not frameName then return nil end

    -- Return existing button
    if copyButtons[chatFrame] then
        LayoutCopyButton(copyButtons[chatFrame], chatFrame)
        return copyButtons[chatFrame]
    end

    local button = CreateFrame("Button", frameName .. "QuaziiCopyButton", chatFrame)
    LayoutCopyButton(button, chatFrame)
    button:SetFrameLevel(chatFrame:GetFrameLevel() + 5)

    button._hoverBg = button:CreateTexture(nil, "BACKGROUND")
    button._hoverBg:SetAllPoints(button)
    button._hoverBg:Hide()
    CreateCopyGlyph(button)
    RefreshCopyButtonTheme(button, false, false)

    -- Hidden by default; chat-frame hover fades the glyph in.
    button:SetAlpha(COPY_BUTTON_IDLE_ALPHA)

    -- Hover effect on button itself
    button:SetScript("OnEnter", function(self)
        UpdateCopyButtonVisibility(self, chatFrame)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Copy Chat", 1, 1, 1)
        GameTooltip:AddLine("Click to copy chat history", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                UpdateCopyButtonVisibility(self, chatFrame)
            end)
        else
            UpdateCopyButtonVisibility(self, chatFrame)
        end
        GameTooltip:Hide()
    end)

    -- Click handler
    button:SetScript("OnClick", function()
        ShowChatCopyFrame(chatFrame)
    end)

    copyButtons[chatFrame] = button
    return button
end

-- Setup hover mode for chat frame (show button on chat frame hover)
local function SetupCopyButtonHoverMode(chatFrame)
    -- Check flag first to prevent duplicate hooks (use local table, NOT frame property)
    if I.copyButtonHookState[chatFrame] then return end
    I.copyButtonHookState[chatFrame] = true

    local button = copyButtons[chatFrame]
    if not button then return end

    -- Hook chat frame enter/leave for copy button fade.
    chatFrame:HookScript("OnEnter", function()
        local settings = I.GetSettings()
        local mode = settings and settings.copyButtonMode or "always"
        if mode ~= "disabled" and button then
            button:Show()
            UpdateCopyButtonVisibility(button, chatFrame)
        end
    end)
    chatFrame:HookScript("OnLeave", function()
        local settings = I.GetSettings()
        local mode = settings and settings.copyButtonMode or "always"
        if mode ~= "disabled" and button then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    UpdateCopyButtonVisibility(button, chatFrame)
                end)
            else
                UpdateCopyButtonVisibility(button, chatFrame)
            end
        end
    end)
end

-- Apply copy button mode for a chat frame
local function ApplyCopyButtonMode(chatFrame)
    local settings = I.GetSettings()

    -- Backwards compatibility: migrate old boolean copyButton to new copyButtonMode
    local mode = settings and settings.copyButtonMode
    if not mode and settings then
        -- Old format: copyButton was boolean
        if settings.copyButton == false then
            mode = "disabled"
        else
            mode = "always"
        end
    end
    mode = mode or "always"

    -- Mode: disabled - hide existing button, don't create new one
    if mode == "disabled" then
        if copyButtons[chatFrame] then
            copyButtons[chatFrame]:Hide()
        end
        return
    end

    -- Mode: always or hover - create and show
    local button = GetOrCreateCopyButton(chatFrame)
    if not button then return end
    button:Show()
    if not I.copyButtonHookState[chatFrame] then
        SetupCopyButtonHoverMode(chatFrame)
    end
    UpdateCopyButtonVisibility(button, chatFrame, true)
end

-- Hide copy button
local function HideCopyButton(chatFrame)
    if copyButtons[chatFrame] then
        copyButtons[chatFrame]:Hide()
    end
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------
Copy.ShowURLPopup    = ShowCopyPopup
Copy.SetupURLClick   = SetupURLClickHandler
Copy.ShowFullCopy    = ShowChatCopyFrame
Copy.ApplyButtonMode = ApplyCopyButtonMode
Copy.HideButton      = HideCopyButton
