local ADDON_NAME, ns = ...

local GroupFrameSpellList = ns.QUI_GroupFramesSpellListSettings or {}
ns.QUI_GroupFramesSpellListSettings = GroupFrameSpellList

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

local AURA_FILTER_PRESETS = {
    {
        name = "Restoration Druid",
        specID = 105,
        spells = {
            { id = 774, name = "Rejuvenation" },
            { id = 8936, name = "Regrowth" },
            { id = 33763, name = "Lifebloom" },
            { id = 155777, name = "Germination" },
            { id = 48438, name = "Wild Growth" },
            { id = 102342, name = "Ironbark" },
            { id = 33786, name = "Cyclone" },
        },
    },
    {
        name = "Restoration Shaman",
        specID = 264,
        spells = {
            { id = 61295, name = "Riptide" },
            { id = 974, name = "Earth Shield" },
            { id = 383648, name = "Earth Shield (Ele)" },
            { id = 98008, name = "Spirit Link Totem" },
            { id = 108271, name = "Astral Shift" },
        },
    },
    {
        name = "Holy Paladin",
        specID = 65,
        spells = {
            { id = 53563, name = "Beacon of Light" },
            { id = 156910, name = "Beacon of Faith" },
            { id = 200025, name = "Beacon of Virtue" },
            { id = 156322, name = "Eternal Flame" },
            { id = 223306, name = "Bestow Faith" },
            { id = 1022, name = "Blessing of Protection" },
            { id = 6940, name = "Blessing of Sacrifice" },
            { id = 1044, name = "Blessing of Freedom" },
        },
    },
    {
        name = "Discipline Priest",
        specID = 256,
        spells = {
            { id = 194384, name = "Atonement" },
            { id = 17, name = "Power Word: Shield" },
            { id = 41635, name = "Prayer of Mending" },
            { id = 10060, name = "Power Infusion" },
            { id = 47788, name = "Guardian Spirit" },
            { id = 33206, name = "Pain Suppression" },
        },
    },
    {
        name = "Holy Priest",
        specID = 257,
        spells = {
            { id = 139, name = "Renew" },
            { id = 77489, name = "Echo of Light" },
            { id = 41635, name = "Prayer of Mending" },
            { id = 10060, name = "Power Infusion" },
            { id = 47788, name = "Guardian Spirit" },
            { id = 64844, name = "Divine Hymn" },
        },
    },
    {
        name = "Mistweaver Monk",
        specID = 270,
        spells = {
            { id = 119611, name = "Renewing Mist" },
            { id = 124682, name = "Enveloping Mist" },
            { id = 115175, name = "Soothing Mist" },
            { id = 191840, name = "Essence Font" },
            { id = 116849, name = "Life Cocoon" },
        },
    },
    {
        name = "Preservation Evoker",
        specID = 1468,
        spells = {
            { id = 364343, name = "Echo" },
            { id = 366155, name = "Reversion" },
            { id = 367364, name = "Echo Reversion" },
            { id = 355941, name = "Dream Breath" },
            { id = 376788, name = "Echo Dream Breath" },
            { id = 363502, name = "Dream Flight" },
            { id = 373267, name = "Lifebind" },
        },
    },
    {
        name = "Augmentation Evoker",
        specID = 1473,
        spells = {
            { id = 410089, name = "Prescience" },
            { id = 395152, name = "Ebon Might" },
            { id = 360827, name = "Blistering Scales" },
            { id = 413984, name = "Shifting Sands" },
            { id = 410263, name = "Inferno's Blessing" },
            { id = 410686, name = "Symbiotic Bloom" },
            { id = 369459, name = "Source of Magic" },
        },
    },
    {
        name = "Common Defensives",
        spells = {
            { id = 31821, name = "Aura Mastery" },
            { id = 97463, name = "Rallying Cry" },
            { id = 15286, name = "Vampiric Embrace" },
            { id = 64843, name = "Divine Hymn" },
            { id = 51052, name = "Anti-Magic Zone" },
            { id = 196718, name = "Darkness" },
        },
    },
}

local SPEC_TO_PRESET = {}
for _, preset in ipairs(AURA_FILTER_PRESETS) do
    if preset.specID then
        SPEC_TO_PRESET[preset.specID] = preset
    end
end

local COMMON_DEFENSIVES_PRESET
for _, preset in ipairs(AURA_FILTER_PRESETS) do
    if not preset.specID then
        COMMON_DEFENSIVES_PRESET = preset
        break
    end
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

local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        return GetSpecializationInfo(specIndex)
    end
    return nil
end

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
    local presets = {}
    local specID = GetPlayerSpecID()
    if specID and SPEC_TO_PRESET[specID] then
        presets[#presets + 1] = SPEC_TO_PRESET[specID]
    end
    if COMMON_DEFENSIVES_PRESET then
        presets[#presets + 1] = COMMON_DEFENSIVES_PRESET
    end
    return presets
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
