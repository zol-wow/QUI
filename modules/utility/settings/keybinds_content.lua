--[[
    QUI Options — CDM Keybinds / Rotation Assist Sub-Tabs
    Migrated to V3 body pattern (Opts.CreateAccentDotLabel + card groups
    + BuildSettingRow). Drop zone + override entry list keep their custom
    layout since they're specialized interactive surfaces, not settings rows.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

local SECTION_GAP = 14

local itemInfoListener = CreateFrame("Frame")
itemInfoListener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local itemInfoListenerCallback = nil
itemInfoListener:SetScript("OnEvent", function(_, event, itemID)
    if event == "GET_ITEM_INFO_RECEIVED" and itemID and itemInfoListenerCallback then
        itemInfoListenerCallback(itemID)
    end
end)

local specChangeListener = CreateFrame("Frame")
specChangeListener:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
local specChangeCallback = nil
specChangeListener:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player" and specChangeCallback then
        C_Timer.After(0.1, specChangeCallback)
    end
end)

local function RefreshCDMKeybinds()
    if _G.QUI_RefreshKeybinds then _G.QUI_RefreshKeybinds() end
end

local function RefreshCustomTrackerKeybinds()
    if _G.QUI_RefreshCustomTrackerKeybinds then _G.QUI_RefreshCustomTrackerKeybinds() end
end

local function RefreshAllKeybindDisplays()
    RefreshCDMKeybinds()
    RefreshCustomTrackerKeybinds()
end

---------------------------------------------------------------------------
-- Override list — drop zone + dynamic entry rows + enable toggles.
-- Self-contained section that draws starting at startY and returns the
-- final y. The caller is responsible for sizing the host frame; this
-- function does call host:SetHeight() dynamically as the list grows so
-- the section height tracks the entry count. Suitable for use as a
-- single section inside a V2 schema tab.
---------------------------------------------------------------------------
local function BuildKeybindOverridesSection(tabContent, startY)
    local y = startY or 0
    local PAD = Shared.PADDING

    Shared.CreateAccentDotLabel(tabContent, "Keybind Text Overrides", y); y = y - 22

    local overrideInfo = GUI:CreateLabel(
        tabContent,
        "Drag spells from your spellbook or items from your bags into the drop zone below, then type the exact text you want shown on the CDM icon.",
        11, C.textMuted
    )
    overrideInfo:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
    overrideInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    overrideInfo:SetJustifyH("LEFT")
    overrideInfo:SetWordWrap(true)
    overrideInfo:SetHeight(32)
    y = y - 40

    local QUICore = _G.QUI and _G.QUI.QUICore
    if not QUICore or not QUICore.db or not QUICore.db.profile or not QUICore.db.char then
        local noDataLabel = GUI:CreateLabel(tabContent, "Override storage is not available yet.", 12, C.textMuted)
        noDataLabel:SetPoint("TOPLEFT", PAD, y)
        tabContent:SetHeight(math.abs(y) + 60)
        return
    end

    -- Enable toggles (CDM + Custom Trackers) paired in a card.
    local toggleCard = Shared.CreateSettingsCardGroup(tabContent, y)
    local cdmToggle = GUI:CreateFormCheckbox(toggleCard.frame, nil, "keybindOverridesEnabledCDM", QUICore.db.profile, RefreshCDMKeybinds,
        { description = "Apply the custom keybind text overrides below to the CDM essential and utility viewers." })
    local trackersToggle = GUI:CreateFormCheckbox(toggleCard.frame, nil, "keybindOverridesEnabledTrackers", QUICore.db.profile, RefreshCustomTrackerKeybinds,
        { description = "Apply the custom keybind text overrides below to the custom item and spell tracker bars." })
    toggleCard.AddRow(
        Shared.BuildSettingRow(toggleCard.frame, "Enable for CDM", cdmToggle),
        Shared.BuildSettingRow(toggleCard.frame, "Enable for Custom Trackers", trackersToggle)
    )
    toggleCard.Finalize()
    y = y - toggleCard.frame:GetHeight() - 12

    local charName = UnitName("player") or "Unknown"
    local specID = 0
    local specName = "No Spec"

    local function UpdateSpecInfo()
        specID = 0
        specName = "No Spec"
        local specIndex = GetSpecialization()
        if specIndex then
            local currentSpecID, currentSpecName = GetSpecializationInfo(specIndex)
            specID = currentSpecID or 0
            specName = currentSpecName or "No Spec"
        end
    end

    UpdateSpecInfo()

    local function GetCurrentSpecOverrides()
        QUICore.db.char.keybindOverrides = QUICore.db.char.keybindOverrides or {}
        if not QUICore.db.char.keybindOverrides[specID] then
            QUICore.db.char.keybindOverrides[specID] = {}
        end
        return QUICore.db.char.keybindOverrides[specID]
    end

    local function SetSpellOverride(spellID, keybindText)
        spellID = tonumber(spellID)
        if not spellID or spellID <= 0 then return false end
        if QUI and QUI.Keybinds and QUI.Keybinds.SetOverride then
            QUI.Keybinds.SetOverride(spellID, keybindText)
            return true
        end
        local overrides = GetCurrentSpecOverrides()
        if keybindText == nil then overrides[spellID] = nil
        else overrides[spellID] = keybindText end
        RefreshAllKeybindDisplays()
        return true
    end

    local function SetItemOverride(itemID, keybindText)
        itemID = tonumber(itemID)
        if not itemID or itemID <= 0 then return false end
        if QUI and QUI.Keybinds and QUI.Keybinds.SetOverrideForItem then
            QUI.Keybinds.SetOverrideForItem(itemID, keybindText)
            return true
        end
        local overrides = GetCurrentSpecOverrides()
        local key = -itemID
        if keybindText == nil then overrides[key] = nil
        else overrides[key] = keybindText end
        RefreshAllKeybindDisplays()
        return true
    end

    -- Drop zone
    local dropZone = CreateFrame("Frame", nil, tabContent, "BackdropTemplate")
    dropZone:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
    dropZone:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    dropZone:SetHeight(56)
    dropZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropZone:SetBackdropColor(0.05, 0.05, 0.05, 0.4)
    dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

    local dropLabel = GUI:CreateLabel(dropZone, "Drop Spell or Item Here", 12, C.text)
    dropLabel:SetPoint("TOP", 0, -12)

    local dropHint = GUI:CreateLabel(dropZone, "Adds the spell or item to this spec's override list.", 10, C.textMuted)
    dropHint:SetPoint("TOP", dropLabel, "BOTTOM", 0, -4)

    y = y - 72

    -- Override list header (dynamic — shows char + spec)
    local trackedHeader = CreateFrame("Frame", nil, tabContent)
    trackedHeader:SetHeight(22)
    trackedHeader:SetPoint("TOPLEFT", dropZone, "BOTTOMLEFT", 0, -15)
    trackedHeader:SetPoint("TOPRIGHT", dropZone, "BOTTOMRIGHT", 0, -15)
    local trackedLabel = trackedHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trackedLabel:SetPoint("LEFT", 0, 0)
    trackedLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 0.9)
    trackedHeader.SetText = function(_, text) trackedLabel:SetText(text) end

    local entryListFrame = CreateFrame("Frame", nil, tabContent)
    entryListFrame:SetPoint("TOPLEFT", trackedHeader, "BOTTOMLEFT", 0, -8)
    entryListFrame:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    entryListFrame:SetHeight(1)

    local entryFrames = {}
    local emptyLabel
    local listBaseHeight = math.abs(y) + 96
    local RefreshOverrideList

    local function UpdateHeader()
        UpdateSpecInfo()
        trackedHeader:SetText(string.format("Overrides for %s, %s spec", charName, specName))
    end

    local function GetDisplayInfo(entry)
        if entry.type == "spell" then
            local spellInfo = C_Spell.GetSpellInfo(entry.id)
            return spellInfo and spellInfo.name or ("Spell " .. tostring(entry.id)), spellInfo and spellInfo.iconID
        end
        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(entry.id)
        if itemName then return itemName, itemIcon end
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(entry.id) end
        return "Item " .. tostring(entry.id), nil
    end

    local function SaveEntryOverride(entry, keybindText)
        if entry.type == "item" then return SetItemOverride(entry.id, keybindText) end
        return SetSpellOverride(entry.id, keybindText)
    end

    local function EnsureEntryRow(index)
        local row = entryFrames[index]
        if row then return row end

        row = CreateFrame("Frame", nil, entryListFrame)
        row:SetHeight(28)
        row:SetPoint("LEFT", entryListFrame, "LEFT", 0, 0)
        row:SetPoint("RIGHT", entryListFrame, "RIGHT", 0, 0)

        row.iconTex = row:CreateTexture(nil, "ARTWORK")
        row.iconTex:SetSize(24, 24)
        row.iconTex:SetPoint("LEFT", 0, 0)
        row.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.removeBtn = GUI:CreateButton(row, "X", 24, 22, function()
            local entry = row.entryData
            if not entry then return end
            if SaveEntryOverride(entry, nil) then RefreshOverrideList() end
        end)
        row.removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

        row.saveBtn = GUI:CreateButton(row, "Save", 50, 22, function()
            local entry = row.entryData
            if not entry then return end
            if SaveEntryOverride(entry, row.input:GetText() or "") then
                RefreshOverrideList()
                row.input:ClearFocus()
            end
        end)
        row.saveBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -6, 0)

        row.inputBg, row.input = GUI:CreateInlineEditBox(row, {
            width = 100,
            height = 22,
            textInset = 6,
            bgColor = { 0.05, 0.05, 0.05, 0.4 },
            borderColor = { 0.25, 0.25, 0.25, 0.6 },
            activeBorderColor = C.accent,
            commitOnFocusLost = false,
            onEscapePressed = function(self)
                local currentEntry = self.rowRef and self.rowRef.entryData
                self:SetText(currentEntry and currentEntry.keybindText or "")
                self:SetCursorPosition(0)
            end,
            onEditFocusGained = function(self) self:HighlightText() end,
            onEnterPressed = function(self)
                if self.rowRef and self.rowRef.saveBtn then
                    self.rowRef.saveBtn:Click()
                end
            end,
        })
        row.inputBg:SetPoint("RIGHT", row.saveBtn, "LEFT", -6, 0)
        row.input.rowRef = row

        row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameLabel:SetPoint("LEFT", row.iconTex, "RIGHT", 6, 0)
        row.nameLabel:SetPoint("RIGHT", row.inputBg, "LEFT", -6, 0)
        row.nameLabel:SetJustifyH("LEFT")
        row.nameLabel:SetWordWrap(false)
        row.nameLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        entryFrames[index] = row
        return row
    end

    RefreshOverrideList = function()
        UpdateHeader()

        for i = 1, #entryFrames do
            if entryFrames[i] then entryFrames[i]:Hide() end
        end
        if emptyLabel then emptyLabel:Hide() end

        local overrides = GetCurrentSpecOverrides()
        local entries = {}
        for key, keybindText in pairs(overrides) do
            local entryType = (key < 0) and "item" or "spell"
            local id = (key < 0) and -key or key
            table.insert(entries, {
                key = key, id = id, type = entryType,
                keybindText = keybindText or "",
            })
        end
        table.sort(entries, function(a, b)
            if a.type ~= b.type then return a.type == "item" end
            return a.id < b.id
        end)

        local totalHeight = 0
        if #entries == 0 then
            if not emptyLabel then
                emptyLabel = GUI:CreateLabel(entryListFrame, "No overrides saved for this spec yet.", 11, C.textMuted)
                emptyLabel:SetJustifyH("LEFT")
                emptyLabel:SetWordWrap(true)
                emptyLabel:SetHeight(32)
            end
            emptyLabel:SetPoint("TOPLEFT", entryListFrame, "TOPLEFT", 0, 0)
            emptyLabel:SetPoint("RIGHT", entryListFrame, "RIGHT", 0, 0)
            emptyLabel:Show()
            totalHeight = 32
        else
            local previousRow
            for index, entry in ipairs(entries) do
                local row = EnsureEntryRow(index)
                row.entryData = entry
                row:ClearAllPoints()
                if previousRow then
                    row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -4)
                else
                    row:SetPoint("TOPLEFT", entryListFrame, "TOPLEFT", 0, 0)
                end
                row:SetPoint("RIGHT", entryListFrame, "RIGHT", 0, 0)

                local displayName, iconID = GetDisplayInfo(entry)
                local typePrefix = (entry.type == "item") and "Item" or "Spell"

                row.iconTex:SetTexture(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.nameLabel:SetText(string.format("%s: %s (%d)", typePrefix, displayName, entry.id))
                row.input:SetText(entry.keybindText or "")
                row.input:SetCursorPosition(0)
                row:Show()

                previousRow = row
            end
            totalHeight = (#entries * 28) + ((#entries - 1) * 4)
        end

        entryListFrame:SetHeight(totalHeight)
        tabContent:SetHeight(listBaseHeight + totalHeight)
    end

    local function HandleDrop()
        local cursorType, id1, id2, id3, id4 = GetCursorInfo()
        if cursorType == "spell" then
            local slotIndex = id1
            local bookType = id2 or "spell"
            local spellID = id3 or id4
            if not spellID and slotIndex then
                local spellBank = (bookType == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                local spellBookInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                if spellBookInfo then spellID = spellBookInfo.spellID end
            end
            if spellID and C_Spell.GetOverrideSpell then
                local overrideID = C_Spell.GetOverrideSpell(spellID)
                if overrideID and overrideID ~= spellID then spellID = overrideID end
            end
            if spellID and SetSpellOverride(spellID, "") then
                ClearCursor()
                RefreshOverrideList()
            end
            return
        end
        if cursorType == "item" then
            local itemID = id1
            if itemID and SetItemOverride(itemID, "") then
                ClearCursor()
                RefreshOverrideList()
            end
        end
    end

    dropZone:SetScript("OnReceiveDrag", HandleDrop)
    dropZone:SetScript("OnMouseUp", function()
        local cursorType = GetCursorInfo()
        if cursorType == "spell" or cursorType == "item" then HandleDrop() end
    end)
    dropZone:SetScript("OnEnter", function(self)
        local cursorType = GetCursorInfo()
        if cursorType == "spell" or cursorType == "item" then
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            dropLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end
    end)
    dropZone:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
        dropLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end)

    itemInfoListenerCallback = function(itemID)
        local overrides = GetCurrentSpecOverrides()
        if overrides and overrides[-itemID] ~= nil then
            C_Timer.After(0.1, RefreshOverrideList)
        end
    end

    specChangeCallback = function() RefreshOverrideList() end

    RefreshOverrideList()
    return y - (entryListFrame and entryListFrame:GetHeight() or 0) - 16
end

ns.QUI_KeybindsOptions = {
    BuildKeybindOverridesSection = BuildKeybindOverridesSection,
}
