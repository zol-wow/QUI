---------------------------------------------------------------------------
-- QUI Layout Mode — Shared Provider Utilities
-- Canonical implementations of CreateCollapsible, StandardRelayout,
-- BuildPositionCollapsible, and PlaceRow used by all settings providers.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = ns.LSM
local UIKit = ns.UIKit

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

    local chevron = UIKit and UIKit.CreateChevronCaret and UIKit.CreateChevronCaret(btn, {
        point = "LEFT",
        relativeTo = btn,
        relativePoint = "LEFT",
        xPixels = 2,
        yPixels = 0,
        sizePixels = 10,
        lineWidthPixels = 6,
        lineHeightPixels = 1,
        expanded = false,
        collapsedDirection = "right",
        r = ACCENT_R,
        g = ACCENT_G,
        b = ACCENT_B,
        a = 1,
    }) or btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not (UIKit and UIKit.CreateChevronCaret) then
        chevron:SetPoint("LEFT", 2, 0)
        chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        chevron:SetText(">")
    end

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
    label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    label:SetText(title)

    local underline = btn:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    underline:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)

    local bodyClip = CreateFrame("ScrollFrame", nil, section)
    bodyClip:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
    bodyClip:SetPoint("RIGHT", section, "RIGHT", 0, 0)
    bodyClip:SetHeight(0)
    bodyClip:Hide()

    local body = CreateFrame("Frame", nil, bodyClip)
    body:SetHeight(contentHeight)
    body:SetWidth(1)
    bodyClip:SetScrollChild(body)
    bodyClip:SetScript("OnSizeChanged", function(self, width)
        body:SetWidth(math.max(width or 1, 1))
    end)
    body:SetAlpha(0)
    body._logicalSection = section
    bodyClip._logicalSection = section

    section._expanded = false
    section._contentHeight = contentHeight
    section._body = body
    section._bodyClip = bodyClip
    section._sectionTitle = title  -- used for saving/restoring expanded state

    local function MeasureBodyContentHeight()
        local bodyTop = body.GetTop and body:GetTop()
        if not bodyTop then return nil end

        local maxOffset = 0
        local function Accumulate(region)
            if not region or not region.GetBottom then return end
            if region.IsShown and not region:IsShown() then return end
            local bottom = region:GetBottom()
            if bottom then
                maxOffset = math.max(maxOffset, bodyTop - bottom)
            end
        end

        local childCount = body.GetNumChildren and body:GetNumChildren() or 0
        for i = 1, childCount do
            Accumulate(select(i, body:GetChildren()))
        end

        local regionCount = body.GetNumRegions and body:GetNumRegions() or 0
        for i = 1, regionCount do
            Accumulate(select(i, body:GetRegions()))
        end

        if maxOffset <= 0 then
            return nil
        end
        return math.ceil(maxOffset + 8)
    end

    local function RefreshContentHeight()
        if type(body._contentHeight) == "number" and body._contentHeight > 0 then
            section._contentHeight = math.max(section._contentHeight or 0, body._contentHeight)
            body._contentHeight = nil
        end
        if type(bodyClip._contentHeight) == "number" and bodyClip._contentHeight > 0 then
            section._contentHeight = math.max(section._contentHeight or 0, bodyClip._contentHeight)
            bodyClip._contentHeight = nil
        end

        local measuredHeight = MeasureBodyContentHeight()
        if measuredHeight and measuredHeight > 0 then
            section._contentHeight = math.max(section._contentHeight or 0, measuredHeight)
        end

        body:SetHeight(section._contentHeight or contentHeight)
    end

    local function ApplyExpandedState(currentHeight)
        local height = math.max(0, math.min(section._contentHeight, currentHeight or 0))
        bodyClip:SetHeight(height)
        section:SetHeight(HEADER_HEIGHT + height)
    end

    section.SetExpanded = function(self, expanded, skipRelayout)
        section._expanded = expanded and true or false
        if UIKit and UIKit.SetChevronCaretExpanded then
            UIKit.SetChevronCaretExpanded(chevron, section._expanded)
        else
            chevron:SetText(section._expanded and "v" or ">")
        end

        RefreshContentHeight()
        local targetHeight = section._expanded and section._contentHeight or 0
        local currentHeight = bodyClip:GetHeight() or 0

        if section._expanded then
            bodyClip:Show()
            body:SetAlpha(skipRelayout and 1 or body:GetAlpha())
        end

        if skipRelayout or not (UIKit and UIKit.AnimateValue and UIKit.CancelValueAnimation) then
            if UIKit and UIKit.CancelValueAnimation then
                UIKit.CancelValueAnimation(section, "layoutCollapsible")
            end
            ApplyExpandedState(targetHeight)
            body:SetAlpha(section._expanded and 1 or 0)
            if not section._expanded then
                bodyClip:Hide()
            end
            if not skipRelayout then
                relayout()
            end
            return
        end

        UIKit.CancelValueAnimation(section, "layoutCollapsible")
        UIKit.AnimateValue(section, "layoutCollapsible", {
            fromValue = currentHeight,
            toValue = targetHeight,
            duration = ((_G.QUI and _G.QUI.GUI and _G.QUI.GUI._sidebarAnimDuration) or 0.16),
            onUpdate = function(_, progressHeight)
                local totalRange = math.max(section._contentHeight, 1)
                local ratio = math.max(0, math.min(1, progressHeight / totalRange))
                ApplyExpandedState(progressHeight)
                body:SetAlpha(ratio)
                relayout()
            end,
            onFinish = function(_, finalHeight)
                ApplyExpandedState(finalHeight)
                body:SetAlpha(section._expanded and 1 or 0)
                if not section._expanded then
                    bodyClip:Hide()
                end
                relayout()
            end,
        })
    end

    -- Restore expanded state from previous build if available
    local settings = ns.QUI_LayoutMode_Settings
    local savedStates = settings and settings._expandedStates
    RefreshContentHeight()
    if savedStates and savedStates[title] then
        section:SetExpanded(true, true)
    end

    btn:SetScript("OnClick", function()
        section:SetExpanded(not section._expanded)
    end)

    btn:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1, 1)
        if UIKit and UIKit.SetChevronCaretColor then
            UIKit.SetChevronCaretColor(chevron, 1, 1, 1, 1)
        else
            chevron:SetTextColor(1, 1, 1, 1)
        end
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        if UIKit and UIKit.SetChevronCaretColor then
            UIKit.SetChevronCaretColor(chevron, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        else
            chevron:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end
    end)

    buildFunc(body)
    RefreshContentHeight()
    C_Timer.After(0, function()
        if not section or not body then return end
        RefreshContentHeight()
        if section._expanded then
            ApplyExpandedState(section._contentHeight)
            relayout()
        end
    end)
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
