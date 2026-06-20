--[[
    QUI Options - Character Pane Tab (Appearance tile sub-page). Migrated to
    V3 body pattern.
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local PAD = (Shared and Shared.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

-- Shared provider-panel layout scaffold (core/settings_layout_shared.lua).
local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function row(parent, label, widget)
    return Shared.BuildSettingRow(parent, label, widget)
end

local function BuildCharacterPaneTab(tabContent)
    local db = Shared.GetDB()
    local char = db and db.character
    if not char then return end

    -- Defaults
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

    local L = MakeLayout(tabContent)

    ---------------------------------------------------------------------------
    -- ENABLE/DISABLE
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Enable/Disable"])
    local sEn = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(sEn.frame, nil, "enabled", char, function()
        GUI:ShowConfirmation({
            title = ns.L["Reload Required"], message = ns.L["Character Pane styling requires a UI reload."],
            acceptText = ns.L["Reload Now"], cancelText = ns.L["Later"],
            onAccept = function() QUI:SafeReload() end,
        })
    end, { description = ns.L["Enable the QUI character pane overlays including inspect and slot information. Requires a reload to take effect."] })
    sEn.AddRow(row(sEn.frame, ns.L["QUI Character Module (Req. Reload)"], enableW))
    L.closeSection(sEn)

    ---------------------------------------------------------------------------
    -- INSPECT FRAME
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Inspect Frame"])
    local sIF = L.sectionAt()
    local ifEnableW = GUI:CreateFormCheckbox(sIF.frame, nil, "inspectEnabled", char, function()
        GUI:ShowConfirmation({
            title = ns.L["Reload UI?"], message = ns.L["Inspect overlay changes require a reload."],
            acceptText = ns.L["Reload"], cancelText = ns.L["Later"],
            onAccept = function() QUI:SafeReload() end,
        })
    end, { description = ns.L["Show item level and enchant overlays on inspected players. Requires a reload to take effect."] })
    local ifShowOverallW = GUI:CreateFormCheckbox(sIF.frame, nil, "inspectLiteShowOverall", char, RefreshInspectLite,
        { description = ns.L["Display the inspected player's overall average item level on the inspect window."] })
    sIF.AddRow(
        row(sIF.frame, ns.L["Enable Inspect Overlays (Req. Reload)"], ifEnableW),
        row(sIF.frame, ns.L["Show Overall Average iLvl"], ifShowOverallW)
    )

    local ifOverallSizeW = GUI:CreateFormSlider(sIF.frame, nil, 8, 24, 1, "inspectLiteOverallFontSize", char, RefreshInspectLite,
        { description = ns.L["Font size used for the overall item level label."] })
    local ifOverallXW = GUI:CreateFormSlider(sIF.frame, nil, -100, 100, 1, "inspectLiteOverallOffsetX", char, RefreshInspectLite,
        { description = ns.L["Horizontal pixel offset of the overall item level label from its anchor."] })
    sIF.AddRow(
        row(sIF.frame, ns.L["Overall iLvl Font Size"], ifOverallSizeW),
        row(sIF.frame, ns.L["Overall iLvl X Offset"], ifOverallXW)
    )

    local ifOverallYW = GUI:CreateFormSlider(sIF.frame, nil, -100, 100, 1, "inspectLiteOverallOffsetY", char, RefreshInspectLite,
        { description = ns.L["Vertical pixel offset of the overall item level label from its anchor."] })
    local ifPerSlotShowW = GUI:CreateFormCheckbox(sIF.frame, nil, "inspectLiteShowPerSlot", char, RefreshInspectLite,
        { description = ns.L["Show a per-slot item level number on each piece of gear in the inspect window."] })
    sIF.AddRow(
        row(sIF.frame, ns.L["Overall iLvl Y Offset"], ifOverallYW),
        row(sIF.frame, ns.L["Show Per-Slot iLvl"], ifPerSlotShowW)
    )

    local ifPerSlotSizeW = GUI:CreateFormSlider(sIF.frame, nil, 8, 24, 1, "inspectLiteFontSize", char, RefreshInspectLite,
        { description = ns.L["Font size used for the per-slot item level numbers."] })
    sIF.AddRow(row(sIF.frame, ns.L["Per-Slot Font Size"], ifPerSlotSizeW))
    L.closeSection(sIF)

    ---------------------------------------------------------------------------
    -- SLOT OVERLAYS
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Slot Overlays"])
    local sSO = L.sectionAt()
    local soFontW = GUI:CreateFormDropdown(sSO.frame, nil, Shared.GetFontList(), "enchantFont", char, RefreshInspectLite,
        { description = ns.L["Font used for enchant text labels drawn on character and inspect slots."] })
    local soScaleW = GUI:CreateFormSlider(sSO.frame, nil, 0.5, 1.5, 0.05, "overlayScale", char, RefreshInspectLite,
        { precision = 2, description = ns.L["Scale multiplier applied to item level and enchant overlays on each gear slot."] })
    sSO.AddRow(
        row(sSO.frame, ns.L["Enchant Font"], soFontW),
        row(sSO.frame, ns.L["Overlay Scale"], soScaleW)
    )

    local soPadW = GUI:CreateFormSlider(sSO.frame, nil, 0, 10, 1, "slotPadding", char, RefreshInspectLite,
        { description = ns.L["Extra pixel padding between gear slots in the skinned character and inspect panes."] })
    sSO.AddRow(row(sSO.frame, ns.L["Slot Padding"], soPadW))
    L.closeSection(sSO)

    ---------------------------------------------------------------------------
    -- OPEN SETTINGS (button)
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Open Settings"])
    local btnFrame = CreateFrame("Frame", nil, tabContent)
    local openBtn = GUI:CreateButton(btnFrame, ns.L["Open Character Panel"], 200, 28, function()
        if not CharacterFrame:IsShown() and not InCombatLockdown() then ToggleCharacter("PaperDollFrame") end
        C_Timer.After(0, function()
            local sp = _G["QUI_CharSettingsPanel"]
            if sp then sp:Show() end
        end)
    end)
    openBtn:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 6, -4)
    L.placeCustom(btnFrame, 40)

    L.finish()
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
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 3 },
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
