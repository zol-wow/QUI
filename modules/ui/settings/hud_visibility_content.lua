--[[
    QUI Options - HUD Visibility Tab (Appearance tile sub-page). Migrated to
    V3 body pattern.
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local PAD = (Shared and Shared.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

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

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

-- Add a muted hint paragraph between a header and a card.
local function placeHint(L, parent, text)
    local f = CreateFrame("Frame", nil, parent)
    local lbl = GUI:CreateLabel(f, text, 11, C.textMuted)
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, 0)
    lbl:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    L.placeCustom(f, 22)
end

-- Pair an iterable list of cells 2-per-row, with a trailing unpaired cell.
local function pairCells(card, cells)
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

local function BuildHUDVisibilityTab(tabContent)
    local db = Shared.GetDB()
    if not db then return end

    local L = MakeLayout(tabContent)

    ---------------------------------------------------------------------------
    -- Shared builder for visibility sections (CDM, Unitframes, etc.)
    ---------------------------------------------------------------------------
    local function BuildVisibilitySection(title, visTable, refreshFunc, mouseoverRefreshGlobal, extraChecks)
        if visTable.showAlways == nil then visTable.showAlways = true end
        if visTable.showWhenTargetExists == nil then visTable.showWhenTargetExists = false end
        if visTable.showInCombat == nil then visTable.showInCombat = false end
        if visTable.showInGroup == nil then visTable.showInGroup = false end
        if visTable.showInInstance == nil then visTable.showInInstance = false end
        if visTable.showOnMouseover == nil then visTable.showOnMouseover = false end
        if visTable.showWhenMounted == nil then visTable.showWhenMounted = false end
        if visTable.fadeDuration == nil then visTable.fadeDuration = 0.2 end
        if visTable.fadeOutAlpha == nil then visTable.fadeOutAlpha = 0 end
        if visTable.hideWhenMounted == nil then visTable.hideWhenMounted = false end
        if visTable.hideWhenInVehicle == nil then visTable.hideWhenInVehicle = false end
        if visTable.hideWhenFlying == nil then visTable.hideWhenFlying = false end
        if visTable.hideWhenSkyriding == nil then visTable.hideWhenSkyriding = false end
        if visTable.dontHideInDungeonsRaids == nil then visTable.dontHideInDungeonsRaids = false end

        L.headerAt(title)
        placeHint(L, tabContent,
            "Uncheck 'Show Always' to use conditional visibility. Hover a setting for details.")

        local s = L.sectionAt()
        local conditionCells = {}

        local function UpdateConditionState()
            local enabled = not visTable.showAlways
            for _, cell in ipairs(conditionCells) do
                cell:SetAlpha(enabled and 1 or 0.4)
            end
        end

        -- Show Always (full-width, sole row)
        local showAlwaysW = GUI:CreateFormCheckbox(s.frame, nil, "showAlways", visTable, function()
            refreshFunc()
            UpdateConditionState()
        end, { description = "Always keep this HUD element visible. Uncheck to switch to the conditional visibility rules below." })
        s.AddRow(row(s.frame, "Show Always", showAlwaysW))

        -- Conditional visibility checkboxes (paired 2-per-row, dim together).
        local condDefs = {
            { key = "showWhenTargetExists", label = "Show When Target Exists",
              desc = "Show this HUD element while you have a target selected." },
            { key = "showInCombat", label = "Show In Combat",
              desc = "Show this HUD element while you are in combat." },
            { key = "showInGroup", label = "Show In Group",
              desc = "Show this HUD element while you are in a party or raid group." },
            { key = "showInInstance", label = "Show In Instance",
              desc = "Show this HUD element while you are inside a dungeon, raid, battleground, or scenario." },
            { key = "showOnMouseover", label = "Show On Mouseover",
              desc = "Show this HUD element while your cursor is hovering over its anchor area." },
            { key = "showWhenMounted", label = "Show When Mounted",
              desc = "Show this HUD element while you are mounted." },
        }
        local extraDescriptions = {
            showWhenHealthBelow100 = "Show these frames whenever your health is not full.",
            alwaysShowCastbars     = "Keep castbars visible even when the rest of the unit frame is hidden.",
        }
        if extraChecks then
            for _, ec in ipairs(extraChecks) do
                if visTable[ec.key] == nil then visTable[ec.key] = ec.default end
                condDefs[#condDefs + 1] = {
                    key = ec.key, label = ec.label, desc = extraDescriptions[ec.key],
                }
            end
        end

        for _, def in ipairs(condDefs) do
            local onChange = refreshFunc
            if def.key == "showOnMouseover" and mouseoverRefreshGlobal then
                onChange = function()
                    refreshFunc()
                    mouseoverRefreshGlobal()
                end
            end
            local w = GUI:CreateFormCheckbox(s.frame, nil, def.key, visTable, onChange,
                { description = def.desc })
            conditionCells[#conditionCells + 1] = row(s.frame, def.label, w)
        end
        pairCells(s, conditionCells)
        UpdateConditionState()

        -- Fade sliders
        local fadeDurW = GUI:CreateFormSlider(s.frame, nil, 0.1, 1.0, 0.05, "fadeDuration", visTable, refreshFunc,
            { precision = 2, description = "How many seconds the fade animation takes when this HUD element's visibility changes." })
        local fadeOutW = GUI:CreateFormSlider(s.frame, nil, 0, 1.0, 0.05, "fadeOutAlpha", visTable, refreshFunc,
            { precision = 2, description = "Opacity used while this HUD element is hidden. 0 is fully invisible, 1 is fully opaque." })
        s.AddRow(
            row(s.frame, "Fade Duration (sec)", fadeDurW),
            row(s.frame, "Fade Out Opacity", fadeOutW)
        )

        -- Hide rules
        local hideCells = {}
        local hideDefs = {
            { key = "hideWhenMounted",         label = "Hide When Mounted",
              desc = "Hide this HUD element while you are mounted, overriding any Show rules above." },
            { key = "hideWhenInVehicle",       label = "Hide When In Vehicle",
              desc = "Hide this HUD element while you are riding a vehicle, overriding any Show rules above." },
            { key = "hideWhenFlying",          label = "Hide When Flying",
              desc = "Hide this HUD element while flying on a traditional (non-dynamic) flying mount." },
            { key = "hideWhenSkyriding",       label = "Hide When Skyriding",
              desc = "Hide this HUD element while actively skyriding on a dynamic flying mount." },
            { key = "dontHideInDungeonsRaids", label = "Don't Hide in Dungeons/Raids",
              desc = "Ignore the mounted, vehicle, flying, and skyriding hide rules while you are inside a dungeon or raid instance." },
        }
        for _, def in ipairs(hideDefs) do
            local w = GUI:CreateFormCheckbox(s.frame, nil, def.key, visTable, refreshFunc,
                { description = def.desc })
            hideCells[#hideCells + 1] = row(s.frame, def.label, w)
        end
        pairCells(s, hideCells)

        L.closeSection(s)
    end

    -- ========== CDM Visibility ==========
    if not db.cdmVisibility then db.cdmVisibility = {} end
    BuildVisibilitySection(
        "CDM Visibility",
        db.cdmVisibility,
        function() if _G.QUI_RefreshCDMVisibility then _G.QUI_RefreshCDMVisibility() end end,
        function() if _G.QUI_RefreshCDMMouseover then _G.QUI_RefreshCDMMouseover() end end
    )

    -- ========== Unitframes Visibility ==========
    if not db.unitframesVisibility then db.unitframesVisibility = {} end
    BuildVisibilitySection(
        "Unitframes Visibility",
        db.unitframesVisibility,
        function() if _G.QUI_RefreshUnitframesVisibility then _G.QUI_RefreshUnitframesVisibility() end end,
        function() if _G.QUI_RefreshUnitframesMouseover then _G.QUI_RefreshUnitframesMouseover() end end,
        {
            {key = "showWhenHealthBelow100", label = "Show When Health < 100%", default = false},
            {key = "alwaysShowCastbars", label = "Always Show Castbars", default = false},
        }
    )

    -- ========== Custom CDM Bars Visibility ==========
    if not db.customTrackersVisibility then db.customTrackersVisibility = {} end
    BuildVisibilitySection(
        "Custom Items/Spells Bars",
        db.customTrackersVisibility,
        function() if _G.QUI_RefreshCustomTrackersVisibility then _G.QUI_RefreshCustomTrackersVisibility() end end,
        function() if _G.QUI_RefreshCustomTrackersMouseover then _G.QUI_RefreshCustomTrackersMouseover() end end
    )

    -- ========== Action Bars Visibility ==========
    if not db.actionBarsVisibility then db.actionBarsVisibility = {} end
    BuildVisibilitySection(
        "Action Bars Visibility",
        db.actionBarsVisibility,
        function() if _G.QUI_RefreshActionBarsVisibility then _G.QUI_RefreshActionBarsVisibility() end end,
        function() if _G.QUI_RefreshActionBarsMouseover then _G.QUI_RefreshActionBarsMouseover() end end
    )

    -- ========== Chat Frames Visibility ==========
    if not db.chatVisibility then db.chatVisibility = {} end
    BuildVisibilitySection(
        "Chat Frames Visibility",
        db.chatVisibility,
        function() if _G.QUI_RefreshChatVisibility then _G.QUI_RefreshChatVisibility() end end,
        function() if _G.QUI_RefreshChatMouseover then _G.QUI_RefreshChatMouseover() end end
    )

    L.finish()
end

-- Export
ns.QUI_HUDVisibilityOptions = {
    BuildHUDVisibilityTab = BuildHUDVisibilityTab
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "hudVisibilityPage",
        moverKey = "hudVisibility",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 7 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildHUDVisibilityTab,
            }),
        },
    }))
end
