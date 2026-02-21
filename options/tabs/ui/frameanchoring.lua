local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers

-- Local references for shared infrastructure
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local FORM_ROW = 32
local HUD_MIN_WIDTH_DEFAULT = Helpers.HUD_MIN_WIDTH_DEFAULT or 200
local HUD_MIN_WIDTH_MIN = Helpers.HUD_MIN_WIDTH_MIN or 100
local HUD_MIN_WIDTH_MAX = Helpers.HUD_MIN_WIDTH_MAX or 500

local GetCore = Helpers.GetCore

-- Lazy-load AnchorOpts (utility/anchoring.lua loads after this file in tabs.xml)
local function GetAnchorOpts()
    return ns.QUI_Anchoring_Options
end

-- Nine-point anchor options (inline fallback, used if AnchorOpts not loaded yet)
local NINE_POINT_OPTIONS = {
    {value = "TOPLEFT", text = "Top Left"},
    {value = "TOP", text = "Top Center"},
    {value = "TOPRIGHT", text = "Top Right"},
    {value = "LEFT", text = "Center Left"},
    {value = "CENTER", text = "Center"},
    {value = "RIGHT", text = "Center Right"},
    {value = "BOTTOMLEFT", text = "Bottom Left"},
    {value = "BOTTOM", text = "Bottom Center"},
    {value = "BOTTOMRIGHT", text = "Bottom Right"},
}

local DEFAULTS = {
    enabled      = false,
    parent       = "screen",
    point        = "CENTER",
    relative     = "CENTER",
    offsetX      = 0,
    offsetY      = 0,
    sizeStable   = true,
    autoWidth    = false,
    widthAdjust  = 0,
    autoHeight   = false,
    heightAdjust = 0,
}

---------------------------------------------------------------------------
-- DATABASE HELPERS
---------------------------------------------------------------------------
local function GetAnchoringDB()
    local core = GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    if type(db.frameAnchoring) ~= "table" then
        db.frameAnchoring = {}
    end

    -- Migrate and normalize legacy scalar keys to object style:
    -- frameAnchoring.hudMinWidth = { enabled = bool, width = number }
    local hudMinWidth
    if Helpers.MigrateHUDMinWidthSettings then
        hudMinWidth = Helpers.MigrateHUDMinWidthSettings(db.frameAnchoring)
    end
    if not hudMinWidth then
        local enabled, width = false, HUD_MIN_WIDTH_DEFAULT
        if Helpers.ParseHUDMinWidth then
            enabled, width = Helpers.ParseHUDMinWidth(db.frameAnchoring)
        end
        hudMinWidth = {
            enabled = enabled == true,
            width = width or HUD_MIN_WIDTH_DEFAULT,
        }
        db.frameAnchoring.hudMinWidth = hudMinWidth
        db.frameAnchoring.hudMinWidthEnabled = nil
    end

    return db.frameAnchoring
end

local function GetFrameDB(key)
    local anchoringDB = GetAnchoringDB()
    if not anchoringDB then return nil end
    if not anchoringDB[key] then
        anchoringDB[key] = {}
    end
    -- Backfill missing defaults (handles entries created before new fields were added)
    for k, v in pairs(DEFAULTS) do
        if anchoringDB[key][k] == nil then
            anchoringDB[key][k] = v
        end
    end
    return anchoringDB[key]
end

---------------------------------------------------------------------------
-- SHARED: Build frame entry widgets for a single frame key
---------------------------------------------------------------------------
local function BuildFrameEntry(tabContent, frameDef, y)
    local PAD = PADDING
    local AnchorOpts = GetAnchorOpts()
    local ninePointOptions = AnchorOpts and AnchorOpts:GetNinePointAnchorOptions() or NINE_POINT_OPTIONS

    local frameDB = GetFrameDB(frameDef.key)
    if not frameDB then return y end

    local function OnChange()
        if _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor(frameDef.key)
        end
    end

    -- Frame section header (blue title + underline)
    local sectionHeader = GUI:CreateSectionHeader(tabContent, frameDef.name)
    sectionHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - sectionHeader.gap

    -- Enable toggle
    local toggle = GUI:CreateFormToggle(tabContent, "Enable Override", "enabled", frameDB, OnChange)
    toggle:SetPoint("TOPLEFT", PAD + 10, y)
    toggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Anchor To dropdown (uses anchor target registry)
    if AnchorOpts then
        local anchorDropdown = AnchorOpts:CreateAnchorDropdown(
            tabContent, "Anchor To", frameDB, "parent",
            PAD + 10, y, nil, OnChange,
            nil, nil, frameDef.key  -- excludeSelf
        )
        if anchorDropdown then
            anchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end
    end

    -- From Point dropdown (source anchor)
    local fromPoint = GUI:CreateFormDropdown(tabContent, "From Point", ninePointOptions, "point", frameDB, OnChange)
    fromPoint:SetPoint("TOPLEFT", PAD + 10, y)
    fromPoint:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- To Point dropdown (target anchor)
    local toPoint = GUI:CreateFormDropdown(tabContent, "To Point", ninePointOptions, "relative", frameDB, OnChange)
    toPoint:SetPoint("TOPLEFT", PAD + 10, y)
    toPoint:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Offset X slider
    local sliderX = GUI:CreateFormSlider(tabContent, "Offset X", -500, 500, 1, "offsetX", frameDB, OnChange)
    sliderX:SetPoint("TOPLEFT", PAD + 10, y)
    sliderX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Offset Y slider
    local sliderY = GUI:CreateFormSlider(tabContent, "Offset Y", -500, 500, 1, "offsetY", frameDB, OnChange)
    sliderY:SetPoint("TOPLEFT", PAD + 10, y)
    sliderY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Auto-width toggle (match anchor target width)
    if frameDef.autoWidth then
        local autoWidthToggle = GUI:CreateFormToggle(tabContent, "Auto-Width (Match Anchor Target)", "autoWidth", frameDB, OnChange)
        autoWidthToggle:SetPoint("TOPLEFT", PAD + 10, y)
        autoWidthToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local widthAdjust = GUI:CreateFormSlider(tabContent, "Width Adjustment", -20, 20, 1, "widthAdjust", frameDB, OnChange)
        widthAdjust:SetPoint("TOPLEFT", PAD + 10, y)
        widthAdjust:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    end

    -- Auto-height toggle (match CDM Essential row 1 icon height)
    if frameDef.autoHeight then
        local autoHeightToggle = GUI:CreateFormToggle(tabContent, "Auto-Height (Match CDM Row 1 Icon)", "autoHeight", frameDB, OnChange)
        autoHeightToggle:SetPoint("TOPLEFT", PAD + 10, y)
        autoHeightToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local heightAdjust = GUI:CreateFormSlider(tabContent, "Height Adjustment", -20, 20, 1, "heightAdjust", frameDB, OnChange)
        heightAdjust:SetPoint("TOPLEFT", PAD + 10, y)
        heightAdjust:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    end

    y = y - 2  -- Small spacing between frame entries (header already adds separation)
    return y
end

---------------------------------------------------------------------------
-- TAB BUILDERS (one per category)
---------------------------------------------------------------------------
local function BuildCDMTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 1, subTabName = "CDM"})
    local y = -10
    local anchoringDB = GetAnchoringDB()
    local hudMinWidth = anchoringDB and anchoringDB.hudMinWidth

    local function RefreshHUDWidth()
        if _G.QUI_RefreshNCDM then
            _G.QUI_RefreshNCDM()
        elseif _G.QUI_UpdateAnchoredFrames then
            _G.QUI_UpdateAnchoredFrames()
        end
    end

    if hudMinWidth then
        GUI:SetSearchSection("HUD Minimum Width")
        local sectionLabel = GUI:CreateLabel(tabContent, "HUD Minimum Width (When Anchored)", 12, C.textLight or C.text)
        sectionLabel:SetPoint("TOPLEFT", PADDING, y)
        y = y - 22

        local minWidthToggle = GUI:CreateFormToggle(
            tabContent,
            "Enable Minimum Width for CDM-Anchored HUD",
            "enabled",
            hudMinWidth,
            RefreshHUDWidth
        )
        minWidthToggle:SetPoint("TOPLEFT", PADDING + 10, y)
        minWidthToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local minWidthSlider = GUI:CreateFormSlider(
            tabContent,
            "Minimum Width",
            HUD_MIN_WIDTH_MIN,
            HUD_MIN_WIDTH_MAX,
            1,
            "width",
            hudMinWidth,
            RefreshHUDWidth
        )
        minWidthSlider:SetPoint("TOPLEFT", PADDING + 10, y)
        minWidthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local minWidthHint = GUI:CreateLabel(
            tabContent,
            ("Only affects player/target when anchored to CDM. Keeps HUD spacing from collapsing. Default: %d."):format(HUD_MIN_WIDTH_DEFAULT),
            11,
            C.textMuted or C.text
        )
        minWidthHint:SetPoint("TOPLEFT", PADDING + 10, y)
        minWidthHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        minWidthHint:SetJustifyH("LEFT")
        y = y - 24
    end

    local frames = {
        { key = "cdmEssential", name = "CDM Essential Viewer" },
        { key = "cdmUtility",   name = "CDM Utility Viewer" },
        { key = "buffIcon",     name = "CDM Buff Icons" },
        { key = "buffBar",      name = "CDM Buff Bars" },
    }
    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

local function BuildResourceBarsTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 2, subTabName = "Resource Bars"})
    local y = -10
    local frames = {
        { key = "primaryPower",   name = "Primary Power Bar",   autoWidth = true },
        { key = "secondaryPower", name = "Secondary Power Bar", autoWidth = true },
    }
    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

local function BuildUnitFramesTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 3, subTabName = "Unit Frames"})
    local y = -10
    local frames = {
        { key = "playerFrame", name = "Player Frame",    autoWidth = true, autoHeight = true },
        { key = "targetFrame", name = "Target Frame",    autoWidth = true, autoHeight = true },
        { key = "totFrame",    name = "Target of Target", autoWidth = true },
        { key = "focusFrame",  name = "Focus Frame",     autoWidth = true },
        { key = "petFrame",    name = "Pet Frame",       autoWidth = true },
        { key = "bossFrames",  name = "Boss Frames",     autoWidth = true },
    }

    -- DandersFrames entries (conditional)
    local dandersAvailable = ns.QUI_DandersFrames and ns.QUI_DandersFrames:IsAvailable()
    if dandersAvailable then
        table.insert(frames, { key = "dandersParty", name = "DandersFrames Party" })
        table.insert(frames, { key = "dandersRaid",  name = "DandersFrames Raid" })
    end

    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

local function BuildCastbarsTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 4, subTabName = "Castbars"})
    local y = -10
    local PAD = PADDING
    local castbarUnits = { "player", "target", "focus" }
    local previewActive = false

    -- Preview All Castbars toggle
    GUI:SetSearchSection("Castbar Preview")
    local castbarKeys = { "playerCastbar", "targetCastbar", "focusCastbar" }
    local previewToggle = GUI:CreateFormToggle(tabContent, "Preview All Castbars", nil, nil, function(val)
        previewActive = val
        for _, unitKey in ipairs(castbarUnits) do
            if val then
                if _G.QUI_ShowCastbarPreview then _G.QUI_ShowCastbarPreview(unitKey) end
            else
                if _G.QUI_HideCastbarPreview then _G.QUI_HideCastbarPreview(unitKey) end
            end
        end
        -- Reapply castbar anchoring overrides after preview refresh repositions frames
        C_Timer.After(0.2, function()
            for _, key in ipairs(castbarKeys) do
                if _G.QUI_ApplyFrameAnchor then
                    _G.QUI_ApplyFrameAnchor(key)
                end
            end
        end)
    end)
    previewToggle:SetPoint("TOPLEFT", PAD, y)
    previewToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW - 8

    local frames = {
        { key = "playerCastbar", name = "Player Castbar", autoWidth = true },
        { key = "targetCastbar", name = "Target Castbar", autoWidth = true },
        { key = "focusCastbar",  name = "Focus Castbar",  autoWidth = true },
    }
    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

local function BuildActionBarsTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 5, subTabName = "Action Bars"})
    local y = -10
    local frames = {
        { key = "bar1",      name = "Action Bar 1 (Main)" },
        { key = "bar2",      name = "Action Bar 2" },
        { key = "bar3",      name = "Action Bar 3" },
        { key = "bar4",      name = "Action Bar 4" },
        { key = "bar5",      name = "Action Bar 5" },
        { key = "bar6",      name = "Action Bar 6" },
        { key = "bar7",      name = "Action Bar 7" },
        { key = "bar8",      name = "Action Bar 8" },
        { key = "petBar",    name = "Pet Action Bar" },
        { key = "stanceBar", name = "Stance Bar" },
        { key = "microMenu", name = "Micro Menu" },
        { key = "bagBar",    name = "Bag Bar" },
        { key = "extraActionButton", name = "Extra Action Button" },
        { key = "zoneAbility", name = "Zone Ability Button" },
    }
    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

local function BuildDisplayTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 6, subTabName = "Display"})
    local y = -10
    local frames = {
        { key = "minimap",          name = "Minimap" },
        { key = "objectiveTracker", name = "Objective Tracker" },
        { key = "buffFrame",        name = "Buff Frame" },
        { key = "debuffFrame",      name = "Debuff Frame" },
    }

    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

local function BuildQoLTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 7, subTabName = "QoL"})
    local y = -10
    local frames = {
        { key = "brezCounter", name = "Brez Counter" },
        { key = "combatTimer", name = "Combat Timer" },
        { key = "skyriding", name = "Skyriding" },
        { key = "petWarning", name = "Pet Warning" },
        { key = "focusCastAlert", name = "Focus Cast Alert" },
        { key = "missingRaidBuffs", name = "Missing Raid Buffs" },
        { key = "mplusTimer", name = "M+ Timer" },
    }
    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

--------------------------------------------------------------------------------
-- FRAME ANCHORING PAGE (coordinator with sub-tabs)
--------------------------------------------------------------------------------
local function CreateFrameAnchoringPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    GUI:CreateSubTabs(content, {
        { name = "CDM",           builder = BuildCDMTab },
        { name = "Resource Bars", builder = BuildResourceBarsTab },
        { name = "Unit Frames",   builder = BuildUnitFramesTab },
        { name = "Castbars",      builder = BuildCastbarsTab },
        { name = "Action Bars",   builder = BuildActionBarsTab },
        { name = "Display",       builder = BuildDisplayTab },
        { name = "QoL",           builder = BuildQoLTab },
        { name = "3rd Party Addons", builder = function(tabContent)
            if ns.QUI_ThirdPartyAnchoringOptions and ns.QUI_ThirdPartyAnchoringOptions.BuildThirdPartyTab then
                ns.QUI_ThirdPartyAnchoringOptions.BuildThirdPartyTab(tabContent)
            else
                local label = GUI:CreateLabel(tabContent, "3rd Party Addons options failed to load. Please reload UI.", 12, {1, 0.3, 0.3, 1})
                label:SetPoint("TOPLEFT", PADDING, -10)
                tabContent:SetHeight(120)
            end
        end },
    })

    content:SetHeight(600)

    return scroll
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_FrameAnchoringOptions = {
    CreateFrameAnchoringPage = CreateFrameAnchoringPage
}
