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
    L.headerAt("Enable/Disable")
    local sEn = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(sEn.frame, nil, "enabled", char, function()
        GUI:ShowConfirmation({
            title = "Reload Required", message = "Character Pane styling requires a UI reload.",
            acceptText = "Reload Now", cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end, { description = "Enable the QUI character pane overlays including inspect and slot information. Requires a reload to take effect." })
    sEn.AddRow(row(sEn.frame, "QUI Character Module (Req. Reload)", enableW))
    L.closeSection(sEn)

    ---------------------------------------------------------------------------
    -- INSPECT FRAME
    ---------------------------------------------------------------------------
    L.headerAt("Inspect Frame")
    local sIF = L.sectionAt()
    local ifEnableW = GUI:CreateFormCheckbox(sIF.frame, nil, "inspectEnabled", char, function()
        GUI:ShowConfirmation({
            title = "Reload UI?", message = "Inspect overlay changes require a reload.",
            acceptText = "Reload", cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end, { description = "Show item level and enchant overlays on inspected players. Requires a reload to take effect." })
    local ifShowOverallW = GUI:CreateFormCheckbox(sIF.frame, nil, "inspectLiteShowOverall", char, RefreshInspectLite,
        { description = "Display the inspected player's overall average item level on the inspect window." })
    sIF.AddRow(
        row(sIF.frame, "Enable Inspect Overlays (Req. Reload)", ifEnableW),
        row(sIF.frame, "Show Overall Average iLvl", ifShowOverallW)
    )

    local ifOverallSizeW = GUI:CreateFormSlider(sIF.frame, nil, 8, 24, 1, "inspectLiteOverallFontSize", char, RefreshInspectLite,
        { description = "Font size used for the overall item level label." })
    local ifOverallXW = GUI:CreateFormSlider(sIF.frame, nil, -100, 100, 1, "inspectLiteOverallOffsetX", char, RefreshInspectLite,
        { description = "Horizontal pixel offset of the overall item level label from its anchor." })
    sIF.AddRow(
        row(sIF.frame, "Overall iLvl Font Size", ifOverallSizeW),
        row(sIF.frame, "Overall iLvl X Offset", ifOverallXW)
    )

    local ifOverallYW = GUI:CreateFormSlider(sIF.frame, nil, -100, 100, 1, "inspectLiteOverallOffsetY", char, RefreshInspectLite,
        { description = "Vertical pixel offset of the overall item level label from its anchor." })
    local ifPerSlotShowW = GUI:CreateFormCheckbox(sIF.frame, nil, "inspectLiteShowPerSlot", char, RefreshInspectLite,
        { description = "Show a per-slot item level number on each piece of gear in the inspect window." })
    sIF.AddRow(
        row(sIF.frame, "Overall iLvl Y Offset", ifOverallYW),
        row(sIF.frame, "Show Per-Slot iLvl", ifPerSlotShowW)
    )

    local ifPerSlotSizeW = GUI:CreateFormSlider(sIF.frame, nil, 8, 24, 1, "inspectLiteFontSize", char, RefreshInspectLite,
        { description = "Font size used for the per-slot item level numbers." })
    sIF.AddRow(row(sIF.frame, "Per-Slot Font Size", ifPerSlotSizeW))
    L.closeSection(sIF)

    ---------------------------------------------------------------------------
    -- SLOT OVERLAYS
    ---------------------------------------------------------------------------
    L.headerAt("Slot Overlays")
    local sSO = L.sectionAt()
    local soFontW = GUI:CreateFormDropdown(sSO.frame, nil, Shared.GetFontList(), "enchantFont", char, RefreshInspectLite,
        { description = "Font used for enchant text labels drawn on character and inspect slots." })
    local soScaleW = GUI:CreateFormSlider(sSO.frame, nil, 0.5, 1.5, 0.05, "overlayScale", char, RefreshInspectLite,
        { precision = 2, description = "Scale multiplier applied to item level and enchant overlays on each gear slot." })
    sSO.AddRow(
        row(sSO.frame, "Enchant Font", soFontW),
        row(sSO.frame, "Overlay Scale", soScaleW)
    )

    local soPadW = GUI:CreateFormSlider(sSO.frame, nil, 0, 10, 1, "slotPadding", char, RefreshInspectLite,
        { description = "Extra pixel padding between gear slots in the skinned character and inspect panes." })
    sSO.AddRow(row(sSO.frame, "Slot Padding", soPadW))
    L.closeSection(sSO)

    ---------------------------------------------------------------------------
    -- OPEN SETTINGS (button)
    ---------------------------------------------------------------------------
    L.headerAt("Open Settings")
    local btnFrame = CreateFrame("Frame", nil, tabContent)
    local openBtn = GUI:CreateButton(btnFrame, "Open Character Panel", 200, 28, function()
        if not CharacterFrame:IsShown() and not InCombatLockdown() then ToggleCharacter("PaperDollFrame") end
        C_Timer.After(0.1, function()
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
