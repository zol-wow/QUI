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
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local trackerSurfaceState, GetTrackerSurfaceState = Helpers.CreateStateTable()

local function ApplyTrackerSurface(frame, bgColor, borderColor, borderSizePixels)
    if not frame then return end

    local state = GetTrackerSurfaceState(frame)
    state.bgColor = bgColor or state.bgColor or {0.1, 0.1, 0.1, 0.8}
    state.borderColor = borderColor or state.borderColor or {0.3, 0.3, 0.3, 1}
    state.borderSizePixels = borderSizePixels or state.borderSizePixels or 1

    if not state.bg then
        state.bg = frame:CreateTexture(nil, "BACKGROUND")
        state.bg:SetAllPoints()
        state.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UIKit and UIKit.DisablePixelSnap then
            UIKit.DisablePixelSnap(state.bg)
        end
    end
    state.bg:SetVertexColor(unpack(state.bgColor))

    if UIKit and UIKit.CreateBackdropBorder then
        state.border = UIKit.CreateBackdropBorder(
            frame,
            state.borderSizePixels,
            state.borderColor[1] or 0,
            state.borderColor[2] or 0,
            state.borderColor[3] or 0,
            state.borderColor[4] or 1
        )
        state.border:SetFrameLevel(frame:GetFrameLevel() + 1)
    end
end

local function SetTrackerSurfaceBorderColor(frame, r, g, b, a)
    if not frame then return end
    local state = GetTrackerSurfaceState(frame)
    state.borderColor = {r or 0.3, g or 0.3, b or 0.3, a or 1}
    ApplyTrackerSurface(frame)
end

local function CreateTrackerSurfaceFrame(parent, width, height, bgColor, borderColor)
    local frame = CreateFrame("Frame", nil, parent)
    if UIKit and UIKit.SetSizePx then
        UIKit.SetSizePx(frame, width, height)
    else
        frame:SetSize(width, height)
    end
    ApplyTrackerSurface(frame, bgColor, borderColor, 1)
    return frame
end

local function CreateTrackerSurfaceButton(parent, width, height, onClick, options)
    options = options or {}

    local btn = CreateFrame("Button", nil, parent)
    if UIKit and UIKit.SetSizePx then
        UIKit.SetSizePx(btn, width, height)
    else
        btn:SetSize(width, height)
    end

    local bgColor = options.bgColor or {0.1, 0.1, 0.1, 0.8}
    local borderColor = options.borderColor or {0.3, 0.3, 0.3, 1}
    local hoverBorderColor = options.hoverBorderColor or C.accent
    ApplyTrackerSurface(btn, bgColor, borderColor, options.borderSizePixels or 1)

    if options.text then
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("CENTER", options.textOffsetX or 0, options.textOffsetY or 0)
        btn.text:SetText(options.text)
        btn.text:SetTextColor(unpack(options.textColor or C.text))
    end

    btn:SetScript("OnEnter", function(self)
        SetTrackerSurfaceBorderColor(self, unpack(hoverBorderColor))
        if self.text and options.hoverTextColor then
            self.text:SetTextColor(unpack(options.hoverTextColor))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        SetTrackerSurfaceBorderColor(self, unpack(borderColor))
        if self.text then
            self.text:SetTextColor(unpack(options.textColor or C.text))
        end
    end)
    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    return btn
end
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
    GUI:SetSearchContext({tabIndex = 11, tabName = "Custom Trackers"})

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
    local ACTION_ROW_HEIGHT = 28
    local TRACKER_HOST_HEIGHT = (#bars > 0) and 1210 or 100
    local PAGE_HEIGHT = math.max(TRACKER_HOST_HEIGHT + 80, 1250)

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

    local function RebuildCustomTrackersPage(selectedBarIndex)
        C_Timer.After(0, function()
            local mainFrame = GUI and GUI.MainFrame
            if not mainFrame then return end

            local page = mainFrame.pages and mainFrame.pages[11]
            if not page then return end

            if page._subTabGroup then
                page._subTabGroup:Hide()
                page._subTabGroup:SetParent(nil)
                page._subTabGroup = nil
                page._subTabDefs = nil
            end

            if page.frame then
                page.frame:Hide()
                page.frame:SetParent(nil)
                page.frame = nil
            end

            page.built = false
            GUI._lastSubTabGroup = nil

            if selectedBarIndex and selectedBarIndex > 0 then
                GUI:NavigateTo(11, selectedBarIndex)
            else
                GUI:SelectTab(mainFrame, 11)
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Helper: Create drop zone for adding items/spells via drag-and-drop
    ---------------------------------------------------------------------------
    local function CreateAddEntrySection(parentFrame, barID, refreshCallback)
        local container = CreateFrame("Frame", nil, parentFrame)
        container:SetHeight(83)  -- 50% taller than original 55

        -- DROP ZONE: Click here while holding an item/spell on cursor
        local dropZone = CreateFrame("Button", nil, container)
        if UIKit and UIKit.SetHeightPx then
            UIKit.SetHeightPx(dropZone, 68)  -- 50% taller than original 45
        else
            dropZone:SetHeight(68)
        end
        dropZone:SetPoint("TOPLEFT", 0, 0)
        dropZone:SetPoint("RIGHT", container, "RIGHT", 0, 0)  -- Full width
        ApplyTrackerSurface(dropZone, {C.bg[1], C.bg[2], C.bg[3], 0.8}, {C.accent[1], C.accent[2], C.accent[3], 0.5}, 1)

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
                SetTrackerSurfaceBorderColor(self, C.accent[1], C.accent[2], C.accent[3], 1)
                dropLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
            end
        end)
        dropZone:SetScript("OnLeave", function(self)
            SetTrackerSurfaceBorderColor(self, C.accent[1], C.accent[2], C.accent[3], 0.5)
            dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end)

        return container
    end

    -- Slot name fallbacks for common equipment slots
    local SLOT_NAMES = {
        [13] = "Trinket 1",
        [14] = "Trinket 2",
    }

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
        elseif entry.type == "slot" then
            local itemID = GetInventoryItemID("player", entry.id)
            if itemID then
                local name = C_Item.GetItemInfo(itemID)
                if name then return name end
            end
            return SLOT_NAMES[entry.id] or ("Slot " .. entry.id)
        else
            local name = C_Item.GetItemInfo(entry.id)
            return name or ("Item " .. entry.id)
        end
    end

    ---------------------------------------------------------------------------
    -- Build tab content for a single tracker bar
    ---------------------------------------------------------------------------
    local function BuildTrackerBarTab(tabContent, barConfig, barIndex, subTabsRef, rebuildPage)
        GUI:SetSearchContext({tabIndex = 11, tabName = "Custom Trackers", subTabIndex = barIndex, subTabName = barConfig.name or ("Bar " .. barIndex)})
        local y = -10

        local entryListFrame  -- Forward declaration for refresh callback

        -- Refresh callback for this bar
        local function RefreshThisBar()
            if QUICore and QUICore.CustomTrackers then
                QUICore.CustomTrackers:UpdateBar(barConfig.id)
            end
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
        local nameRow = GUI:CreateFormEditBox(tabContent, "Bar Name", nil, nil, nil, {
            width = 200,
            value = barConfig.name or "Tracker Bar",
            commitOnEnter = false,
            commitOnFocusLost = false,
            live = true,
            onTextChanged = function(self)
                local newName = self:GetText()
                if newName == "" then newName = "Tracker Bar" end
                barConfig.name = newName

                if subTabsRef and subTabsRef.tabButtons and subTabsRef.tabButtons[barIndex] then
                    local displayName = newName
                    if #displayName > 20 then
                        displayName = displayName:sub(1, 17) .. "..."
                    end
                    subTabsRef.tabButtons[barIndex].text:SetText(displayName)
                end
                if subTabsRef and subTabsRef.subTabDefs and subTabsRef.subTabDefs[barIndex] then
                    subTabsRef.subTabDefs[barIndex].name = newName
                    if GUI and GUI.MainFrame and GUI.RefreshSidebarTree then
                        GUI:RefreshSidebarTree(GUI.MainFrame)
                    end
                end
            end,
            onEscapePressed = function(self)
                self:ClearFocus()
            end,
        })
        nameRow:SetPoint("TOPLEFT", PAD, y)
        nameRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Export This Bar button
        y = y - 10
        local exportBarBtn = GUI:CreateButton(tabContent, "Export This Bar", 130, 26, function()
            local exportStr, err = QUICore:ExportSingleTrackerBar(barIndex)
            if not exportStr then
                print("|cffff0000QUI:|r " .. (err or "Export failed"))
                return
            end
            GUI:ShowExportPopup("Export Tracker Bar", exportStr)
        end)
        exportBarBtn:SetPoint("TOPLEFT", PAD, y)

        -- Delete Bar button
        local deleteBtn = GUI:CreateButton(tabContent, "Delete Bar", 120, 26, function()
            GUI:ShowConfirmation({
                title = "Delete Tracker Bar?",
                message = "Delete this custom tracker bar?",
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
                        if QUICore.CustomTrackers.UnregisterDynamicLayoutElement then
                            QUICore.CustomTrackers:UnregisterDynamicLayoutElement(barConfig.id)
                        end
                        if QUICore.CustomTrackers.UpdateEventRegistrations then
                            QUICore.CustomTrackers.UpdateEventRegistrations()
                        end
                    end
                    if QUI and QUI.db and QUI.db.global and QUI.db.global.specTrackerSpells then
                        QUI.db.global.specTrackerSpells[barConfig.id] = nil
                    end
                    if ns.QUI_Anchoring and ns.QUI_Anchoring.RegisterAllFrameTargets then
                        ns.QUI_Anchoring:RegisterAllFrameTargets()
                    end
                    if rebuildPage then
                        local nextIndex = nil
                        if db.customTrackers.bars and #db.customTrackers.bars > 0 then
                            nextIndex = math.max(1, math.min(barIndex, #db.customTrackers.bars))
                        end
                        rebuildPage(nextIndex)
                    end
                end,
            })
        end)
        deleteBtn:SetPoint("LEFT", exportBarBtn, "RIGHT", 10, 0)
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

        local hintText = GUI:CreateLabel(tabContent, "Drag items from your bags or character pane, spells from your spellbook into the box below, or use the buttons below to track equipment slots.", 11, C.textMuted)
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
                elseif entry.type == "slot" then
                    local itemID = GetInventoryItemID("player", entry.id)
                    if itemID then
                        local _, _, _, _, _, _, _, _, _, slotIcon = C_Item.GetItemInfo(itemID)
                        iconTex:SetTexture(slotIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    else
                        iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    end
                else
                    local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(entry.id)
                    iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                end
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                entryFrame.iconTex = iconTex  -- Store reference for name resolution

                -- Name (editable input box with subtle styling)
                local nameInputBg, nameInput = GUI:CreateInlineEditBox(entryFrame, {
                    width = 176,
                    height = 22,
                    editHeight = 20,
                    textInset = 6,
                    text = GetEntryDisplayName(entry),
                    bgColor = {0.05, 0.05, 0.05, 0.4},
                    borderColor = {0.25, 0.25, 0.25, 0.6},
                    activeBorderColor = C.accent,
                    onEscapePressed = function(self)
                        self:SetText(GetEntryDisplayName(self.entry))
                    end,
                    onEditFocusGained = function(self)
                        self:HighlightText()
                    end,
                })
                nameInputBg:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)

                -- Store reference to entry for saving
                nameInput.entry = entry
                nameInput.barConfig = barConfig

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

                    -- Slot entries: name edits are custom display name only (don't resolve as spell/item)
                    if self.entry.type == "slot" then
                        self.entry.customName = newName
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
                nameInput:SetScript("OnEditFocusLost", function(self)
                    nameInputBg:SetFieldBorderColor(0.25, 0.25, 0.25, 0.6)
                    ResolveAndUpdateEntry(self)
                end)
                nameInput:SetScript("OnEditFocusGained", function(self)
                    nameInputBg:SetFieldBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    self:HighlightText()
                end)

                -- Store reference for button positioning
                local entryName = nameInputBg

                -- Helper: Create styled chevron button (matches dropdown style)
                local function CreateChevronButton(parent, direction, onClick)
                    local btn = CreateTrackerSurfaceButton(parent, 22, 22, onClick, {
                        bgColor = {0.1, 0.1, 0.1, 0.8},
                        borderColor = {0.3, 0.3, 0.3, 1},
                        hoverBorderColor = {C.accent[1], C.accent[2], C.accent[3], 1},
                    })

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
                    if UIKit and UIKit.DisablePixelSnap then
                        UIKit.DisablePixelSnap(chevronLeft)
                        UIKit.DisablePixelSnap(chevronRight)
                    end

                    btn:HookScript("OnEnter", function(self)
                        self.chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                        self.chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                    end)
                    btn:HookScript("OnLeave", function(self)
                        self.chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                        self.chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
                    end)

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
                local removeBtn = CreateTrackerSurfaceButton(entryFrame, 22, 22, function()
                    if QUICore and QUICore.CustomTrackers then
                        QUICore.CustomTrackers:RemoveEntry(barConfig.id, entry.type, entry.id, nil)
                    end
                    RefreshEntryList()
                end, {
                    text = "X",
                    textColor = {C.accent[1], C.accent[2], C.accent[3], 0.7},
                    hoverTextColor = {C.accent[1], C.accent[2], C.accent[3], 1},
                    bgColor = {0.1, 0.1, 0.1, 0.8},
                    borderColor = {0.3, 0.3, 0.3, 1},
                    hoverBorderColor = {C.accent[1], C.accent[2], C.accent[3], 1},
                })
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

        -- Equipment slot buttons (Trinket 1 / Trinket 2)
        local slotBtnContainer = CreateFrame("Frame", nil, tabContent)
        slotBtnContainer:SetHeight(30)
        slotBtnContainer:SetPoint("TOPLEFT", addSection, "BOTTOMLEFT", 0, -6)
        slotBtnContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local slotLabel = slotBtnContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slotLabel:SetPoint("LEFT", 0, 0)
        slotLabel:SetText("Track Equipment Slot:")
        slotLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

        local trinket1Btn = GUI:CreateButton(slotBtnContainer, "Trinket 1", 90, 24, function()
            local trackerMod = QUICore and QUICore.CustomTrackers
            if trackerMod then
                trackerMod:AddEntry(barConfig.id, "slot", 13)
                RefreshEntryList()
            end
        end)
        trinket1Btn:SetPoint("LEFT", slotLabel, "RIGHT", 10, 0)

        local trinket2Btn = GUI:CreateButton(slotBtnContainer, "Trinket 2", 90, 24, function()
            local trackerMod = QUICore and QUICore.CustomTrackers
            if trackerMod then
                trackerMod:AddEntry(barConfig.id, "slot", 14)
                RefreshEntryList()
            end
        end)
        trinket2Btn:SetPoint("LEFT", trinket1Btn, "RIGHT", 6, 0)

        -----------------------------------------------------------------------
        -- TRACKED ITEMS SECTION
        -----------------------------------------------------------------------
        local trackedHeader = GUI:CreateSectionHeader(tabContent, "Tracked Items And Spells")
        trackedHeader:SetPoint("TOPLEFT", slotBtnContainer, "BOTTOMLEFT", 0, -15)

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
        -- POSITION SECTION
        -----------------------------------------------------------------------
        local posHeader = GUI:CreateSectionHeader(lowerContainer, "Position")
        posHeader:SetPoint("TOPLEFT", 0, y)
        y = y - posHeader.gap

        local AnchorOpts = ns.QUI_Anchoring_Options
        if AnchorOpts and AnchorOpts.BuildAnchoringSection then
            y = AnchorOpts:BuildAnchoringSection(lowerContainer, "customTracker:" .. barConfig.id, {
                noHeader = true,
            }, y)
        else
            local posFallback = GUI:CreateLabel(lowerContainer, "Position controls are unavailable because the shared anchoring options module is missing.", 11, C.textMuted)
            posFallback:SetPoint("TOPLEFT", 0, y)
            posFallback:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
            posFallback:SetJustifyH("LEFT")
            posFallback:SetWordWrap(true)
            posFallback:SetHeight(30)
            y = y - 38
        end

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

        local clickableIconsCheck = GUI:CreateFormCheckbox(lowerContainer, "Clickable Icons", "clickableIcons", barConfig, RefreshThisBar)
        clickableIconsCheck:SetPoint("TOPLEFT", 0, y)
        clickableIconsCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local mutualExclusionDesc = GUI:CreateLabel(lowerContainer, "Clickable Icons and Dynamic Layout are mutually exclusive. Clickable icons use secure frames that prevent layout changes during combat.", 11, C.textMuted)
        mutualExclusionDesc:SetPoint("TOPLEFT", 0, y)
        mutualExclusionDesc:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        mutualExclusionDesc:SetJustifyH("LEFT")
        mutualExclusionDesc:SetWordWrap(true)
        mutualExclusionDesc:SetHeight(30)
        y = y - 40

        -- Mutual exclusion: clickableIcons and dynamicLayout cannot both be enabled
        -- Legacy migration: if both are enabled, dynamicLayout wins — force clickableIcons off
        if barConfig.dynamicLayout and barConfig.clickableIcons then
            barConfig.clickableIcons = false
            clickableIconsCheck.SetValue(false, true)
        end
        if clickableIconsCheck.SetEnabled then
            clickableIconsCheck:SetEnabled(not barConfig.dynamicLayout)
        end
        if dynamicLayoutCheck.SetEnabled then
            dynamicLayoutCheck:SetEnabled(not barConfig.clickableIcons)
        end
        if clickableIconsCheck.track then
            clickableIconsCheck.track:SetScript("OnClick", function()
                local newVal = not clickableIconsCheck.GetValue()
                clickableIconsCheck.SetValue(newVal, true)
                if newVal and dynamicLayoutCheck.SetEnabled then
                    dynamicLayoutCheck:SetEnabled(false)
                elseif dynamicLayoutCheck.SetEnabled then
                    dynamicLayoutCheck:SetEnabled(true)
                end
                RefreshThisBar()
            end)
        end
        if dynamicLayoutCheck.track then
            dynamicLayoutCheck.track:SetScript("OnClick", function()
                local newVal = not dynamicLayoutCheck.GetValue()
                dynamicLayoutCheck.SetValue(newVal, true)
                if newVal and clickableIconsCheck.SetEnabled then
                    clickableIconsCheck:SetEnabled(false)
                elseif clickableIconsCheck.SetEnabled then
                    clickableIconsCheck:SetEnabled(true)
                end
                RefreshThisBar()
            end)
        end

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

        local qualityCheck = GUI:CreateFormCheckbox(lowerContainer, "Show Crafted Item Quality", "showProfessionQuality", barConfig, RefreshThisBar)
        qualityCheck:SetPoint("TOPLEFT", 0, y)
        qualityCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
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

        local durFontList = GetFontList()
        local durFontDropdown = GUI:CreateFormDropdown(lowerContainer, "Font", durFontList, "durationFont", barConfig, RefreshThisBar)
        durFontDropdown:SetPoint("TOPLEFT", 0, y)
        durFontDropdown:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
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

        local stackFontList = GetFontList()
        local stackFontDropdown = GUI:CreateFormDropdown(lowerContainer, "Font", stackFontList, "stackFont", barConfig, RefreshThisBar)
        stackFontDropdown:SetPoint("TOPLEFT", 0, y)
        stackFontDropdown:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
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

        local noDesatWithChargesCheck  -- Forward declare
        noDesatWithChargesCheck = GUI:CreateFormCheckbox(lowerContainer, "Don't Desaturate With Charges", "noDesaturateWithCharges", barConfig, RefreshThisBar)
        noDesatWithChargesCheck:SetPoint("TOPLEFT", 15, y)  -- Indent to show it's a sub-option
        noDesatWithChargesCheck:SetPoint("RIGHT", lowerContainer, "RIGHT", -PAD, 0)
        -- Only enable when showOnlyOnCooldown is checked
        if noDesatWithChargesCheck.SetEnabled then
            noDesatWithChargesCheck:SetEnabled(barConfig.showOnlyOnCooldown == true)
        end
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
                -- Enable/disable sub-option
                if noDesatWithChargesCheck and noDesatWithChargesCheck.SetEnabled then
                    noDesatWithChargesCheck:SetEnabled(newVal)
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
                    -- Disable sub-option when switching away from showOnlyOnCooldown
                    if noDesatWithChargesCheck and noDesatWithChargesCheck.SetEnabled then
                        noDesatWithChargesCheck:SetEnabled(false)
                    end
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
                    -- Disable sub-option when switching away from showOnlyOnCooldown
                    if noDesatWithChargesCheck and noDesatWithChargesCheck.SetEnabled then
                        noDesatWithChargesCheck:SetEnabled(false)
                    end
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
    -- EXTRA PAGES
    ---------------------------------------------------------------------------
    local scannerSubTabIndex
    local importSubTabIndex

    local function BuildSpellScannerTab(tabContent)
        GUI:SetSearchContext({tabIndex = 11, tabName = "Custom Trackers", subTabIndex = scannerSubTabIndex, subTabName = "Setup Custom Buff Tracking"})
        local y = -4
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
            local step2 = GUI:CreateLabel(tabContent, "2. Add those spells/items to a Custom Tracker Bar", 11, C.text)
            step2:SetPoint("TOPLEFT", PAD, y)
            step2:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            step2:SetJustifyH("LEFT")
            y = y - 20

            -- Step 3
            local step3 = GUI:CreateLabel(tabContent, "3. The icons on your Custom Tracker Bars will now show accurate custom buff timers in combat", 11, C.text)
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
                        if self.SetFieldBackgroundColor then
                            self:SetFieldBackgroundColor(0.2, 0.6, 0.2, 1)
                        end
                    else
                        self.text:SetText("Enable")
                        if self.SetFieldBackgroundColor then
                            self:SetFieldBackgroundColor(C.bg[1], C.bg[2], C.bg[3], 1)
                        end
                    end
                end
            end)
            scanBtn:SetPoint("LEFT", 180, 0)
            -- Set initial state
            if scanner and scanner.scanMode then
                scanBtn.text:SetText("Disable")
                if scanBtn.SetFieldBackgroundColor then
                    scanBtn:SetFieldBackgroundColor(0.2, 0.6, 0.2, 1)
                end
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
                    local nameBg = CreateTrackerSurfaceFrame(entryFrame, 200, 22, {0.05, 0.05, 0.05, 0.4}, {0.25, 0.25, 0.25, 0.6})
                    nameBg:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)

                    local nameText = nameBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    nameText:SetPoint("LEFT", 6, 0)
                    nameText:SetPoint("RIGHT", -6, 0)
                    nameText:SetJustifyH("LEFT")
                    local displayName = data.name or (isItem and "Item " .. id or "Spell " .. id)
                    local durationStr = string.format("%.1fs", data.duration or 0)
                    nameText:SetText(displayName .. "  |cff888888" .. durationStr .. "|r")
                    nameText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

                    -- Delete button (X) - matches Tracked Items style
                    local removeBtn = CreateTrackerSurfaceButton(entryFrame, 22, 22, function()
                        if scannerDB then
                            if isItem then
                                scannerDB.items[id] = nil
                            else
                                scannerDB.spells[id] = nil
                            end
                            RefreshScannedList()
                        end
                    end, {
                        text = "X",
                        textColor = {C.accent[1], C.accent[2], C.accent[3], 1},
                        hoverTextColor = {C.accent[1], C.accent[2], C.accent[3], 1},
                        bgColor = {0.15, 0.15, 0.15, 1},
                        borderColor = {0.3, 0.3, 0.3, 1},
                        hoverBorderColor = {C.accent[1], C.accent[2], C.accent[3], 1},
                    })
                    removeBtn:SetPoint("LEFT", nameBg, "RIGHT", 6, 0)

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

            -- Import/Export section for learned spells
            local importExportHeader = GUI:CreateSectionHeader(lowerContainer, "Import / Export Learned Spells")
            importExportHeader:SetPoint("TOPLEFT", 0, -40)

            -- Export button
            local exportBtn = GUI:CreateButton(lowerContainer, "Export Learned Spells", 160, 24, function()
                local exportStr, err = QUICore:ExportSpellScanner()
                if not exportStr then
                    print("|cffff0000QUI:|r " .. (err or "Export failed"))
                    return
                end
                GUI:ShowExportPopup("Export Learned Spells", exportStr)
            end)
            exportBtn:SetPoint("TOPLEFT", 0, -40 - importExportHeader.gap)

            -- Import button
            local importBtn = GUI:CreateButton(lowerContainer, "Import Learned Spells", 160, 24, function()
                GUI:ShowImportPopup({
                    title = "Import Learned Spells",
                    hint = "Paste the export string below. 'Merge' adds to existing, 'Replace All' overwrites.",
                    hasMerge = true,
                    onImport = function(str)
                        return QUICore:ImportSpellScanner(str, false)  -- merge
                    end,
                    onReplace = function(str)
                        return QUICore:ImportSpellScanner(str, true)  -- replace
                    end,
                    onSuccess = function()
                        RefreshScannedList()
                        GUI:ShowConfirmation({
                            title = "Reload UI?",
                            message = "Learned spells imported. Reload UI to apply changes?",
                            acceptText = "Reload",
                            cancelText = "Later",
                            onAccept = function() QUI:SafeReload() end,
                        })
                    end,
                })
            end)
            importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)

            tabContent:SetHeight(550)
    end

    local function BuildImportExportTab(body)
        GUI:SetSearchContext({tabIndex = 11, tabName = "Custom Trackers", subTabIndex = importSubTabIndex, subTabName = "Import / Export Tracker Bars"})
        local desc = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("TOPLEFT", 4, -4)
        desc:SetPoint("RIGHT", body, "RIGHT", -4, 0)
        desc:SetTextColor(0.6, 0.6, 0.6, 0.8)
        desc:SetText("Per-bar settings are available above and in Layout Mode (/qui layout)")
        desc:SetJustifyH("LEFT")

        local exportAllBtn = GUI:CreateButton(body, "Export All Bars", 120, 24, function()
            local exportStr, err = QUICore:ExportAllTrackerBars()
            if not exportStr then print("|cffff0000QUI:|r " .. (err or "Export failed")); return end
            GUI:ShowExportPopup("Export All Tracker Bars", exportStr)
        end)
        exportAllBtn:SetPoint("TOPLEFT", 4, -24)

        local importBarsBtn = GUI:CreateButton(body, "Import Bars", 120, 24, function()
            GUI:ShowImportPopup({
                title = "Import Tracker Bars",
                hint = "Paste the export string below. 'Merge' adds to existing bars, 'Replace All' overwrites.",
                hasMerge = true,
                onImport = function(str) return QUICore:ImportAllTrackerBars(str, false) end,
                onReplace = function(str) return QUICore:ImportAllTrackerBars(str, true) end,
                onSuccess = function()
                    GUI:ShowConfirmation({
                        title = "Reload UI?", message = "Tracker bars imported. Reload UI to see changes?",
                        acceptText = "Reload", cancelText = "Later",
                        onAccept = function() QUI:SafeReload() end,
                    })
                end,
            })
        end)
        importBarsBtn:SetPoint("LEFT", exportAllBtn, "RIGHT", 8, 0)

        local importSingleBtn = GUI:CreateButton(body, "Import Single Bar", 120, 24, function()
            GUI:ShowImportPopup({
                title = "Import Single Tracker Bar",
                hint = "Paste a single bar export string below",
                hasMerge = false,
                onImport = function(str) return QUICore:ImportSingleTrackerBar(str) end,
                onSuccess = function()
                    GUI:ShowConfirmation({
                        title = "Reload UI?", message = "Tracker bar imported. Reload UI to see changes?",
                        acceptText = "Reload", cancelText = "Later",
                        onAccept = function() QUI:SafeReload() end,
                    })
                end,
            })
        end)
        importSingleBtn:SetPoint("LEFT", importBarsBtn, "RIGHT", 8, 0)
        body:SetHeight(100)
    end

    ---------------------------------------------------------------------------
    -- Build sub-tabs dynamically from bars
    ---------------------------------------------------------------------------
    local actionsRow = CreateFrame("Frame", nil, content)
    actionsRow:SetHeight(ACTION_ROW_HEIGHT)
    actionsRow:SetPoint("TOPLEFT", PAD, -10)
    actionsRow:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local addTrackerBtn = GUI:CreateButton(actionsRow, "Add Tracker", 120, 24, function()
        local trackerModule = QUICore and QUICore.CustomTrackers
        if not trackerModule or not trackerModule.CreateNewBar then
            print("|cffff0000QUI:|r Custom tracker creation is unavailable right now.")
            return
        end

        local _, newIndex, err = trackerModule:CreateNewBar()
        if newIndex then
            RebuildCustomTrackersPage(newIndex)
        elseif err then
            print("|cffff0000QUI:|r " .. err)
        end
    end)
    addTrackerBtn:SetPoint("TOPRIGHT", actionsRow, "TOPRIGHT", 0, -2)

    local actionHint = GUI:CreateLabel(actionsRow, "Create and edit tracker bars here. Spell Scanner and import/export each have their own pages.", 11, C.textMuted)
    actionHint:SetPoint("LEFT", 0, 0)
    actionHint:SetPoint("RIGHT", addTrackerBtn, "LEFT", -10, 0)
    actionHint:SetJustifyH("LEFT")

    local subTabHost = CreateFrame("Frame", nil, content)
    subTabHost:SetPoint("TOPLEFT", actionsRow, "BOTTOMLEFT", 0, -12)
    subTabHost:SetPoint("BOTTOMRIGHT", 0, 0)

    local subTabsRef = {}
    local trackerTabs = {}

    for barIndex, barConfig in ipairs(bars) do
        local displayName = barConfig.name or ("Tracker " .. barIndex)
        if #displayName > 20 then
            displayName = displayName:sub(1, 17) .. "..."
        end

        table.insert(trackerTabs, {
            name = displayName,
            builder = function(tabContent)
                BuildTrackerBarTab(tabContent, barConfig, barIndex, subTabsRef, RebuildCustomTrackersPage)
            end,
        })
    end

    scannerSubTabIndex = #trackerTabs + 1
    table.insert(trackerTabs, {
        name = "Setup Custom Buff Tracking",
        builder = BuildSpellScannerTab,
    })

    importSubTabIndex = #trackerTabs + 1
    table.insert(trackerTabs, {
        name = "Import / Export",
        builder = BuildImportExportTab,
    })

    local trackerSubTabs = GUI:CreateSubTabs(subTabHost, trackerTabs)
    subTabsRef.tabButtons = trackerSubTabs.tabButtons
    subTabsRef.tabContents = trackerSubTabs.tabContents
    subTabsRef.subTabDefs = trackerSubTabs.subTabDefs
    subTabsRef.SelectTab = trackerSubTabs.SelectTab

    content:SetHeight(PAGE_HEIGHT)
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_CustomTrackersOptions = {
    CreateCustomTrackersPage = CreateCustomTrackersPage
}
