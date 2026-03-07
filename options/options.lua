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
    GUI:AddTab(frame, "General & QoL", ns.QUI_GeneralOptions.CreateGeneralQoLPage)
    GUI:AddTab(frame, "Anchoring & Layout", ns.QUI_FrameAnchoringOptions.CreateFrameAnchoringPage)
    GUI:AddTab(frame, "Cooldown Manager", ns.QUI_NCDMOptions.CreateCDMSetupPage)
    GUI:AddTab(frame, "Unit Frames", ns.QUI_UnitFramesOptions.CreateUnitFramesPage)
    GUI:AddTab(frame, "Action Bars", ns.QUI_ActionBarsOptions.CreateActionBarsPage)
    GUI:AddTab(frame, "Minimap & Datatext", ns.QUI_MinimapPageOptions.CreateMinimapPage)
    GUI:AddTab(frame, "Skinning & Autohide", ns.QUI_AutohidesOptions.CreateAutohidesPage)
    GUI:AddTab(frame, "Custom Trackers", ns.QUI_CustomTrackersOptions.CreateCustomTrackersPage)
    GUI:AddTab(frame, "Frame Levels", ns.QUI_HUDLayeringOptions.CreateHUDLayeringPage)
    GUI:AddTab(frame, "Profiles", ns.QUI_ProfilesOptions.CreateSpecProfilesPage)
    GUI:AddTab(frame, "Import & Export Strings", ns.QUI_ImportOptions.CreateImportExportPage)
    -- Bottom sidebar items (Search tab + action buttons)
    -- Add separator line between normal tabs and bottom items
    local sepLine = frame.sidebar:CreateTexture(nil, "ARTWORK")
    sepLine:SetHeight(1)
    sepLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.6)
    -- Position separator above the bottom items (will sit above 3 items * 28px + some padding)
    sepLine:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMLEFT", 8, 3 * 28 + 8)
    sepLine:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", -8, 3 * 28 + 8)

    GUI:AddTab(frame, "Search", CreateSearchPage, true)  -- isBottomItem = true
    GUI._searchTabIndex = #frame.tabs

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
