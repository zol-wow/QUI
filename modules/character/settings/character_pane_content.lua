--[[
    QUI Options - Character Pane Tab (Gameplay tile sub-page)
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

local function BuildCharacterPaneTab(tabContent)
    local FORM_ROW = 32
    local PAD = Shared.PADDING
    local db = Shared.GetDB()

    local char = db and db.character
    if not char then return end

    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(tabContent, PAD)

    -- Enable
    CreateCollapsible("Enable/Disable", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        P(GUI:CreateFormCheckbox(body, "QUI Character Module (Req. Reload)", "enabled", char, function()
            GUI:ShowConfirmation({
                title = "Reload Required", message = "Character Pane styling requires a UI reload.",
                acceptText = "Reload Now", cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end, { description = "Enable the QUI character pane overlays including inspect and slot information. Requires a reload to take effect." }), body, sy)
    end)

    -- Inspect Frame
    if char.inspectEnabled == nil then char.inspectEnabled = true end
    if char.inspectLiteMode == nil then char.inspectLiteMode = false end
    if char.inspectLiteShowOverall == nil then char.inspectLiteShowOverall = true end
    if char.inspectLiteShowPerSlot == nil then char.inspectLiteShowPerSlot = true end
    if char.inspectLiteFontSize == nil then char.inspectLiteFontSize = 15 end
    if char.inspectLiteOverallFontSize == nil then char.inspectLiteOverallFontSize = 11 end
    if char.inspectLiteOverallOffsetX == nil then char.inspectLiteOverallOffsetX = 0 end
    if char.inspectLiteOverallOffsetY == nil then char.inspectLiteOverallOffsetY = -8 end

    local function RefreshInspectLite()
        local shared = ns.QUI.CharacterShared
        if shared and shared.ScheduleUpdate then shared.ScheduleUpdate() end
    end

    CreateCollapsible("Inspect Frame", 7 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Enable Inspect Overlays (Req. Reload)", "inspectEnabled", char, function()
            GUI:ShowConfirmation({
                title = "Reload UI?", message = "Inspect overlay changes require a reload.",
                acceptText = "Reload", cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end, { description = "Show item level and enchant overlays on inspected players. Requires a reload to take effect." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Overall Average iLvl", "inspectLiteShowOverall", char, RefreshInspectLite,
            { description = "Display the inspected player's overall average item level on the inspect window." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Overall iLvl Font Size", 8, 24, 1, "inspectLiteOverallFontSize", char, RefreshInspectLite, nil,
            { description = "Font size used for the overall item level label." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Overall iLvl X Offset", -100, 100, 1, "inspectLiteOverallOffsetX", char, RefreshInspectLite, nil,
            { description = "Horizontal pixel offset of the overall item level label from its anchor." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Overall iLvl Y Offset", -100, 100, 1, "inspectLiteOverallOffsetY", char, RefreshInspectLite, nil,
            { description = "Vertical pixel offset of the overall item level label from its anchor." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Per-Slot iLvl", "inspectLiteShowPerSlot", char, RefreshInspectLite,
            { description = "Show a per-slot item level number on each piece of gear in the inspect window." }), body, sy)
        P(GUI:CreateFormSlider(body, "Per-Slot Font Size", 8, 24, 1, "inspectLiteFontSize", char, RefreshInspectLite, nil,
            { description = "Font size used for the per-slot item level numbers." }), body, sy)
    end)

    -- Slot Overlays (enchant text, overlay scale, slot spacing)
    CreateCollapsible("Slot Overlays", 3 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormDropdown(body, "Enchant Font",
            Shared.GetFontList(), "enchantFont", char, RefreshInspectLite,
            { description = "Font used for enchant text labels drawn on character and inspect slots." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Overlay Scale", 0.5, 1.5, 0.05,
            "overlayScale", char, RefreshInspectLite, nil,
            { description = "Scale multiplier applied to item level and enchant overlays on each gear slot." }), body, sy)
        P(GUI:CreateFormSlider(body, "Slot Padding", 0, 10, 1,
            "slotPadding", char, RefreshInspectLite, nil,
            { description = "Extra pixel padding between gear slots in the skinned character and inspect panes." }), body, sy)
    end)

    -- Open Character Panel
    CreateCollapsible("Open Settings", 1 * FORM_ROW + 8, function(body)
        local openBtn = GUI:CreateButton(body, "Open Character Panel", 200, 28, function()
            if not CharacterFrame:IsShown() and not InCombatLockdown() then ToggleCharacter("PaperDollFrame") end
            C_Timer.After(0.1, function()
                local sp = _G["QUI_CharSettingsPanel"]
                if sp then sp:Show() end
            end)
        end)
        openBtn:SetPoint("TOPLEFT", 0, -4)
    end)

    relayout()
end

ns.QUI_CharacterOptions = {
    BuildCharacterPaneTab = BuildCharacterPaneTab
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "characterPane",
        moverKey = "characterPane",
        category = "gameplay",
        nav = { tileId = "gameplay", subPageIndex = 5 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildCharacterPaneTab,
            }),
        },
    }))
end
