local _, ns = ...
local QUI = QUI
local GUI = QUI and QUI.GUI

local P = {}
ns.QUI_AuraDisplayPickers = P

local classDataCache
local encounterCache

function P.ClassSpecData()
    if classDataCache then return classDataCache end
    if not (C_CreatureInfo and C_CreatureInfo.GetClassInfo
        and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
        and GetSpecializationInfoForClassID) then
        return nil
    end
    local out = {}
    local numClasses = (GetNumClasses and GetNumClasses()) or 13
    for classID = 1, numClasses do
        local info = C_CreatureInfo.GetClassInfo(classID)
        if info and info.classFile then
            local entry = {
                classID = classID,
                classFile = info.classFile,
                className = info.className or info.classFile,
                specs = {},
            }
            local n = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
            for i = 1, n do
                local specID, specName, _, icon = GetSpecializationInfoForClassID(classID, i)
                if specID then
                    entry.specs[#entry.specs + 1] = { specID = specID, name = specName, icon = icon }
                end
            end
            out[#out + 1] = entry
        end
    end
    if #out > 0 then classDataCache = out end
    return out
end

function P.ListCurrentTierRaidEncounters()
    if encounterCache then return encounterCache end
    local out = {}
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex
        and EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then
        return out
    end
    local numTiers = EJ_GetNumTiers()
    if not numTiers or numTiers == 0 then return out end
    EJ_SelectTier(numTiers)
    local instanceIndex = 1
    while true do
        local instanceID, instanceName = EJ_GetInstanceByIndex(instanceIndex, true)
        if not instanceID then break end
        local inst = { instanceID = instanceID, name = instanceName, encounters = {} }
        EJ_SelectInstance(instanceID)
        local encounterIndex = 1
        while true do
            local name, _, _, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(encounterIndex)
            if not name then break end
            if dungeonEncounterID then
                inst.encounters[#inst.encounters + 1] = { id = dungeonEncounterID, name = name }
            end
            encounterIndex = encounterIndex + 1
        end
        out[#out + 1] = inst
        instanceIndex = instanceIndex + 1
    end
    if #out > 0 then encounterCache = out end
    return out
end

local FALLBACK_ICON = 134400

local function AccentRGB()
    local accent = GUI and GUI.Colors and GUI.Colors.accent
    if type(accent) == "table" then
        return accent[1] or 0.2, accent[2] or 0.6, accent[3] or 1
    end
    return 0.2, 0.6, 1
end

local function MakeToggleButton(parent, w, h, labelText, isOn, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w, h)
    btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    local ar, ag, ab = AccentRGB()
    local function Paint(on)
        if on then
            btn:SetBackdropColor(ar * 0.25, ag * 0.25, ab * 0.25, 0.9)
            btn:SetBackdropBorderColor(ar, ag, ab, 1)
        else
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        end
    end
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(labelText)
    Paint(isOn())
    btn:SetScript("OnClick", function()
        onClick()
        Paint(isOn())
    end)
    return btn
end

function P.BuildRolePicker(parent, width, get, set)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 26)
    local labels = { TANK = _G.TANK or "TANK", HEALER = _G.HEALER or "HEALER",
        DAMAGER = _G.DAMAGER or "DAMAGER" }
    local x = 0
    for _, token in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local roleToken = token
        local btn = MakeToggleButton(frame, 90, 24, labels[roleToken],
            function() return get()[roleToken] == true end,
            function()
                local roles = get()
                roles[roleToken] = not roles[roleToken] or nil
                set()
            end)
        btn:SetPoint("LEFT", frame, "LEFT", x, 0)
        x = x + 96
    end
    return frame, 26
end

function P.BuildClassPicker(parent, width, get, set)
    local frame = CreateFrame("Frame", nil, parent)
    local data = P.ClassSpecData()
    if not data then
        frame:SetSize(width, 1)
        return frame, 1
    end
    local SIZE, GAP = 26, 4
    local x = 0
    for i = 1, #data do
        local entry = data[i]
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(SIZE, SIZE)
        btn:SetPoint("LEFT", frame, "LEFT", x, 0)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetAtlas("classicon-" .. string.lower(entry.classFile))
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        local ar, ag, ab = AccentRGB()
        border:SetColorTexture(ar, ag, ab, 0.9)
        local function Paint()
            local on = get()[entry.classFile] == true
            icon:SetDesaturated(not on)
            icon:SetAlpha(on and 1 or 0.55)
            border:SetShown(on)
        end
        Paint()
        btn:SetScript("OnClick", function()
            local classes = get()
            classes[entry.classFile] = not classes[entry.classFile] or nil
            set()
            Paint()
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(entry.className)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        x = x + SIZE + GAP
    end
    frame:SetSize(width, SIZE)
    return frame, SIZE
end

function P.BuildSpecPicker(parent, width, get, set, expanded, onToggleExpand)
    local frame = CreateFrame("Frame", nil, parent)
    local data = P.ClassSpecData()
    if not data then
        frame:SetSize(width, 1)
        return frame, 1
    end
    local header = CreateFrame("Button", nil, frame)
    header:SetSize(width, 20)
    header:SetPoint("TOPLEFT")
    local headerLabel = GUI:CreateLabel(header, "", 11, GUI.Colors and GUI.Colors.textMuted)
    headerLabel:SetPoint("LEFT", header, "LEFT", 0, 0)
    local function RefreshHeaderLabel()
        local selected = 0
        for _, on in pairs(get()) do
            if on then selected = selected + 1 end
        end
        headerLabel:SetText((expanded and "▾ " or "▸ ") .. ns.L["Specs"]
            .. (selected > 0 and (" (" .. selected .. ")") or ""))
    end
    RefreshHeaderLabel()
    header:SetScript("OnClick", onToggleExpand)
    local y = 24
    if expanded then
        local SIZE, GAP, ROW_H = 18, 4, 22
        for i = 1, #data do
            local entry = data[i]
            local x = 10
            for s = 1, #entry.specs do
                local spec = entry.specs[s]
                local btn = CreateFrame("Button", nil, frame)
                btn:SetSize(SIZE + 90, ROW_H - 2)
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetSize(SIZE, SIZE)
                icon:SetPoint("LEFT")
                icon:SetTexture(spec.icon or FALLBACK_ICON)
                local label = GUI:CreateLabel(btn, spec.name or tostring(spec.specID), 10)
                label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                local function Paint()
                    local on = get()[spec.specID] == true
                    icon:SetDesaturated(not on)
                    label:SetAlpha(on and 1 or 0.5)
                end
                Paint()
                btn:SetScript("OnClick", function()
                    local specs = get()
                    specs[spec.specID] = not specs[spec.specID] or nil
                    set()
                    Paint()
                    RefreshHeaderLabel()
                end)
                x = x + SIZE + 90 + GAP
                if x > width - 100 then break end
            end
            y = y + ROW_H
        end
    end
    frame:SetSize(width, y)
    return frame, y
end

local function ResolveEncounterName(id, tiers)
    for i = 1, #tiers do
        local inst = tiers[i]
        for e = 1, #inst.encounters do
            if inst.encounters[e].id == id then return inst.encounters[e].name end
        end
    end
    return nil
end

function P.BuildEncounterPicker(parent, width, get, set)
    local frame = CreateFrame("Frame", nil, parent)
    local tiers = P.ListCurrentTierRaidEncounters()
    local y = 0
    for i = 1, #tiers do
        local inst = tiers[i]
        local instLabel = GUI:CreateLabel(frame, inst.name or "", 11,
            GUI.Colors and GUI.Colors.textMuted)
        instLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        y = y + 18
        for e = 1, #inst.encounters do
            local enc = inst.encounters[e]
            local btn = CreateFrame("Button", nil, frame)
            btn:SetSize(width - 10, 18)
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -y)
            local box = btn:CreateTexture(nil, "ARTWORK")
            box:SetSize(10, 10)
            box:SetPoint("LEFT")
            local label = GUI:CreateLabel(btn, enc.name, 10)
            label:SetPoint("LEFT", box, "RIGHT", 6, 0)
            local function Paint()
                local on = get()[enc.id] == true
                local ar, ag, ab = AccentRGB()
                if on then
                    box:SetColorTexture(ar, ag, ab, 0.9)
                else
                    box:SetColorTexture(0.2, 0.2, 0.2, 0.9)
                end
                label:SetAlpha(on and 1 or 0.6)
            end
            Paint()
            btn:SetScript("OnClick", function()
                local encounters = get()
                encounters[enc.id] = not encounters[enc.id] or nil
                set()
                Paint()
            end)
            y = y + 20
        end
        y = y + 4
    end

    local extras = {}
    for id, on in pairs(get()) do
        if on and not ResolveEncounterName(id, tiers) then extras[#extras + 1] = id end
    end
    table.sort(extras)
    if #extras > 0 then
        local extraHeader = GUI:CreateLabel(frame, ns.L["Other encounter IDs"], 11,
            GUI.Colors and GUI.Colors.textMuted)
        extraHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        y = y + 18
        for i = 1, #extras do
            local id = extras[i]
            local row = CreateFrame("Frame", nil, frame)
            row:SetSize(width - 10, 18)
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -y)
            local label = GUI:CreateLabel(row, tostring(id), 10)
            label:SetPoint("LEFT")
            local remove = GUI:CreateButton(row, ns.L["X"], 18, 16, function()
                get()[id] = nil
                set()
            end)
            remove:SetPoint("LEFT", label, "RIGHT", 8, 0)
            y = y + 20
        end
    end

    local addBox = GUI:CreateInlineEditBox(frame, {
        width = 120,
        onEnterPressed = function(self)
            local id = tonumber(self:GetText())
            if id and id > 0 then
                get()[id] = true
                self:SetText("")
                set()
            end
            self:ClearFocus()
        end,
    })
    addBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y - 4)
    local addLabel = GUI:CreateLabel(frame, ns.L["Add encounter ID"], 10,
        GUI.Colors and GUI.Colors.textMuted)
    addLabel:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    y = y + 30

    frame:SetSize(width, y)
    return frame, y
end

function P.CreateSpellEchoInput(parent, width, onResolve)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 52)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local echo = GUI:CreateLabel(frame, "", 11)
    icon:Hide()
    local field, editBox = GUI:CreateInlineEditBox(frame, {
        width = width,
        onTextChanged = function(self)
            local id = tonumber(self:GetText())
            local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if id and name then
                local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                icon:SetTexture(tex or FALLBACK_ICON)
                icon:Show()
                echo:SetText(name .. "  (" .. id .. ")")
            else
                icon:Hide()
                echo:SetText(id and ns.L["Unknown spell"] or "")
            end
            onResolve(id, name)
        end,
    })
    field:SetPoint("TOPLEFT")
    icon:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -6)
    echo:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    frame.editBox = editBox
    return frame
end
