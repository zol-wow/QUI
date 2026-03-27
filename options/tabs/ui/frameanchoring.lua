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

---------------------------------------------------------------------------
-- DATABASE HELPERS (delegate to shared infrastructure in utility/anchoring.lua)
---------------------------------------------------------------------------
local function GetAnchoringDB()
    local AnchorOpts = GetAnchorOpts()
    if AnchorOpts and AnchorOpts.GetAnchoringDB then
        return AnchorOpts:GetAnchoringDB()
    end
    -- Fallback if utility module not loaded yet
    local core = GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    if type(db.frameAnchoring) ~= "table" then
        db.frameAnchoring = {}
    end
    return db.frameAnchoring
end

local function GetFrameDB(key)
    local AnchorOpts = GetAnchorOpts()
    if AnchorOpts and AnchorOpts.GetFrameDB then
        return AnchorOpts:GetFrameDB(key)
    end
    return nil
end

---------------------------------------------------------------------------
-- SHARED: Build frame entry widgets for a single frame key
-- Delegates to BuildAnchoringSection from utility/anchoring.lua
---------------------------------------------------------------------------
local function BuildFrameEntry(tabContent, frameDef, y)
    local AnchorOpts = GetAnchorOpts()
    if AnchorOpts and AnchorOpts.BuildAnchoringSection then
        local newY = AnchorOpts:BuildAnchoringSection(tabContent, frameDef.key, {
            name = frameDef.name,
            autoWidth = frameDef.autoWidth,
            autoHeight = frameDef.autoHeight,
        }, y)
        return newY
    end

    -- Fallback: just return y if shared builder not available
    return y
end

---------------------------------------------------------------------------
-- TAB BUILDERS (one per category)
---------------------------------------------------------------------------
local function BuildCDMTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Frame Positioning", subTabIndex = 1, subTabName = "CDM"})
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

    -- CDM frames — positioning moved to Edit Mode settings panels.
end

local function BuildResourceBarsTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Frame Positioning", subTabIndex = 2, subTabName = "Resource Bars"})
    local y = -10
    local frames = {
        { key = "primaryPower",   name = "Primary Power Bar",   autoWidth = true },
        { key = "secondaryPower", name = "Secondary Power Bar", autoWidth = true },
    }
    for _, frameDef in ipairs(frames) do
        y = BuildFrameEntry(tabContent, frameDef, y)
    end
end

-- Unit Frames and Castbars sub-tabs removed — anchoring controls are now
-- embedded directly in each frame's own options panel.

local function BuildActionBarsTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Frame Positioning", subTabIndex = 3, subTabName = "Action Bars"})
    -- All action bar positioning moved to Edit Mode settings panels.
end


local function BuildQoLTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Frame Positioning", subTabIndex = 5, subTabName = "QoL"})
    -- All QoL frame positioning moved to Edit Mode settings panels.
end

local function BuildCustomTrackersTab(tabContent)
    GUI:SetSearchContext({tabIndex = 3, tabName = "Frame Positioning", subTabIndex = 6, subTabName = "Custom CDM Bars"})
    local y = -10
    local core = GetCore()
    local db = core and core.db and core.db.profile
    local trackerBars = db and db.customTrackers and db.customTrackers.bars

    if ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAllFrameTargets then
        ns.QUI_Anchoring:RegisterAllFrameTargets()
    end

    GUI:SetSearchSection("Custom CDM Bar Preview")
    local previewState = {
        enabled = _G.QUI_IsAnchoringPreviewAllCustomTrackers and _G.QUI_IsAnchoringPreviewAllCustomTrackers() or false
    }
    local previewToggle = GUI:CreateFormToggle(tabContent, "Preview All Custom CDM Bars", "enabled", previewState, function(val)
        previewState.enabled = val and true or false
        if _G.QUI_SetAnchoringPreviewAllCustomTrackers then
            _G.QUI_SetAnchoringPreviewAllCustomTrackers(previewState.enabled)
        end
        if _G.QUI_ApplyAllFrameAnchors then
            C_Timer.After(0.05, function()
                if _G.QUI_ApplyAllFrameAnchors then
                    _G.QUI_ApplyAllFrameAnchors()
                end
            end)
        end
    end)
    previewToggle:SetPoint("TOPLEFT", PADDING, y)
    previewToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local previewHint = GUI:CreateLabel(
        tabContent,
        "Shows every custom tracker bar at 50% opacity, including bars that are currently disabled.",
        11,
        C.textMuted or C.text
    )
    previewHint:SetPoint("TOPLEFT", PADDING + 10, y)
    previewHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    previewHint:SetJustifyH("LEFT")
    y = y - 26

    -- Auto-disable preview when leaving this sub-tab/page.
    tabContent:HookScript("OnHide", function()
        if _G.QUI_IsAnchoringPreviewAllCustomTrackers and _G.QUI_IsAnchoringPreviewAllCustomTrackers() then
            if _G.QUI_SetAnchoringPreviewAllCustomTrackers then
                _G.QUI_SetAnchoringPreviewAllCustomTrackers(false)
            end
            previewState.enabled = false
            if previewToggle and previewToggle.SetValue then
                previewToggle:SetValue(false, true)
            end
        end
    end)

    if type(trackerBars) ~= "table" or #trackerBars == 0 then
        local empty = GUI:CreateLabel(tabContent, "No custom tracker bars are configured for this profile.", 12, C.textMuted or C.text)
        empty:SetPoint("TOPLEFT", PADDING, y)
        empty:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        empty:SetJustifyH("LEFT")
        tabContent:SetHeight(180)
        return
    end

    local renderedCount = 0
    for i, barConfig in ipairs(trackerBars) do
        local barID = barConfig and barConfig.id
        if type(barID) == "string" and barID ~= "" then
            local displayName = barConfig.name
            if type(displayName) ~= "string" or displayName == "" then
                displayName = ("CDM Bar %d"):format(i)
            end
            y = BuildFrameEntry(tabContent, {
                key = "customTracker:" .. barID,
                name = displayName,
            }, y)
            renderedCount = renderedCount + 1
        end
    end

    if renderedCount == 0 then
        local invalid = GUI:CreateLabel(tabContent, "No valid custom tracker IDs were found in this profile.", 12, C.textMuted or C.text)
        invalid:SetPoint("TOPLEFT", PADDING, y)
        invalid:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        invalid:SetJustifyH("LEFT")
    end
end

--------------------------------------------------------------------------------
-- FRAME ANCHORING PAGE (coordinator with sub-tabs)
--------------------------------------------------------------------------------
local function CreateFrameAnchoringPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    GUI:SetSearchContext({tabIndex = 3, tabName = "Frame Positioning"})

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(content, PADDING)

    -- 3rd Party Addons (default expanded)
    local thirdPartySection = CreateCollapsible("3rd Party Addons", 400, function(body)
        if ns.QUI_ThirdPartyAnchoringOptions and ns.QUI_ThirdPartyAnchoringOptions.BuildThirdPartyTab then
            ns.QUI_ThirdPartyAnchoringOptions.BuildThirdPartyTab(body)
        else
            local label = GUI:CreateLabel(body, "3rd Party Addons options failed to load. Please reload UI.", 12, {1, 0.3, 0.3, 1})
            label:SetPoint("TOPLEFT", 0, -4)
        end
    end)

    -- Expand 3rd Party section by default
    if thirdPartySection and thirdPartySection.SetExpanded and not thirdPartySection._hasStoredState then
        thirdPartySection:SetExpanded(true)
    end

    relayout()

    return scroll
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_FrameAnchoringOptions = {
    CreateFrameAnchoringPage = CreateFrameAnchoringPage
}
