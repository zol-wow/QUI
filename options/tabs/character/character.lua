--[[
    QUI Options - Character Pane Tab
    BuildCharacterPaneTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local P = Helpers.PlaceRow

local function BuildCharacterPaneTab(tabContent)
    local FORM_ROW = 32
    local PAD = Shared.PADDING
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 7, subTabName = "Character Pane"})

    local char = db and db.character
    if not char then return end

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

    -- Enable
    CreateCollapsible("Enable/Disable", 1 * FORM_ROW + 8, function(body)
        local sy = -4
        P(GUI:CreateFormCheckbox(body, "QUI Character Module (Req. Reload)", "enabled", char, function()
            GUI:ShowConfirmation({
                title = "Reload Required", message = "Character Pane styling requires a UI reload.",
                acceptText = "Reload Now", cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end), body, sy)
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
        end), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Overall Average iLvl", "inspectLiteShowOverall", char, RefreshInspectLite), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Overall iLvl Font Size", 8, 24, 1, "inspectLiteOverallFontSize", char, RefreshInspectLite), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Overall iLvl X Offset", -100, 100, 1, "inspectLiteOverallOffsetX", char, RefreshInspectLite), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Overall iLvl Y Offset", -100, 100, 1, "inspectLiteOverallOffsetY", char, RefreshInspectLite), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Per-Slot iLvl", "inspectLiteShowPerSlot", char, RefreshInspectLite), body, sy)
        P(GUI:CreateFormSlider(body, "Per-Slot Font Size", 8, 24, 1, "inspectLiteFontSize", char, RefreshInspectLite), body, sy)
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
