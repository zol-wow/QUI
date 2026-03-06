--[[
    QUI Options Pages
    Top-down flow layout for the /qui GUI
    Single scrollable content area per tab
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local QUICore = ns.Addon
local C = GUI.Colors

-- SEARCH TAB - Search settings across all tabs
---------------------------------------------------------------------------
local function CreateSearchPage(tabContent)
    local PAD = 15
    local y = -10

    -- Search input at top
    local searchBox = GUI:CreateSearchBox(tabContent)
    searchBox:SetSize(tabContent:GetWidth() - (PAD * 2), 28)
    searchBox:SetPoint("TOPLEFT", PAD, y)
    y = y - 40

    -- Results scroll area below
    local scrollFrame = CreateFrame("ScrollFrame", nil, tabContent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PAD, y)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local resultsContent = CreateFrame("Frame", nil, scrollFrame)
    resultsContent:SetWidth(scrollFrame:GetWidth() - 10)
    scrollFrame:SetScrollChild(resultsContent)

    -- Scroll bar styling
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)

        -- Match shared QUI scrollbar styling used across other options pages
        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8) -- Subtle grey-blue
        end

        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end

        -- Auto-hide when there is nothing to scroll
        scrollBar:HookScript("OnShow", function(self)
            C_Timer.After(0.066, function()
                local maxScroll = (ns.GetSafeVerticalScrollRange and ns.GetSafeVerticalScrollRange(scrollFrame)) or 0
                if maxScroll <= 1 then
                    self:Hide()
                end
            end)
        end)
    end

    if ns.ApplyScrollWheel then
        ns.ApplyScrollWheel(scrollFrame)
    end

    -- Initial empty state
    GUI:RenderSearchResults(resultsContent, nil, nil, nil)

    -- Wire up search callbacks
    searchBox.onSearch = function(text)
        local results, navResults = GUI:ExecuteSearch(text)
        GUI:RenderSearchResults(resultsContent, results, text, navResults)
    end

    searchBox.onClear = function()
        GUI:RenderSearchResults(resultsContent, nil, nil, nil)
    end

    tabContent.searchBox = searchBox
    tabContent.resultsContent = resultsContent
end

-- INITIALIZE OPTIONS - Main tabs
---------------------------------------------------------------------------
function GUI:InitializeOptions()
    local frame = self:CreateMainFrame()

    -- Sidebar tabs (short names for vertical layout)
    GUI:AddTab(frame, "Welcome", ns.QUI_WelcomeOptions.CreateWelcomePage)
    local generalTab = GUI:AddTab(frame, "General & QoL", ns.QUI_GeneralOptions.CreateGeneralQoLPage)
    local anchoringTab = GUI:AddTab(frame, "Anchoring & Layout", ns.QUI_FrameAnchoringOptions.CreateFrameAnchoringPage)
    local cdmTab = GUI:AddTab(frame, "Cooldown Manager", ns.QUI_NCDMOptions.CreateCDMSetupPage)
    local unitFramesTab = GUI:AddTab(frame, "Unit Frames", ns.QUI_UnitFramesOptions.CreateUnitFramesPage)
    local actionBarsTab = GUI:AddTab(frame, "Action Bars", ns.QUI_ActionBarsOptions.CreateActionBarsPage)
    local minimapTab = GUI:AddTab(frame, "Minimap & Datatext", ns.QUI_MinimapPageOptions.CreateMinimapPage)
    local skinningTab = GUI:AddTab(frame, "Skinning & Autohide", ns.QUI_AutohidesOptions.CreateAutohidesPage)
    local customTrackersTab = GUI:AddTab(frame, "Custom Trackers", ns.QUI_CustomTrackersOptions.CreateCustomTrackersPage)
    GUI:AddTab(frame, "Frame Levels", ns.QUI_HUDLayeringOptions.CreateHUDLayeringPage)
    GUI:AddTab(frame, "Profiles", ns.QUI_ProfilesOptions.CreateSpecProfilesPage)
    local importExportTab = GUI:AddTab(frame, "Import & Export Strings", ns.QUI_ImportOptions.CreateImportExportPage)

    -- Hint caret visibility on first load for tabs that have level-2 entries.
    generalTab._hasSubTabsHint = true
    anchoringTab._hasSubTabsHint = true
    cdmTab._hasSubTabsHint = true
    unitFramesTab._hasSubTabsHint = true
    actionBarsTab._hasSubTabsHint = true
    minimapTab._hasSubTabsHint = true
    skinningTab._hasSubTabsHint = true
    customTrackersTab._hasSubTabsHint = true
    importExportTab._hasSubTabsHint = true
    -- Bottom sidebar items (Search tab, Help tab, action buttons)
    local searchTab = GUI:AddTab(frame, "Search", CreateSearchPage, true)  -- isBottomItem = true
    GUI._searchTabIndex = #frame.tabs

    -- Make Search more discoverable: magnifying glass icon + subtle accent background
    local searchIcon = "|TInterface\\Common\\UI-Searchbox-Icon:12:12:0:0|t "
    searchTab.text:SetText(searchIcon .. "Search")
    local accentBg = searchTab:CreateTexture(nil, "BACKGROUND", nil, -1)
    accentBg:SetAllPoints()
    accentBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.08)
    searchTab._accentBg = accentBg

    GUI:AddTab(frame, "Help", ns.QUI_HelpOptions.CreateHelpPage, true)  -- isBottomItem = true

    GUI:AddActionButton(frame, "CDM Settings", function()
        if CooldownViewerSettings then
            CooldownViewerSettings:SetShown(not CooldownViewerSettings:IsShown())
        else
            print("|cFF56D1FFQUI:|r Cooldown Settings not available. Enable Cooldown Manager in Options > Gameplay Enhancement.")
        end
    end)

    GUI:AddActionButton(frame, "Edit Mode", function()
        if InCombatLockdown() then return end
        if EditModeManagerFrame then
            ShowUIPanel(EditModeManagerFrame)
        end
    end)

    -- Mark that all tabs have been added (for search indexing)
    GUI._allTabsAdded = true

    return frame
end
