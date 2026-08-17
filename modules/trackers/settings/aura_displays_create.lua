local _, ns = ...
local QUI = QUI
local GUI = QUI and QUI.GUI
local C = (GUI and GUI.Colors) or {}

-- The "New Display" dialog: three doors into Aura Displays.
--   Templates — curated starter displays, one click, role-relevant first.
--   Guided    — a 4-step wizard: goal → spells/filter → look → where & when.
--   Custom    — the original quick-create form for power users.
-- All three call back into the content page via opts.onCreated(display).

local Create = {}
ns.QUI_AuraDisplaysCreate = Create

local DIALOG_W, DIALOG_H = 560, 470
local CONTENT_TOP = 78
local BROWSE_PREFIX = "adCreate"

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

local ZONE_ROWS = {
    { "TOPLEFT", "TOP", "TOPRIGHT" },
    { "LEFT", "CENTER", "RIGHT" },
    { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
}

local dialog
local callbacks = {}
local state

local function Templates()
    return ns.QUI_AuraDisplayTemplates
end

local function SpellListAPI()
    return ns.QUI_AuraSpellList
end

local function ResetState()
    state = {
        tab = "templates",
        wizardStep = 1,
        wizard = {
            goalID = nil,
            spells = {},
            whatToShow = nil,
            displayType = "icon",
            iconSize = 32,
            unitChoice = nil,
            position = nil,
            loadChoice = "always",
            pendingSpellID = nil,
            pendingSpellName = nil,
        },
        custom = { kind = "tracked", spellID = nil, spellName = nil,
            unitChoice = "player", _quiTransientOptionsProxy = true },
    }
end

local function AccentRGB()
    local accent = C.accent
    if type(accent) == "table" then
        return accent[1] or 0.2, accent[2] or 0.6, accent[3] or 1
    end
    return 0.2, 0.6, 1
end

local function PaintChoice(btn, on)
    local ar, ag, ab = AccentRGB()
    if on then
        btn:SetBackdropColor(ar * 0.25, ag * 0.25, ab * 0.25, 0.9)
        btn:SetBackdropBorderColor(ar, ag, ab, 1)
    else
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
end

local function MakeChoiceButton(parent, w, h, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w, h)
    btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    btn.label = GUI:CreateLabel(btn, text, 11)
    btn.label:SetPoint("CENTER")
    PaintChoice(btn, false)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function ClassDisplayName()
    if type(UnitClass) ~= "function" then return nil end
    local ok, name = ns.SafeCall("best-effort-style", UnitClass, "player")
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

local function SpecDisplayName()
    local H = ns.Helpers
    local specID = H and type(H.GetCurrentSpecID) == "function" and H.GetCurrentSpecID() or nil
    if specID and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID then
        local ok, _, name = ns.SafeCall("best-effort-style",
            C_SpecializationInfo.GetSpecializationInfoByID, specID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

local function CloseBrowse()
    local SpellList = SpellListAPI()
    if SpellList and SpellList.CloseBrowsePopup then
        SpellList.CloseBrowsePopup(BROWSE_PREFIX)
    end
end

local function Finish(display)
    if dialog then dialog:Hide() end
    if display and type(callbacks.onCreated) == "function" then
        callbacks.onCreated(display)
    end
end

local Rebuild

-- Templates tab --------------------------------------------------------------

local function BuildTemplatesTab(content)
    local T = Templates()
    if not T then return end
    local y = 0
    local hint = GUI:CreateLabel(content,
        ns.L["Start from a working setup — everything stays editable afterwards."],
        10, C.textMuted)
    hint:SetPoint("TOPLEFT", 2, -y)
    y = y + 20

    local list = T.List()
    for i = 1, #list do
        local tpl = list[i]
        local row = CreateFrame("Button", nil, content, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(40)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        row:SetBackdropColor(0.09, 0.09, 0.11, 0.9)
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(T.SpellIcon(tpl.iconSpell))

        local name = GUI:CreateLabel(row, tpl.name, 12)
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)

        local desc = GUI:CreateLabel(row, tpl.desc, 10, C.textMuted)
        desc:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
        desc:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(false)

        local addBtn = GUI:CreateButton(row, ns.L["Add"], 54, 20, function()
            Finish(T.Install(tpl.id))
        end, "primary")
        addBtn:SetPoint("RIGHT", -6, 0)

        row:SetScript("OnClick", function()
            Finish(T.Install(tpl.id))
        end)
        row:SetScript("OnEnter", function()
            row:SetBackdropBorderColor(AccentRGB())
        end)
        row:SetScript("OnLeave", function()
            row:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        end)

        y = y + 43
    end
end

-- Guided tab -----------------------------------------------------------------

local function WizardHeader(content, question)
    local step = GUI:CreateLabel(content,
        string.format(ns.L["Step %1$d of %2$d"], state.wizardStep, 4), 10, C.textMuted)
    step:SetPoint("TOPLEFT", 2, 0)
    local title = GUI:CreateLabel(content, question, 13)
    title:SetPoint("TOPLEFT", 2, -16)
    return 42
end

local function BuildWizardStep1(content)
    local T = Templates()
    local y = WizardHeader(content, ns.L["What do you want to track?"])
    for i = 1, #T.GOALS do
        local goal = T.GOALS[i]
        local row = CreateFrame("Button", nil, content, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(38)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        row:SetBackdropColor(0.09, 0.09, 0.11, 0.9)
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        local name = GUI:CreateLabel(row, goal.name, 12)
        name:SetPoint("TOPLEFT", 10, -5)
        local desc = GUI:CreateLabel(row, goal.desc, 10, C.textMuted)
        desc:SetPoint("BOTTOMLEFT", 10, 5)

        row:SetScript("OnEnter", function()
            row:SetBackdropBorderColor(AccentRGB())
        end)
        row:SetScript("OnLeave", function()
            row:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        end)
        row:SetScript("OnClick", function()
            local w = state.wizard
            w.goalID = goal.id
            w.unitChoice = goal.unitChoice
            w.position = goal.position
            w.whatToShow = goal.whatToShow
            state.wizardStep = 2
            Rebuild()
        end)
        y = y + 41
    end
end

local function BuildWizardStep2(content)
    local T = Templates()
    local w = state.wizard
    local goal = T.GoalByID(w.goalID)
    if not goal then state.wizardStep = 1 Rebuild() return end

    if goal.kind == "tracked" then
        local y = WizardHeader(content, ns.L["Which spell(s)?"])
        local P = ns.QUI_AuraDisplayPickers
        local SpellList = SpellListAPI()

        local input = P.CreateSpellEchoInput(content, 220, function(spellID, spellName)
            w.pendingSpellID = spellID
            w.pendingSpellName = spellName
        end)
        input:SetPoint("TOPLEFT", 2, -y)

        local function AddSpell(spellID)
            if not spellID then return end
            for i = 1, #w.spells do
                if w.spells[i] == spellID then return end
            end
            w.spells[#w.spells + 1] = spellID
            input.editBox:SetText("")
            w.pendingSpellID = nil
            Rebuild()
        end

        local addBtn = GUI:CreateButton(content, ns.L["Add"], 54, 22, function()
            AddSpell(w.pendingSpellID)
        end, "primary")
        addBtn:SetPoint("TOPLEFT", 230, -y)

        if SpellList and SpellList.ToggleBrowsePopup then
            local browseBtn = GUI:CreateButton(content, ns.L["Browse"], 70, 22, function()
                SpellList.ToggleBrowsePopup(BROWSE_PREFIX .. ":wizard", {
                    title = ns.L["Add Tracked Spells"],
                    presets = (SpellList.GetDefaultPresets and SpellList.GetDefaultPresets()) or {},
                    isSelected = function(id)
                        for i = 1, #w.spells do
                            if w.spells[i] == id then return true end
                        end
                        return false
                    end,
                    onToggle = function(id)
                        for i = #w.spells, 1, -1 do
                            if w.spells[i] == id then
                                table.remove(w.spells, i)
                                Rebuild()
                                return
                            end
                        end
                        AddSpell(id)
                    end,
                    onClose = function() end,
                })
            end)
            browseBtn:SetPoint("TOPLEFT", 290, -y)
        end
        y = y + 56

        for i = 1, #w.spells do
            local spellID = w.spells[i]
            local row = CreateFrame("Frame", nil, content)
            row:SetPoint("TOPLEFT", 2, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row:SetHeight(20)
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(T.SpellIcon(spellID))
            local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
                or (ns.L["Spell"] .. " " .. tostring(spellID))
            local label = GUI:CreateLabel(row, name .. "  |cFF808080(" .. spellID .. ")|r", 11)
            label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            local remove = GUI:CreateButton(row, ns.L["X"], 18, 16, function()
                table.remove(w.spells, i)
                Rebuild()
            end)
            remove:SetPoint("LEFT", label, "RIGHT", 8, 0)
            y = y + 22
        end

        local hint = GUI:CreateLabel(content,
            ns.L["You can add or change spells later in the editor."], 10, C.textMuted)
        hint:SetPoint("TOPLEFT", 2, -y - 6)
    else
        local y = WizardHeader(content, ns.L["Which auras?"])
        local proxy = { whatToShow = w.whatToShow or goal.whatToShow or "all",
            _quiTransientOptionsProxy = true }
        local dropdown = GUI:CreateFormDropdown(content, nil,
            T.WhatToShowOptions(goal.auraType), "whatToShow", proxy, function()
                w.whatToShow = proxy.whatToShow
            end, {
                description = ns.L["Pick what this strip shows in plain terms. QUI writes the underlying filters."],
            })
        dropdown:SetPoint("TOPLEFT", 2, -y)
        local hint = GUI:CreateLabel(content,
            ns.L["Fine-grained filters (whitelist, dispel types, sorting) live in the editor."],
            10, C.textMuted)
        hint:SetPoint("TOPLEFT", 2, -y - 40)
    end
end

local function BuildWizardStep3(content)
    local T = Templates()
    local w = state.wizard
    local goal = T.GoalByID(w.goalID)
    if not goal then state.wizardStep = 1 Rebuild() return end
    local y = WizardHeader(content, ns.L["How should it look?"])

    if goal.kind == "tracked" then
        local typeLabel = GUI:CreateLabel(content, ns.L["Display Type"], 10, C.textMuted)
        typeLabel:SetPoint("TOPLEFT", 2, -y)
        y = y + 16
        local types = {
            { value = "icon", text = ns.L["Icon"] },
            { value = "bar", text = ns.L["Bar"] },
            { value = "square", text = ns.L["Colored Square"] },
        }
        local buttons = {}
        local x = 2
        for i = 1, #types do
            local opt = types[i]
            local btn
            btn = MakeChoiceButton(content, 120, 26, opt.text, function()
                w.displayType = opt.value
                for v, b in pairs(buttons) do PaintChoice(b, v == opt.value) end
            end)
            btn:SetPoint("TOPLEFT", x, -y)
            PaintChoice(btn, (w.displayType or "icon") == opt.value)
            buttons[opt.value] = btn
            x = x + 126
        end
        y = y + 38
    end

    local sizeLabel = GUI:CreateLabel(content, ns.L["Size"], 10, C.textMuted)
    sizeLabel:SetPoint("TOPLEFT", 2, -y)
    y = y + 16
    local sizeButtons = {}
    local x = 2
    for i = 1, #T.SIZE_PRESETS do
        local preset = T.SIZE_PRESETS[i]
        local btn = MakeChoiceButton(content, 120, 26,
            preset.label .. "  (" .. preset.size .. "px)", function()
                w.iconSize = preset.size
                for s, b in pairs(sizeButtons) do PaintChoice(b, s == preset.size) end
            end)
        btn:SetPoint("TOPLEFT", x, -y)
        PaintChoice(btn, (w.iconSize or 32) == preset.size)
        sizeButtons[preset.size] = btn
        x = x + 126
    end
end

local function BuildWizardStep4(content)
    local T = Templates()
    local w = state.wizard
    local goal = T.GoalByID(w.goalID)
    if not goal then state.wizardStep = 1 Rebuild() return end
    local y = WizardHeader(content, ns.L["Where and when?"])

    local nameLabel = GUI:CreateLabel(content, ns.L["Name"], 10, C.textMuted)
    nameLabel:SetPoint("TOPLEFT", 2, -y)
    local nameBox, nameEdit = GUI:CreateInlineEditBox(content, { width = 250 })
    nameBox:SetPoint("TOPLEFT", 2, -y - 14)
    local defaultName = w.spells and w.spells[1]
        and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(w.spells[1])
        or goal.name
    nameEdit:SetText(w.name or defaultName or "")
    dialog._wizardNameEdit = nameEdit

    local unitLabel = GUI:CreateLabel(content, ns.L["Unit"], 10, C.textMuted)
    unitLabel:SetPoint("TOPLEFT", 280, -y)
    local unitProxy = { unitChoice = w.unitChoice or goal.unitChoice,
        _quiTransientOptionsProxy = true }
    local unitDrop = GUI:CreateFormDropdown(content, nil, UNIT_OPTIONS, "unitChoice",
        unitProxy, function()
            w.unitChoice = unitProxy.unitChoice
        end, {
            description = ns.L["Which unit this display watches. Co-Tank follows the first other tank in your group."],
        })
    unitDrop:SetPoint("TOPLEFT", 280, -y - 14)
    y = y + 58

    local posLabel = GUI:CreateLabel(content, ns.L["Screen position"], 10, C.textMuted)
    posLabel:SetPoint("TOPLEFT", 2, -y)
    local posHint = GUI:CreateLabel(content,
        ns.L["A starting spot — fine-tune anytime in Layout Mode."], 10, C.textMuted)
    posHint:SetPoint("TOPLEFT", 130, -y)
    y = y + 16

    local zoneButtons = {}
    for r = 1, #ZONE_ROWS do
        for c = 1, #ZONE_ROWS[r] do
            local zone = ZONE_ROWS[r][c]
            local btn = MakeChoiceButton(content, 34, 22, "", function()
                w.position = zone
                for z, b in pairs(zoneButtons) do PaintChoice(b, z == zone) end
            end)
            btn:SetPoint("TOPLEFT", 2 + (c - 1) * 38, -y - (r - 1) * 26)
            PaintChoice(btn, (w.position or goal.position) == zone)
            zoneButtons[zone] = btn
        end
    end

    local loadLabel = GUI:CreateLabel(content, ns.L["Load"], 10, C.textMuted)
    loadLabel:SetPoint("TOPLEFT", 200, -y)
    local loadChoices = {
        { key = "always", text = ns.L["Always"] },
        { key = "class", text = ClassDisplayName()
            and string.format(ns.L["Only %s"], ClassDisplayName()) or ns.L["My class only"] },
        { key = "spec", text = SpecDisplayName()
            and string.format(ns.L["Only %s"], SpecDisplayName()) or ns.L["My spec only"] },
    }
    local loadButtons = {}
    for i = 1, #loadChoices do
        local choice = loadChoices[i]
        local btn = MakeChoiceButton(content, 110, 22, choice.text, function()
            w.loadChoice = choice.key
            for k, b in pairs(loadButtons) do PaintChoice(b, k == choice.key) end
        end)
        btn:SetPoint("TOPLEFT", 200, -y - 16 - (i - 1) * 26)
        PaintChoice(btn, (w.loadChoice or "always") == choice.key)
        loadButtons[choice.key] = btn
    end
end

local WIZARD_STEPS = {
    BuildWizardStep1,
    BuildWizardStep2,
    BuildWizardStep3,
    BuildWizardStep4,
}

-- Custom tab -----------------------------------------------------------------

local function BuildCustomTab(content)
    local cs = state.custom
    local trackedBtn, stripBtn, browseBtn, spellInput

    local function PaintKind()
        trackedBtn:SetAlpha(cs.kind == "tracked" and 1 or 0.5)
        stripBtn:SetAlpha(cs.kind == "filterStrip" and 1 or 0.5)
        spellInput:SetShown(cs.kind == "tracked")
        if browseBtn then browseBtn:SetShown(cs.kind == "tracked") end
    end

    trackedBtn = GUI:CreateButton(content, ns.L["Track spells"], 130, 22, function()
        cs.kind = "tracked"
        PaintKind()
    end, "primary")
    trackedBtn:SetPoint("TOPLEFT", 2, 0)
    stripBtn = GUI:CreateButton(content, ns.L["Filter strip"], 130, 22, function()
        cs.kind = "filterStrip"
        PaintKind()
    end)
    stripBtn:SetPoint("LEFT", trackedBtn, "RIGHT", 8, 0)

    local P = ns.QUI_AuraDisplayPickers
    local SpellList = SpellListAPI()
    spellInput = P.CreateSpellEchoInput(content, 200, function(spellID, spellName)
        cs.spellID = spellID
        cs.spellName = spellName
        if spellName and dialog._customNameEdit and dialog._customNameEdit:GetText() == "" then
            dialog._customNameEdit:SetText(spellName)
        end
    end)
    spellInput:SetPoint("TOPLEFT", 2, -30)

    if SpellList and SpellList.ToggleBrowsePopup then
        browseBtn = GUI:CreateButton(content, ns.L["Browse"], 64, 22, function()
            SpellList.ToggleBrowsePopup(BROWSE_PREFIX .. ":custom", {
                title = ns.L["Add Tracked Spells"],
                presets = (SpellList.GetDefaultPresets and SpellList.GetDefaultPresets()) or {},
                isSelected = function(id) return cs.spellID == id end,
                onToggle = function(id) spellInput.editBox:SetText(tostring(id)) end,
                onClose = function() end,
            })
        end)
        browseBtn:SetPoint("LEFT", spellInput, "RIGHT", 6, 0)
    end

    local nameLabel = GUI:CreateLabel(content, ns.L["Name"], 10, C.textMuted)
    nameLabel:SetPoint("TOPLEFT", 2, -92)
    local nameBox, nameEdit = GUI:CreateInlineEditBox(content, { width = 270 })
    nameBox:SetPoint("TOPLEFT", 2, -106)
    dialog._customNameEdit = nameEdit

    local unitLabel = GUI:CreateLabel(content, ns.L["Unit"], 10, C.textMuted)
    unitLabel:SetPoint("TOPLEFT", 2, -138)
    local unitDrop = GUI:CreateFormDropdown(content, nil, UNIT_OPTIONS, "unitChoice",
        cs, function() end, {
            description = ns.L["Which unit this display watches. Co-Tank follows the first other tank in your group."],
        })
    unitDrop:SetPoint("TOPLEFT", 2, -152)

    local createBtn = GUI:CreateButton(content, ns.L["Create"], 100, 24, function()
        local Page = ns.QUI_AuraDisplaysOptions
        if not (Page and type(Page._QuickCreate) == "function") then return end
        Finish(Page._QuickCreate({
            kind = cs.kind,
            name = nameEdit:GetText(),
            unitChoice = cs.unitChoice,
            spellID = cs.spellID,
        }))
    end, "primary")
    createBtn:SetPoint("TOPLEFT", 2, -196)
    PaintKind()
end

-- Dialog shell ---------------------------------------------------------------

local function EnsureDialog()
    if dialog then return dialog end

    dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(DIALOG_W, DIALOG_H)
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

    dialog.title = GUI:CreateLabel(dialog, ns.L["New Display"], 13)
    dialog.title:SetPoint("TOP", 0, -10)

    local TAB_DEFS = {
        { key = "templates", label = ns.L["Templates"] },
        { key = "guided", label = ns.L["Guided"] },
        { key = "custom", label = ns.L["Custom"] },
    }
    dialog.tabs = {}
    local x = 15
    for i = 1, #TAB_DEFS do
        local def = TAB_DEFS[i]
        local btn = GUI:CreateButton(dialog, def.label, 100, 22, function()
            state.tab = def.key
            CloseBrowse()
            Rebuild()
        end)
        btn:SetPoint("TOPLEFT", x, -32)
        dialog.tabs[def.key] = btn
        x = x + 106
    end

    dialog.content = CreateFrame("Frame", nil, dialog)
    dialog.content:SetPoint("TOPLEFT", 15, -CONTENT_TOP)
    dialog.content:SetPoint("BOTTOMRIGHT", -15, 42)

    dialog.backBtn = GUI:CreateButton(dialog, ns.L["Back"], 80, 24, function()
        if state.wizardStep > 1 then
            state.wizardStep = state.wizardStep - 1
            CloseBrowse()
            Rebuild()
        end
    end)
    dialog.backBtn:SetPoint("BOTTOMLEFT", 15, 10)

    dialog.nextBtn = GUI:CreateButton(dialog, ns.L["Next"], 80, 24, function()
        if state.wizardStep < 4 then
            state.wizardStep = state.wizardStep + 1
            CloseBrowse()
            Rebuild()
        end
    end, "primary")
    dialog.nextBtn:SetPoint("LEFT", dialog.backBtn, "RIGHT", 8, 0)

    dialog.createBtn = GUI:CreateButton(dialog, ns.L["Create Display"], 120, 24, function()
        local T = Templates()
        if not T then return end
        local w = state.wizard
        if dialog._wizardNameEdit then
            w.name = dialog._wizardNameEdit:GetText()
        end
        Finish(T.BuildWizardDisplay(w))
    end, "primary")
    dialog.createBtn:SetPoint("LEFT", dialog.backBtn, "RIGHT", 8, 0)

    dialog.cancelBtn = GUI:CreateButton(dialog, ns.L["Cancel"], 80, 24, function()
        dialog:Hide()
    end)
    dialog.cancelBtn:SetPoint("BOTTOMRIGHT", -15, 10)

    dialog:SetScript("OnHide", function()
        local SpellList = SpellListAPI()
        if SpellList and SpellList.CloseBrowsePopup then
            SpellList.CloseBrowsePopup(BROWSE_PREFIX)
        end
    end)

    return dialog
end

Rebuild = function()
    if not dialog then return end
    local content = dialog.content
    if GUI and type(GUI.TeardownFrameTree) == "function" then
        GUI:TeardownFrameTree(content)
    else
        for _, child in ipairs({ content:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
    end
    dialog._wizardNameEdit = nil
    dialog._customNameEdit = nil

    for key, btn in pairs(dialog.tabs) do
        btn:SetAlpha(state.tab == key and 1 or 0.5)
    end

    local isWizard = state.tab == "guided"
    dialog.backBtn:SetShown(isWizard and state.wizardStep > 1)
    dialog.nextBtn:SetShown(isWizard and state.wizardStep > 1 and state.wizardStep < 4)
    dialog.createBtn:SetShown(isWizard and state.wizardStep == 4)

    if state.tab == "templates" then
        BuildTemplatesTab(content)
    elseif state.tab == "guided" then
        WIZARD_STEPS[state.wizardStep](content)
    else
        BuildCustomTab(content)
    end
end

function Create.ShowDialog(opts)
    callbacks.onCreated = opts and opts.onCreated or nil
    ResetState()
    EnsureDialog()
    Rebuild()
    dialog:Show()
end

function Create.HideDialog()
    if dialog then dialog:Hide() end
end

return Create
