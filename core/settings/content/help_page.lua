--[[
    QUI Help Tab — Page Builder
    Migrated to V3 section pattern (Opts.CreateAccentDotLabel). Help
    content is narrative (wrapped labels + expandable guides + link
    items), not interactive settings — so there are no widget rows to
    pair into cards; the section headers just get the accent-dot style
    for visual consistency with other V3 tabs.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local HelpContent = ns.QUI_HelpContent

local CreateScrollableContent = Shared.CreateScrollableContent
local CreateWrappedLabel = Shared.CreateWrappedLabel
local CreateLinkItem = Shared.CreateLinkItem
local PADDING = Shared.PADDING or 15

local SECTION_LABEL_GAP = 30  -- matches CreateAccentDotLabel's 22px height + 8 breathing room

--------------------------------------------------------------------------------
-- PAGE: Help (single scrollable page)
--------------------------------------------------------------------------------
local function CreateHelpPage(parent)
    if not HelpContent then return end

    local scroll, content = CreateScrollableContent(parent)
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
    -- FEATURE GUIDES (collapsible sections)
    -- =====================================================
    Shared.CreateAccentDotLabel(content, "Feature Guides", y); y = y - SECTION_LABEL_GAP

    local guideDesc = CreateWrappedLabel(content,
        "Click a section below to expand detailed guidance for each feature.",
        11, C.textMuted, contentWidth - PADDING * 2)
    guideDesc:SetPoint("TOPLEFT", PADDING, y)
    y = y - (guideDesc:GetStringHeight() or 14) - 10

    -- Build all guide sections with relative anchoring
    local guideSections = {}
    local prevAnchor = nil  -- frame to anchor next section to
    local prevAnchorY = y   -- y offset for first section

    if HelpContent.FeatureGuides then
        for i, guide in ipairs(HelpContent.FeatureGuides) do
            -- V3 inline card (always visible). CreateInlineCollapsible returns
            -- (section, body); body is where child widgets get parented.
            local section, sectionContent = Shared.CreateInlineCollapsible(
                content, guide.title, 100)
            section:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)

            if prevAnchor then
                section:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -6)
            else
                section:SetPoint("TOPLEFT", PADDING, prevAnchorY)
            end

            local sy = -6

            -- Description
            local desc = CreateWrappedLabel(sectionContent, guide.description,
                11, C.textMuted, contentWidth - PADDING * 2 - 20)
            desc:SetPoint("TOPLEFT", 10, sy)
            sy = sy - (desc:GetStringHeight() or 14) - 10

            -- Tips
            if guide.tips then
                local tipsLabel = CreateWrappedLabel(sectionContent, "Tips:", 11, C.accent, contentWidth - PADDING * 2 - 20)
                tipsLabel:SetPoint("TOPLEFT", 10, sy)
                sy = sy - (tipsLabel:GetStringHeight() or 14) - 4

                for _, tip in ipairs(guide.tips) do
                    local tipLabel = CreateWrappedLabel(sectionContent,
                        "|cff60A5FA\226\128\162|r  " .. tip,
                        11, C.text, contentWidth - PADDING * 2 - 40)
                    tipLabel:SetPoint("TOPLEFT", 20, sy)
                    sy = sy - (tipLabel:GetStringHeight() or 14) - 4
                end
            end
            sy = sy - 4

            sectionContent:SetHeight(math.abs(sy))
            if section.RefreshContentHeight then section:RefreshContentHeight() end

            prevAnchor = section
            table.insert(guideSections, section)
        end
    end

    -- =====================================================
    -- CONTAINER for everything after guides
    -- Uses relative anchoring to the last guide section
    -- so expand/collapse automatically reflows
    -- =====================================================
    local afterGuidesContainer = CreateFrame("Frame", nil, content)
    afterGuidesContainer:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    if prevAnchor then
        afterGuidesContainer:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", -PADDING, -12)
    else
        afterGuidesContainer:SetPoint("TOPLEFT", PADDING, prevAnchorY - 12)
    end

    local ay = 0

    -- =====================================================
    -- SLASH COMMANDS
    -- =====================================================
    Shared.CreateAccentDotLabel(afterGuidesContainer, "Slash Commands", ay); ay = ay - SECTION_LABEL_GAP

    if HelpContent.SlashCommands then
        for _, cmd in ipairs(HelpContent.SlashCommands) do
            local cmdLabel = CreateWrappedLabel(afterGuidesContainer,
                "|cff60A5FA" .. cmd.command .. "|r  \226\128\148  " .. cmd.description,
                12, C.text, contentWidth - PADDING * 2)
            cmdLabel:SetPoint("TOPLEFT", PADDING + 10, ay)
            ay = ay - (cmdLabel:GetStringHeight() or 14) - 6
        end
    end
    ay = ay - 12

    -- =====================================================
    -- TROUBLESHOOTING
    -- =====================================================
    Shared.CreateAccentDotLabel(afterGuidesContainer, "Troubleshooting", ay); ay = ay - SECTION_LABEL_GAP

    if HelpContent.Troubleshooting then
        for _, qa in ipairs(HelpContent.Troubleshooting) do
            local qLabel = CreateWrappedLabel(afterGuidesContainer, qa.question, 12, C.text, contentWidth - PADDING * 2)
            qLabel:SetPoint("TOPLEFT", PADDING, ay)
            ay = ay - (qLabel:GetStringHeight() or 14) - 4

            local aLabel = CreateWrappedLabel(afterGuidesContainer, qa.answer, 11, C.textMuted, contentWidth - PADDING * 2 - 10)
            aLabel:SetPoint("TOPLEFT", PADDING + 10, ay)
            ay = ay - (aLabel:GetStringHeight() or 14) - 12
        end
    end
    ay = ay - 10

    -- =====================================================
    -- LINKS & RESOURCES
    -- =====================================================
    Shared.CreateAccentDotLabel(afterGuidesContainer, "Links & Resources", ay); ay = ay - SECTION_LABEL_GAP

    if HelpContent.Links then
        for _, link in ipairs(HelpContent.Links) do
            local linkItem = CreateLinkItem(afterGuidesContainer,
                link.label, link.url,
                link.iconR, link.iconG, link.iconB,
                link.iconTexture, link.popupTitle)
            linkItem:SetPoint("TOPLEFT", PADDING, ay)
            linkItem:SetSize(contentWidth - PADDING * 2, 22)
            ay = ay - 28
        end
    end

    local afterGuidesHeight = math.abs(ay) + 10
    afterGuidesContainer:SetHeight(afterGuidesHeight)

    -- =====================================================
    -- CONTENT HEIGHT MANAGEMENT
    -- =====================================================
    local function RecalcContentHeight()
        C_Timer.After(0.01, function()
            if not content:GetParent() then return end
            local containerTop = afterGuidesContainer:GetTop()
            local contentTop = content:GetTop()
            if containerTop and contentTop then
                local offset = contentTop - containerTop
                content:SetHeight(offset + afterGuidesHeight + 20)
            else
                content:SetHeight(1200)
            end
        end)
    end

    for _, section in ipairs(guideSections) do
        section.OnExpandChanged = function()
            RecalcContentHeight()
        end
    end

    RecalcContentHeight()
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_HelpOptions = {
    CreateHelpPage = CreateHelpPage,
}
