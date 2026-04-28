--[[
    QUI Help Tab — Page Builder
    Narrative content rendered flat: accent-dot section headers + plain
    wrapped labels + link items. No card chrome on guides — the tile
    opts into chip-strip section nav at the top via sectionNav=true,
    which auto-collects the accent-dot labels as scroll anchors.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local HelpContent = ns.QUI_HelpContent
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local CreateWrappedLabel = Shared.CreateWrappedLabel
local CreateLinkItem = Shared.CreateLinkItem
local PADDING = Shared.PADDING or 15

local SECTION_LABEL_GAP = 30  -- matches CreateAccentDotLabel's 22px height + 8 breathing room

--------------------------------------------------------------------------------
-- CONTENT: Help
--------------------------------------------------------------------------------
local function BuildHelpContent(content)
    if not HelpContent then return end

    local y = -10
    local contentWidth = 700

    GUI:SetSearchContext({tabIndex = 13, tabName = "Help"})

    -- =====================================================
    -- HEADER
    -- =====================================================
    local title = CreateWrappedLabel(content, "Help & Documentation", 20, C.accent, contentWidth)
    title:SetPoint("TOPLEFT", PADDING, y)
    y = y - 28

    local subtitle = CreateWrappedLabel(content,
        "Everything you need to get started and troubleshoot QUI.",
        12, C.textMuted, contentWidth - PADDING * 2)
    subtitle:SetPoint("TOPLEFT", PADDING, y)
    y = y - (subtitle:GetStringHeight() or 14) - 18

    -- =====================================================
    -- GETTING STARTED
    -- =====================================================
    Shared.CreateAccentDotLabel(content, "Getting Started", y); y = y - SECTION_LABEL_GAP

    if HelpContent.GettingStarted then
        for _, step in ipairs(HelpContent.GettingStarted) do
            local stepLabel = CreateWrappedLabel(content,
                "|cff60A5FA" .. step.num .. "|r  " .. step.text,
                12, C.text, contentWidth - PADDING * 2 - 10)
            stepLabel:SetPoint("TOPLEFT", PADDING + 10, y)
            y = y - (stepLabel:GetStringHeight() or 14) - 8
        end
    end
    y = y - 12

    -- =====================================================
    -- FEATURE GUIDES (flat — no card chrome)
    -- =====================================================
    Shared.CreateAccentDotLabel(content, "Feature Guides", y); y = y - SECTION_LABEL_GAP

    if HelpContent.FeatureGuides then
        for _, guide in ipairs(HelpContent.FeatureGuides) do
            local titleLabel = CreateWrappedLabel(content, guide.title, 13, C.accent, contentWidth - PADDING * 2)
            titleLabel:SetPoint("TOPLEFT", PADDING, y)
            y = y - (titleLabel:GetStringHeight() or 14) - 4

            local desc = CreateWrappedLabel(content, guide.description,
                11, C.textMuted, contentWidth - PADDING * 2 - 10)
            desc:SetPoint("TOPLEFT", PADDING + 10, y)
            y = y - (desc:GetStringHeight() or 14) - 8

            if guide.tips then
                for _, tip in ipairs(guide.tips) do
                    local tipLabel = CreateWrappedLabel(content,
                        "|cff60A5FA\226\128\162|r  " .. tip,
                        11, C.text, contentWidth - PADDING * 2 - 30)
                    tipLabel:SetPoint("TOPLEFT", PADDING + 20, y)
                    y = y - (tipLabel:GetStringHeight() or 14) - 4
                end
            end
            y = y - 14
        end
    end

    -- =====================================================
    -- SLASH COMMANDS
    -- =====================================================
    Shared.CreateAccentDotLabel(content, "Slash Commands", y); y = y - SECTION_LABEL_GAP

    if HelpContent.SlashCommands then
        for _, cmd in ipairs(HelpContent.SlashCommands) do
            local cmdLabel = CreateWrappedLabel(content,
                "|cff60A5FA" .. cmd.command .. "|r  \226\128\148  " .. cmd.description,
                12, C.text, contentWidth - PADDING * 2)
            cmdLabel:SetPoint("TOPLEFT", PADDING + 10, y)
            y = y - (cmdLabel:GetStringHeight() or 14) - 6
        end
    end
    y = y - 12

    -- =====================================================
    -- TROUBLESHOOTING
    -- =====================================================
    Shared.CreateAccentDotLabel(content, "Troubleshooting", y); y = y - SECTION_LABEL_GAP

    if HelpContent.Troubleshooting then
        for _, qa in ipairs(HelpContent.Troubleshooting) do
            local qLabel = CreateWrappedLabel(content, qa.question, 12, C.text, contentWidth - PADDING * 2)
            qLabel:SetPoint("TOPLEFT", PADDING, y)
            y = y - (qLabel:GetStringHeight() or 14) - 4

            local aLabel = CreateWrappedLabel(content, qa.answer, 11, C.textMuted, contentWidth - PADDING * 2 - 10)
            aLabel:SetPoint("TOPLEFT", PADDING + 10, y)
            y = y - (aLabel:GetStringHeight() or 14) - 12
        end
    end
    y = y - 10

    -- =====================================================
    -- LINKS & RESOURCES
    -- =====================================================
    Shared.CreateAccentDotLabel(content, "Links & Resources", y); y = y - SECTION_LABEL_GAP

    if HelpContent.Links then
        for _, link in ipairs(HelpContent.Links) do
            local linkItem = CreateLinkItem(content,
                link.label, link.url,
                link.iconR, link.iconG, link.iconB,
                link.iconTexture, link.popupTitle)
            linkItem:SetPoint("TOPLEFT", PADDING, y)
            linkItem:SetSize(contentWidth - PADDING * 2, 22)
            y = y - 28
        end
    end

    content:SetHeight(math.abs(y) + 10)
end

--------------------------------------------------------------------------------
-- PAGE: Help (legacy wrapper for callers that still need a full page)
--------------------------------------------------------------------------------
local function CreateHelpPage(parent)
    local _, content = Shared.CreateScrollableContent(parent)
    BuildHelpContent(content)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_HelpOptions = {
    BuildHelpContent = BuildHelpContent,
    CreateHelpPage = CreateHelpPage,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "helpPage",
        moverKey = "help",
        category = "help",
        nav = { tileId = "help" },
        noSearch = true,
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildHelpContent,
            }),
        },
    }))
end
