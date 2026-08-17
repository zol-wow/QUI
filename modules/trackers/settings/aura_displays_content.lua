local _, ns = ...
local QUI = QUI
local GUI = QUI and QUI.GUI
local C = (GUI and GUI.Colors) or {}
local Shared = ns.QUI_Options

local PAD = (Shared and Shared.PADDING) or 15

local AD = ns.QUI_AuraDisplays
local E = ns.AuraElements

local UNIT_OPTIONS = {
    { value = "player", text = ns.L["Player"] },
    { value = "pet", text = ns.L["Pet"] },
    { value = "target", text = ns.L["Target"] },
    { value = "targettarget", text = ns.L["Target of Target"] },
    { value = "focus", text = ns.L["Focus"] },
    { value = "focustarget", text = ns.L["Focus Target"] },
    { value = "mouseover", text = ns.L["Mouseover"] },
    { value = "boss1", text = ns.L["Boss 1"] },
    { value = "boss2", text = ns.L["Boss 2"] },
    { value = "boss3", text = ns.L["Boss 3"] },
    { value = "boss4", text = ns.L["Boss 4"] },
    { value = "boss5", text = ns.L["Boss 5"] },
    { value = "party1", text = ns.L["Party 1"] },
    { value = "party2", text = ns.L["Party 2"] },
    { value = "party3", text = ns.L["Party 3"] },
    { value = "party4", text = ns.L["Party 4"] },
    { value = "arena1", text = ns.L["Arena 1"] },
    { value = "arena2", text = ns.L["Arena 2"] },
    { value = "arena3", text = ns.L["Arena 3"] },
    { value = "arena4", text = ns.L["Arena 4"] },
    { value = "arena5", text = ns.L["Arena 5"] },
    { value = "__cotank", text = ns.L["Co-Tank"] },
    { value = "__name", text = ns.L["Specific player..."] },
}

local DISPLAY_DIRECTION_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "RIGHT", text = ns.L["Right"] },
    { value = "UP", text = ns.L["Up"] },
    { value = "DOWN", text = ns.L["Down"] },
}

local DISPLAY_ALIGNMENT_OPTIONS = {
    { value = "START", text = ns.L["Start"] },
    { value = "CENTER", text = ns.L["Center"] },
    { value = "END", text = ns.L["End"] },
}

local VISIBILITY_OPTIONS = {
    { value = "active", text = ns.L["Active Only"] },
    { value = "instance", text = ns.L["Show In Instance"] },
    { value = "always", text = ns.L["Always"] },
}

local BUILTIN_ALERT_SOUND = "Sound\\Interface\\RaidWarning.ogg"

local function AlertSoundOptions()
    local options = Shared.GetSoundList()
    for i = 1, #options do
        if options[i].value == BUILTIN_ALERT_SOUND then return options end
    end
    options[#options + 1] = { value = BUILTIN_ALERT_SOUND, text = ns.L["Raid Warning"] }
    return options
end

ns.QUI_AuraDisplaysOptions = {}

local function Fold(text)
    if type(text) ~= "string" then return "" end
    local H = ns.Helpers
    if H and type(H.FoldUTF8) == "function" then return H.FoldUTF8(text) end
    return string.lower(text)
end

function ns.QUI_AuraDisplaysOptions.BuildListModel(displays, searchText, isCollapsed)
    local search = (type(searchText) == "string" and searchText ~= "") and Fold(searchText) or nil
    local groups, order = {}, {}
    for i = 1, #displays do
        local display = displays[i]
        local key = display.group or ""
        local matches = not search
            or Fold(display.name or ""):find(search, 1, true) ~= nil
            or Fold(key):find(search, 1, true) ~= nil
        if matches then
            local bucket = groups[key]
            if not bucket then
                bucket = {}
                groups[key] = bucket
                order[#order + 1] = key
            end
            bucket[#bucket + 1] = display
        end
    end
    local model = {}
    for i = 1, #order do
        local key = order[i]
        local bucket = groups[key]
        local collapsed = not search and isCollapsed(key) or false
        model[#model + 1] = { kind = "header", group = key, count = #bucket, collapsed = collapsed }
        if not collapsed then
            for j = 1, #bucket do
                model[#model + 1] = { kind = "display", display = bucket[j] }
            end
        end
    end
    return model
end

local function EnsureLoad(display)
    display.load = display.load or {}
    display.load.classes = display.load.classes or {}
    display.load.specs = display.load.specs or {}
    display.load.roles = display.load.roles or {}
    display.load.encounters = display.load.encounters or {}
    return display.load
end

local function UnitLabelFor(display)
    if display.unitMode == "cotank" then return ns.L["Co-Tank"] end
    if display.unitMode == "name" then
        if type(display.unit) == "string" and display.unit ~= "" then
            return display.unit
        end
        return ns.L["Specific player..."]
    end
    for i = 1, #UNIT_OPTIONS do
        if UNIT_OPTIONS[i].value == display.unit then return UNIT_OPTIONS[i].text end
    end
    return display.unit or ns.L["Player"]
end

local function HasHelpfulTrackedElement(display)
    local elements = display.auras and display.auras.elements
    if type(elements) ~= "table" then return false end
    for _, bucket in pairs(elements) do
        if type(bucket) == "table" then
            for i = 1, #bucket do
                local element = bucket[i]
                if type(element) == "table" and element.mode == "tracked"
                    and (element.auraType or "HELPFUL") == "HELPFUL" then
                    return true
                end
            end
        end
    end
    return false
end

local PAGE_H = 640
local LIST_W = 210
local PANE_GAP = 10
local FALLBACK_ICON = 134400

local selectedID = nil
local searchText = ""
local previewEnabled = true
local specsExpanded = false
local activeDetailTab = "general"
local newGroupPending = false

local function FirstSpellIcon(display)
    local elements = display.auras and display.auras.elements
    if type(elements) == "table" then
        for _, bucket in pairs(elements) do
            if type(bucket) == "table" then
                for i = 1, #bucket do
                    local el = bucket[i]
                    if type(el) == "table" and el.mode == "tracked"
                        and type(el.spells) == "table" and el.spells[1] then
                        local tex = C_Spell and C_Spell.GetSpellTexture
                            and C_Spell.GetSpellTexture(el.spells[1])
                        if tex then return tex end
                    end
                end
            end
        end
    end
    return FALLBACK_ICON
end

local function AccentRGB()
    local accent = GUI and GUI.Colors and GUI.Colors.accent
    if type(accent) == "table" then
        return accent[1] or 0.2, accent[2] or 0.6, accent[3] or 1
    end
    return 0.2, 0.6, 1
end

local UI = { headerRows = {}, displayRows = {} }

local function SyncPreview()
    if not (AD and type(AD.ShowPreviewFor) == "function") then return end
    if previewEnabled and selectedID then
        AD.ShowPreviewFor(selectedID)
    elseif UI.lastPreviewID then
        AD.HidePreviewFor(UI.lastPreviewID)
    end
    UI.lastPreviewID = previewEnabled and selectedID or nil
end

local function SelectDisplay(id)
    if UI.lastPreviewID and UI.lastPreviewID ~= id then
        AD.HidePreviewFor(UI.lastPreviewID)
        UI.lastPreviewID = nil
    end
    selectedID = id
    newGroupPending = false
    SyncPreview()
    if UI.RebuildList then UI.RebuildList() end
    if UI.RebuildDetail then UI.RebuildDetail() end
end

local BuildLeftPane, BuildRightPane

local ShowQuickCreatePopup

function ns.QUI_AuraDisplaysOptions._QuickCreate(spec)
    local name = spec.name
    if type(name) ~= "string" or name == "" then
        name = spec.kind == "filterStrip" and ns.L["New Filter Strip"] or ns.L["New Display"]
    end
    local display = AD.NewDisplay(name)
    if not display then return nil end
    local choice = spec.unitChoice or "player"
    if choice == "__cotank" then
        display.unitMode = "cotank"
        display.unit = nil
    elseif choice == "__name" then
        display.unitMode = "name"
        display.unit = ""
    else
        display.unitMode = "token"
        display.unit = choice
    end
    E.EnsureSeeded(display.auras, AD.DefaultBucket)
    local bucket = display.auras.elements["*"]
    for i = #bucket, 1, -1 do bucket[i] = nil end
    -- Seed at DefaultBucket quality (32px, duration text on), not the bare
    -- 16px constructor defaults quick-create used to ship.
    local T = ns.QUI_AuraDisplayTemplates
    if spec.kind == "tracked" then
        local spellID = spec.spellID
            and E.ResolveTrackedSpellID and E.ResolveTrackedSpellID(spec.spellID)
            or spec.spellID
        if T and type(T.TunedTrackedElement) == "function" then
            bucket[1] = T.TunedTrackedElement(spellID and { spellID } or {}, "icon", "HELPFUL", nil, 100)
        else
            bucket[1] = E.NewTrackedElement(spellID and { spellID } or {}, "icon")
            bucket[1].iconSize = 100
        end
    else
        local seeded = AD.DefaultBucket()
        bucket[1] = seeded[1] or E.NewFilterStripElement("HELPFUL")
    end
    return display
end

local ShowGroupRenameBox
do
    local field, editBox
    local renameTarget
    ShowGroupRenameBox = function(row, groupKey)
        if not field then
            field, editBox = GUI:CreateInlineEditBox(UIParent, {
                width = LIST_W - 60,
                onEscapePressed = function(self)
                    self:ClearFocus()
                    field:Hide()
                end,
                onEnterPressed = function(self)
                    local text = self:GetText()
                    self:ClearFocus()
                    field:Hide()
                    local ok, reason = AD.RenameGroup(renameTarget, text)
                    if ok then
                        AD.Refresh()
                        UI.RebuildList()
                        if UI.RebuildDetail then UI.RebuildDetail() end
                    elseif reason == "collision" and UIErrorsFrame then
                        UIErrorsFrame:AddMessage(
                            ns.L["A group with that name already exists."],
                            1.0, 0.3, 0.3, 1.0)
                    end
                end,
                onCommit = function()
                    field:Hide()
                end,
            })
            field:SetFrameStrata("TOOLTIP")
            UI.groupRenameField = field
        end
        renameTarget = groupKey
        field:ClearAllPoints()
        field:SetPoint("LEFT", row, "LEFT", 2, 0)
        field:Show()
        editBox:SetText(groupKey)
        editBox:SetFocus()
        editBox:HighlightText()
    end
end

local function AcquireHeaderRow(parent, index)
    local row = UI.headerRows[index]
    if not row then
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetSize(LIST_W - 20, 22)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0.08, 0.14, 0.18, 0.9)
        row.label = GUI:CreateLabel(row, "", 11)
        row.label:SetPoint("LEFT", 4, 0)
        row.rename = GUI:CreateButton(row, "✎", 16, 16, nil)
        row.rename:SetPoint("RIGHT", -60, 0)
        row.toggle = GUI:CreateButton(row, "", 40, 16, nil)
        row.toggle:SetPoint("RIGHT", -20, 0)
        row.del = GUI:CreateButton(row, "x", 16, 16, nil)
        row.del:SetPoint("RIGHT", -2, 0)
        local function OnHoverButtonLeave()
            if not row:IsMouseOver() then
                row.rename:Hide()
                row.toggle:Hide()
                row.del:Hide()
            end
        end
        row.rename:HookScript("OnLeave", OnHoverButtonLeave)
        row.toggle:HookScript("OnLeave", OnHoverButtonLeave)
        row.del:HookScript("OnLeave", OnHoverButtonLeave)
        UI.headerRows[index] = row
    end
    if row:GetParent() ~= parent then row:SetParent(parent) end
    row:Show()
    return row
end

local function PaintGroupHeaderRow(row, y, node)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -y)
    local title = node.group == "" and ns.L["Ungrouped"] or node.group
    local marker = node.group == "" and "" or (node.collapsed and "> " or "v ")
    row.label:SetText(marker .. title .. " (" .. node.count .. ")")
    row:SetScript("OnClick", function()
        if node.group ~= "" then
            AD.SetGroupCollapsed(node.group, not node.collapsed)
        end
        UI.RebuildList()
    end)
    local real = node.group ~= ""
    row.rename:Hide()
    row.toggle:Hide()
    row.del:Hide()
    if real then
        row.rename:SetScript("OnClick", function()
            ShowGroupRenameBox(row, node.group)
        end)
        local enabled = AD.GroupEnabled(node.group)
        row.toggle:SetText(enabled and ns.L["On"] or ns.L["Off"])
        row.toggle:SetScript("OnClick", function()
            AD.SetGroupEnabled(node.group, not enabled)
            AD.Refresh()
            UI.RebuildList()
        end)
        row.del:SetScript("OnClick", function()
            GUI:ShowConfirmation({
                title = ns.L["Delete Group?"],
                message = string.format(ns.L["Delete '%1$s'?"], node.group),
                warningText = ns.L["This cannot be undone."],
                acceptText = ns.L["Delete"],
                cancelText = ns.L["Cancel"],
                isDestructive = true,
                onAccept = function()
                    AD.DeleteGroup(node.group)
                    AD.Refresh()
                    UI.RebuildList()
                    if UI.RebuildDetail then UI.RebuildDetail() end
                end,
            })
        end)
        row:SetScript("OnEnter", function()
            row.rename:Show()
            row.toggle:Show()
            row.del:Show()
        end)
        row:SetScript("OnLeave", function()
            if not row:IsMouseOver() then
                row.rename:Hide()
                row.toggle:Hide()
                row.del:Hide()
            end
        end)
    else
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
    end
    return 24
end

local function AcquireDisplayRow(parent, index)
    local row = UI.displayRows[index]
    if not row then
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetSize(LIST_W - 20, 24)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row.check = CreateFrame("Button", nil, row)
        row.check:SetSize(12, 12)
        row.check:SetPoint("LEFT", 3, 0)
        row.checkBg = row.check:CreateTexture(nil, "BACKGROUND")
        row.checkBg:SetAllPoints()
        row.checkBg:SetColorTexture(0.12, 0.12, 0.12, 1)
        row.checkFill = row.check:CreateTexture(nil, "ARTWORK")
        row.checkFill:SetPoint("TOPLEFT", 2, -2)
        row.checkFill:SetPoint("BOTTOMRIGHT", -2, 2)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", 5, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = GUI:CreateLabel(row, "", 11)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -34, 0)
        row.name:SetJustifyH("LEFT")
        row.up = GUI:CreateButton(row, "▲", 15, 15, nil)
        row.up:SetPoint("RIGHT", -17, 0)
        row.down = GUI:CreateButton(row, "▼", 15, 15, nil)
        row.down:SetPoint("RIGHT", -1, 0)
        local function OnHoverButtonLeave()
            if not row:IsMouseOver() then
                row.up:Hide()
                row.down:Hide()
            end
        end
        row.up:HookScript("OnLeave", OnHoverButtonLeave)
        row.down:HookScript("OnLeave", OnHoverButtonLeave)
        UI.displayRows[index] = row
    end
    if row:GetParent() ~= parent then row:SetParent(parent) end
    row:Show()
    return row
end

local function PaintDisplayRow(row, y, display)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -y)
    if display.id == selectedID then
        local ar, ag, ab = AccentRGB()
        row:SetBackdropColor(ar * 0.3, ag * 0.3, ab * 0.3, 0.9)
    else
        row:SetBackdropColor(0, 0, 0, 0)
    end
    local function PaintCheck()
        if display.enabled then
            local ar, ag, ab = AccentRGB()
            row.checkFill:SetColorTexture(ar, ag, ab, 0.9)
            row.checkFill:Show()
        else
            row.checkFill:Hide()
        end
    end
    PaintCheck()
    row.check:SetScript("OnClick", function()
        display.enabled = not display.enabled
        AD.Refresh()
        PaintCheck()
    end)
    row.icon:SetTexture(FirstSpellIcon(display))
    row.name:SetText(display.name or display.id)
    row.up:Hide()
    row.down:Hide()
    row.up:SetScript("OnClick", function()
        if AD.MoveDisplayWithinGroup(display.id, -1) then
            AD.Refresh()
            UI.RebuildList()
        end
    end)
    row.down:SetScript("OnClick", function()
        if AD.MoveDisplayWithinGroup(display.id, 1) then
            AD.Refresh()
            UI.RebuildList()
        end
    end)
    row:SetScript("OnEnter", function()
        row.up:Show()
        row.down:Show()
    end)
    row:SetScript("OnLeave", function()
        if not row:IsMouseOver() then
            row.up:Hide()
            row.down:Hide()
        end
    end)
    row:SetScript("OnClick", function() SelectDisplay(display.id) end)
    return 26
end

do
    local popup
    ShowQuickCreatePopup = function()
        if not popup then
            popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            popup:SetSize(300, 240)
            popup:SetPoint("CENTER")
            popup:SetFrameStrata("TOOLTIP")
            popup:SetMovable(true)
            popup:EnableMouse(true)
            popup:RegisterForDrag("LeftButton")
            popup:SetScript("OnDragStart", popup.StartMoving)
            popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
            popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            popup:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
            popup:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

            popup.state = { kind = "tracked", spellID = nil, spellName = nil,
                unitChoice = "player", _quiTransientOptionsProxy = true }

            local title = GUI:CreateLabel(popup, ns.L["New Display"], 13)
            title:SetPoint("TOP", 0, -10)

            local trackedBtn, stripBtn, browseBtn
            local function PaintKind()
                trackedBtn:SetAlpha(popup.state.kind == "tracked" and 1 or 0.5)
                stripBtn:SetAlpha(popup.state.kind == "filterStrip" and 1 or 0.5)
                popup.spellInput:SetShown(popup.state.kind == "tracked")
                browseBtn:SetShown(popup.state.kind == "tracked")
            end
            trackedBtn = GUI:CreateButton(popup, ns.L["Track spells"], 130, 22, function()
                popup.state.kind = "tracked"
                PaintKind()
            end, "primary")
            trackedBtn:SetPoint("TOPLEFT", 15, -34)
            stripBtn = GUI:CreateButton(popup, ns.L["Filter strip"], 130, 22, function()
                popup.state.kind = "filterStrip"
                PaintKind()
            end)
            stripBtn:SetPoint("LEFT", trackedBtn, "RIGHT", 8, 0)

            local P = ns.QUI_AuraDisplayPickers
            local SpellList = ns.QUI_AuraSpellList
            popup.spellInput = P.CreateSpellEchoInput(popup, 200, function(spellID, spellName)
                popup.state.spellID = spellID
                popup.state.spellName = spellName
                if spellName and popup.nameEdit:GetText() == "" then
                    popup.nameEdit:SetText(spellName)
                end
            end)
            popup.spellInput:SetPoint("TOPLEFT", 15, -64)

            browseBtn = GUI:CreateButton(popup, ns.L["Browse"], 64, 22, function()
                if not (SpellList and SpellList.ToggleBrowsePopup) then return end
                SpellList.ToggleBrowsePopup("quickCreate", {
                    title = ns.L["Add Tracked Spells"],
                    presets = (SpellList.GetDefaultPresets and SpellList.GetDefaultPresets()) or {},
                    isSelected = function(id) return popup.state.spellID == id end,
                    onToggle = function(id) popup.spellInput.editBox:SetText(tostring(id)) end,
                    onClose = function() end,
                })
            end)
            browseBtn:SetPoint("LEFT", popup.spellInput, "RIGHT", 6, 0)

            popup:HookScript("OnHide", function()
                if SpellList and SpellList.CloseBrowsePopup then
                    SpellList.CloseBrowsePopup("quickCreate")
                end
            end)

            popup.nameBox, popup.nameEdit = GUI:CreateInlineEditBox(popup, { width = 270 })
            popup.nameBox:SetPoint("TOPLEFT", 15, -124)
            local nameLabel = GUI:CreateLabel(popup, ns.L["Name"], 10, C.textMuted)
            nameLabel:SetPoint("BOTTOMLEFT", popup.nameBox, "TOPLEFT", 0, 2)

            local unitW = GUI:CreateFormDropdown(popup, nil, UNIT_OPTIONS, "unitChoice",
                popup.state, function() end,
                { description = ns.L["Which unit this display watches. Co-Tank follows the first other tank in your group."] })
            unitW:SetPoint("TOPLEFT", 15, -156)
            local unitLabel = GUI:CreateLabel(popup, ns.L["Unit"], 10, C.textMuted)
            unitLabel:SetPoint("BOTTOMLEFT", unitW, "TOPLEFT", 0, 2)

            local createBtn = GUI:CreateButton(popup, ns.L["Create"], 100, 24, function()
                local display = ns.QUI_AuraDisplaysOptions._QuickCreate({
                    kind = popup.state.kind,
                    name = popup.nameEdit:GetText(),
                    unitChoice = popup.state.unitChoice,
                    spellID = popup.state.spellID,
                })
                popup:Hide()
                if display then
                    AD.Refresh()
                    SelectDisplay(display.id)
                end
            end, "primary")
            createBtn:SetPoint("BOTTOMLEFT", 15, 10)
            local cancelBtn = GUI:CreateButton(popup, ns.L["Cancel"], 100, 24, function()
                popup:Hide()
            end)
            cancelBtn:SetPoint("BOTTOMRIGHT", -15, 10)
            popup.PaintKind = PaintKind
            UI.quickCreatePopup = popup
        end
        popup.state.kind = "tracked"
        popup.state.spellID = nil
        popup.state.spellName = nil
        popup.nameEdit:SetText("")
        popup.spellInput.editBox:SetText("")
        popup.PaintKind()
        popup:Show()
        popup.spellInput.editBox:SetFocus()
    end
end

BuildLeftPane = function(left)
    local search = GUI:CreateSearchBox(left, ns.L["Search displays"])
    search:SetPoint("TOPLEFT", 0, 0)
    search:SetPoint("TOPRIGHT", 0, 0)
    search.onSearch = function(text)
        searchText = text or ""
        UI.RebuildList()
    end
    search.onClear = function()
        searchText = ""
        UI.RebuildList()
    end

    local newBtn = GUI:CreateButton(left, ns.L["New Display"], LIST_W, 24, function()
        local Create = ns.QUI_AuraDisplaysCreate
        if Create and type(Create.ShowDialog) == "function" then
            Create.ShowDialog({
                onCreated = function(display)
                    if not display then return end
                    AD.Refresh()
                    SelectDisplay(display.id)
                end,
            })
        else
            ShowQuickCreatePopup()
        end
    end, "primary")
    newBtn:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
    newBtn:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -4)

    local scroll, listContent = Shared.CreateScrollableContent(left)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -18, 0)

    UI.RebuildList = function()
        local model = ns.QUI_AuraDisplaysOptions.BuildListModel(
            AD.OrderedDisplays(), searchText, AD.GroupCollapsed)
        local headerIdx, displayIdx, y = 0, 0, 0
        for i = 1, #model do
            local node = model[i]
            if node.kind == "header" then
                headerIdx = headerIdx + 1
                y = y + PaintGroupHeaderRow(AcquireHeaderRow(listContent, headerIdx), y, node)
            else
                displayIdx = displayIdx + 1
                y = y + PaintDisplayRow(AcquireDisplayRow(listContent, displayIdx), y, node.display)
            end
        end
        for i = headerIdx + 1, #UI.headerRows do UI.headerRows[i]:Hide() end
        for i = displayIdx + 1, #UI.displayRows do UI.displayRows[i]:Hide() end
        listContent:SetHeight(math.max(y, 1))
    end
    UI.RebuildList()
end

function ns.QUI_AuraDisplaysOptions._BuildGeneralTab(host, ctx, display)
    local L = ns.QUI_SettingsLayoutShared.MakeLayout(host)
    local card = L.sectionAt()

    local nameW = GUI:CreateFormEditBox(card.frame, nil, "name", display, function()
        AD.RenameDisplay(display.id, display.name)
        AD.Refresh()
        if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
        if UI.RebuildList then UI.RebuildList() end
    end, nil, { description = ns.L["The name shown in this list and in Layout Mode."] })

    local groupOptions = { { value = "", text = ns.L["No group"] } }
    local seen = {}
    local displays = AD.OrderedDisplays()
    for i = 1, #displays do
        local g = displays[i].group
        if type(g) == "string" and g ~= "" and not seen[g] then
            seen[g] = true
            groupOptions[#groupOptions + 1] = { value = g, text = g }
        end
    end
    groupOptions[#groupOptions + 1] = { value = "__new", text = ns.L["New group..."] }

    local groupW
    if newGroupPending then
        groupW = GUI:CreateInlineEditBox(card.frame, {
            width = 160,
            onEscapePressed = function(self)
                newGroupPending = false
                self:ClearFocus()
                if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
            end,
            onEnterPressed = function(self)
                local text = self:GetText()
                newGroupPending = false
                self:ClearFocus()
                if type(text) == "string" and text ~= "" then
                    display.group = text
                    AD.Refresh()
                    if UI.RebuildList then UI.RebuildList() end
                end
                if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
            end,
        })
    else
        local proxy = { groupChoice = display.group or "", _quiTransientOptionsProxy = true }
        groupW = GUI:CreateFormDropdown(card.frame, nil, groupOptions, "groupChoice", proxy,
            function()
                if proxy.groupChoice == "__new" then
                    proxy.groupChoice = display.group or ""
                    newGroupPending = true
                    if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
                    return
                end
                display.group = proxy.groupChoice ~= "" and proxy.groupChoice or nil
                AD.Refresh()
                if UI.RebuildList then UI.RebuildList() end
            end,
            { description = ns.L["Displays sharing a group are listed and collapsed together."] })
    end

    card.AddRow(
        Shared.BuildSettingRow(card.frame, ns.L["Name"], nameW),
        Shared.BuildSettingRow(card.frame, ns.L["Group"], groupW)
    )
    L.closeSection(card)

    local unitCard = L.sectionAt()
    local current = display.unitMode == "cotank" and "__cotank"
        or display.unitMode == "name" and "__name"
        or display.unit
    local unitProxy = { unitChoice = current, _quiTransientOptionsProxy = true }
    local unitW = GUI:CreateFormDropdown(unitCard.frame, nil, UNIT_OPTIONS, "unitChoice", unitProxy,
        function()
            local choice = unitProxy.unitChoice
            if choice == "__cotank" then
                display.unitMode = "cotank"
                display.unit = nil
            elseif choice == "__name" then
                display.unitMode = "name"
                display.unit = ""
            else
                display.unitMode = "token"
                display.unit = choice
            end
            AD.Refresh()
            if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
        end,
        { description = ns.L["Which unit this display watches. Co-Tank follows the first other tank in your group."] })
    display.visibility = display.visibility or "active"
    local visibilityW = GUI:CreateFormDropdown(unitCard.frame, nil, VISIBILITY_OPTIONS,
        "visibility", display, function() AD.Refresh() end, {
            description = ns.L["Controls when inactive aura icons remain visible and desaturated. Active Only hides them; Show In Instance keeps them visible in dungeons and raids; Always keeps them visible everywhere."],
        })
    unitCard.AddRow(
        Shared.BuildSettingRow(unitCard.frame, ns.L["Unit"], unitW),
        Shared.BuildSettingRow(unitCard.frame, ns.L["Visibility"], visibilityW)
    )
    if display.unitMode == "name" then
        local nameField = GUI:CreateFormEditBox(unitCard.frame, nil, "unit", display, function()
            AD.Refresh()
        end, nil, { description = ns.L["Character name, optionally Name-Realm. Matched against your current group."] })
        unitCard.AddRow(Shared.BuildSettingRow(unitCard.frame, ns.L["Player Name"], nameField))
    end
    L.closeSection(unitCard)

    local layoutCard = L.sectionAt()
    display.layout = display.layout or {}
    display.layout.direction = display.layout.direction or "RIGHT"
    display.layout.alignment = display.layout.alignment or "CENTER"
    display.layout.spacing = display.layout.spacing or 2
    local layoutChanged = function()
        AD.Refresh()
        SyncPreview()
    end
    local directionProxy = {
        direction = display.layout.direction,
        _quiTransientOptionsProxy = true,
    }
    local directionW = GUI:CreateFormDropdown(layoutCard.frame, nil,
        DISPLAY_DIRECTION_OPTIONS, "direction", directionProxy, function()
            display.layout.direction = directionProxy.direction
            layoutChanged()
        end, {
            description = ns.L["How separate aura rows are arranged inside this display. Grow Direction still controls icons within one row."],
        })
    local alignmentProxy = {
        alignment = display.layout.alignment,
        _quiTransientOptionsProxy = true,
    }
    local alignmentW = GUI:CreateFormDropdown(layoutCard.frame, nil,
        DISPLAY_ALIGNMENT_OPTIONS, "alignment", alignmentProxy, function()
            display.layout.alignment = alignmentProxy.alignment
            layoutChanged()
        end, {
            description = ns.L["How rows are aligned across the other axis."],
        })
    local spacingW = GUI:CreateFormSlider(layoutCard.frame, nil, 0, 8, 1, "spacing",
        display.layout, layoutChanged, { deferOnDrag = true }, {
            description = ns.L["Pixel gap between separate aura rows."],
        })
    layoutCard.AddRow(
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Row Direction"], directionW),
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Row Alignment"], alignmentW)
    )
    layoutCard.AddRow(Shared.BuildSettingRow(layoutCard.frame, ns.L["Row Spacing"], spacingW))
    L.closeSection(layoutCard)

    if AD.UnitPolarityFor(display) == "hostile" and HasHelpfulTrackedElement(display) then
        local wrap = CreateFrame("Frame", nil, host)
        wrap:SetHeight(44)
        local warn = GUI:CreateLabel(wrap,
            ns.L["Blizzard does not allow tracking specific buffs by spell on units you cannot assist, so a tracked buff list on an enemy unit will always be empty. Use a filter strip instead, or point this display at a friendly unit."],
            11, C.warning)
        warn:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
        warn:SetPoint("RIGHT", wrap, "RIGHT", 0, 0)
        warn:SetJustifyH("LEFT")
        warn:SetWordWrap(true)
        L.placeCustom(wrap, 48)
    end

    L.finish()
    return host:GetHeight()
end

function ns.QUI_AuraDisplaysOptions._BuildAurasTab(host, ctx, display)
    E.EnsureSeeded(display.auras, AD.DefaultBucket)
    local AurasEditor = ns.QUI_AuraElementsEditor
    if not AurasEditor or type(AurasEditor.RenderAuras) ~= "function" then return 1 end

    local warnHeight = 0
    local editorHost = host
    if AD.UnitPolarityFor(display) == "hostile" and HasHelpfulTrackedElement(display) then
        local wrap = CreateFrame("Frame", nil, host)
        wrap:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        wrap:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        wrap:SetHeight(44)
        local warn = GUI:CreateLabel(wrap,
            ns.L["Blizzard does not allow tracking specific buffs by spell on units you cannot assist, so a tracked buff list on an enemy unit will always be empty. Use a filter strip instead, or point this display at a friendly unit."],
            11, C.warning)
        warn:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
        warn:SetPoint("RIGHT", wrap, "RIGHT", 0, 0)
        warn:SetJustifyH("LEFT")
        warn:SetWordWrap(true)
        warnHeight = 48
        editorHost = CreateFrame("Frame", nil, host)
        editorHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -warnHeight)
        editorHost:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        editorHost:SetHeight(1)
    end

    local W = ns.QUI_AuraWizard
    local specID = W and type(W.PlayerSpecID) == "function" and W.PlayerSpecID() or nil
    local bucketKey = (W and type(W.ActiveBucketKey) == "function")
        and W.ActiveBucketKey(display.auras.elements, specID) or "*"

    local height = AurasEditor.RenderAuras(editorHost, display.auras, bucketKey, function()
        AD.Refresh()
        SyncPreview()
        if UI.RebuildList then UI.RebuildList() end
    end, {
        capabilities = {
            elementTypes        = { filterStrip = true, tracked = true },
            trackedDisplayTypes = { icon = true, square = true, bar = true },
            iconSizeMax         = 200,
            containerLayout     = true,
            allowSpecOverride   = true,
            roleGate            = false,
            cancelEligible      = false,
            unitPolarity        = AD.UnitPolarityFor(display),
            defaultBucketFn     = AD.DefaultBucket,
            simpleMode          = true,
            summaryUnit         = UnitLabelFor(display),
        },
        onLayoutChanged = function(newHeight)
            if type(newHeight) == "number" and ctx and ctx.ResizeTab then
                ctx.ResizeTab(newHeight + warnHeight)
            end
        end,
    })
    local total = (type(height) == "number" and height > 0) and height or (editorHost:GetHeight() or 1)
    return total + warnHeight
end

local function CreateAuraSoundControl(parent, sounds, key, onChange)
    local control = CreateFrame("Frame", nil, parent)
    control:SetSize(240, 24)
    local dropdown = GUI:CreateFormDropdown(control, nil, AlertSoundOptions(), key, sounds, onChange, {
        description = ns.L["Blizzard plays this sound when the aura event occurs. None disables this event."],
    })
    dropdown:SetPoint("LEFT", control, "LEFT", 0, 0)
    dropdown:SetPoint("RIGHT", control, "RIGHT", -48, 0)
    local preview = GUI:CreateButton(control, ns.L["Test"], 44, 22, function()
        AD.PreviewAuraSound(sounds[key])
    end)
    preview:SetPoint("RIGHT", control, "RIGHT", 0, 0)
    return control
end

function ns.QUI_AuraDisplaysOptions._BuildAlertsTab(host, ctx, display)
    local mode = display.unitMode or "token"
    if mode ~= "token" or AD.STATIC_TOKENS[display.unit] == nil then
        local L = ns.QUI_SettingsLayoutShared.MakeLayout(host)
        L.intro(ns.L["Blizzard aura sounds require a fixed unit token. Choose Player, Target, Focus, Party, Raid, Boss, Arena, Pet, or Mouseover in General. Co-Tank and Specific Player cannot be registered safely because their unit token changes."])
        return L.finish()
    end
    if AD.HasEncounterLoadConditions(display) then
        local L = ns.QUI_SettingsLayoutShared.MakeLayout(host)
        L.intro(ns.L["Encounter load conditions cannot control Blizzard native aura sound registrations safely because encounters begin in combat. Remove the Encounter condition to configure sounds for this display."])
        return L.finish()
    end

    E.EnsureSeeded(display.auras, AD.DefaultBucket)
    local W = ns.QUI_AuraWizard
    local specID = W and type(W.PlayerSpecID) == "function" and W.PlayerSpecID() or nil
    local elements = E.ActiveElementsForSpec(display.auras, specID)
    local L = ns.QUI_SettingsLayoutShared.MakeLayout(host)
    local found = false

    for _, element in ipairs(elements) do
        if element.mode == "tracked" and type(element.spells) == "table" then
            for _, spellID in ipairs(element.spells) do
                if type(spellID) == "number" then
                    found = true
                    local spellName = C_Spell and C_Spell.GetSpellName
                        and C_Spell.GetSpellName(spellID) or tostring(spellID)
                    L.headerAt(spellName or tostring(spellID))
                    if E.EffectiveOnlyMine(element, spellID) then
                        L.intro(ns.L["This aura uses Only My Cast. Blizzard's native sound API cannot filter by caster, so sounds stay off for this spell until Only My Cast is disabled in the Auras tab."])
                    else
                        element.auraSounds = element.auraSounds or {}
                        local sounds = element.auraSounds[spellID]
                        if type(sounds) ~= "table" then
                            sounds = {
                                added = "None",
                                applicationsIncreased = "None",
                                removed = "None",
                            }
                            element.auraSounds[spellID] = sounds
                        end
                        local changed = function() AD.Refresh() end
                        local card = L.sectionAt()
                        card.AddRow(Shared.BuildSettingRow(card.frame, ns.L["Aura Applied"],
                            CreateAuraSoundControl(card.frame, sounds, "added", changed)))
                        card.AddRow(Shared.BuildSettingRow(card.frame, ns.L["Stacks Increased"],
                            CreateAuraSoundControl(card.frame, sounds, "applicationsIncreased", changed)))
                        card.AddRow(Shared.BuildSettingRow(card.frame, ns.L["Aura Removed"],
                            CreateAuraSoundControl(card.frame, sounds, "removed", changed)))
                        L.closeSection(card)
                    end
                end
            end
        end
    end

    if not found then
        L.intro(ns.L["Add a tracked spell in the Auras tab to configure native aura sounds."])
    end
    return L.finish()
end

function ns.QUI_AuraDisplaysOptions._BuildLoadTab(host, ctx, display)
    EnsureLoad(display)
    local P = ns.QUI_AuraDisplayPickers
    local width = host:GetWidth()
    if not width or width < 100 then width = 520 end
    local y = 8

    local function Place(builder, get, onSet)
        local frame, h = builder(host, width - 8, get, onSet or function()
            AD.Refresh()
        end)
        frame:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -y)
        y = y + h + 12
        return frame
    end

    local rolesHeader = GUI:CreateLabel(host, ns.L["Roles"], 11, C.textMuted)
    rolesHeader:SetPoint("TOPLEFT", 4, -y)
    y = y + 18
    Place(P.BuildRolePicker, function() return display.load.roles end)

    local classHeader = GUI:CreateLabel(host, ns.L["Classes"], 11, C.textMuted)
    classHeader:SetPoint("TOPLEFT", 4, -y)
    y = y + 18
    Place(P.BuildClassPicker, function() return display.load.classes end)

    local specFrame, specH = P.BuildSpecPicker(host, width - 8,
        function() return display.load.specs end,
        function() AD.Refresh() end,
        specsExpanded,
        function()
            specsExpanded = not specsExpanded
            if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
        end)
    specFrame:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -y)
    y = y + specH + 12

    local encHeader = GUI:CreateLabel(host, ns.L["Encounters"], 11, C.textMuted)
    encHeader:SetPoint("TOPLEFT", 4, -y)
    y = y + 18
    Place(P.BuildEncounterPicker, function() return display.load.encounters end,
        function()
            AD.Refresh()
            if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
        end)

    local hint = GUI:CreateLabel(host,
        ns.L["Nothing selected in a category means it always loads."], 10, C.textMuted)
    hint:SetPoint("TOPLEFT", 4, -y)
    y = y + 20

    host:SetHeight(y)
    return y
end

BuildRightPane = function(right, ctx)
    local FullSurface = ns.Settings and ns.Settings.FullSurface
    local header = CreateFrame("Frame", nil, right)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(28)

    local title = GUI:CreateLabel(header, "", 13)
    title:SetPoint("LEFT", 2, 0)

    local deleteBtn = GUI:CreateButton(header, ns.L["Delete"], 70, 22, function()
        local display = selectedID and AD.GetDisplay(selectedID)
        if not display then return end
        GUI:ShowConfirmation({
            title = ns.L["Delete Display?"],
            message = string.format(ns.L["Delete '%1$s'?"], display.name or display.id),
            warningText = ns.L["This cannot be undone."],
            acceptText = ns.L["Delete"],
            cancelText = ns.L["Cancel"],
            isDestructive = true,
            onAccept = function()
                AD.HidePreviewFor(display.id)
                AD.UnregisterLayoutElement(display.id)
                AD.DeleteDisplay(display.id)
                UI.lastPreviewID = nil
                SelectDisplay(nil)
                AD.Refresh()
            end,
        })
    end)
    deleteBtn:SetPoint("RIGHT", 0, 0)

    local dupBtn = GUI:CreateButton(header, ns.L["Duplicate"], 80, 22, function()
        if not selectedID then return end
        local display = AD.GetDisplay(selectedID)
        local copy = display and AD.DuplicateDisplay(display.id,
            ns.L["%s (copy)"]:format(display.name or display.id))
        if copy then
            AD.Refresh()
            SelectDisplay(copy.id)
        end
    end)
    dupBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)

    local previewBtn
    local function PaintPreviewButton()
        previewBtn:SetText(previewEnabled and ns.L["Preview: On"] or ns.L["Preview: Off"])
    end
    previewBtn = GUI:CreateButton(header, "", 90, 22, function()
        previewEnabled = not previewEnabled
        PaintPreviewButton()
        SyncPreview()
    end)
    previewBtn:SetPoint("RIGHT", dupBtn, "LEFT", -4, 0)
    PaintPreviewButton()
    title:SetPoint("RIGHT", previewBtn, "LEFT", -8, 0)

    local strip, paint
    if FullSurface and type(FullSurface.CreateTabStrip) == "function" then
        strip, paint = FullSurface.CreateTabStrip(right)
        strip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
        strip:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    end

    local body = CreateFrame("Frame", nil, right)
    body:SetPoint("TOPLEFT", strip or header, "BOTTOMLEFT", 0, -4)
    body:SetPoint("BOTTOMRIGHT")
    local scroll, tabContent = Shared.CreateScrollableContent(body)

    local TABS = {
        { key = "general", label = ns.L["General"] },
        { key = "auras", label = ns.L["Auras"] },
        { key = "alerts", label = ns.L["Alerts"] },
        { key = "load", label = ns.L["Load Conditions"] },
    }
    local BUILDERS = {
        general = ns.QUI_AuraDisplaysOptions._BuildGeneralTab,
        auras = ns.QUI_AuraDisplaysOptions._BuildAurasTab,
        alerts = ns.QUI_AuraDisplaysOptions._BuildAlertsTab,
        load = ns.QUI_AuraDisplaysOptions._BuildLoadTab,
    }

    UI.RebuildDetail = function()
        if type(GUI.TeardownFrameTree) == "function" then
            GUI:TeardownFrameTree(tabContent)
        else
            for _, child in ipairs({ tabContent:GetChildren() }) do
                child:Hide()
                child:SetParent(nil)
            end
        end
        local display = selectedID and AD.GetDisplay(selectedID)
        title:SetText(display and (display.name or display.id) or "")
        deleteBtn:SetShown(display ~= nil)
        dupBtn:SetShown(display ~= nil)
        previewBtn:SetShown(display ~= nil)
        if paint then
            paint(TABS, activeDetailTab, function(key)
                activeDetailTab = key
                UI.RebuildDetail()
            end)
        end
        if not display then
            local hint = GUI:CreateLabel(tabContent,
                ns.L["Select a display on the left, or create one."], 11, C.textMuted)
            hint:SetPoint("TOPLEFT", 4, -12)
            tabContent:SetHeight(60)
            return
        end
        local host = CreateFrame("Frame", nil, tabContent)
        host:SetPoint("TOPLEFT")
        host:SetPoint("TOPRIGHT")
        host:SetHeight(1)
        local builder = BUILDERS[activeDetailTab] or BUILDERS.general
        local height = builder(host, { RebuildDetail = UI.RebuildDetail,
            ResizeTab = function(h) tabContent:SetHeight(math.max(h, 1)) end }, display)
        tabContent:SetHeight(math.max(height or 1, 1))
        SyncPreview()
    end
    UI.RebuildDetail()
end

function ns.QUI_AuraDisplaysOptions.BuildAuraDisplaysContent(content, ctx)
    AD = ns.QUI_AuraDisplays
    if not AD or type(AD.OrderedDisplays) ~= "function" then
        local noData = GUI:CreateLabel(content,
            ns.L["Aura display settings are not available. Please reload the UI."],
            12, C.textMuted)
        noData:SetPoint("TOPLEFT", PAD, -20)
        content:SetHeight(80)
        return 80
    end

    if selectedID and not AD.GetDisplay(selectedID) then selectedID = nil end

    local topOffset = 0
    local profileCopy = ns.QUI_ProfileCopyOptions
    if profileCopy
        and type(profileCopy.CreateCard) == "function"
    then
        local copyHeader = Shared.CreateAccentDotLabel(content, ns.L["Copy Settings"], 0)
        copyHeader:ClearAllPoints()
        copyHeader:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, 0)
        copyHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, 0)

        local copyHost = CreateFrame("Frame", nil, content)
        copyHost:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -22)
        copyHost:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -22)
        local controller = profileCopy.CreateCard(copyHost, {
            fixedCategoryID = "auraDisplays",
            fixedCategoryLabel = ns.L["Aura Displays"],
            onCopied = function()
                if UI.lastPreviewID then AD.HidePreviewFor(UI.lastPreviewID) end
                UI.lastPreviewID = nil
                selectedID = nil
                if UI.RebuildList then UI.RebuildList() end
                if UI.RebuildDetail then UI.RebuildDetail() end
            end,
        })
        copyHost:SetHeight(controller.frame:GetHeight())
        topOffset = 22 + controller.frame:GetHeight() + 14
    end

    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -topOffset)
    pane:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -topOffset)
    pane:SetHeight(PAGE_H)
    pane:SetScript("OnHide", function()
        if UI.lastPreviewID then
            AD.HidePreviewFor(UI.lastPreviewID)
            UI.lastPreviewID = nil
        end
        if UI.groupRenameField then UI.groupRenameField:Hide() end
        if UI.quickCreatePopup then UI.quickCreatePopup:Hide() end
        local Create = ns.QUI_AuraDisplaysCreate
        if Create and type(Create.HideDialog) == "function" then Create.HideDialog() end
    end)
    pane:HookScript("OnShow", SyncPreview)

    local left = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W)

    local right = CreateFrame("Frame", nil, pane)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", PANE_GAP, 0)
    right:SetPoint("BOTTOMRIGHT")

    BuildLeftPane(left)
    BuildRightPane(right, ctx)

    content:SetHeight(PAGE_H + topOffset)
    return PAGE_H + topOffset
end
