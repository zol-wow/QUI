--[[
    QUI Options - HUD Visibility Tab
    BuildHUDVisibilityTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildHUDVisibilityTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    local function BuildSearchInfo(sectionKeyword, ...)
        local keywords = {"hud", "visibility", sectionKeyword}
        local extra = {...}
        for i = 1, #extra do
            keywords[#keywords + 1] = extra[i]
        end
        return {keywords = keywords}
    end

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 2, subTabName = "HUD Visibility"})

    -- Ensure cdmVisibility settings exist
    if not db.cdmVisibility then db.cdmVisibility = {} end
    local cdmVis = db.cdmVisibility
    if cdmVis.showAlways == nil then cdmVis.showAlways = true end
    if cdmVis.showWhenTargetExists == nil then cdmVis.showWhenTargetExists = false end
    if cdmVis.showInCombat == nil then cdmVis.showInCombat = false end
    if cdmVis.showInGroup == nil then cdmVis.showInGroup = false end
    if cdmVis.showInInstance == nil then cdmVis.showInInstance = false end
    if cdmVis.showOnMouseover == nil then cdmVis.showOnMouseover = false end
    if cdmVis.fadeDuration == nil then cdmVis.fadeDuration = 0.2 end
    if cdmVis.fadeOutAlpha == nil then cdmVis.fadeOutAlpha = 0 end

    local function RefreshCDMVisibility()
        if _G.QUI_RefreshCDMVisibility then
            _G.QUI_RefreshCDMVisibility()
        end
    end

    -- CDM Visibility Section
    local cdmHeader = GUI:CreateSectionHeader(tabContent, "CDM Visibility")
    cdmHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - cdmHeader.gap

    local cdmTip = GUI:CreateLabel(tabContent,
        "Show CDM viewers and power bars. Uncheck 'Show Always' to use conditional visibility.",
        11, C.textMuted)
    cdmTip:SetPoint("TOPLEFT", PADDING, y)
    cdmTip:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    cdmTip:SetJustifyH("LEFT")
    y = y - 28

    local cdmConditionChecks = {}

    local function UpdateCDMConditionState()
        local enabled = not cdmVis.showAlways
        for _, check in ipairs(cdmConditionChecks) do
            if enabled then
                check:SetAlpha(1)
                if check.track then check.track:EnableMouse(true) end
            else
                check:SetAlpha(0.4)
                if check.track then check.track:EnableMouse(false) end
            end
        end
    end

    local cdmAlwaysCheck = GUI:CreateFormCheckbox(tabContent, "Show Always", "showAlways", cdmVis, function()
        RefreshCDMVisibility()
        UpdateCDMConditionState()
    end)
    cdmAlwaysCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmAlwaysCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cdmTargetCheck = GUI:CreateFormCheckbox(tabContent, "Show When Target Exists", "showWhenTargetExists", cdmVis, RefreshCDMVisibility)
    cdmTargetCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmTargetCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(cdmConditionChecks, cdmTargetCheck)
    y = y - FORM_ROW

    local cdmCombatCheck = GUI:CreateFormCheckbox(tabContent, "Show In Combat", "showInCombat", cdmVis, RefreshCDMVisibility)
    cdmCombatCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmCombatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(cdmConditionChecks, cdmCombatCheck)
    y = y - FORM_ROW

    local cdmGroupCheck = GUI:CreateFormCheckbox(tabContent, "Show In Group", "showInGroup", cdmVis, RefreshCDMVisibility)
    cdmGroupCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmGroupCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(cdmConditionChecks, cdmGroupCheck)
    y = y - FORM_ROW

    local cdmInstanceCheck = GUI:CreateFormCheckbox(tabContent, "Show In Instance", "showInInstance", cdmVis, RefreshCDMVisibility)
    cdmInstanceCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmInstanceCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(cdmConditionChecks, cdmInstanceCheck)
    y = y - FORM_ROW

    local cdmMouseoverCheck = GUI:CreateFormCheckbox(tabContent, "Show On Mouseover", "showOnMouseover", cdmVis, function()
        RefreshCDMVisibility()
        if _G.QUI_RefreshCDMMouseover then
            _G.QUI_RefreshCDMMouseover()
        end
    end)
    cdmMouseoverCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmMouseoverCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(cdmConditionChecks, cdmMouseoverCheck)
    y = y - FORM_ROW

    UpdateCDMConditionState()

    local cdmFadeSlider = GUI:CreateFormSlider(tabContent, "Fade Duration (sec)", 0.1, 1.0, 0.05, "fadeDuration", cdmVis, RefreshCDMVisibility)
    cdmFadeSlider:SetPoint("TOPLEFT", PADDING, y)
    cdmFadeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cdmFadeAlpha = GUI:CreateFormSlider(tabContent, "Fade Out Opacity", 0, 1.0, 0.05, "fadeOutAlpha", cdmVis, RefreshCDMVisibility)
    cdmFadeAlpha:SetPoint("TOPLEFT", PADDING, y)
    cdmFadeAlpha:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    if cdmVis.hideWhenMounted == nil then cdmVis.hideWhenMounted = false end
    local cdmMountedCheck = GUI:CreateFormCheckbox(tabContent, "Hide When Mounted", "hideWhenMounted", cdmVis, RefreshCDMVisibility)
    cdmMountedCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmMountedCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cdmMountedHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while mounted regardless of the settings above.",
        11, C.textMuted)
    cdmMountedHint:SetPoint("TOPLEFT", PADDING, y)
    cdmMountedHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    cdmMountedHint:SetJustifyH("LEFT")
    y = y - 20

    if cdmVis.hideWhenFlying == nil then cdmVis.hideWhenFlying = false end
    local cdmFlyingCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Hide When Flying",
        "hideWhenFlying",
        cdmVis,
        RefreshCDMVisibility,
        BuildSearchInfo("cdm", "flying", "flight", "airborne")
    )
    cdmFlyingCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmFlyingCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cdmFlyingHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while flying regardless of the settings above.",
        11, C.textMuted)
    cdmFlyingHint:SetPoint("TOPLEFT", PADDING, y)
    cdmFlyingHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    cdmFlyingHint:SetJustifyH("LEFT")
    y = y - 20

    if cdmVis.hideWhenSkyriding == nil then cdmVis.hideWhenSkyriding = false end
    local cdmSkyridingCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Hide When Skyriding",
        "hideWhenSkyriding",
        cdmVis,
        RefreshCDMVisibility,
        BuildSearchInfo("cdm", "skyriding", "dragonriding", "dynamic flight", "gliding")
    )
    cdmSkyridingCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmSkyridingCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cdmSkyridingHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while actively skyriding.",
        11, C.textMuted)
    cdmSkyridingHint:SetPoint("TOPLEFT", PADDING, y)
    cdmSkyridingHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    cdmSkyridingHint:SetJustifyH("LEFT")
    y = y - 20

    if cdmVis.dontHideInDungeonsRaids == nil then cdmVis.dontHideInDungeonsRaids = false end
    local cdmDungeonOverrideCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Don't Hide in Dungeons/Raids",
        "dontHideInDungeonsRaids",
        cdmVis,
        RefreshCDMVisibility,
        BuildSearchInfo("cdm", "dungeon", "dungeons", "raid", "raids", "instance", "instances", "mythic", "mythic+", "m+")
    )
    cdmDungeonOverrideCheck:SetPoint("TOPLEFT", PADDING, y)
    cdmDungeonOverrideCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cdmDungeonOverrideHint = GUI:CreateLabel(tabContent,
        "When enabled, mounted/flying/skyriding hide rules are ignored in dungeon and raid instances.",
        11, C.textMuted)
    cdmDungeonOverrideHint:SetPoint("TOPLEFT", PADDING, y)
    cdmDungeonOverrideHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    cdmDungeonOverrideHint:SetJustifyH("LEFT")
    y = y - 20

    y = y - 10

    -- Unitframes Visibility Section
    if not db.unitframesVisibility then db.unitframesVisibility = {} end
    local ufVis = db.unitframesVisibility
    if ufVis.showAlways == nil then ufVis.showAlways = true end
    if ufVis.showWhenTargetExists == nil then ufVis.showWhenTargetExists = false end
    if ufVis.showInCombat == nil then ufVis.showInCombat = false end
    if ufVis.showInGroup == nil then ufVis.showInGroup = false end
    if ufVis.showInInstance == nil then ufVis.showInInstance = false end
    if ufVis.showOnMouseover == nil then ufVis.showOnMouseover = false end
    if ufVis.fadeDuration == nil then ufVis.fadeDuration = 0.2 end
    if ufVis.fadeOutAlpha == nil then ufVis.fadeOutAlpha = 0 end

    local function RefreshUnitframesVisibility()
        if _G.QUI_RefreshUnitframesVisibility then
            _G.QUI_RefreshUnitframesVisibility()
        end
    end

    local ufHeader = GUI:CreateSectionHeader(tabContent, "Unitframes Visibility")
    ufHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - ufHeader.gap

    local ufTip = GUI:CreateLabel(tabContent,
        "Show unit frames. Uncheck 'Show Always' to use conditional visibility.",
        11, C.textMuted)
    ufTip:SetPoint("TOPLEFT", PADDING, y)
    ufTip:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ufTip:SetJustifyH("LEFT")
    y = y - 28

    local ufConditionChecks = {}

    local function UpdateUFConditionState()
        local enabled = not ufVis.showAlways
        for _, check in ipairs(ufConditionChecks) do
            if enabled then
                check:SetAlpha(1)
                if check.track then check.track:EnableMouse(true) end
            else
                check:SetAlpha(0.4)
                if check.track then check.track:EnableMouse(false) end
            end
        end
    end

    local ufAlwaysCheck = GUI:CreateFormCheckbox(tabContent, "Show Always", "showAlways", ufVis, function()
        RefreshUnitframesVisibility()
        UpdateUFConditionState()
    end)
    ufAlwaysCheck:SetPoint("TOPLEFT", PADDING, y)
    ufAlwaysCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ufTargetCheck = GUI:CreateFormCheckbox(tabContent, "Show When Target Exists", "showWhenTargetExists", ufVis, RefreshUnitframesVisibility)
    ufTargetCheck:SetPoint("TOPLEFT", PADDING, y)
    ufTargetCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ufConditionChecks, ufTargetCheck)
    y = y - FORM_ROW

    local ufCombatCheck = GUI:CreateFormCheckbox(tabContent, "Show In Combat", "showInCombat", ufVis, RefreshUnitframesVisibility)
    ufCombatCheck:SetPoint("TOPLEFT", PADDING, y)
    ufCombatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ufConditionChecks, ufCombatCheck)
    y = y - FORM_ROW

    local ufGroupCheck = GUI:CreateFormCheckbox(tabContent, "Show In Group", "showInGroup", ufVis, RefreshUnitframesVisibility)
    ufGroupCheck:SetPoint("TOPLEFT", PADDING, y)
    ufGroupCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ufConditionChecks, ufGroupCheck)
    y = y - FORM_ROW

    local ufInstanceCheck = GUI:CreateFormCheckbox(tabContent, "Show In Instance", "showInInstance", ufVis, RefreshUnitframesVisibility)
    ufInstanceCheck:SetPoint("TOPLEFT", PADDING, y)
    ufInstanceCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ufConditionChecks, ufInstanceCheck)
    y = y - FORM_ROW

    local ufMouseoverCheck = GUI:CreateFormCheckbox(tabContent, "Show On Mouseover", "showOnMouseover", ufVis, function()
        RefreshUnitframesVisibility()
        if _G.QUI_RefreshUnitframesMouseover then
            _G.QUI_RefreshUnitframesMouseover()
        end
    end)
    ufMouseoverCheck:SetPoint("TOPLEFT", PADDING, y)
    ufMouseoverCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ufConditionChecks, ufMouseoverCheck)
    y = y - FORM_ROW

    UpdateUFConditionState()

    local ufFadeSlider = GUI:CreateFormSlider(tabContent, "Fade Duration (sec)", 0.1, 1.0, 0.05, "fadeDuration", ufVis, RefreshUnitframesVisibility)
    ufFadeSlider:SetPoint("TOPLEFT", PADDING, y)
    ufFadeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ufFadeAlpha = GUI:CreateFormSlider(tabContent, "Fade Out Opacity", 0, 1.0, 0.05, "fadeOutAlpha", ufVis, RefreshUnitframesVisibility)
    ufFadeAlpha:SetPoint("TOPLEFT", PADDING, y)
    ufFadeAlpha:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    if ufVis.alwaysShowCastbars == nil then ufVis.alwaysShowCastbars = false end
    local ufCastbarsCheck = GUI:CreateFormCheckbox(tabContent, "Always Show Castbars", "alwaysShowCastbars", ufVis, RefreshUnitframesVisibility)
    ufCastbarsCheck:SetPoint("TOPLEFT", PADDING, y)
    ufCastbarsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ufConditionChecks, ufCastbarsCheck)
    y = y - FORM_ROW

    if ufVis.hideWhenMounted == nil then ufVis.hideWhenMounted = false end
    local ufMountedCheck = GUI:CreateFormCheckbox(tabContent, "Hide When Mounted", "hideWhenMounted", ufVis, RefreshUnitframesVisibility)
    ufMountedCheck:SetPoint("TOPLEFT", PADDING, y)
    ufMountedCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ufMountedHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while mounted regardless of the settings above.",
        11, C.textMuted)
    ufMountedHint:SetPoint("TOPLEFT", PADDING, y)
    ufMountedHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ufMountedHint:SetJustifyH("LEFT")
    y = y - 20

    if ufVis.hideWhenFlying == nil then ufVis.hideWhenFlying = false end
    local ufFlyingCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Hide When Flying",
        "hideWhenFlying",
        ufVis,
        RefreshUnitframesVisibility,
        BuildSearchInfo("unitframes", "unit frames", "flying", "flight", "airborne")
    )
    ufFlyingCheck:SetPoint("TOPLEFT", PADDING, y)
    ufFlyingCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ufFlyingHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while flying regardless of the settings above.",
        11, C.textMuted)
    ufFlyingHint:SetPoint("TOPLEFT", PADDING, y)
    ufFlyingHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ufFlyingHint:SetJustifyH("LEFT")
    y = y - 20

    if ufVis.hideWhenSkyriding == nil then ufVis.hideWhenSkyriding = false end
    local ufSkyridingCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Hide When Skyriding",
        "hideWhenSkyriding",
        ufVis,
        RefreshUnitframesVisibility,
        BuildSearchInfo("unitframes", "unit frames", "skyriding", "dragonriding", "dynamic flight", "gliding")
    )
    ufSkyridingCheck:SetPoint("TOPLEFT", PADDING, y)
    ufSkyridingCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ufSkyridingHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while actively skyriding.",
        11, C.textMuted)
    ufSkyridingHint:SetPoint("TOPLEFT", PADDING, y)
    ufSkyridingHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ufSkyridingHint:SetJustifyH("LEFT")
    y = y - 20

    if ufVis.dontHideInDungeonsRaids == nil then ufVis.dontHideInDungeonsRaids = false end
    local ufDungeonOverrideCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Don't Hide in Dungeons/Raids",
        "dontHideInDungeonsRaids",
        ufVis,
        RefreshUnitframesVisibility,
        BuildSearchInfo("unitframes", "unit frames", "dungeon", "dungeons", "raid", "raids", "instance", "instances", "mythic", "mythic+", "m+")
    )
    ufDungeonOverrideCheck:SetPoint("TOPLEFT", PADDING, y)
    ufDungeonOverrideCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ufDungeonOverrideHint = GUI:CreateLabel(tabContent,
        "When enabled, mounted/flying/skyriding hide rules are ignored in dungeon and raid instances.",
        11, C.textMuted)
    ufDungeonOverrideHint:SetPoint("TOPLEFT", PADDING, y)
    ufDungeonOverrideHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ufDungeonOverrideHint:SetJustifyH("LEFT")
    y = y - 20

    -- =====================================================
    -- CUSTOM TRACKERS VISIBILITY SECTION
    -- =====================================================
    if not db.customTrackersVisibility then db.customTrackersVisibility = {} end
    local ctVis = db.customTrackersVisibility
    if ctVis.showAlways == nil then ctVis.showAlways = true end
    if ctVis.showWhenTargetExists == nil then ctVis.showWhenTargetExists = false end
    if ctVis.showInCombat == nil then ctVis.showInCombat = false end
    if ctVis.showInGroup == nil then ctVis.showInGroup = false end
    if ctVis.showInInstance == nil then ctVis.showInInstance = false end
    if ctVis.showOnMouseover == nil then ctVis.showOnMouseover = false end
    if ctVis.fadeDuration == nil then ctVis.fadeDuration = 0.2 end
    if ctVis.fadeOutAlpha == nil then ctVis.fadeOutAlpha = 0 end

    local function RefreshCustomTrackersVisibility()
        if _G.QUI_RefreshCustomTrackersVisibility then
            _G.QUI_RefreshCustomTrackersVisibility()
        end
    end

    local ctHeader = GUI:CreateSectionHeader(tabContent, "Custom Items/Spells Bars")
    ctHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - ctHeader.gap

    local ctTip = GUI:CreateLabel(tabContent,
        "Show custom tracker bars. Uncheck 'Show Always' to use conditional visibility.",
        11, C.textMuted)
    ctTip:SetPoint("TOPLEFT", PADDING, y)
    ctTip:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ctTip:SetJustifyH("LEFT")
    y = y - 28

    local ctConditionChecks = {}

    local function UpdateCTConditionState()
        local enabled = not ctVis.showAlways
        for _, check in ipairs(ctConditionChecks) do
            if enabled then
                check:SetAlpha(1)
                if check.track then check.track:EnableMouse(true) end
            else
                check:SetAlpha(0.4)
                if check.track then check.track:EnableMouse(false) end
            end
        end
    end

    local ctAlwaysCheck = GUI:CreateFormCheckbox(tabContent, "Show Always", "showAlways", ctVis, function()
        RefreshCustomTrackersVisibility()
        UpdateCTConditionState()
    end)
    ctAlwaysCheck:SetPoint("TOPLEFT", PADDING, y)
    ctAlwaysCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ctTargetCheck = GUI:CreateFormCheckbox(tabContent, "Show When Target Exists", "showWhenTargetExists", ctVis, RefreshCustomTrackersVisibility)
    ctTargetCheck:SetPoint("TOPLEFT", PADDING, y)
    ctTargetCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ctConditionChecks, ctTargetCheck)
    y = y - FORM_ROW

    local ctCombatCheck = GUI:CreateFormCheckbox(tabContent, "Show In Combat", "showInCombat", ctVis, RefreshCustomTrackersVisibility)
    ctCombatCheck:SetPoint("TOPLEFT", PADDING, y)
    ctCombatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ctConditionChecks, ctCombatCheck)
    y = y - FORM_ROW

    local ctGroupCheck = GUI:CreateFormCheckbox(tabContent, "Show In Group", "showInGroup", ctVis, RefreshCustomTrackersVisibility)
    ctGroupCheck:SetPoint("TOPLEFT", PADDING, y)
    ctGroupCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ctConditionChecks, ctGroupCheck)
    y = y - FORM_ROW

    local ctInstanceCheck = GUI:CreateFormCheckbox(tabContent, "Show In Instance", "showInInstance", ctVis, RefreshCustomTrackersVisibility)
    ctInstanceCheck:SetPoint("TOPLEFT", PADDING, y)
    ctInstanceCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ctConditionChecks, ctInstanceCheck)
    y = y - FORM_ROW

    local ctMouseoverCheck = GUI:CreateFormCheckbox(tabContent, "Show On Mouseover", "showOnMouseover", ctVis, function()
        RefreshCustomTrackersVisibility()
        if _G.QUI_RefreshCustomTrackersMouseover then
            _G.QUI_RefreshCustomTrackersMouseover()
        end
    end)
    ctMouseoverCheck:SetPoint("TOPLEFT", PADDING, y)
    ctMouseoverCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    table.insert(ctConditionChecks, ctMouseoverCheck)
    y = y - FORM_ROW

    local ctFadeSlider = GUI:CreateFormSlider(tabContent, "Fade Duration (sec)", 0.1, 1.0, 0.05, "fadeDuration", ctVis, RefreshCustomTrackersVisibility)
    ctFadeSlider:SetPoint("TOPLEFT", PADDING, y)
    ctFadeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ctFadeAlpha = GUI:CreateFormSlider(tabContent, "Fade Out Opacity", 0, 1.0, 0.05, "fadeOutAlpha", ctVis, RefreshCustomTrackersVisibility)
    ctFadeAlpha:SetPoint("TOPLEFT", PADDING, y)
    ctFadeAlpha:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    if ctVis.hideWhenMounted == nil then ctVis.hideWhenMounted = false end
    local ctMountedCheck = GUI:CreateFormCheckbox(tabContent, "Hide When Mounted", "hideWhenMounted", ctVis, RefreshCustomTrackersVisibility)
    ctMountedCheck:SetPoint("TOPLEFT", PADDING, y)
    ctMountedCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ctMountedHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while mounted regardless of the settings above.",
        11, C.textMuted)
    ctMountedHint:SetPoint("TOPLEFT", PADDING, y)
    ctMountedHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ctMountedHint:SetJustifyH("LEFT")
    y = y - 20

    if ctVis.hideWhenFlying == nil then ctVis.hideWhenFlying = false end
    local ctFlyingCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Hide When Flying",
        "hideWhenFlying",
        ctVis,
        RefreshCustomTrackersVisibility,
        BuildSearchInfo("custom trackers", "trackers", "flying", "flight", "airborne")
    )
    ctFlyingCheck:SetPoint("TOPLEFT", PADDING, y)
    ctFlyingCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ctFlyingHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while flying regardless of the settings above.",
        11, C.textMuted)
    ctFlyingHint:SetPoint("TOPLEFT", PADDING, y)
    ctFlyingHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ctFlyingHint:SetJustifyH("LEFT")
    y = y - 20

    if ctVis.hideWhenSkyriding == nil then ctVis.hideWhenSkyriding = false end
    local ctSkyridingCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Hide When Skyriding",
        "hideWhenSkyriding",
        ctVis,
        RefreshCustomTrackersVisibility,
        BuildSearchInfo("custom trackers", "trackers", "skyriding", "dragonriding", "dynamic flight", "gliding")
    )
    ctSkyridingCheck:SetPoint("TOPLEFT", PADDING, y)
    ctSkyridingCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ctSkyridingHint = GUI:CreateLabel(tabContent,
        "When enabled, elements hide while actively skyriding.",
        11, C.textMuted)
    ctSkyridingHint:SetPoint("TOPLEFT", PADDING, y)
    ctSkyridingHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ctSkyridingHint:SetJustifyH("LEFT")
    y = y - 20

    if ctVis.dontHideInDungeonsRaids == nil then ctVis.dontHideInDungeonsRaids = false end
    local ctDungeonOverrideCheck = GUI:CreateFormCheckbox(
        tabContent,
        "Don't Hide in Dungeons/Raids",
        "dontHideInDungeonsRaids",
        ctVis,
        RefreshCustomTrackersVisibility,
        BuildSearchInfo("custom trackers", "trackers", "dungeon", "dungeons", "raid", "raids", "instance", "instances", "mythic", "mythic+", "m+")
    )
    ctDungeonOverrideCheck:SetPoint("TOPLEFT", PADDING, y)
    ctDungeonOverrideCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ctDungeonOverrideHint = GUI:CreateLabel(tabContent,
        "When enabled, mounted/flying/skyriding hide rules are ignored in dungeon and raid instances.",
        11, C.textMuted)
    ctDungeonOverrideHint:SetPoint("TOPLEFT", PADDING, y)
    ctDungeonOverrideHint:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    ctDungeonOverrideHint:SetJustifyH("LEFT")
    y = y - 20

    UpdateCTConditionState()

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_HUDVisibilityOptions = {
    BuildHUDVisibilityTab = BuildHUDVisibilityTab
}
