---------------------------------------------------------------------------
-- QUI Chat Module
-- Glass-style chat frame customization with URL detection and copy support
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- Local references
---------------------------------------------------------------------------
local skinnedFrames = {}        -- Track which frames have been styled
local urlPopup = nil            -- Copy popup frame (created on demand)
local chatCopyFrame = nil       -- Chat history copy frame (created on demand)
local copyButtons = {}          -- Track copy buttons per chat frame

-- Localized table functions for performance
local tinsert = table.insert
local tconcat = table.concat

-- Blizzard texture names to strip for glass effect
local CHAT_FRAME_TEXTURES = {
    "Background",
    "TopLeftTexture", "TopRightTexture",
    "BottomLeftTexture", "BottomRightTexture",
    "TopTexture", "BottomTexture",
    "LeftTexture", "RightTexture",
}

-- URL detection patterns (standard protocol and www formats)
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",             -- protocol://path
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",    -- www.domain.tld/path
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",        -- www.domain.tld
}

-- Edit box textures to remove for clean styling
local EDITBOX_TEXTURES = {
    "FocusLeft", "FocusMid", "FocusRight",
    "Header", "HeaderSuffix", "LanguageHeader",
    "Prompt", "NewcomerHint",
}

-- QUI Color palette for popup styling
local QUI_COLORS = {
    bg = {0.067, 0.094, 0.153, 0.97},
    accent = {0.204, 0.827, 0.6, 1},
    text = {0.953, 0.957, 0.965, 1},
}

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("chat")
end

---------------------------------------------------------------------------
-- Strip Blizzard default textures from chat frame
---------------------------------------------------------------------------
local function StripDefaultTextures(chatFrame)
    local frameName = chatFrame:GetName()
    if not frameName then return end

    for _, textureName in ipairs(CHAT_FRAME_TEXTURES) do
        local texture = _G[frameName .. textureName]
        if texture and texture.SetTexture then
            texture:SetTexture(0)
            texture:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- Create glass-style backdrop for chat frame
---------------------------------------------------------------------------
local function CreateGlassBackdrop(chatFrame)
    local settings = GetSettings()
    if not settings or not settings.glass or not settings.glass.enabled then return end

    -- Create or update backdrop
    if not chatFrame.__quiChatBackdrop then
        local backdrop = CreateFrame("Frame", nil, chatFrame, "BackdropTemplate")
        backdrop:SetFrameLevel(math.max(1, chatFrame:GetFrameLevel() - 1))
        backdrop:SetPoint("TOPLEFT", -8, 2)
        backdrop:SetPoint("BOTTOMRIGHT", 8, -8)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        chatFrame.__quiChatBackdrop = backdrop
    end

    -- Apply color and transparency
    local alpha = settings.glass.bgAlpha or 0.25
    local bgColor = settings.glass.bgColor or {0, 0, 0}
    chatFrame.__quiChatBackdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], alpha)
    chatFrame.__quiChatBackdrop:SetBackdropBorderColor(bgColor[1], bgColor[2], bgColor[3], alpha)
    chatFrame.__quiChatBackdrop:Show()
end

---------------------------------------------------------------------------
-- Remove glass backdrop (when disabled)
---------------------------------------------------------------------------
local function RemoveGlassBackdrop(chatFrame)
    if chatFrame.__quiChatBackdrop then
        chatFrame.__quiChatBackdrop:Hide()
    end
end

---------------------------------------------------------------------------
-- Force font outline on chat text (always enabled)
---------------------------------------------------------------------------
local function StyleFontStrings(chatFrame)
    -- Style the main font string container
    local fontFile, fontSize, fontFlags = chatFrame:GetFont()
    if fontFile and fontSize then
        -- Add OUTLINE if not already present
        local newFlags = fontFlags or ""
        if not newFlags:find("OUTLINE") then
            newFlags = "OUTLINE"
        end
        chatFrame:SetFont(fontFile, fontSize, newFlags)
        chatFrame:SetShadowOffset(0, 0)
    end
end

---------------------------------------------------------------------------
-- Timestamp - Prepend time to messages
---------------------------------------------------------------------------
local function AddTimestamp(text)
    local settings = GetSettings()
    if not settings or not settings.timestamps or not settings.timestamps.enabled then
        return text
    end

    local fmt = settings.timestamps.format == "12h" and "%I:%M %p" or "%H:%M"
    local timestamp = date(fmt)
    local color = settings.timestamps.color
    if color then
        local hex = string.format("%02x%02x%02x", color[1]*255, color[2]*255, color[3]*255)
        return string.format("|cff%s[%s]|r %s", hex, timestamp, text)
    end
    return string.format("[%s] %s", timestamp, text)
end

---------------------------------------------------------------------------
-- URL Detection - Make URLs clickable
---------------------------------------------------------------------------
local function MakeURLsClickable(text)
    local settings = GetSettings()
    if not settings or not settings.urls or not settings.urls.enabled then
        return text
    end

    -- During M+ keystones and raid encounters, chat messages may be
    -- "secret values" that can't be modified - use pcall to handle gracefully
    local success, result = pcall(function()
        -- Get URL color
        local r, g, b = 0.078, 0.608, 0.992  -- Default blue
        if settings.urls.color then
            r, g, b = settings.urls.color[1] or r, settings.urls.color[2] or g, settings.urls.color[3] or b
        end
        local colorHex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)

        -- Create clickable hyperlink format
        local linkFormat = "|cff" .. colorHex .. "|Haddon:quaziiuichat:%1|h[%1]|h|r"

        local processed = text
        for _, pattern in ipairs(URL_PATTERNS) do
            processed = processed:gsub(pattern, linkFormat)
        end
        return processed
    end)

    -- If protected content, return original unmodified text
    if success then
        return result
    else
        return text
    end
end

---------------------------------------------------------------------------
-- Hook chat frame AddMessage to process URLs
---------------------------------------------------------------------------
local function HookChatMessages(chatFrame)
    if chatFrame.__quiChatMessageHooked then return end
    chatFrame.__quiChatMessageHooked = true

    local origAddMessage = chatFrame.AddMessage
    chatFrame.AddMessage = function(self, text, ...)
        if text and type(text) == "string" then
            text = AddTimestamp(text)
            text = MakeURLsClickable(text)
        end
        return origAddMessage(self, text, ...)
    end
end

---------------------------------------------------------------------------
-- Create URL copy popup (on demand) - QUI styled
---------------------------------------------------------------------------
local function CreateCopyPopup()
    if urlPopup then return urlPopup end

    urlPopup = CreateFrame("Frame", "QUI_ChatCopyPopup", UIParent, "BackdropTemplate")
    urlPopup:SetSize(420, 90)
    urlPopup:SetPoint("CENTER")
    urlPopup:SetFrameStrata("DIALOG")
    urlPopup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    -- QUI color scheme
    urlPopup:SetBackdropColor(QUI_COLORS.bg[1], QUI_COLORS.bg[2], QUI_COLORS.bg[3], QUI_COLORS.bg[4])
    urlPopup:SetBackdropBorderColor(QUI_COLORS.accent[1], QUI_COLORS.accent[2], QUI_COLORS.accent[3], QUI_COLORS.accent[4])
    urlPopup:EnableMouse(true)
    urlPopup:SetMovable(true)
    urlPopup:RegisterForDrag("LeftButton")
    urlPopup:SetScript("OnDragStart", urlPopup.StartMoving)
    urlPopup:SetScript("OnDragStop", urlPopup.StopMovingOrSizing)
    urlPopup:Hide()

    -- Title text with accent color
    local title = urlPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Press Ctrl+C to copy")
    title:SetTextColor(QUI_COLORS.accent[1], QUI_COLORS.accent[2], QUI_COLORS.accent[3], 1)

    -- EditBox for URL
    local editBox = CreateFrame("EditBox", nil, urlPopup, "InputBoxTemplate")
    editBox:SetSize(380, 24)
    editBox:SetPoint("CENTER", 0, -8)
    editBox:SetAutoFocus(true)
    editBox:SetTextColor(QUI_COLORS.text[1], QUI_COLORS.text[2], QUI_COLORS.text[3], 1)
    editBox:SetScript("OnEscapePressed", function() urlPopup:Hide() end)
    editBox:SetScript("OnEnterPressed", function() urlPopup:Hide() end)
    urlPopup.editBox = editBox

    -- Close button
    local closeBtn = CreateFrame("Button", nil, urlPopup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetSize(24, 24)

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
    popup.editBox:SetText(url)
    popup.editBox:HighlightText()
    popup:Show()
    popup.editBox:SetFocus()
end

---------------------------------------------------------------------------
-- Setup URL click handler
---------------------------------------------------------------------------
local function SetupURLClickHandler()
    -- Register for hyperlink clicks
    EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button)
        if not link then return end

        local url = link:match("^addon:quaziiuichat:(.*)")
        if url then
            ShowCopyPopup(url)
            return true
        end
    end)
end

---------------------------------------------------------------------------
-- Chat Copy Frame (full chat history copy)
---------------------------------------------------------------------------

-- Check if message contains protected/secure content
local function IsMessageProtected(message)
    -- BUG-009: Secret values are truthy but can't be indexed - check type first
    if not message or type(message) ~= "string" then return false end
    -- Secret values use |K...|k pattern
    if message:find("|K") then return true end
    return false
end

-- Strip textures, icons, and hyperlink formatting from message
local function CleanMessage(message)
    -- BUG-009: Secret values are truthy but can't be indexed - check type first
    if not message or type(message) ~= "string" then return "" end

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
local function GetChatLines(chatFrame)
    local lines = {}
    local numMessages = chatFrame:GetNumMessages()

    for i = 1, numMessages do
        local message, r, g, b = chatFrame:GetMessageInfo(i)
        if message and not IsMessageProtected(message) then
            local cleaned = CleanMessage(message)
            if cleaned and cleaned ~= "" then
                tinsert(lines, cleaned)
            end
        end
    end

    return lines
end

-- Create the chat copy frame (on demand)
local function CreateChatCopyFrame()
    if chatCopyFrame then return chatCopyFrame end

    chatCopyFrame = CreateFrame("Frame", "QUI_ChatCopyFrame", UIParent, "BackdropTemplate")
    chatCopyFrame:SetSize(500, 400)
    chatCopyFrame:SetPoint("CENTER")
    chatCopyFrame:SetFrameStrata("DIALOG")
    chatCopyFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    chatCopyFrame:SetBackdropColor(QUI_COLORS.bg[1], QUI_COLORS.bg[2], QUI_COLORS.bg[3], QUI_COLORS.bg[4])
    chatCopyFrame:SetBackdropBorderColor(QUI_COLORS.accent[1], QUI_COLORS.accent[2], QUI_COLORS.accent[3], QUI_COLORS.accent[4])
    chatCopyFrame:EnableMouse(true)
    chatCopyFrame:SetMovable(true)
    chatCopyFrame:SetResizable(true)
    chatCopyFrame:SetResizeBounds(300, 200, 800, 600)
    chatCopyFrame:RegisterForDrag("LeftButton")
    chatCopyFrame:SetScript("OnDragStart", chatCopyFrame.StartMoving)
    chatCopyFrame:SetScript("OnDragStop", chatCopyFrame.StopMovingOrSizing)
    chatCopyFrame:Hide()

    -- Title
    local title = chatCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Chat History - Select and Ctrl+C to copy")
    title:SetTextColor(QUI_COLORS.accent[1], QUI_COLORS.accent[2], QUI_COLORS.accent[3], 1)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, chatCopyFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    -- Edit box for text selection
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetAutoFocus(false)
    editBox:SetTextColor(QUI_COLORS.text[1], QUI_COLORS.text[2], QUI_COLORS.text[3], 1)
    editBox:SetScript("OnEscapePressed", function() chatCopyFrame:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    chatCopyFrame.editBox = editBox
    chatCopyFrame.scrollFrame = scrollFrame

    -- Close button
    local closeBtn = CreateFrame("Button", nil, chatCopyFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetSize(24, 24)

    -- Select All button
    local selectAllBtn = CreateFrame("Button", nil, chatCopyFrame, "UIPanelButtonTemplate")
    selectAllBtn:SetSize(100, 22)
    selectAllBtn:SetPoint("BOTTOMLEFT", 12, 10)
    selectAllBtn:SetText("Select All")
    selectAllBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    -- Resize grip
    local resizeBtn = CreateFrame("Button", nil, chatCopyFrame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
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
    local lines = GetChatLines(chatFrame)

    local text
    if #lines == 0 then
        text = "(No copyable messages in chat history)"
    else
        text = tconcat(lines, "\n")
    end

    frame.editBox:SetText(text)
    frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    frame:Show()
    frame.editBox:SetFocus()
    frame.editBox:HighlightText()
end

---------------------------------------------------------------------------
-- Copy Button (per chat frame)
---------------------------------------------------------------------------

local COPY_BUTTON_IDLE_ALPHA = 0.35

-- Create or get the copy button for a chat frame
local function GetOrCreateCopyButton(chatFrame)
    local frameName = chatFrame:GetName()
    if not frameName then return nil end

    -- Return existing button
    if copyButtons[chatFrame] then
        return copyButtons[chatFrame]
    end

    local button = CreateFrame("Button", frameName .. "QuaziiCopyButton", chatFrame)
    button:SetSize(20, 22)
    -- Position at visual top-right (matching glass backdrop +8 offset, plus padding)
    button:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", 4, -2)
    button:SetFrameLevel(chatFrame:GetFrameLevel() + 5)

    -- Copy icon texture (simple document icon)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    button.icon = icon

    -- Semi-transparent by default
    button:SetAlpha(COPY_BUTTON_IDLE_ALPHA)

    -- Hover effect on button itself
    button:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Copy Chat", 1, 1, 1)
        GameTooltip:AddLine("Click to copy chat history", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        local settings = GetSettings()
        local mode = settings and settings.copyButtonMode or "always"
        -- In hover mode, hide when leaving button (unless mouse is over chat frame)
        if mode == "hover" then
            if not chatFrame:IsMouseOver() then
                self:SetAlpha(0)
            end
        else
            self:SetAlpha(COPY_BUTTON_IDLE_ALPHA)
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
    -- Check flag first to prevent duplicate hooks
    if chatFrame.quaziiCopyButtonHooked then return end
    chatFrame.quaziiCopyButtonHooked = true

    local button = copyButtons[chatFrame]
    if not button then return end

    -- Hook chat frame enter/leave for hover mode
    chatFrame:HookScript("OnEnter", function()
        local settings = GetSettings()
        local mode = settings and settings.copyButtonMode or "always"
        if mode == "hover" and button then
            button:SetAlpha(COPY_BUTTON_IDLE_ALPHA)
            button:Show()
        end
    end)
    chatFrame:HookScript("OnLeave", function()
        local settings = GetSettings()
        local mode = settings and settings.copyButtonMode or "always"
        if mode == "hover" and button then
            -- Only hide if mouse isn't over the button
            if not button:IsMouseOver() then
                button:SetAlpha(0)
            end
        end
    end)
end

-- Apply copy button mode for a chat frame
local function ApplyCopyButtonMode(chatFrame)
    local settings = GetSettings()

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

    if mode == "always" then
        button:SetAlpha(COPY_BUTTON_IDLE_ALPHA)
        button:Show()
    elseif mode == "hover" then
        -- Start hidden, show on chat frame hover
        button:SetAlpha(0)
        button:Show()
        -- Setup hover hooks if not already done
        if not chatFrame.quaziiCopyButtonHooked then
            SetupCopyButtonHoverMode(chatFrame)
        end
    end
end

-- Hide copy button
local function HideCopyButton(chatFrame)
    if copyButtons[chatFrame] then
        copyButtons[chatFrame]:Hide()
    end
end

---------------------------------------------------------------------------
-- Message Fade System (uses native ScrollingMessageFrame API)
---------------------------------------------------------------------------
local function SetupMessageFade(chatFrame)
    local settings = GetSettings()
    if not settings or not settings.fade then return end

    if settings.fade.enabled then
        chatFrame:SetFading(true)
        chatFrame:SetTimeVisible(settings.fade.delay or 60)
    else
        chatFrame:SetFading(false)
    end
end

---------------------------------------------------------------------------
-- Hide chat buttons (social, channel, scroll)
---------------------------------------------------------------------------
-- Hide function to prevent Blizzard from re-showing frames
local function preventShow(self)
    self:Hide()
end

local function HideChatButtons(chatFrame)
    local settings = GetSettings()
    if not settings or not settings.hideButtons then return end

    -- Hide button frame and prevent Blizzard from re-showing it
    if chatFrame.buttonFrame then
        chatFrame.buttonFrame:SetScript("OnShow", preventShow)
        chatFrame.buttonFrame:Hide()
        chatFrame.buttonFrame:SetWidth(0.1)  -- Collapse to minimal width
    end

    -- Hide scroll bar and buttons
    if chatFrame.ScrollBar then
        chatFrame.ScrollBar:Hide()
    end
    if chatFrame.ScrollToBottomButton then
        chatFrame.ScrollToBottomButton:Hide()
    end

    -- Also try global names for older frames
    local frameName = chatFrame:GetName()
    if frameName then
        local buttonFrame = _G[frameName .. "ButtonFrame"]
        if buttonFrame then
            buttonFrame:SetScript("OnShow", preventShow)
            buttonFrame:Hide()
            buttonFrame:SetWidth(0.1)
        end

        local scrollBar = _G[frameName .. "ScrollBar"]
        if scrollBar then scrollBar:Hide() end
    end

    -- Hide QuickJoinToastButton (global frame, not per-chat)
    if QuickJoinToastButton then
        QuickJoinToastButton:SetScript("OnShow", preventShow)
        QuickJoinToastButton:Hide()
    end

    -- Remove screen clamping so chat can move to edges
    if not InCombatLockdown() then
        chatFrame:SetClampedToScreen(false)
        chatFrame:SetClampRectInsets(0, 0, 0, 0)
    end
end

---------------------------------------------------------------------------
-- Show chat buttons (restore when disabled)
---------------------------------------------------------------------------
local function ShowChatButtons(chatFrame)
    if chatFrame.buttonFrame then
        chatFrame.buttonFrame:SetScript("OnShow", nil)  -- Remove hide script
        chatFrame.buttonFrame:Show()
        chatFrame.buttonFrame:SetWidth(29)  -- Restore default width
    end
    if chatFrame.ScrollBar then
        chatFrame.ScrollBar:Show()
    end
    if chatFrame.ScrollToBottomButton then
        chatFrame.ScrollToBottomButton:Show()
    end

    local frameName = chatFrame:GetName()
    if frameName then
        local buttonFrame = _G[frameName .. "ButtonFrame"]
        if buttonFrame then
            buttonFrame:SetScript("OnShow", nil)
            buttonFrame:Show()
            buttonFrame:SetWidth(29)
        end

        local scrollBar = _G[frameName .. "ScrollBar"]
        if scrollBar then scrollBar:Show() end
    end

    -- Show QuickJoinToastButton
    if QuickJoinToastButton then
        QuickJoinToastButton:SetScript("OnShow", nil)
        QuickJoinToastButton:Show()
    end

    -- Restore screen clamping
    if not InCombatLockdown() then
        chatFrame:SetClampedToScreen(true)
    end
end

---------------------------------------------------------------------------
-- Style edit box (chat input area)
---------------------------------------------------------------------------
local function StyleEditBox(chatFrame)
    local settings = GetSettings()
    if not settings or not settings.editBox or not settings.editBox.enabled then return end
    if not settings.glass or not settings.glass.enabled then return end

    local frameName = chatFrame:GetName()
    if not frameName then return end

    -- Find edit box
    local editBox = chatFrame.editBox or _G[frameName .. "EditBox"]
    if not editBox then return end

    -- Only strip Blizzard textures once
    if not editBox.__quiChatStyled then
        editBox.__quiChatStyled = true

        -- Hide child FRAMES by global name (these are frames, not textures)
        local childSuffixes = {
            "Left", "Mid", "Right",
            "FocusLeft", "FocusMid", "FocusRight",
        }
        for _, suffix in ipairs(childSuffixes) do
            local child = _G[frameName .. "EditBox" .. suffix]
            if child and child.Hide then
                child:Hide()
            end
        end

        -- Alpha out focus textures via editBox properties
        if editBox.focusLeft then editBox.focusLeft:SetAlpha(0) end
        if editBox.focusMid then editBox.focusMid:SetAlpha(0) end
        if editBox.focusRight then editBox.focusRight:SetAlpha(0) end

        -- Remove Blizzard textures by property name
        for _, name in ipairs(EDITBOX_TEXTURES) do
            local tex = editBox[name]
            if tex and tex.Hide then
                tex:Hide()
            end
        end

        -- Hide all texture regions on the editbox itself
        local regions = {editBox:GetRegions()}
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                if not region.__quiChatKeep then
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- Create glass backdrop for edit box (once per chatFrame, stored on chatFrame)
    -- Parent to chatFrame (not editBox) so we can control visibility independently
    if not chatFrame.__quiEditBoxBackdrop then
        local backdrop = CreateFrame("Frame", nil, chatFrame, "BackdropTemplate")
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        chatFrame.__quiEditBoxBackdrop = backdrop
    end

    local backdrop = chatFrame.__quiEditBoxBackdrop
    local positionTop = settings.editBox.positionTop

    -- Position backdrop and editbox based on setting
    backdrop:ClearAllPoints()
    if positionTop then
        -- Position at TOP, overlaying tabs with opaque black background
        backdrop:SetFrameLevel(chatFrame:GetFrameLevel() + 10)
        backdrop:SetPoint("BOTTOMLEFT", chatFrame, "TOPLEFT", -8, 0)
        backdrop:SetPoint("BOTTOMRIGHT", chatFrame, "TOPRIGHT", 8, 0)
        backdrop:SetHeight(24)
        backdrop:SetBackdropColor(0, 0, 0, 1)
        backdrop:SetBackdropBorderColor(0, 0, 0, 1)

        -- Anchor editbox to CENTER of backdrop (vertically centered, full width)
        editBox:ClearAllPoints()
        editBox:SetPoint("LEFT", backdrop, "LEFT", -8, 0)
        editBox:SetPoint("RIGHT", backdrop, "RIGHT", -4, 0)
        editBox:SetPoint("CENTER", backdrop, "CENTER", 0, 0)

        -- Store backdrop reference on editBox for hooks to access
        editBox.__quiChatBackdrop = backdrop

        -- For top position: Only show backdrop when editbox has focus (user is typing)
        if not editBox.__quiTopModeHooked then
            editBox.__quiTopModeHooked = true
            editBox:HookScript("OnEditFocusGained", function(self)
                local s = GetSettings()
                if s and s.editBox and s.editBox.positionTop and self.__quiChatBackdrop then
                    self.__quiChatBackdrop:Show()
                end
            end)
            editBox:HookScript("OnEditFocusLost", function(self)
                if self.__quiChatBackdrop then
                    self.__quiChatBackdrop:Hide()
                end
            end)
        end

        -- Start hidden - will show when user focuses editbox (presses Enter)
        backdrop:Hide()
        if editBox:HasFocus() then
            backdrop:Show()
        end
    else
        -- Default: Position at BOTTOM
        backdrop:SetFrameLevel(math.max(1, editBox:GetFrameLevel() - 1))
        backdrop:SetPoint("TOPLEFT", chatFrame, "BOTTOMLEFT", -8, -6)
        backdrop:SetPoint("TOPRIGHT", chatFrame, "BOTTOMRIGHT", 8, -6)
        backdrop:SetHeight(24)  -- Fixed height matching top mode

        -- Apply user-configured opacity
        local alpha = settings.editBox.bgAlpha or 0.25
        local bgColor = settings.editBox.bgColor or {0, 0, 0}
        backdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], alpha)
        backdrop:SetBackdropBorderColor(bgColor[1], bgColor[2], bgColor[3], alpha)

        -- Anchor editbox to backdrop (same as top mode for consistent alignment)
        -- Left offset of -8 aligns text with chat messages
        editBox:ClearAllPoints()
        editBox:SetPoint("LEFT", backdrop, "LEFT", -8, 0)
        editBox:SetPoint("RIGHT", backdrop, "RIGHT", -4, 0)
        editBox:SetPoint("CENTER", backdrop, "CENTER", 0, 0)

        -- Store backdrop reference on editBox for consistency
        editBox.__quiChatBackdrop = backdrop

        -- Bottom position: always show backdrop (standard behavior)
        backdrop:Show()
    end
end

---------------------------------------------------------------------------
-- Style chat tabs (General, Combat Log, etc.)
---------------------------------------------------------------------------
local function UpdateTabColors(tab)
    local settings = GetSettings()
    if not settings or not tab.__quiBackdrop then return end

    local alpha = settings.glass and settings.glass.bgAlpha or 0.4

    -- Check if this tab is selected
    local isSelected = false
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame:IsShown() then
            local frameTab = _G["ChatFrame" .. i .. "Tab"]
            if frameTab == tab then
                isSelected = true
                break
            end
        end
    end

    -- Also check button state
    if tab.GetButtonState and tab:GetButtonState() == "PUSHED" then
        isSelected = true
    end

    if isSelected then
        -- Selected: mint accent border
        tab.__quiBackdrop:SetBackdropColor(0, 0, 0, alpha + 0.2)
        tab.__quiBackdrop:SetBackdropBorderColor(QUI_COLORS.accent[1], QUI_COLORS.accent[2], QUI_COLORS.accent[3], 1)
    else
        -- Unselected: standard glass
        tab.__quiBackdrop:SetBackdropColor(0, 0, 0, alpha)
        tab.__quiBackdrop:SetBackdropBorderColor(0, 0, 0, alpha)
    end
end

local function StyleChatTab(tab)
    if not tab then return end

    local settings = GetSettings()
    if not settings or not settings.styleTabs then return end

    -- Strip default textures
    local tabName = tab:GetName()
    if tabName then
        local textures = {
            "Left", "Middle", "Right",
            "SelectedLeft", "SelectedMiddle", "SelectedRight",
            "HighlightLeft", "HighlightMiddle", "HighlightRight",
        }
        for _, suffix in ipairs(textures) do
            local tex = _G[tabName .. suffix]
            if tex and tex.SetAlpha then
                tex:SetAlpha(0)
            end
        end
    end

    -- Create glass backdrop (once)
    if not tab.__quiBackdrop then
        local backdrop = CreateFrame("Frame", nil, tab, "BackdropTemplate")
        backdrop:SetFrameLevel(math.max(1, tab:GetFrameLevel() - 1))
        backdrop:SetPoint("TOPLEFT", 2, -4)
        backdrop:SetPoint("BOTTOMRIGHT", -2, 2)
        backdrop:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        tab.__quiBackdrop = backdrop
    end

    -- Update colors
    UpdateTabColors(tab)

    -- Style font with outline
    local fontString = tab:GetFontString()
    if fontString then
        local font, size = fontString:GetFont()
        if font then
            fontString:SetFont(font, size or 12, "OUTLINE")
            fontString:SetShadowOffset(0, 0)
        end
    end
end

local function StyleAllChatTabs()
    local settings = GetSettings()
    if not settings or not settings.styleTabs then return end

    for i = 1, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then
            StyleChatTab(tab)
        end
    end
end

local function RefreshAllTabColors()
    for i = 1, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab.__quiBackdrop then
            UpdateTabColors(tab)
        end
    end
end

---------------------------------------------------------------------------
-- Apply message padding (text inset via FontStringContainer positioning)
---------------------------------------------------------------------------
local function ApplyMessagePadding(chatFrame)
    local settings = GetSettings()
    if not settings then return end

    local padding = settings.messagePadding or 0

    -- Modern chat frames use FontStringContainer for message display
    local container = chatFrame.FontStringContainer
    if container then
        container:ClearAllPoints()
        if padding > 0 then
            -- Left padding only - pushes text rightward
            container:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", padding, 0)
            container:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 0, 0)
        else
            container:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", 0, 0)
            container:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 0, 0)
        end
    end
end

---------------------------------------------------------------------------
-- Remove edit box styling (restore when disabled)
---------------------------------------------------------------------------
local function RemoveEditBoxStyle(chatFrame)
    -- Hide backdrop stored on chatFrame
    if chatFrame.__quiEditBoxBackdrop then
        chatFrame.__quiEditBoxBackdrop:Hide()
    end
end

---------------------------------------------------------------------------
-- Main skin function for a single chat frame
---------------------------------------------------------------------------
local function SkinChatFrame(chatFrame)
    if not chatFrame or chatFrame:IsForbidden() then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    local frameName = chatFrame:GetName()
    if not frameName then return end

    -- Mark as skinned
    skinnedFrames[chatFrame] = true

    -- Apply glass effect
    if settings.glass and settings.glass.enabled then
        StripDefaultTextures(chatFrame)
        CreateGlassBackdrop(chatFrame)
    end

    -- Apply font styling (always enabled)
    StyleFontStrings(chatFrame)

    -- Hook URL detection
    if settings.urls and settings.urls.enabled then
        HookChatMessages(chatFrame)
    end

    -- Setup message fade (handles both enabling and disabling)
    SetupMessageFade(chatFrame)

    -- Hide chat buttons (social, channel, scroll)
    if settings.hideButtons then
        HideChatButtons(chatFrame)
    end

    -- Style edit box
    if settings.editBox and settings.editBox.enabled then
        StyleEditBox(chatFrame)
    end

    -- Apply message padding
    ApplyMessagePadding(chatFrame)

    -- Apply copy button based on mode
    ApplyCopyButtonMode(chatFrame)
end

---------------------------------------------------------------------------
-- Skin all existing chat frames
---------------------------------------------------------------------------
local function SkinAllChatFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            SkinChatFrame(chatFrame)
        end
    end
end

---------------------------------------------------------------------------
-- Hook new chat window creation
---------------------------------------------------------------------------
local function HookNewChatWindows()
    -- Hook temporary windows (whispers, etc.)
    hooksecurefunc("FCF_OpenTemporaryWindow", function(...)
        C_Timer.After(0.1, function()
            SkinAllChatFrames()
            StyleAllChatTabs()
        end)
    end)

    -- Hook new permanent windows
    if FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function(...)
            C_Timer.After(0.1, function()
                SkinAllChatFrames()
                StyleAllChatTabs()
            end)
        end)
    end

    -- Hook tab clicks to update selection state colors AND editbox backdrop
    hooksecurefunc("FCF_Tab_OnClick", function(self)
        local tabID = self:GetID()
        C_Timer.After(0.05, function()
            RefreshAllTabColors()

            local chatFrame = _G["ChatFrame" .. tabID]
            local settings = GetSettings()

            if chatFrame and settings and settings.editBox and settings.editBox.positionTop then
                -- Use ChatFrame1's backdrop as the SINGLE shared backdrop for top position mode
                -- Parent to UIParent so it stays visible when ChatFrame1 is hidden
                -- (WoW hides ChatFrame1 when other tabs are selected)
                local sharedBackdrop = ChatFrame1.__quiEditBoxBackdrop
                if sharedBackdrop then
                    sharedBackdrop:SetParent(UIParent)
                    sharedBackdrop:ClearAllPoints()
                    sharedBackdrop:SetFrameLevel(ChatFrame1:GetFrameLevel() + 10)
                    sharedBackdrop:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", -8, 0)
                    sharedBackdrop:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 8, 0)
                    sharedBackdrop:SetHeight(24)

                    -- Update ChatFrame1EditBox's reference (it's always the active editbox)
                    ChatFrame1EditBox.__quiChatBackdrop = sharedBackdrop

                    -- If editbox has focus, show the backdrop
                    if ChatFrame1EditBox:HasFocus() then
                        sharedBackdrop:Show()
                    end
                end
            end
        end)
    end)
end

---------------------------------------------------------------------------
-- Refresh all chat styling (called from options)
---------------------------------------------------------------------------
local function RefreshAll()
    local settings = GetSettings()

    -- Handle each skinned frame
    for chatFrame in pairs(skinnedFrames) do
        -- Handle glass backdrop
        if not settings or not settings.enabled or not settings.glass or not settings.glass.enabled then
            RemoveGlassBackdrop(chatFrame)
        end

        -- Handle button visibility
        if not settings or not settings.enabled or not settings.hideButtons then
            ShowChatButtons(chatFrame)
        else
            HideChatButtons(chatFrame)
        end

        -- Handle editbox styling
        if not settings or not settings.enabled or not settings.editBox or not settings.editBox.enabled then
            RemoveEditBoxStyle(chatFrame)
        else
            -- Show editbox backdrop if it exists (for bottom position mode)
            -- Top position mode handles visibility via OnShow/OnHide hooks
            if chatFrame.__quiEditBoxBackdrop and not settings.editBox.positionTop then
                chatFrame.__quiEditBoxBackdrop:Show()
            end
        end

        -- Handle message fade (native API)
        SetupMessageFade(chatFrame)

        -- Handle copy button based on mode
        if not settings or not settings.enabled then
            HideCopyButton(chatFrame)
        else
            ApplyCopyButtonMode(chatFrame)
        end
    end

    -- Re-apply all styling if enabled
    if settings and settings.enabled then
        SkinAllChatFrames()
        StyleAllChatTabs()
    end
end

---------------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.5, function()
            local settings = GetSettings()
            if not settings or not settings.enabled then return end

            -- Setup URL click handler (once)
            SetupURLClickHandler()

            -- Skin existing chat frames
            SkinAllChatFrames()

            -- Style chat tabs
            StyleAllChatTabs()

            -- Hook for new chat windows
            HookNewChatWindows()
        end)
    end
end)

---------------------------------------------------------------------------
-- Global refresh function for GUI
---------------------------------------------------------------------------
_G.QUI_RefreshChat = RefreshAll

QUI.Chat = {
    Refresh = RefreshAll,
    SkinFrame = SkinChatFrame,
    SkinAll = SkinAllChatFrames,
}
