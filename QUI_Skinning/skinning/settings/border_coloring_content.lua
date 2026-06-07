--[[
    QUI Options - Border Coloring Page
    BuildBorderColoringTab: Global Border section + per-module rows from BorderRegistry.
    Registered as feature "borderColoringPage" in the appearance category.
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI

local Shared = ns.QUI_Options
local Helpers = ns.Helpers

local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local BORDER_COLORING_SUBPAGE_INDEX = 11

local PAD = (Shared and Shared.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

---------------------------------------------------------------------------
-- V3 layout helpers (mirrored from skinning_content.lua)
---------------------------------------------------------------------------
local function MakeLayout(content)
    local y = -10
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
    function L.finish()
        content:SetHeight(math.abs(y) + 10)
        return content:GetHeight()
    end
    return L
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

local function RefreshBorderColoring()
    if Helpers and Helpers.RefreshAllBorders then
        Helpers.RefreshAllBorders()
    end
    if ns.Registry and type(ns.Registry.RefreshAll) == "function" then
        ns.Registry:RefreshAll("skinning")
    end
end

---------------------------------------------------------------------------
-- BUILD FUNCTION
---------------------------------------------------------------------------
local function BuildBorderColoringTab(tabContent)
    local db = Shared.GetDB()

    GUI:SetSearchContext({
        tileId = "appearance",
        tabName = "Appearance",
        subPageIndex = BORDER_COLORING_SUBPAGE_INDEX,
        subTabName = "Border Coloring",
        featureId = "borderColoringPage",
        category = "appearance",
    })

    if not db then return end
    if not db.general then db.general = {} end

    local general = db.general
    local profile = db

    -- Ensure defaults for the global border keys
    if general.hideSkinBorders == nil then general.hideSkinBorders = false end
    if general.skinBorderColorSource == nil then
        general.skinBorderColorSource = general.skinBorderUseClassColor and "class" or "theme"
    end

    local L = MakeLayout(tabContent)

    -- Global Border section
    L.headerAt("Global Border")
    local sGB = L.sectionAt()

    local gbSourceW, gbColorW = ns.QUI_BorderControl.Attach(
        GUI,
        sGB.frame,
        general,
        "skin",
        RefreshBorderColoring,
        {
            includeInherit   = false,
            noAlpha          = true,
            label            = "Border Color Source",
            colorLabel       = "Custom Border Color",
        }
    )

    local gbHideW = GUI:CreateFormCheckbox(sGB.frame, nil, "hideSkinBorders", general,
        RefreshBorderColoring,
        { description = "Hide the 1px border drawn around all globally skinned frames." }
    )

    sGB.AddRow(
        row(sGB.frame, "Border Color Source", gbSourceW),
        row(sGB.frame, "Custom Border Color",  gbColorW)
    )
    sGB.AddRow(
        row(sGB.frame, "Hide Borders", gbHideW)
    )
    L.closeSection(sGB)

    -- Per-module sections grouped by category
    local CATEGORY_ORDER = { "Skinning", "Unit Frames", "CDM", "Trackers", "HUD" }

    -- Build category -> entries map
    local byCategory = {}
    Helpers.BorderRegistry.Each(function(e)
        local cat = e.category or "Other"
        if not byCategory[cat] then byCategory[cat] = {} end
        local t = byCategory[cat]
        t[#t + 1] = e
    end)

    for _, cat in ipairs(CATEGORY_ORDER) do
        local entries = byCategory[cat]
        if entries and #entries > 0 then
            L.headerAt(cat)
            local sCat = L.sectionAt()
            local cells = {}
            for _, e in ipairs(entries) do
                if e.multi then
                    -- Multi-instance: bind the control to the first instance, but
                    -- bulk-copy its chosen source/color to ALL instances on change.
                    local insts = e.instances and e.instances(profile) or {}
                    local rep = insts[1]
                    if rep then
                        local keys = Helpers.GetBorderKeys(e.prefix or "")
                        local srcW, colW = ns.QUI_BorderControl.Attach(
                            GUI,
                            sCat.frame,
                            rep,
                            e.prefix or "",
                            function()
                                for _, inst in ipairs(insts) do
                                    inst[keys.source] = rep[keys.source]
                                    if type(rep[keys.color]) == "table" then
                                        inst[keys.color] = {
                                            rep[keys.color][1], rep[keys.color][2],
                                            rep[keys.color][3], rep[keys.color][4],
                                        }
                                    end
                                end
                                RefreshBorderColoring()
                            end,
                            {
                                label      = e.label .. " Source (all)",
                                colorLabel = e.label .. " Color (all)",
                            }
                        )
                        cells[#cells + 1] = row(sCat.frame, e.label .. " Source", srcW)
                        cells[#cells + 1] = row(sCat.frame, e.label .. " Color",  colW)
                    end
                else
                    local dbTable = type(e.db) == "function" and e.db(profile) or nil
                    if dbTable then
                        local srcW, colW = ns.QUI_BorderControl.Attach(
                            GUI,
                            sCat.frame,
                            dbTable,
                            e.prefix or "",
                            RefreshBorderColoring,
                            {
                                label      = e.label .. " Source",
                                colorLabel = e.label .. " Color",
                            }
                        )
                        cells[#cells + 1] = row(sCat.frame, e.label .. " Source", srcW)
                        cells[#cells + 1] = row(sCat.frame, e.label .. " Color",  colW)
                    end
                end
            end
            -- Emit rows in pairs
            local i = 1
            while i <= #cells do
                local left  = cells[i]
                local right = cells[i + 1]
                if right then
                    sCat.AddRow(left, right)
                    i = i + 2
                else
                    sCat.AddRow(left)
                    i = i + 1
                end
            end
            L.closeSection(sCat)
        end
    end

    L.finish()
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_BorderColoringOptions = {
    BuildBorderColoringTab = BuildBorderColoringTab,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id         = "borderColoringPage",
        moverKey   = "borderColoring",
        lookupKeys = { "border", "outline", "edge" },
        category   = "appearance",
        nav        = { tileId = "appearance", subPageIndex = BORDER_COLORING_SUBPAGE_INDEX },
        sections   = {
            Schema.Section({
                id        = "settings",
                kind      = "page",
                minHeight = 80,
                build     = BuildBorderColoringTab,
            }),
        },
    }))
end
