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

---------------------------------------------------------------------------
-- CONSTANTS - Match panel width (750px panel)
---------------------------------------------------------------------------
local ROW_GAP = 28
local SECTION_GAP = 38
local SECTION_HEADER_GAP = 46  -- Section header height + spacing below underline
local PADDING = 15  -- Standard left/right padding for all content
local SLIDER_HEIGHT = 65  -- Standard height for slider widgets

-- Nine-point anchor options (used for UI element positioning)
local NINE_POINT_ANCHOR_OPTIONS = {
    {value = "TOPLEFT", text = "Top Left"},
    {value = "TOP", text = "Top"},
    {value = "TOPRIGHT", text = "Top Right"},
    {value = "LEFT", text = "Left"},
    {value = "CENTER", text = "Center"},
    {value = "RIGHT", text = "Right"},
    {value = "BOTTOMLEFT", text = "Bottom Left"},
    {value = "BOTTOM", text = "Bottom"},
    {value = "BOTTOMRIGHT", text = "Bottom Right"},
}

---------------------------------------------------------------------------
-- QUAZII RECOMMENDED FPS SETTINGS (58 CVars)
---------------------------------------------------------------------------
local QUAZII_FPS_CVARS = {
    -- Graphics Tab
    ["vsync"] = "0",
    ["LowLatencyMode"] = "3",
    ["MSAAQuality"] = "0",
    ["ffxAntiAliasingMode"] = "0",
    ["alphaTestMSAA"] = "1",
    ["cameraFov"] = "90",

    -- Graphics Quality (Base)
    ["graphicsQuality"] = "9",
    ["graphicsShadowQuality"] = "0",
    ["graphicsLiquidDetail"] = "1",
    ["graphicsParticleDensity"] = "5",
    ["graphicsSSAO"] = "0",
    ["graphicsDepthEffects"] = "0",
    ["graphicsComputeEffects"] = "0",
    ["graphicsOutlineMode"] = "1",
    ["OutlineEngineMode"] = "1",
    ["graphicsTextureResolution"] = "2",
    ["graphicsSpellDensity"] = "0",
    ["spellClutter"] = "1",
    ["spellVisualDensityFilterSetting"] = "1",
    ["graphicsProjectedTextures"] = "1",
    ["projectedTextures"] = "1",
    ["graphicsViewDistance"] = "3",
    ["graphicsEnvironmentDetail"] = "0",
    ["graphicsGroundClutter"] = "0",

    -- Advanced Tab
    ["gxTripleBuffer"] = "0",
    ["textureFilteringMode"] = "5",
    ["graphicsRayTracedShadows"] = "0",
    ["rtShadowQuality"] = "0",
    ["ResampleQuality"] = "4",
    ["ffxSuperResolution"] = "1",
    ["VRSMode"] = "0",
    ["GxApi"] = "D3D12",
    ["physicsLevel"] = "0",
    ["maxFPS"] = "144",
    ["maxFPSBk"] = "60",
    ["targetFPS"] = "61",
    ["useTargetFPS"] = "0",
    ["ResampleSharpness"] = "0.2",
    ["Contrast"] = "75",
    ["Brightness"] = "50",
    ["Gamma"] = "1",

    -- Additional Optimizations
    ["particulatesEnabled"] = "0",
    ["clusteredShading"] = "0",
    ["volumeFogLevel"] = "0",
    ["reflectionMode"] = "0",
    ["ffxGlow"] = "0",
    ["farclip"] = "5000",
    ["horizonStart"] = "1000",
    ["horizonClip"] = "5000",
    ["lodObjectCullSize"] = "35",
    ["lodObjectFadeScale"] = "50",
    ["lodObjectMinSize"] = "0",
    ["doodadLodScale"] = "50",
    ["entityLodDist"] = "7",
    ["terrainLodDist"] = "350",
    ["TerrainLodDiv"] = "512",
    ["waterDetail"] = "1",
    ["rippleDetail"] = "0",
    ["weatherDensity"] = "3",
    ["entityShadowFadeScale"] = "15",
    ["groundEffectDist"] = "40",
    ["ResampleAlwaysSharpen"] = "1",

    -- Special Hacks
    ["cameraDistanceMaxZoomFactor"] = "2.6",
    ["CameraReduceUnexpectedMovement"] = "1",
}

---------------------------------------------------------------------------
-- HELPER: Get texture list from LSM
---------------------------------------------------------------------------
local LSM = LibStub("LibSharedMedia-3.0", true)

local function GetTextureList()
    local textures = {}
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            table.insert(textures, {value = name, text = name})
        end
    else
        textures = {{value = "Solid", text = "Solid"}}
    end
    return textures
end

-- Hidden frame for pre-warming fonts (forces WoW to load font files)
local fontPrewarmFrame = nil

local function GetFontList()
    local fonts = {}
    if LSM then
        -- Create a hidden frame for pre-warming fonts if needed
        if not fontPrewarmFrame then
            fontPrewarmFrame = CreateFrame("Frame", nil, UIParent)
            fontPrewarmFrame:SetSize(1, 1)
            fontPrewarmFrame:SetPoint("TOPLEFT", -9999, 9999)  -- Off-screen
            fontPrewarmFrame.text = fontPrewarmFrame:CreateFontString(nil, "OVERLAY")
            fontPrewarmFrame.text:SetPoint("CENTER")
            fontPrewarmFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")  -- Set default font first
            fontPrewarmFrame.text:SetText("A")  -- Need some text for font to load
        end

        for _, name in ipairs(LSM:List("font")) do
            local path = LSM:Fetch("font", name) or ""
            local pathLower = path:lower()

            -- Only allow fonts from WoW defaults, QUI, or SharedMedia
            local isWoWFont = pathLower:find("^fonts\\") ~= nil or pathLower:find("^fonts/") ~= nil
            local isQuaziiFont = pathLower:find("quaziiui") ~= nil
            local isSharedMediaFont = pathLower:find("sharedmedia") ~= nil

            if (isWoWFont or isQuaziiFont or isSharedMediaFont) and path ~= "" then
                -- Pre-warm the font by actually applying it (forces WoW to load the font file)
                local success = pcall(function()
                    fontPrewarmFrame.text:SetFont(path, 12, "")
                end)
                if success then
                    table.insert(fonts, {value = name, text = name})
                end
            end
        end
    else
        fonts = {{value = "Friz Quadrata TT", text = "Friz Quadrata TT"}}
    end
    return fonts
end

local function GetBorderList()
    local borders = {{value = "None", text = "None (Solid)"}}
    if LSM then
        for _, name in ipairs(LSM:List("border")) do
            table.insert(borders, {value = name, text = name})
        end
    end
    return borders
end

---------------------------------------------------------------------------
-- HELPER: Create scrollable content frame
---------------------------------------------------------------------------
local function CreateScrollableContent(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())  -- Dynamic width based on scroll frame
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    content._hasContent = false  -- Track if any content added (for auto-spacing)

    -- Update content width when scroll frame resizes (for panel resize support)
    scrollFrame:SetScript("OnSizeChanged", function(self, width, height)
        content:SetWidth(width)
    end)

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)

        -- Style the thumb (safe operation)
        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8)  -- Subtle grey-blue
        end

        -- Hide arrow buttons (modern best practice)
        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end

        -- Auto-hide scrollbar when not needed
        scrollBar:HookScript("OnShow", function(self)
            C_Timer.After(0.066, function()
                local maxScroll = scrollFrame:GetVerticalScrollRange()
                if maxScroll <= 1 then
                    self:Hide()
                end
            end)
        end)
    end
    
    ns.ApplyScrollWheel(scrollFrame)

    return scrollFrame, content
end

---------------------------------------------------------------------------
-- HELPER: Get database safely
---------------------------------------------------------------------------
local function GetDB()
    if QUICore and QUICore.db and QUICore.db.profile then
        return QUICore.db.profile
    end
    return nil
end

---------------------------------------------------------------------------
-- FPS SETTINGS FUNCTIONS (must be after GetDB)
---------------------------------------------------------------------------
local function BackupCurrentFPSSettings()
    local db = GetDB()
    local backup = {}
    for cvar, _ in pairs(QUAZII_FPS_CVARS) do
        local success, current = pcall(C_CVar.GetCVar, cvar)
        if success and current then
            backup[cvar] = current
        end
    end
    db.fpsBackup = backup
    return true
end

local function RestorePreviousFPSSettings()
    local db = GetDB()
    if not db.fpsBackup then
        print("|cffFF6B6BQUI:|r No backup found. Apply FPS settings first to create a backup.")
        return false
    end

    local successCount = 0
    local failCount = 0
    for cvar, value in pairs(db.fpsBackup) do
        local ok = pcall(C_CVar.SetCVar, cvar, tostring(value))
        if ok then
            successCount = successCount + 1
        else
            failCount = failCount + 1
        end
    end

    -- Clear backup after successful restore
    db.fpsBackup = nil

    print("|cff34D399QUI:|r Restored " .. successCount .. " previous settings.")
    if failCount > 0 then
        print("|cffFF6B6BQUI:|r " .. failCount .. " settings could not be restored.")
    end
    return true
end

local function ApplyQuaziiFPSSettings()
    -- Backup current settings first
    BackupCurrentFPSSettings()

    local successCount = 0
    local failCount = 0

    for cvar, value in pairs(QUAZII_FPS_CVARS) do
        local success = pcall(function()
            C_CVar.SetCVar(cvar, value)
        end)

        if success then
            successCount = successCount + 1
        else
            failCount = failCount + 1
        end
    end

    print("|cff34D399QUI:|r Your previous settings have been backed up.")
    print("|cff34D399QUI:|r Applied " .. successCount .. " FPS settings. Use 'Restore Previous Settings' to undo.")
    if failCount > 0 then
        print("|cffFF6B6BQUI:|r " .. failCount .. " settings could not be applied (may require restart).")
    end
end

local function CheckCVarsMatch()
    local matchCount, totalCount = 0, 0
    for cvar, expectedVal in pairs(QUAZII_FPS_CVARS) do
        totalCount = totalCount + 1
        local currentVal = C_CVar.GetCVar(cvar)
        if currentVal == expectedVal then
            matchCount = matchCount + 1
        end
    end
    return matchCount == totalCount, matchCount, totalCount
end

---------------------------------------------------------------------------
-- HELPER: Refresh callbacks
---------------------------------------------------------------------------
local function RefreshAll()
    if QUICore and QUICore.RefreshAll then QUICore:RefreshAll() end
end

local function RefreshMinimap()
    if QUICore and QUICore.Minimap and QUICore.Minimap.Refresh then QUICore.Minimap:Refresh() end
end

local function RefreshUIHider()
    if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end
end

local function RefreshUnitFrames(unit)
    if QUICore and QUICore.UnitFrames then
        -- If unit is a string (valid unit name), update that specific frame
        -- Otherwise (nil, boolean from checkbox, etc.), refresh all frames
        if type(unit) == "string" then
            QUICore.UnitFrames:UpdateUnitFrame(unit)
        else
            QUICore.UnitFrames:RefreshFrames()
        end
    end
end

local function RefreshBuffBorders()
    if _G.QUI_RefreshBuffBorders then
        _G.QUI_RefreshBuffBorders()
    end
end

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
    GUI:AddTab(frame, "General & QoL", ns.QUI_GeneralOptions.CreateGeneralQoLPage)
    GUI:AddTab(frame, "Cooldown Manager", ns.QUI_NCDMOptions.CreateCDMSetupPage)
    GUI:AddTab(frame, "Unit Frames", ns.QUI_UnitFramesOptions.CreateUnitFramesPage)
    GUI:AddTab(frame, "Action Bars", ns.QUI_ActionBarsOptions.CreateActionBarsPage)
    GUI:AddTab(frame, "Minimap & Datatext", ns.QUI_MinimapPageOptions.CreateMinimapPage)
    GUI:AddTab(frame, "Skinning & Autohide", ns.QUI_AutohidesOptions.CreateAutohidesPage)
    GUI:AddTab(frame, "Custom Trackers", ns.QUI_CustomTrackersOptions.CreateCustomTrackersPage)
    GUI:AddTab(frame, "Frame Levels", ns.QUI_HUDLayeringOptions.CreateHUDLayeringPage)
    GUI:AddTab(frame, "Profiles", ns.QUI_ProfilesOptions.CreateSpecProfilesPage)
    GUI:AddTab(frame, "Import", ns.QUI_ImportOptions.CreateImportExportPage)
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
        if EditModeManagerFrame then
            ShowUIPanel(EditModeManagerFrame)
        end
    end)

    -- Mark that all tabs have been added (for search indexing)
    GUI._allTabsAdded = true

    return frame
end
