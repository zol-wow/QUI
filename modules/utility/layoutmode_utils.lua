---------------------------------------------------------------------------
-- QUI Layout Mode — Shared Provider Utilities
-- Canonical implementations of CreateCollapsible, StandardRelayout,
-- BuildPositionCollapsible, and PlaceRow used by all settings providers.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = ns.LSM

local Utils = {}
ns.QUI_LayoutMode_Utils = Utils

---------------------------------------------------------------------------
-- SHARED CONSTANTS
---------------------------------------------------------------------------
Utils.ACCENT_R, Utils.ACCENT_G, Utils.ACCENT_B = 0.376, 0.647, 0.980

function Utils:RefreshAccentColor()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        self.ACCENT_R = GUI.Colors.accent[1]
        self.ACCENT_G = GUI.Colors.accent[2]
        self.ACCENT_B = GUI.Colors.accent[3]
    end
end
Utils.HEADER_HEIGHT = 24
Utils.FORM_ROW = 32
Utils.PADDING = 0

---------------------------------------------------------------------------
-- DB / LSM HELPERS
---------------------------------------------------------------------------

function Utils.GetProfileDB()
    local core = Helpers.GetCore()
    return core and core.db and core.db.profile
end

function Utils.GetTextureList()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do
            list[#list + 1] = {value = name, text = name}
        end
        table.sort(list, function(a, b) return a.text < b.text end)
    end
    return list
end

function Utils.GetFontList()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            list[#list + 1] = {value = name, text = name}
        end
        table.sort(list, function(a, b) return a.text < b.text end)
    end
    return list
end

function Utils.GetSoundList()
    local sounds = {{value = "None", text = "None"}}
    if LSM then
        for _, name in ipairs(LSM:List("sound") or {}) do
            if name ~= "None" then
                sounds[#sounds + 1] = {value = name, text = name}
            end
        end
    end
    return sounds
end

---------------------------------------------------------------------------
-- STANDARD RELAYOUT
---------------------------------------------------------------------------

function Utils.StandardRelayout(content, sections)
    local cy = -8
    for _, s in ipairs(sections) do
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", content, "TOPLEFT", Utils.PADDING, cy)
        s:SetPoint("RIGHT", content, "RIGHT", -Utils.PADDING, 0)
        cy = cy - s:GetHeight() - 4
    end
    content:SetHeight(math.abs(cy) + 16)
end

---------------------------------------------------------------------------
-- CREATE COLLAPSIBLE SECTION
---------------------------------------------------------------------------

function Utils.CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
    local ACCENT_R, ACCENT_G, ACCENT_B = Utils.ACCENT_R, Utils.ACCENT_G, Utils.ACCENT_B
    local HEADER_HEIGHT = Utils.HEADER_HEIGHT

    local section = CreateFrame("Frame", nil, parent)
    section:SetHeight(HEADER_HEIGHT)

    local btn = CreateFrame("Button", nil, section)
    btn:SetPoint("TOPLEFT", 0, 0)
    btn:SetPoint("TOPRIGHT", 0, 0)
    btn:SetHeight(HEADER_HEIGHT)

    local chevron = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chevron:SetPoint("LEFT", 2, 0)
    chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    chevron:SetText(">")

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
    label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    label:SetText(title)

    local underline = btn:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    underline:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    body:SetPoint("RIGHT", 0, 0)
    body:SetHeight(contentHeight)
    body:Hide()

    section._expanded = false
    section._contentHeight = contentHeight
    section._body = body
    section._sectionTitle = title  -- used for saving/restoring expanded state

    -- Restore expanded state from previous build if available
    local settings = ns.QUI_LayoutMode_Settings
    local savedStates = settings and settings._expandedStates
    if savedStates and savedStates[title] then
        section._expanded = true
        chevron:SetText("v")
        body:Show()
        section:SetHeight(HEADER_HEIGHT + contentHeight)
    end

    btn:SetScript("OnClick", function()
        section._expanded = not section._expanded
        if section._expanded then
            chevron:SetText("v")
            body:Show()
            section:SetHeight(HEADER_HEIGHT + section._contentHeight)
        else
            chevron:SetText(">")
            body:Hide()
            section:SetHeight(HEADER_HEIGHT)
        end
        relayout()
    end)

    btn:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1, 1)
        chevron:SetTextColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)

    buildFunc(body)
    table.insert(sections, section)
    return section
end

---------------------------------------------------------------------------
-- BUILD POSITION COLLAPSIBLE
---------------------------------------------------------------------------

function Utils.BuildPositionCollapsible(content, frameKey, anchorOpts, sections, relayout)
    local AnchorOpts = ns.QUI_Anchoring_Options
    if not AnchorOpts or not AnchorOpts.BuildAnchoringSection then return end

    local PLACEHOLDER = 6 * Utils.FORM_ROW + 8
    Utils.CreateCollapsible(content, "Position", PLACEHOLDER, function(body)
        local opts = {}
        if anchorOpts then
            for k, v in pairs(anchorOpts) do opts[k] = v end
        end
        opts.noHeader = true
        local finalY = AnchorOpts:BuildAnchoringSection(body, frameKey, opts, -4)
        local realHeight = math.abs(finalY) + 4
        body:SetHeight(realHeight)
        local sec = body:GetParent()
        if sec then
            sec._contentHeight = realHeight
            if sec._expanded then
                sec:SetHeight(Utils.HEADER_HEIGHT + realHeight)
            end
        end
    end, sections, relayout)
end

---------------------------------------------------------------------------
-- WIDGET ROW HELPER (delegates to Helpers)
---------------------------------------------------------------------------

Utils.PlaceRow = Helpers.PlaceRow
Utils.EnsureDefaults = Helpers.EnsureDefaults

---------------------------------------------------------------------------
-- BACKDROP & BORDER SECTION (shared by combatTimer, brezCounter)
---------------------------------------------------------------------------

function Utils.BuildBackdropBorderSection(content, db, sections, relayout, Refresh)
    local GUI = QUI and QUI.GUI
    if not GUI then return end

    Utils.CreateCollapsible(content, "Backdrop & Border", 7 * Utils.FORM_ROW + 8, function(body)
        local sy = -4
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, "Show Backdrop", "showBackdrop", db, Refresh), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormColorPicker(body, "Backdrop Color", "backdropColor", db, Refresh), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, "Hide Border", "hideBorder", db, Refresh), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormSlider(body, "Border Size", 1, 5, 0.5, "borderSize", db, Refresh), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, "Class Color Border", "useClassColorBorder", db, Refresh), body, sy)
        sy = Utils.PlaceRow(GUI:CreateFormCheckbox(body, "Accent Color Border", "useAccentColorBorder", db, Refresh), body, sy)
        Utils.PlaceRow(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", db, Refresh), body, sy)
    end, sections, relayout)
end
