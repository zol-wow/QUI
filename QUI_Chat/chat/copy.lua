---------------------------------------------------------------------------
-- QUI Chat Module — Copy
-- URL copy popup, full-history copy frame (custom display only), custom
-- display copy button (always/hover/hidden modes), URL click handler
-- routing through the EventRegistry SetItemRef callback.
--
-- Blizzard-frame copy-button machinery removed in Phase 11 Task 3.
-- The copy frame is populated exclusively from the custom display's
-- MessageStore; Blizzard ChatFrame live-line and persisted-history
-- paths have been excised.
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

-- Skip the on-open Select-All when the rendered text is large — the
-- selection walk is another full-text pass on top of SetText. Users can
-- still hit the Select All button on demand.
local AUTO_HIGHLIGHT_MAX_CHARS = 8000
local COPY_BUTTON_SIZE = 24
local COPY_BUTTON_FRAME_LEVEL = 100
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
if type(QUI_COLORS) ~= "table" then
    QUI_COLORS = {
        bg      = {0.067, 0.094, 0.153, 0.97},
        accent  = {0.204, 0.827, 0.600, 1},
        text    = {0.953, 0.957, 0.965, 1},
        textDim = {0.72,  0.72,  0.76,  1},
    }
end

local function ResolveAccent()
    return (I.GetAccent and I.GetAccent()) or QUI_COLORS.accent
end

local function ResolveTheme()
    if I.GetThemeColors then
        local theme = I.GetThemeColors()
        if theme then return theme end
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
        local settings = I.GetSettings and I.GetSettings()
        if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end

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

-- Lines for the CUSTOM display's copy popup: sourced from MessageStore
-- (the display's source of truth), markup-stripped, secrets replaced with
-- a placeholder (never touched).
local function GetCustomDisplayLines()
    local Store = ns.QUI.Chat.MessageStore
    if not Store then return {} end
    local lines = {}
    Store.ForEach(function(entry)
        if entry.s then
            lines[#lines + 1] = "??? (protected message)"
        else
            local cleaned = CleanMessage(entry.m)
            if cleaned ~= "" then
                lines[#lines + 1] = cleaned
            end
        end
    end)
    return lines
end
Copy.GetCustomDisplayLines = GetCustomDisplayLines

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

local function RefreshCopyGlyph(button, hovered)
    if not button then return end
    local theme = ResolveTheme()
    CreateCopyGlyph(button)
    if button._hoverBg then
        if hovered then
            button._hoverBg:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.18)
            button._hoverBg:Show()
        else
            button._hoverBg:Hide()
        end
    end
    for key, part in pairs(button._quiGlyphParts) do
        if key:find("^back") then
            ColorTexture(part, {theme.text[1], theme.text[2], theme.text[3], hovered and 0.72 or 0.55})
        else
            ColorTexture(part, {theme.accent[1], theme.accent[2], theme.accent[3], hovered and 1 or 0.95})
        end
    end
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

-- Open the chat-copy frame populated from the custom display store.
function Copy.ShowCustomCopyFrame()
    local settings = I.GetSettings and I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings)) then return end
    local frame = CreateChatCopyFrame()
    RefreshPopupAccent(frame)
    local lines = GetCustomDisplayLines()
    local text = #lines > 0 and tconcat(lines, "\n") or "(No copyable messages in custom display)"
    frame.editBox:SetText(text)
    frame.editBox:SetWidth(math.max(1, frame.scrollFrame:GetWidth() - 10))
    frame:Show()
    frame.editBox:SetFocus()
    if #text <= AUTO_HIGHLIGHT_MAX_CHARS then
        frame.editBox:HighlightText()
    end
end

local customCopyButton

-- Apply the current copyButtonMode to the already-created button and its
-- container. Called on first creation and on every subsequent EnsureCustomCopyButton
-- call so live mode-switches take effect without a /reload.
--
-- "always"  — button always visible; container hover scripts cleared; mouse released.
-- "hover"   — button hidden until container OnEnter; true OnLeave (cursor no longer
--             over the container or any child) hides it again. EnableMouse(true) makes
--             the container swallow panel-background clicks — acceptable (children keep
--             priority; SMF/drag-strip interactions are unaffected).
-- "hidden"/"disabled" — button hidden; hover scripts cleared; mouse released.
local function ApplyCustomCopyButtonMode(container)
    if not customCopyButton then return end
    local settings = I.GetSettings and I.GetSettings()
    local mode = settings and settings.copyButtonMode or "always"
    if mode == "hidden" or mode == "disabled" then
        customCopyButton:Hide()
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container:EnableMouse(false)
    elseif mode == "hover" then
        customCopyButton:Hide()
        -- OnLeave fires when entering a CHILD — only hide on a true exit.
        container:EnableMouse(true)
        container:SetScript("OnEnter", function()
            customCopyButton:Show()
        end)
        container:SetScript("OnLeave", function(self)
            if not (self.IsMouseOver and self:IsMouseOver()) then
                customCopyButton:Hide()
            end
        end)
    else -- "always"
        customCopyButton:Show()
        container:SetScript("OnEnter", nil)
        container:SetScript("OnLeave", nil)
        container:EnableMouse(false)
    end
end

function Copy.EnsureCustomCopyButton()
    local Display = ns.QUI.Chat.DisplayLayer
    local container = Display and Display.GetContainer and Display.GetContainer()
    if not container then return end
    if customCopyButton then
        -- Button already exists — re-apply mode so live settings changes
        -- (always/hover/hidden) take effect without a /reload.
        ApplyCustomCopyButtonMode(container)
        return
    end
    -- Lazy creation: skip first creation for hidden/disabled to avoid an
    -- invisible orphan button on initial load when the feature is off.
    local settings = I.GetSettings and I.GetSettings()
    local mode = settings and settings.copyButtonMode or "always"
    if mode == "hidden" or mode == "disabled" then return end
    customCopyButton = CreateFrame("Button", "QUI_CustomChatCopyButton", container)
    customCopyButton:SetSize(COPY_BUTTON_SIZE, COPY_BUTTON_SIZE)
    customCopyButton:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, 2)
    if customCopyButton.SetFrameLevel then
        customCopyButton:SetFrameLevel(COPY_BUTTON_FRAME_LEVEL)
    end
    customCopyButton:EnableMouse(true)
    customCopyButton._hoverBg = customCopyButton:CreateTexture(nil, "BACKGROUND")
    customCopyButton._hoverBg:SetAllPoints(customCopyButton)
    customCopyButton._hoverBg:Hide()
    RefreshCopyGlyph(customCopyButton, false)
    customCopyButton:SetScript("OnEnter", function(self)
        RefreshCopyGlyph(self, true)
    end)
    customCopyButton:SetScript("OnLeave", function(self)
        RefreshCopyGlyph(self, false)
    end)
    customCopyButton:SetScript("OnClick", function()
        Copy.ShowCustomCopyFrame()
    end)
    -- Apply mode (always/hover) immediately after creation.
    ApplyCustomCopyButtonMode(container)
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------
Copy.ShowURLPopup  = ShowCopyPopup
Copy.SetupURLClick = SetupURLClickHandler
