local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

-- Local references for shared infrastructure
local CreateScrollableContent = Shared.CreateScrollableContent

--------------------------------------------------------------------------------
-- Helper: Create a scrollable text box container
--------------------------------------------------------------------------------
local function CreateScrollableTextBox(parent, height, text)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetHeight(height)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(0.1, 0.1, 0.1, 1)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- ScrollFrame to contain the EditBox
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

    -- Style the scroll bar
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName().."ScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 18)
    end

    -- EditBox inside ScrollFrame
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() or 400)
    editBox:SetText(text or "")
    editBox:SetCursorPosition(0)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Update width when container is sized
    container:SetScript("OnSizeChanged", function(self)
        editBox:SetWidth(self:GetWidth() - 36)
    end)

    scrollFrame:SetScrollChild(editBox)

    container.editBox = editBox
    container.scrollFrame = scrollFrame
    return container
end

--------------------------------------------------------------------------------
-- SUB-TAB BUILDER: Import/Export (user profile import/export)
--------------------------------------------------------------------------------
local function BuildImportExportTab(tabContent)
    local y = -10
    local PAD = 10

    GUI:SetSearchContext({tabIndex = 12, tabName = "QUI Import/Export", subTabIndex = 1, subTabName = "Import/Export"})

    local info = GUI:CreateLabel(tabContent, "Import and export QUI profiles", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    -- Export Section Header
    local exportHeader = GUI:CreateSectionHeader(tabContent, "Export Current Profile")
    exportHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - exportHeader.gap

    -- Create a scroll frame for the export box
    local exportScroll = CreateFrame("ScrollFrame", nil, tabContent, "UIPanelScrollFrameTemplate")
    exportScroll:SetPoint("TOPLEFT", PAD, y)
    exportScroll:SetPoint("TOPRIGHT", -PAD - 20, y)
    exportScroll:SetHeight(100)

    local exportEditBox = CreateFrame("EditBox", nil, exportScroll)
    exportEditBox:SetMultiLine(true)
    exportEditBox:SetAutoFocus(false)
    exportEditBox:SetFont(GUI.FONT_PATH, 11, "")
    exportEditBox:SetTextColor(0.8, 0.85, 0.9, 1)
    exportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    exportEditBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    exportScroll:SetScrollChild(exportEditBox)

    -- Set width dynamically when scroll frame is sized
    exportScroll:SetScript("OnSizeChanged", function(self)
        exportEditBox:SetWidth(self:GetWidth() - 10)
    end)

    -- Background for export box
    local exportBg = tabContent:CreateTexture(nil, "BACKGROUND")
    exportBg:SetPoint("TOPLEFT", exportScroll, -5, 5)
    exportBg:SetPoint("BOTTOMRIGHT", exportScroll, 25, -5)
    exportBg:SetColorTexture(0.05, 0.07, 0.1, 0.9)

    -- Border for export box
    local exportBorder = CreateFrame("Frame", nil, tabContent, "BackdropTemplate")
    exportBorder:SetPoint("TOPLEFT", exportScroll, -6, 6)
    exportBorder:SetPoint("BOTTOMRIGHT", exportScroll, 26, -6)
    exportBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    exportBorder:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    -- Populate export string
    local function RefreshExportString()
        local QUICore = _G.QUI and _G.QUI.QUICore
        if QUICore and QUICore.ExportProfileToString then
            local str = QUICore:ExportProfileToString()
            exportEditBox:SetText(str or "Error generating export string")
        else
            exportEditBox:SetText("QUICore not available")
        end
    end
    RefreshExportString()

    y = y - 115

    -- SELECT ALL button (themed)
    local selectBtn = GUI:CreateButton(tabContent, "SELECT ALL", 120, 28, function()
        RefreshExportString()
        exportEditBox:SetFocus()
        exportEditBox:HighlightText()
    end)
    selectBtn:SetPoint("TOPLEFT", PAD, y)

    -- Hint text
    local copyHint = GUI:CreateLabel(tabContent, "then press Ctrl+C to copy", 11, C.textMuted)
    copyHint:SetPoint("LEFT", selectBtn, "RIGHT", 12, 0)

    y = y - 50

    -- Import Section Header
    local importHeader = GUI:CreateSectionHeader(tabContent, "Import Profile String")
    importHeader:SetPoint("TOPLEFT", PAD, y)

    -- Paste hint next to header
    local pasteHint = GUI:CreateLabel(tabContent, "press Ctrl+V to paste", 11, C.textMuted)
    pasteHint:SetPoint("LEFT", importHeader, "RIGHT", 12, 0)

    y = y - importHeader.gap

    -- Import EditBox (user pastes string here)
    local importScroll = CreateFrame("ScrollFrame", nil, tabContent, "UIPanelScrollFrameTemplate")
    importScroll:SetPoint("TOPLEFT", PAD, y)
    importScroll:SetPoint("TOPRIGHT", -PAD - 20, y)
    importScroll:SetHeight(100)

    local importEditBox = CreateFrame("EditBox", nil, importScroll)
    importEditBox:SetMultiLine(true)
    importEditBox:SetAutoFocus(false)
    importEditBox:SetFont(GUI.FONT_PATH, 11, "")
    importEditBox:SetTextColor(0.8, 0.85, 0.9, 1)
    importEditBox:SetHeight(100)
    importEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    importScroll:SetScrollChild(importEditBox)

    -- Set width dynamically when scroll frame is sized
    importScroll:SetScript("OnSizeChanged", function(self)
        importEditBox:SetWidth(self:GetWidth() - 10)
    end)

    -- Background for import box - make it clickable to focus the editbox
    local importBg = CreateFrame("Button", nil, tabContent)
    importBg:SetPoint("TOPLEFT", importScroll, -5, 5)
    importBg:SetPoint("BOTTOMRIGHT", importScroll, 25, -5)
    importBg:SetScript("OnClick", function() importEditBox:SetFocus() end)

    local importBgTex = importBg:CreateTexture(nil, "BACKGROUND")
    importBgTex:SetAllPoints()
    importBgTex:SetColorTexture(0.05, 0.07, 0.1, 0.9)

    -- Border for import box
    local importBorder = CreateFrame("Frame", nil, tabContent, "BackdropTemplate")
    importBorder:SetPoint("TOPLEFT", importScroll, -6, 6)
    importBorder:SetPoint("BOTTOMRIGHT", importScroll, 26, -6)
    importBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    importBorder:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    y = y - 115

    -- IMPORT AND RELOAD button (themed)
    local importBtn = GUI:CreateButton(tabContent, "IMPORT AND RELOAD", 200, 28, function()
        local str = importEditBox:GetText()
        if not str or str == "" then
            print("|cffff0000QUI: No import string provided.|r")
            return
        end
        local QUICore = _G.QUI and _G.QUI.QUICore
        if QUICore and QUICore.ImportProfileFromString then
            local ok, err = QUICore:ImportProfileFromString(str)
            if ok then
                print("|cff34D399QUI:|r Profile imported successfully!")
                print("|cff34D399QUI:|r Please type |cFFFFD700/reload|r to apply changes.")
            else
                print("|cffff0000QUI: Import failed: " .. (err or "Unknown error") .. "|r")
            end
        else
            print("|cffff0000QUI: QUICore not available for import.|r")
        end
    end)
    importBtn:SetPoint("TOPLEFT", PAD, y)
    y = y - 40

    tabContent:SetHeight(math.abs(y) + 20)
end

--------------------------------------------------------------------------------
-- SUB-TAB BUILDER: Quazii's Strings (preset import strings)
--------------------------------------------------------------------------------
local function BuildQuaziiStringsTab(tabContent)
    local y = -10
    local PAD = 10
    local BOX_HEIGHT = 70

    GUI:SetSearchContext({tabIndex = 12, tabName = "QUI Import/Export", subTabIndex = 2, subTabName = "Quazii's Strings"})

    local info = GUI:CreateLabel(tabContent, "Quazii's personal import strings - select all and copy", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    -- Store all text boxes for clearing selections
    local allTextBoxes = {}

    -- Helper to clear all selections except the target
    local function selectOnly(targetEditBox)
        for _, editBox in ipairs(allTextBoxes) do
            if editBox ~= targetEditBox then
                editBox:ClearFocus()
                editBox:HighlightText(0, 0)
            end
        end
        targetEditBox:SetFocus()
        targetEditBox:HighlightText()
    end

    -- =====================================================
    -- EDIT MODE STRING
    -- =====================================================
    local editModeHeader = GUI:CreateSectionHeader(tabContent, "Quazii Edit Mode String")
    editModeHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - editModeHeader.gap

    local editModeString = ""
    if _G.QUI and _G.QUI.imports and _G.QUI.imports.EditMode then
        editModeString = _G.QUI.imports.EditMode.data or ""
    end

    local editModeContainer = CreateScrollableTextBox(tabContent, BOX_HEIGHT, editModeString)
    editModeContainer:SetPoint("TOPLEFT", PAD, y)
    editModeContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    table.insert(allTextBoxes, editModeContainer.editBox)

    y = y - BOX_HEIGHT - 8

    local editModeBtn = GUI:CreateButton(tabContent, "SELECT ALL", 120, 24, function()
        selectOnly(editModeContainer.editBox)
    end)
    editModeBtn:SetPoint("TOPLEFT", PAD, y)

    local editModeTip = GUI:CreateLabel(tabContent, "then press Ctrl+C to copy", 11, C.textMuted)
    editModeTip:SetPoint("LEFT", editModeBtn, "RIGHT", 10, 0)
    y = y - 40

    -- =====================================================
    -- QUI IMPORT/EXPORT STRING - DEFAULT PROFILE
    -- =====================================================
    local quiHeader = GUI:CreateSectionHeader(tabContent, "QUI Import/Export String - Default Profile")
    quiHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - quiHeader.gap

    local quiString = ""
    if _G.QUI and _G.QUI.imports and _G.QUI.imports.QUIProfile then
        quiString = _G.QUI.imports.QUIProfile.data or ""
    end

    local quiContainer = CreateScrollableTextBox(tabContent, BOX_HEIGHT, quiString)
    quiContainer:SetPoint("TOPLEFT", PAD, y)
    quiContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    table.insert(allTextBoxes, quiContainer.editBox)

    y = y - BOX_HEIGHT - 8

    local quiBtn = GUI:CreateButton(tabContent, "SELECT ALL", 120, 24, function()
        selectOnly(quiContainer.editBox)
    end)
    quiBtn:SetPoint("TOPLEFT", PAD, y)

    local quiTip = GUI:CreateLabel(tabContent, "then press Ctrl+C to copy", 11, C.textMuted)
    quiTip:SetPoint("LEFT", quiBtn, "RIGHT", 10, 0)
    y = y - 40

    -- =====================================================
    -- QUI IMPORT/EXPORT STRING - DARK MODE
    -- =====================================================
    local quiDarkHeader = GUI:CreateSectionHeader(tabContent, "QUI Import/Export String - Dark Mode")
    quiDarkHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - quiDarkHeader.gap

    local quiDarkString = ""
    if _G.QUI and _G.QUI.imports and _G.QUI.imports.QUIProfileDarkMode then
        quiDarkString = _G.QUI.imports.QUIProfileDarkMode.data or ""
    end

    local quiDarkContainer = CreateScrollableTextBox(tabContent, BOX_HEIGHT, quiDarkString)
    quiDarkContainer:SetPoint("TOPLEFT", PAD, y)
    quiDarkContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    table.insert(allTextBoxes, quiDarkContainer.editBox)

    y = y - BOX_HEIGHT - 8

    local quiDarkBtn = GUI:CreateButton(tabContent, "SELECT ALL", 120, 24, function()
        selectOnly(quiDarkContainer.editBox)
    end)
    quiDarkBtn:SetPoint("TOPLEFT", PAD, y)

    local quiDarkTip = GUI:CreateLabel(tabContent, "then press Ctrl+C to copy", 11, C.textMuted)
    quiDarkTip:SetPoint("LEFT", quiDarkBtn, "RIGHT", 10, 0)
    y = y - 40

    -- =====================================================
    -- PLATYNATOR STRING
    -- =====================================================
    local platHeader = GUI:CreateSectionHeader(tabContent, "Platynator String")
    platHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - platHeader.gap

    local platString = ""
    if _G.QUI and _G.QUI.imports and _G.QUI.imports.Platynator then
        platString = _G.QUI.imports.Platynator.data or ""
    end

    local platContainer = CreateScrollableTextBox(tabContent, BOX_HEIGHT, platString)
    platContainer:SetPoint("TOPLEFT", PAD, y)
    platContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    table.insert(allTextBoxes, platContainer.editBox)

    y = y - BOX_HEIGHT - 8

    local platBtn = GUI:CreateButton(tabContent, "SELECT ALL", 120, 24, function()
        selectOnly(platContainer.editBox)
    end)
    platBtn:SetPoint("TOPLEFT", PAD, y)

    local platTip = GUI:CreateLabel(tabContent, "then press Ctrl+C to copy", 11, C.textMuted)
    platTip:SetPoint("LEFT", platBtn, "RIGHT", 10, 0)
    y = y - 30

    tabContent:SetHeight(math.abs(y) + 20)
end

--------------------------------------------------------------------------------
-- PAGE: QUI Import/Export (with sub-tabs)
--------------------------------------------------------------------------------
local function CreateImportExportPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    local subTabs = GUI:CreateSubTabs(content, {
        {name = "Import/Export", builder = BuildImportExportTab},
        {name = "Quazii's Strings", builder = BuildQuaziiStringsTab},
    })
    subTabs:SetPoint("TOPLEFT", 5, -5)
    subTabs:SetPoint("TOPRIGHT", -5, -5)
    subTabs:SetHeight(550)

    content:SetHeight(600)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_ImportOptions = {
    CreateImportExportPage = CreateImportExportPage,
    BuildImportExportTab = BuildImportExportTab,
    BuildQuaziiStringsTab = BuildQuaziiStringsTab,
}
