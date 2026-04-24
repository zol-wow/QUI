local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

local CreateScrollableContent = Shared.CreateScrollableContent
local CreateWrappedLabel = Shared.CreateWrappedLabel
local CreateLinkItem = Shared.CreateLinkItem
local PADDING = Shared.PADDING or 15

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
    local version = QUI.versionString or "3.00"
    local title = CreateWrappedLabel(content, "Welcome to QUI", 20, C.accent, contentWidth)
    title:SetPoint("TOPLEFT", PADDING, y)
    y = y - 28

    local versionLabel = CreateWrappedLabel(content, "v" .. version, 12, C.textMuted, contentWidth)
    versionLabel:SetPoint("TOPLEFT", PADDING, y)
    y = y - 22

    local tagline = CreateWrappedLabel(content,
        "A comprehensive UI suite for World of Warcraft with custom unit and group frames, cooldown tracking, action bars, anchoring and layout tools, profile import/export, and quality-of-life features.",
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
    Shared.CreateAccentDotLabel(content, "Quick Setup Guide", y); y = y - 30

    local steps = {
        {num = "1.", text = "Open |cff60A5FA/qui|r to browse settings, then use the Search tab if you are not sure where a system lives"},
        {num = "2.", text = "If you want a starting point, install a bundled preset from the |cff60A5FAProfiles|r tab or analyze/import a current QUI profile in |cff60A5FAImport & Export Strings|r"},
        {num = "3.", text = "Use |cff60A5FA/qui layout|r or the |cff60A5FAQUI Edit Mode|r button to move QUI-managed frames, then fine-tune anchors and nudges in |cff60A5FAFrame Positioning|r"},
        {num = "4.", text = "Use Blizzard Edit Mode only for Blizzard-managed elements that QUI does not replace or anchor for you"},
        {num = "5.", text = "Type |cff60A5FA/rl|r after profile imports or larger changes when a module asks for a reload"},
    }

    for _, step in ipairs(steps) do
        local stepLabel = CreateWrappedLabel(content,
            "|cff60A5FA" .. step.num .. "|r  " .. step.text,
            12, C.text, contentWidth - PADDING * 2 - 10)
        stepLabel:SetPoint("TOPLEFT", PADDING + 10, y)
        y = y - (stepLabel:GetStringHeight() or 14) - 8
    end
    y = y - 12

    -- =====================================================
    -- FAQ
    -- =====================================================
    Shared.CreateAccentDotLabel(content, "Frequently Asked Questions", y); y = y - 30

    y = CreateQA(content,
        "What is QUI?",
        "QUI is a full UI suite built around QUI 3 systems: custom unit and group frames, Cooldown Manager viewers, action bar styling, anchoring and layout tools, profile import/export, skinning, and quality-of-life modules - all configurable from one options panel.",
        y, contentWidth)

    y = CreateQA(content,
        "How do I move and resize frames?",
        "For QUI-managed elements, use the |cff60A5FAQUI Edit Mode|r button or type |cff60A5FA/qui layout|r to drag frames, then use |cff60A5FAFrame Positioning|r for exact anchors, offsets, and nudging. Use Blizzard Edit Mode only for Blizzard frames that QUI does not replace. You generally do not need to import a separate Edit Mode string to get started anymore.",
        y, contentWidth)

    y = CreateQA(content,
        "What is QUI Layout Mode?",
        "Layout Mode is QUI's drag-and-place workflow for QUI-managed frames. It is the fastest way to get elements roughly where you want them on screen. After that, use |cff60A5FAFrame Positioning|r when you want precise anchors, offsets, and nudge controls instead of freeform dragging.",
        y, contentWidth)

    y = CreateQA(content,
        "What is the Cooldown Manager (CDM)?",
        "The Cooldown Manager powers QUI's essential and utility cooldown viewers, buff trackers, and tracked bars. Use |cff60A5FA/qui cdm|r to open the CDM Spell Composer and control what gets tracked, then use the Cooldown Manager tab for appearance, glows, keybind text, and custom-entry behavior. If you need Blizzard's viewer settings panel itself, use |cff60A5FA/cdm|r.",
        y, contentWidth)

    y = CreateQA(content,
        "Coming from QUI 2.x or old Quazii strings?",
        "Prefer QUI 3 presets or current QUI profile strings over legacy Quazii or Edit Mode strings. QUI 3 has newer layout, anchoring, cooldown, and selective import systems, so older strings can miss settings or conflict with the current defaults.",
        y, contentWidth)

    y = CreateQA(content,
        "How do I set up keybinds?",
        "Type |cff60A5FA/kb|r to open the keybind overlay. Hover over any action button and press a key to bind it. Keybind display settings and override text live in the Cooldown Manager tab under Keybinds.",
        y, contentWidth)

    y = CreateQA(content,
        "How do I report a bug or get help?",
        "If something still looks wrong after reloading or trying a current QUI 3 preset/profile import, enable Lua errors with |cff60A5FA/console scriptErrors 1|r and report the issue on GitHub (https://github.com/zol-wow/QUI) or ask on Discord (https://discord.gg/FFUjA4JXnH). Links with copy buttons are at the top of this page.",
        y, contentWidth)

    y = y - 10

    -- Set total content height for scrolling
    content:SetHeight(math.abs(y) + 0)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_WelcomeOptions = {
    CreateWelcomePage = CreateWelcomePage,
}
