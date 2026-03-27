local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local QUICore = ns.Addon
local UIKit = ns.UIKit

-- Local references for shared infrastructure
local CreateScrollableContent = Shared.CreateScrollableContent
local CreateWrappedLabel = Shared.CreateWrappedLabel

local GetCore = ns.Helpers.GetCore

--------------------------------------------------------------------------------
-- Helper: Create a scrollable text box container
--------------------------------------------------------------------------------
local function CreateScrollableTextBox(parent, height, text)
    return GUI:CreateScrollableTextBox(parent, height, text)
end

local function ApplyImportSurface(frame, bgColor, borderColor)
    if not frame then return end

    if not frame.bg then
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints()
        frame.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UIKit and UIKit.DisablePixelSnap then
            UIKit.DisablePixelSnap(frame.bg)
        end
    end
    frame.bg:SetVertexColor((bgColor or C.bg)[1], (bgColor or C.bg)[2], (bgColor or C.bg)[3], (bgColor or C.bg)[4] or 1)

    if UIKit and UIKit.CreateBackdropBorder then
        frame.Border = UIKit.CreateBackdropBorder(
            frame,
            1,
            (borderColor or C.border)[1],
            (borderColor or C.border)[2],
            (borderColor or C.border)[3],
            (borderColor or C.border)[4] or 1
        )
    end
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    button:EnableMouse(enabled and true or false)
    button:SetAlpha(enabled and 1 or 0.45)
    if button.text then
        local color = enabled and C.text or C.textMuted
        button.text:SetTextColor(color[1], color[2], color[3], 1)
    end
end

local function SetImportCheckboxEnabled(checkbox, enabled)
    if not checkbox then return end
    if checkbox.box then
        checkbox.box:EnableMouse(enabled and true or false)
    end
    checkbox:SetAlpha(enabled and 1 or 0.45)
    if checkbox.label then
        local color = enabled and C.text or C.textMuted
        checkbox.label:SetTextColor(color[1], color[2], color[3], 1)
    end
end

local function CreateImportBanner(parent, title, message, titleColor, bgColor, borderColor, bodyColor)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", 0, 0)
    frame:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    ApplyImportSurface(frame, bgColor or {0.08, 0.1, 0.14, 0.95}, borderColor or C.border)

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetFont(GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF", 12, "")
    titleText:SetTextColor(
        (titleColor or C.accentLight)[1],
        (titleColor or C.accentLight)[2],
        (titleColor or C.accentLight)[3],
        (titleColor or C.accentLight)[4] or 1
    )
    titleText:SetText(title or "")
    titleText:SetPoint("TOPLEFT", 10, -8)

    local body = CreateWrappedLabel(frame, message or "", 11, bodyColor or C.textMuted)
    body:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    body:SetPoint("RIGHT", frame, "RIGHT", -10, 0)

    local height = (body:GetStringHeight() or 14) + 34
    frame:SetHeight(height)
    return frame, height
end

--------------------------------------------------------------------------------
-- SUB-TAB BUILDER: Import/Export (user profile import/export)
--------------------------------------------------------------------------------
local function BuildImportExportTab(tabContent)
    local y = -10
    local PAD = 10

    GUI:SetSearchContext({tabIndex = 14, tabName = "Import & Export Strings", subTabIndex = 1, subTabName = "Import/Export"})

    local info = GUI:CreateLabel(tabContent, "Import and export QUI profiles", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    local validationNote = GUI:CreateLabel(tabContent, "Import now validates payload structure and may reject incompatible or corrupted strings.", 10, C.textMuted)
    validationNote:SetPoint("TOPLEFT", PAD, y)
    validationNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    validationNote:SetJustifyH("LEFT")
    y = y - 20

    -- Export Section Header
    local exportHeader = GUI:CreateSectionHeader(tabContent, "Export Current Profile")
    exportHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - exportHeader.gap

    -- Export text box
    local exportContainer = CreateScrollableTextBox(tabContent, 100, "")
    exportContainer:SetPoint("TOPLEFT", PAD, y)
    exportContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    local exportEditBox = exportContainer.editBox
    exportEditBox:SetTextColor(0.8, 0.85, 0.9, 1)
    exportEditBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    -- Populate export string
    local function RefreshExportString()
        local core = GetCore()
        if core and core.ExportProfileToString then
            local str = core:ExportProfileToString()
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

    -- Import text box (user pastes string here)
    local importContainer = CreateScrollableTextBox(tabContent, 100, "")
    importContainer:SetPoint("TOPLEFT", PAD, y)
    importContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    importContainer:EnableMouse(true)
    local importEditBox = importContainer.editBox
    importEditBox:SetTextColor(0.8, 0.85, 0.9, 1)
    importContainer:SetScript("OnMouseDown", function()
        importEditBox:SetFocus()
    end)

    y = y - 115

    local analysisNote = CreateWrappedLabel(
        tabContent,
        "Paste a QUI profile string, analyze it, then choose which categories to import. Unselected categories will stay as they are in your current profile.",
        10,
        C.textMuted
    )
    analysisNote:SetPoint("TOPLEFT", PAD, y)
    analysisNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - (analysisNote:GetStringHeight() or 28) - 12

    local analysisState = {
        preview = nil,
        selected = {},
        checkboxByID = {},
    }

    local previewHost = CreateFrame("Frame", nil, tabContent)
    local previewTopY = y - 40
    previewHost:SetPoint("TOPLEFT", PAD, previewTopY)
    previewHost:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    previewHost:SetHeight(10)

    local function ShowReloadPrompt(message)
        GUI:ShowConfirmation({
            title = "Reload UI?",
            message = message or "Import complete. Reload UI to apply all changes?",
            acceptText = "Reload",
            cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end

    local function PrintImportResult(ok, message)
        local printFeedback = (Shared and Shared.PrintImportFeedback) or ns.PrintImportFeedback
        if printFeedback then
            printFeedback(ok, message, false)
        elseif ok then
            print("|cff34D399QUI:|r " .. (message or "Import successful"))
        else
            print("|cffff4d4dQUI:|r Import failed: " .. tostring(message or "Unknown error"))
        end
    end

    local function GetSelectedCategoryIDs()
        if not analysisState.preview or type(analysisState.preview.categories) ~= "table" then
            return {}
        end

        local selectedIDs = {}
        local function CollectSelected(categories, parentSelected)
            for _, category in ipairs(categories or {}) do
                local isSelected = category.available and analysisState.selected[category.id] and not parentSelected
                if isSelected then
                    selectedIDs[#selectedIDs + 1] = category.id
                end
                if type(category.children) == "table" then
                    CollectSelected(category.children, isSelected)
                end
            end
        end
        CollectSelected(analysisState.preview.categories, false)
        return selectedIDs
    end

    local function UpdateActionButtons()
        local hasPreview = analysisState.preview and true or false
        local selectedIDs = GetSelectedCategoryIDs()
        SetButtonEnabled(analysisState.importSelectedBtn, hasPreview and #selectedIDs > 0)
        SetButtonEnabled(analysisState.importEverythingBtn, hasPreview)
    end

    local function UpdateCategoryCheckboxStates()
        local function ApplyState(categories, parentSelected)
            for _, category in ipairs(categories or {}) do
                local checkbox = analysisState.checkboxByID[category.id]
                if checkbox then
                    SetImportCheckboxEnabled(checkbox, category.available and not parentSelected)
                end

                if type(category.children) == "table" then
                    ApplyState(category.children, parentSelected or (analysisState.selected[category.id] and category.available))
                end
            end
        end

        if analysisState.preview and type(analysisState.preview.categories) == "table" then
            ApplyState(analysisState.preview.categories, false)
        end
    end

    local function ApplySelectionPreset(mode)
        if not analysisState.preview or type(analysisState.preview.categories) ~= "table" then
            return
        end

        local function ApplyToCategories(categories, parentHasChildren)
            for _, category in ipairs(categories or {}) do
                local shouldSelect = false
                if category.available then
                    if mode == "all" then
                        shouldSelect = true
                    elseif mode == "recommended" then
                        shouldSelect = category.recommended and true or false
                        if parentHasChildren then
                            shouldSelect = false
                        end
                    end
                end

                analysisState.selected[category.id] = shouldSelect
                local checkbox = analysisState.checkboxByID[category.id]
                if checkbox and checkbox.SetValue then
                    checkbox:SetValue(shouldSelect, true)
                end

                if type(category.children) == "table" then
                    ApplyToCategories(category.children, true)
                end
            end
        end

        ApplyToCategories(analysisState.preview.categories, false)
        UpdateCategoryCheckboxStates()
        UpdateActionButtons()
    end

    local function UpdateContentHeight()
        tabContent:SetHeight(math.abs(previewTopY) + previewHost:GetHeight() + 20)
    end

    local function RenderPreview(title, message, preview, isError)
        if previewHost.content then
            previewHost.content:Hide()
            previewHost.content:SetParent(nil)
        end

        analysisState.checkboxByID = {}
        analysisState.importSelectedBtn = nil
        analysisState.importEverythingBtn = nil

        local content = CreateFrame("Frame", nil, previewHost)
        content:SetPoint("TOPLEFT", 0, 0)
        content:SetPoint("RIGHT", previewHost, "RIGHT", 0, 0)
        content:SetHeight(1)
        previewHost.content = content

        local localY = -6
        local banner, bannerHeight = CreateImportBanner(
            content,
            title,
            message,
            isError and {1, 0.45, 0.45, 1} or C.accentLight,
            isError and {0.35, 0.08, 0.08, 0.35} or {0.07, 0.11, 0.16, 0.95},
            isError and {0.8, 0.2, 0.2, 0.7} or {C.accent[1], C.accent[2], C.accent[3], 0.6},
            isError and {0.92, 0.72, 0.72, 1} or C.textMuted
        )
        banner:SetPoint("TOPLEFT", 0, localY)
        localY = localY - bannerHeight - 14

        if preview and type(preview.categories) == "table" then
            local summaryHeader = GUI:CreateSectionHeader(content, "Selective Import")
            summaryHeader:SetPoint("TOPLEFT", 0, localY)
            localY = localY - summaryHeader.gap

            local summaryText = CreateWrappedLabel(
                content,
                "Type: " .. tostring(preview.importType or "QUI Profile") .. ". Parent checkboxes import a whole section. Indented child rows let you import specific subtabs only. Recommended keeps Theme / Fonts / Colors and Layout / Positions unchecked.",
                11,
                C.textMuted
            )
            summaryText:SetPoint("TOPLEFT", 0, localY)
            summaryText:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            localY = localY - (summaryText:GetStringHeight() or 18) - 12

            local selectAllBtn = GUI:CreateButton(content, "SELECT ALL", 110, 24, function()
                ApplySelectionPreset("all")
            end)
            selectAllBtn:SetPoint("TOPLEFT", 0, localY)

            local recommendedBtn = GUI:CreateButton(content, "RECOMMENDED", 130, 24, function()
                ApplySelectionPreset("recommended")
            end)
            recommendedBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 10, 0)

            local clearBtn = GUI:CreateButton(content, "CLEAR", 90, 24, function()
                ApplySelectionPreset("clear")
            end)
            clearBtn:SetPoint("LEFT", recommendedBtn, "RIGHT", 10, 0)
            localY = localY - 36

            local availableCount = 0

            local function RenderCategoryRow(category, indent, parentCategory)
                if not category.available and parentCategory == nil then
                    return
                end

                if category.available then
                    availableCount = availableCount + 1
                end

                local checkbox = GUI:CreateFormCheckboxOriginal(
                    content,
                    category.label,
                    category.id,
                    analysisState.selected,
                    function(value)
                        if value and parentCategory and analysisState.selected[parentCategory.id] then
                            analysisState.selected[parentCategory.id] = false
                            local parentCheckbox = analysisState.checkboxByID[parentCategory.id]
                            if parentCheckbox and parentCheckbox.SetValue then
                                parentCheckbox:SetValue(false, true)
                            end
                        end

                        UpdateCategoryCheckboxStates()
                        UpdateActionButtons()
                    end
                )
                checkbox:SetPoint("TOPLEFT", indent, localY)
                checkbox:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                analysisState.checkboxByID[category.id] = checkbox

                local descColor = category.available and C.textMuted or C.warning
                local descText = category.description or ""
                if not category.available then
                    descText = descText ~= "" and (descText .. " Not present in this import string.") or "Not present in this import string."
                end

                local desc = CreateWrappedLabel(content, descText, 10, descColor)
                desc:SetPoint("TOPLEFT", 208 + indent, localY - 4)
                desc:SetPoint("RIGHT", content, "RIGHT", 0, 0)

                local descHeight = desc:GetStringHeight() or 14
                local rowHeight = math.max(28, descHeight + 8)
                localY = localY - rowHeight - 4

                if type(category.children) == "table" then
                    for _, child in ipairs(category.children) do
                        RenderCategoryRow(child, indent + 18, category)
                    end
                end
            end

            for _, category in ipairs(preview.categories) do
                RenderCategoryRow(category, 0, nil)
            end

            if availableCount == 0 then
                local noCategories = CreateWrappedLabel(
                    content,
                    "No selective categories were detected in this string. Try importing everything or use a different QUI profile string.",
                    11,
                    C.textMuted
                )
                noCategories:SetPoint("TOPLEFT", 0, localY)
                noCategories:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                localY = localY - (noCategories:GetStringHeight() or 18) - 12
            end

            local actionNote = CreateWrappedLabel(
                content,
                "Import Selected keeps all unchecked categories from your current profile. If a parent section is checked, its child rows are ignored. Import Everything replaces the whole profile, just like the old importer.",
                10,
                C.textMuted
            )
            actionNote:SetPoint("TOPLEFT", 0, localY)
            actionNote:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            localY = localY - (actionNote:GetStringHeight() or 18) - 14

            analysisState.importSelectedBtn = GUI:CreateButton(content, "IMPORT SELECTED", 170, 28, function()
                local selectedIDs = GetSelectedCategoryIDs()
                if #selectedIDs == 0 then
                    return
                end

                local core = GetCore()
                if not core or not core.ImportProfileSelectionFromString then
                    print("|cffff0000QUI: QUICore not available for selective import.|r")
                    return
                end

                local ok, err = core:ImportProfileSelectionFromString(importEditBox:GetText(), selectedIDs)
                PrintImportResult(ok, err)
                if ok then
                    ShowReloadPrompt("Selected profile settings imported. Reload UI to fully apply the changes?")
                end
            end)
            analysisState.importSelectedBtn:SetPoint("TOPLEFT", 0, localY)

            analysisState.importEverythingBtn = GUI:CreateButton(content, "IMPORT EVERYTHING", 180, 28, function()
                GUI:ShowConfirmation({
                    title = "Import Entire Profile?",
                    message = "Replace your current profile with every setting from this string?",
                    warningText = "This overwrites the whole profile.",
                    acceptText = "Import Everything",
                    cancelText = "Cancel",
                    isDestructive = true,
                    onAccept = function()
                        local core = GetCore()
                        if not core or not core.ImportProfileFromString then
                            print("|cffff0000QUI: QUICore not available for import.|r")
                            return
                        end

                        local ok, err = core:ImportProfileFromString(importEditBox:GetText())
                        PrintImportResult(ok, err)
                        if ok then
                            ShowReloadPrompt("Full profile imported. Reload UI to fully apply the changes?")
                        end
                    end,
                })
            end)
            analysisState.importEverythingBtn:SetPoint("LEFT", analysisState.importSelectedBtn, "RIGHT", 10, 0)
            localY = localY - 40

            UpdateCategoryCheckboxStates()
            UpdateActionButtons()
        end

        previewHost:SetHeight(math.abs(localY) + 8)
        UpdateContentHeight()
    end

    local function ClearAnalysis(message, isError)
        analysisState.preview = nil
        analysisState.selected = {}
        RenderPreview(
            isError and "Import Analysis Failed" or "Analyze Import",
            message or "Paste a QUI profile string and click Analyze Import to choose what to import.",
            nil,
            isError
        )
    end

    local analyzeBtn = GUI:CreateButton(tabContent, "ANALYZE IMPORT", 160, 28, function()
        local core = GetCore()
        if not core or not core.AnalyzeProfileImportString then
            ClearAnalysis("QUICore is not available for import analysis.", true)
            return
        end

        local ok, result = core:AnalyzeProfileImportString(importEditBox:GetText())
        if not ok then
            ClearAnalysis(result or "Import analysis failed.", true)
            return
        end

        analysisState.preview = result
        analysisState.selected = {}
        for _, category in ipairs(result.categories or {}) do
            if category.available and category.recommended then
                analysisState.selected[category.id] = true
            end
        end

        RenderPreview(
            "Import Ready",
            "Choose the parts of the profile you want to import. Leave categories unchecked to preserve your current settings in those areas.",
            result,
            false
        )
    end)
    analyzeBtn:SetPoint("TOPLEFT", PAD, y)

    local analyzeHint = GUI:CreateLabel(tabContent, "Analyze first, then import selected parts or the whole profile.", 11, C.textMuted)
    analyzeHint:SetPoint("LEFT", analyzeBtn, "RIGHT", 12, 0)

    importEditBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput and analysisState.preview then
            ClearAnalysis("Import string changed. Analyze it again before importing.", false)
        end
    end)

    ClearAnalysis("Paste a QUI profile string and click Analyze Import to choose what to import.", false)
end

--------------------------------------------------------------------------------
-- SUB-TAB BUILDER: Quazii's Strings (preset import strings)
--------------------------------------------------------------------------------
local function BuildQuaziiStringsTab(tabContent)
    local PAD = 10
    local BOX_HEIGHT = 70
    local SECTION_HEIGHT = BOX_HEIGHT + 8 + 24 + 12  -- textbox + gap + button + pad
    local CreateCollapsiblePage = Shared.CreateCollapsiblePage

    GUI:SetSearchContext({tabIndex = 14, tabName = "Import & Export Strings", subTabIndex = 2, subTabName = "Quazii's Strings"})

    -- Disclaimer banner
    local warnBg = CreateFrame("Frame", nil, tabContent)
    warnBg:SetPoint("TOPLEFT", PAD, -10)
    warnBg:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    ApplyImportSurface(warnBg, {0.5, 0.25, 0.0, 0.25}, {0.961, 0.620, 0.043, 0.6})

    local warnTitle = warnBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warnTitle:SetFont(GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF", 12, "")
    warnTitle:SetTextColor(0.961, 0.620, 0.043)
    warnTitle:SetText("Warning: These strings are outdated")
    warnTitle:SetPoint("TOPLEFT", 10, -8)

    local warnText = warnBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warnText:SetFont(GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF", 11, "")
    warnText:SetTextColor(0.8, 0.75, 0.65)
    warnText:SetText("These profile strings may no longer match the current version of QUI and could cause unexpected issues. The Edit Mode string in particular may conflict with QUI's skinning and anchoring. Use with caution \226\128\148 for a reliable starting point, use the Edit Mode string on the Welcome tab instead.")
    warnText:SetPoint("TOPLEFT", warnTitle, "BOTTOMLEFT", 0, -4)
    warnText:SetPoint("RIGHT", warnBg, "RIGHT", -10, 0)
    warnText:SetJustifyH("LEFT")
    warnText:SetWordWrap(true)

    warnBg:SetScript("OnShow", function(self)
        C_Timer.After(0, function()
            local textHeight = warnText:GetStringHeight() or 14
            self:SetHeight(textHeight + 32)
        end)
    end)
    warnBg:SetHeight(60)

    -- Store all text boxes for clearing selections
    local allTextBoxes = {}

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

    local sections, relayout, CreateCollapsible = CreateCollapsiblePage(tabContent, PAD, -78)

    -- Helper to build a string section body
    local function BuildStringSection(body, importKey)
        local str = ""
        if _G.QUI and _G.QUI.imports and _G.QUI.imports[importKey] then
            str = _G.QUI.imports[importKey].data or ""
        end

        local container = CreateScrollableTextBox(body, BOX_HEIGHT, str)
        container:SetPoint("TOPLEFT", 0, -4)
        container:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        table.insert(allTextBoxes, container.editBox)

        local btn = GUI:CreateButton(body, "SELECT ALL", 120, 24, function()
            selectOnly(container.editBox)
        end)
        btn:SetPoint("TOPLEFT", 0, -(BOX_HEIGHT + 12))

        local tip = GUI:CreateLabel(body, "then press Ctrl+C to copy", 11, C.textMuted)
        tip:SetPoint("LEFT", btn, "RIGHT", 10, 0)
    end

    CreateCollapsible("Details! String", SECTION_HEIGHT, function(body) BuildStringSection(body, "QuaziiDetails") end)
    CreateCollapsible("Plater String", SECTION_HEIGHT, function(body) BuildStringSection(body, "Plater") end)
    CreateCollapsible("Platynator String", SECTION_HEIGHT, function(body) BuildStringSection(body, "Platynator") end)
    CreateCollapsible("QUI Import/Export String - Default Profile", SECTION_HEIGHT, function(body) BuildStringSection(body, "QUIProfile") end)
    CreateCollapsible("QUI Import/Export String - Dark Mode", SECTION_HEIGHT, function(body) BuildStringSection(body, "QUIProfileDarkMode") end)
    CreateCollapsible("Quazii Edit Mode String", SECTION_HEIGHT, function(body) BuildStringSection(body, "EditMode") end)

    relayout()
end

--------------------------------------------------------------------------------
-- PAGE: QUI Import/Export (with sub-tabs)
--------------------------------------------------------------------------------
local function CreateImportExportPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    GUI:CreateSubTabs(content, {
        {name = "Import/Export", builder = BuildImportExportTab},
        {name = "Quazii's Strings", builder = BuildQuaziiStringsTab},
    })

    content:SetHeight(550)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_ImportOptions = {
    CreateImportExportPage = CreateImportExportPage,
    BuildImportExportTab = BuildImportExportTab,
    BuildQuaziiStringsTab = BuildQuaziiStringsTab,
}
