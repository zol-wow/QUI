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
local COLUMN_GAP = 16
local MIN_COLUMN_WIDTH = 220
local MIN_RIGHT_COLUMN_WIDTH = 300
local MAX_LEFT_COLUMN_WIDTH = 520
local RIGHT_CONFIG_TOP_OFFSET = 42
local RIGHT_CONFIG_LABEL_STEP = 18
local LIST_START_GAP = 6
local RIGHT_CONFIG_ACTION_STEP = 24 + LIST_START_GAP

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
            placeholder:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, nextY)
            placeholder:Show()
            nextY = nextY - rowStep
            placedPlaceholder = true
        end
        if row ~= skipRow then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
            row:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, nextY)
            nextY = nextY - rowStep
        end
    end

    if skipRow and not placedPlaceholder then
        placeholder:ClearAllPoints()
        placeholder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
        placeholder:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, nextY)
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

local function RebuildAuraList(ctx)
    local normalizeAuraIndicators = ctx.normalizeAuraIndicators
    local auraIndicatorsDB = ctx.auraIndicatorsDB
    if normalizeAuraIndicators then
        normalizeAuraIndicators(auraIndicatorsDB)
    end

    local entries = auraIndicatorsDB.entries or {}
    if #entries == 0 then
        ctx.selectedAuraIndex = 1
        ctx.selectedIndicatorIndex = 1
    else
        ctx.selectedAuraIndex = math.max(1, math.min(ctx.selectedAuraIndex, #entries))
        local selectedEntry = entries[ctx.selectedAuraIndex]
        local indicatorCount = #(selectedEntry and selectedEntry.indicators or {})
        ctx.selectedIndicatorIndex = math.max(1, math.min(ctx.selectedIndicatorIndex, math.max(indicatorCount, 1)))
    end

    ctx.ReleaseAuraRows()
    ctx.ReleaseSuggestRows()
    ctx.ReleaseIndicatorRows()
    ctx.ClearDetailWidgets()

    local C = ctx.C
    local GUI = ctx.GUI
    local specID = GetPlayerSpecID()
    ctx.title:SetText("|cFF34D399" .. (GetPlayerSpecName(specID) or "Tracked Auras") .. "|r")

    local leftWidth = ctx.LayoutEditorColumns()
    local leftY = 0
    local rightY = RIGHT_CONFIG_TOP_OFFSET
    ctx.auraRowsContainer:ClearAllPoints()
    ctx.auraRowsContainer:SetPoint("TOPLEFT", ctx.leftColumn, "TOPLEFT", 0, -LIST_START_GAP)
    ctx.auraRowsContainer:SetPoint("TOPRIGHT", ctx.leftColumn, "TOPRIGHT", 0, -LIST_START_GAP)

    for index, entry in ipairs(entries) do
        local row = ctx.AcquireAuraRow()
        row:SetParent(ctx.auraRowsContainer)
        row.icon:SetTexture(GetSpellTexture(entry.spellID))

        local spellName = GetSpellName(entry.spellID) or ("Spell " .. tostring(entry.spellID))
        row.name:SetText((entry.enabled ~= false and "|cFFFFFFFF" or "|cFF808080") .. spellName .. "|r")

        local iconCount, barCount, tintCount = CountIndicatorTypes(entry)
        row.summary:SetText(string.format("I:%d B:%d T:%d%s", iconCount, barCount, tintCount, entry.onlyMine and " |cff56D1FFMine|r" or ""))

        local selected = index == ctx.selectedAuraIndex
        row:SetBackdropColor(selected and 0.16 or 0.08, selected and 0.16 or 0.08, selected and 0.2 or 0.08, 0.9)
        row:SetBackdropBorderColor(
            selected and ((C.accent and C.accent[1]) or 0.3) or ((C.border and C.border[1]) or 0.2),
            selected and ((C.accent and C.accent[2]) or 0.7) or ((C.border and C.border[2]) or 0.2),
            selected and ((C.accent and C.accent[3]) or 1) or ((C.border and C.border[3]) or 0.2),
            1
        )

        row:SetScript("OnClick", function()
            if ctx.auraDragState.suppressClick then
                ctx.auraDragState.suppressClick = nil
                return
            end
            ctx.selectedAuraIndex = index
            ctx.selectedIndicatorIndex = 1
            ctx.rebuildAuraList()
        end)
        row:SetScript("OnDragStart", function(self)
            local drag = ctx.auraDragState
            drag.active = true
            drag.row = self
            drag.fromIndex = index
            drag.toIndex = index
            drag.baseStrata = self:GetFrameStrata()
            drag.baseLevel = self:GetFrameLevel()
            drag.baseAlpha = self:GetAlpha()
            self:StartMoving()
            self:SetFrameStrata("TOOLTIP")
            self:SetFrameLevel(400)
            self:SetAlpha(0.92)
            self.dragHandle:SetBackdropBorderColor((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 1)
            LayoutDraggableRows(ctx.auraRowsContainer, ctx.activeAuraRows, ctx.auraPlaceholder, ctx.auraRowStep, self, drag.toIndex)
            self:SetScript("OnUpdate", function(dragged)
                if not drag.active then
                    return
                end
                local nextIndex = ComputeDropIndex(ctx.activeAuraRows, ctx.auraRowsContainer, ctx.auraRowStep)
                if nextIndex ~= drag.toIndex then
                    drag.toIndex = nextIndex
                    LayoutDraggableRows(ctx.auraRowsContainer, ctx.activeAuraRows, ctx.auraPlaceholder, ctx.auraRowStep, dragged, drag.toIndex)
                end
            end)
        end)
        row:SetScript("OnDragStop", function(self)
            local drag = ctx.auraDragState
            if not drag.active then
                return
            end
            self:StopMovingOrSizing()
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(drag.baseAlpha or 1)
            self:SetFrameStrata(drag.baseStrata or "MEDIUM")
            if drag.baseLevel then
                self:SetFrameLevel(drag.baseLevel)
            end
            self.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
            drag.active = false
            local changed, targetIndex = CommitReorder(entries, drag.fromIndex or index, drag.toIndex or index)
            drag.row = nil
            drag.fromIndex = nil
            drag.toIndex = nil
            drag.baseStrata = nil
            drag.baseLevel = nil
            drag.baseAlpha = nil
            ctx.auraPlaceholder:Hide()
            if changed then
                ctx.selectedAuraIndex = RemapSelectedIndex(ctx.selectedAuraIndex, index, targetIndex)
                drag.suppressClick = true
                ctx.NotifyChanged()
            end
            ctx.rebuildAuraList()
        end)
        row.remove:SetScript("OnClick", function()
            table.remove(entries, index)
            ctx.NotifyChanged()
            ctx.rebuildAuraList()
        end)

        ctx.activeAuraRows[#ctx.activeAuraRows + 1] = row
    end

    local auraRowsHeight = LayoutDraggableRows(ctx.auraRowsContainer, ctx.activeAuraRows, ctx.auraPlaceholder, ctx.auraRowStep)
    leftY = -(LIST_START_GAP + auraRowsHeight + 4)
    ctx.addHeader:ClearAllPoints()
    ctx.addHeader:SetPoint("TOPLEFT", 0, leftY)
    ctx.addHeader:SetText("|cFFAAAAAAAdd Tracked Aura:|r")
    leftY = leftY - 16

    ctx.inputRow:ClearAllPoints()
    ctx.inputRow:SetPoint("TOPLEFT", 0, leftY)
    ctx.inputRow:SetPoint("TOPRIGHT", ctx.leftColumn, "TOPRIGHT", 0, leftY)
    leftY = leftY - 28

    local suggestions = GetSuggestionSpells(entries)
    if #suggestions > 0 then
        local contentWidth = leftWidth
        if type(contentWidth) ~= "number" or contentWidth < SUGGEST_CELL_STRIDE then
            contentWidth = MAX_LEFT_COLUMN_WIDTH
        end
        local cols = math.max(1, math.floor(contentWidth / SUGGEST_CELL_STRIDE))
        local rows = math.ceil(#suggestions / cols)
        for index, spell in ipairs(suggestions) do
            local cell = ctx.AcquireSuggestCell()
            local col = (index - 1) % cols
            local row = math.floor((index - 1) / cols)
            cell:SetParent(ctx.leftColumn)
            cell:SetPoint("TOPLEFT", col * SUGGEST_CELL_STRIDE, leftY - (row * SUGGEST_CELL_STRIDE))
            cell._spell = spell
            cell.icon:SetTexture(spell.icon or GetSpellTexture(spell.id))
            cell:SetScript("OnClick", function(_, button)
                if button == "LeftButton" or button == "RightButton" then
                    ctx.AddNewAura(spell.id)
                    ctx.rebuildAuraList()
                end
            end)
            ctx.activeSuggestRows[#ctx.activeSuggestRows + 1] = cell
        end
        leftY = leftY - (rows * SUGGEST_CELL_STRIDE) - 4
    end

    local selectedEntry = entries[ctx.selectedAuraIndex]
    if selectedEntry then
        ctx.selectedAuraLabel:ClearAllPoints()
        ctx.selectedAuraLabel:SetPoint("TOPLEFT", ctx.rightColumn, "TOPLEFT", 0, rightY)
        ctx.selectedAuraLabel:SetPoint("TOPRIGHT", ctx.rightColumn, "TOPRIGHT", 0, rightY)
        ctx.selectedAuraLabel:SetText("Configure: " .. (GetSpellName(selectedEntry.spellID) or ("Spell " .. tostring(selectedEntry.spellID))))
        rightY = rightY - RIGHT_CONFIG_LABEL_STEP

        ctx.indicatorActionsRow:ClearAllPoints()
        ctx.indicatorActionsRow:SetPoint("TOPLEFT", ctx.rightColumn, "TOPLEFT", 0, rightY)
        ctx.indicatorActionsRow:SetPoint("TOPRIGHT", ctx.rightColumn, "TOPRIGHT", 0, rightY)
        ctx.indicatorActionsRow:Show()
        rightY = rightY - RIGHT_CONFIG_ACTION_STEP

        local indicatorCount = #(selectedEntry.indicators or {})
        if indicatorCount == 0 then
            ctx.selectedIndicatorIndex = 1
        else
            ctx.selectedIndicatorIndex = math.max(1, math.min(ctx.selectedIndicatorIndex, indicatorCount))
        end

        for index, indicator in ipairs(selectedEntry.indicators or {}) do
            local row = ctx.AcquireIndicatorRow()
            row:SetParent(ctx.indicatorRowsContainer)
            row.label:SetText(GetIndicatorLabel(indicator, index))

            local selected = index == ctx.selectedIndicatorIndex
            row:SetBackdropColor(selected and 0.15 or 0.07, selected and 0.15 or 0.07, selected and 0.18 or 0.07, 0.9)
            row:SetBackdropBorderColor(
                selected and ((C.accent and C.accent[1]) or 0.3) or ((C.border and C.border[1]) or 0.2),
                selected and ((C.accent and C.accent[2]) or 0.7) or ((C.border and C.border[2]) or 0.2),
                selected and ((C.accent and C.accent[3]) or 1) or ((C.border and C.border[3]) or 0.2),
                1
            )

            row:SetScript("OnClick", function()
                if ctx.indicatorDragState.suppressClick then
                    ctx.indicatorDragState.suppressClick = nil
                    return
                end
                ctx.selectedIndicatorIndex = index
                ctx.rebuildAuraList()
            end)
            row:SetScript("OnDragStart", function(self)
                local drag = ctx.indicatorDragState
                drag.active = true
                drag.row = self
                drag.fromIndex = index
                drag.toIndex = index
                drag.baseStrata = self:GetFrameStrata()
                drag.baseLevel = self:GetFrameLevel()
                drag.baseAlpha = self:GetAlpha()
                self:StartMoving()
                self:SetFrameStrata("TOOLTIP")
                self:SetFrameLevel(401)
                self:SetAlpha(0.92)
                self.dragHandle:SetBackdropBorderColor((C.accent and C.accent[1]) or 0.3, (C.accent and C.accent[2]) or 0.7, (C.accent and C.accent[3]) or 1, 1)
                LayoutDraggableRows(ctx.indicatorRowsContainer, ctx.activeIndicatorRows, ctx.indicatorPlaceholder, ctx.indicatorRowStep, self, drag.toIndex)
                self:SetScript("OnUpdate", function(dragged)
                    if not drag.active then
                        return
                    end
                    local nextIndex = ComputeDropIndex(ctx.activeIndicatorRows, ctx.indicatorRowsContainer, ctx.indicatorRowStep)
                    if nextIndex ~= drag.toIndex then
                        drag.toIndex = nextIndex
                        LayoutDraggableRows(ctx.indicatorRowsContainer, ctx.activeIndicatorRows, ctx.indicatorPlaceholder, ctx.indicatorRowStep, dragged, drag.toIndex)
                    end
                end)
            end)
            row:SetScript("OnDragStop", function(self)
                local drag = ctx.indicatorDragState
                if not drag.active then
                    return
                end
                self:StopMovingOrSizing()
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(drag.baseAlpha or 1)
                self:SetFrameStrata(drag.baseStrata or "MEDIUM")
                if drag.baseLevel then
                    self:SetFrameLevel(drag.baseLevel)
                end
                self.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
                drag.active = false
                local changed, targetIndex = CommitReorder(selectedEntry.indicators, drag.fromIndex or index, drag.toIndex or index)
                drag.row = nil
                drag.fromIndex = nil
                drag.toIndex = nil
                drag.baseStrata = nil
                drag.baseLevel = nil
                drag.baseAlpha = nil
                ctx.indicatorPlaceholder:Hide()
                if changed then
                    ctx.selectedIndicatorIndex = RemapSelectedIndex(ctx.selectedIndicatorIndex, index, targetIndex)
                    drag.suppressClick = true
                    ctx.NotifyChanged()
                end
                ctx.rebuildAuraList()
            end)
            row.remove:SetScript("OnClick", function()
                table.remove(selectedEntry.indicators, index)
                if normalizeAuraIndicators then
                    normalizeAuraIndicators(auraIndicatorsDB)
                end
                ctx.NotifyChanged()
                ctx.rebuildAuraList()
            end)

            ctx.activeIndicatorRows[#ctx.activeIndicatorRows + 1] = row
        end

        ctx.indicatorRowsContainer:ClearAllPoints()
        ctx.indicatorRowsContainer:SetPoint("TOPLEFT", ctx.rightColumn, "TOPLEFT", 0, rightY)
        ctx.indicatorRowsContainer:SetPoint("TOPRIGHT", ctx.rightColumn, "TOPRIGHT", 0, rightY)
        local indicatorRowsHeight = LayoutDraggableRows(ctx.indicatorRowsContainer, ctx.activeIndicatorRows, ctx.indicatorPlaceholder, ctx.indicatorRowStep)
        rightY = rightY - indicatorRowsHeight

        local selectedIndicator = selectedEntry.indicators and selectedEntry.indicators[ctx.selectedIndicatorIndex]
        if selectedIndicator then
            rightY = rightY - 6
            ctx.detailArea:ClearAllPoints()
            ctx.detailArea:SetPoint("TOPLEFT", ctx.rightColumn, "TOPLEFT", 0, rightY)
            ctx.detailArea:SetPoint("TOPRIGHT", ctx.rightColumn, "TOPRIGHT", 0, rightY)

            local detailY = -2
            local function AddDetailWidget(widget, height)
                ctx.RegisterDetailWidget(widget)
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", PAD, detailY)
                widget:SetPoint("TOPRIGHT", ctx.detailArea, "TOPRIGHT", -PAD, detailY)
                detailY = detailY - height
            end

            AddDetailWidget(GUI:CreateFormCheckbox(ctx.detailArea, "Aura Enabled", "enabled", selectedEntry, function()
                ctx.NotifyChanged()
                ctx.rebuildAuraList()
            end, {
                description = "Toggle tracking of this aura. When off, none of its attached indicators display.",
            }), FORM_ROW)
            AddDetailWidget(GUI:CreateFormCheckbox(ctx.detailArea, "Only My Cast", "onlyMine", selectedEntry, function()
                ctx.NotifyChanged()
                ctx.rebuildAuraList()
            end, {
                description = "Only track this aura when you applied it.",
            }), FORM_ROW)
            AddDetailWidget(GUI:CreateFormDropdown(ctx.detailArea, "Indicator Type", AURA_INDICATOR_TYPE_OPTIONS, "type", selectedIndicator, function()
                if normalizeAuraIndicators then
                    normalizeAuraIndicators(auraIndicatorsDB)
                end
                ctx.NotifyChanged()
                ctx.rebuildAuraList()
            end, {
                description = "How this indicator displays: icon in the shared strip, a standalone bar, or a tint applied across the health bar.",
            }), DROP_ROW)
            AddDetailWidget(GUI:CreateFormCheckbox(ctx.detailArea, "Indicator Enabled", "enabled", selectedIndicator, function()
                ctx.NotifyChanged()
                ctx.rebuildAuraList()
            end, {
                description = "Toggle just this indicator without removing it.",
            }), FORM_ROW)

            if selectedIndicator.type == "bar" then
                AddDetailWidget(GUI:CreateFormDropdown(ctx.detailArea, "Orientation", BAR_ORIENTATION_OPTIONS, "orientation", selectedIndicator, function()
                    ctx.NotifyChanged()
                    ctx.rebuildAuraList()
                end, {
                    description = "Whether the bar drains horizontally or vertically as the tracked aura ticks down.",
                }), DROP_ROW)
                AddDetailWidget(GUI:CreateFormSlider(ctx.detailArea, "Thickness", 1, 20, 1, "thickness", selectedIndicator, ctx.onChange, nil, {
                    description = "Pixel thickness of the bar.",
                }), SLIDER_HEIGHT)
                AddDetailWidget(GUI:CreateFormSlider(ctx.detailArea, "Width / Height", 4, 200, 1, "length", selectedIndicator, ctx.onChange, nil, {
                    description = "Pixel length of the bar.",
                }), SLIDER_HEIGHT)
                AddDetailWidget(GUI:CreateFormCheckbox(ctx.detailArea, "Match Frame Width / Height", "matchFrameSize", selectedIndicator, function()
                    ctx.NotifyChanged()
                    ctx.rebuildAuraList()
                end, {
                    description = "Stretch the bar to match the frame size.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormDropdown(ctx.detailArea, "Anchor", NINE_POINT_OPTIONS, "anchor", selectedIndicator, ctx.onChange, {
                    description = "Where on the frame the bar is anchored.",
                }), DROP_ROW)
                AddDetailWidget(GUI:CreateFormSlider(ctx.detailArea, "X Offset", -100, 100, 1, "offsetX", selectedIndicator, ctx.onChange, nil, {
                    description = "Horizontal pixel offset for the bar from its anchor.",
                }), SLIDER_HEIGHT)
                AddDetailWidget(GUI:CreateFormSlider(ctx.detailArea, "Y Offset", -100, 100, 1, "offsetY", selectedIndicator, ctx.onChange, nil, {
                    description = "Vertical pixel offset for the bar from its anchor.",
                }), SLIDER_HEIGHT)
                AddDetailWidget(GUI:CreateFormColorPicker(ctx.detailArea, "Bar Color", "color", selectedIndicator, ctx.onChange, nil, {
                    description = "Fill color of the bar while the tracked aura is active.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormColorPicker(ctx.detailArea, "Background Color", "backgroundColor", selectedIndicator, ctx.onChange, nil, {
                    description = "Color drawn behind the bar fill.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormCheckbox(ctx.detailArea, "Hide Border", "hideBorder", selectedIndicator, function()
                    ctx.NotifyChanged()
                    ctx.rebuildAuraList()
                end, {
                    description = "Remove the border drawn around the bar.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormSlider(ctx.detailArea, "Border Size", 1, 8, 1, "borderSize", selectedIndicator, ctx.onChange, nil, {
                    description = "Pixel thickness of the bar's border.",
                }), SLIDER_HEIGHT)
                AddDetailWidget(GUI:CreateFormColorPicker(ctx.detailArea, "Border Color", "borderColor", selectedIndicator, ctx.onChange, nil, {
                    description = "Color of the bar's border.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormSlider(ctx.detailArea, "Low-Time Seconds", 0, 30, 0.5, "lowTimeThreshold", selectedIndicator, ctx.onChange, {
                    precision = 1,
                }, {
                    description = "When the remaining duration drops below this many seconds, the bar switches to the Low-Time Color.",
                }), SLIDER_HEIGHT)
                AddDetailWidget(GUI:CreateFormColorPicker(ctx.detailArea, "Low-Time Color", "lowTimeColor", selectedIndicator, ctx.onChange, nil, {
                    description = "Bar fill color used once the remaining duration crosses the Low-Time threshold.",
                }), FORM_ROW)
            elseif selectedIndicator.type == "healthBarColor" then
                AddDetailWidget(GUI:CreateFormColorPicker(ctx.detailArea, "Tint Color", "color", selectedIndicator, ctx.onChange, nil, {
                    description = "Color tint applied across the health bar while the tracked aura is active.",
                }), FORM_ROW)
                AddDetailWidget(GUI:CreateFormDropdown(ctx.detailArea, "Tint Animation", HEALTH_TINT_ANIMATION_OPTIONS, "animation", selectedIndicator, ctx.onChange, {
                    description = "How the health-bar tint appears when the tracked aura is detected.",
                }), DROP_ROW)
                AddDetailWidget(CreateHealthTintAnimationPreview(ctx.detailArea, GUI, C, selectedIndicator), 72)
            else
                local note = GUI:CreateLabel(ctx.detailArea, "Icon indicators use the shared icon-strip settings in the section above.", 11, C.textMuted)
                note:SetJustifyH("LEFT")
                AddDetailWidget(note, 28)
            end

            ctx.detailArea:SetHeight(math.abs(detailY) + 8)
            rightY = rightY - (ctx.detailArea:GetHeight() + 4)
        else
            ctx.detailArea:SetHeight(1)
        end
    else
        ctx.selectedAuraLabel:SetText("No tracked auras yet.")
        ctx.selectedAuraLabel:ClearAllPoints()
        ctx.selectedAuraLabel:SetPoint("TOPLEFT", ctx.rightColumn, "TOPLEFT", 0, rightY)
        ctx.selectedAuraLabel:SetPoint("TOPRIGHT", ctx.rightColumn, "TOPRIGHT", 0, rightY)
        ctx.indicatorActionsRow:Hide()
        ctx.detailArea:SetHeight(1)
        rightY = rightY - 24
    end

    local contentHeight = math.max(math.abs(leftY), math.abs(rightY), 1)
    ctx.auraListArea:SetHeight(contentHeight)
    ctx.leftColumn:SetHeight(contentHeight)
    ctx.rightColumn:SetHeight(contentHeight)
    ctx.host:SetHeight(56 + ctx.auraListArea:GetHeight())
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
    local editor = {
        selectedAuraIndex = 1,
        selectedIndicatorIndex = 1,
    }

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

    local leftColumn = CreateFrame("Frame", nil, auraListArea)
    leftColumn:SetPoint("TOPLEFT", auraListArea, "TOPLEFT", 0, 0)
    leftColumn:SetHeight(1)

    local rightColumn = CreateFrame("Frame", nil, auraListArea)
    rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", COLUMN_GAP, 0)
    rightColumn:SetPoint("TOPRIGHT", auraListArea, "TOPRIGHT", 0, 0)
    rightColumn:SetHeight(1)

    local auraRowHeight = 28
    local auraRowStep = 30
    local indicatorRowHeight = 24
    local indicatorRowStep = 26

    local auraRowsContainer = CreateFrame("Frame", nil, leftColumn)
    auraRowsContainer:SetPoint("TOPLEFT", 0, 0)
    auraRowsContainer:SetPoint("TOPRIGHT", leftColumn, "TOPRIGHT", 0, 0)
    auraRowsContainer:SetHeight(1)

    local indicatorRowsContainer = CreateFrame("Frame", nil, rightColumn)
    indicatorRowsContainer:SetPoint("TOPLEFT", 0, 0)
    indicatorRowsContainer:SetPoint("TOPRIGHT", rightColumn, "TOPRIGHT", 0, 0)
    indicatorRowsContainer:SetHeight(1)

    local addHeader = leftColumn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addHeader:SetJustifyH("LEFT")

    local inputRow = CreateFrame("Frame", nil, leftColumn)
    inputRow:SetHeight(24)

    local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
    inputBox:SetSize(80, 20)
    inputBox:SetPoint("LEFT", 0, 0)
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
    addManualButton:SetPoint("LEFT", inputLabel, "RIGHT", 8, 0)
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

    local indicatorActionsRow = CreateFrame("Frame", nil, rightColumn)
    indicatorActionsRow:SetHeight(26)
    indicatorActionsRow:SetPoint("TOPLEFT", rightColumn, "TOPLEFT", 0, 0)
    indicatorActionsRow:SetPoint("TOPRIGHT", rightColumn, "TOPRIGHT", 0, 0)

    local addIconButton = GUI:CreateButton(indicatorActionsRow, "Add Icon", 74, 22)
    addIconButton:SetPoint("LEFT", 0, 0)
    local addBarButton = GUI:CreateButton(indicatorActionsRow, "Add Bar", 68, 22)
    addBarButton:SetPoint("LEFT", addIconButton, "RIGHT", 6, 0)
    local addTintButton = GUI:CreateButton(indicatorActionsRow, "Add Tint", 72, 22)
    addTintButton:SetPoint("LEFT", addBarButton, "RIGHT", 6, 0)
    GUI:AttachTooltip(addTintButton,
        "Add a tint indicator — recolors the unit's health bar while the selected aura is active. Useful for at-a-glance buff/debuff awareness without adding screen clutter.",
        "Add Tint Indicator")

    local selectedAuraLabel = rightColumn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedAuraLabel:SetJustifyH("LEFT")

    local detailArea = CreateFrame("Frame", nil, rightColumn)
    detailArea:SetPoint("TOPLEFT", rightColumn, "TOPLEFT", 0, 0)
    detailArea:SetPoint("TOPRIGHT", rightColumn, "TOPRIGHT", 0, 0)
    detailArea:SetHeight(1)

    editor.GUI = GUI
    editor.C = C
    editor.host = host
    editor.auraIndicatorsDB = auraIndicatorsDB
    editor.normalizeAuraIndicators = normalizeAuraIndicators
    editor.onChange = onChange
    editor.title = title
    editor.auraListArea = auraListArea
    editor.leftColumn = leftColumn
    editor.rightColumn = rightColumn
    editor.auraRowsContainer = auraRowsContainer
    editor.indicatorRowsContainer = indicatorRowsContainer
    editor.addHeader = addHeader
    editor.inputRow = inputRow
    editor.indicatorActionsRow = indicatorActionsRow
    editor.selectedAuraLabel = selectedAuraLabel
    editor.detailArea = detailArea

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

    editor.auraRowStep = auraRowStep
    editor.indicatorRowStep = indicatorRowStep
    editor.auraPlaceholder = auraPlaceholder
    editor.indicatorPlaceholder = indicatorPlaceholder
    editor.auraDragState = auraDragState
    editor.indicatorDragState = indicatorDragState

    local function NotifyChanged()
        if normalizeAuraIndicators then
            normalizeAuraIndicators(auraIndicatorsDB)
        end
        if type(onChange) == "function" then
            onChange()
        end
    end
    editor.NotifyChanged = NotifyChanged

    local function AcquireAuraRow()
        local row = table.remove(auraRows)
        if row then
            row:Show()
            row:ClearAllPoints()
            return row
        end

        row = CreateFrame("Button", nil, leftColumn, "BackdropTemplate")
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
    editor.AcquireAuraRow = AcquireAuraRow

    local activeAuraRows = {}
    editor.activeAuraRows = activeAuraRows
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
    editor.ReleaseAuraRows = ReleaseAuraRows

    local function AcquireSuggestCell()
        local cell = table.remove(suggestRows)
        if cell then
            cell:Show()
            cell:ClearAllPoints()
            return cell
        end

        cell = CreateFrame("Button", nil, leftColumn, "BackdropTemplate")
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
    editor.AcquireSuggestCell = AcquireSuggestCell

    local activeSuggestRows = {}
    editor.activeSuggestRows = activeSuggestRows
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
    editor.ReleaseSuggestRows = ReleaseSuggestRows

    local function AcquireIndicatorRow()
        local row = table.remove(indicatorRows)
        if row then
            row:Show()
            row:ClearAllPoints()
            return row
        end

        row = CreateFrame("Button", nil, rightColumn, "BackdropTemplate")
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
    editor.AcquireIndicatorRow = AcquireIndicatorRow

    local activeIndicatorRows = {}
    editor.activeIndicatorRows = activeIndicatorRows
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
    editor.ReleaseIndicatorRows = ReleaseIndicatorRows

    local function ClearDetailWidgets()
        for _, widget in ipairs(detailWidgets) do
            widget:Hide()
        end
        wipe(detailWidgets)
    end
    editor.ClearDetailWidgets = ClearDetailWidgets

    local function RegisterDetailWidget(widget)
        detailWidgets[#detailWidgets + 1] = widget
        return widget
    end
    editor.RegisterDetailWidget = RegisterDetailWidget

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
        editor.selectedAuraIndex = #auraIndicatorsDB.entries
        editor.selectedIndicatorIndex = 1
        NotifyChanged()
    end
    editor.AddNewAura = AddNewAura

    local rebuildAuraList

    local function AddIndicator(indicatorType)
        local entry = auraIndicatorsDB.entries and auraIndicatorsDB.entries[editor.selectedAuraIndex]
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
        editor.selectedIndicatorIndex = #entry.indicators
        NotifyChanged()
        if rebuildAuraList then
            rebuildAuraList()
        end
    end
    editor.AddIndicator = AddIndicator

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

    local function LayoutEditorColumns()
        local width = auraListArea:GetWidth()
        if type(width) ~= "number" or width < 1 then
            width = 960
        end

        local minStableWidth = MAX_LEFT_COLUMN_WIDTH + COLUMN_GAP + MIN_RIGHT_COLUMN_WIDTH
        local leftWidth
        if width >= minStableWidth then
            leftWidth = MAX_LEFT_COLUMN_WIDTH
        else
            leftWidth = math.floor((width - COLUMN_GAP) * 0.46)
            leftWidth = math.max(MIN_COLUMN_WIDTH, math.min(leftWidth, MAX_LEFT_COLUMN_WIDTH))
            if width - leftWidth - COLUMN_GAP < MIN_RIGHT_COLUMN_WIDTH then
                leftWidth = math.max(MIN_COLUMN_WIDTH, width - COLUMN_GAP - MIN_RIGHT_COLUMN_WIDTH)
            end
        end

        leftColumn:ClearAllPoints()
        leftColumn:SetPoint("TOPLEFT", auraListArea, "TOPLEFT", 0, 0)
        leftColumn:SetWidth(leftWidth)

        rightColumn:ClearAllPoints()
        rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", COLUMN_GAP, 0)
        rightColumn:SetPoint("TOPRIGHT", auraListArea, "TOPRIGHT", 0, 0)

        return leftWidth
    end
    editor.LayoutEditorColumns = LayoutEditorColumns

    rebuildAuraList = function()
        RebuildAuraList(editor)
    end
    editor.rebuildAuraList = rebuildAuraList

    rebuildAuraList()
    return host:GetHeight()
end
