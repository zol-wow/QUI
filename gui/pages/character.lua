--[[
    QUI Options - Character Pane Tab
    BuildCharacterPaneTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildCharacterPaneTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 1, tabName = "General & QoL", subTabIndex = 7, subTabName = "Character Pane"})

    local char = db and db.character
    if not char then return end

    -- SECTION: Enable/Disable
    local enableHeader = GUI:CreateSectionHeader(tabContent, "Enable/Disable QUI Character Module")
    enableHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - enableHeader.gap

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "QUI Character Module",
        "enabled", char, function(val)
            GUI:ShowConfirmation({
                title = "Reload Required",
                message = "Character Pane styling requires a UI reload to take effect.",
                acceptText = "Reload Now",
                cancelText = "Later",
                isDestructive = false,
                onAccept = function()
                    QUI:SafeReload()
                end,
            })
        end)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local enableInfo = GUI:CreateLabel(tabContent, "If you are using a dedicated character stats addon, toggle this off.", 10, C.textMuted)
    enableInfo:SetPoint("TOPLEFT", PADDING, y)
    enableInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    enableInfo:SetJustifyH("LEFT")
    y = y - 20

    -- Section Header
    local header = GUI:CreateSectionHeader(tabContent, "Character Pane Settings")
    header:SetPoint("TOPLEFT", PADDING, y)
    y = y - header.gap

    -- Description
    local desc = GUI:CreateLabel(tabContent, "Character Pane settings are now accessed from the Character Panel itself.\n\nOpen your Character Frame (C) and click the gear icon to access all settings.", 11, C.textMuted)
    desc:SetPoint("TOPLEFT", PADDING, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetHeight(50)
    y = y - 60

    -- INSPECT FRAME Section
    local inspectHeader = GUI:CreateSectionHeader(tabContent, "Inspect Frame")
    inspectHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - inspectHeader.gap

    local inspectDesc = GUI:CreateLabel(tabContent, "Apply the same overlays and stats panel to the Inspect frame when inspecting other players.", 11, C.textMuted)
    inspectDesc:SetPoint("TOPLEFT", PADDING, y)
    inspectDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    inspectDesc:SetJustifyH("LEFT")
    inspectDesc:SetWordWrap(true)
    inspectDesc:SetHeight(20)
    y = y - 28

    if char.inspectEnabled == nil then char.inspectEnabled = true end

    local inspectEnabled = GUI:CreateFormCheckbox(tabContent, "Enable Inspect Overlays", "inspectEnabled", char, function()
        print("|cFF56D1FFQUI:|r Inspect overlay change requires /reload to take effect.")
    end)
    inspectEnabled:SetPoint("TOPLEFT", PADDING, y)
    inspectEnabled:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    y = y - 10

    -- Open Character Panel button
    local openBtn = GUI:CreateButton(tabContent, "Open Character Panel", 200, 32, function()
        -- Open character frame if not open
        if not CharacterFrame:IsShown() then
            ToggleCharacter("PaperDollFrame")
        end
        -- Show settings panel after a short delay
        C_Timer.After(0.1, function()
            local settingsPanel = _G["QUI_CharSettingsPanel"]
            if settingsPanel then
                settingsPanel:Show()
            end
        end)
    end)
    openBtn:SetPoint("TOPLEFT", PADDING, y)

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_CharacterOptions = {
    BuildCharacterPaneTab = BuildCharacterPaneTab
}
