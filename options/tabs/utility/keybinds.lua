--[[
    QUI Options - CDM Keybind & Rotation Sub-Tab
    BuildKeybindsTab for Cooldown Manager > Keybinds sub-tab
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local ANCHOR_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "CENTER", text = "Center" },
}

local function BuildKeybindsTab(tabContent)
    local db = Shared.GetDB()
    local y = -10
    local FORM_ROW = 32
    local PAD = 10

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 7, subTabName = "Keybinds"})

    -- Refresh function for keybinds
    local function RefreshKeybinds()
        if _G.QUI_RefreshKeybinds then
            _G.QUI_RefreshKeybinds()
        end
    end

    -- Info text at top
    local info = GUI:CreateLabel(tabContent, "Keybind display - shows ability keybinds on cooldown icons", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    if db and db.viewers then
        local essentialViewer = db.viewers.EssentialCooldownViewer
        local utilityViewer = db.viewers.UtilityCooldownViewer

        -- =====================================================
        -- ESSENTIAL KEYBIND DISPLAY
        -- =====================================================
        local essentialHeader = GUI:CreateSectionHeader(tabContent, "ESSENTIAL KEYBIND DISPLAY")
        essentialHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - essentialHeader.gap

        local essentialShowCheck = GUI:CreateFormCheckbox(tabContent, "Show Keybinds", "showKeybinds", essentialViewer, RefreshKeybinds)
        essentialShowCheck:SetPoint("TOPLEFT", PAD, y)
        essentialShowCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialAnchor = GUI:CreateFormDropdown(tabContent, "Keybind Anchor", ANCHOR_OPTIONS, "keybindAnchor", essentialViewer, RefreshKeybinds)
        essentialAnchor:SetPoint("TOPLEFT", PAD, y)
        essentialAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialSizeSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Size", 6, 18, 1, "keybindTextSize", essentialViewer, RefreshKeybinds)
        essentialSizeSlider:SetPoint("TOPLEFT", PAD, y)
        essentialSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialColorPicker = GUI:CreateFormColorPicker(tabContent, "Keybind Text Color", "keybindTextColor", essentialViewer, RefreshKeybinds)
        essentialColorPicker:SetPoint("TOPLEFT", PAD, y)
        essentialColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialOffsetXSlider = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", essentialViewer, RefreshKeybinds)
        essentialOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        essentialOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialOffsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -20, 20, 1, "keybindOffsetY", essentialViewer, RefreshKeybinds)
        essentialOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        essentialOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- UTILITY KEYBIND DISPLAY
        -- =====================================================
        y = y - 10 -- Section spacing
        local utilityHeader = GUI:CreateSectionHeader(tabContent, "UTILITY KEYBIND DISPLAY")
        utilityHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - utilityHeader.gap

        local utilityShowCheck = GUI:CreateFormCheckbox(tabContent, "Show Keybinds", "showKeybinds", utilityViewer, RefreshKeybinds)
        utilityShowCheck:SetPoint("TOPLEFT", PAD, y)
        utilityShowCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityAnchor = GUI:CreateFormDropdown(tabContent, "Keybind Anchor", ANCHOR_OPTIONS, "keybindAnchor", utilityViewer, RefreshKeybinds)
        utilityAnchor:SetPoint("TOPLEFT", PAD, y)
        utilityAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilitySizeSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Size", 6, 18, 1, "keybindTextSize", utilityViewer, RefreshKeybinds)
        utilitySizeSlider:SetPoint("TOPLEFT", PAD, y)
        utilitySizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityColorPicker = GUI:CreateFormColorPicker(tabContent, "Keybind Text Color", "keybindTextColor", utilityViewer, RefreshKeybinds)
        utilityColorPicker:SetPoint("TOPLEFT", PAD, y)
        utilityColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityOffsetXSlider = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", utilityViewer, RefreshKeybinds)
        utilityOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        utilityOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityOffsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -20, 20, 1, "keybindOffsetY", utilityViewer, RefreshKeybinds)
        utilityOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        utilityOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- CUSTOM TRACKER KEYBIND DISPLAYS
        -- =====================================================
        y = y - 10 -- Section spacing
        local ctKeybindHeader = GUI:CreateSectionHeader(tabContent, "CUSTOM TRACKER KEYBIND DISPLAYS")
        ctKeybindHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - ctKeybindHeader.gap

        local ctKeybindInfo = GUI:CreateLabel(tabContent, "Shows keybinds on Custom Item/Spell bar icons. Settings apply globally to all custom tracker bars.", 11, C.textMuted)
        ctKeybindInfo:SetPoint("TOPLEFT", PAD, y)
        ctKeybindInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        ctKeybindInfo:SetJustifyH("LEFT")
        y = y - 28

        -- Get custom tracker keybind settings from DB
        local ctKeybindDB = db and db.customTrackers and db.customTrackers.keybinds
        if not ctKeybindDB and db and db.customTrackers then
            -- Initialize defaults if missing
            db.customTrackers.keybinds = {
                showKeybinds = false,
                keybindTextSize = 10,
                keybindTextColor = { 1, 0.82, 0, 1 },
                keybindOffsetX = 2,
                keybindOffsetY = -2,
            }
            ctKeybindDB = db.customTrackers.keybinds
        end

        -- Refresh function for custom tracker keybinds
        local function RefreshCustomTrackerKeybinds()
            if _G.QUI_RefreshCustomTrackerKeybinds then
                _G.QUI_RefreshCustomTrackerKeybinds()
            end
        end

        if ctKeybindDB then
            local ctShowCheck = GUI:CreateFormCheckbox(tabContent, "Show Keybinds", "showKeybinds", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctShowCheck:SetPoint("TOPLEFT", PAD, y)
            ctShowCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctSizeSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Size", 6, 18, 1, "keybindTextSize", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctSizeSlider:SetPoint("TOPLEFT", PAD, y)
            ctSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctColorPicker = GUI:CreateFormColorPicker(tabContent, "Keybind Text Color", "keybindTextColor", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctColorPicker:SetPoint("TOPLEFT", PAD, y)
            ctColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctOffsetXSlider = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
            ctOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctOffsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -20, 20, 1, "keybindOffsetY", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
            ctOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- =====================================================
        -- CDM KEYBIND OVERRIDES (SPELL ID → CUSTOM TEXT)
        -- =====================================================
        y = y - 10 -- Section spacing
        local overrideHeader = GUI:CreateSectionHeader(tabContent, "CDM KEYBIND OVERRIDES")
        overrideHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - overrideHeader.gap

        local overrideInfo = GUI:CreateLabel(tabContent, "Override the auto-detected keybind for specific spells and items. Drag spells from your spellbook or items from your bags into the box below.", 11, C.textMuted)
        overrideInfo:SetPoint("TOPLEFT", PAD, y)
        overrideInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        overrideInfo:SetJustifyH("LEFT")
        y = y - 32

        -- Get shared overrides from DB
        local QUICore = _G.QUI and _G.QUI.QUICore
        if not QUICore or not QUICore.db or not QUICore.db.profile then
            local noDataLabel = GUI:CreateLabel(tabContent, "Database not available", 12, C.textMuted)
            noDataLabel:SetPoint("TOPLEFT", PAD, y)
            y = y - 24
        else
            -- Initialize if needed
            if not QUICore.db.profile.keybindOverrides then
                QUICore.db.profile.keybindOverrides = {}
            end

            -- Helper function to save/update override
            -- If keybindText is nil, it means "remove override" (user clicked X)
            -- If keybindText is a string (even empty ""), it means "set this binding"
            local function SaveOverride(spellID, keybindText)
                if not spellID or spellID <= 0 then return false end
                
                local saved = false
                local shouldRemove = (keybindText == nil)
                
                if _G.QUI_SetKeybindOverride then
                    -- Pass nil to remove, or the text (even if empty string) to set
                    _G.QUI_SetKeybindOverride("EssentialCooldownViewer", spellID, keybindText)
                    saved = true
                elseif QUI and QUI.Keybinds and QUI.Keybinds.SetOverride then
                    QUI.Keybinds.SetOverride("EssentialCooldownViewer", spellID, keybindText)
                    saved = true
                else
                    -- Direct DB access fallback
                    QUICore.db.profile.keybindOverrides = QUICore.db.profile.keybindOverrides or {}
                    if shouldRemove then
                        QUICore.db.profile.keybindOverrides[spellID] = nil
                    else
                        -- Store the text (even if empty string - this allows new entries to show in list)
                        QUICore.db.profile.keybindOverrides[spellID] = keybindText
                    end
                    saved = true
                    if _G.QUI_RefreshKeybinds then
                        _G.QUI_RefreshKeybinds()
                    end
                end
                return saved
            end

            -- Entry list frame (will be created below)
            local entryListFrame = nil
            local entryFrames = {} -- Track created frames for proper cleanup

            -- Function to refresh override list
            local function RefreshOverrideList()
                if not entryListFrame then return end
                
                -- Clear existing children properly
                for i, frame in ipairs(entryFrames) do
                    if frame and frame:IsShown() then
                        frame:Hide()
                    end
                    if frame then
                        frame:SetParent(nil)
                    end
                end
                wipe(entryFrames)

                local overrides = QUICore.db.profile.keybindOverrides
                if not overrides then return end

                -- Convert to sorted array for display (show ALL spells and items in overrides table, even with empty binding)
                -- Items use negative keys, spells use positive keys
                local entries = {}
                for key, keybindText in pairs(overrides) do
                    local entryType = (key < 0) and "item" or "spell"
                    local id = (key < 0) and -key or key
                    table.insert(entries, {key = key, id = id, type = entryType, keybindText = keybindText or ""})
                end
                -- Sort: items first (negative keys), then spells (positive keys)
                table.sort(entries, function(a, b)
                    if a.type ~= b.type then
                        return a.type == "item" -- Items first
                    end
                    return a.id < b.id
                end)

                local listY = 0
                for i, entry in ipairs(entries) do
                    local entryFrame = CreateFrame("Frame", nil, entryListFrame)
                    entryFrame:SetSize(400, 28)
                    entryFrame:SetPoint("TOPLEFT", 0, listY)
                    entryFrame:Show() -- Ensure frame is visible
                    table.insert(entryFrames, entryFrame) -- Track for cleanup

                    -- Icon
                    local iconTex = entryFrame:CreateTexture(nil, "ARTWORK")
                    iconTex:SetSize(24, 24)
                    iconTex:SetPoint("LEFT", 0, 0)
                    local displayName = ""
                    local iconID = nil
                    
                    if entry.type == "spell" then
                        local spellInfo = C_Spell.GetSpellInfo(entry.id)
                        iconID = spellInfo and spellInfo.iconID
                        displayName = spellInfo and spellInfo.name or ("Spell " .. tostring(entry.id))
                    else -- item
                        -- C_Item.GetItemInfo returns multiple values, not an object
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(entry.id)
                        if itemName then
                            iconID = itemIcon
                            displayName = itemName
                        else
                            -- Item not cached yet, request it
                            C_Item.RequestLoadItemDataByID(entry.id)
                            iconID = nil
                            displayName = "Item " .. tostring(entry.id)
                        end
                    end
                    
                    iconTex:SetTexture(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                    -- Name and ID label (shows both name and ID, with type prefix)
                    local nameLabel = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    nameLabel:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                    local typePrefix = (entry.type == "item") and "Item" or "Spell"
                    nameLabel:SetText(string.format("%s: %s (%d)", typePrefix, displayName, entry.id))
                    nameLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                    nameLabel:SetWidth(200)

                    -- Keybind text input box
                    local keybindInputBg = CreateFrame("Frame", nil, entryFrame, "BackdropTemplate")
                    keybindInputBg:SetPoint("LEFT", nameLabel, "RIGHT", 6, 0)
                    keybindInputBg:SetSize(100, 22)
                    keybindInputBg:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    keybindInputBg:SetBackdropColor(0.05, 0.05, 0.05, 0.4)
                    keybindInputBg:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

                    local keybindInput = CreateFrame("EditBox", nil, keybindInputBg)
                    keybindInput:SetPoint("LEFT", 6, 0)
                    keybindInput:SetPoint("RIGHT", -6, 0)
                    keybindInput:SetHeight(20)
                    keybindInput:SetAutoFocus(false)
                    keybindInput:SetFont(GUI.FONT_PATH, 11, "")
                    keybindInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                    keybindInput:SetText(entry.keybindText or "")
                    keybindInput:SetCursorPosition(0)
                    keybindInput.entryKey = entry.key -- Store the key (positive for spells, negative for items)
                    keybindInput.entryType = entry.type
                    keybindInput.entryID = entry.id

                    keybindInput:SetScript("OnEscapePressed", function(self)
                        self:SetText(entry.keybindText or "")
                        self:ClearFocus()
                    end)

                    keybindInput:SetScript("OnEditFocusGained", function(self)
                        keybindInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                        self:HighlightText()
                    end)
                    keybindInput:SetScript("OnEditFocusLost", function(self)
                        keybindInputBg:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
                    end)

                    -- Save button for this entry
                    local saveBtn = GUI:CreateButton(entryFrame, "Save", 50, 22, function()
                        local newKeybindText = keybindInput:GetText() or ""
                        local saved = false
                        if entry.type == "spell" then
                            saved = SaveOverride(entry.id, newKeybindText)
                        else -- item
                            if _G.QUI_SetKeybindOverrideForItem then
                                _G.QUI_SetKeybindOverrideForItem(entry.id, newKeybindText)
                                saved = true
                            elseif QUI and QUI.Keybinds and QUI.Keybinds.SetOverrideForItem then
                                QUI.Keybinds.SetOverrideForItem(entry.id, newKeybindText)
                                saved = true
                            else
                                -- Direct DB access fallback
                                QUICore.db.profile.keybindOverrides = QUICore.db.profile.keybindOverrides or {}
                                if newKeybindText == "" or not newKeybindText then
                                    QUICore.db.profile.keybindOverrides[-entry.id] = nil
                                else
                                    QUICore.db.profile.keybindOverrides[-entry.id] = newKeybindText
                                end
                                saved = true
                                if _G.QUI_RefreshCustomTrackerKeybinds then
                                    _G.QUI_RefreshCustomTrackerKeybinds()
                                end
                            end
                        end
                        if saved then
                            entry.keybindText = newKeybindText
                            keybindInput:ClearFocus()
                            RefreshOverrideList()
                        end
                    end)
                    saveBtn:SetPoint("LEFT", keybindInputBg, "RIGHT", 6, 0)

                    -- Remove button (X)
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
                        -- Pass nil to explicitly remove the override
                        local removed = false
                        if entry.type == "spell" then
                            removed = SaveOverride(entry.id, nil)
                        else -- item
                            if _G.QUI_SetKeybindOverrideForItem then
                                _G.QUI_SetKeybindOverrideForItem(entry.id, nil)
                                removed = true
                            elseif QUI and QUI.Keybinds and QUI.Keybinds.SetOverrideForItem then
                                QUI.Keybinds.SetOverrideForItem(entry.id, nil)
                                removed = true
                            else
                                -- Direct DB access fallback
                                QUICore.db.profile.keybindOverrides = QUICore.db.profile.keybindOverrides or {}
                                QUICore.db.profile.keybindOverrides[-entry.id] = nil
                                removed = true
                                if _G.QUI_RefreshCustomTrackerKeybinds then
                                    _G.QUI_RefreshCustomTrackerKeybinds()
                                end
                            end
                        end
                        if removed then
                            RefreshOverrideList()
                        end
                    end)
                    removeBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)

                    listY = listY - 30
                end

                -- Update entry list frame height and ensure it's visible
                local listHeight = math.max(20, math.abs(listY))
                entryListFrame:SetHeight(listHeight)
                entryListFrame:Show()
            end

            -- Helper: Create drop zone for adding spells via drag-and-drop
            local function CreateDropZone(parentFrame, refreshCallback)
                local container = CreateFrame("Frame", nil, parentFrame)
                container:SetHeight(68)

                local dropZone = CreateFrame("Button", nil, container, "BackdropTemplate")
                dropZone:SetHeight(68)
                dropZone:SetPoint("TOPLEFT", 0, 0)
                dropZone:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                dropZone:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                dropZone:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.8)
                dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
                
                -- Enable receiving drags
                dropZone:RegisterForDrag("LeftButton")
                dropZone:EnableMouse(true)

                local dropLabel = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dropLabel:SetPoint("CENTER", 0, 0)
                dropLabel:SetText("Drop Spells or Items here")
                dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

                -- Helper function to handle spell/item drop
                local function HandleDrop()
                    local cursorType, id1, id2, id3, id4 = GetCursorInfo()
                    
                    if cursorType == "spell" then
                        local slotIndex = id1
                        local bookType = id2 or "spell"
                        local spellID = id4

                        if not spellID and slotIndex then
                            local spellBank = (bookType == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                            local spellBookInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                            if spellBookInfo then
                                spellID = spellBookInfo.spellID
                            end
                        end

                        if spellID then
                            local overrideID = C_Spell.GetOverrideSpell(spellID)
                            if overrideID and overrideID ~= spellID then
                                spellID = overrideID
                            end
                            
                            -- Add to overrides (with empty keybind text initially - store directly to show in list)
                            QUICore.db.profile.keybindOverrides = QUICore.db.profile.keybindOverrides or {}
                            QUICore.db.profile.keybindOverrides[spellID] = ""
                            ClearCursor()
                            
                            -- Refresh the list immediately
                            if refreshCallback then
                                refreshCallback()
                            end
                            
                            -- Also trigger keybind refresh
                            if _G.QUI_RefreshKeybinds then
                                _G.QUI_RefreshKeybinds()
                            end
                        end
                    elseif cursorType == "item" then
                        local itemID = id1
                        if itemID then
                            -- Add to overrides using negative itemID as key
                            QUICore.db.profile.keybindOverrides = QUICore.db.profile.keybindOverrides or {}
                            QUICore.db.profile.keybindOverrides[-itemID] = ""
                            ClearCursor()
                            
                            -- Refresh the list immediately
                            if refreshCallback then
                                refreshCallback()
                            end
                            
                            -- Also trigger custom tracker keybind refresh
                            if _G.QUI_RefreshCustomTrackerKeybinds then
                                _G.QUI_RefreshCustomTrackerKeybinds()
                            end
                        end
                    end
                end

                -- Handle drop on mouse release
                dropZone:SetScript("OnReceiveDrag", function(self)
                    HandleDrop()
                end)
                
                -- Also handle OnMouseUp as fallback (some drag modes use this)
                dropZone:SetScript("OnMouseUp", function(self)
                    local cursorType = GetCursorInfo()
                    if cursorType == "spell" or cursorType == "item" then
                        HandleDrop()
                    end
                end)
                
                -- Highlight on hover when cursor has spell or item
                dropZone:SetScript("OnEnter", function(self)
                    local cursorType = GetCursorInfo()
                    if cursorType == "spell" or cursorType == "item" then
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

            -- Create drop zone
            local dropSection = CreateDropZone(tabContent, RefreshOverrideList)
            dropSection:SetPoint("TOPLEFT", overrideInfo, "BOTTOMLEFT", 0, -10)
            dropSection:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - 90

            -- Overridden Keybind Spells section
            local trackedHeader = GUI:CreateSectionHeader(tabContent, "Overridden Keybind Spells")
            trackedHeader:SetPoint("TOPLEFT", dropSection, "BOTTOMLEFT", 0, -15)

            -- Entry list container
            entryListFrame = CreateFrame("Frame", nil, tabContent)
            entryListFrame:SetPoint("TOPLEFT", trackedHeader, "BOTTOMLEFT", 0, -8)
            entryListFrame:SetSize(400, 20)
            
            -- Listen for item info loading to refresh the list
            local itemInfoListener = CreateFrame("Frame")
            itemInfoListener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            itemInfoListener:SetScript("OnEvent", function(self, event, itemID)
                if event == "GET_ITEM_INFO_RECEIVED" and itemID then
                    -- Check if this item is in our overrides list
                    local overrides = QUICore.db.profile.keybindOverrides
                    if overrides and overrides[-itemID] then
                        -- Refresh the list to update the item name/icon
                        C_Timer.After(0.1, function()
                            RefreshOverrideList()
                        end)
                    end
                end
            end)
            
            RefreshOverrideList()

            y = y - 50 -- Space for header and initial list
        end

    else
        y = y - 10
        local noDataLabel = GUI:CreateLabel(tabContent, "Keybind settings not available - database not loaded", 12, C.textMuted)
        noDataLabel:SetPoint("TOPLEFT", PAD, y)
    end

    tabContent:SetHeight(math.abs(y) + 60)
end

local function BuildRotationAssistTab(tabContent)
    local db = Shared.GetDB()
    local y = -10
    local FORM_ROW = 32
    local PAD = 10

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 8, subTabName = "Rotation Assist"})

    -- Refresh function for rotation helper
    local function RefreshRotationHelper()
        if _G.QUI_RefreshRotationHelper then
            _G.QUI_RefreshRotationHelper()
        end
    end

    if db and db.viewers then
        local essentialViewer = db.viewers.EssentialCooldownViewer
        local utilityViewer = db.viewers.UtilityCooldownViewer

        -- =====================================================
        -- ROTATION HELPER OVERLAY
        -- =====================================================
        local rotationHeader = GUI:CreateSectionHeader(tabContent, "ROTATION HELPER OVERLAY")
        rotationHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - rotationHeader.gap

        local rotationInfo = GUI:CreateLabel(tabContent, "Shows a border on the CDM icon recommended by Blizzard's Assisted Combat (Starter Build). Requires 'Starter Build' to be enabled in Game Menu > Options > Gameplay > Combat.", 11, C.textMuted)
        rotationInfo:SetPoint("TOPLEFT", PAD, y)
        rotationInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        rotationInfo:SetJustifyH("LEFT")
        y = y - 38

        local essentialRotationCheck = GUI:CreateFormCheckbox(tabContent, "Show on Essential CDM", "showRotationHelper", essentialViewer, RefreshRotationHelper)
        essentialRotationCheck:SetPoint("TOPLEFT", PAD, y)
        essentialRotationCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityRotationCheck = GUI:CreateFormCheckbox(tabContent, "Show on Utility CDM", "showRotationHelper", utilityViewer, RefreshRotationHelper)
        utilityRotationCheck:SetPoint("TOPLEFT", PAD, y)
        utilityRotationCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialRotationColor = GUI:CreateFormColorPicker(tabContent, "Essential Border Color", "rotationHelperColor", essentialViewer, RefreshRotationHelper)
        essentialRotationColor:SetPoint("TOPLEFT", PAD, y)
        essentialRotationColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityRotationColor = GUI:CreateFormColorPicker(tabContent, "Utility Border Color", "rotationHelperColor", utilityViewer, RefreshRotationHelper)
        utilityRotationColor:SetPoint("TOPLEFT", PAD, y)
        utilityRotationColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialThicknessSlider = GUI:CreateFormSlider(tabContent, "Essential Border Thickness", 1, 6, 1, "rotationHelperThickness", essentialViewer, RefreshRotationHelper)
        essentialThicknessSlider:SetPoint("TOPLEFT", PAD, y)
        essentialThicknessSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityThicknessSlider = GUI:CreateFormSlider(tabContent, "Utility Border Thickness", 1, 6, 1, "rotationHelperThickness", utilityViewer, RefreshRotationHelper)
        utilityThicknessSlider:SetPoint("TOPLEFT", PAD, y)
        utilityThicknessSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- ROTATION ASSIST ICON
        -- =====================================================
        y = y - 10 -- Extra spacing
        local raiHeader = GUI:CreateSectionHeader(tabContent, "ROTATION ASSIST ICON")
        raiHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - raiHeader.gap

        -- Get rotation assist icon DB
        local raiDB = db and db.rotationAssistIcon
        if not raiDB and db then
            -- Initialize defaults if missing
            db.rotationAssistIcon = {
                enabled = false,
                isLocked = true,
                iconSize = 56,
                visibility = "always",  -- "always", "combat", "hostile"
                frameStrata = "MEDIUM",
                -- Border
                showBorder = true,
                borderThickness = 2,
                borderColor = { 0, 0, 0, 1 },
                -- Cooldown
                cooldownSwipeEnabled = true,
                -- Keybind
                showKeybind = true,
                keybindFont = nil,  -- nil = use general.font
                keybindSize = 13,
                keybindColor = { 1, 1, 1, 1 },
                keybindOutline = true,
                keybindAnchor = "BOTTOMRIGHT",
                keybindOffsetX = -2,
                keybindOffsetY = 2,
                -- Position (anchored to CENTER of screen)
                positionX = 0,
                positionY = -180,
            }
            raiDB = db.rotationAssistIcon
        end

        -- Refresh function
        local function RefreshRAI()
            if _G.QUI_RefreshRotationAssistIcon then
                _G.QUI_RefreshRotationAssistIcon()
            end
        end

        -- Info text
        local raiInfo = GUI:CreateLabel(tabContent, "Displays a standalone movable icon showing Blizzard's next recommended ability.", 11, C.textMuted)
        raiInfo:SetPoint("TOPLEFT", PAD, y)
        y = y - 18

        local raiInfo2 = GUI:CreateLabel(tabContent, "Requires 'Starter Build' to be enabled in Game Menu > Options > Gameplay > Combat.", 11, C.textMuted)
        raiInfo2:SetPoint("TOPLEFT", PAD, y)
        y = y - 30

        -- Form rows
        local raiEnable = GUI:CreateFormCheckbox(tabContent, "Enable", "enabled", raiDB, RefreshRAI)
        raiEnable:SetPoint("TOPLEFT", PAD, y)
        raiEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiLock = GUI:CreateFormCheckbox(tabContent, "Lock Position", "isLocked", raiDB, RefreshRAI)
        raiLock:SetPoint("TOPLEFT", PAD, y)
        raiLock:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiSwipe = GUI:CreateFormCheckbox(tabContent, "Cooldown Swipe", "cooldownSwipeEnabled", raiDB, RefreshRAI)
        raiSwipe:SetPoint("TOPLEFT", PAD, y)
        raiSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local visibilityOptions = {
            { value = "always", text = "Always" },
            { value = "combat", text = "In Combat" },
            { value = "hostile", text = "Hostile Target" },
        }
        local raiVisibility = GUI:CreateFormDropdown(tabContent, "Visibility", visibilityOptions, "visibility", raiDB, RefreshRAI)
        raiVisibility:SetPoint("TOPLEFT", PAD, y)
        raiVisibility:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local strataOptions = {
            { value = "LOW", text = "Low" },
            { value = "MEDIUM", text = "Medium" },
            { value = "HIGH", text = "High" },
            { value = "DIALOG", text = "Dialog" },
        }
        local raiStrata = GUI:CreateFormDropdown(tabContent, "Frame Strata", strataOptions, "frameStrata", raiDB, RefreshRAI)
        raiStrata:SetPoint("TOPLEFT", PAD, y)
        raiStrata:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiSize = GUI:CreateFormSlider(tabContent, "Icon Size", 16, 400, 1, "iconSize", raiDB, RefreshRAI)
        raiSize:SetPoint("TOPLEFT", PAD, y)
        raiSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiBorderWidth = GUI:CreateFormSlider(tabContent, "Border Size", 0, 15, 1, "borderThickness", raiDB, RefreshRAI)
        raiBorderWidth:SetPoint("TOPLEFT", PAD, y)
        raiBorderWidth:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiBorderColor = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColor", raiDB, RefreshRAI)
        raiBorderColor:SetPoint("TOPLEFT", PAD, y)
        raiBorderColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiKeybindShow = GUI:CreateFormCheckbox(tabContent, "Show Keybind", "showKeybind", raiDB, RefreshRAI)
        raiKeybindShow:SetPoint("TOPLEFT", PAD, y)
        raiKeybindShow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiFontColor = GUI:CreateFormColorPicker(tabContent, "Keybind Color", "keybindColor", raiDB, RefreshRAI)
        raiFontColor:SetPoint("TOPLEFT", PAD, y)
        raiFontColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiAnchor = GUI:CreateFormDropdown(tabContent, "Keybind Anchor", ANCHOR_OPTIONS, "keybindAnchor", raiDB, RefreshRAI)
        raiAnchor:SetPoint("TOPLEFT", PAD, y)
        raiAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiFontSize = GUI:CreateFormSlider(tabContent, "Keybind Size", 6, 48, 1, "keybindSize", raiDB, RefreshRAI)
        raiFontSize:SetPoint("TOPLEFT", PAD, y)
        raiFontSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiOffsetX = GUI:CreateFormSlider(tabContent, "Keybind X Offset", -50, 50, 1, "keybindOffsetX", raiDB, RefreshRAI)
        raiOffsetX:SetPoint("TOPLEFT", PAD, y)
        raiOffsetX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiOffsetY = GUI:CreateFormSlider(tabContent, "Keybind Y Offset", -50, 50, 1, "keybindOffsetY", raiDB, RefreshRAI)
        raiOffsetY:SetPoint("TOPLEFT", PAD, y)
        raiOffsetY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    else
        y = y - 10
        local noDataLabel = GUI:CreateLabel(tabContent, "Rotation assist settings not available - database not loaded", 12, C.textMuted)
        noDataLabel:SetPoint("TOPLEFT", PAD, y)
    end

    tabContent:SetHeight(math.abs(y) + 60)
end

-- Export
ns.QUI_KeybindsOptions = {
    BuildKeybindsTab = BuildKeybindsTab,
    BuildRotationAssistTab = BuildRotationAssistTab,
}
