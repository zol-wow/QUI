local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
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

local CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local ROLE_TOKENS = { "TANK", "HEALER", "DAMAGER" }

local selectedID = nil

local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function Refresh()
    if AD and type(AD.Refresh) == "function" then AD.Refresh() end
end

local function ScheduleSectionReflow(ctx)
    if type(ctx) ~= "table" or type(ctx.RerenderFeature) ~= "function" then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            ctx:RerenderFeature()
        end)
    else
        ctx:RerenderFeature()
    end
end

local rebuildPage = function() end

local function RefreshAndRebuild()
    Refresh()
    rebuildPage()
end

local function GroupedDisplays()
    local groups, orderOfGroups = {}, {}
    local displays = AD.OrderedDisplays()
    for i = 1, #displays do
        local display = displays[i]
        local key = display.group or ""
        local bucket = groups[key]
        if not bucket then
            bucket = {}
            groups[key] = bucket
            orderOfGroups[#orderOfGroups + 1] = key
        end
        bucket[#bucket + 1] = display
    end
    return groups, orderOfGroups
end

ns.QUI_AuraDisplaysOptions = {}

local function BuildDisplayRow(L, parent, display)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)

    local enable = GUI:CreateFormCheckbox(row, nil, "enabled", display, RefreshAndRebuild,
        { description = ns.L["Show this display in the game world."] })
    enable:SetPoint("LEFT", row, "LEFT", 0, 0)

    local selectBtn = GUI:CreateButton(row, display.name or display.id, 190, 22, function()
        selectedID = display.id
        rebuildPage()
    end, selectedID == display.id and "primary" or nil)
    selectBtn:SetPoint("LEFT", enable, "RIGHT", 8, 0)

    local up = GUI:CreateButton(row, ns.L["Up"], 40, 22, function()
        if AD.MoveDisplayWithinGroup(display.id, -1) then RefreshAndRebuild() end
    end)
    up:SetPoint("LEFT", selectBtn, "RIGHT", 8, 0)

    local down = GUI:CreateButton(row, ns.L["Down"], 50, 22, function()
        if AD.MoveDisplayWithinGroup(display.id, 1) then RefreshAndRebuild() end
    end)
    down:SetPoint("LEFT", up, "RIGHT", 4, 0)

    local duplicate = GUI:CreateButton(row, ns.L["Duplicate"], 80, 22, function()
        local copy = AD.DuplicateDisplay(display.id, ns.L["%s (copy)"]:format(display.name or display.id))
        if copy then
            selectedID = copy.id
            RefreshAndRebuild()
        end
    end)
    duplicate:SetPoint("LEFT", down, "RIGHT", 4, 0)

    local delete = GUI:CreateButton(row, ns.L["Delete"], 70, 22, function()
        GUI:ShowConfirmation({
            title = ns.L["Delete Display?"],
            message = string.format(ns.L["Delete '%1$s'?"], display.name or display.id),
            warningText = ns.L["This cannot be undone."],
            acceptText = ns.L["Delete"],
            cancelText = ns.L["Cancel"],
            isDestructive = true,
            onAccept = function()
                AD.UnregisterLayoutElement(display.id)
                AD.DeleteDisplay(display.id)
                if selectedID == display.id then selectedID = nil end
                RefreshAndRebuild()
            end,
        })
    end)
    delete:SetPoint("LEFT", duplicate, "RIGHT", 4, 0)

    L.placeCustom(row, 30)
end

local function BuildGroupHeader(L, parent, groupKey)
    if groupKey == "" then
        L.headerAt(ns.L["Ungrouped"])
        return true
    end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)

    local collapsed = AD.GroupCollapsed(groupKey)
    local toggle = GUI:CreateButton(row, collapsed and ns.L["Expand"] or ns.L["Collapse"], 80, 22, function()
        AD.SetGroupCollapsed(groupKey, not collapsed)
        rebuildPage()
    end)
    toggle:SetPoint("LEFT", row, "LEFT", 0, 0)

    local label = GUI:CreateLabel(row, groupKey, 12, C.text)
    label:SetPoint("LEFT", toggle, "RIGHT", 8, 0)

    local enabled = AD.GroupEnabled(groupKey)
    local enableBtn = GUI:CreateButton(row, enabled and ns.L["Disable Group"] or ns.L["Enable Group"], 120, 22, function()
        AD.SetGroupEnabled(groupKey, not enabled)
        RefreshAndRebuild()
    end)
    enableBtn:SetPoint("LEFT", label, "RIGHT", 12, 0)

    local deleteBtn = GUI:CreateButton(row, ns.L["Delete Group"], 110, 22, function()
        GUI:ShowConfirmation({
            title = ns.L["Delete Group?"],
            message = string.format(ns.L["Delete '%1$s'?"], groupKey),
            warningText = ns.L["This cannot be undone."],
            acceptText = ns.L["Delete"],
            cancelText = ns.L["Cancel"],
            isDestructive = true,
            onAccept = function()
                AD.DeleteGroup(groupKey)
                RefreshAndRebuild()
            end,
        })
    end)
    deleteBtn:SetPoint("LEFT", enableBtn, "RIGHT", 4, 0)

    L.placeCustom(row, 30)
    return not collapsed
end

function ns.QUI_AuraDisplaysOptions.BuildAuraDisplaysContent(content, ctx)
    AD = ns.QUI_AuraDisplays
    if not AD or type(AD.OrderedDisplays) ~= "function" then
        local noData = GUI:CreateLabel(content,
            ns.L["Aura display settings are not available. Please reload the UI."], 12, C.textMuted)
        noData:SetPoint("TOPLEFT", PAD, -20)
        content:SetHeight(80)
        return
    end

    rebuildPage = function() ScheduleSectionReflow(ctx) end

    if selectedID and not AD.GetDisplay(selectedID) then
        selectedID = nil
    end

    local L = MakeLayout(content)

    L.headerAt(ns.L["Aura Displays"])

    local addRow = CreateFrame("Frame", nil, content)
    addRow:SetHeight(26)
    local addBtn = GUI:CreateButton(addRow, ns.L["Add Display"], 130, 22, function()
        local display = AD.NewDisplay(ns.L["New Display"])
        if display then
            selectedID = display.id
            RefreshAndRebuild()
        end
    end)
    addBtn:SetPoint("LEFT", addRow, "LEFT", 0, 0)

    local groupBox = GUI:CreateInlineEditBox(addRow, {
        width = 160,
        onEnterPressed = function(self)
            local text = self:GetText()
            if type(text) == "string" and text ~= "" then
                AD.SetGroupEnabled(text, true)
                self:SetText("")
                self:ClearFocus()
                RefreshAndRebuild()
            end
        end,
    })
    groupBox:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)

    local groupBoxLabel = GUI:CreateLabel(addRow, ns.L["New group name"], 11, C.textMuted)
    groupBoxLabel:SetPoint("LEFT", groupBox, "RIGHT", 8, 0)

    L.placeCustom(addRow, 30)

    local groups, orderOfGroups = GroupedDisplays()
    if #orderOfGroups == 0 then
        local empty = GUI:CreateLabel(content,
            ns.L["No aura displays yet. Add one to place a custom aura frame on your screen."],
            11, C.textMuted)
        local wrap = CreateFrame("Frame", nil, content)
        wrap:SetHeight(24)
        empty:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
        empty:SetPoint("RIGHT", wrap, "RIGHT", 0, 0)
        empty:SetJustifyH("LEFT")
        L.placeCustom(wrap, 26)
    end

    for i = 1, #orderOfGroups do
        local groupKey = orderOfGroups[i]
        local expanded = BuildGroupHeader(L, content, groupKey)
        if expanded then
            local bucket = groups[groupKey]
            for j = 1, #bucket do
                BuildDisplayRow(L, content, bucket[j])
            end
        end
    end

    ns.QUI_AuraDisplaysOptions._BuildDetail(L, content, ctx, selectedID and AD.GetDisplay(selectedID) or nil)

    L.finish()
end

local function BuildIdentityCard(L, display)
    local card = L.sectionAt()

    local nameW = GUI:CreateFormEditBox(card.frame, nil, "name", display, function()
        AD.RenameDisplay(display.id, display.name)
        RefreshAndRebuild()
    end, nil, { description = ns.L["The name shown in this list and in Layout Mode."] })

    local groupW = GUI:CreateFormEditBox(card.frame, nil, "group", display, function()
        if display.group == "" then display.group = nil end
        RefreshAndRebuild()
    end, nil, { description = ns.L["Optional group name. Displays sharing a name are listed and toggled together."] })

    card.AddRow(
        Shared.BuildSettingRow(card.frame, ns.L["Name"], nameW),
        Shared.BuildSettingRow(card.frame, ns.L["Group"], groupW)
    )
    L.closeSection(card)
end

local function BuildUnitCard(L, display)
    local card = L.sectionAt()

    local current = display.unitMode == "cotank" and "__cotank"
        or display.unitMode == "name" and "__name"
        or display.unit

    local proxy = { unitChoice = current, _quiTransientOptionsProxy = true }
    local unitW = GUI:CreateFormDropdown(card.frame, nil, UNIT_OPTIONS, "unitChoice", proxy,
        function()
            local choice = proxy.unitChoice
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
            RefreshAndRebuild()
        end,
        { description = ns.L["Which unit this display watches. Co-Tank follows the first other tank in your group."] })

    card.AddRow(Shared.BuildSettingRow(card.frame, ns.L["Unit"], unitW))

    if display.unitMode == "name" then
        local nameW = GUI:CreateFormEditBox(card.frame, nil, "unit", display, RefreshAndRebuild,
            nil, { description = ns.L["Character name, optionally Name-Realm. Matched against your current group."] })
        card.AddRow(Shared.BuildSettingRow(card.frame, ns.L["Player Name"], nameW))
    end

    L.closeSection(card)
end

local function ParseIDList(text)
    local set = {}
    if type(text) ~= "string" then return set end
    for chunk in text:gmatch("[^,%s]+") do
        if chunk:match("^%d+$") then
            set[tonumber(chunk)] = true
        end
    end
    return set
end

local function FormatIDList(set)
    local ids = {}
    for id, on in pairs(set or {}) do
        if on then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return table.concat(ids, ", ")
end

local function AddPairedRows(card, rows)
    local i = 1
    while i <= #rows do
        local left, right = rows[i], rows[i + 1]
        if right then
            card.AddRow(left, right)
            i = i + 2
        else
            card.AddRow(left)
            i = i + 1
        end
    end
end

local function BuildLoadCard(L, display)
    display.load = display.load or {}
    display.load.classes = display.load.classes or {}
    display.load.specs = display.load.specs or {}
    display.load.roles = display.load.roles or {}
    display.load.encounters = display.load.encounters or {}

    local card = L.sectionAt()

    local classRows = {}
    for i = 1, #CLASS_TOKENS do
        local token = CLASS_TOKENS[i]
        local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
        local widget = GUI:CreateFormCheckbox(card.frame, nil, token, display.load.classes, Refresh,
            { description = ns.L["Only load this display on the checked classes. No class checked means every class."] })
        classRows[#classRows + 1] = Shared.BuildSettingRow(card.frame, label, widget)
    end
    AddPairedRows(card, classRows)

    local roleRows = {}
    local ROLE_LABELS = { TANK = TANK, HEALER = HEALER, DAMAGER = DAMAGER }
    for i = 1, #ROLE_TOKENS do
        local token = ROLE_TOKENS[i]
        local widget = GUI:CreateFormCheckbox(card.frame, nil, token, display.load.roles, Refresh,
            { description = ns.L["Only load this display in the checked roles. No role checked means every role."] })
        roleRows[#roleRows + 1] = Shared.BuildSettingRow(card.frame, ROLE_LABELS[token] or token, widget)
    end
    AddPairedRows(card, roleRows)

    L.closeSection(card)
end

local function BuildSpecEncounterCard(L, display)
    local card = L.sectionAt()

    local specsW = GUI:CreateInlineEditBox(card.frame, {
        width = 260,
        text = FormatIDList(display.load.specs),
        onEnterPressed = function(self)
            display.load.specs = ParseIDList(self:GetText())
            self:SetText(FormatIDList(display.load.specs))
            self:ClearFocus()
            Refresh()
        end,
    })
    card.AddRow(Shared.BuildSettingRow(card.frame, ns.L["Specs"], specsW,
        ns.L["Comma-separated specialization IDs. Empty means every spec."]))

    local encountersW = GUI:CreateInlineEditBox(card.frame, {
        width = 260,
        text = FormatIDList(display.load.encounters),
        onEnterPressed = function(self)
            display.load.encounters = ParseIDList(self:GetText())
            self:SetText(FormatIDList(display.load.encounters))
            self:ClearFocus()
            Refresh()
        end,
    })
    card.AddRow(Shared.BuildSettingRow(card.frame, ns.L["Encounters"], encountersW,
        ns.L["Comma-separated encounter journal IDs. Empty means every encounter."]))

    L.closeSection(card)
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

function ns.QUI_AuraDisplaysOptions._BuildDetail(L, content, ctx, display)
    if not display then return end

    E.EnsureSeeded(display.auras, AD.DefaultBucket)

    BuildIdentityCard(L, display)
    BuildUnitCard(L, display)

    L.headerAt(ns.L["Load Conditions"])
    BuildLoadCard(L, display)
    BuildSpecEncounterCard(L, display)

    if AD.UnitPolarityFor(display) == "hostile" and HasHelpfulTrackedElement(display) then
        local wrap = CreateFrame("Frame", nil, content)
        wrap:SetHeight(36)
        local warn = GUI:CreateLabel(wrap,
            ns.L["Blizzard does not allow tracking specific buffs by spell on units you cannot assist, so a tracked buff list on an enemy unit will always be empty. Use a filter strip instead, or point this display at a friendly unit."],
            11, C.warning)
        warn:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
        warn:SetPoint("RIGHT", wrap, "RIGHT", 0, 0)
        warn:SetJustifyH("LEFT")
        warn:SetWordWrap(true)
        L.placeCustom(wrap, 40)
    end

    L.headerAt(ns.L["Auras"])

    local AurasEditor = ns.QUI_AuraElementsEditor
    if not AurasEditor or type(AurasEditor.RenderAuras) ~= "function" then return end

    local W = ns.QUI_AuraWizard
    local specID = W and type(W.PlayerSpecID) == "function" and W.PlayerSpecID() or nil
    local bucketKey = (W and type(W.ActiveBucketKey) == "function")
        and W.ActiveBucketKey(display.auras.elements, specID) or "*"

    local editorHost = CreateFrame("Frame", nil, content)
    editorHost:SetHeight(1)

    local mounted, previousHeight = false, nil
    local height = AurasEditor.RenderAuras(editorHost, display.auras, bucketKey, RefreshAndRebuild, {
        capabilities = {
            elementTypes      = { filterStrip = true, tracked = true },
            trackedDisplayTypes = { icon = true, square = true, bar = true },
            allowSpecOverride = true,
            roleGate          = false,
            cancelEligible    = false,
            unitPolarity      = AD.UnitPolarityFor(display),
            defaultBucketFn   = AD.DefaultBucket,
        },
        onLayoutChanged = function(newHeight)
            if type(newHeight) ~= "number" then return end
            local previous = previousHeight
            previousHeight = newHeight
            if not mounted or previous == nil or previous == newHeight then return end
            local sectionHeight = ctx and ctx.runtime and ctx.runtime.sectionHeights
                and ctx.runtime.sectionHeights.settings
            if ctx and type(ctx.ResizeSection) == "function" and type(sectionHeight) == "number" then
                ctx:ResizeSection("settings", sectionHeight + (newHeight - previous))
            end
        end,
    })
    mounted = true
    height = (type(height) == "number" and height > 0) and height
        or (editorHost:GetHeight() or 1)
    L.placeCustom(editorHost, math.max(1, height))
end
