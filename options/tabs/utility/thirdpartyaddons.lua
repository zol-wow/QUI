--[[
    QUI Options - 3rd Party Addons Anchoring
    Anchoring controls for BigWigs and DandersFrames integrations.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

local PADDING = Shared.PADDING
local GetCore = ns.Helpers.GetCore

local ANCHOR_POINTS = {
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

local FORM_ROW = 32

local function BuildAnchorSection(content, label, cfg, y, anchorOptions, onChange)
    local PAD = PADDING

    if not cfg then
        return y
    end

    local header = GUI:CreateSectionHeader(content, label)
    header:SetPoint("TOPLEFT", PAD, y)
    y = y - header.gap

    local enableCheck = GUI:CreateFormCheckbox(content, "Enable Anchoring", "enabled", cfg, onChange)
    enableCheck:SetPoint("TOPLEFT", PAD, y)
    enableCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local anchorDropdown = GUI:CreateFormDropdown(content, "Anchor To", anchorOptions, "anchorTo", cfg, onChange)
    anchorDropdown:SetPoint("TOPLEFT", PAD, y)
    anchorDropdown:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local sourceDropdown = GUI:CreateFormDropdown(content, "Container Point", ANCHOR_POINTS, "sourcePoint", cfg, onChange)
    sourceDropdown:SetPoint("TOPLEFT", PAD, y)
    sourceDropdown:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local targetDropdown = GUI:CreateFormDropdown(content, "Target Point", ANCHOR_POINTS, "targetPoint", cfg, onChange)
    targetDropdown:SetPoint("TOPLEFT", PAD, y)
    targetDropdown:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local xSlider = GUI:CreateFormSlider(content, "X Offset", -200, 200, 1, "offsetX", cfg, onChange)
    xSlider:SetPoint("TOPLEFT", PAD, y)
    xSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local ySlider = GUI:CreateFormSlider(content, "Y Offset", -200, 200, 1, "offsetY", cfg, onChange)
    ySlider:SetPoint("TOPLEFT", PAD, y)
    ySlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW - 10

    return y
end

local function BuildBigWigsSection(tabContent, y)
    local PAD = PADDING

    local header = GUI:CreateSectionHeader(tabContent, "BigWigs")
    header:SetPoint("TOPLEFT", PAD, y)
    y = y - header.gap

    if not (ns.QUI_BigWigs and ns.QUI_BigWigs:IsAvailable()) then
        local info = GUI:CreateLabel(tabContent, "BigWigs not detected. Install and enable BigWigs to use these anchors.", 11, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, y)
        info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        info:SetJustifyH("LEFT")
        return y - 26
    end

    local core = GetCore()
    local db = core and core.db and core.db.profile and core.db.profile.bigWigs
    if not db then
        local errorLabel = GUI:CreateLabel(tabContent, "BigWigs anchor database not loaded. Please reload UI.", 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, y)
        return y - 24
    end

    local info = GUI:CreateLabel(tabContent, "Anchor BigWigs bar groups to QUI elements. This writes to BigWigs Bars custom anchor points.", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    local anchorOptions = ns.QUI_BigWigs:BuildAnchorOptions()
    local keys = {
        {key = "normal", label = "Normal Bars"},
        {key = "emphasized", label = "Emphasized Bars"},
    }

    for _, entry in ipairs(keys) do
        local cfg = db[entry.key]
        y = BuildAnchorSection(tabContent, entry.label, cfg, y, anchorOptions, function()
            ns.QUI_BigWigs:ApplyPosition(entry.key)
        end)
    end

    return y
end

local function BuildDandersSection(tabContent, y)
    local PAD = PADDING

    local header = GUI:CreateSectionHeader(tabContent, "DandersFrames")
    header:SetPoint("TOPLEFT", PAD, y)
    y = y - header.gap

    if not (ns.QUI_DandersFrames and ns.QUI_DandersFrames:IsAvailable()) then
        local info = GUI:CreateLabel(tabContent, "DandersFrames not detected. Install and enable DandersFrames to use these anchors.", 11, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, y)
        info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        info:SetJustifyH("LEFT")
        return y - 26
    end

    local core = GetCore()
    local db = core and core.db and core.db.profile and core.db.profile.dandersFrames
    if not db then
        local errorLabel = GUI:CreateLabel(tabContent, "DandersFrames anchor database not loaded. Please reload UI.", 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, y)
        return y - 24
    end

    local info = GUI:CreateLabel(tabContent, "Anchor DandersFrames containers to QUI elements. When enabled, QUI controls container placement.", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    local anchorOptions = ns.QUI_DandersFrames:BuildAnchorOptions()
    local keys = {
        {key = "party", label = "Party Frames"},
        {key = "raid", label = "Raid Frames"},
        {key = "pinned1", label = "Pinned Set 1"},
        {key = "pinned2", label = "Pinned Set 2"},
    }

    for _, entry in ipairs(keys) do
        local cfg = db[entry.key]
        y = BuildAnchorSection(tabContent, entry.label, cfg, y, anchorOptions, function()
            ns.QUI_DandersFrames:ApplyPosition(entry.key)
        end)
    end

    return y
end

local function BuildThirdPartyTab(tabContent)
    local y = -10
    local PAD = PADDING

    GUI:SetSearchContext({tabIndex = 3, tabName = "Anchoring & Layout", subTabIndex = 8, subTabName = "3rd Party Addons"})

    local info = GUI:CreateLabel(tabContent, "Configure QUI-driven anchoring integrations for supported external addons.", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 26

    y = BuildBigWigsSection(tabContent, y)
    y = y - 4
    y = BuildDandersSection(tabContent, y)

    tabContent:SetHeight(math.abs(y) + 30)
end

ns.QUI_ThirdPartyAnchoringOptions = {
    BuildThirdPartyTab = BuildThirdPartyTab
}
