--[[
    QUI Modules - Shared settings-content layout helpers.

    The HUD/crosshair/autohide/visibility settings pages all use the same
    "MakeLayout" body-builder rhythm (accent-dot header + settings card group +
    cursor advance) and the same single-row wrapper. This module hosts one
    parameterized copy so the layout cadence lives in a single place.

    Loaded by the core QUI.toc (before QUI_Options), so ns.QUI_Options is read
    lazily inside the helpers — never captured at file scope.
]]

local _, ns = ...

local SettingsLayout = {}
ns.QUI_ModulesSettingsLayout = SettingsLayout

local HEADER_GAP = 26
local SECTION_GAP = 14

-- Canonical 9-point anchor dropdown options (value + display text), shared by
-- the layout composer and the third-party anchoring settings surface.
SettingsLayout.NINE_POINT_OPTIONS = {
    { value = "TOPLEFT",     text = ns.L["Top Left"] },
    { value = "TOP",         text = ns.L["Top"] },
    { value = "TOPRIGHT",    text = ns.L["Top Right"] },
    { value = "LEFT",        text = ns.L["Left"] },
    { value = "CENTER",      text = ns.L["Center"] },
    { value = "RIGHT",       text = ns.L["Right"] },
    { value = "BOTTOMLEFT",  text = ns.L["Bottom Left"] },
    { value = "BOTTOM",      text = ns.L["Bottom"] },
    { value = "BOTTOMRIGHT", text = ns.L["Bottom Right"] },
}

-- Build a body-layout helper bound to `content`. `startY` defaults to -10.
-- The returned table exposes headerAt/sectionAt/closeSection/placeCustom/finish.
function SettingsLayout.MakeLayout(content, startY)
    local Shared = ns.QUI_Options
    local PAD = (Shared and Shared.PADDING) or 15
    local y = startY or -10
    local L = {}
    function L.headerAt(text)
        local h = Shared.CreateAccentDotLabel(content, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end
    function L.sectionAt()
        local c = Shared.CreateSettingsCardGroup(content, y)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        c.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        return c
    end
    function L.closeSection(c)
        c.Finalize()
        y = y - c.frame:GetHeight() - SECTION_GAP
    end
    function L.placeCustom(frame, height)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        frame:SetHeight(height)
        y = y - height - SECTION_GAP
    end
    function L.finish()
        content:SetHeight(math.abs(y) + 10)
        return content:GetHeight()
    end
    return L
end

-- Single settings row wrapper (label + widget + optional description).
function SettingsLayout.Row(parent, label, widget, desc)
    return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
end

-- Add a flat list of pre-built cells to `card` two-per-row, trailing the last
-- cell on its own row when the count is odd.
function SettingsLayout.PairCells(card, cells)
    local i = 1
    while i <= #cells do
        local left = cells[i]
        local right = cells[i + 1]
        if right then
            card.AddRow(left, right)
            i = i + 2
        else
            card.AddRow(left)
            i = i + 1
        end
    end
end
