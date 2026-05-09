local ADDON_NAME, ns = ...

local AuraDefaults = ns.QUI_GroupFramesAuraDefaults

local AuraIndicatorsEditor = ns.QUI_GroupFramesAuraIndicatorsSettings or {}
ns.QUI_GroupFramesAuraIndicatorsSettings = AuraIndicatorsEditor

local FORM_ROW = 32
local DROP_ROW = 52
local SLIDER_HEIGHT = 65
local PAD = 10
local SUGGEST_CELL_SIZE = 36
local SUGGEST_ICON_SIZE = 28
local SUGGEST_CELL_GAP = 2
local SUGGEST_CELL_STRIDE = SUGGEST_CELL_SIZE + SUGGEST_CELL_GAP

local NINE_POINT_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOP", text = "Top" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local AURA_INDICATOR_TYPE_OPTIONS = {
    { value = "icon", text = "Icon" },
    { value = "bar", text = "Bar" },
    { value = "healthBarColor", text = "Health Bar Tint" },
}

local BAR_ORIENTATION_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal" },
    { value = "VERTICAL", text = "Vertical" },
}
local HEALTH_TINT_ANIMATION_OPTIONS = {
    { value = "fill", text = "Soft Fill" },
    { value = "fade", text = "Soft Fade" },
    { value = "fillFade", text = "Fill + Fade" },
    { value = "pulse", text = "Subtle Pulse" },
    { value = "instant", text = "Instant" },
}
local HEALTH_TINT_ANIMATION_DURATIONS = {
    instant = 0,
    fill = 0.35,
    fade = 0.25,
    fillFade = 0.35,
    pulse = 0.28,
}

local function GetGUI()
    return QUI and QUI.GUI or nil
end

local function GetPixelSize(frame)
    local core = ns.Addon
    return (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
end

local function ApplyPixelBackdrop(frame, borderPixels, withBackground)
    if not frame then
        return
    end
    local uikit = ns.UIKit
    local core = ns.Addon
    if uikit and uikit.CreateBorderLines and uikit.UpdateBorderLines and uikit.CreateBackground then
        if not frame._quiAuraIndicatorBg and withBackground then
            frame._quiAuraIndicatorBg = uikit.CreateBackground(frame)
        end
        if frame._quiAuraIndicatorBg then
            frame._quiAuraIndicatorBg:Show()
        end
        if not frame._quiAuraIndicatorBorder then
            frame._quiAuraIndicatorBorder = uikit.CreateBorderLines(frame)
        end
        uikit.UpdateBorderLines(frame, borderPixels or 1, 1, 1, 1, 0.2, false)
        return
    end
    if not frame.SetBackdrop then
        return
    end
    if core and core.SetPixelPerfectBackdrop then
        core:SetPixelPerfectBackdrop(frame, borderPixels or 1, withBackground and "Interface\\Buttons\\WHITE8x8" or nil)
        return
    end
    local pixelSize = core and core.GetPixelSize and core:GetPixelSize(frame) or 1
    frame:SetBackdrop({
        bgFile = withBackground and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = (borderPixels or 1) * pixelSize,
    })
end

local function NormalizeHealthTintAnimation(value)
    if value == "instant"
        or value == "fill"
        or value == "fade"
        or value == "fillFade"
        or value == "pulse" then
        return value
    end
    return "fill"
end

local function EaseOutCubic(t)
    local inv = 1 - t
    return 1 - (inv * inv * inv)
end

local function CreateHealthTintAnimationPreview(parent, GUI, C, indicator)
    local preview = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    preview:SetHeight(72)
    ApplyPixelBackdrop(preview, 1, true)
    preview:SetBackdropColor(0.06, 0.06, 0.07, 0.92)
    preview:SetBackdropBorderColor(0.22, 0.24, 0.28, 1)

    local label = GUI:CreateLabel(preview, "Animation Preview", 11, C.textMuted)
    label:SetPoint("TOPLEFT", PAD, -8)
    label:SetJustifyH("LEFT")

    local replay = GUI:CreateButton(preview, "Replay", 72, 22, function()
        preview._elapsed = 0
    end)
    replay:SetPoint("TOPRIGHT", -PAD, -6)
    GUI:AttachTooltip(replay, "Restart the animation preview from the beginning.", "Replay Preview")

    local bar = CreateFrame("StatusBar", nil, preview)
    bar:SetPoint("LEFT", PAD, 0)
    bar:SetPoint("RIGHT", replay, "LEFT", -10, 0)
    bar:SetPoint("BOTTOM", 0, 12)
    bar:SetHeight(18)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(72)
    local texturePath = ns.LSM and ns.LSM:Fetch("statusbar", "Quazii v5", true) or "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(texturePath)
    bar:SetStatusBarColor(0.18, 0.18, 0.2, 1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    local tint = CreateFrame("StatusBar", nil, bar)
    tint:SetAllPoints(bar)
    tint:SetFrameLevel(bar:GetFrameLevel() + 1)
    tint:SetStatusBarTexture(texturePath)
    tint:SetMinMaxValues(0, 100)
    tint:SetValue(0)

    local function UpdatePreview()
        local color = indicator and indicator.color or { 0.2, 0.8, 0.2, 1 }
        local r = color[1] or 0.2
        local g = color[2] or 0.8
        local b = color[3] or 0.2
        local a = color[4] or 1
        local mode = NormalizeHealthTintAnimation(indicator and indicator.animation)
        local duration = HEALTH_TINT_ANIMATION_DURATIONS[mode] or HEALTH_TINT_ANIMATION_DURATIONS.fill
        local target = 72
        local elapsed = preview._elapsed or 0
        local pct = duration > 0 and math.min(elapsed / duration, 1) or 1
        local eased = EaseOutCubic(pct)
        local value, alpha

        if mode == "instant" then
            value, alpha = target, 1
        elseif mode == "fade" then
            value, alpha = target, eased
        elseif mode == "fillFade" then
            value, alpha = target * eased, eased
        elseif mode == "pulse" then
            value, alpha = target, 0.35 + (0.65 * eased)
        else
            value, alpha = target * eased, 1
        end

        tint:SetStatusBarColor(r, g, b, a)
        tint:SetValue(value)
        tint:SetAlpha(alpha)
    end

    preview._elapsed = 0
    preview:SetScript("OnShow", function(self)
        self._elapsed = 0
        UpdatePreview()
    end)
    preview:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed > 1.4 then
            self._elapsed = 0
        end
        UpdatePreview()
    end)
    preview:SetScript("OnHide", function(self)
        self._elapsed = 0
    end)
    UpdatePreview()

    return preview
end

local function GetSpellName(spellId)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellId)
        if ok and name and name ~= "" then
            return name
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellId)
        if ok and name and name ~= "" then
            return name
        end
    end
    return nil
end

local function GetSpellTexture(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellId)
        if ok and texture then
            return texture
        end
    end
    return 134400
end

local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        return GetSpecializationInfo(specIndex)
    end
    return nil
end

local function GetPlayerSpecName(specID)
    if not specID or not GetSpecializationInfoByID then
        return nil
    end
    local _, specName = GetSpecializationInfoByID(specID)
    return specName
end

local function LayoutDraggableRows(container, rows, placeholder, rowStep, skipRow, insertIndex)
    local nextY = 0
    local placedPlaceholder = false
    for index, row in ipairs(rows) do
        if skipRow and insertIndex == index and not placedPlaceholder then
            placeholder:ClearAllPoints()
            placeholder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
            placeholder:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            placeholder:Show()
            nextY = nextY - rowStep
            placedPlaceholder = true
        end
        if row ~= skipRow then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
            row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            nextY = nextY - rowStep
        end
    end

    if skipRow and not placedPlaceholder then
        placeholder:ClearAllPoints()
        placeholder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
        placeholder:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        placeholder:Show()
        nextY = nextY - rowStep
    elseif placeholder then
        placeholder:Hide()
    end

    local usedHeight = math.max(0, math.abs(nextY))
    container:SetHeight(math.max(1, usedHeight))
    return usedHeight
end

local function ComputeDropIndex(rows, container, rowStep)
    local rowCount = #rows
    if rowCount <= 1 then
        return 1
    end

    local scale = UIParent:GetEffectiveScale() or 1
    local _, cursorY = GetCursorPosition()
    cursorY = (cursorY or 0) / scale
    local topY = container:GetTop()
    if not topY then
        return rowCount
    end

    local relative = topY - cursorY
    local slot = math.floor((relative + (rowStep * 0.5)) / rowStep) + 1
    if slot < 1 then
        slot = 1
    end
    if slot > (rowCount + 1) then
        slot = rowCount + 1
    end
    return slot
end

local function CommitReorder(list, fromIndex, toIndex)
    if type(list) ~= "table" then
        return false, fromIndex
    end

    local length = #list
    if fromIndex < 1 or fromIndex > length then
        return false, fromIndex
    end

    local targetIndex = toIndex
    if targetIndex > fromIndex then
        targetIndex = targetIndex - 1
    end
    if targetIndex < 1 then
        targetIndex = 1
    end
    if targetIndex > length then
        targetIndex = length
    end
    if targetIndex == fromIndex then
        return false, fromIndex
    end

    local moving = table.remove(list, fromIndex)
    table.insert(list, targetIndex, moving)
    return true, targetIndex
end

local function RemapSelectedIndex(selectedIndex, fromIndex, toIndex)
    if not selectedIndex then
        return selectedIndex
    end
    if selectedIndex == fromIndex then
        return toIndex
    end
    if fromIndex < selectedIndex and toIndex >= selectedIndex then
        return selectedIndex - 1
    end
    if fromIndex > selectedIndex and toIndex <= selectedIndex then
        return selectedIndex + 1
    end
    return selectedIndex
end

local function CountIndicatorTypes(entry)
    local icons, bars, tints = 0, 0, 0
    for _, indicator in ipairs(entry.indicators or {}) do
        if indicator.type == "bar" then
            bars = bars + 1
        elseif indicator.type == "healthBarColor" then
            tints = tints + 1
        else
            icons = icons + 1
        end
    end
    return icons, bars, tints
end

local function GetIndicatorLabel(indicator, index)
    if indicator.type == "bar" then
        return "Bar " .. index
    elseif indicator.type == "healthBarColor" then
        return "Health Bar Tint " .. index
    end
    return "Icon " .. index
end

local function GetSuggestionSpells(entries)
    if AuraDefaults and type(AuraDefaults.GetSuggestionSpells) == "function" then
        return AuraDefaults.GetSuggestionSpells(entries)
    end
    return {}
end

function AuraIndicatorsEditor.RenderTrackedAuras(host, auraIndicatorsDB, onChange)
    local GUI = GetGUI()
    if not host or not GUI or type(auraIndicatorsDB) ~= "table" then
        return 1
    end

    local C = GUI.Colors or {}
    local normalizeAuraIndicators = ns.Helpers and ns.Helpers.NormalizeAuraIndicatorConfig
    if normalizeAuraIndicators then
        normalizeAuraIndicators(auraIndicatorsDB)
    end

    local auraRows = {}
    local suggestRows = {}
    local indicatorRows = {}
    local detailWidgets = {}
    local selectedAuraIndex = 1
    local selectedIndicatorIndex = 1

    local title = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -6)
    title:SetJustifyH("LEFT")

    local subtitle = GUI:CreateLabel(host, "Add tracked auras, then attach one or more indicator types to each aura.", 11, C.textMuted)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -24)
    subtitle:SetPoint("RIGHT", host, "RIGHT", 0, -24)

    local auraListArea = CreateFrame("Frame", nil, host)
    auraListArea:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -48)
    auraListArea:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    auraListArea:SetHeight(1)

    local auraRowHeight = 28
    local auraRowStep = 30
    local indicatorRowHeight = 24
    local indicatorRowStep = 26

    local auraRowsContainer = CreateFrame("Frame", nil, auraListArea)
    auraRowsContainer:SetPoint("TOPLEFT", 0, 0)
    auraRowsContainer:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
    auraRowsContainer:SetHeight(1)

    local indicatorRowsContainer = CreateFrame("Frame", nil, auraListArea)
    indicatorRowsContainer:SetPoint("TOPLEFT", 0, 0)
    indicatorRowsContainer:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
    indicatorRowsContainer:SetHeight(1)

    local addHeader = auraListArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addHeader:SetJustifyH("LEFT")

    local inputRow = CreateFrame("Frame", nil, auraListArea)
    inputRow:SetHeight(24)

    local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
    inputBox:SetSize(80, 20)
    inputBox:SetPoint("LEFT", 4, 0)
    inputBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GetPixelSize(inputBox),
    })
    inputBox:SetBackdropColor(0.06, 0.06, 0.08, 1)
    inputBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    inputBox:SetFontObject("GameFontNormalSmall")
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(10)
    inputBox:SetTextInsets(4, 4, 0, 0)
    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local inputLabel = inputRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputLabel:SetPoint("LEFT", inputBox, "RIGHT", 4, 0)
    inputLabel:SetText("Spell ID")
    inputLabel:SetTextColor(0.5, 0.5, 0.5)

    local addManualButton = CreateFrame("Button", nil, inputRow, "BackdropTemplate")
    addManualButton:SetSize(40, 20)
    addManualButton:SetPoint("RIGHT", inputRow, "RIGHT", -2, 0)
    addManualButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GetPixelSize(addManualButton),
    })
    addManualButton:SetBackdropColor(0.15, 0.15, 0.15, 1)
    addManualButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local addManualText = addManualButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addManualText:SetPoint("CENTER")
    addManualText:SetText("Add")

    local indicatorActionsRow = CreateFrame("Frame", nil, auraListArea)
    indicatorActionsRow:SetHeight(26)
    indicatorActionsRow:SetPoint("TOPLEFT", auraListArea, "TOPLEFT", 0, 0)
    indicatorActionsRow:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)

    local addIconButton = GUI:CreateButton(indicatorActionsRow, "Add Icon", 74, 22)
    addIconButton:SetPoint("LEFT", 0, 0)
    local addBarButton = GUI:CreateButton(indicatorActionsRow, "Add Bar", 68, 22)
    addBarButton:SetPoint("LEFT", addIconButton, "RIGHT", 6, 0)
    local addTintButton = GUI:CreateButton(indicatorActionsRow, "Add Tint", 72, 22)
    addTintButton:SetPoint("LEFT", addBarButton, "RIGHT", 6, 0)
    GUI:AttachTooltip(addTintButton,
        "Add a tint indicator — recolors the unit's health bar while the selected aura is active. Useful for at-a-glance buff/debuff awareness without adding screen clutter.",
        "Add Tint Indicator")

    local selectedAuraLabel = auraListArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedAuraLabel:SetJustifyH("LEFT")

    local detailArea = CreateFrame("Frame", nil, auraListArea)
    detailArea:SetPoint("TOPLEFT", auraListArea, "TOPLEFT", 0, 0)
    detailArea:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
    detailArea:SetHeight(1)

    local function CreateDropPlaceholder(parent, height)
        local placeholder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        placeholder:SetHeight(height)
        ApplyPixelBackdrop(placeholder, 1, true)
        placeholder:SetBackdropColor((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 0.12)
        placeholder:SetBackdropBorderColor((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 0.85)
        placeholder:Hide()
        return placeholder
    end

    local auraPlaceholder = CreateDropPlaceholder(auraRowsContainer, auraRowHeight)
    local indicatorPlaceholder = CreateDropPlaceholder(indicatorRowsContainer, indicatorRowHeight)
    local auraDragState = {}
    local indicatorDragState = {}

    local function NotifyChanged()
        if normalizeAuraIndicators then
            normalizeAuraIndicators(auraIndicatorsDB)
        end
        if type(onChange) == "function" then
            onChange()
        end
    end

    local function AcquireAuraRow()
        local row = table.remove(auraRows)
        if row then
            row:Show()
            row:ClearAllPoints()
            return row
        end

        row = CreateFrame("Button", nil, auraListArea, "BackdropTemplate")
        row:SetHeight(auraRowHeight)
        row:RegisterForClicks("LeftButtonUp")
        row:SetMovable(true)
        row:RegisterForDrag("LeftButton")
        ApplyPixelBackdrop(row, 1, true)

        row.dragHandle = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.dragHandle:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
        row.dragHandle:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
        row.dragHandle:SetWidth(22)
        ApplyPixelBackdrop(row.dragHandle, 1, true)
        row.dragHandle:SetBackdropColor(0.14, 0.14, 0.16, 0.65)
        row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
        row.dragHandle:EnableMouse(false)

        row.dragHint = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.dragHint:SetPoint("CENTER", row.dragHandle, "CENTER", 0, 0)
        row.dragHint:SetText("::")
        row.dragHint:SetTextColor((C.textMuted and C.textMuted[1]) or 0.5, (C.textMuted and C.textMuted[2]) or 0.5, (C.textMuted and C.textMuted[3]) or 0.5, 1)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row.dragHandle, "RIGHT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetJustifyH("LEFT")

        row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.summary:SetJustifyH("RIGHT")

        row.remove = CreateFrame("Button", nil, row)
        row.remove:SetSize(18, 18)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.removeText = row.remove:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.removeText:SetPoint("CENTER")
        row.removeText:SetText("x")
        row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        row.remove:SetScript("OnEnter", function()
            row.removeText:SetTextColor(1, 0.4, 0.4, 1)
        end)
        row.remove:SetScript("OnLeave", function()
            row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        end)
        row.summary:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
        row.name:SetPoint("RIGHT", row.summary, "LEFT", -6, 0)

        return row
    end

    local activeAuraRows = {}
    local function ReleaseAuraRows()
        for _, row in ipairs(activeAuraRows) do
            row:Hide()
            row:ClearAllPoints()
            row.remove:SetScript("OnClick", nil)
            row:SetScript("OnDragStart", nil)
            row:SetScript("OnDragStop", nil)
            row:SetScript("OnUpdate", nil)
            row:SetScript("OnClick", nil)
            row:SetAlpha(1)
            if row.dragHandle then
                row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
            end
            table.insert(auraRows, row)
        end
        wipe(activeAuraRows)
    end

    local function AcquireSuggestCell()
        local cell = table.remove(suggestRows)
        if cell then
            cell:Show()
            cell:ClearAllPoints()
            return cell
        end

        cell = CreateFrame("Button", nil, auraListArea, "BackdropTemplate")
        cell:SetSize(SUGGEST_CELL_SIZE, SUGGEST_CELL_SIZE)
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        ApplyPixelBackdrop(cell, 1, true)
        cell:SetBackdropColor(0, 0, 0, 0)
        cell:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)

        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(SUGGEST_ICON_SIZE, SUGGEST_ICON_SIZE)
        cell.icon:SetPoint("CENTER")
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
        cell.highlight:SetAllPoints()
        cell.highlight:SetColorTexture((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 0.15)

        cell:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 0.8)
            if GameTooltip and self._spell then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetFrameStrata("TOOLTIP")
                GameTooltip:SetFrameLevel(250)
                GameTooltip:AddLine(self._spell.name or GetSpellName(self._spell.id) or ("Spell " .. tostring(self._spell.id)), 1, 1, 1)
                GameTooltip:AddLine("ID: " .. tostring(self._spell.id), 0.5, 0.5, 0.5)
                if self._spell.source then
                    GameTooltip:AddLine(self._spell.source, 0.45, 0.65, 0.95)
                end
                GameTooltip:AddLine("Click to add", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)
        cell:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)

        return cell
    end

    local activeSuggestRows = {}
    local function ReleaseSuggestRows()
        for _, cell in ipairs(activeSuggestRows) do
            cell:Hide()
            cell:ClearAllPoints()
            cell:SetScript("OnClick", nil)
            cell._spell = nil
            cell:SetAlpha(1)
            if cell.icon then
                cell.icon:SetDesaturated(false)
            end
            table.insert(suggestRows, cell)
        end
        wipe(activeSuggestRows)
    end

    local function AcquireIndicatorRow()
        local row = table.remove(indicatorRows)
        if row then
            row:Show()
            row:ClearAllPoints()
            return row
        end

        row = CreateFrame("Button", nil, auraListArea, "BackdropTemplate")
        row:SetHeight(indicatorRowHeight)
        row:RegisterForClicks("LeftButtonUp")
        row:SetMovable(true)
        row:RegisterForDrag("LeftButton")
        ApplyPixelBackdrop(row, 1, true)

        row.dragHandle = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.dragHandle:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
        row.dragHandle:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
        row.dragHandle:SetWidth(22)
        ApplyPixelBackdrop(row.dragHandle, 1, true)
        row.dragHandle:SetBackdropColor(0.14, 0.14, 0.16, 0.65)
        row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
        row.dragHandle:EnableMouse(false)

        row.dragHint = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.dragHint:SetPoint("CENTER", row.dragHandle, "CENTER", 0, 0)
        row.dragHint:SetText("::")
        row.dragHint:SetTextColor((C.textMuted and C.textMuted[1]) or 0.5, (C.textMuted and C.textMuted[2]) or 0.5, (C.textMuted and C.textMuted[3]) or 0.5, 1)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.dragHandle, "RIGHT", 8, 0)
        row.label:SetJustifyH("LEFT")

        row.remove = CreateFrame("Button", nil, row)
        row.remove:SetSize(18, 18)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.removeText = row.remove:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.removeText:SetPoint("CENTER")
        row.removeText:SetText("x")
        row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        row.remove:SetScript("OnEnter", function()
            row.removeText:SetTextColor(1, 0.4, 0.4, 1)
        end)
        row.remove:SetScript("OnLeave", function()
            row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        end)
        row.label:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)

        return row
    end

    local activeIndicatorRows = {}
    local function ReleaseIndicatorRows()
        for _, row in ipairs(activeIndicatorRows) do
            row:Hide()
            row:ClearAllPoints()
            row.remove:SetScript("OnClick", nil)
            row:SetScript("OnDragStart", nil)
            row:SetScript("OnDragStop", nil)
            row:SetScript("OnUpdate", nil)
            row:SetScript("OnClick", nil)
            row:SetAlpha(1)
            if row.dragHandle then
                row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
            end
            table.insert(indicatorRows, row)
        end
        wipe(activeIndicatorRows)
    end

    local function ClearDetailWidgets()
        for _, widget in ipairs(detailWidgets) do
            widget:Hide()
        end
        wipe(detailWidgets)
    end

    local function RegisterDetailWidget(widget)
        detailWidgets[#detailWidgets + 1] = widget
        return widget
    end

    local function AddNewAura(spellID)
        auraIndicatorsDB.entries = auraIndicatorsDB.entries or {}
        auraIndicatorsDB.entries[#auraIndicatorsDB.entries + 1] = {
            spellID = tonumber(spellID) or spellID,
            enabled = true,
            onlyMine = false,
            indicators = {
                { type = "icon", enabled = true },
            },
        }
        if normalizeAuraIndicators then
            normalizeAuraIndicators(auraIndicatorsDB)
        end
        selectedAuraIndex = #auraIndicatorsDB.entries
        selectedIndicatorIndex = 1
        NotifyChanged()
    end

    local rebuildAuraList

    local function AddIndicator(indicatorType)
        local entry = auraIndicatorsDB.entries and auraIndicatorsDB.entries[selectedAuraIndex]
        if not entry then
            return
        end
        entry.indicators[#entry.indicators + 1] = {
            type = indicatorType,
            enabled = true,
        }
        if normalizeAuraIndicators then
            normalizeAuraIndicators(auraIndicatorsDB)
        end
        selectedIndicatorIndex = #entry.indicators
        NotifyChanged()
        if rebuildAuraList then
            rebuildAuraList()
        end
    end

    addIconButton:SetScript("OnClick", function()
        AddIndicator("icon")
    end)
    addBarButton:SetScript("OnClick", function()
        AddIndicator("bar")
    end)
    addTintButton:SetScript("OnClick", function()
        AddIndicator("healthBarColor")
    end)

    addManualButton:SetScript("OnClick", function()
        local spellID = tonumber(inputBox:GetText())
        if spellID and spellID > 0 then
            AddNewAura(spellID)
            inputBox:SetText("")
            inputBox:ClearFocus()
            if rebuildAuraList then
                rebuildAuraList()
            end
        end
    end)
    inputBox:SetScript("OnEnterPressed", function()
        local click = addManualButton:GetScript("OnClick")
        if click then
            click(addManualButton)
        end
    end)

    rebuildAuraList = function()
        if normalizeAuraIndicators then
            normalizeAuraIndicators(auraIndicatorsDB)
        end

        local entries = auraIndicatorsDB.entries or {}
        if #entries == 0 then
            selectedAuraIndex = 1
            selectedIndicatorIndex = 1
        else
            selectedAuraIndex = math.max(1, math.min(selectedAuraIndex, #entries))
            local selectedEntry = entries[selectedAuraIndex]
            local indicatorCount = #(selectedEntry and selectedEntry.indicators or {})
            selectedIndicatorIndex = math.max(1, math.min(selectedIndicatorIndex, math.max(indicatorCount, 1)))
        end

        ReleaseAuraRows()
        ReleaseSuggestRows()
        ReleaseIndicatorRows()
        ClearDetailWidgets()

        local specID = GetPlayerSpecID()
        title:SetText("|cFF34D399" .. (GetPlayerSpecName(specID) or "Tracked Auras") .. "|r")

        local y = 0
        for index, entry in ipairs(entries) do
            local row = AcquireAuraRow()
            row:SetParent(auraRowsContainer)
            row.icon:SetTexture(GetSpellTexture(entry.spellID))

            local spellName = GetSpellName(entry.spellID) or ("Spell " .. tostring(entry.spellID))
            row.name:SetText((entry.enabled ~= false and "|cFFFFFFFF" or "|cFF808080") .. spellName .. "|r")

            local iconCount, barCount, tintCount = CountIndicatorTypes(entry)
            row.summary:SetText(string.format("I:%d B:%d T:%d%s", iconCount, barCount, tintCount, entry.onlyMine and " |cff56D1FFMine|r" or ""))

            local selected = index == selectedAuraIndex
            row:SetBackdropColor(selected and 0.16 or 0.08, selected and 0.16 or 0.08, selected and 0.2 or 0.08, 0.9)
            row:SetBackdropBorderColor(
                selected and ((C.accent and C.accent[1]) or 0.3) or ((C.border and C.border[1]) or 0.2),
                selected and ((C.accent and C.accent[2]) or 0.7) or ((C.border and C.border[2]) or 0.2),
                selected and ((C.accent and C.accent[3]) or 1) or ((C.border and C.border[3]) or 0.2),
                1
            )

            row:SetScript("OnClick", function()
                if auraDragState.suppressClick then
                    auraDragState.suppressClick = nil
                    return
                end
                selectedAuraIndex = index
                selectedIndicatorIndex = 1
                rebuildAuraList()
            end)
            row:SetScript("OnDragStart", function(self)
                auraDragState.active = true
                auraDragState.row = self
                auraDragState.fromIndex = index
                auraDragState.toIndex = index
                auraDragState.baseStrata = self:GetFrameStrata()
                auraDragState.baseLevel = self:GetFrameLevel()
                auraDragState.baseAlpha = self:GetAlpha()
                self:StartMoving()
                self:SetFrameStrata("TOOLTIP")
                self:SetFrameLevel(400)
                self:SetAlpha(0.92)
                self.dragHandle:SetBackdropBorderColor((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 1)
                LayoutDraggableRows(auraRowsContainer, activeAuraRows, auraPlaceholder, auraRowStep, self, auraDragState.toIndex)
                self:SetScript("OnUpdate", function(dragged)
                    if not auraDragState.active then
                        return
                    end
                    local nextIndex = ComputeDropIndex(activeAuraRows, auraRowsContainer, auraRowStep)
                    if nextIndex ~= auraDragState.toIndex then
                        auraDragState.toIndex = nextIndex
                        LayoutDraggableRows(auraRowsContainer, activeAuraRows, auraPlaceholder, auraRowStep, dragged, auraDragState.toIndex)
                    end
                end)
            end)
            row:SetScript("OnDragStop", function(self)
                if not auraDragState.active then
                    return
                end
                self:StopMovingOrSizing()
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(auraDragState.baseAlpha or 1)
                self:SetFrameStrata(auraDragState.baseStrata or "MEDIUM")
                if auraDragState.baseLevel then
                    self:SetFrameLevel(auraDragState.baseLevel)
                end
                self.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
                auraDragState.active = false
                local changed, targetIndex = CommitReorder(entries, auraDragState.fromIndex or index, auraDragState.toIndex or index)
                auraDragState.row = nil
                auraDragState.fromIndex = nil
                auraDragState.toIndex = nil
                auraDragState.baseStrata = nil
                auraDragState.baseLevel = nil
                auraDragState.baseAlpha = nil
                auraPlaceholder:Hide()
                if changed then
                    selectedAuraIndex = RemapSelectedIndex(selectedAuraIndex, index, targetIndex)
                    auraDragState.suppressClick = true
                    NotifyChanged()
                end
                rebuildAuraList()
            end)
            row.remove:SetScript("OnClick", function()
                table.remove(entries, index)
                NotifyChanged()
                rebuildAuraList()
            end)

            activeAuraRows[#activeAuraRows + 1] = row
        end

        local auraRowsHeight = LayoutDraggableRows(auraRowsContainer, activeAuraRows, auraPlaceholder, auraRowStep)
        y = -(auraRowsHeight + 4)
        addHeader:ClearAllPoints()
        addHeader:SetPoint("TOPLEFT", 0, y)
        addHeader:SetText("|cFFAAAAAAAdd Tracked Aura:|r")
        y = y - 16

        inputRow:ClearAllPoints()
        inputRow:SetPoint("TOPLEFT", 0, y)
        inputRow:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
        y = y - 28

        local suggestions = GetSuggestionSpells(entries)
        if #suggestions > 0 then
            local contentWidth = auraListArea:GetWidth()
            if type(contentWidth) ~= "number" or contentWidth < SUGGEST_CELL_STRIDE then
                contentWidth = 520
            end
            local cols = math.max(1, math.floor(contentWidth / SUGGEST_CELL_STRIDE))
            local rows = math.ceil(#suggestions / cols)
            for index, spell in ipairs(suggestions) do
                local cell = AcquireSuggestCell()
                local col = (index - 1) % cols
                local row = math.floor((index - 1) / cols)
                cell:SetParent(auraListArea)
                cell:SetPoint("TOPLEFT", col * SUGGEST_CELL_STRIDE, y - (row * SUGGEST_CELL_STRIDE))
                cell._spell = spell
                cell.icon:SetTexture(spell.icon or GetSpellTexture(spell.id))
                cell:SetScript("OnClick", function(_, button)
                    if button == "LeftButton" or button == "RightButton" then
                        AddNewAura(spell.id)
                        rebuildAuraList()
                    end
                end)
                activeSuggestRows[#activeSuggestRows + 1] = cell
            end
            y = y - (rows * SUGGEST_CELL_STRIDE) - 4
        end

        local selectedEntry = entries[selectedAuraIndex]
        if selectedEntry then
            y = y - 10
            selectedAuraLabel:ClearAllPoints()
            selectedAuraLabel:SetPoint("TOPLEFT", 0, y)
            selectedAuraLabel:SetText("Configure: " .. (GetSpellName(selectedEntry.spellID) or ("Spell " .. tostring(selectedEntry.spellID))))
            y = y - 22

            indicatorActionsRow:ClearAllPoints()
            indicatorActionsRow:SetPoint("TOPLEFT", 0, y)
            indicatorActionsRow:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
            indicatorActionsRow:Show()
            y = y - 30

            local indicatorCount = #(selectedEntry.indicators or {})
            if indicatorCount == 0 then
                selectedIndicatorIndex = 1
            else
                selectedIndicatorIndex = math.max(1, math.min(selectedIndicatorIndex, indicatorCount))
            end

            for index, indicator in ipairs(selectedEntry.indicators or {}) do
                local row = AcquireIndicatorRow()
                row:SetParent(indicatorRowsContainer)
                row.label:SetText(GetIndicatorLabel(indicator, index))

                local selected = index == selectedIndicatorIndex
                row:SetBackdropColor(selected and 0.15 or 0.07, selected and 0.15 or 0.07, selected and 0.18 or 0.07, 0.9)
                row:SetBackdropBorderColor(
                    selected and ((C.accent and C.accent[1]) or 0.3) or ((C.border and C.border[1]) or 0.2),
                    selected and ((C.accent and C.accent[2]) or 0.7) or ((C.border and C.border[2]) or 0.2),
                    selected and ((C.accent and C.accent[3]) or 1) or ((C.border and C.border[3]) or 0.2),
                    1
                )

                row:SetScript("OnClick", function()
                    if indicatorDragState.suppressClick then
                        indicatorDragState.suppressClick = nil
                        return
                    end
                    selectedIndicatorIndex = index
                    rebuildAuraList()
                end)
                row:SetScript("OnDragStart", function(self)
                    indicatorDragState.active = true
                    indicatorDragState.row = self
                    indicatorDragState.fromIndex = index
                    indicatorDragState.toIndex = index
                    indicatorDragState.baseStrata = self:GetFrameStrata()
                    indicatorDragState.baseLevel = self:GetFrameLevel()
                    indicatorDragState.baseAlpha = self:GetAlpha()
                    self:StartMoving()
                    self:SetFrameStrata("TOOLTIP")
                    self:SetFrameLevel(401)
                    self:SetAlpha(0.92)
                    self.dragHandle:SetBackdropBorderColor((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 1)
                    LayoutDraggableRows(indicatorRowsContainer, activeIndicatorRows, indicatorPlaceholder, indicatorRowStep, self, indicatorDragState.toIndex)
                    self:SetScript("OnUpdate", function(dragged)
                        if not indicatorDragState.active then
                            return
                        end
                        local nextIndex = ComputeDropIndex(activeIndicatorRows, indicatorRowsContainer, indicatorRowStep)
                        if nextIndex ~= indicatorDragState.toIndex then
                            indicatorDragState.toIndex = nextIndex
                            LayoutDraggableRows(indicatorRowsContainer, activeIndicatorRows, indicatorPlaceholder, indicatorRowStep, dragged, indicatorDragState.toIndex)
                        end
                    end)
                end)
                row:SetScript("OnDragStop", function(self)
                    if not indicatorDragState.active then
                        return
                    end
                    self:StopMovingOrSizing()
                    self:SetScript("OnUpdate", nil)
                    self:SetAlpha(indicatorDragState.baseAlpha or 1)
                    self:SetFrameStrata(indicatorDragState.baseStrata or "MEDIUM")
                    if indicatorDragState.baseLevel then
                        self:SetFrameLevel(indicatorDragState.baseLevel)
                    end
                    self.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
                    indicatorDragState.active = false
                    local changed, targetIndex = CommitReorder(selectedEntry.indicators, indicatorDragState.fromIndex or index, indicatorDragState.toIndex or index)
                    indicatorDragState.row = nil
                    indicatorDragState.fromIndex = nil
                    indicatorDragState.toIndex = nil
                    indicatorDragState.baseStrata = nil
                    indicatorDragState.baseLevel = nil
                    indicatorDragState.baseAlpha = nil
                    indicatorPlaceholder:Hide()
                    if changed then
                        selectedIndicatorIndex = RemapSelectedIndex(selectedIndicatorIndex, index, targetIndex)
                        indicatorDragState.suppressClick = true
                        NotifyChanged()
                    end
                    rebuildAuraList()
                end)
                row.remove:SetScript("OnClick", function()
                    table.remove(selectedEntry.indicators, index)
                    if normalizeAuraIndicators then
                        normalizeAuraIndicators(auraIndicatorsDB)
                    end
                    NotifyChanged()
                    rebuildAuraList()
                end)

                activeIndicatorRows[#activeIndicatorRows + 1] = row
            end

            indicatorRowsContainer:ClearAllPoints()
            indicatorRowsContainer:SetPoint("TOPLEFT", 0, y)
            indicatorRowsContainer:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
            local indicatorRowsHeight = LayoutDraggableRows(indicatorRowsContainer, activeIndicatorRows, indicatorPlaceholder, indicatorRowStep)
            y = y - indicatorRowsHeight

            local selectedIndicator = selectedEntry.indicators and selectedEntry.indicators[selectedIndicatorIndex]
            if selectedIndicator then
                y = y - 6
                detailArea:ClearAllPoints()
                detailArea:SetPoint("TOPLEFT", 0, y)
                detailArea:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)

                local detailY = -2
                local function AddDetailWidget(widget, height)
                    RegisterDetailWidget(widget)
                    widget:ClearAllPoints()
                    widget:SetPoint("TOPLEFT", PAD, detailY)
                    widget:SetPoint("RIGHT", detailArea, "RIGHT", -PAD, 0)
                    detailY = detailY - height
                end

                AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Aura Enabled", "enabled", selectedEntry, function()
                    NotifyChanged()
                    rebuildAuraList()
                end, {
                    description = "Toggle tracking of this aura. When off, none of its attached indicators display.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Only My Cast", "onlyMine", selectedEntry, function()
                    NotifyChanged()
                    rebuildAuraList()
                end, {
                    description = "Only track this aura when you applied it.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormDropdown(detailArea, "Indicator Type", AURA_INDICATOR_TYPE_OPTIONS, "type", selectedIndicator, function()
                    if normalizeAuraIndicators then
                        normalizeAuraIndicators(auraIndicatorsDB)
                    end
                    NotifyChanged()
                    rebuildAuraList()
                end, {
                    description = "How this indicator displays: icon in the shared strip, a standalone bar, or a tint applied across the health bar.",
                }), DROP_ROW)
                AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Indicator Enabled", "enabled", selectedIndicator, function()
                    NotifyChanged()
                    rebuildAuraList()
                end, {
                    description = "Toggle just this indicator without removing it.",
                }), FORM_ROW)

                if selectedIndicator.type == "bar" then
                    AddDetailWidget(GUI:CreateFormDropdown(detailArea, "Orientation", BAR_ORIENTATION_OPTIONS, "orientation", selectedIndicator, function()
                        NotifyChanged()
                        rebuildAuraList()
                    end, {
                        description = "Whether the bar drains horizontally or vertically as the tracked aura ticks down.",
                    }), DROP_ROW)
                    AddDetailWidget(GUI:CreateFormSlider(detailArea, "Thickness", 1, 20, 1, "thickness", selectedIndicator, onChange, nil, {
                        description = "Pixel thickness of the bar.",
                    }), SLIDER_HEIGHT)
                    AddDetailWidget(GUI:CreateFormSlider(detailArea, "Width / Height", 4, 200, 1, "length", selectedIndicator, onChange, nil, {
                        description = "Pixel length of the bar.",
                    }), SLIDER_HEIGHT)
                    AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Match Frame Width / Height", "matchFrameSize", selectedIndicator, function()
                        NotifyChanged()
                        rebuildAuraList()
                    end, {
                        description = "Stretch the bar to match the frame size.",
                    }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormDropdown(detailArea, "Anchor", NINE_POINT_OPTIONS, "anchor", selectedIndicator, onChange, {
                        description = "Where on the frame the bar is anchored.",
                    }), DROP_ROW)
                    AddDetailWidget(GUI:CreateFormSlider(detailArea, "X Offset", -100, 100, 1, "offsetX", selectedIndicator, onChange, nil, {
                        description = "Horizontal pixel offset for the bar from its anchor.",
                    }), SLIDER_HEIGHT)
                    AddDetailWidget(GUI:CreateFormSlider(detailArea, "Y Offset", -100, 100, 1, "offsetY", selectedIndicator, onChange, nil, {
                        description = "Vertical pixel offset for the bar from its anchor.",
                    }), SLIDER_HEIGHT)
                    AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Bar Color", "color", selectedIndicator, onChange, nil, {
                        description = "Fill color of the bar while the tracked aura is active.",
                    }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Background Color", "backgroundColor", selectedIndicator, onChange, nil, {
                        description = "Color drawn behind the bar fill.",
                    }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Hide Border", "hideBorder", selectedIndicator, function()
                        NotifyChanged()
                        rebuildAuraList()
                    end, {
                        description = "Remove the border drawn around the bar.",
                    }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormSlider(detailArea, "Border Size", 1, 8, 1, "borderSize", selectedIndicator, onChange, nil, {
                        description = "Pixel thickness of the bar's border.",
                    }), SLIDER_HEIGHT)
                    AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Border Color", "borderColor", selectedIndicator, onChange, nil, {
                        description = "Color of the bar's border.",
                    }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormSlider(detailArea, "Low-Time Seconds", 0, 30, 0.5, "lowTimeThreshold", selectedIndicator, onChange, {
                        precision = 1,
                    }, {
                        description = "When the remaining duration drops below this many seconds, the bar switches to the Low-Time Color.",
                    }), SLIDER_HEIGHT)
                    AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Low-Time Color", "lowTimeColor", selectedIndicator, onChange, nil, {
                        description = "Bar fill color used once the remaining duration crosses the Low-Time threshold.",
                    }), FORM_ROW)
                elseif selectedIndicator.type == "healthBarColor" then
                    AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Tint Color", "color", selectedIndicator, onChange, nil, {
                        description = "Color tint applied across the health bar while the tracked aura is active.",
                    }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormDropdown(detailArea, "Tint Animation", HEALTH_TINT_ANIMATION_OPTIONS, "animation", selectedIndicator, onChange, {
                        description = "How the health-bar tint appears when the tracked aura is detected.",
                    }), DROP_ROW)
                    AddDetailWidget(CreateHealthTintAnimationPreview(detailArea, GUI, C, selectedIndicator), 72)
                else
                    local note = GUI:CreateLabel(detailArea, "Icon indicators use the shared icon-strip settings in the section above.", 11, C.textMuted)
                    note:SetJustifyH("LEFT")
                    AddDetailWidget(note, 28)
                end

                detailArea:SetHeight(math.abs(detailY) + 8)
                y = y - (detailArea:GetHeight() + 4)
            else
                indicatorActionsRow:Hide()
                detailArea:SetHeight(1)
            end
        else
            selectedAuraLabel:SetText("No tracked auras yet.")
            selectedAuraLabel:ClearAllPoints()
            selectedAuraLabel:SetPoint("TOPLEFT", 0, y)
            indicatorActionsRow:Hide()
            detailArea:SetHeight(1)
            y = y - 24
        end

        auraListArea:SetHeight(math.max(1, math.abs(y)))
        host:SetHeight(56 + auraListArea:GetHeight())
    end

    rebuildAuraList()
    return host:GetHeight()
end
