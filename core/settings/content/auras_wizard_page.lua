local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
if not Registry or type(Registry.RegisterFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function"
    or type(Schema.Section) ~= "function" then
    return
end

local W = ns.QUI_AuraWizard
local SpellList = ns.QUI_AuraSpellList

local BROWSE_PREFIX = "quiWizard:"
local BROWSE_KEY = "quiWizard:hots"

local ROLE_OPTIONS = {
    { value = "HEALER",  text = ns.L["Healer"], desc = ns.L["HoTs, dispels, defensives"] },
    { value = "TANK",    text = ns.L["Tank"],   desc = ns.L["Actives, boss debuffs"] },
    { value = "DAMAGER", text = ns.L["DPS"],    desc = ns.L["My debuffs, procs"] },
}

local STEP_LABELS = {
    role       = ns.L["Role"],
    surfaces   = ns.L["Surfaces"],
    partyAuras = ns.L["Party auras"],
    placeHoTs  = ns.L["Place HoTs"],
    review     = ns.L["Review"],
}

local SURFACE_ROWS = {
    { key = "party",  label = ns.L["Party / Raid frames"] },
    { key = "player", label = ns.L["Player frame"] },
    { key = "target", label = ns.L["Target frame"] },
    { key = "focus",  label = ns.L["Focus frame"] },
}

local CORNER_OPTIONS = {
    { value = "TOPLEFT",     text = ns.L["Top-Left"] },
    { value = "TOPRIGHT",    text = ns.L["Top-Right"] },
    { value = "BOTTOMLEFT",  text = ns.L["Bottom-Left"] },
    { value = "BOTTOMRIGHT", text = ns.L["Bottom-Right"] },
}
local DISPLAY_OPTIONS = {
    { value = "icon",   text = ns.L["Icon"] },
    { value = "square", text = ns.L["Square"] },
    { value = "bar",    text = ns.L["Bar"] },
    { value = "border", text = ns.L["Border"] },
}

local function RoleLabel(role)
    if role == "TANK" then return ns.L["Tank"] end
    if role == "HEALER" then return ns.L["Healer"] end
    return ns.L["DPS"]
end

local function ensure(t, k) t[k] = t[k] or {}; return t[k] end

local INTENT_SHORT = {
    mine         = ns.L["mine"],
    defensives   = ns.L["defensives"],
    all          = ns.L["all buffs"],
    dispellable  = ns.L["dispellable"],
    boss         = ns.L["boss debuffs"],
    crowdControl = ns.L["crowd control"],
}
local function joinShort(keys)
    if type(keys) ~= "table" or #keys == 0 then return nil end
    local out = {}
    for i, k in ipairs(keys) do out[i] = INTENT_SHORT[k] or k end
    return table.concat(out, ", ")
end
local function SurfaceDescriptor(role, kind)
    if kind == "party" then return ns.L["primary"] end
    local d = W.RoleDefaults(role)
    local keys
    if kind == "player" then keys = d.player and d.player.buffs
    elseif kind == "target" then keys = d.target and d.target.debuffs end
    return joinShort(keys) or ns.L["off"]
end

local function SeedFromRole(ctx, role)
    local d = W.RoleDefaults(role)
    ctx.state.wizardSurfaces = {
        party  = (#d.groupParty.buffs > 0 or #d.groupParty.debuffs > 0),
        player = (#d.player.buffs > 0),
        target = (#d.target.debuffs > 0),
        focus  = false,
    }
    ctx.state.wizardPartyBuffs = {}
    for _, k in ipairs(d.groupParty.buffs) do ctx.state.wizardPartyBuffs[k] = true end
    ctx.state.wizardPartyBuffs.defensives = true
    ctx.state.wizardPartyDebuffs = {}
    for _, k in ipairs(d.groupParty.debuffs) do ctx.state.wizardPartyDebuffs[k] = true end
    ctx.state.wizardHoTs = {}
end

local function CheckedKeys(menu, checkedMap)
    local out = {}
    for _, entry in ipairs(menu) do
        if checkedMap and checkedMap[entry.key] then out[#out + 1] = entry.key end
    end
    return out
end

local function DoApply(ctx, skipSet)
    skipSet = skipSet or {}
    local db = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    if not db then return ns.L["Profile not available."] end
    if not (W and type(W.SeedBucketForRole) == "function") then return ns.L["Profile not available."] end

    local role = ctx.state.wizardRole
    local surfaces = ctx.state.wizardSurfaces or {}
    local d = W.RoleDefaults(role)

    local partyDefaultFn
    if ns.QUI_GroupFramesAuraModel and type(ns.QUI_GroupFramesAuraModel.DefaultStripBucket) == "function" then
        partyDefaultFn = function() return ns.QUI_GroupFramesAuraModel.DefaultStripBucket("party") end
    end
    local unitDefaultFn = ns.QUI_UnitFrameAuras and ns.QUI_UnitFrameAuras.DefaultUnitAuraBucket

    local touched = { group = false, unit = false }

    local function seed(kind, auras, buffKeys, debuffKeys, defaultBucketFn, bucketKey, explicit)
        auras.elements = auras.elements or {}
        auras.elements[bucketKey] = W.SeedBucketForRole(auras.elements[bucketKey], buffKeys, debuffKeys, defaultBucketFn, explicit)
        auras.elementsSeeded = true
        auras.enabled = true
        if kind == "party" then touched.group = true else touched.unit = true end
    end

    if surfaces.party and not skipSet.party then
        local partyAuras = ensure(ensure(ensure(db, "quiGroupFrames"), "party"), "auras")
        local partyKey = "*"
        if type(W.ActiveBucketKey) == "function" then
            local specID = type(W.PlayerSpecID) == "function" and W.PlayerSpecID() or nil
            partyKey = W.ActiveBucketKey(partyAuras.elements, specID)
        end
        local buffKeys = CheckedKeys(W.PARTY_BUFF_INTENTS, ctx.state.wizardPartyBuffs)
        local debuffKeys = CheckedKeys(W.PARTY_DEBUFF_INTENTS, ctx.state.wizardPartyDebuffs)
        seed("party", partyAuras, buffKeys, debuffKeys, partyDefaultFn, partyKey, true)
        partyAuras.elements[partyKey] = W.CommitTrackedHoTs(partyAuras.elements[partyKey], ctx.state.wizardHoTs)
    end

    if surfaces.player and not skipSet.player then
        local playerAuras = ensure(ensure(ensure(db, "quiUnitFrames"), "player"), "auras")
        seed("player", playerAuras, d.player and d.player.buffs, nil, unitDefaultFn, "*")
    end
    if surfaces.target and not skipSet.target then
        local targetAuras = ensure(ensure(ensure(db, "quiUnitFrames"), "target"), "auras")
        seed("target", targetAuras, nil, d.target and d.target.debuffs, unitDefaultFn, "*")
    end
    if surfaces.focus and not skipSet.focus then
        local focusAuras = ensure(ensure(ensure(db, "quiUnitFrames"), "focus"), "auras")
        seed("focus", focusAuras, nil, W.FocusDefaults(role).debuffs, unitDefaultFn, "*")
    end

    if touched.group and _G.QUI_RefreshGroupFrames then _G.QUI_RefreshGroupFrames() end
    if touched.unit and _G.QUI_RefreshUnitFrames then _G.QUI_RefreshUnitFrames() end
    return ns.L["Applied!"]
end

local function CustomizedSurfaces(ctx)
    local out = {}
    local db = _G.QUI and _G.QUI.db and _G.QUI.db.profile
    if not db then return out end
    local surfaces = ctx.state.wizardSurfaces or {}

    if surfaces.party then
        local partyAuras = db.quiGroupFrames and db.quiGroupFrames.party and db.quiGroupFrames.party.auras
        if partyAuras then
            local partyDefaultFn
            if ns.QUI_GroupFramesAuraModel and type(ns.QUI_GroupFramesAuraModel.DefaultStripBucket) == "function" then
                partyDefaultFn = function() return ns.QUI_GroupFramesAuraModel.DefaultStripBucket("party") end
            end
            local partyKey = "*"
            if type(W.ActiveBucketKey) == "function" then
                local specID = type(W.PlayerSpecID) == "function" and W.PlayerSpecID() or nil
                partyKey = W.ActiveBucketKey(partyAuras.elements, specID)
            end
            if W.SurfaceIsCustomized(partyAuras, partyDefaultFn, partyKey) then
                out[#out + 1] = "party"
            end
        end
    end

    local unitDefaultFn = ns.QUI_UnitFrameAuras and ns.QUI_UnitFrameAuras.DefaultUnitAuraBucket
    for _, kind in ipairs({ "player", "target", "focus" }) do
        if surfaces[kind] then
            local unitAuras = db.quiUnitFrames and db.quiUnitFrames[kind] and db.quiUnitFrames[kind].auras
            if unitAuras and W.SurfaceIsCustomized(unitAuras, unitDefaultFn, "*") then
                out[#out + 1] = kind
            end
        end
    end

    return out
end

local function ListToSet(list)
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    return set
end

local function StepRole(host, ctx, y, C)
    local detected = (type(W.PlayerRole) == "function" and W.PlayerRole()) or "DAMAGER"
    local specName = ""
    if type(W.PlayerSpecID) == "function" then
        local id = W.PlayerSpecID()
        if id and GetSpecializationInfoByID then
            local _, sn = GetSpecializationInfoByID(id)
            specName = sn or ""
        end
    end
    local head = specName ~= ""
        and string.format(ns.L["Looks like you're a %s — %s."], RoleLabel(detected), specName)
        or string.format(ns.L["Looks like you're a %s."], RoleLabel(detected))
    local q = GUI:CreateLabel(host, head, 16, C.text)
    q:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24
    local sub = GUI:CreateLabel(host, ns.L["Detected from your active spec. Set up for this role? You can override."], 12, C.textMuted)
    sub:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 22

    local role = ctx.state.wizardRole
    local x = 0
    for _, opt in ipairs(ROLE_OPTIONS) do
        local selected = (role == opt.value)
        local btn = GUI:CreateButton(host, opt.text, 120, 30, function()
            if ctx.state.wizardRole ~= opt.value then
                ctx.state.wizardRole = opt.value
                SeedFromRole(ctx, opt.value)
                if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(ctx._sectionId) end
            end
        end, selected and "primary" or nil)
        btn:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
        x = x + 128
    end
    y = y + 30 + 8
    return y
end

local function StepSurfaces(host, ctx, y, C)
    local q = GUI:CreateLabel(host, ns.L["Where should auras show?"], 16, C.text)
    q:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24
    local sub = GUI:CreateLabel(host, ns.L["Pre-checked for your role. Uncheck anything you don't want touched."], 12, C.textMuted)
    sub:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24

    local surfaces = ctx.state.wizardSurfaces or {}
    for _, sr in ipairs(SURFACE_ROWS) do
        local row = CreateFrame("Frame", nil, host)
        row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        row:SetHeight(24)
        local key = sr.key
        local cb = GUI:CreateAccentCheckbox(row, {
            size = 16,
            checked = surfaces[key] == true,
            onChange = function(checked) surfaces[key] = checked and true or false end,
        })
        if cb then cb:SetPoint("LEFT", row, "LEFT", 0, 0) end
        local lbl = GUI:CreateLabel(row, sr.label, 13, C.text)
        lbl:SetPoint("LEFT", cb or row, cb and "RIGHT" or "LEFT", cb and 8 or 0, 0)
        local desc = GUI:CreateLabel(row, SurfaceDescriptor(ctx.state.wizardRole, key), 11, C.textMuted)
        desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        y = y + 24
    end
    local note = GUI:CreateLabel(host, ns.L["Action-bar buffs and debuffs aren't set here — that surface is self-only."], 11, C.textMuted)
    note:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 22
    return y
end

local function StepPartyAuras(host, ctx, y, C)
    local q = GUI:CreateLabel(host, ns.L["Party frames — what to show"], 16, C.text)
    q:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24
    local sub = GUI:CreateLabel(host, ns.L["Plain-language intents. QUI writes the underlying filters for you."], 12, C.textMuted)
    sub:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24

    local function column(title, menu, checkedMap, startY)
        local cy = startY
        local h = GUI:CreateLabel(host, title, 11, C.accent)
        h:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -cy); cy = cy + 20
        for _, entry in ipairs(menu) do
            local row = CreateFrame("Frame", nil, host)
            row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -cy)
            row:SetPoint("RIGHT", host, "RIGHT", 0, 0)
            row:SetHeight(22)
            local ek = entry.key
            local cb = GUI:CreateAccentCheckbox(row, {
                size = 16,
                checked = checkedMap[ek] == true,
                onChange = function(checked) checkedMap[ek] = checked and true or nil end,
            })
            if cb then cb:SetPoint("LEFT", row, "LEFT", 0, 0) end
            local lbl = GUI:CreateLabel(row, entry.label, 12, C.text)
            lbl:SetPoint("LEFT", cb or row, cb and "RIGHT" or "LEFT", cb and 8 or 0, 0)
            cy = cy + 22
        end
        return cy
    end

    local buffsBottom = column(ns.L["Buffs"], W.PARTY_BUFF_INTENTS, ctx.state.wizardPartyBuffs, y)
    local debuffsBottom = column(ns.L["Debuffs"], W.PARTY_DEBUFF_INTENTS, ctx.state.wizardPartyDebuffs, buffsBottom + 8)
    return debuffsBottom
end

local function StepPlaceHoTs(host, ctx, y, C)
    local q = GUI:CreateLabel(host, ns.L["Place your HoTs on the party frame"], 16, C.text)
    q:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24
    local sub = GUI:CreateLabel(host, ns.L["Browse or enter a Spell ID to add a HoT, then choose where it sits."], 12, C.textMuted)
    sub:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24

    local staged = ctx.state.wizardHoTs

    local addRow = CreateFrame("Frame", nil, host)
    addRow:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    addRow:SetHeight(24)
    local input = CreateFrame("EditBox", nil, addRow, "InputBoxTemplate")
    input:SetSize(70, 20)
    input:SetPoint("LEFT", addRow, "LEFT", 6, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(10)
    input:SetNumeric(true)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function commitManual()
        local spellID = tonumber(input:GetText())
        if spellID and spellID > 0 and not staged[spellID] then
            staged[spellID] = { corner = "TOPLEFT", displayType = "icon", _quiTransientOptionsProxy = true }
            input:SetText(""); input:ClearFocus()
            if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(ctx._sectionId) end
        end
    end
    input:SetScript("OnEnterPressed", commitManual)
    local addBtn = GUI:CreateButton(addRow, ns.L["Add"], 50, 20, commitManual)
    addBtn:SetPoint("LEFT", input, "RIGHT", 8, 0)

    if SpellList and SpellList.ToggleBrowsePopup then
        local browseOpts = {
            title = ns.L["Add HoTs"],
            presets = (SpellList.GetDefaultPresets and SpellList.GetDefaultPresets()) or {},
            isSelected = function(spellID) return staged[spellID] ~= nil end,
            onToggle = function(spellID)
                if staged[spellID] then staged[spellID] = nil
                else staged[spellID] = { corner = "TOPLEFT", displayType = "icon", _quiTransientOptionsProxy = true } end
                if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(ctx._sectionId) end
            end,
        }
        local browseBtn = GUI:CreateButton(addRow, ns.L["Browse"], 70, 20, function()
            SpellList.ToggleBrowsePopup(BROWSE_KEY, browseOpts)
        end)
        browseBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
        if SpellList.RefreshBrowsePopup then SpellList.RefreshBrowsePopup(BROWSE_KEY, browseOpts) end
    end
    y = y + 28

    local ids = {}
    for spellID in pairs(staged) do ids[#ids + 1] = spellID end
    table.sort(ids)
    if #ids == 0 then
        local empty = GUI:CreateLabel(host, ns.L["No HoTs added yet."], 12, C.textMuted)
        empty:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 20
    else
        for _, spellID in ipairs(ids) do
            local cfg = staged[spellID]
            local row = CreateFrame("Frame", nil, host)
            row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", host, "RIGHT", 0, 0)
            row:SetHeight(30)

            local name
            if C_Spell and C_Spell.GetSpellName then
                local ok, nm = pcall(C_Spell.GetSpellName, spellID)
                name = ok and nm or nil
            end
            local label = GUI:CreateLabel(row, (name or ("#" .. tostring(spellID))) .. "  #" .. tostring(spellID), 12, C.text)
            label:SetPoint("LEFT", row, "LEFT", 0, 0)

            local cornerDD = GUI:CreateFormDropdown(row, nil, CORNER_OPTIONS, "corner", cfg, function() if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(ctx._sectionId) end end, { description = ns.L["Where on the party frame this HoT sits."] })
            cornerDD:SetPoint("LEFT", row, "LEFT", 180, 0)
            local dispDD = GUI:CreateFormDropdown(row, nil, DISPLAY_OPTIONS, "displayType", cfg, function() if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(ctx._sectionId) end end, { description = ns.L["How this HoT displays."] })
            dispDD:SetPoint("LEFT", cornerDD, "RIGHT", 8, 0)

            local rm = GUI:CreateButton(row, ns.L["Remove"], 70, 20, function()
                staged[spellID] = nil
                if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(ctx._sectionId) end
            end)
            rm:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            y = y + 32
        end
    end

    y = y + 8
    local pvLabel = GUI:CreateLabel(host, ns.L["Live preview"], 11, C.textMuted)
    pvLabel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 16

    local pv = CreateFrame("Frame", nil, host)
    pv:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    pv:SetSize(200, 46)
    local hp = pv:CreateTexture(nil, "BACKGROUND")
    hp:SetAllPoints(pv)
    hp:SetColorTexture(0.18, 0.36, 0.24, 0.55)
    local pname = GUI:CreateLabel(pv, ns.L["Party 1"], 12, C.text)
    pname:SetPoint("LEFT", pv, "LEFT", 8, 0)

    local PV_PALETTE = { { 0.39, 0.77, 0.42 }, { 0.56, 0.82, 0.44 }, { 0.31, 0.68, 0.35 }, { 0.48, 0.82, 0.63 } }
    local cornerX, cornerY = {}, {}
    local borderColor, borderCount = nil, 0
    for idx, spellID in ipairs(ids) do
        local cfg = staged[spellID]
        local corner = cfg.corner or "TOPLEFT"
        local dt = cfg.displayType or "icon"
        local col = PV_PALETTE[((idx - 1) % #PV_PALETTE) + 1]
        if dt == "border" then
            borderColor = col
            borderCount = borderCount + 1
        else
            local ind = pv:CreateTexture(nil, "OVERLAY")
            if dt == "icon" then
                local tex
                if C_Spell and C_Spell.GetSpellTexture then
                    local ok, t = pcall(C_Spell.GetSpellTexture, spellID)
                    tex = ok and t or nil
                end
                ind:SetSize(16, 16)
                if tex then
                    ind:SetTexture(tex); ind:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                else
                    ind:SetColorTexture(col[1], col[2], col[3], 1)
                end
            elseif dt == "square" then
                ind:SetSize(12, 12); ind:SetColorTexture(col[1], col[2], col[3], 1)
            elseif dt == "bar" then
                ind:SetSize(44, 4); ind:SetColorTexture(col[1], col[2], col[3], 1)
            else
                ind:SetSize(12, 12); ind:SetColorTexture(col[1], col[2], col[3], 1)
            end
            local dx = cornerX[corner] or 0
            local dy = cornerY[corner] or 0
            if corner == "TOPLEFT" then ind:SetPoint("TOPLEFT", pv, "TOPLEFT", 4 + dx, -4 - dy)
            elseif corner == "TOPRIGHT" then ind:SetPoint("TOPRIGHT", pv, "TOPRIGHT", -4 - dx, -4 - dy)
            elseif corner == "BOTTOMLEFT" then ind:SetPoint("BOTTOMLEFT", pv, "BOTTOMLEFT", 4 + dx, 4 + dy)
            else ind:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -4 - dx, 4 + dy) end
            if dt == "bar" then
                cornerY[corner] = dy + 6
            else
                cornerX[corner] = dx + (ind:GetWidth() or 12) + 2
            end
        end
    end
    if borderColor then
        local b = CreateFrame("Frame", nil, pv, "BackdropTemplate")
        b:SetPoint("TOPLEFT", pv, "TOPLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", 0, 0)
        b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        b:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1)
    end
    y = y + 46 + 8
    if borderCount > 1 then
        local hint = GUI:CreateLabel(host, ns.L["Only one border shows at a time — when several border HoTs are active, the frame border takes the most recent one's color."], 11, C.textMuted)
        hint:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
        hint:SetWidth(math.max((ctx.width or 700) - 16, 200)); hint:SetWordWrap(true)
        y = y + (hint:GetStringHeight() or 14) + 6
    end
    return y
end

local function StepReview(host, ctx, y, C)
    local surfaces = ctx.state.wizardSurfaces or {}
    local customList = CustomizedSurfaces(ctx)
    local customSet = ListToSet(customList)
    local customLabels = {}
    for _, kind in ipairs(customList) do
        for _, sr in ipairs(SURFACE_ROWS) do
            if sr.key == kind then customLabels[#customLabels + 1] = sr.label end
        end
    end

    if #customList > 0 then
        local warn = GUI:CreateLabel(host, string.format(ns.L["You've customized %s. Applying replaces that surface's aura layout."], table.concat(customLabels, ", ")), 12, C.accent)
        warn:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
        warn:SetWidth(math.max((ctx.width or 700) - 16, 200)); warn:SetWordWrap(true)
        y = y + (warn:GetStringHeight() or 16) + 10
    end

    local q = GUI:CreateLabel(host, ns.L["Ready to apply"], 16, C.text)
    q:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 24
    local sub = GUI:CreateLabel(host, ns.L["Here's what each surface gets. Nothing is written until you confirm."], 12, C.textMuted)
    sub:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 22

    for _, sr in ipairs(SURFACE_ROWS) do
        if surfaces[sr.key] then
            local suffix = customSet[sr.key] and ns.L["replace · you customized this"] or ns.L["set · untouched"]
            local line = GUI:CreateLabel(host, sr.label .. "  —  " .. suffix, 12, C.text)
            line:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y); y = y + 18
        end
    end
    y = y + 12

    ctx.state._wizardStatus = GUI:CreateLabel(host, "", 12, C.accent)
    ctx.state._wizardStatus:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(y + 40))

    local applyBtn = GUI:CreateButton(host, ns.L["Apply Setup"], 160, 28, function()
        if #customList > 0 then
            StaticPopupDialogs["QUI_AURA_WIZARD_REPLACE"] = {
                text = string.format(ns.L["You've customized %s. Applying replaces that surface's aura layout."], table.concat(customLabels, ", ")),
                button1 = ACCEPT,
                button2 = CANCEL,
                OnAccept = function()
                    local msg = DoApply(ctx, {})
                    if ctx.state._wizardStatus then ctx.state._wizardStatus:SetText(msg or "") end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("QUI_AURA_WIZARD_REPLACE")
        else
            local msg = DoApply(ctx, {})
            if ctx.state._wizardStatus then ctx.state._wizardStatus:SetText(msg or "") end
        end
    end, "primary")
    applyBtn:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    if #customList > 0 then
        local keepBtn = GUI:CreateButton(host, ns.L["Keep mine, skip customized"], 180, 28, function()
            local msg = DoApply(ctx, customSet)
            if ctx.state._wizardStatus then ctx.state._wizardStatus:SetText(msg or "") end
        end)
        keepBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    end
    y = y + 28 + 24
    return y
end

local STEP_BUILDERS = {
    role = StepRole, surfaces = StepSurfaces, partyAuras = StepPartyAuras,
    placeHoTs = StepPlaceHoTs, review = StepReview,
}

local function BuildAurasWizardContent(host, ctx, section)
    local C = GUI.Colors or {}
    ctx._sectionId = section.id

    if ctx.state.wizardRole == nil then
        ctx.state.wizardRole = (type(W.PlayerRole) == "function" and W.PlayerRole()) or "DAMAGER"
        SeedFromRole(ctx, ctx.state.wizardRole)
    end
    if type(ctx.state.wizardSurfaces) ~= "table" then SeedFromRole(ctx, ctx.state.wizardRole) end
    if type(ctx.state.wizardHoTs) ~= "table" then ctx.state.wizardHoTs = {} end
    if type(ctx.state.wizardStep) ~= "number" then ctx.state.wizardStep = 1 end

    if SpellList and SpellList.BeginBrowseScope then SpellList.BeginBrowseScope(BROWSE_PREFIX) end
    if host.SetScript then
        host:SetScript("OnHide", function()
            if SpellList and SpellList.CloseBrowsePopup then SpellList.CloseBrowsePopup(BROWSE_PREFIX) end
        end)
    end

    local steps = W.WizardSteps(ctx.state.wizardRole, ctx.state.wizardSurfaces)
    if ctx.state.wizardStep > #steps then ctx.state.wizardStep = #steps end
    if ctx.state.wizardStep < 1 then ctx.state.wizardStep = 1 end
    local currentKey = steps[ctx.state.wizardStep]

    local y = 0

    local railRow = CreateFrame("Frame", nil, host)
    railRow:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    railRow:SetHeight(24)
    local rx = 0
    for i, key in ipairs(steps) do
        local isCurrent = (i == ctx.state.wizardStep)
        local text = tostring(i) .. ". " .. (STEP_LABELS[key] or key)
        local btn = GUI:CreateButton(railRow, text, 116, 24, function()
            if i ~= ctx.state.wizardStep then
                ctx.state.wizardStep = i
                if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(section.id) end
            end
        end, isCurrent and "primary" or nil)
        btn:SetPoint("TOPLEFT", railRow, "TOPLEFT", rx, 0)
        rx = rx + 122
    end
    railRow:SetWidth(math.max(rx, 1))
    y = y + 24 + 16

    local builder = STEP_BUILDERS[currentKey]
    if builder then y = builder(host, ctx, y, C) end
    y = y + 8

    local navRow = CreateFrame("Frame", nil, host)
    navRow:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
    navRow:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    navRow:SetHeight(30)
    if ctx.state.wizardStep > 1 then
        local back = GUI:CreateButton(navRow, ns.L["Back"], 90, 28, function()
            ctx.state.wizardStep = ctx.state.wizardStep - 1
            if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(section.id) end
        end)
        back:SetPoint("TOPLEFT", navRow, "TOPLEFT", 0, 0)
    end
    if currentKey ~= "review" then
        local nextLabel = (currentKey == "partyAuras" and steps[ctx.state.wizardStep + 1] == "placeHoTs")
            and ns.L["Place my HoTs →"] or ns.L["Continue →"]
        local nextBtn = GUI:CreateButton(navRow, nextLabel, 150, 28, function()
            ctx.state.wizardStep = ctx.state.wizardStep + 1
            if type(ctx.RerenderSection) == "function" then ctx:RerenderSection(section.id) end
        end, "primary")
        nextBtn:SetPoint("TOPRIGHT", navRow, "TOPRIGHT", 0, 0)
    end
    y = y + 34

    if SpellList and SpellList.EndBrowseScope then SpellList.EndBrowseScope(BROWSE_PREFIX) end

    host:SetHeight(y)

    if GUI and type(GUI.SetSearchContext) == "function" then
        GUI:SetSearchContext({
            tileId = "auras",
            subPageIndex = 1,
            featureId = "aurasWizardPage",
            tabIndex = 21,
            subTabIndex = 1,
            tabName = ns.L["Auras"],
            subTabName = ns.L["Setup Wizard"],
        })
    end

    return y
end

Registry:RegisterFeature(Schema.Feature({
    id = "aurasWizardPage",
    category = "frames",
    nav = { tileId = "auras", subPageIndex = 1 },
    sections = {
        Schema.Section({
            id = "settings",
            kind = "page",
            minHeight = 80,
            build = BuildAurasWizardContent,
        }),
    },
}))
