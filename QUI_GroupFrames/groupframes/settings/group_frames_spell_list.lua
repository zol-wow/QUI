local ADDON_NAME, ns = ...

local GroupFrameSpellList = ns.QUI_GroupFramesSpellListSettings or {}
ns.QUI_GroupFramesSpellListSettings = GroupFrameSpellList
local AuraDefaults = ns.QUI_GroupFramesAuraDefaults

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

local function CreateMiniToggle(parent)
    local gui = QUI and QUI.GUI
    local colors = gui and gui.Colors or {}
    local accent = colors.accent or { 0.204, 0.827, 0.6, 1 }
    local toggleOff = colors.toggleOff or { 1, 1, 1, 0.12 }
    local toggleThumb = colors.toggleThumb or { 1, 1, 1, 1 }

    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(26, 14)

    local track = toggle:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints(toggle)
    track:SetColorTexture(toggleOff[1], toggleOff[2], toggleOff[3], toggleOff[4] or 1)
    toggle.track = track

    local trackMask = toggle:CreateMaskTexture()
    trackMask:SetTexture(ns.Helpers.AssetPath .. "pill_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    trackMask:SetAllPoints(track)
    track:AddMaskTexture(trackMask)
    toggle._trackMask = trackMask

    local thumb = toggle:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 10)
    thumb:SetColorTexture(toggleThumb[1], toggleThumb[2], toggleThumb[3], toggleThumb[4] or 1)
    thumb:SetPoint("LEFT", toggle, "LEFT", 2, 0)
    toggle.thumb = thumb

    local thumbMask = toggle:CreateMaskTexture()
    thumbMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    thumbMask:SetAllPoints(thumb)
    thumb:AddMaskTexture(thumbMask)
    toggle._thumbMask = thumbMask

    local hovered = false

    function toggle:SetToggleState(enabled)
        self._toggleOn = enabled == true

        local hoverBoost = hovered and 0.06 or 0
        if self._toggleOn then
            self.track:SetColorTexture(accent[1], accent[2], accent[3], math.min(1, (accent[4] or 1) + hoverBoost))
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("RIGHT", self, "RIGHT", -2, 0)
        else
            self.track:SetColorTexture(
                toggleOff[1],
                toggleOff[2],
                toggleOff[3],
                math.min(1, (toggleOff[4] or 1) + hoverBoost)
            )
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("LEFT", self, "LEFT", 2, 0)
        end

        if self._thumbMask then
            self._thumbMask:SetAllPoints(self.thumb)
        end
    end

    toggle:SetScript("OnEnter", function(self)
        hovered = true
        self:SetToggleState(self._toggleOn)
    end)

    toggle:SetScript("OnLeave", function(self)
        hovered = false
        self:SetToggleState(self._toggleOn)
    end)

    toggle:SetToggleState(false)
    return toggle
end

local BUFF_BLACKLIST_PRESETS = {
    {
        name = "Raid Buffs",
        spells = {
            { id = 1459, name = "Arcane Intellect" },
            { id = 6673, name = "Battle Shout" },
            { id = 21562, name = "Power Word: Fortitude" },
            { id = 1126, name = "Mark of the Wild" },
            { id = 381753, name = "Skyfury" },
            { id = 381748, name = "Blessing of the Bronze" },
            { id = 369459, name = "Source of Magic" },
        },
    },
}

local DEBUFF_BLACKLIST_PRESETS = {
    {
        name = "Sated / Exhaustion",
        spells = {
            { id = 57723, name = "Exhaustion" },
            { id = 57724, name = "Sated" },
            { id = 80354, name = "Temporal Displacement" },
            { id = 95809, name = "Insanity" },
            { id = 160455, name = "Fatigued" },
            { id = 264689, name = "Fatigued" },
            { id = 390435, name = "Exhaustion" },
        },
    },
    {
        name = "Deserter",
        spells = {
            { id = 26013, name = "Deserter" },
            { id = 71041, name = "Dungeon Deserter" },
        },
    },
}

local function RebuildSpellToggleRows(container, listTable, presets, onChange)
    if type(listTable) ~= "table" then
        container:SetHeight(1)
        return
    end

    if container._rows then
        for _, row in ipairs(container._rows) do
            row:Hide()
        end
    end
    container._rows = container._rows or {}

    local rowHeight = 26
    local headerHeight = 22
    local y = 0
    local rowIndex = 0
    local presetSpellIds = {}

    for _, preset in ipairs(presets or {}) do
        rowIndex = rowIndex + 1
        local headerRow = container._rows[rowIndex]
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, container)
            headerRow:SetHeight(headerHeight)
            headerRow.text = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerRow.text:SetPoint("LEFT", 2, 0)
            headerRow.text:SetJustifyH("LEFT")
            container._rows[rowIndex] = headerRow
        end

        if headerRow.toggle then headerRow.toggle:Hide() end
        if headerRow.removeBtn then headerRow.removeBtn:Hide() end
        headerRow.text:SetText("|cFF56D1FF" .. preset.name .. "|r")
        headerRow:SetPoint("TOPLEFT", 0, y)
        headerRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        headerRow:Show()
        y = y - headerHeight

        for _, spell in ipairs(preset.spells or {}) do
            presetSpellIds[spell.id] = true
            rowIndex = rowIndex + 1
            local row = container._rows[rowIndex]
            if not row then
                row = CreateFrame("Frame", nil, container)
                row:SetHeight(rowHeight)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -44, 0)
                row.text:SetJustifyH("LEFT")
                row.toggle = CreateMiniToggle(row)
                row.toggle:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                container._rows[rowIndex] = row
            end

            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            row.text:SetText(spell.name or GetSpellName(spell.id) or ("Spell " .. spell.id))
            if row.toggle then row.toggle:Show() end
            if row.removeBtn then row.removeBtn:Hide() end

            local spellId = spell.id
            row.toggle:SetToggleState(listTable[spellId] == true)
            row.toggle:SetScript("OnClick", function()
                local enabled = listTable[spellId] ~= true
                if enabled then
                    listTable[spellId] = true
                else
                    listTable[spellId] = nil
                end
                row.toggle:SetToggleState(enabled)
                if onChange then
                    onChange()
                end
            end)

            row:Show()
            y = y - rowHeight
        end
    end

    local extras = {}
    for spellId in pairs(listTable) do
        if not presetSpellIds[spellId] then
            extras[#extras + 1] = spellId
        end
    end
    table.sort(extras)

    if #extras > 0 then
        rowIndex = rowIndex + 1
        local headerRow = container._rows[rowIndex]
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, container)
            headerRow:SetHeight(headerHeight)
            headerRow.text = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerRow.text:SetPoint("LEFT", 2, 0)
            headerRow.text:SetJustifyH("LEFT")
            container._rows[rowIndex] = headerRow
        end

        if headerRow.toggle then headerRow.toggle:Hide() end
        if headerRow.removeBtn then headerRow.removeBtn:Hide() end
        headerRow.text:SetText("|cFF56D1FFOther|r")
        headerRow:SetPoint("TOPLEFT", 0, y)
        headerRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        headerRow:Show()
        y = y - headerHeight

        for _, spellId in ipairs(extras) do
            rowIndex = rowIndex + 1
            local row = container._rows[rowIndex]
            if not row then
                row = CreateFrame("Frame", nil, container)
                row:SetHeight(rowHeight)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetJustifyH("LEFT")
                row.removeBtn = CreateFrame("Button", nil, row)
                row.removeBtn:SetSize(18, 18)
                row.removeBtn:SetPoint("RIGHT", -2, 0)
                row.removeBtnText = row.removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.removeBtnText:SetPoint("CENTER")
                row.removeBtnText:SetText("x")
                row.removeBtnText:SetTextColor(0.8, 0.3, 0.3)
                row.removeBtn:SetScript("OnEnter", function()
                    row.removeBtnText:SetTextColor(1, 0.4, 0.4)
                end)
                row.removeBtn:SetScript("OnLeave", function()
                    row.removeBtnText:SetTextColor(0.8, 0.3, 0.3)
                end)
                container._rows[rowIndex] = row
            end

            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            row.text:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)
            row.text:SetText(GetSpellName(spellId) or ("Spell " .. spellId))
            if row.toggle then row.toggle:Hide() end
            if row.removeBtn then row.removeBtn:Show() end
            row.removeBtn:SetScript("OnClick", function()
                listTable[spellId] = nil
                RebuildSpellToggleRows(container, listTable, presets, onChange)
                if onChange then
                    onChange()
                end
            end)

            row:Show()
            y = y - rowHeight
        end
    end

    for i = rowIndex + 1, #container._rows do
        container._rows[i]:Hide()
    end

    container:SetHeight(math.max(1, math.abs(y)))
    if type(container._onLayoutChanged) == "function" then
        container:_onLayoutChanged(container:GetHeight())
    end
end

function GroupFrameSpellList.GetDefaultPresets()
    if AuraDefaults and type(AuraDefaults.GetDefaultPresets) == "function" then
        return AuraDefaults.GetDefaultPresets()
    end
    return {}
end

function GroupFrameSpellList.GetBuffBlacklistPresets()
    return BUFF_BLACKLIST_PRESETS
end

function GroupFrameSpellList.GetDebuffBlacklistPresets()
    return DEBUFF_BLACKLIST_PRESETS
end

function GroupFrameSpellList.CreateListFrame(parent, listTable, presets, onChange, onLayoutChanged)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(1)
    frame._onLayoutChanged = onLayoutChanged
    RebuildSpellToggleRows(frame, listTable, presets, onChange)
    return frame
end
