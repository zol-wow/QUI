--[[
    QUI Options - HUD Visibility Tab (Appearance tile sub-page)
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local P = Helpers.PlaceRow
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local function BuildHUDVisibilityTab(tabContent)
    local FORM_ROW = 32
    local PAD = Shared.PADDING
    local db = Shared.GetDB()

    if not db then return end

    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(tabContent, PAD)

    ---------------------------------------------------------------------------
    -- Shared builder for visibility sections (CDM, Unitframes, Custom CDM Bars)
    -- Each section has the same pattern of condition checks + fade + hide rules.
    ---------------------------------------------------------------------------
    local function BuildVisibilitySection(title, visTable, refreshFunc, mouseoverRefreshGlobal, extraChecks)
        -- Ensure defaults
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

        -- Base content height before the tile wrapper compacts the rows into its
        -- dual-column layout. Keep this aligned with the actual stacked widgets
        -- we create here so the initial render does not overshoot.
        CreateCollapsible(title, 1, function(body)
            local sy = -4
            local conditionChecks = {}

            local tip = GUI:CreateLabel(body,
                "Uncheck 'Show Always' to use conditional visibility. Hover a setting for details.",
                11, C.textMuted)
            tip:SetPoint("TOPLEFT", 0, sy)
            tip:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            tip:SetJustifyH("LEFT")
            sy = sy - 28

            local function UpdateConditionState()
                local enabled = not visTable.showAlways
                for _, check in ipairs(conditionChecks) do
                    if enabled then
                        check:SetAlpha(1)
                        if check.track then check.track:EnableMouse(true) end
                    else
                        check:SetAlpha(0.4)
                        if check.track then check.track:EnableMouse(false) end
                    end
                end
            end

            sy = P(GUI:CreateFormCheckbox(body, "Show Always", "showAlways", visTable, function()
                refreshFunc()
                UpdateConditionState()
            end, { description = "Always keep this HUD element visible. Uncheck to switch to the conditional visibility rules below." }), body, sy)

            local targetCheck = GUI:CreateFormCheckbox(body, "Show When Target Exists", "showWhenTargetExists", visTable, refreshFunc,
                { description = "Show this HUD element while you have a target selected." })
            table.insert(conditionChecks, targetCheck)
            sy = P(targetCheck, body, sy)

            local combatCheck = GUI:CreateFormCheckbox(body, "Show In Combat", "showInCombat", visTable, refreshFunc,
                { description = "Show this HUD element while you are in combat." })
            table.insert(conditionChecks, combatCheck)
            sy = P(combatCheck, body, sy)

            local groupCheck = GUI:CreateFormCheckbox(body, "Show In Group", "showInGroup", visTable, refreshFunc,
                { description = "Show this HUD element while you are in a party or raid group." })
            table.insert(conditionChecks, groupCheck)
            sy = P(groupCheck, body, sy)

            local instanceCheck = GUI:CreateFormCheckbox(body, "Show In Instance", "showInInstance", visTable, refreshFunc,
                { description = "Show this HUD element while you are inside a dungeon, raid, battleground, or scenario." })
            table.insert(conditionChecks, instanceCheck)
            sy = P(instanceCheck, body, sy)

            local mouseoverCheck = GUI:CreateFormCheckbox(body, "Show On Mouseover", "showOnMouseover", visTable, function()
                refreshFunc()
                if mouseoverRefreshGlobal then mouseoverRefreshGlobal() end
            end, { description = "Show this HUD element while your cursor is hovering over its anchor area." })
            table.insert(conditionChecks, mouseoverCheck)
            sy = P(mouseoverCheck, body, sy)

            local mountedCheck = GUI:CreateFormCheckbox(body, "Show When Mounted", "showWhenMounted", visTable, refreshFunc,
                { description = "Show this HUD element while you are mounted." })
            table.insert(conditionChecks, mountedCheck)
            sy = P(mountedCheck, body, sy)

            -- Extra condition checks (e.g. showWhenHealthBelow100, alwaysShowCastbars)
            local extraDescriptions = {
                showWhenHealthBelow100 = "Show these frames whenever your health is not full.",
                alwaysShowCastbars     = "Keep castbars visible even when the rest of the unit frame is hidden.",
            }
            if extraChecks then
                for _, ec in ipairs(extraChecks) do
                    if visTable[ec.key] == nil then visTable[ec.key] = ec.default end
                    local check = GUI:CreateFormCheckbox(body, ec.label, ec.key, visTable, refreshFunc,
                        { description = extraDescriptions[ec.key] })
                    table.insert(conditionChecks, check)
                    sy = P(check, body, sy)
                end
            end

            UpdateConditionState()

            sy = P(GUI:CreateFormSlider(body, "Fade Duration (sec)", 0.1, 1.0, 0.05, "fadeDuration", visTable, refreshFunc, nil,
                { description = "How many seconds the fade animation takes when this HUD element's visibility changes." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Out Opacity", 0, 1.0, 0.05, "fadeOutAlpha", visTable, refreshFunc, nil,
                { description = "Opacity used while this HUD element is hidden. 0 is fully invisible, 1 is fully opaque." }), body, sy)

            -- Hide When Mounted
            sy = P(GUI:CreateFormCheckbox(body, "Hide When Mounted", "hideWhenMounted", visTable, refreshFunc,
                { description = "Hide this HUD element while you are mounted, overriding any Show rules above." }), body, sy)

            -- Hide When In Vehicle
            sy = P(GUI:CreateFormCheckbox(body, "Hide When In Vehicle", "hideWhenInVehicle", visTable, refreshFunc,
                { description = "Hide this HUD element while you are riding a vehicle, overriding any Show rules above." }), body, sy)

            -- Hide When Flying
            sy = P(GUI:CreateFormCheckbox(body, "Hide When Flying", "hideWhenFlying", visTable, refreshFunc,
                { description = "Hide this HUD element while flying on a traditional (non-dynamic) flying mount." }), body, sy)

            -- Hide When Skyriding
            sy = P(GUI:CreateFormCheckbox(body, "Hide When Skyriding", "hideWhenSkyriding", visTable, refreshFunc,
                { description = "Hide this HUD element while actively skyriding on a dynamic flying mount." }), body, sy)

            -- Don't Hide in Dungeons/Raids
            sy = P(GUI:CreateFormCheckbox(body, "Don't Hide in Dungeons/Raids", "dontHideInDungeonsRaids", visTable, refreshFunc,
                { description = "Ignore the mounted, vehicle, flying, and skyriding hide rules while you are inside a dungeon or raid instance." }), body, sy)

            -- Calculate total content height
            local numConditions = 7 + (extraChecks and #extraChecks or 0)
            -- tip(28) + showAlways(FORM_ROW) + conditions(numConditions * FORM_ROW)
            -- + fadeSliders(2 * FORM_ROW) + 5 hide rules(5 * FORM_ROW)
            local totalHeight = 28 + FORM_ROW + numConditions * FORM_ROW + 2 * FORM_ROW + 5 * FORM_ROW + 8
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end)
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

    relayout()
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
        nav = { tileId = "appearance", subPageIndex = 6 },
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
