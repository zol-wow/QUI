local ADDON_NAME, ns = ...

local SpellList = ns.QUI_GroupFramesSpellListSettings

local PinnedAurasEditor = ns.QUI_GroupFramesPinnedAurasSettings or {}
ns.QUI_GroupFramesPinnedAurasSettings = PinnedAurasEditor

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

local PINNED_DISPLAY_OPTIONS = {
    { value = "icon", text = "Icon" },
    { value = "square", text = "Colored Square" },
}

local PINNED_ANCHOR_SHORT = {
    TOPLEFT = "TL",
    TOP = "T",
    TOPRIGHT = "TR",
    LEFT = "L",
    CENTER = "C",
    RIGHT = "R",
    BOTTOMLEFT = "BL",
    BOTTOM = "B",
    BOTTOMRIGHT = "BR",
}

local PINNED_ANCHOR_ROTATION = {
    "TOPLEFT",
    "TOPRIGHT",
    "BOTTOMLEFT",
    "BOTTOMRIGHT",
    "TOP",
    "BOTTOM",
    "LEFT",
    "RIGHT",
    "CENTER",
}

local function GetGUI()
    return QUI and QUI.GUI or nil
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

local function NextPinnedAnchor(slots)
    local used = {}
    for _, slot in ipairs(slots or {}) do
        local anchor = slot.anchor or "TOPLEFT"
        used[anchor] = (used[anchor] or 0) + 1
    end

    local bestAnchor = PINNED_ANCHOR_ROTATION[1]
    local bestCount = math.huge
    for _, anchor in ipairs(PINNED_ANCHOR_ROTATION) do
        local count = used[anchor] or 0
        if count < bestCount then
            bestAnchor = anchor
            bestCount = count
            if count == 0 then
                break
            end
        end
    end

    return bestAnchor
end

local function GetPinnedSlotMenu()
    local menu = _G.QUI_PinnedSlotMenu
    if menu then
        return menu
    end

    local gui = GetGUI()
    local colors = gui and gui.Colors or {}
    local accent = colors.accent or { 0.204, 0.827, 0.6 }

    menu = CreateFrame("Frame", "QUI_PinnedSlotMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(300)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
    menu:SetBackdropBorderColor(accent[1] * 0.5, accent[2] * 0.5, accent[3] * 0.5, 0.8)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetScript("OnUpdate", function(self)
        if not MouseIsOver(self) and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
            self:Hide()
        end
    end)
    return menu
end

local function ShowPinnedSlotMenu(anchorFrame, slot, onChanged)
    local gui = GetGUI()
    local colors = gui and gui.Colors or {}
    local accent = colors.accent or { 0.204, 0.827, 0.6 }
    local menu = GetPinnedSlotMenu()

    if menu._content then
        menu._content:Hide()
        menu._content:SetParent(nil)
        menu._content = nil
    end

    local items = {}
    items[#items + 1] = { label = "Anchor Position", isTitle = true }
    for _, option in ipairs(NINE_POINT_OPTIONS) do
        items[#items + 1] = {
            label = option.text,
            isSelected = (slot.anchor or "TOPLEFT") == option.value,
            action = function()
                slot.anchor = option.value
                if type(onChanged) == "function" then
                    onChanged()
                end
            end,
        }
    end
    items[#items + 1] = { isDivider = true }
    items[#items + 1] = { label = "Display Type", isTitle = true }
    for _, option in ipairs(PINNED_DISPLAY_OPTIONS) do
        items[#items + 1] = {
            label = option.text,
            isSelected = (slot.displayType or "icon") == option.value,
            action = function()
                slot.displayType = option.value
                if option.value == "square" and not slot.color then
                    slot.color = { 0.2, 0.8, 0.2, 1 }
                end
                if type(onChanged) == "function" then
                    onChanged()
                end
            end,
        }
    end
    if (slot.displayType or "icon") == "square" then
        items[#items + 1] = { isDivider = true }
        items[#items + 1] = { isColorPicker = true }
    end

    local itemHeight = 20
    local titleHeight = 20
    local dividerHeight = 8
    local colorPickerHeight = 28
    local menuWidth = 150
    local totalHeight = 4
    for _, item in ipairs(items) do
        if item.isDivider then
            totalHeight = totalHeight + dividerHeight
        elseif item.isTitle then
            totalHeight = totalHeight + titleHeight
        elseif item.isColorPicker then
            totalHeight = totalHeight + colorPickerHeight
        else
            totalHeight = totalHeight + itemHeight
        end
    end

    menu:SetSize(menuWidth, totalHeight)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)

    local content = CreateFrame("Frame", nil, menu)
    content:SetAllPoints(menu)
    menu._content = content

    local y = -2
    for _, item in ipairs(items) do
        if item.isDivider then
            local divider = content:CreateTexture(nil, "ARTWORK")
            divider:SetHeight(1)
            divider:SetPoint("TOPLEFT", 6, y - 3)
            divider:SetPoint("RIGHT", content, "RIGHT", -6, 0)
            divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            y = y - dividerHeight
        elseif item.isTitle then
            local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 8, y)
            label:SetText(item.label)
            label:SetTextColor(accent[1], accent[2], accent[3], 1)
            y = y - titleHeight
        elseif item.isColorPicker then
            local colorRow = CreateFrame("Button", nil, content)
            colorRow:SetSize(menuWidth - 4, colorPickerHeight)
            colorRow:SetPoint("TOPLEFT", 2, y)

            local colorLabel = colorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            colorLabel:SetPoint("LEFT", 12, 0)
            colorLabel:SetText("Color")
            colorLabel:SetTextColor(0.8, 0.8, 0.8, 1)

            local swatch = colorRow:CreateTexture(nil, "ARTWORK")
            swatch:SetSize(16, 16)
            swatch:SetPoint("RIGHT", -8, 0)
            local color = slot.color or { 0.2, 0.8, 0.2, 1 }
            swatch:SetColorTexture(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5, color[4] or 1)

            colorRow:SetScript("OnClick", function()
                menu:Hide()
                local previous = { color[1], color[2], color[3], color[4] }
                local function SetColor(r, g, b, a)
                    slot.color = slot.color or {}
                    slot.color[1] = r
                    slot.color[2] = g
                    slot.color[3] = b
                    slot.color[4] = a or 1
                    if type(onChanged) == "function" then
                        onChanged()
                    end
                end

                local info = {}
                info.r = color[1] or 0.2
                info.g = color[2] or 0.8
                info.b = color[3] or 0.2
                info.opacity = 1 - (color[4] or 1)
                info.hasOpacity = true
                info.swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local rawAlpha = 0
                    if ColorPickerFrame.GetColorAlpha then
                        rawAlpha = ColorPickerFrame:GetColorAlpha() or 0
                    elseif OpacitySliderFrame then
                        rawAlpha = OpacitySliderFrame:GetValue() or 0
                    end
                    SetColor(r, g, b, 1 - rawAlpha)
                end
                info.cancelFunc = function()
                    SetColor(previous[1], previous[2], previous[3], previous[4])
                end
                info.opacityFunc = info.swatchFunc
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            colorRow:SetScript("OnEnter", function()
                colorLabel:SetTextColor(1, 1, 1, 1)
            end)
            colorRow:SetScript("OnLeave", function()
                colorLabel:SetTextColor(0.8, 0.8, 0.8, 1)
            end)
            y = y - colorPickerHeight
        else
            local button = CreateFrame("Button", nil, content)
            button:SetSize(menuWidth - 4, itemHeight)
            button:SetPoint("TOPLEFT", 2, y)
            local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 12, 0)
            label:SetText(item.label)
            local r, g, b = 0.8, 0.8, 0.8
            if item.isSelected then
                r, g, b = accent[1], accent[2], accent[3]
            end
            label:SetTextColor(r, g, b, 1)
            if item.isSelected then
                local check = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                check:SetPoint("RIGHT", -8, 0)
                check:SetText("*")
                check:SetTextColor(accent[1], accent[2], accent[3], 1)
            end
            button:SetScript("OnClick", function()
                menu:Hide()
                if item.action then
                    item.action()
                end
            end)
            button:SetScript("OnEnter", function()
                label:SetTextColor(1, 1, 1, 1)
            end)
            button:SetScript("OnLeave", function()
                label:SetTextColor(r, g, b, 1)
            end)
            y = y - itemHeight
        end
    end

    menu:Show()
end

local function ReleaseRows(rows, reset)
    for _, row in ipairs(rows) do
        if type(reset) == "function" then
            reset(row)
        end
        row:Hide()
        row:ClearAllPoints()
    end
    wipe(rows)
end

function PinnedAurasEditor.RenderSpellSlots(host, pinnedAurasDB, onChange)
    local gui = GetGUI()
    local colors = gui and gui.Colors or {}
    local accent = colors.accent or { 0.204, 0.827, 0.6, 1 }
    if not host or type(pinnedAurasDB) ~= "table" then
        return 1
    end

    pinnedAurasDB.specSlots = type(pinnedAurasDB.specSlots) == "table" and pinnedAurasDB.specSlots or {}

    local specID = GetPlayerSpecID()
    if not specID then
        local noSpec = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noSpec:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -6)
        noSpec:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -6)
        noSpec:SetJustifyH("LEFT")
        noSpec:SetText("No specialization detected. Choose a spec to configure pinned auras.")
        noSpec:SetTextColor(0.6, 0.6, 0.6, 1)
        host:SetHeight(30)
        return 30
    end

    pinnedAurasDB.specSlots[specID] = type(pinnedAurasDB.specSlots[specID]) == "table" and pinnedAurasDB.specSlots[specID] or {}
    local slots = pinnedAurasDB.specSlots[specID]

    local specLabel = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specLabel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -6)
    specLabel:SetText("|cFF34D399" .. (GetPlayerSpecName(specID) or ("Spec " .. specID)) .. "|r")

    local listArea = CreateFrame("Frame", nil, host)
    listArea:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -24)
    listArea:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    listArea:SetHeight(1)

    local addHeader = listArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addHeader:SetJustifyH("LEFT")

    local inputRow = CreateFrame("Frame", nil, listArea)
    inputRow:SetHeight(24)

    local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
    inputBox:SetSize(80, 20)
    inputBox:SetPoint("LEFT", 4, 0)
    inputBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
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
        edgeSize = 1,
    })
    addManualButton:SetBackdropColor(0.15, 0.15, 0.15, 1)
    addManualButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local addManualText = addManualButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addManualText:SetPoint("CENTER")
    addManualText:SetText("Add")

    local spellRowPool = {}
    local suggestRowPool = {}
    local activeSpellRows = {}
    local activeSuggestRows = {}

    local function NotifyChanged()
        if type(onChange) == "function" then
            onChange()
        end
    end

    local function AcquireSpellRow()
        local row = table.remove(spellRowPool)
        if row then
            row:SetParent(listArea)
            row:Show()
            return row
        end

        row = CreateFrame("Button", nil, listArea)
        row:SetHeight(28)
        row:RegisterForClicks("AnyUp")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetJustifyH("LEFT")

        row.anchorButton = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.anchorButton:SetSize(24, 16)
        row.anchorButton:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        row.anchorButton:SetBackdropColor(0.1, 0.1, 0.12, 1)
        row.anchorButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        row.anchorButton:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        row.anchorText = row.anchorButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.anchorText:SetPoint("CENTER")
        row.anchorText:SetTextColor(0.7, 0.85, 1, 1)

        row.removeButton = CreateFrame("Button", nil, row)
        row.removeButton:SetSize(18, 18)
        row.removeButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.removeText = row.removeButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.removeText:SetPoint("CENTER")
        row.removeText:SetText("x")
        row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        row.removeButton:SetScript("OnEnter", function()
            row.removeText:SetTextColor(1, 0.4, 0.4, 1)
        end)
        row.removeButton:SetScript("OnLeave", function()
            row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        end)

        row.name:SetPoint("RIGHT", row.anchorButton, "LEFT", -4, 0)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(self.spellName or "Spell")
            GameTooltip:AddLine("Right-click to configure", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return row
    end

    local function ResetSpellRow(row)
        row.removeButton:SetScript("OnClick", nil)
        row.anchorButton:SetScript("OnClick", nil)
        row.anchorButton:SetScript("OnEnter", nil)
        row.anchorButton:SetScript("OnLeave", nil)
        row:SetScript("OnClick", nil)
        row.spellName = nil
        row.icon:SetVertexColor(1, 1, 1, 1)
        table.insert(spellRowPool, row)
    end

    local function AcquireSuggestRow()
        local row = table.remove(suggestRowPool)
        if row then
            row:SetParent(listArea)
            row:Show()
            return row
        end

        row = CreateFrame("Frame", nil, listArea)
        row:SetHeight(22)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetJustifyH("LEFT")

        row.addButton = CreateFrame("Button", nil, row)
        row.addButton:SetSize(18, 18)
        row.addButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.addText = row.addButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.addText:SetPoint("CENTER")
        row.addText:SetText("+")
        row.addText:SetTextColor(0.3, 0.8, 0.3, 1)
        row.addButton:SetScript("OnEnter", function()
            row.addText:SetTextColor(0.4, 1, 0.4, 1)
        end)
        row.addButton:SetScript("OnLeave", function()
            row.addText:SetTextColor(0.3, 0.8, 0.3, 1)
        end)

        row.name:SetPoint("RIGHT", row.addButton, "LEFT", -4, 0)
        return row
    end

    local function ResetSuggestRow(row)
        row.addButton:SetScript("OnClick", nil)
        table.insert(suggestRowPool, row)
    end

    local function RebuildSpellList()
        ReleaseRows(activeSpellRows, ResetSpellRow)
        ReleaseRows(activeSuggestRows, ResetSuggestRow)

        local y = 0
        for index, slot in ipairs(slots) do
            local row = AcquireSpellRow()
            row:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", listArea, "RIGHT", 0, 0)

            row.icon:SetTexture(GetSpellTexture(slot.spellID))
            if slot.displayType == "square" then
                local color = slot.color or { 0.2, 0.8, 0.2, 1 }
                row.icon:SetVertexColor(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5, color[4] or 1)
            else
                row.icon:SetVertexColor(1, 1, 1, 1)
            end

            local spellName = GetSpellName(slot.spellID) or ("Spell " .. tostring(slot.spellID))
            row.name:SetText(spellName)
            row.spellName = spellName

            local anchor = slot.anchor or "TOPLEFT"
            row.anchorText:SetText(PINNED_ANCHOR_SHORT[anchor] or "TL")

            local function ShowSlotMenu(frame)
                ShowPinnedSlotMenu(frame, slot, function()
                    RebuildSpellList()
                    NotifyChanged()
                end)
            end

            row.anchorButton:RegisterForClicks("AnyUp")
            row.anchorButton:SetScript("OnClick", function(self)
                ShowSlotMenu(self)
            end)
            row.anchorButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText("Position: " .. anchor)
                GameTooltip:AddLine("Display: " .. ((slot.displayType or "icon") == "square" and "Colored Square" or "Icon"), 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            row.anchorButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    ShowSlotMenu(self)
                end
            end)
            row.removeButton:SetScript("OnClick", function()
                table.remove(slots, index)
                RebuildSpellList()
                NotifyChanged()
            end)

            activeSpellRows[#activeSpellRows + 1] = row
            y = y - 28
        end

        y = y - 6
        addHeader:ClearAllPoints()
        addHeader:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, y)
        addHeader:SetText("|cFFAAAAAAAdd Spells:|r")
        addHeader:Show()
        y = y - 16

        local assigned = {}
        for _, slot in ipairs(slots) do
            if slot.spellID then
                assigned[slot.spellID] = true
            end
        end

        local suggestions = {}
        local addedSuggestion = {}
        local presets = SpellList and SpellList.GetDefaultPresets and SpellList.GetDefaultPresets() or {}
        for _, preset in ipairs(presets) do
            for _, spell in ipairs(preset.spells or {}) do
                if not assigned[spell.id] and not addedSuggestion[spell.id] then
                    suggestions[#suggestions + 1] = spell
                    addedSuggestion[spell.id] = true
                end
            end
        end

        for _, spell in ipairs(suggestions) do
            local row = AcquireSuggestRow()
            row:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", listArea, "RIGHT", 0, 0)
            row.icon:SetTexture(GetSpellTexture(spell.id))
            row.name:SetText(spell.name or GetSpellName(spell.id) or ("Spell " .. tostring(spell.id)))
            row.addButton:SetScript("OnClick", function()
                slots[#slots + 1] = {
                    spellID = spell.id,
                    displayType = "icon",
                    anchor = NextPinnedAnchor(slots),
                }
                RebuildSpellList()
                NotifyChanged()
            end)
            activeSuggestRows[#activeSuggestRows + 1] = row
            y = y - 22
        end

        y = y - 8
        inputRow:ClearAllPoints()
        inputRow:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, y)
        inputRow:SetPoint("RIGHT", listArea, "RIGHT", 0, 0)
        y = y - 28

        addManualButton:SetScript("OnClick", function()
            local spellId = tonumber(inputBox:GetText())
            if spellId and spellId > 0 then
                slots[#slots + 1] = {
                    spellID = spellId,
                    displayType = "icon",
                    anchor = NextPinnedAnchor(slots),
                }
                inputBox:SetText("")
                inputBox:ClearFocus()
                RebuildSpellList()
                NotifyChanged()
            end
        end)
        inputBox:SetScript("OnEnterPressed", function()
            local onClick = addManualButton:GetScript("OnClick")
            if type(onClick) == "function" then
                onClick(addManualButton)
            end
        end)

        local contentHeight = math.max(1, math.abs(y))
        listArea:SetHeight(contentHeight)
        local totalHeight = 24 + contentHeight + 10
        host:SetHeight(totalHeight)
    end

    RebuildSpellList()
    return host:GetHeight()
end
