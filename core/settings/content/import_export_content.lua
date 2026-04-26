local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local QUICore = ns.Addon
local UIKit = ns.UIKit
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

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

    local function NormalizeTargetProfileName(raw)
        raw = tostring(raw or "")
        raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if raw == "" then
            return nil
        end
        return raw
    end

    GUI:SetSearchContext({tabIndex = 14, tabName = "Import & Export Strings", subTabIndex = 1, subTabName = "Import/Export"})

    local info = GUI:CreateLabel(tabContent, "Import and export QUI profiles", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    local validationNote = GUI:CreateLabel(
        tabContent,
        "Import validates the decoded profile. If analysis fails, reasons are listed and you can strip incompatible settings from a temporary copy, then import the rest.",
        10,
        C.textMuted
    )
    validationNote:SetPoint("TOPLEFT", PAD, y)
    validationNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    validationNote:SetJustifyH("LEFT")
    y = y - 20

    -- Export Section Header
    Shared.CreateAccentDotLabel(tabContent, "Export Current Profile", y); y = y - 30

    local exportNote = CreateWrappedLabel(
        tabContent,
        "Generate a full profile string or export only selected categories. Selective exports use the same QUI1 profile format as full exports, so they can be pasted into the import analyzer below.",
        10,
        C.textMuted
    )
    exportNote:SetPoint("TOPLEFT", PAD, y)
    exportNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - (exportNote:GetStringHeight() or 28) - 12

    local exportState = {
        preview = nil,
        selected = {},
        checkboxByID = {},
        exportSelectedBtn = nil,
    }

    local exportEditBox

    local function FocusExportText()
        if not exportEditBox then
            return
        end
        exportEditBox:SetFocus()
        exportEditBox:HighlightText()
    end

    local function GetSelectedExportCategoryIDs()
        if not exportState.preview or type(exportState.preview.categories) ~= "table" then
            return {}
        end

        local selectedIDs = {}
        local function CollectSelected(categories, parentSelected)
            for _, category in ipairs(categories or {}) do
                local isSelected = category.available and exportState.selected[category.id] and not parentSelected
                if isSelected then
                    selectedIDs[#selectedIDs + 1] = category.id
                end
                if type(category.children) == "table" then
                    CollectSelected(category.children, isSelected)
                end
            end
        end
        CollectSelected(exportState.preview.categories, false)
        return selectedIDs
    end

    local function UpdateExportActionButtons()
        local hasPreview = exportState.preview and true or false
        local selectedIDs = GetSelectedExportCategoryIDs()
        SetButtonEnabled(exportState.exportSelectedBtn, hasPreview and #selectedIDs > 0)
    end

    local function UpdateExportCheckboxStates()
        local function ApplyState(categories, parentSelected)
            for _, category in ipairs(categories or {}) do
                local checkbox = exportState.checkboxByID[category.id]
                if checkbox then
                    SetImportCheckboxEnabled(checkbox, category.available and not parentSelected)
                end

                if type(category.children) == "table" then
                    ApplyState(category.children, parentSelected or (exportState.selected[category.id] and category.available))
                end
            end
        end

        if exportState.preview and type(exportState.preview.categories) == "table" then
            ApplyState(exportState.preview.categories, false)
        end
    end

    local function ApplyExportSelectionPreset(mode)
        if not exportState.preview or type(exportState.preview.categories) ~= "table" then
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

                exportState.selected[category.id] = shouldSelect
                local checkbox = exportState.checkboxByID[category.id]
                if checkbox and checkbox.SetValue then
                    checkbox:SetValue(shouldSelect, true)
                end

                if type(category.children) == "table" then
                    ApplyToCategories(category.children, true)
                end
            end
        end

        ApplyToCategories(exportState.preview.categories, false)
        UpdateExportCheckboxStates()
        UpdateExportActionButtons()
    end

    local function RefreshExportString(selectText)
        local core = GetCore()
        if core and core.ExportProfileToString then
            local str = core:ExportProfileToString()
            exportEditBox:SetText(str or "Error generating export string")
        else
            exportEditBox:SetText("QUICore not available")
        end

        if selectText then
            FocusExportText()
        end
    end

    local function RefreshSelectiveExportString(selectText)
        local core = GetCore()
        if not core or not core.ExportProfileSelectionToString then
            exportEditBox:SetText("QUICore not available")
            return
        end

        local selectedIDs = GetSelectedExportCategoryIDs()
        local exportString, exportErr = core:ExportProfileSelectionToString(selectedIDs)
        exportEditBox:SetText(exportString or exportErr or "Error generating export string")

        if selectText then
            FocusExportText()
        end
    end

    local exportPreview = nil
    local core = GetCore()
    if core and core.BuildProfileExportPreview then
        exportPreview = core:BuildProfileExportPreview()
    end
    exportState.preview = exportPreview

    -- Forward-declare; defined after postExportContainer is created
    local exportRelayout
    local exportCollapsibleAnchorY = y
    local exportCollapsibleSection  -- always-visible section wrapper (accent-dot label + body)

    if exportPreview and type(exportPreview.categories) == "table" then
        -- Wrapper frame containing the accent-dot header and body. Its
        -- GetHeight()/ExportRelayout use measure the whole section, matching
        -- the old CreateInlineCollapsible contract without collapsibility.
        exportCollapsibleSection = CreateFrame("Frame", nil, tabContent)
        exportCollapsibleSection:SetPoint("TOPLEFT", PAD, y)
        exportCollapsibleSection:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        Shared.CreateAccentDotLabel(exportCollapsibleSection, "Selective Export", 0)

        local body = CreateFrame("Frame", nil, exportCollapsibleSection)
        body:SetPoint("TOPLEFT", exportCollapsibleSection, "TOPLEFT", 0, -28)
        body:SetPoint("RIGHT", exportCollapsibleSection, "RIGHT", 0, 0)
        body:SetHeight(1)

        exportCollapsibleSection.RefreshContentHeight = function()
            exportCollapsibleSection:SetHeight(28 + (body:GetHeight() or 0))
        end

        local localY = -6

        local selectiveExportText = CreateWrappedLabel(
            body,
            "Parent checkboxes export a whole section. Indented child rows let you export specific subtabs only. Recommended keeps Theme / Fonts / Colors and Layout / Positions unchecked.",
            11,
            C.textMuted
        )
        selectiveExportText:SetPoint("TOPLEFT", 0, localY)
        selectiveExportText:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        localY = localY - (selectiveExportText:GetStringHeight() or 18) - 12

        local selectAllExportBtn = GUI:CreateButton(body, "SELECT ALL", 110, 24, function()
            ApplyExportSelectionPreset("all")
        end)
        selectAllExportBtn:SetPoint("TOPLEFT", 0, localY)

        local recommendedExportBtn = GUI:CreateButton(body, "RECOMMENDED", 130, 24, function()
            ApplyExportSelectionPreset("recommended")
        end)
        recommendedExportBtn:SetPoint("LEFT", selectAllExportBtn, "RIGHT", 10, 0)

        local clearExportBtn = GUI:CreateButton(body, "CLEAR", 90, 24, function()
            ApplyExportSelectionPreset("clear")
        end)
        clearExportBtn:SetPoint("LEFT", recommendedExportBtn, "RIGHT", 10, 0)
        localY = localY - 36

        local availableCount = 0

        local function RenderExportCategoryRow(category, indent, parentCategory)
            if not category.available and parentCategory == nil then
                return
            end

            if category.available then
                availableCount = availableCount + 1
            end

            local checkbox = GUI:CreateFormCheckboxOriginal(
                body,
                category.label,
                category.id,
                exportState.selected,
                function(value)
                    if value and parentCategory and exportState.selected[parentCategory.id] then
                        exportState.selected[parentCategory.id] = false
                        local parentCheckbox = exportState.checkboxByID[parentCategory.id]
                        if parentCheckbox and parentCheckbox.SetValue then
                            parentCheckbox:SetValue(false, true)
                        end
                    end

                    UpdateExportCheckboxStates()
                    UpdateExportActionButtons()
                end,
                { description = category.description or ("Include " .. category.label .. " in the exported profile string.") }
            )
            checkbox:SetPoint("TOPLEFT", indent, localY)
            checkbox:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            exportState.checkboxByID[category.id] = checkbox

            local descColor = category.available and C.textMuted or C.warning
            local descText = category.description or ""
            if not category.available then
                descText = descText ~= "" and (descText .. " Not present in the current profile.") or "Not present in the current profile."
            end

            local desc = CreateWrappedLabel(body, descText, 10, descColor)
            desc:SetPoint("TOPLEFT", 208 + indent, localY - 4)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)

            local descHeight = desc:GetStringHeight() or 14
            local rowHeight = math.max(28, descHeight + 8)
            localY = localY - rowHeight - 4

            if type(category.children) == "table" then
                for _, child in ipairs(category.children) do
                    RenderExportCategoryRow(child, indent + 18, category)
                end
            end
        end

        for _, category in ipairs(exportPreview.categories) do
            RenderExportCategoryRow(category, 0, nil)
        end

        if availableCount == 0 then
            local noCategories = CreateWrappedLabel(
                body,
                "No selective export categories are currently available in this profile.",
                11,
                C.textMuted
            )
            noCategories:SetPoint("TOPLEFT", 0, localY)
            noCategories:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            localY = localY - (noCategories:GetStringHeight() or 18) - 12
        end

        local selectiveExportActionNote = CreateWrappedLabel(
            body,
            "Export Selected writes a partial QUI1 profile string containing only the checked categories. Full Profile regenerates the complete current profile string.",
            10,
            C.textMuted
        )
        selectiveExportActionNote:SetPoint("TOPLEFT", 0, localY)
        selectiveExportActionNote:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        localY = localY - (selectiveExportActionNote:GetStringHeight() or 18) - 14

        exportState.exportSelectedBtn = GUI:CreateButton(body, "EXPORT SELECTED", 170, 28, function()
            RefreshSelectiveExportString(true)
        end)
        exportState.exportSelectedBtn:SetPoint("TOPLEFT", 0, localY)

        local fullExportBtn = GUI:CreateButton(body, "FULL PROFILE", 140, 28, function()
            RefreshExportString(true)
        end)
        fullExportBtn:SetPoint("LEFT", exportState.exportSelectedBtn, "RIGHT", 10, 0)

        localY = localY - 42

        body:SetHeight(math.abs(localY) + 8)
        body._contentHeight = math.abs(localY) + 8
        exportCollapsibleSection.RefreshContentHeight()
        ApplyExportSelectionPreset("all")

        y = y - exportCollapsibleSection:GetHeight() - 8
    end

    ---------------------------------------------------------------------------
    -- Post-export container: holds everything below the collapsible so it
    -- shifts automatically when the selective export section expands/collapses.
    ---------------------------------------------------------------------------
    local postExportContainer = CreateFrame("Frame", nil, tabContent)
    postExportContainer:SetPoint("TOPLEFT", tabContent, "TOPLEFT", 0, y)
    postExportContainer:SetPoint("RIGHT", tabContent, "RIGHT", 0, 0)
    postExportContainer:SetHeight(1)

    -- Reset y for container-local positioning
    y = 0

    -- Export text box
    local exportContainer = CreateScrollableTextBox(postExportContainer, 100, "")
    exportContainer:SetPoint("TOPLEFT", PAD, y)
    exportContainer:SetPoint("RIGHT", postExportContainer, "RIGHT", -PAD, 0)
    exportEditBox = exportContainer.editBox
    exportEditBox:SetTextColor(0.8, 0.85, 0.9, 1)
    exportEditBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    RefreshExportString()

    y = y - 115

    local copyHint = GUI:CreateLabel(postExportContainer, "press Ctrl+C to copy the generated export string", 11, C.textMuted)
    copyHint:SetPoint("TOPLEFT", PAD, y)

    y = y - 28

    -- Import Section Header (with a paste hint rendered next to the label)
    local importHeader = Shared.CreateAccentDotLabel(postExportContainer, "Import Profile String", y)

    -- Paste hint next to header
    local pasteHint = GUI:CreateLabel(postExportContainer, "press Ctrl+V to paste", 11, C.textMuted)
    pasteHint:SetPoint("LEFT", importHeader, "RIGHT", 12, 0)

    y = y - 30

    -- Import text box (user pastes string here)
    local importContainer = CreateScrollableTextBox(postExportContainer, 100, "")
    importContainer:SetPoint("TOPLEFT", PAD, y)
    importContainer:SetPoint("RIGHT", postExportContainer, "RIGHT", -PAD, 0)
    importContainer:EnableMouse(true)
    local importEditBox = importContainer.editBox
    importEditBox:SetTextColor(0.8, 0.85, 0.9, 1)
    importContainer:SetScript("OnMouseDown", function()
        importEditBox:SetFocus()
    end)

    y = y - 110

    local targetProfileInput = GUI:CreateFormEditBox(postExportContainer, "Save As Profile", nil, nil, nil, {
        width = 240,
        commitOnEnter = false,
        commitOnFocusLost = false,
        maxLetters = 64,
        onEscapePressed = function(self) self:ClearFocus() end,
    }, { description = "Optional. Leave empty to overwrite the active profile, or enter a name to import into a named profile instead." })
    targetProfileInput:SetPoint("TOPLEFT", PAD, y)
    targetProfileInput:SetPoint("RIGHT", postExportContainer, "RIGHT", -PAD, 0)

    local targetProfileHint = CreateWrappedLabel(
        postExportContainer,
        "Optional. Leave this empty to overwrite your current active profile. Enter a name to import into that profile instead.",
        10,
        C.textMuted
    )
    targetProfileHint:SetPoint("TOPLEFT", PAD, y - 30)
    targetProfileHint:SetPoint("RIGHT", postExportContainer, "RIGHT", -PAD, 0)
    y = y - (targetProfileHint:GetStringHeight() or 28) - 42

    local function GetTargetProfileName()
        if not targetProfileInput or not targetProfileInput.editBox then
            return nil
        end
        return NormalizeTargetProfileName(targetProfileInput.editBox:GetText())
    end

    local analysisNote = CreateWrappedLabel(
        postExportContainer,
        "Paste a QUI profile string, analyze it, then choose which categories to import. Unselected categories stay as they are in the target profile.",
        10,
        C.textMuted
    )
    analysisNote:SetPoint("TOPLEFT", PAD, y)
    analysisNote:SetPoint("RIGHT", postExportContainer, "RIGHT", -PAD, 0)
    y = y - (analysisNote:GetStringHeight() or 28) - 12

    local analysisState = {
        preview = nil,
        selected = {},
        checkboxByID = {},
        --- When set, selective/full import uses this validated table instead of re-parsing the edit box (required after sanitization).
        activePayload = nil,
    }

    local previewHost = CreateFrame("Frame", nil, postExportContainer)
    local previewTopY = y - 40
    previewHost:SetPoint("TOPLEFT", PAD, previewTopY)
    previewHost:SetPoint("RIGHT", postExportContainer, "RIGHT", -PAD, 0)
    previewHost:SetHeight(10)

    -- Track the final y inside postExportContainer for height calculations
    local postExportFinalY = previewTopY

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
        local containerInternalHeight = math.abs(postExportFinalY) + previewHost:GetHeight() + 20
        postExportContainer:SetHeight(containerInternalHeight)

        local containerOffset
        if exportCollapsibleSection then
            containerOffset = math.abs(exportCollapsibleAnchorY) + exportCollapsibleSection:GetHeight() + 8
        else
            containerOffset = math.abs(exportCollapsibleAnchorY)
        end
        tabContent:SetHeight(containerOffset + containerInternalHeight + 20)
    end

    exportRelayout = function()
        local newY = exportCollapsibleAnchorY
        if exportCollapsibleSection then
            newY = exportCollapsibleAnchorY - exportCollapsibleSection:GetHeight() - 8
        end
        postExportContainer:ClearAllPoints()
        postExportContainer:SetPoint("TOPLEFT", tabContent, "TOPLEFT", 0, newY)
        postExportContainer:SetPoint("RIGHT", tabContent, "RIGHT", 0, 0)
        UpdateContentHeight()
    end

    local function RenderPreview(title, message, preview, isError, validationDetail)
        previewHost._importCollapsible = nil

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

        if isError and type(validationDetail) == "table" and type(validationDetail.errors) == "table" and #validationDetail.errors > 0 then
            local stripBtn = GUI:CreateButton(content, "STRIP incompatible settings & re-analyze", 300, 28, function()
                local core = GetCore()
                if not core or not core.SanitizeProfileImportString or not core.BuildProfileImportPreviewFromPayload then
                    print("|cffff0000QUI: Profile sanitization is not available.|r")
                    return
                end
                local ok, payload, prefix, stripped, err = core:SanitizeProfileImportString(importEditBox:GetText())
                if not ok then
                    local msg = err
                        or "Could not produce a compatible profile from this string."
                    if type(msg) ~= "string" then
                        msg = tostring(msg)
                    end
                    ClearAnalysis(msg, true)
                    return
                end
                local newPreview = core:BuildProfileImportPreviewFromPayload(payload, prefix)
                if not newPreview then
                    ClearAnalysis("Sanitization succeeded but preview could not be built.", true)
                    return
                end
                if type(stripped) == "table" and #stripped > 0 then
                    newPreview.sanitizationLog = stripped
                end
                analysisState.preview = newPreview
                analysisState.activePayload = payload
                analysisState.selected = {}
                for _, category in ipairs(newPreview.categories or {}) do
                    if category.available and category.recommended then
                        analysisState.selected[category.id] = true
                    end
                end
                local note = "Incompatible keys were removed so this string matches what the current QUI version expects. Review categories below, then import. Other settings from the string are unchanged."
                RenderPreview("Import ready (sanitized)", note, newPreview, false, nil)
            end)
            stripBtn:SetPoint("TOPLEFT", 0, localY)
            localY = localY - 36

            local stripHint = CreateWrappedLabel(
                content,
                "Removes only the listed settings from a temporary copy of the import—your pasted text is not modified. Defaults will apply for anything removed.",
                10,
                C.textMuted
            )
            stripHint:SetPoint("TOPLEFT", 0, localY)
            stripHint:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            localY = localY - (stripHint:GetStringHeight() or 28) - 10
        end

        if preview and type(preview.sanitizationLog) == "table" and #preview.sanitizationLog > 0 then
            local removedText = table.concat(preview.sanitizationLog, "\n")
            local sanBanner, sanH = CreateImportBanner(
                content,
                "Removed incompatible settings",
                removedText,
                {0.961, 0.620, 0.043, 1},
                {0.25, 0.18, 0.05, 0.5},
                {0.961, 0.620, 0.043, 0.5},
                {0.85, 0.8, 0.72, 1}
            )
            sanBanner:SetPoint("TOPLEFT", 0, localY)
            localY = localY - sanH - 14
        end

        if preview and type(preview.categories) == "table" then
            -- "Import Everything" button above the collapsible for quick access
            analysisState.importEverythingBtn = GUI:CreateButton(content, "IMPORT EVERYTHING", 180, 28, function()
                local targetProfileName = GetTargetProfileName()
                GUI:ShowConfirmation({
                    title = targetProfileName and "Import Into Profile?" or "Import Entire Profile?",
                    message = targetProfileName
                        and ("Replace every setting in profile '%s' with this import string?"):format(targetProfileName)
                        or "Replace your current profile with every setting from this string?",
                    warningText = targetProfileName
                        and "If that profile already exists, its settings will be overwritten."
                        or "This overwrites the whole current profile.",
                    acceptText = targetProfileName and "Import Into Profile" or "Import Everything",
                    cancelText = "Cancel",
                    isDestructive = true,
                    onAccept = function()
                        local core = GetCore()
                        if not core or not core.ImportProfileFromString then
                            print("|cffff0000QUI: QUICore not available for import.|r")
                            return
                        end

                        local ok, err
                        if analysisState.activePayload then
                            ok, err = core:ImportProfileFromValidatedPayload(
                                analysisState.activePayload,
                                targetProfileName
                            )
                        else
                            ok, err = core:ImportProfileFromString(importEditBox:GetText(), targetProfileName)
                        end
                        PrintImportResult(ok, err)
                        if ok then
                            ShowReloadPrompt("Full profile imported. Reload UI to fully apply the changes?")
                        end
                    end,
                })
            end)
            analysisState.importEverythingBtn:SetPoint("TOPLEFT", 0, localY)
            localY = localY - 36

            local orLabel = GUI:CreateLabel(content, "or", 11, C.textMuted)
            orLabel:SetPoint("TOPLEFT", 0, localY)
            localY = localY - 20

            local importSectionStartY = localY

            -- Always-visible "Selective Import" section: accent-dot header +
            -- inline body. Replaces CreateInlineCollapsible for style parity
            -- with the new-standard settings panels (Keybind Mode, Third-party).
            local importCollapsibleSection = CreateFrame("Frame", nil, content)
            importCollapsibleSection:SetPoint("TOPLEFT", 0, localY)
            importCollapsibleSection:SetPoint("RIGHT", content, "RIGHT", 0, 0)

            Shared.CreateAccentDotLabel(importCollapsibleSection, "Selective Import", 0)

            local importBody = CreateFrame("Frame", nil, importCollapsibleSection)
            importBody:SetPoint("TOPLEFT", importCollapsibleSection, "TOPLEFT", 0, -28)
            importBody:SetPoint("RIGHT", importCollapsibleSection, "RIGHT", 0, 0)
            importBody:SetHeight(1)

            importCollapsibleSection.RefreshContentHeight = function()
                importCollapsibleSection:SetHeight(28 + (importBody:GetHeight() or 0))
            end

            previewHost._importCollapsible = importCollapsibleSection

            local innerY = -6

            local summaryText = CreateWrappedLabel(
                importBody,
                "Type: " .. tostring(preview.importType or "QUI Profile") .. ". Parent checkboxes import a whole section. Indented child rows let you import specific subtabs only. Recommended keeps Theme / Fonts / Colors and Layout / Positions unchecked.",
                11,
                C.textMuted
            )
            summaryText:SetPoint("TOPLEFT", 0, innerY)
            summaryText:SetPoint("RIGHT", importBody, "RIGHT", 0, 0)
            innerY = innerY - (summaryText:GetStringHeight() or 18) - 12

            local selectAllBtn = GUI:CreateButton(importBody, "SELECT ALL", 110, 24, function()
                ApplySelectionPreset("all")
            end)
            selectAllBtn:SetPoint("TOPLEFT", 0, innerY)

            local recommendedBtn = GUI:CreateButton(importBody, "RECOMMENDED", 130, 24, function()
                ApplySelectionPreset("recommended")
            end)
            recommendedBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 10, 0)

            local clearBtn = GUI:CreateButton(importBody, "CLEAR", 90, 24, function()
                ApplySelectionPreset("clear")
            end)
            clearBtn:SetPoint("LEFT", recommendedBtn, "RIGHT", 10, 0)
            innerY = innerY - 36

            local availableCount = 0

            local function RenderCategoryRow(category, indent, parentCategory)
                if not category.available and parentCategory == nil then
                    return
                end

                if category.available then
                    availableCount = availableCount + 1
                end

                local checkbox = GUI:CreateFormCheckboxOriginal(
                    importBody,
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
                    end,
                    { description = category.description or ("Import the " .. category.label .. " section of the analyzed profile into your current profile.") }
                )
                checkbox:SetPoint("TOPLEFT", indent, innerY)
                checkbox:SetPoint("RIGHT", importBody, "RIGHT", 0, 0)
                analysisState.checkboxByID[category.id] = checkbox

                local descColor = category.available and C.textMuted or C.warning
                local descText = category.description or ""
                if not category.available then
                    descText = descText ~= "" and (descText .. " Not present in this import string.") or "Not present in this import string."
                end

                local desc = CreateWrappedLabel(importBody, descText, 10, descColor)
                desc:SetPoint("TOPLEFT", 208 + indent, innerY - 4)
                desc:SetPoint("RIGHT", importBody, "RIGHT", 0, 0)

                local descHeight = desc:GetStringHeight() or 14
                local rowHeight = math.max(28, descHeight + 8)
                innerY = innerY - rowHeight - 4

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
                    importBody,
                    "No selective categories were detected in this string. Try importing everything or use a different QUI profile string.",
                    11,
                    C.textMuted
                )
                noCategories:SetPoint("TOPLEFT", 0, innerY)
                noCategories:SetPoint("RIGHT", importBody, "RIGHT", 0, 0)
                innerY = innerY - (noCategories:GetStringHeight() or 18) - 12
            end

            local actionNote = CreateWrappedLabel(
                importBody,
                "Import Selected keeps all unchecked categories from the target profile. If a parent section is checked, its child rows are ignored. If Save As Profile is empty, the target is your current profile. Import Everything replaces the whole target profile.",
                10,
                C.textMuted
            )
            actionNote:SetPoint("TOPLEFT", 0, innerY)
            actionNote:SetPoint("RIGHT", importBody, "RIGHT", 0, 0)
            innerY = innerY - (actionNote:GetStringHeight() or 18) - 14

            analysisState.importSelectedBtn = GUI:CreateButton(importBody, "IMPORT SELECTED", 170, 28, function()
                local selectedIDs = GetSelectedCategoryIDs()
                if #selectedIDs == 0 then
                    return
                end

                local core = GetCore()
                if not core or not core.ImportProfileSelectionFromString then
                    print("|cffff0000QUI: QUICore not available for selective import.|r")
                    return
                end

                local ok, err
                if analysisState.activePayload then
                    ok, err = core:ImportProfileSelectionFromValidatedPayload(
                        analysisState.activePayload,
                        selectedIDs,
                        GetTargetProfileName()
                    )
                else
                    ok, err = core:ImportProfileSelectionFromString(
                        importEditBox:GetText(),
                        selectedIDs,
                        GetTargetProfileName()
                    )
                end
                PrintImportResult(ok, err)
                if ok then
                    ShowReloadPrompt("Selected profile settings imported. Reload UI to fully apply the changes?")
                end
            end)
            analysisState.importSelectedBtn:SetPoint("TOPLEFT", 0, innerY)
            innerY = innerY - 40

            importBody:SetHeight(math.abs(innerY) + 8)
            importCollapsibleSection:RefreshContentHeight()

            UpdateCategoryCheckboxStates()
            UpdateActionButtons()

            localY = importSectionStartY - importCollapsibleSection:GetHeight() - 8
        end

        previewHost:SetHeight(math.abs(localY) + 8)
        UpdateContentHeight()
    end

    local function ClearAnalysis(message, isError)
        analysisState.preview = nil
        analysisState.selected = {}
        analysisState.activePayload = nil
        RenderPreview(
            isError and "Import Analysis Failed" or "Analyze Import",
            message or "Paste a QUI profile string and click Analyze Import to choose what to import.",
            nil,
            isError,
            nil
        )
    end

    local analyzeBtn = GUI:CreateButton(postExportContainer, "ANALYZE IMPORT", 160, 28, function()
        local core = GetCore()
        if not core or not core.AnalyzeProfileImportString then
            ClearAnalysis("QUICore is not available for import analysis.", true)
            return
        end

        local ok, result = core:AnalyzeProfileImportString(importEditBox:GetText())
        if not ok then
            if type(result) == "table" and result.errors and core.DescribeProfileImportValidationErrors then
                analysisState.preview = nil
                analysisState.selected = {}
                analysisState.activePayload = nil
                local detailText = core:DescribeProfileImportValidationErrors(result)
                RenderPreview(
                    "Import analysis blocked",
                    detailText,
                    nil,
                    true,
                    result
                )
            else
                ClearAnalysis(result or "Import analysis failed.", true)
            end
            return
        end

        analysisState.preview = result
        analysisState.selected = {}
        analysisState.activePayload = nil
        for _, category in ipairs(result.categories or {}) do
            if category.available and category.recommended then
                analysisState.selected[category.id] = true
            end
        end

        RenderPreview(
            "Import Ready",
            "Choose the parts of the profile you want to import. Leave categories unchecked to preserve your current settings in those areas.",
            result,
            false,
            nil
        )
    end)
    analyzeBtn:SetPoint("TOPLEFT", PAD, y)

    local analyzeHint = GUI:CreateLabel(postExportContainer, "Analyze first, then import selected parts or the whole profile.", 11, C.textMuted)
    analyzeHint:SetPoint("LEFT", analyzeBtn, "RIGHT", 12, 0)

    importEditBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput and (analysisState.preview or analysisState.activePayload) then
            ClearAnalysis("Import string changed. Analyze it again before importing.", false)
        end
    end)

    ClearAnalysis("Paste a QUI profile string and click Analyze Import to choose what to import.", false)
end

-- PAGE: QUI Import/Export
--------------------------------------------------------------------------------
local function CreateImportExportPage(parent)
    local _, content = CreateScrollableContent(parent)
    BuildImportExportTab(content)
    content:SetHeight(550)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_ImportOptions = {
    CreateImportExportPage = CreateImportExportPage,
    BuildImportExportTab = BuildImportExportTab,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "importExportPage",
        moverKey = "importExport",
        category = "global",
        nav = { tileId = "global", subPageIndex = 3 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildImportExportTab,
            }),
        },
    }))
end
