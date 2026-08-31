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

-- Nested list model. `tree.children[""]` names the root groups and
-- `tree.children[name]` each group's ordered child groups; groups render as a
-- tree with their displays, then an Ungrouped section. While searching, a
-- display matches on its own name or any ancestor group's name, collapse is
-- ignored, and empty branches are pruned.
function ns.QUI_AuraDisplaysOptions.BuildListModel(displays, searchText, isCollapsed, tree)
    local search = (type(searchText) == "string" and searchText ~= "") and Fold(searchText) or nil
    local children = (type(tree) == "table" and type(tree.children) == "table")
        and tree.children or {}

    local buckets, ungrouped = {}, {}
    for i = 1, #displays do
        local display = displays[i]
        local key = display.group
        if type(key) == "string" and key ~= "" then
            local bucket = buckets[key]
            if not bucket then
                bucket = {}
                buckets[key] = bucket
            end
            bucket[#bucket + 1] = display
        else
            ungrouped[#ungrouped + 1] = display
        end
    end

    local model = {}
    local visited = {}

    local function AddGroup(name, depth, ancestorMatch)
        if visited[name] then return 0 end
        visited[name] = true
        local groupMatch = ancestorMatch
            or (search and Fold(name):find(search, 1, true) ~= nil)
        local headerIndex = #model + 1
        model[headerIndex] = { kind = "header", group = name, depth = depth }
        local collapsed = not search and isCollapsed(name) or false
        model[headerIndex].collapsed = collapsed

        local count = 0
        local bucket = buckets[name]
        if bucket then
            for j = 1, #bucket do
                local display = bucket[j]
                local matches = not search or groupMatch
                    or Fold(display.name or ""):find(search, 1, true) ~= nil
                if matches then
                    count = count + 1
                    if not collapsed then
                        model[#model + 1] = { kind = "display", display = display, depth = depth + 1 }
                    end
                end
            end
        end

        local childNames = children[name]
        if childNames then
            for j = 1, #childNames do
                if collapsed then
                    -- Children stay hidden but still contribute to the count.
                    local before = #model
                    count = count + AddGroup(childNames[j], depth + 1, groupMatch)
                    for k = #model, before + 1, -1 do model[k] = nil end
                else
                    count = count + AddGroup(childNames[j], depth + 1, groupMatch)
                end
            end
        end

        model[headerIndex].count = count
        if search and count == 0 and not groupMatch then
            -- Prune the empty branch: nothing under it matched.
            for k = #model, headerIndex, -1 do model[k] = nil end
            return 0
        end
        return count
    end

    local roots = children[""] or {}
    for i = 1, #roots do
        AddGroup(roots[i], 0, false)
    end

    local ungroupedShown = {}
    for i = 1, #ungrouped do
        local display = ungrouped[i]
        local matches = not search
            or Fold(display.name or ""):find(search, 1, true) ~= nil
        if matches then ungroupedShown[#ungroupedShown + 1] = display end
    end
    if #ungroupedShown > 0 then
        model[#model + 1] = { kind = "header", group = "", depth = 0,
            count = #ungroupedShown, collapsed = false }
        for i = 1, #ungroupedShown do
            model[#model + 1] = { kind = "display", display = ungroupedShown[i], depth = 1 }
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
local selectedGroup = nil
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
    local wantedID = previewEnabled and selectedID or nil
    local wantedGroup = previewEnabled and selectedGroup or nil
    if UI.lastPreviewID and UI.lastPreviewID ~= wantedID then
        AD.HidePreviewFor(UI.lastPreviewID)
    end
    if UI.lastPreviewGroup and UI.lastPreviewGroup ~= wantedGroup
        and type(AD.HidePreviewForGroup) == "function" then
        AD.HidePreviewForGroup(UI.lastPreviewGroup)
    end
    UI.lastPreviewID = nil
    UI.lastPreviewGroup = nil
    if wantedID then
        AD.ShowPreviewFor(wantedID)
        UI.lastPreviewID = wantedID
    elseif wantedGroup and type(AD.ShowPreviewForGroup) == "function" then
        AD.ShowPreviewForGroup(wantedGroup)
        UI.lastPreviewGroup = wantedGroup
    end
end

local function SelectDisplay(id)
    selectedID = id
    selectedGroup = nil
    newGroupPending = false
    SyncPreview()
    if UI.RebuildList then UI.RebuildList() end
    if UI.RebuildDetail then UI.RebuildDetail() end
end

local function SelectGroup(groupName)
    selectedID = nil
    selectedGroup = groupName
    newGroupPending = false
    activeDetailTab = "group"
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
                    if UI.lastPreviewGroup == renameTarget
                        and type(AD.HidePreviewForGroup) == "function" then
                        AD.HidePreviewForGroup(renameTarget)
                        UI.lastPreviewGroup = nil
                    end
                    local ok, reason = AD.RenameGroup(renameTarget, text)
                    if ok then
                        if selectedGroup == renameTarget then selectedGroup = text end
                        AD.Refresh()
                        UI.RebuildList()
                        if UI.RebuildDetail then UI.RebuildDetail() end
                    else
                        if UIErrorsFrame then
                            local message = reason == "collision"
                                and ns.L["A group with that name already exists."]
                                or ns.L["Group names cannot be empty."]
                            UIErrorsFrame:AddMessage(message, 1.0, 0.3, 0.3, 1.0)
                        end
                        SyncPreview()
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

local ShowExportDialog
do
    local dialog, editBox
    ShowExportDialog = function(text)
        if not dialog then
            dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            dialog:SetSize(460, 110)
            dialog:SetPoint("CENTER")
            dialog:SetFrameStrata("TOOLTIP")
            dialog:SetMovable(true)
            dialog:EnableMouse(true)
            dialog:RegisterForDrag("LeftButton")
            dialog:SetScript("OnDragStart", dialog.StartMoving)
            dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
            dialog:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            dialog:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
            dialog:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

            local titleLabel = GUI:CreateLabel(dialog, ns.L["Export String"], 13)
            titleLabel:SetPoint("TOP", 0, -10)
            local hint = GUI:CreateLabel(dialog,
                ns.L["Press Ctrl+C to copy, then Escape to close."], 10, C.textMuted)
            hint:SetPoint("TOP", titleLabel, "BOTTOM", 0, -4)

            local box
            box, editBox = GUI:CreateInlineEditBox(dialog, {
                width = 430,
                onEscapePressed = function(self)
                    self:ClearFocus()
                    dialog:Hide()
                end,
            })
            box:SetPoint("TOP", hint, "BOTTOM", 0, -8)
            -- Read-only: any edit snaps back to the exported string.
            editBox:SetScript("OnTextChanged", function(self, userInput)
                if userInput and dialog._exportText then
                    self:SetText(dialog._exportText)
                    self:HighlightText()
                end
            end)

            local closeBtn = GUI:CreateButton(dialog, ns.L["Close"], 90, 22, function()
                dialog:Hide()
            end)
            closeBtn:SetPoint("BOTTOM", 0, 10)
            UI.exportDialog = dialog
        end
        dialog._exportText = text
        editBox:SetText(text)
        dialog:Show()
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
        row.collapse = GUI:CreateButton(row, "", 16, 16, nil)
        row.collapse:SetPoint("LEFT", 2, 0)
        row.label = GUI:CreateLabel(row, "", 11)
        row.label:SetPoint("LEFT", row.collapse, "RIGHT", 2, 0)
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

local TREE_INDENT = 12

-- Depth-first list of every group record, parents before children, so
-- dropdowns show the tree in path order.
local function AllGroupNames(out, parent)
    out = out or {}
    local children = AD.GroupChildren(parent)
    for i = 1, #children do
        out[#out + 1] = children[i]
        AllGroupNames(out, children[i])
    end
    return out
end

local function PaintGroupHeaderRow(row, y, node)
    local indent = (node.depth or 0) * TREE_INDENT
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", indent, -y)
    row:SetWidth(math.max(LIST_W - 20 - indent, 80))
    local title = node.group == "" and ns.L["Ungrouped"] or node.group
    row.label:SetText(title .. " (" .. node.count .. ")")
    row.collapse:SetText(node.collapsed and ">" or "v")
    row.collapse:SetScript("OnClick", function()
        if node.group ~= "" then
            AD.SetGroupCollapsed(node.group, not node.collapsed)
        end
        UI.RebuildList()
    end)
    local real = node.group ~= ""
    if real and selectedGroup == node.group then
        local ar, ag, ab = AccentRGB()
        row:SetBackdropColor(ar * 0.3, ag * 0.3, ab * 0.3, 0.9)
    else
        row:SetBackdropColor(0.08, 0.14, 0.18, 0.9)
    end
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
                    if selectedGroup == node.group then
                        if UI.lastPreviewGroup and type(AD.HidePreviewForGroup) == "function" then
                            AD.HidePreviewForGroup(UI.lastPreviewGroup)
                        end
                        UI.lastPreviewGroup = nil
                        selectedGroup = nil
                    end
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
        row:SetScript("OnClick", function() SelectGroup(node.group) end)
    else
        row:SetScript("OnClick", nil)
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

local function PaintDisplayRow(row, y, display, depth)
    local indent = math.max((depth or 1) - 1, 0) * TREE_INDENT
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", indent, -y)
    row:SetWidth(math.max(LIST_W - 20 - indent, 80))
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
                onImported = function(summary)
                    AD.Refresh()
                    if UI.RebuildList then UI.RebuildList() end
                    if summary and summary.rootKind == "display" and summary.rootID then
                        SelectDisplay(summary.rootID)
                    elseif summary and summary.rootKind == "group" and summary.rootName then
                        SelectGroup(summary.rootName)
                    end
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
        -- Materialize records for any group a display references by name only
        -- (legacy data, "New group..." commits) so the tree can render it.
        local displays = AD.OrderedDisplays()
        for i = 1, #displays do
            local g = displays[i].group
            if type(g) == "string" and g ~= "" then AD.GetGroup(g, true) end
        end
        local children = {}
        local function FillChildren(parent)
            local list = AD.GroupChildren(parent)
            children[parent or ""] = list
            for i = 1, #list do FillChildren(list[i]) end
        end
        FillChildren(nil)
        local model = ns.QUI_AuraDisplaysOptions.BuildListModel(
            AD.OrderedDisplays(), searchText, AD.GroupCollapsed, { children = children })
        local headerIdx, displayIdx, y = 0, 0, 0
        for i = 1, #model do
            local node = model[i]
            if node.kind == "header" then
                headerIdx = headerIdx + 1
                y = y + PaintGroupHeaderRow(AcquireHeaderRow(listContent, headerIdx), y, node)
            else
                displayIdx = displayIdx + 1
                y = y + PaintDisplayRow(AcquireDisplayRow(listContent, displayIdx), y, node.display, node.depth)
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
    for _, name in ipairs(AllGroupNames()) do
        groupOptions[#groupOptions + 1] = { value = name, text = AD.GroupPathLabel(name) }
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
                    AD.GetGroup(text, true)
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
            { description = ns.L["Displays sharing a group move and flow together using the group's layout settings."] })
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

function ns.QUI_AuraDisplaysOptions._BuildGroupTab(host, ctx, groupName)
    local group = AD.GetGroup(groupName, true)
    if not group then return 1 end
    local L = ns.QUI_SettingsLayoutShared.MakeLayout(host)

    local generalCard = L.sectionAt()
    local nameProxy = { name = groupName, _quiTransientOptionsProxy = true }
    local nameW = GUI:CreateFormEditBox(generalCard.frame, nil, "name", nameProxy, function()
        local newName = nameProxy.name
        if newName == groupName then return end
        if UI.lastPreviewGroup == groupName and type(AD.HidePreviewForGroup) == "function" then
            AD.HidePreviewForGroup(groupName)
            UI.lastPreviewGroup = nil
        end
        local ok, reason = AD.RenameGroup(groupName, newName)
        if ok then
            selectedGroup = newName
            AD.Refresh()
            if UI.RebuildList then UI.RebuildList() end
            if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
        else
            nameProxy.name = groupName
            if UIErrorsFrame then
                local message = reason == "collision"
                    and ns.L["A group with that name already exists."]
                    or ns.L["Group names cannot be empty."]
                UIErrorsFrame:AddMessage(message, 1.0, 0.3, 0.3, 1.0)
            end
            SyncPreview()
        end
    end, nil, { description = ns.L["The group name shown in this list and in Layout Mode."] })
    local enabledW = GUI:CreateFormCheckbox(generalCard.frame, nil, "enabled", group, function()
        AD.Refresh()
        if UI.RebuildList then UI.RebuildList() end
    end, { description = ns.L["Toggle every aura display in this group together."] })
    generalCard.AddRow(
        Shared.BuildSettingRow(generalCard.frame, ns.L["Name"], nameW),
        Shared.BuildSettingRow(generalCard.frame, ns.L["Enabled"], enabledW)
    )

    local parentOptions = { { value = "", text = ns.L["No parent (root group)"] } }
    for _, name in ipairs(AllGroupNames()) do
        if name ~= groupName and not AD.GroupIsAncestor(groupName, name) then
            parentOptions[#parentOptions + 1] = { value = name, text = AD.GroupPathLabel(name) }
        end
    end
    local parentProxy = { parentChoice = AD.GroupParent(groupName) or "",
        _quiTransientOptionsProxy = true }
    local parentW = GUI:CreateFormDropdown(generalCard.frame, nil, parentOptions,
        "parentChoice", parentProxy, function()
            local choice = parentProxy.parentChoice
            local ok, reason = AD.SetGroupParent(groupName,
                choice ~= "" and choice or nil)
            if not ok and UIErrorsFrame then
                local message = reason == "depth"
                    and ns.L["Groups can only be nested a few levels deep."]
                    or ns.L["A group cannot be nested inside itself or its children."]
                UIErrorsFrame:AddMessage(message, 1.0, 0.3, 0.3, 1.0)
                parentProxy.parentChoice = AD.GroupParent(groupName) or ""
            end
            AD.Refresh()
            if UI.RebuildList then UI.RebuildList() end
            if ctx and ctx.RebuildDetail then ctx.RebuildDetail() end
        end, {
            description = ns.L["Nest this group inside another group. Nested groups flow as blocks in the parent's layout; only root groups have Layout Mode movers."],
        })

    local orderRow = CreateFrame("Frame", nil, generalCard.frame)
    orderRow:SetHeight(24)
    local function MoveGroup(delta)
        if AD.MoveGroupWithinParent(groupName, delta) then
            AD.Refresh()
            if UI.RebuildList then UI.RebuildList() end
        end
    end
    local upBtn = GUI:CreateButton(orderRow, ns.L["Move Up"], 80, 22,
        function() MoveGroup(-1) end)
    upBtn:SetPoint("LEFT", 0, 0)
    local downBtn = GUI:CreateButton(orderRow, ns.L["Move Down"], 80, 22,
        function() MoveGroup(1) end)
    downBtn:SetPoint("LEFT", upBtn, "RIGHT", 6, 0)

    generalCard.AddRow(
        Shared.BuildSettingRow(generalCard.frame, ns.L["Parent Group"], parentW),
        Shared.BuildSettingRow(generalCard.frame, ns.L["Sibling Order"], orderRow)
    )
    L.closeSection(generalCard)

    local layoutCard = L.sectionAt()
    local growW = GUI:CreateFormDropdown(layoutCard.frame, nil, {
        { value = "RIGHT", text = ns.L["Right"] },
        { value = "LEFT", text = ns.L["Left"] },
        { value = "CENTER_H", text = ns.L["Center (H)"] },
        { value = "DOWN", text = ns.L["Down"] },
        { value = "UP", text = ns.L["Up"] },
        { value = "CENTER_V", text = ns.L["Center (V)"] },
    }, "growDirection", group, AD.Refresh, {
        description = ns.L["Direction displays are added from the group anchor. Center options alternate around the anchor."],
    })
    local alignW = GUI:CreateFormDropdown(layoutCard.frame, nil, {
        { value = "START", text = ns.L["Start"] },
        { value = "CENTER", text = ns.L["Center"] },
        { value = "END", text = ns.L["End"] },
    }, "alignment", group, AD.Refresh, {
        description = ns.L["Alignment on the axis perpendicular to the grow direction."],
    })
    layoutCard.AddRow(
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Grow Direction"], growW),
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Cross-axis Alignment"], alignW)
    )

    local spacingW = GUI:CreateFormSlider(layoutCard.frame, nil, 0, 100, 1,
        "spacing", group, AD.Refresh, { deferOnDrag = true },
        { description = ns.L["Pixel gap between aura displays in this group."] })
    local scaleW = GUI:CreateFormSlider(layoutCard.frame, nil, 0.25, 3, 0.05,
        "scale", group, AD.Refresh, { deferOnDrag = true, precision = 2 },
        { description = ns.L["Scale multiplier applied to the entire group."] })
    layoutCard.AddRow(
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Spacing"], spacingW),
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Scale"], scaleW)
    )

    local widthW = GUI:CreateFormSlider(layoutCard.frame, nil, 0, 400, 1,
        "itemWidth", group, AD.Refresh, { deferOnDrag = true },
        { description = ns.L["Width reserved for every display. 0 uses each display's natural width."] })
    local heightW = GUI:CreateFormSlider(layoutCard.frame, nil, 0, 400, 1,
        "itemHeight", group, AD.Refresh, { deferOnDrag = true },
        { description = ns.L["Height reserved for every display. 0 uses each display's natural height."] })
    layoutCard.AddRow(
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Item Width"], widthW),
        Shared.BuildSettingRow(layoutCard.frame, ns.L["Item Height"], heightW)
    )
    L.closeSection(layoutCard)

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
            durationDecimals    = true,
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
        if selectedGroup then
            local groupName = selectedGroup
            GUI:ShowConfirmation({
                title = ns.L["Delete Group?"],
                message = string.format(ns.L["Delete '%1$s'?"], groupName),
                warningText = ns.L["Displays in this group will become ungrouped."],
                acceptText = ns.L["Delete"],
                cancelText = ns.L["Cancel"],
                isDestructive = true,
                onAccept = function()
                    if UI.lastPreviewGroup and type(AD.HidePreviewForGroup) == "function" then
                        AD.HidePreviewForGroup(UI.lastPreviewGroup)
                    end
                    UI.lastPreviewGroup = nil
                    AD.DeleteGroup(groupName)
                    selectedGroup = nil
                    AD.Refresh()
                    if UI.RebuildList then UI.RebuildList() end
                    if UI.RebuildDetail then UI.RebuildDetail() end
                end,
            })
            return
        end
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

    local exportBtn = GUI:CreateButton(header, ns.L["Export"], 70, 22, function()
        local Share = ns.QUI_AuraDisplayShare
        if not Share then return end
        local str, err
        if selectedID then
            str, err = Share.ExportDisplayString(selectedID)
        elseif selectedGroup then
            str, err = Share.ExportGroupString(selectedGroup)
        end
        if str then
            ShowExportDialog(str)
        elseif err and UIErrorsFrame then
            UIErrorsFrame:AddMessage(err, 1.0, 0.3, 0.3, 1.0)
        end
    end)
    exportBtn:SetPoint("RIGHT", dupBtn, "LEFT", -4, 0)

    local previewBtn
    local function PaintPreviewButton()
        previewBtn:SetText(previewEnabled and ns.L["Preview: On"] or ns.L["Preview: Off"])
    end
    previewBtn = GUI:CreateButton(header, "", 90, 22, function()
        previewEnabled = not previewEnabled
        PaintPreviewButton()
        SyncPreview()
    end)
    previewBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
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
    local GROUP_TABS = {
        { key = "group", label = ns.L["Group Layout"] },
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
        local groupName = selectedGroup
        if groupName and not AD.GetGroup(groupName, false) then
            selectedGroup = nil
            groupName = nil
        end
        if groupName then
            activeDetailTab = "group"
        elseif activeDetailTab == "group" then
            activeDetailTab = "general"
        end
        title:SetText(groupName or (display and (display.name or display.id) or ""))
        deleteBtn:SetShown(display ~= nil or groupName ~= nil)
        dupBtn:SetShown(display ~= nil)
        exportBtn:SetShown(display ~= nil or groupName ~= nil)
        previewBtn:SetShown(display ~= nil or groupName ~= nil)
        if paint then
            paint(groupName and GROUP_TABS or TABS, activeDetailTab, function(key)
                activeDetailTab = key
                UI.RebuildDetail()
            end)
        end
        if not display and not groupName then
            local hint = GUI:CreateLabel(tabContent,
                ns.L["Select a display or group on the left, or create a display."], 11, C.textMuted)
            hint:SetPoint("TOPLEFT", 4, -12)
            tabContent:SetHeight(60)
            return
        end
        local host = CreateFrame("Frame", nil, tabContent)
        host:SetPoint("TOPLEFT")
        host:SetPoint("TOPRIGHT")
        host:SetHeight(1)
        local detailContext = { RebuildDetail = UI.RebuildDetail,
            ResizeTab = function(h) tabContent:SetHeight(math.max(h, 1)) end }
        local height
        if groupName then
            height = ns.QUI_AuraDisplaysOptions._BuildGroupTab(host, detailContext, groupName)
        else
            local builder = BUILDERS[activeDetailTab] or BUILDERS.general
            height = builder(host, detailContext, display)
        end
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
    if selectedGroup and #AD.GroupMembers(selectedGroup) == 0 then selectedGroup = nil end

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
        if UI.lastPreviewGroup and type(AD.HidePreviewForGroup) == "function" then
            AD.HidePreviewForGroup(UI.lastPreviewGroup)
            UI.lastPreviewGroup = nil
        end
        if UI.groupRenameField then UI.groupRenameField:Hide() end
        if UI.quickCreatePopup then UI.quickCreatePopup:Hide() end
        if UI.exportDialog then UI.exportDialog:Hide() end
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
