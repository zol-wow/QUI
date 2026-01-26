local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList
local GetFontList = Shared.GetFontList

-- Local reference to QUICore (needed by helper functions)
local QUICore = ns.Addon

---------------------------------------------------------------------------
-- Helper: Refresh tracker bar position
---------------------------------------------------------------------------
local function RefreshTrackerPosition(barID)
    if QUICore and QUICore.CustomTrackers then
        QUICore.CustomTrackers:RefreshBarPosition(barID)
    end
end

---------------------------------------------------------------------------
-- PAGE: Custom Trackers (Trinkets, Pots, Spells)
---------------------------------------------------------------------------
local function CreateCustomTrackersPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local db = GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 9, tabName = "Custom Items/Spells/Buffs"})

    -- Ensure customTrackers.bars exists
    if not db.customTrackers then
        db.customTrackers = {bars = {}}
    end
    if not db.customTrackers.bars then
        db.customTrackers.bars = {}
    end

    local bars = db.customTrackers.bars
    local PAD = 10
    local FORM_ROW = 32

    ---------------------------------------------------------------------------
    -- Helper: Calculate offset relative to QUI_Player frame's top-left corner
    -- Returns screen-center offsets that position a bar relative to player frame
    ---------------------------------------------------------------------------
    local function CalculatePlayerRelativeOffset(playerOffsetX, playerOffsetY)
        local playerFrame = _G.QUI_Player
        if not playerFrame then
            -- Fallback: use default screen-center offsets
            return -406, -152
        end

        local screenCenterX, screenCenterY = UIParent:GetCenter()
        local playerLeft = playerFrame:GetLeft()
        local playerTop = playerFrame:GetTop()

        if not (screenCenterX and screenCenterY and playerLeft and playerTop) then
            return -406, -152
        end

        -- Bar position = player top-left + desired offset
        local barCenterX = playerLeft + playerOffsetX
        local barCenterY = playerTop + playerOffsetY

        -- Convert to screen-center offsets
        local offsetX = math.floor(barCenterX - screenCenterX + 0.5)
        local offsetY = math.floor(barCenterY - screenCenterY + 0.5)

        return offsetX, offsetY
    end

    ---------------------------------------------------------------------------
    -- Helper: Create drop zone for adding items/spells via drag-and-drop
    ---------------------------------------------------------------------------
    local function CreateAddEntrySection(parentFrame, barID, refreshCallback)
        local container = CreateFrame("Frame", nil, parentFrame)
        container:SetHeight(83)  -- 50% taller than original 55

        -- DROP ZONE: Click here while holding an item/spell on cursor
        local dropZone = CreateFrame("Button", nil, container, "BackdropTemplate")
        dropZone:SetHeight(68)  -- 50% taller than original 45
        dropZone:SetPoint("TOPLEFT", 0, 0)
        dropZone:SetPoint("RIGHT", container, "RIGHT", 0, 0)  -- Full width
        dropZone:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        dropZone:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.8)
        dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

        local dropLabel = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dropLabel:SetPoint("CENTER", 0, 0)
        dropLabel:SetText("Drop Items or Spells here")
        dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

        -- Handle drop on mouse release (OnReceiveDrag fires when releasing with item on cursor)
        dropZone:SetScript("OnReceiveDrag", function(self)
            local cursorType, id1, id2, id3, id4 = GetCursorInfo()
            if cursorType == "item" then
                local itemID = id1
                if itemID then
                    local trackerModule = QUI and QUI.QUICore and QUI.QUICore.CustomTrackers
                    if trackerModule then
                        trackerModule:AddEntry(barID, "item", itemID)
                        ClearCursor()
                        if refreshCallback then refreshCallback() end
                    end
                end
            elseif cursorType == "spell" then
                -- id1 is slot index, id2 is bookType ("spell" or "pet")
                -- Need to look up actual spellID from spellbook
                local slotIndex = id1
                local bookType = id2 or "spell"
                local spellID = id4  -- Try direct spellID first (older API)

                -- If no direct spellID, look it up from spellbook
                if not spellID and slotIndex then
                    local spellBank = (bookType == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                    local spellBookInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                    if spellBookInfo then
                        spellID = spellBookInfo.spellID
                    end
                end

                -- Resolve override spell (talents that replace base spells)
                if spellID then
                    local overrideID = C_Spell.GetOverrideSpell(spellID)
                    if overrideID and overrideID ~= spellID then
                        spellID = overrideID
                    end
                end

                if spellID then
                    local trackerModule = QUI and QUI.QUICore and QUI.QUICore.CustomTrackers
                    if trackerModule then
                        trackerModule:AddEntry(barID, "spell", spellID)
                        ClearCursor()
                        if refreshCallback then refreshCallback() end
                    end
                end
            end
        end)

        -- Also handle OnMouseUp as fallback (some drag modes use this)
        dropZone:SetScript("OnMouseUp", function(self)
            local cursorType = GetCursorInfo()
            if cursorType == "item" or cursorType == "spell" then
                -- Trigger the same logic as OnReceiveDrag
                local handler = dropZone:GetScript("OnReceiveDrag")
                if handler then handler(self) end
            end
        end)

        -- Highlight on hover when cursor has item/spell
        dropZone:SetScript("OnEnter", function(self)
            local cursorType = GetCursorInfo()
            if cursorType == "item" or cursorType == "spell" then
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                dropLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
            end
        end)
        dropZone:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
            dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end)

        return container
    end

    -- Helper: Get entry display name (prefers customName if set)
    local function GetEntryDisplayName(entry)
        -- Use custom name if set
        if entry.customName and entry.customName ~= "" then
            return entry.customName
        end
        -- Otherwise, auto-detect from spell/item info
        if entry.type == "spell" then
            local info = C_Spell.GetSpellInfo(entry.id)
            return info and info.name or ("Spell " .. entry.id)
        else
            local name = C_Item.GetItemInfo(entry.id)
            return name or ("Item " .. entry.id)
        end
    end

    ---------------------------------------------------------------------------
    -- Build tab content for a single tracker bar
    ---------------------------------------------------------------------------
    local function BuildTrackerBarTab(tabContent, barConfig, barIndex, subTabsRef)
        GUI:SetSearchContext({tabIndex = 9, tabName = "Custom Items/Spells/Buffs", subTabIndex = barIndex + 1, subTabName = barConfig.name or ("Bar " .. barIndex)})
        local y = -10
        local entryListFrame  -- Forward declaration for refresh callback

        -- Refresh callback for this bar
        local function RefreshThisBar()
            if QUICore and QUICore.CustomTrackers then
                QUICore.CustomTrackers:UpdateBar(barConfig.id)
            end
        end

        -- Refresh position callback
        local function RefreshPosition()
            RefreshTrackerPosition(barConfig.id)
        end

        -----------------------------------------------------------------------
        -- GENERAL SECTION
        -----------------------------------------------------------------------
        local generalHeader = GUI:CreateSectionHeader(tabContent, "General")
        generalHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - generalHeader.gap

        local generalHint = GUI:CreateLabel(tabContent, "Reminder: Enable this bar, else nothing will show. If you are deleting the ONLY remaining bar, it would just restore the original 'Trinket & Pot' bar that is disabled by default.", 11, C.textMuted)
        generalHint:SetPoint("TOPLEFT", PAD, y)
        generalHint:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        generalHint:SetJustifyH("LEFT")
        generalHint:SetWordWrap(true)
        generalHint:SetHeight(30)
        y = y - 40

        -- Enable Bar
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Bar", "enabled", barConfig, RefreshThisBar)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Name (editable, updates tab text instantly)
        local nameContainer = CreateFrame("Frame", nil, tabContent)
        nameContainer:SetHeight(FORM_ROW)
        nameContainer:SetPoint("TOPLEFT", PAD, y)
        nameContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local nameLabel = nameContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("LEFT", 0, 0)
        nameLabel:SetText("Bar Name")
        nameLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Custom styled editbox (matches QUI dropdown styling)
        local nameInputBg = CreateFrame("Frame", nil, nameContainer, "BackdropTemplate")
        nameInputBg:SetPoint("LEFT", nameContainer, "LEFT", 180, 0)
        nameInputBg:SetSize(200, 24)
        nameInputBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        nameInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        nameInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        local nameInput = CreateFrame("EditBox", nil, nameInputBg)
        nameInput:SetPoint("LEFT", 8, 0)
        nameInput:SetPoint("RIGHT", -8, 0)
        nameInput:SetHeight(22)
        nameInput:SetAutoFocus(false)
        nameInput:SetFont(GUI.FONT_PATH, 11, "")
        nameInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        nameInput:SetText(barConfig.name or "Tracker")
        nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        nameInput:SetScript("OnEditFocusGained", function()
            nameInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        nameInput:SetScript("OnEditFocusLost", function()
            nameInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end)
        nameInput:SetScript("OnTextChanged", function(self)
            local newName = self:GetText()
            if newName == "" then newName = "Tracker" end
            barConfig.name = newName

            -- Update sub-tab text instantly
            if subTabsRef and subTabsRef.tabButtons and subTabsRef.tabButtons[barIndex] then
                local displayName = newName
                if #displayName > 20 then
                    displayName = displayName:sub(1, 17) .. "..."
                end
                subTabsRef.tabButtons[barIndex].text:SetText(displayName)
            end
        end)
        y = y - FORM_ROW

        -- Delete Bar button
        y = y - 10
        local deleteBtn = GUI:CreateButton(tabContent, "Delete Bar", 120, 26, function()
            GUI:ShowConfirmation({
                title = "Delete Tracker Bar?",
                message = "Delete this tracker bar?",
                warningText = "This cannot be undone.",
                acceptText = "Delete",
                cancelText = "Cancel",
                isDestructive = true,
                onAccept = function()
                    -- Remove from DB
                    for i, bc in ipairs(db.customTrackers.bars) do
                        if bc.id == barConfig.id then
                            table.remove(db.customTrackers.bars, i)
                            break
                        end
                    end
                    -- Delete the active bar frame
                    if QUICore and QUICore.CustomTrackers then
                        QUICore.CustomTrackers:DeleteBar(barConfig.id)
                    end
                    -- Prompt reload to rebuild tabs
                    GUI:ShowConfirmation({
                        title = "Reload UI?",
                        message = "Tracker deleted. Reload UI to see changes?",
                        acceptText = "Reload",
                        cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
                    })
                end,
            })
        end)
        deleteBtn:SetPoint("TOPLEFT", PAD, y)
        deleteBtn:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - 36

        -----------------------------------------------------------------------
        -- ADD ITEMS/SPELLS SECTION (moved up for better UX flow)
        -----------------------------------------------------------------------
        local addHeader = GUI:CreateSectionHeader(tabContent, "Add Trinkets/Consumables/Spells")
        addHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - addHeader.gap

        -- Forward declarations for spec-specific helpers (needed by RefreshEntryList)
        local specInfoLabel = nil
        local copyFromDropdown = nil

        -- Get tracker module reference
        local trackerModule = QUICore and QUICore.CustomTrackers

        -- Helper to get current spec key (always uses actual current spec)
        local function getCurrentSpecKey()
            -- Use tracker module's helper if available
            if trackerModule and trackerModule.GetCurrentSpecKey then
                return trackerModule.GetCurrentSpecKey()
            end
            -- Fallback
            local _, className = UnitClass("player")
            local specIndex = GetSpecialization()
            if specIndex then
                local specID = GetSpecializationInfo(specIndex)
                if specID and className then
                    return className .. "-" .. specID
                end
            end
            return nil
        end

        -- Helper to get readable spec name
        local function getSpecDisplayName(specKey)
            if trackerModule and trackerModule.GetClassSpecName then
                return trackerModule.GetClassSpecName(specKey)
            end
            return specKey or "Unknown"
        end

        -- Update info label
        local function updateSpecInfoLabel()
            if specInfoLabel then
                if barConfig.specSpecificSpells then
                    local specKey = getCurrentSpecKey()
                    specInfoLabel:SetText("Currently editing: " .. getSpecDisplayName(specKey))
                    specInfoLabel:Show()
                else
                    specInfoLabel:Hide()
                end
            end
        end

        -- Refresh entry list when spec changes
        local function refreshForSpec()
            RefreshThisBar()
            updateSpecInfoLabel()
            -- Note: Entry list refresh is handled by entryListFrame recreation
        end

        local hintText = GUI:CreateLabel(tabContent, "Drag items from your bags or character pane, spells from your spellbook into the box below.", 11, C.textMuted)
        hintText:SetPoint("TOPLEFT", addHeader, "BOTTOMLEFT", 0, -8)
        hintText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        hintText:SetJustifyH("LEFT")
        hintText:SetWordWrap(true)
        hintText:SetHeight(30)

        -- Function to refresh entry list (defined later, used in add section)
        local function RefreshEntryList()
            if not entryListFrame then return end
            -- Clear existing children
            for _, child in ipairs({entryListFrame:GetChildren()}) do
                child:Hide()
                child:SetParent(nil)
            end

            -- Use GetBarEntries for spec-aware loading (always uses current spec)
            local entries
            local trackerMod = QUICore and QUICore.CustomTrackers
            if trackerMod and trackerMod.GetBarEntries then
                -- Pass nil to use current spec
                entries = trackerMod.GetBarEntries(barConfig, nil)
            else
                entries = barConfig.entries or {}
            end
            local listY = 0
            for j, entry in ipairs(entries) do
                local entryFrame = CreateFrame("Frame", nil, entryListFrame)
                entryFrame:SetSize(320, 28)
                entryFrame:SetPoint("TOPLEFT", 0, listY)

                -- Icon
                local iconTex = entryFrame:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(24, 24)
                iconTex:SetPoint("LEFT", 0, 0)
                if entry.type == "spell" then
                    local info = C_Spell.GetSpellInfo(entry.id)
                    iconTex:SetTexture(info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
                else
                    local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(entry.id)
                    iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                end
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                entryFrame.iconTex = iconTex  -- Store reference for name resolution

                -- Name (editable input box with subtle styling)
                local nameInputBg = CreateFrame("Frame", nil, entryFrame, "BackdropTemplate")
                nameInputBg:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                nameInputBg:SetSize(176, 22)
                nameInputBg:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                nameInputBg:SetBackdropColor(0.05, 0.05, 0.05, 0.4)
                nameInputBg:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

                local nameInput = CreateFrame("EditBox", nil, nameInputBg)
                nameInput:SetPoint("LEFT", 6, 0)
                nameInput:SetPoint("RIGHT", -6, 0)
                nameInput:SetHeight(20)
                nameInput:SetAutoFocus(false)
                nameInput:SetFont(GUI.FONT_PATH, 11, "")
                nameInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                nameInput:SetText(GetEntryDisplayName(entry))
                nameInput:SetCursorPosition(0)

                -- Store reference to entry for saving
                nameInput.entry = entry
                nameInput.barConfig = barConfig

                nameInput:SetScript("OnEscapePressed", function(self)
                    self:SetText(GetEntryDisplayName(self.entry))
                    self:ClearFocus()
                end)

                -- Helper to resolve name to spell/item and update entry
                local function ResolveAndUpdateEntry(self)
                    local newName = self:GetText()
                    if newName == "" then
                        -- Clear custom name to restore auto-detected
                        self.entry.customName = nil
                        self:SetText(GetEntryDisplayName(self.entry))
                        return
                    end

                    local currentName = GetEntryDisplayName(self.entry)
                    if newName == currentName then
                        -- No change, don't process
                        return
                    end

                    -- Try to resolve the name to a spell/item ID
                    local resolved = false

                    if self.entry.type == "spell" then
                        -- Try to look up spell by name using C_Spell API
                        local newSpellID = C_Spell.GetSpellIDForSpellIdentifier(newName)
                        if newSpellID then
                            -- Found the spell - update the entry ID
                            self.entry.id = newSpellID
                            self.entry.customName = nil  -- Clear custom name since we resolved
                            resolved = true
                            -- Refresh the bar to use new spell
                            if QUICore and QUICore.CustomTrackers then
                                QUICore.CustomTrackers:UpdateBar(self.barConfig.id)
                            end
                            -- Update display to show resolved name
                            self:SetText(GetEntryDisplayName(self.entry))
                            -- Update icon
                            local iconTexRef = self:GetParent():GetParent().iconTex
                            if iconTexRef then
                                local info = C_Spell.GetSpellInfo(newSpellID)
                                if info and info.iconID then
                                    iconTexRef:SetTexture(info.iconID)
                                end
                            end
                        end
                    elseif self.entry.type == "item" then
                        -- Try to look up item by name
                        local newItemID = C_Item.GetItemIDForItemInfo(newName)
                        if newItemID then
                            -- Found the item - update the entry ID
                            self.entry.id = newItemID
                            self.entry.customName = nil
                            resolved = true
                            -- Refresh the bar
                            if QUICore and QUICore.CustomTrackers then
                                QUICore.CustomTrackers:UpdateBar(self.barConfig.id)
                            end
                            -- Update display
                            self:SetText(GetEntryDisplayName(self.entry))
                            -- Update icon
                            local iconTexRef = self:GetParent():GetParent().iconTex
                            if iconTexRef then
                                local _, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(newItemID)
                                if itemIcon then
                                    iconTexRef:SetTexture(itemIcon)
                                end
                            end
                        end
                    end

                    if not resolved then
                        -- Could not resolve - revert to original name
                        self:SetText(GetEntryDisplayName(self.entry))
                    end
                end

                nameInput:SetScript("OnEnterPressed", function(self)
                    ResolveAndUpdateEntry(self)
                    self:ClearFocus()
                end)
                nameInput:SetScript("OnEditFocusGained", function(self)
                    nameInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    self:HighlightText()
                end)
                nameInput:SetScript("OnEditFocusLost", function(self)
                    nameInputBg:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
                    ResolveAndUpdateEntry(self)
                end)

                -- Store reference for button positioning
                local entryName = nameInputBg

                -- Helper: Create styled chevron button (matches dropdown style)
                local function CreateChevronButton(parent, direction, onClick)
                    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
                    btn:SetSize(22, 22)
                    btn:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

                    -- Chevron made of two rotated lines
                    local chevronLeft = btn:CreateTexture(nil, "OVERLAY")
                    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                    chevronLeft:SetSize(6, 2)
                    local chevronRight = btn:CreateTexture(nil, "OVERLAY")
                    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                    chevronRight:SetSize(6, 2)

                    if direction == "up" then
                        chevronLeft:SetPoint("CENTER", btn, "CENTER", -2, 1)
                        chevronLeft:SetRotation(math.rad(45))
                        chevronRight:SetPoint("CENTER", btn, "CENTER", 2, 1)
                        chevronRight:SetRotation(math.rad(-45))
                    else
                        chevronLeft:SetPoint("CENTER", btn, "CENTER", -2, -1)
                        chevronLeft:SetRotation(math.rad(-45))
                        chevronRight:SetPoint("CENTER", btn, "CENTER", 2, -1)
                        chevronRight:SetRotation(math.rad(45))
                    end

                    btn.chevronLeft = chevronLeft
                    btn.chevronRight = chevronRight

                    btn:SetScript("OnEnter", function(self)
                        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                        self.chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                        self.chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                    end)
                    btn:SetScript("OnLeave", function(self)
                        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        self.chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                        self.chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                    end)
                    btn:SetScript("OnClick", onClick)

                    return btn
                end

                -- Move Up button (anchored after fixed-width name)
                local upBtn = CreateChevronButton(entryFrame, "up", function()
                    if QUICore and QUICore.CustomTrackers then
                        QUICore.CustomTrackers:MoveEntry(barConfig.id, j, -1, nil)
                    end
                    RefreshEntryList()
                end)
                upBtn:SetPoint("LEFT", entryName, "RIGHT", 8, 0)
                if j == 1 then
                    upBtn:SetAlpha(0.3)
                    upBtn:EnableMouse(false)
                end

                -- Move Down button
                local downBtn = CreateChevronButton(entryFrame, "down", function()
                    if QUICore and QUICore.CustomTrackers then
                        QUICore.CustomTrackers:MoveEntry(barConfig.id, j, 1, nil)
                    end
                    RefreshEntryList()
                end)
                downBtn:SetPoint("LEFT", upBtn, "RIGHT", 2, 0)
                if j == #entries then
                    downBtn:SetAlpha(0.3)
                    downBtn:EnableMouse(false)
                end

                -- Remove button (styled to match chevrons)
                local removeBtn = CreateFrame("Button", nil, entryFrame, "BackdropTemplate")
                removeBtn:SetSize(22, 22)
                removeBtn:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                removeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                removeBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                local xText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                xText:SetPoint("CENTER", 0, 0)
                xText:SetText("X")
                xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
                removeBtn:SetScript("OnEnter", function(self)
                    self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
                end)
                removeBtn:SetScript("OnLeave", function(self)
                    self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                    xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
                end)
                removeBtn:SetScript("OnClick", function()
                    if QUICore and QUICore.CustomTrackers then
                        QUICore.CustomTrackers:RemoveEntry(barConfig.id, entry.type, entry.id, nil)
                    end
                    RefreshEntryList()
                end)
                removeBtn:SetPoint("LEFT", downBtn, "RIGHT", 4, 0)

                listY = listY - 30
            end

            -- Update entry list frame height
            local listHeight = math.max(20, math.abs(listY))
            entryListFrame:SetHeight(listHeight)
        end

        -- Create add entry section (drop zone) - anchored to hintText
        local addSection = CreateAddEntrySection(tabContent, barConfig.id, RefreshEntryList)
        addSection:SetPoint("TOPLEFT", hintText, "BOTTOMLEFT", 0, -10)
        addSection:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)  -- Full width

        -----------------------------------------------------------------------
        -- TRACKED ITEMS SECTION
        -----------------------------------------------------------------------
        local trackedHeader = GUI:CreateSectionHeader(tabContent, "Tracked Items And Spells")
        trackedHeader:SetPoint("TOPLEFT", addSection, "BOTTOMLEFT", 0, -15)

        -- Entry list container
        entryListFrame = CreateFrame("Frame", nil, tabContent)
        entryListFrame:SetPoint("TOPLEFT", trackedHeader, "BOTTOMLEFT", 0, -8)
        entryListFrame:SetSize(400, 20)
        RefreshEntryList()

        -----------------------------------------------------------------------
        -- LOWER SECTIONS CONTAINER (anchored to entry list for dynamic positioning)
        -----------------------------------------------------------------------
        local lowerContainer = CreateFrame("Frame", nil, tabContent)
        lowerContainer:SetPoint("TOPLEFT", entryListFrame, "BOTTOMLEFT", 0, -10)
        lowerContainer:SetPoint("RIGHT", tabContent, "RIGHT", 0, 0)
        lowerContainer:SetHeight(600)  -- Will contain all sections below
        lowerContainer:EnableMouse(false)  -- Let clicks pass through to widgets
        y = 0  -- Reset y for positioning within lowerContainer

        -----------------------------------------------------------------------
        -- AUTOHIDE NON-USABLES SECTION (moved up per user request - highly useful feature)
        -----------------------------------------------------------------------
        local autohideHeader = GUI:CreateSectionHeader(lowerContainer, "Autohide Non-Usables")
        autohideHeader:SetPoint("TOPLEFT", 0, y)
        y = y - autohideHeader.gap + 12  -- Tighter spacing for description text

        local autohideDesc = GUI:CreateLabel(lowerContainer, "By default, when a consumable has 0 stacks in your bags, a trinket is unequipped from your character, or you have unlearned a spell, those tracked elements are merely desaturated. Toggling this on will hide them entirely.", 11, C.textMuted)
        autohideDesc:SetPoint("TOPLEFT", 0, y)
        autohideDesc:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        autohideDesc:SetJustifyH("LEFT")
        autohideDesc:SetWordWrap(true)
        autohideDesc:SetHeight(45)
        y = y - 55

        local hideNonUsableCheck = GUI:CreateFormCheckbox(lowerContainer, "Hide Non-Usable", "hideNonUsable", barConfig, RefreshThisBar)
        hideNonUsableCheck:SetPoint("TOPLEFT", 0, y)
        hideNonUsableCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- POSITIONING SECTION (moved to lowerContainer for better flow)
        -----------------------------------------------------------------------
        local posHeader = GUI:CreateSectionHeader(lowerContainer, "Positioning")
        posHeader:SetPoint("TOPLEFT", 0, y)
        y = y - posHeader.gap

        local posHint = GUI:CreateLabel(lowerContainer, "Hint: You can place your custom bar ANYWHERE on screen. Simply toggle off Prevent Mouse Dragging, then left-click drag the bar. Locking to Player Frame is merely for convenience.", 11, C.textMuted)
        posHint:SetPoint("TOPLEFT", 0, y)
        posHint:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        posHint:SetJustifyH("LEFT")
        posHint:SetWordWrap(true)
        posHint:SetHeight(45)
        y = y - 55

        -- Ensure offset fields exist (migration)
        if not barConfig.offsetX then barConfig.offsetX = 0 end
        if not barConfig.offsetY then barConfig.offsetY = -300 end

        -- Store slider references for external updates (when bar is dragged)
        local xOffsetSlider, yOffsetSlider

        -- Register callback to update sliders when bar is dragged
        if trackerModule then
            trackerModule.onPositionChanged = function(draggedBarID, newX, newY)
                if draggedBarID == barConfig.id and xOffsetSlider and yOffsetSlider then
                    if xOffsetSlider.SetValue then xOffsetSlider.SetValue(newX, true) end
                    if yOffsetSlider.SetValue then yOffsetSlider.SetValue(newY, true) end
                end
            end
        end

        -- Lock to Player Frame section
        local btnGap = 4
        local rowGap = 4

        local lockContainer = CreateFrame("Frame", nil, lowerContainer)
        lockContainer:SetHeight(FORM_ROW + 22 + rowGap)
        lockContainer:SetPoint("TOPLEFT", 0, y)
        lockContainer:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)

        local lockLabel = lockContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockLabel:SetPoint("LEFT", 0, 0)
        lockLabel:SetText("Lock to Player Frame")
        lockLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Store button references for state updates
        local lockButtons = {}

        -- Function to update slider enabled state based on lock
        local function UpdateLockState()
            -- No-op: sliders always enabled for fine-tuning locked positions
        end

        -- Function to update button border colors and text based on lock state
        local function UpdateLockButtonStates()
            local currentPos = barConfig.lockedToPlayer and barConfig.lockPosition or nil
            for pos, btn in pairs(lockButtons) do
                if pos == currentPos then
                    btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    btn.textObj:SetText("Unlock " .. btn.label)
                else
                    btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
                    btn.textObj:SetText(btn.label)
                end
            end
        end

        -- Forward declaration for mutual exclusion (defined in target lock section)
        local UpdateTargetLockButtonStates

        -- Toggle lock: click same button to unlock
        local function LockToPlayer(corner)
            if barConfig.lockedToPlayer and barConfig.lockPosition == corner then
                local bar = QUICore and QUICore.CustomTrackers and QUICore.CustomTrackers.activeBars and QUICore.CustomTrackers.activeBars[barConfig.id]
                if bar then
                    local scX, scY = UIParent:GetCenter()
                    local bX, bY = bar:GetCenter()
                    if bX and bY and scX and scY then
                        barConfig.offsetX = math.floor(bX - scX + 0.5)
                        barConfig.offsetY = math.floor(bY - scY + 0.5)
                    end
                end
                barConfig.lockedToPlayer = false
                barConfig.lockPosition = nil
                if xOffsetSlider and xOffsetSlider.SetValue then xOffsetSlider.SetValue(barConfig.offsetX, true) end
                if yOffsetSlider and yOffsetSlider.SetValue then yOffsetSlider.SetValue(barConfig.offsetY, true) end
            else
                local playerFrame = _G["QUI_Player"]
                if not playerFrame then
                    print("|cffff6666[QUI]|r Player frame not found")
                    return
                end
                if barConfig.lockedToTarget then
                    barConfig.lockedToTarget = false
                    barConfig.targetLockPosition = nil
                    UpdateTargetLockButtonStates()
                end
                barConfig.lockedToPlayer = true
                barConfig.lockPosition = corner
                barConfig.offsetX = 0
                barConfig.offsetY = 0
                if xOffsetSlider and xOffsetSlider.SetValue then xOffsetSlider.SetValue(0, true) end
                if yOffsetSlider and yOffsetSlider.SetValue then yOffsetSlider.SetValue(0, true) end
            end
            RefreshPosition()
            UpdateLockState()
            UpdateLockButtonStates()
        end

        -- Helper to create lock button
        local function CreateLockButton(parent, label, corner)
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetSize(75, 22)
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("CENTER")
            text:SetText(label)
            text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            btn.label = label
            btn.textObj = text
            btn:SetScript("OnClick", function() LockToPlayer(corner) end)
            btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
            btn:SetScript("OnLeave", function(self)
                if not (barConfig.lockedToPlayer and barConfig.lockPosition == corner) then
                    self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
                end
            end)
            lockButtons[corner] = btn
            return btn
        end

        local lockTLBtn = CreateLockButton(lockContainer, "Top Left", "topleft")
        local lockTCBtn = CreateLockButton(lockContainer, "Top Center", "topcenter")
        local lockTRBtn = CreateLockButton(lockContainer, "Top Right", "topright")
        local lockBLBtn = CreateLockButton(lockContainer, "Btm Left", "bottomleft")
        local lockBCBtn = CreateLockButton(lockContainer, "Btm Center", "bottomcenter")
        local lockBRBtn = CreateLockButton(lockContainer, "Btm Right", "bottomright")

        local lockRow1Y = (22 + rowGap) / 2
        lockTLBtn:SetPoint("LEFT", lockContainer, "LEFT", 180, lockRow1Y)
        lockTCBtn:SetPoint("LEFT", lockTLBtn, "RIGHT", btnGap, 0)
        lockTRBtn:SetPoint("LEFT", lockTCBtn, "RIGHT", btnGap, 0)
        local lockRow2Y = -lockRow1Y
        lockBLBtn:SetPoint("LEFT", lockContainer, "LEFT", 180, lockRow2Y)
        lockBCBtn:SetPoint("LEFT", lockBLBtn, "RIGHT", btnGap, 0)
        lockBRBtn:SetPoint("LEFT", lockBCBtn, "RIGHT", btnGap, 0)

        local function UpdateLockButtonWidths()
            local containerWidth = lockContainer:GetWidth()
            if containerWidth and containerWidth > 0 then
                local availableWidth = containerWidth - 180
                local totalGaps = 2 * btnGap
                local lockBtnWidth = (availableWidth - totalGaps) / 3
                if lockBtnWidth > 20 then
                    lockTLBtn:SetWidth(lockBtnWidth)
                    lockTCBtn:SetWidth(lockBtnWidth)
                    lockTRBtn:SetWidth(lockBtnWidth)
                    lockBLBtn:SetWidth(lockBtnWidth)
                    lockBCBtn:SetWidth(lockBtnWidth)
                    lockBRBtn:SetWidth(lockBtnWidth)
                end
            end
        end
        lockContainer:HookScript("OnSizeChanged", function() UpdateLockButtonWidths() end)
        C_Timer.After(0, function() UpdateLockButtonWidths() UpdateLockButtonStates() end)

        y = y - (FORM_ROW + 22 + rowGap + 4)

        -- Lock to Target Frame section
        local targetLockContainer = CreateFrame("Frame", nil, lowerContainer)
        targetLockContainer:SetHeight(FORM_ROW + 22 + rowGap)
        targetLockContainer:SetPoint("TOPLEFT", 0, y)
        targetLockContainer:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)

        local targetLockLabel = targetLockContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        targetLockLabel:SetPoint("LEFT", 0, 0)
        targetLockLabel:SetText("Lock to Target Frame")
        targetLockLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local targetLockButtons = {}

        UpdateTargetLockButtonStates = function()
            local currentPos = barConfig.lockedToTarget and barConfig.targetLockPosition or nil
            for pos, btn in pairs(targetLockButtons) do
                if pos == currentPos then
                    btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    btn.textObj:SetText("Unlock " .. btn.label)
                else
                    btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
                    btn.textObj:SetText(btn.label)
                end
            end
        end

        local function LockToTarget(corner)
            if barConfig.lockedToTarget and barConfig.targetLockPosition == corner then
                local bar = QUICore and QUICore.CustomTrackers and QUICore.CustomTrackers.activeBars and QUICore.CustomTrackers.activeBars[barConfig.id]
                if bar then
                    local scX, scY = UIParent:GetCenter()
                    local bX, bY = bar:GetCenter()
                    if bX and bY and scX and scY then
                        barConfig.offsetX = math.floor(bX - scX + 0.5)
                        barConfig.offsetY = math.floor(bY - scY + 0.5)
                    end
                end
                barConfig.lockedToTarget = false
                barConfig.targetLockPosition = nil
                if xOffsetSlider and xOffsetSlider.SetValue then xOffsetSlider.SetValue(barConfig.offsetX, true) end
                if yOffsetSlider and yOffsetSlider.SetValue then yOffsetSlider.SetValue(barConfig.offsetY, true) end
            else
                local targetFrame = _G["QUI_Target"]
                if not targetFrame then
                    print("|cffff6666[QUI]|r Target frame not found")
                    return
                end
                if barConfig.lockedToPlayer then
                    barConfig.lockedToPlayer = false
                    barConfig.lockPosition = nil
                    UpdateLockButtonStates()
                end
                barConfig.lockedToTarget = true
                barConfig.targetLockPosition = corner
                barConfig.offsetX = 0
                barConfig.offsetY = 0
                if xOffsetSlider and xOffsetSlider.SetValue then xOffsetSlider.SetValue(0, true) end
                if yOffsetSlider and yOffsetSlider.SetValue then yOffsetSlider.SetValue(0, true) end
            end
            RefreshPosition()
            UpdateTargetLockButtonStates()
        end

        local function CreateTargetLockButton(parent, label, corner)
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetSize(75, 22)
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("CENTER")
            text:SetText(label)
            text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            btn.label = label
            btn.textObj = text
            btn:SetScript("OnClick", function() LockToTarget(corner) end)
            btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
            btn:SetScript("OnLeave", function(self)
                if not (barConfig.lockedToTarget and barConfig.targetLockPosition == corner) then
                    self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
                end
            end)
            targetLockButtons[corner] = btn
            return btn
        end

        local targetLockTLBtn = CreateTargetLockButton(targetLockContainer, "Top Left", "topleft")
        local targetLockTCBtn = CreateTargetLockButton(targetLockContainer, "Top Center", "topcenter")
        local targetLockTRBtn = CreateTargetLockButton(targetLockContainer, "Top Right", "topright")
        local targetLockBLBtn = CreateTargetLockButton(targetLockContainer, "Btm Left", "bottomleft")
        local targetLockBCBtn = CreateTargetLockButton(targetLockContainer, "Btm Center", "bottomcenter")
        local targetLockBRBtn = CreateTargetLockButton(targetLockContainer, "Btm Right", "bottomright")

        local targetLockRow1Y = (22 + rowGap) / 2
        targetLockTLBtn:SetPoint("LEFT", targetLockContainer, "LEFT", 180, targetLockRow1Y)
        targetLockTCBtn:SetPoint("LEFT", targetLockTLBtn, "RIGHT", btnGap, 0)
        targetLockTRBtn:SetPoint("LEFT", targetLockTCBtn, "RIGHT", btnGap, 0)
        local targetLockRow2Y = -targetLockRow1Y
        targetLockBLBtn:SetPoint("LEFT", targetLockContainer, "LEFT", 180, targetLockRow2Y)
        targetLockBCBtn:SetPoint("LEFT", targetLockBLBtn, "RIGHT", btnGap, 0)
        targetLockBRBtn:SetPoint("LEFT", targetLockBCBtn, "RIGHT", btnGap, 0)

        local function UpdateTargetLockButtonWidths()
            local containerWidth = targetLockContainer:GetWidth()
            if containerWidth and containerWidth > 0 then
                local availableWidth = containerWidth - 180
                local totalGaps = 2 * btnGap
                local btnWidth = (availableWidth - totalGaps) / 3
                if btnWidth > 20 then
                    targetLockTLBtn:SetWidth(btnWidth)
                    targetLockTCBtn:SetWidth(btnWidth)
                    targetLockTRBtn:SetWidth(btnWidth)
                    targetLockBLBtn:SetWidth(btnWidth)
                    targetLockBCBtn:SetWidth(btnWidth)
                    targetLockBRBtn:SetWidth(btnWidth)
                end
            end
        end
        targetLockContainer:HookScript("OnSizeChanged", function() UpdateTargetLockButtonWidths() end)
        C_Timer.After(0, function() UpdateTargetLockButtonWidths() UpdateTargetLockButtonStates() end)

        y = y - (FORM_ROW + 22 + rowGap + 8)

        -- X/Y Offset sliders
        xOffsetSlider = GUI:CreateFormSlider(lowerContainer, "X Offset", -2000, 2000, 1, "offsetX", barConfig, RefreshPosition)
        xOffsetSlider:SetPoint("TOPLEFT", 0, y)
        xOffsetSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        yOffsetSlider = GUI:CreateFormSlider(lowerContainer, "Y Offset", -2000, 2000, 1, "offsetY", barConfig, RefreshPosition)
        yOffsetSlider:SetPoint("TOPLEFT", 0, y)
        yOffsetSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        UpdateLockState()

        -- Prevent Mouse Dragging checkbox
        local lockCheck = GUI:CreateFormCheckbox(lowerContainer, "Prevent Mouse Dragging", "locked", barConfig)
        lockCheck:SetPoint("TOPLEFT", 0, y)
        lockCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- LAYOUT SECTION
        -----------------------------------------------------------------------
        local layoutHeader = GUI:CreateSectionHeader(lowerContainer, "Layout")
        layoutHeader:SetPoint("TOPLEFT", 0, y)
        y = y - layoutHeader.gap

        -- Grow Direction dropdown
        local growOptions = {
            {value = "RIGHT", text = "Right"},
            {value = "LEFT", text = "Left"},
            {value = "UP", text = "Up"},
            {value = "DOWN", text = "Down"},
            {value = "CENTER", text = "Center (Horizontal)"},
            {value = "CENTER_VERTICAL", text = "Center (Vertical)"},
        }
        local growDropdown = GUI:CreateFormDropdown(lowerContainer, "Grow Direction", growOptions, "growDirection", barConfig, RefreshThisBar)
        growDropdown:SetPoint("TOPLEFT", 0, y)
        growDropdown:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local dynamicLayoutCheck = GUI:CreateFormCheckbox(lowerContainer, "Dynamic Layout (Collapsing)", "dynamicLayout", barConfig, RefreshThisBar)
        dynamicLayoutCheck:SetPoint("TOPLEFT", 0, y)
        dynamicLayoutCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local dynamicLayoutDesc = GUI:CreateLabel(lowerContainer, "When enabled, icons that are hidden by visibility rules (e.g. 'Show Only On Cooldown' or 'Show Only When Active') are removed from the layout, so the bar collapses/expands dynamically.", 11, C.textMuted)
        dynamicLayoutDesc:SetPoint("TOPLEFT", 0, y)
        dynamicLayoutDesc:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        dynamicLayoutDesc:SetJustifyH("LEFT")
        dynamicLayoutDesc:SetWordWrap(true)
        dynamicLayoutDesc:SetHeight(40)
        y = y - 50

        -- Icon Shape slider
        local shapeSlider = GUI:CreateFormSlider(lowerContainer, "Icon Shape", 1.0, 2.0, 0.01, "aspectRatioCrop", barConfig, RefreshThisBar)
        shapeSlider:SetPoint("TOPLEFT", 0, y)
        shapeSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeTip = GUI:CreateLabel(lowerContainer, "Higher values imply flatter icons.", 11, C.textMuted)
        shapeTip:SetPoint("TOPLEFT", 0, y)
        shapeTip:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        shapeTip:SetJustifyH("LEFT")
        y = y - 20

        -- Icon Size slider
        local sizeSlider = GUI:CreateFormSlider(lowerContainer, "Icon Size", 16, 64, 1, "iconSize", barConfig, RefreshThisBar)
        sizeSlider:SetPoint("TOPLEFT", 0, y)
        sizeSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Spacing slider
        local spacingSlider = GUI:CreateFormSlider(lowerContainer, "Spacing", 0, 20, 1, "spacing", barConfig, RefreshThisBar)
        spacingSlider:SetPoint("TOPLEFT", 0, y)
        spacingSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- ICON STYLE SECTION
        -----------------------------------------------------------------------
        local styleHeader = GUI:CreateSectionHeader(lowerContainer, "Icon Style")
        styleHeader:SetPoint("TOPLEFT", 0, y)
        y = y - styleHeader.gap

        -- Border Size slider
        local borderSlider = GUI:CreateFormSlider(lowerContainer, "Border Size", 0, 8, 1, "borderSize", barConfig, RefreshThisBar)
        borderSlider:SetPoint("TOPLEFT", 0, y)
        borderSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Zoom slider
        local zoomSlider = GUI:CreateFormSlider(lowerContainer, "Zoom", 0, 0.2, 0.01, "zoom", barConfig, RefreshThisBar)
        zoomSlider:SetPoint("TOPLEFT", 0, y)
        zoomSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- DURATION TEXT SECTION
        -----------------------------------------------------------------------
        local durHeader = GUI:CreateSectionHeader(lowerContainer, "Duration Text")
        durHeader:SetPoint("TOPLEFT", 0, y)
        y = y - durHeader.gap

        local hideDurCheck = GUI:CreateFormCheckbox(lowerContainer, "Hide Text", "hideDurationText", barConfig, RefreshThisBar)
        hideDurCheck:SetPoint("TOPLEFT", 0, y)
        hideDurCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durSizeSlider = GUI:CreateFormSlider(lowerContainer, "Size", 8, 24, 1, "durationSize", barConfig, RefreshThisBar)
        durSizeSlider:SetPoint("TOPLEFT", 0, y)
        durSizeSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durColorPicker = GUI:CreateFormColorPicker(lowerContainer, "Text Color", "durationColor", barConfig, RefreshThisBar)
        durColorPicker:SetPoint("TOPLEFT", 0, y)
        durColorPicker:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durXSlider = GUI:CreateFormSlider(lowerContainer, "X Offset", -20, 20, 1, "durationOffsetX", barConfig, RefreshThisBar)
        durXSlider:SetPoint("TOPLEFT", 0, y)
        durXSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durYSlider = GUI:CreateFormSlider(lowerContainer, "Y Offset", -20, 20, 1, "durationOffsetY", barConfig, RefreshThisBar)
        durYSlider:SetPoint("TOPLEFT", 0, y)
        durYSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- STACK TEXT SECTION
        -----------------------------------------------------------------------
        local stackHeader = GUI:CreateSectionHeader(lowerContainer, "Stack Text")
        stackHeader:SetPoint("TOPLEFT", 0, y)
        y = y - stackHeader.gap

        local showChargesCheck  -- Forward declare for callback reference

        local hideStackCheck = GUI:CreateFormCheckbox(lowerContainer, "Hide Text", "hideStackText", barConfig, function(val)
            RefreshThisBar()
            -- Disable "Show Item Charges" when text is hidden (it has no effect)
            if showChargesCheck and showChargesCheck.SetEnabled then
                showChargesCheck:SetEnabled(not val)
            end
        end)
        hideStackCheck:SetPoint("TOPLEFT", 0, y)
        hideStackCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        showChargesCheck = GUI:CreateFormCheckbox(lowerContainer, "Show Item Charges", "showItemCharges", barConfig, RefreshThisBar)
        showChargesCheck:SetPoint("TOPLEFT", 0, y)
        showChargesCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        -- Initial state: disabled if text is hidden
        if showChargesCheck.SetEnabled then
            showChargesCheck:SetEnabled(not barConfig.hideStackText)
        end
        y = y - FORM_ROW

        local stackSizeSlider = GUI:CreateFormSlider(lowerContainer, "Size", 8, 24, 1, "stackSize", barConfig, RefreshThisBar)
        stackSizeSlider:SetPoint("TOPLEFT", 0, y)
        stackSizeSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackColorPicker = GUI:CreateFormColorPicker(lowerContainer, "Text Color", "stackColor", barConfig, RefreshThisBar)
        stackColorPicker:SetPoint("TOPLEFT", 0, y)
        stackColorPicker:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackXSlider = GUI:CreateFormSlider(lowerContainer, "X Offset", -20, 20, 1, "stackOffsetX", barConfig, RefreshThisBar)
        stackXSlider:SetPoint("TOPLEFT", 0, y)
        stackXSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackYSlider = GUI:CreateFormSlider(lowerContainer, "Y Offset", -20, 20, 1, "stackOffsetY", barConfig, RefreshThisBar)
        stackYSlider:SetPoint("TOPLEFT", 0, y)
        stackYSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- BUFF ACTIVE SETTINGS SECTION
        -----------------------------------------------------------------------
        local buffActiveHeader = GUI:CreateSectionHeader(lowerContainer, "Buff Active Settings")
        buffActiveHeader:SetPoint("TOPLEFT", 0, y)
        y = y - buffActiveHeader.gap

        local glowEnabledCheck = GUI:CreateFormCheckbox(lowerContainer, "Enable Glow", "activeGlowEnabled", barConfig, RefreshThisBar)
        glowEnabledCheck:SetPoint("TOPLEFT", 0, y)
        glowEnabledCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glowTypeOptions = {
            {value = "Pixel Glow", text = "Pixel Glow"},
            {value = "Autocast Shine", text = "Autocast Shine"},
            {value = "Proc Glow", text = "Proc Glow"},
        }
        local glowTypeDropdown = GUI:CreateFormDropdown(lowerContainer, "Glow Type", glowTypeOptions, "activeGlowType", barConfig, RefreshThisBar)
        glowTypeDropdown:SetPoint("TOPLEFT", 0, y)
        glowTypeDropdown:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glowColorPicker = GUI:CreateFormColorPicker(lowerContainer, "Glow Color", "activeGlowColor", barConfig, RefreshThisBar)
        glowColorPicker:SetPoint("TOPLEFT", 0, y)
        glowColorPicker:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glowLinesSlider = GUI:CreateFormSlider(lowerContainer, "Glow Lines", 4, 16, 1, "activeGlowLines", barConfig, RefreshThisBar)
        glowLinesSlider:SetPoint("TOPLEFT", 0, y)
        glowLinesSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glowSpeedSlider = GUI:CreateFormSlider(lowerContainer, "Glow Speed", 0.1, 1.0, 0.05, "activeGlowFrequency", barConfig, RefreshThisBar)
        glowSpeedSlider:SetPoint("TOPLEFT", 0, y)
        glowSpeedSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glowThicknessSlider = GUI:CreateFormSlider(lowerContainer, "Glow Thickness", 1, 5, 1, "activeGlowThickness", barConfig, RefreshThisBar)
        glowThicknessSlider:SetPoint("TOPLEFT", 0, y)
        glowThicknessSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glowScaleSlider = GUI:CreateFormSlider(lowerContainer, "Glow Scale", 0.5, 2.0, 0.1, "activeGlowScale", barConfig, RefreshThisBar)
        glowScaleSlider:SetPoint("TOPLEFT", 0, y)
        glowScaleSlider:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- ICON VISIBILITY SECTION (moved after Buff Active per plan)
        -----------------------------------------------------------------------
        local cooldownOnlyHeader = GUI:CreateSectionHeader(lowerContainer, "Icon Visibility")
        cooldownOnlyHeader:SetPoint("TOPLEFT", 0, y)
        y = y - cooldownOnlyHeader.gap + 10

        local cooldownOnlyDesc = GUI:CreateLabel(lowerContainer, "Control when icons are visible. The first three options are mutually exclusive. 'Show Only In Combat' can be combined with any other option.", 11, C.textMuted)
        cooldownOnlyDesc:SetPoint("TOPLEFT", 0, y)
        cooldownOnlyDesc:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        cooldownOnlyDesc:SetJustifyH("LEFT")
        cooldownOnlyDesc:SetWordWrap(true)
        cooldownOnlyDesc:SetHeight(30)
        y = y - 38

        local showOnlyInCombatCheck = GUI:CreateFormCheckbox(lowerContainer, "Show Only In Combat", "showOnlyInCombat", barConfig, nil)
        showOnlyInCombatCheck:SetPoint("TOPLEFT", 0, y)
        showOnlyInCombatCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showOnlyOnCooldownCheck = GUI:CreateFormCheckbox(lowerContainer, "Show Only On Cooldown", "showOnlyOnCooldown", barConfig, nil)
        showOnlyOnCooldownCheck:SetPoint("TOPLEFT", 0, y)
        showOnlyOnCooldownCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showOnlyWhenActiveCheck = GUI:CreateFormCheckbox(lowerContainer, "Show Only When Active", "showOnlyWhenActive", barConfig, nil)
        showOnlyWhenActiveCheck:SetPoint("TOPLEFT", 0, y)
        showOnlyWhenActiveCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showOnlyWhenOffCooldownCheck = GUI:CreateFormCheckbox(lowerContainer, "Show Only When Off Cooldown", "showOnlyWhenOffCooldown", barConfig, nil)
        showOnlyWhenOffCooldownCheck:SetPoint("TOPLEFT", 0, y)
        showOnlyWhenOffCooldownCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Mutual exclusion handlers for cooldown/active visibility checkboxes
        -- showOnlyOnCooldown, showOnlyWhenActive, showOnlyWhenOffCooldown are mutually exclusive
        -- showOnlyInCombat can be combined with any of them
        if showOnlyOnCooldownCheck.track then
            showOnlyOnCooldownCheck.track:SetScript("OnClick", function()
                local newVal = not showOnlyOnCooldownCheck.GetValue()
                showOnlyOnCooldownCheck.SetValue(newVal, true)
                if newVal then
                    showOnlyWhenActiveCheck.SetValue(false, true)
                    showOnlyWhenOffCooldownCheck.SetValue(false, true)
                end
                RefreshThisBar()
            end)
        end
        if showOnlyWhenActiveCheck.track then
            showOnlyWhenActiveCheck.track:SetScript("OnClick", function()
                local newVal = not showOnlyWhenActiveCheck.GetValue()
                showOnlyWhenActiveCheck.SetValue(newVal, true)
                if newVal then
                    showOnlyOnCooldownCheck.SetValue(false, true)
                    showOnlyWhenOffCooldownCheck.SetValue(false, true)
                end
                RefreshThisBar()
            end)
        end
        if showOnlyWhenOffCooldownCheck.track then
            showOnlyWhenOffCooldownCheck.track:SetScript("OnClick", function()
                local newVal = not showOnlyWhenOffCooldownCheck.GetValue()
                showOnlyWhenOffCooldownCheck.SetValue(newVal, true)
                if newVal then
                    showOnlyOnCooldownCheck.SetValue(false, true)
                    showOnlyWhenActiveCheck.SetValue(false, true)
                end
                RefreshThisBar()
            end)
        end
        if showOnlyInCombatCheck.track then
            showOnlyInCombatCheck.track:SetScript("OnClick", function()
                local newVal = not showOnlyInCombatCheck.GetValue()
                showOnlyInCombatCheck.SetValue(newVal, true)
                RefreshThisBar()
            end)
        end

        -----------------------------------------------------------------------
        -- ADVANCED SETTINGS SECTION
        -----------------------------------------------------------------------
        local advancedHeader = GUI:CreateSectionHeader(lowerContainer, "Advanced Settings")
        advancedHeader:SetPoint("TOPLEFT", 0, y)
        y = y - advancedHeader.gap

        -- Show Recharge Swipe checkbox
        local showRechargeSwipe = GUI:CreateFormCheckbox(lowerContainer, "Show Recharge Swipe", "showRechargeSwipe", barConfig, RefreshThisBar)
        showRechargeSwipe:SetPoint("TOPLEFT", 0, y)
        showRechargeSwipe:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Recharge swipe description (below toggle)
        local rechargeSwipeDesc = GUI:CreateLabel(lowerContainer, "DO NOT turn on unless you know what you're doing. Shows GCD and radial swipe animations when spells are recharging.", 10, C.textMuted)
        rechargeSwipeDesc:SetPoint("TOPLEFT", 0, y + 4)
        y = y - 18

        -- Enable Spec-Specific Spells checkbox
        local specEnableCheck = GUI:CreateFormCheckbox(lowerContainer, "Enable Spec-Specific Spells", "specSpecificSpells", barConfig, function()
            if barConfig.specSpecificSpells then
                local specKey = getCurrentSpecKey()
                if specKey and trackerModule then
                    trackerModule:CopyEntriesToSpec(barConfig, specKey)
                end
            end
            refreshForSpec()
            if copyFromDropdown then
                if barConfig.specSpecificSpells then
                    copyFromDropdown:Show()
                else
                    copyFromDropdown:Hide()
                end
            end
        end)
        specEnableCheck:SetPoint("TOPLEFT", 0, y)
        specEnableCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Spec-specific description (below toggle)
        local specHint = GUI:CreateLabel(lowerContainer, "When enabled, the spell list for this bar is saved separately for each spec. The bar's layout settings remain shared.", 10, C.textMuted)
        specHint:SetPoint("TOPLEFT", 0, y + 4)
        specHint:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        specHint:SetJustifyH("LEFT")
        specHint:SetWordWrap(true)
        specHint:SetHeight(26)
        y = y - 34

        -- Build specs list for copy dropdown
        local allSpecs = {}
        if trackerModule and trackerModule.GetAllClassSpecs then
            allSpecs = trackerModule.GetAllClassSpecs()
        else
            local _, className = UnitClass("player")
            local numSpecs = GetNumSpecializations()
            for i = 1, numSpecs do
                local specID, specName = GetSpecializationInfo(i)
                if specID and specName then
                    table.insert(allSpecs, {
                        key = className .. "-" .. specID,
                        name = className:sub(1, 1):upper() .. className:sub(2):lower() .. " - " .. specName,
                    })
                end
            end
        end

        -- Info label (shows currently editing spec)
        specInfoLabel = GUI:CreateLabel(lowerContainer, "", 11, C.accent)
        specInfoLabel:SetPoint("TOPLEFT", 0, y)
        specInfoLabel:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        specInfoLabel:SetJustifyH("LEFT")
        updateSpecInfoLabel()
        y = y - 18

        -- Copy From dropdown container
        local copyContainer = CreateFrame("Frame", nil, lowerContainer)
        copyContainer:SetHeight(FORM_ROW)
        copyContainer:SetPoint("TOPLEFT", 0, y)
        copyContainer:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)

        local copyLabel = copyContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        copyLabel:SetPoint("LEFT", 0, 0)
        copyLabel:SetText("Copy spells from")
        copyLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

        local copyOptions = {}
        local targetSpec = getCurrentSpecKey()
        for _, spec in ipairs(allSpecs) do
            if spec.key ~= targetSpec then
                local entryCount = 0
                if trackerModule then
                    local specEntries = trackerModule:GetSpecEntries(barConfig, spec.key)
                    entryCount = specEntries and #specEntries or 0
                end
                local suffix = entryCount > 0 and (" (" .. entryCount .. " spells)") or " (empty)"
                table.insert(copyOptions, { value = spec.key, text = spec.name .. suffix })
            end
        end

        local copyDropdownWidget = GUI:CreateFormDropdown(copyContainer, "", copyOptions, nil, nil, function(selectedValue)
            if selectedValue and trackerModule then
                local sourceEntries = trackerModule:GetSpecEntries(barConfig, selectedValue)
                if sourceEntries and #sourceEntries > 0 then
                    local destSpec = getCurrentSpecKey()
                    local copiedEntries = {}
                    for _, entry in ipairs(sourceEntries) do
                        table.insert(copiedEntries, {
                            type = entry.type,
                            id = entry.id,
                            customName = entry.customName,
                        })
                    end
                    trackerModule:SetSpecEntries(barConfig, destSpec, copiedEntries)
                    refreshForSpec()
                end
            end
        end)
        copyDropdownWidget:SetPoint("LEFT", copyLabel, "RIGHT", 10, 0)
        copyDropdownWidget:SetPoint("RIGHT", copyContainer, "RIGHT", 0, 0)

        if not barConfig.specSpecificSpells then
            copyContainer:Hide()
        end
        copyFromDropdown = copyContainer
        y = y - FORM_ROW

        -- Set lowerContainer height based on content (increased for new sections)
        lowerContainer:SetHeight(math.abs(y) + 40)

        -- tabContent height needs to accommodate more content now
        tabContent:SetHeight(1200)
    end

    ---------------------------------------------------------------------------
    -- Build sub-tabs dynamically from bars
    ---------------------------------------------------------------------------
    -- Reference to be populated after subTabs creation (for live tab text updates)
    local subTabsRef = {}

    local tabDefs = {}

    ---------------------------------------------------------------------------
    -- SPELL SCANNER TAB (always first)
    ---------------------------------------------------------------------------
    table.insert(tabDefs, {
        name = "Setup Custom Buff Tracking",
        builder = function(tabContent)
            GUI:SetSearchContext({tabIndex = 9, tabName = "Custom Items/Spells/Buffs", subTabIndex = 1, subTabName = "Spell Scanner"})
            local y = -10
            local scanner = QUI.SpellScanner
            local scannedListFrame  -- Forward declaration for refresh

            -- Header
            local header = GUI:CreateSectionHeader(tabContent, "Spell Scanner")
            header:SetPoint("TOPLEFT", PAD, y)
            y = y - header.gap

            -- "How It Works" mini-header
            local howItWorks = GUI:CreateLabel(tabContent, "How It Works", 11, C.accentLight)
            howItWorks:SetPoint("TOPLEFT", PAD, y)
            y = y - 16

            -- Step 1
            local step1 = GUI:CreateLabel(tabContent, "1. Enable Scan Mode and cast spells or items out of combat to record their buff durations", 11, C.text)
            step1:SetPoint("TOPLEFT", PAD, y)
            step1:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            step1:SetJustifyH("LEFT")
            step1:SetWordWrap(true)
            step1:SetHeight(28)
            y = y - 32

            -- Step 2
            local step2 = GUI:CreateLabel(tabContent, "2. Add those spells/items to a Custom Tracker bar", 11, C.text)
            step2:SetPoint("TOPLEFT", PAD, y)
            step2:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            step2:SetJustifyH("LEFT")
            y = y - 20

            -- Step 3
            local step3 = GUI:CreateLabel(tabContent, "3. The icons on your Custom Bars will now show accurate custom buff timers in combat", 11, C.text)
            step3:SetPoint("TOPLEFT", PAD, y)
            step3:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            step3:SetJustifyH("LEFT")
            y = y - 26

            -- Scan Mode Toggle
            local scanModeContainer = CreateFrame("Frame", nil, tabContent)
            scanModeContainer:SetHeight(FORM_ROW)
            scanModeContainer:SetPoint("TOPLEFT", PAD, y)
            scanModeContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            local scanLabel = scanModeContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            scanLabel:SetPoint("LEFT", 0, 0)
            scanLabel:SetText("Scan Mode")
            scanLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

            local scanBtn = GUI:CreateButton(scanModeContainer, "Enable", 100, 24, function(self)
                if scanner then
                    local enabled = scanner.ToggleScanMode()
                    if enabled then
                        self.text:SetText("Disable")
                        self:SetBackdropColor(0.2, 0.6, 0.2, 1)
                    else
                        self.text:SetText("Enable")
                        self:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
                    end
                end
            end)
            scanBtn:SetPoint("LEFT", 180, 0)
            -- Set initial state
            if scanner and scanner.scanMode then
                scanBtn.text:SetText("Disable")
                scanBtn:SetBackdropColor(0.2, 0.6, 0.2, 1)
            end

            y = y - FORM_ROW

            -- Auto-Scan Toggle (persistent setting) - using proper switch toggle
            -- Ensure spellScanner db exists with proper defaults
            if not QUI.db.global.spellScanner then
                QUI.db.global.spellScanner = { spells = {}, items = {}, autoScan = false }
            end
            -- Ensure autoScan key exists (could be nil from older version)
            if QUI.db.global.spellScanner.autoScan == nil then
                QUI.db.global.spellScanner.autoScan = false
            end

            local autoScanToggle = GUI:CreateFormToggle(tabContent, "Auto-Scan (silent)", "autoScan", QUI.db.global.spellScanner, function(val)
                if scanner then
                    scanner.autoScan = val  -- Keep runtime state in sync
                end
            end)
            autoScanToggle:SetPoint("TOPLEFT", PAD, y)
            autoScanToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            y = y - FORM_ROW - 10

            -- Scanned Spells Header
            local scannedHeader = GUI:CreateSectionHeader(tabContent, "Scanned Spells & Items")
            scannedHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - scannedHeader.gap

            -- Refresh function for the list (matches Tracked Items pattern)
            local function RefreshScannedList()
                if not scannedListFrame then return end

                -- Clear existing child frames
                for _, child in ipairs({scannedListFrame:GetChildren()}) do
                    child:Hide()
                    child:SetParent(nil)
                end

                local scannerDB = QUI.db and QUI.db.global and QUI.db.global.spellScanner
                local listY = 0
                local rowHeight = 30

                -- Helper to create a row (matches Tracked Items style)
                local function CreateScannedRow(id, data, isItem)
                    local entryFrame = CreateFrame("Frame", nil, scannedListFrame)
                    entryFrame:SetSize(320, 28)
                    entryFrame:SetPoint("TOPLEFT", 0, listY)

                    -- Icon (24x24)
                    local iconTex = entryFrame:CreateTexture(nil, "ARTWORK")
                    iconTex:SetSize(24, 24)
                    iconTex:SetPoint("LEFT", 0, 0)
                    iconTex:SetTexture(data.icon or 134400)
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                    -- Name display (input-box style background)
                    local nameBg = CreateFrame("Frame", nil, entryFrame, "BackdropTemplate")
                    nameBg:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                    nameBg:SetSize(200, 22)
                    nameBg:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    nameBg:SetBackdropColor(0.05, 0.05, 0.05, 0.4)
                    nameBg:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

                    local nameText = nameBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    nameText:SetPoint("LEFT", 6, 0)
                    nameText:SetPoint("RIGHT", -6, 0)
                    nameText:SetJustifyH("LEFT")
                    local displayName = data.name or (isItem and "Item " .. id or "Spell " .. id)
                    local durationStr = string.format("%.1fs", data.duration or 0)
                    nameText:SetText(displayName .. "  |cff888888" .. durationStr .. "|r")
                    nameText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

                    -- Delete button (X) - matches Tracked Items style
                    local removeBtn = CreateFrame("Button", nil, entryFrame, "BackdropTemplate")
                    removeBtn:SetSize(22, 22)
                    removeBtn:SetPoint("LEFT", nameBg, "RIGHT", 6, 0)
                    removeBtn:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    removeBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
                    removeBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

                    local removeText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    removeText:SetPoint("CENTER", 0, 0)
                    removeText:SetText("X")
                    removeText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)

                    removeBtn:SetScript("OnClick", function()
                        if scannerDB then
                            if isItem then
                                scannerDB.items[id] = nil
                            else
                                scannerDB.spells[id] = nil
                            end
                            RefreshScannedList()
                        end
                    end)
                    removeBtn:SetScript("OnEnter", function(self)
                        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    end)
                    removeBtn:SetScript("OnLeave", function(self)
                        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                    end)

                    listY = listY - rowHeight
                end

                -- List spells
                for spellID, data in pairs((scannerDB and scannerDB.spells) or {}) do
                    CreateScannedRow(spellID, data, false)
                end

                -- List items
                for itemID, data in pairs((scannerDB and scannerDB.items) or {}) do
                    CreateScannedRow(itemID, data, true)
                end

                -- Update list frame height
                local listHeight = math.max(20, math.abs(listY))
                scannedListFrame:SetHeight(listHeight)
            end

            -- Scanned list container (no backdrop, matches Tracked Items style)
            scannedListFrame = CreateFrame("Frame", nil, tabContent)
            scannedListFrame:SetPoint("TOPLEFT", PAD, y)
            scannedListFrame:SetSize(400, 20)

            -- Register callback for real-time updates when spells are scanned
            if scanner then
                scanner.onScanCallback = RefreshScannedList
            end

            -- Populate the list
            RefreshScannedList()

            -- Lower container anchored to list (shifts down when list grows)
            local lowerContainer = CreateFrame("Frame", nil, tabContent)
            lowerContainer:SetPoint("TOPLEFT", scannedListFrame, "BOTTOMLEFT", 0, -15)
            lowerContainer:SetPoint("RIGHT", tabContent, "RIGHT", 0, 0)
            lowerContainer:SetHeight(100)
            lowerContainer:EnableMouse(false)

            -- Clear all button (in lower container)
            local clearBtn = GUI:CreateButton(lowerContainer, "Clear All Scanned", 140, 24, function()
                GUI:ShowConfirmation({
                    title = "Clear All Scanned Spells?",
                    message = "This will remove all scanned spell and item durations. You will need to cast them again to re-scan.",
                    acceptText = "Clear All",
                    cancelText = "Cancel",
                    onAccept = function()
                        local scannerDB = QUI.db and QUI.db.global and QUI.db.global.spellScanner
                        if scannerDB then
                            scannerDB.spells = {}
                            scannerDB.items = {}
                            RefreshScannedList()
                        end
                    end,
                })
            end)
            clearBtn:SetPoint("TOPLEFT", 0, 0)

            tabContent:SetHeight(500)
        end,
    })

    -- Add a tab for each existing bar
    for i, barConfig in ipairs(bars) do
        local tabName = barConfig.name or ("Tracker " .. i)
        -- Truncate long names for tab display
        if #tabName > 20 then
            tabName = tabName:sub(1, 17) .. "..."
        end
        table.insert(tabDefs, {
            name = tabName,
            builder = function(tabContent)
                -- Pass i+1 for subTabIndex since Spell Scanner is tab 1
                BuildTrackerBarTab(tabContent, barConfig, i + 1, subTabsRef)
            end,
        })
    end

    -- If no bars exist (only Spell Scanner tab), show empty state
    if #tabDefs == 1 then
        local emptyHeader = GUI:CreateSectionHeader(content, "Custom Tracker Bars")
        emptyHeader:SetPoint("TOPLEFT", PAD, -15)

        local emptyLabel = GUI:CreateLabel(content, "No tracker bars created yet. A default bar will be created on next /reload.", 12, C.textMuted)
        emptyLabel:SetPoint("TOPLEFT", PAD, -60)
        emptyLabel:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        emptyLabel:SetJustifyH("LEFT")

        -- Add bar button
        local addBtn = GUI:CreateButton(content, "+ Add Tracker Bar", 160, 28, function()
            local newID = "tracker" .. (time() % 100000)
            -- Calculate position relative to player frame
            local newOffsetX, newOffsetY = CalculatePlayerRelativeOffset(-20, -50)
            local newBar = {
                id = newID,
                name = "Tracker " .. (#bars + 1),
                enabled = false,
                locked = false,
                offsetX = newOffsetX,
                offsetY = newOffsetY,
                growDirection = "RIGHT",
                iconSize = 28,
                spacing = 4,
                borderSize = 2,
                shape = "square",
                zoom = 0,
                durationSize = 13,
                durationColor = {1, 1, 1, 1},
                durationOffsetX = 0,
                durationOffsetY = 0,
                stackSize = 9,
                stackColor = {1, 1, 1, 1},
                stackOffsetX = 3,
                stackOffsetY = -1,
                bgOpacity = 0,
                hideGCD = true,
                showRechargeSwipe = false,
                entries = {},
            }
            table.insert(db.customTrackers.bars, newBar)
            if QUICore and QUICore.CustomTrackers then
                QUICore.CustomTrackers:RefreshAll()
            end
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Tracker bar created. Reload UI to configure it?",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        addBtn:SetPoint("TOPLEFT", PAD, -100)
        content:SetHeight(200)
    else
        -- Add a "+" tab to create new bars
        table.insert(tabDefs, {
            name = "+ Add Bar",
            builder = function(tabContent)
                local y = -10
                local header = GUI:CreateSectionHeader(tabContent, "Add New Tracker Bar")
                header:SetPoint("TOPLEFT", PAD, y)
                y = y - header.gap

                local desc = GUI:CreateLabel(tabContent, "Create a new tracker bar to monitor consumables, trinkets, or ability cooldowns.", 11, C.textMuted)
                desc:SetPoint("TOPLEFT", PAD, y)
                desc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                desc:SetJustifyH("LEFT")
                y = y - 30

                local addBtn = GUI:CreateButton(tabContent, "Create New Tracker Bar", 180, 28, function()
                    local newID = "tracker" .. (time() % 100000)
                    -- Calculate position relative to player frame (stagger by bar count)
                    local staggerY = #bars * 40  -- Each new bar 40px lower
                    local newOffsetX, newOffsetY = CalculatePlayerRelativeOffset(-20, -50 - staggerY)
                    local newBar = {
                        id = newID,
                        name = "Tracker " .. (#bars + 1),
                        enabled = false,
                        locked = false,
                        offsetX = newOffsetX,
                        offsetY = newOffsetY,
                        growDirection = "RIGHT",
                        iconSize = 28,
                        spacing = 4,
                        borderSize = 2,
                        shape = "square",
                        zoom = 0,
                        durationSize = 13,
                        durationColor = {1, 1, 1, 1},
                        durationOffsetX = 0,
                        durationOffsetY = 0,
                        stackSize = 9,
                        stackColor = {1, 1, 1, 1},
                        stackOffsetX = 3,
                        stackOffsetY = -1,
                        bgOpacity = 0,
                        hideGCD = true,
                        showRechargeSwipe = false,
                        entries = {},
                    }
                    table.insert(db.customTrackers.bars, newBar)
                    if QUICore and QUICore.CustomTrackers then
                        QUICore.CustomTrackers:RefreshAll()
                    end
                    GUI:ShowConfirmation({
                        title = "Reload UI?",
                        message = "Tracker bar created. Reload UI to configure it?",
                        acceptText = "Reload",
                        cancelText = "Later",
                        onAccept = function() QUI:SafeReload() end,
                    })
                end)
                addBtn:SetPoint("TOPLEFT", PAD, y)
                tabContent:SetHeight(150)
            end,
        })

        -- Create sub-tabs
        local subTabs = GUI:CreateSubTabs(content, tabDefs)
        subTabsRef.tabButtons = subTabs.tabButtons  -- Populate reference for live tab text updates
        subTabs:SetPoint("TOPLEFT", 5, -5)
        subTabs:SetPoint("TOPRIGHT", -5, -5)
        subTabs:SetHeight(750)

        content:SetHeight(800)
    end
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_CustomTrackersOptions = {
    CreateCustomTrackersPage = CreateCustomTrackersPage
}
