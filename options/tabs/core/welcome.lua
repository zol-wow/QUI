local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

local CreateScrollableContent = Shared.CreateScrollableContent
local PADDING = Shared.PADDING or 15

--------------------------------------------------------------------------------
-- Helper: pixel size
--------------------------------------------------------------------------------
local function SafeGetPixelSize(frame)
    local core = ns.Addon
    return (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
end

--------------------------------------------------------------------------------
-- Helper: Create a compact link item (icon + label + copy button)
-- Returns a frame that can be placed inline alongside other items
--------------------------------------------------------------------------------
local COPY_ICON = "|TInterface\\Buttons\\UI-GuildButton-PublicNote-Up:11|t "
local function CreateLinkItem(parent, label, url, iconR, iconG, iconB, iconTexture, popupTitle)
    local item = CreateFrame("Frame", nil, parent)
    item:SetHeight(22)

    -- Icon (custom texture file or colored square fallback)
    local icon = item:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 0, 0)
    if iconTexture then
        icon:SetTexture(iconTexture)
        icon:SetVertexColor(iconR or 1, iconG or 1, iconB or 1)
    else
        icon:SetColorTexture(iconR or 1, iconG or 1, iconB or 1, 1)
    end

    -- Label text
    local fontPath = GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF"
    local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(fontPath, 11, "")
    text:SetTextColor(C.text[1], C.text[2], C.text[3])
    text:SetText(label .. "  |cff999999" .. url .. "|r")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)

    -- Copy button with icon
    local btn = CreateFrame("Button", nil, item, "BackdropTemplate")
    btn:SetSize(56, 18)
    btn:SetPoint("LEFT", text, "RIGHT", 8, 0)

    local px = SafeGetPixelSize(btn)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetFont(fontPath, 9, "")
    btnText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    btnText:SetText(COPY_ICON .. "COPY")
    btnText:SetPoint("CENTER")

    btn:SetScript("OnClick", function()
        if GUI and GUI.ShowExportPopup then
            GUI:ShowExportPopup(popupTitle or "Copy Link", url)
        end

        btnText:SetText("OPENED")
        C_Timer.After(2, function()
            if btnText then btnText:SetText(COPY_ICON .. "COPY") end
        end)
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)

    -- Calculate total width for inline placement
    item.totalWidth = 14 + 6 + (text:GetStringWidth() or 200) + 8 + 56

    return item
end

--------------------------------------------------------------------------------
-- Helper: Create a wrapped paragraph label (auto word-wrap)
--------------------------------------------------------------------------------
local function CreateWrappedLabel(parent, text, size, color, maxWidth)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontPath = GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF"
    label:SetFont(fontPath, size or 12, "")
    label:SetTextColor(unpack(color or C.text))
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetNonSpaceWrap(true)
    if maxWidth then
        label:SetWidth(maxWidth)
    end
    return label
end

--------------------------------------------------------------------------------
-- Helper: Create a Q/A pair (bold question + muted answer)
--------------------------------------------------------------------------------
local function CreateQA(parent, question, answer, y, contentWidth)
    local qLabel = CreateWrappedLabel(parent, question, 12, C.text, contentWidth - PADDING * 2)
    qLabel:SetPoint("TOPLEFT", PADDING, y)
    local qHeight = qLabel:GetStringHeight() or 14
    y = y - qHeight - 4

    local aLabel = CreateWrappedLabel(parent, answer, 11, C.textMuted, contentWidth - PADDING * 2 - 10)
    aLabel:SetPoint("TOPLEFT", PADDING + 10, y)
    local aHeight = aLabel:GetStringHeight() or 14
    y = y - aHeight - 12

    return y
end

--------------------------------------------------------------------------------
-- PAGE: Welcome (single scrollable page, no subtabs)
--------------------------------------------------------------------------------
local function CreateWelcomePage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local y = -10
    local contentWidth = 700

    -- =====================================================
    -- WELCOME HEADER
    -- =====================================================
    local version = QUI.versionString or "2.00"
    local title = CreateWrappedLabel(content, "Welcome to QUI", 20, C.accent, contentWidth)
    title:SetPoint("TOPLEFT", PADDING, y)
    y = y - 28

    local versionLabel = CreateWrappedLabel(content, "v" .. version, 12, C.textMuted, contentWidth)
    versionLabel:SetPoint("TOPLEFT", PADDING, y)
    y = y - 22

    local tagline = CreateWrappedLabel(content,
        "A comprehensive UI replacement for World of Warcraft. Customizable unit frames, cooldown management, action bars, and quality-of-life features.",
        12, C.textMuted, contentWidth - PADDING * 2)
    tagline:SetPoint("TOPLEFT", PADDING, y)
    y = y - (tagline:GetStringHeight() or 14) - 14

    -- Links (both on one row, parented directly to content)
    local discordItem = CreateLinkItem(content,
        "|cff5865F2Discord|r", "https://discord.gg/FFUjA4JXnH",
        0.345, 0.396, 0.949,  -- Discord blurple
        "Interface\\AddOns\\QUI\\assets\\discord",
        "Copy Discord Invite")
    discordItem:SetPoint("TOPLEFT", PADDING, y)
    discordItem:SetSize(320, 22)

    local githubItem = CreateLinkItem(content,
        "|cffF0F6FCGitHub|r", "https://github.com/zol-wow/QUI",
        0.941, 0.965, 0.988,  -- GitHub light
        "Interface\\AddOns\\QUI\\assets\\github",
        "Copy GitHub URL")
    githubItem:SetPoint("TOPLEFT", PADDING + 330, y)
    githubItem:SetSize(350, 22)

    y = y - 40

    -- =====================================================
    -- QUICK SETUP GUIDE
    -- =====================================================
    local setupHeader = GUI:CreateSectionHeader(content, "Quick Setup Guide")
    setupHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - setupHeader.gap

    local steps = {
        {num = "1.", text = "Import the Edit Mode string (below) into Blizzard Edit Mode to position default frames"},
        {num = "2.", text = "Open |cff34D399/qui|r to browse and configure settings for each module"},
        {num = "3.", text = "Import a QUI profile from the |cff34D399Import & Export Strings|r tab for a recommended starting layout"},
        {num = "4.", text = "Type |cff34D399/rl|r to reload the UI after making changes"},
    }

    for _, step in ipairs(steps) do
        local stepLabel = CreateWrappedLabel(content,
            "|cff34D399" .. step.num .. "|r  " .. step.text,
            12, C.text, contentWidth - PADDING * 2 - 10)
        stepLabel:SetPoint("TOPLEFT", PADDING + 10, y)
        y = y - (stepLabel:GetStringHeight() or 14) - 8
    end
    y = y - 12

    -- =====================================================
    -- FAQ
    -- =====================================================
    local faqHeader = GUI:CreateSectionHeader(content, "Frequently Asked Questions")
    faqHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - faqHeader.gap

    y = CreateQA(content,
        "What is QUI?",
        "QUI (QuaziiUI) is a full UI replacement addon. It provides custom unit frames, cooldown tracking, action bar styling, data panels, and many quality-of-life improvements \226\128\148 all configurable from a single options panel.",
        y, contentWidth)

    y = CreateQA(content,
        "How do I move and resize frames?",
        "Open Blizzard Edit Mode (Escape > Edit Mode, or type /qui editmode) to reposition the default Blizzard frames. For best results with QUI's skinning, anchoring, and auto-sizing features, set all frames to 100% size in Edit Mode. QUI's own frame anchoring is under the Anchoring & Layout tab in /qui.",
        y, contentWidth)

    y = CreateQA(content,
        "What is the Cooldown Manager (CDM)?",
        "The Cooldown Manager displays your ability cooldowns as icon bars near your character. Configure which spells to track, bar appearance, and glow effects in the Cooldown Manager tab. You can also open CDM-specific settings with /cdm.",
        y, contentWidth)

    y = CreateQA(content,
        "How do I set up keybinds?",
        "Type /kb to open the keybind overlay. Hover over any action button and press a key to bind it. Keybind display settings are in the Cooldown Manager tab under Keybinds.",
        y, contentWidth)

    y = CreateQA(content,
        "How do I report a bug or get help?",
        "First, try importing the QUI Edit Mode layout string (below) as a starting point. If you're still encountering issues, raise an issue on GitHub (https://github.com/zol-wow/QUI) or ask for help on Discord (https://discord.gg/FFUjA4JXnH). Links with copy buttons are at the top of this page.",
        y, contentWidth)

    y = y - 10

    -- =====================================================
    -- EDIT MODE LAYOUT STRING
    -- =====================================================
    local editModeHeader = GUI:CreateSectionHeader(content, "QUI Edit Mode Layout String")
    editModeHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - editModeHeader.gap

    local editModeDesc = CreateWrappedLabel(content,
        "Copy this string and import it in Blizzard Edit Mode (Escape > Edit Mode > Layout dropdown > Import) to set up these default frame positions. Use this as a starting point for your layout if you encounter any unusual errors with your old layout or even the Quazii Edit Mode string.",
        11, C.textMuted, contentWidth - PADDING * 2)
    editModeDesc:SetPoint("TOPLEFT", PADDING, y)
    y = y - (editModeDesc:GetStringHeight() or 14) - 10

    -- Load Edit Mode string from importstrings/qui_editmode_base.lua
    local editModeString = ""
    if _G.QUI and _G.QUI.imports and _G.QUI.imports.QUIEditMode then
        editModeString = _G.QUI.imports.QUIEditMode.data or ""
    end

    local BOX_HEIGHT = 80

    local boxContainer = CreateFrame("Frame", nil, content, "BackdropTemplate")
    boxContainer:SetPoint("TOPLEFT", PADDING, y)
    boxContainer:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
    boxContainer:SetHeight(BOX_HEIGHT)
    local px = SafeGetPixelSize(boxContainer)
    boxContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    boxContainer:SetBackdropColor(0.05, 0.07, 0.1, 0.9)
    boxContainer:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, boxContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", boxContainer, "TOPRIGHT", -4, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", boxContainer, "BOTTOMRIGHT", -4, 18)

        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8)
        end

        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end
    end

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() or 400)
    editBox:SetText(editModeString)
    editBox:SetCursorPosition(0)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    boxContainer:SetScript("OnSizeChanged", function(self)
        editBox:SetWidth(self:GetWidth() - 36)
    end)

    scrollFrame:SetScrollChild(editBox)
    ns.ApplyScrollWheel(scrollFrame)

    y = y - BOX_HEIGHT - 8

    -- SELECT ALL button + hint
    local selectBtn = GUI:CreateButton(content, "SELECT ALL", 120, 28, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectBtn:SetPoint("TOPLEFT", PADDING, y)

    local copyHint = GUI:CreateLabel(content, "then press Ctrl+C to copy", 11, C.textMuted)
    copyHint:SetPoint("LEFT", selectBtn, "RIGHT", 12, 0)

    y = y - 50

    -- Set total content height for scrolling
    content:SetHeight(math.abs(y) + 0)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_WelcomeOptions = {
    CreateWelcomePage = CreateWelcomePage,
}
