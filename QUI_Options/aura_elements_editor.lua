local ADDON_NAME, ns = ...
local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local E = ns.AuraElements
local SpellList = ns.QUI_AuraSpellList
local SkinBase = ns.SkinBase
local MissingRaidBuffs = ns.QUI_GroupFrameMissingRaidBuffs

local AurasEditor = ns.QUI_AuraElementsEditor or {}
ns.QUI_AuraElementsEditor = AurasEditor

local FORM_ROW = 32
local PAD = 10
local COL_GAP = 12
local ROW_HEIGHT = 30
local ROW_STEP = 32
local FALLBACK_ICON = 134400

local browseInstanceCounter = 0

local NINE_POINT_OPTIONS = ns.QUI_SettingsLayoutShared.BuildNinePointAnchorOptions()

local AURA_GROW_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "RIGHT", text = ns.L["Right"] },
    { value = "CENTER", text = ns.L["Center"] },
    { value = "UP", text = ns.L["Up"] },
    { value = "DOWN", text = ns.L["Down"] },
}

local FILTER_MODE_OPTIONS = {
    { value = "off", text = ns.L["Off (Show All)"] },
    { value = "flags", text = ns.L["Filter Flags"] },
    { value = "classify", text = ns.L["Classification"] },
    { value = "whitelist", text = ns.L["Spell Whitelist"] },
}

local AURA_TYPE_OPTIONS = {
    { value = "HELPFUL", text = ns.L["Buffs (Helpful)"] },
    { value = "HARMFUL", text = ns.L["Debuffs (Harmful)"] },
}

local WHAT_TO_SHOW_LABELS = {
    all          = ns.L["All"],
    mine         = ns.L["Only my auras"],
    defensives   = ns.L["Defensives"],
    important    = ns.L["Important"],
    purgeable    = ns.L["Purgeable"],
    dispellable  = ns.L["Dispellable by me"],
    crowdControl = ns.L["Crowd control"],
    boss         = ns.L["Boss debuffs"],
    roleBoss     = ns.L["Role-relevant boss debuffs"],
    whitelist    = ns.L["Specific spells"],
    custom       = ns.L["Custom…"],
}

local function WhatToShowOptions(auraType)
    local out = {}
    for _, key in ipairs(E.WhatToShowKeys(auraType)) do
        out[#out + 1] = { value = key, text = WHAT_TO_SHOW_LABELS[key] or key }
    end
    out[#out + 1] = { value = "custom", text = WHAT_TO_SHOW_LABELS.custom }
    return out
end

local TRACKED_DISPLAY_OPTIONS_ALL = {
    { value = "icon", text = ns.L["Icon"] },
    { value = "square", text = ns.L["Colored Square"] },
    { value = "bar", text = ns.L["Bar"] },
    { value = "healthTint", text = ns.L["Health Bar Tint"] },
    { value = "border", text = ns.L["Colored Border"] },
}

local APPLY_TO_ROLES_OPTIONS = {
    { value = "all", text = ns.L["Everyone"] },
    { value = "tank", text = ns.L["Tanks"] },
    { value = "healer", text = ns.L["Healers"] },
    { value = "dps", text = ns.L["Damage"] },
    { value = "me", text = ns.L["Only Me"] },
}

local SORT_OPTIONS = {
    { value = "INDEX", text = ns.L["Default Order"] },
    { value = "EXPIRY", text = ns.L["Expiration"] },
    { value = "EXPIRY_ONLY", text = ns.L["Expiration Only"] },
    { value = "NAME", text = ns.L["Name"] },
    { value = "NAME_ONLY", text = ns.L["Name Only"] },
    { value = "BIG_DEFENSIVE", text = ns.L["Big Defensives First"] },
    { value = "IMPORTANT_ONLY", text = ns.L["Important First"] },
    { value = "UF_DEBUFF", text = ns.L["Debuff Priority"] },
}

local TRI_STATE_OPTIONS = {
    { value = "off", text = ns.L["Off"] },
    { value = "require", text = ns.L["Require"] },
    { value = "exclude", text = ns.L["Exclude"] },
}

local DISPEL_FILTER_MODE_OPTIONS = {
    { value = "off", text = ns.L["Off"] },
    { value = "include", text = ns.L["Only These Types"] },
    { value = "exclude", text = ns.L["Hide These Types"] },
}

local DISPEL_TYPES = {
    { key = "Magic", label = ns.L["Magic"] },
    { key = "Curse", label = ns.L["Curse"] },
    { key = "Disease", label = ns.L["Disease"] },
    { key = "Poison", label = ns.L["Poison"] },
    { key = "Bleed", label = ns.L["Bleed"] },
}

local TOOLTIP_ANCHOR_OPTIONS = {
    { value = "ANCHOR_TOPRIGHT", text = ns.L["Top Right"] },
    { value = "ANCHOR_TOP", text = ns.L["Top"] },
    { value = "ANCHOR_TOPLEFT", text = ns.L["Top Left"] },
    { value = "ANCHOR_RIGHT", text = ns.L["Right"] },
    { value = "ANCHOR_LEFT", text = ns.L["Left"] },
    { value = "ANCHOR_BOTTOMRIGHT", text = ns.L["Bottom Right"] },
    { value = "ANCHOR_BOTTOM", text = ns.L["Bottom"] },
    { value = "ANCHOR_BOTTOMLEFT", text = ns.L["Bottom Left"] },
    { value = "ANCHOR_CURSOR", text = ns.L["At Cursor"] },
}

local HEALTH_TINT_ANIMATION_OPTIONS = {
    { value = "fill", text = ns.L["Soft Fill"] },
    { value = "fade", text = ns.L["Soft Fade"] },
    { value = "fillFade", text = ns.L["Fill + Fade"] },
    { value = "pulse", text = ns.L["Subtle Pulse"] },
    { value = "instant", text = ns.L["Instant"] },
}

local SWIPE_STYLE_OPTIONS = {
    { value = "radial", text = ns.L["Radial"] },
    { value = "horizontal", text = ns.L["Horizontal"] },
    { value = "vertical", text = ns.L["Vertical"] },
}

local BAR_ORIENTATION_OPTIONS = {
    { value = "HORIZONTAL", text = ns.L["Horizontal"] },
    { value = "VERTICAL", text = ns.L["Vertical"] },
}

local DISPEL_BORDER_MODE_OPTIONS = {
    { value = "debuffs", text = ns.L["Debuffs"] },
    { value = "stealable", text = ns.L["Debuffs + Stealable Buffs"] },
    { value = "all", text = ns.L["All Auras"] },
}

local MISSING_RAID_BUFF_OPTIONS = {
    { key = "intellect", label = ns.L["Arcane Intellect (Mage)"] },
    { key = "stamina", label = ns.L["Power Word: Fortitude (Priest)"] },
    { key = "attackPower", label = ns.L["Battle Shout (Warrior)"] },
    { key = "versatility", label = ns.L["Mark of the Wild (Druid)"] },
    { key = "skyfury", label = ns.L["Skyfury (Shaman)"] },
    { key = "bronze", label = ns.L["Blessing of the Bronze (Evoker)"] },
}

local HELPFUL_CLASSIFICATIONS = {
    { key = "raid", label = ns.L["Raid"] },
    { key = "raidInCombat", label = ns.L["Raid (In Combat)"] },
    { key = "cancelable", label = ns.L["Cancelable"] },
    { key = "notCancelable", label = ns.L["Not Cancelable"] },
    { key = "bigDefensive", label = ns.L["Big Defensive"] },
    { key = "externalDefensive", label = ns.L["External Defensive"] },
    { key = "important", label = ns.L["Important"] },
}

local HARMFUL_CLASSIFICATIONS = {
    { key = "raid", label = ns.L["Raid"] },
    { key = "crowdControl", label = ns.L["Crowd Control"] },
    { key = "important", label = ns.L["Important"] },
}

local HELPFUL_FLAG_TOKENS = {
    { token = "PLAYER", label = ns.L["Player"] },
    { token = "RAID", label = ns.L["Castable by Me"] },
    { token = "CANCELABLE", label = ns.L["Cancelable"] },
    { token = "BIG_DEFENSIVE", label = ns.L["Big Defensive"] },
    { token = "EXTERNAL_DEFENSIVE", label = ns.L["External Defensive"] },
    { token = "IMPORTANT", label = ns.L["Important"] },
}

local HARMFUL_FLAG_TOKENS = {
    { token = "PLAYER", label = ns.L["Player"] },
    { token = "RAID", label = ns.L["Dispellable by Me"] },
    { token = "RAID_PLAYER_DISPELLABLE", label = ns.L["Raid-Dispellable (Anyone)"] },
    { token = "DISPELLABLE", label = ns.L["Dispellable (Any Source)"] },
    { token = "CROWD_CONTROL", label = ns.L["Crowd Control"] },
    { token = "IMPORTANT", label = ns.L["Important"] },
}

local function DefaultCapabilities()
    local AuraDefaults = ns.QUI_GroupFramesAuraDefaults
    return {
        elementTypes        = { filterStrip = true, tracked = true, missingRaidBuff = true },
        trackedDisplayTypes = { icon = true, square = true, bar = true, healthTint = true, border = true },
        iconSizeMax         = 40,
        cancelEligible      = false,
        maxStripElements    = 4,
        allowSpecOverride   = true,
        defaultBucketFn     = AuraDefaults and AuraDefaults.DefaultStripBucket or nil,
    }
end

local function ResolveCapabilities(opts)
    local caps = type(opts) == "table" and opts.capabilities
    if type(caps) ~= "table" then
        return DefaultCapabilities()
    end
    caps.elementTypes = caps.elementTypes or {}
    caps.trackedDisplayTypes = caps.trackedDisplayTypes or {}
    return caps
end

local function BuildTrackedDisplayOptions(trackedDisplayTypes)
    local out = {}
    for _, opt in ipairs(TRACKED_DISPLAY_OPTIONS_ALL) do
        if not trackedDisplayTypes or trackedDisplayTypes[opt.value] then
            out[#out + 1] = opt
        end
    end
    if #out == 0 then out[1] = TRACKED_DISPLAY_OPTIONS_ALL[1] end
    return out
end

local function DefaultTrackedDisplay(caps)
    local t = caps and caps.trackedDisplayTypes
    if type(t) ~= "table" then return "icon" end
    for _, v in ipairs({ "icon", "square", "bar", "healthTint", "border" }) do
        if t[v] then return v end
    end
    return "icon"
end

local function GetGUI()
    return QUI and QUI.GUI or nil
end

local function GetOptionsAPI()
    return ns.QUI_Options
end

local function GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = ns.SafeCall("best-effort-style", C_Spell.GetSpellName, spellID)
        if ok and name and name ~= "" then
            return name
        end
    end
    if GetSpellInfo then
        local ok, name = ns.SafeCall("best-effort-style", GetSpellInfo, spellID)
        if ok and name and name ~= "" then
            return name
        end
    end
    return nil
end

local function GetSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = ns.SafeCall("best-effort-style", C_Spell.GetSpellTexture, spellID)
        if ok and texture then
            return texture
        end
    end
    return FALLBACK_ICON
end

local function StyleSpellInputText(GUI, C, box, label, addText)
    local fp = (GUI and GUI.FONT_PATH) or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
    local tc = (C and C.text) or { 1, 1, 1, 1 }
    local mc = (C and C.textMuted) or { 1, 1, 1, 0.45 }
    if box then
        CJKFont(box, fp, 12, "")
        box:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
    if label then
        CJKFont(label, fp, 11, "")
        label:SetTextColor(mc[1], mc[2], mc[3], mc[4] or 0.45)
    end
    if addText then
        CJKFont(addText, fp, 11, "")
        addText:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
end

local function GetElementLabel(element)
    if element.mode == "filterStrip" then
        if element.auraType == "HARMFUL" then
            return ns.L["Debuffs"], nil
        end
        return ns.L["Buffs"], nil
    elseif element.mode == "missingRaidBuff" then
        local icon = 134400
        local buffs = MissingRaidBuffs and MissingRaidBuffs.RaidBuffs
        if buffs and buffs[1] then
            local spellID = buffs[1].iconSpellID or (buffs[1].ids and buffs[1].ids[1])
            if spellID and C_Spell and C_Spell.GetSpellTexture then
                local ok, texture = ns.SafeCall("best-effort-style", C_Spell.GetSpellTexture, spellID)
                if ok and texture then icon = texture end
            end
        end
        return ns.L["Missing Raid Buff"], icon
    end

    local spells = element.spells or {}
    local first = spells[1]
    if not first then
        return ns.L["Tracked (empty)"], FALLBACK_ICON
    end
    local name = GetSpellName(first) or (ns.L["Spell"] .. " " .. tostring(first))
    if #spells > 1 then
        name = name .. " +" .. tostring(#spells - 1)
    end
    return name, GetSpellTexture(first)
end

local function EffectiveWhatToShow(element)
    local derived = E.DeriveWhatToShow(element)
    for _, key in ipairs(E.WhatToShowKeys(element.auraType)) do
        if key == derived then return derived end
    end
    return "custom"
end

local function RefreshDetailWidgetVisual(widget, dbTable, dbKey)
    if type(widget.Refresh) == "function" then
        widget.Refresh()
    elseif type(widget.UpdateVisual) == "function" then
        if type(widget.GetValue) == "function" then
            widget.UpdateVisual(widget.GetValue())
        elseif dbTable and dbKey ~= nil and dbTable[dbKey] ~= nil then
            widget.UpdateVisual(dbTable[dbKey])
        end
    end
end

local function OptionsFingerprint(options)
    if type(options) ~= "table" then return "" end
    local parts = {}
    for i = 1, #options do
        local opt = options[i]
        parts[i] = tostring(opt and (opt.value ~= nil and opt.value or opt.text) or "")
    end
    return table.concat(parts, ",")
end

local function DetailWidgetKey(ctx, kind, dbKey, dbTable, extra)
    if type(dbTable) == "table" and dbTable._quiTransientOptionsProxy then
        return table.concat({ "p", tostring(ctx._detailScope), kind, tostring(dbKey), extra or "" }, "\31")
    end
    return table.concat({ "s", tostring(dbTable), kind, tostring(dbKey), extra or "" }, "\31")
end

local function CreateDetailGUI(ctx, GUI)
    local cache = {}

    local function Acquire(key, dbKey, dbTable, build)
        local hit = cache[key]
        if hit then
            if type(dbTable) == "table" and dbTable._quiTransientOptionsProxy and hit.dbTable ~= dbTable then
                for k in pairs(hit.dbTable) do
                    if dbTable[k] == nil then hit.dbTable[k] = nil end
                end
                for k, v in pairs(dbTable) do
                    hit.dbTable[k] = v
                end
            end
            RefreshDetailWidgetVisual(hit.widget, hit.dbTable, hit.dbKey)
            return hit.widget
        end
        local widget = build()
        if widget then
            cache[key] = { widget = widget, dbTable = dbTable, dbKey = dbKey }
        end
        return widget
    end

    local wrapper = setmetatable({}, { __index = GUI })

    function wrapper.CreateFormSlider(_, parent, label, minV, maxV, step, dbKey, dbTable, onChange, options, registryInfo)
        local extra = tostring(minV) .. "\31" .. tostring(maxV) .. "\31" .. tostring(step)
            .. "\31" .. ((registryInfo and registryInfo.description) or "")
        return Acquire(DetailWidgetKey(ctx, "slider", dbKey, dbTable, extra), dbKey, dbTable, function()
            return GUI:CreateFormSlider(parent, label, minV, maxV, step, dbKey, dbTable, onChange, options, registryInfo)
        end)
    end

    function wrapper.CreateFormCheckbox(_, parent, label, dbKey, dbTable, onChange, registryInfo)
        local extra = (registryInfo and registryInfo.description) or ""
        return Acquire(DetailWidgetKey(ctx, "checkbox", dbKey, dbTable, extra), dbKey, dbTable, function()
            return GUI:CreateFormCheckbox(parent, label, dbKey, dbTable, onChange, registryInfo)
        end)
    end

    function wrapper.CreateFormDropdown(_, parent, label, options, dbKey, dbTable, onChange, registryInfo, opts)
        local extra = ((registryInfo and registryInfo.description) or "") .. "\31" .. OptionsFingerprint(options)
        return Acquire(DetailWidgetKey(ctx, "dropdown", dbKey, dbTable, extra), dbKey, dbTable, function()
            return GUI:CreateFormDropdown(parent, label, options, dbKey, dbTable, onChange, registryInfo, opts)
        end)
    end

    function wrapper.CreateFormColorPicker(_, parent, label, dbKey, dbTable, onChange, options, registryInfo)
        local extra = (registryInfo and registryInfo.description) or ""
        return Acquire(DetailWidgetKey(ctx, "color", dbKey, dbTable, extra), dbKey, dbTable, function()
            return GUI:CreateFormColorPicker(parent, label, dbKey, dbTable, onChange, options, registryInfo)
        end)
    end

    function wrapper.CreateLabel(_, parent, text, size, color, anchor, x, y)
        if anchor ~= nil then
            return GUI:CreateLabel(parent, text, size, color, anchor, x, y)
        end
        local key = table.concat({ "label", tostring(ctx._detailScope), tostring(text), tostring(size) }, "\31")
        local hit = cache[key]
        if hit then
            return hit.widget
        end
        local widget = GUI:CreateLabel(parent, text, size, color)
        cache[key] = { widget = widget }
        return widget
    end

    return wrapper
end

local sectionExpand = {}
local function sectionState(element)
    local s = sectionExpand[element.id]
    if not s then
        s = { basics = false, filters = false, advanced = false }
        s.manualCustom = false
        sectionExpand[element.id] = s
    end
    return s
end

local function MakeSectionHeader(ctx, element, sectionKey, labelText)
    local state = sectionState(element)
    local header, caret
    local cached = ctx._sectionHeaders[sectionKey]
    if cached then
        header = cached.header
        caret = cached.caret
        cached.fs:SetText(labelText)
        if caret and ns.UIKit and ns.UIKit.SetChevronCaretExpanded then
            ns.UIKit.SetChevronCaretExpanded(caret, state[sectionKey])
        end
    else
        header = CreateFrame("Button", nil, ctx.detailArea)
        header:SetHeight(FORM_ROW)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        local textColor = ctx.C.text or { 1, 1, 1, 1 }
        CJKFont(fs, ctx.GUI.FONT_PATH or [[Interface\\AddOns\\QUI\\assets\\Quazii.ttf]], 11, "")
        fs:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
        fs:SetPoint("LEFT", header, "LEFT", 20, 0)
        fs:SetText(labelText)
        if ns.UIKit and ns.UIKit.CreateChevronCaret then
            caret = ns.UIKit.CreateChevronCaret(header, {
                point = "LEFT", relativeTo = header, relativePoint = "LEFT",
                xPixels = 4, sizePixels = 8, collapsedDirection = "right",
                expanded = state[sectionKey],
            })
        end
        ctx._sectionHeaders[sectionKey] = { header = header, fs = fs, caret = caret }
    end
    if ctx._detailSectionCarets then
        ctx._detailSectionCarets[sectionKey] = caret
    end
    header:SetScript("OnClick", function()
        ctx.SetDetailSectionExpanded(sectionKey, not state[sectionKey])
    end)
    ctx.BeginDetailSection(header, FORM_ROW, sectionKey)
end

local function AddMaxIconsRow(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    if element.filterMode == "classify" then
        row(ns.L["Max Icons Per Category"], GUI:CreateFormSlider(ctx.detailArea, nil, 0, 40, 1, "maxIcons", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Hard cap on how many icons EACH ticked category shows at once — Classification mode builds one full-size group per category, so this limit applies separately to every one of them. 0 shows all matches in every category."],
        }))
    else
        row(ns.L["Max Icons"], GUI:CreateFormSlider(ctx.detailArea, nil, 0, 40, 1, "maxIcons", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Hard cap on how many icons this element displays at once. 0 shows all matches."],
        }))
    end
end

local function AddIconSizeRow(ctx, element)
    local iconSizeMax = ctx.caps.iconSizeMax or 40
    ctx.AddFormRow(ns.L["Icon Size"], ctx.GUI:CreateFormSlider(ctx.detailArea, nil, 4, iconSizeMax, 1, "iconSize", element, ctx.onChange, { deferOnDrag = true }, {
        description = ns.L["Pixel size of each icon."],
    }))
end

local function AddPlacementWidgets(ctx, element, includeStrip, skip)
    local GUI = ctx.GUI
    local C = ctx.C
    local row = ctx.AddFormRow
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange

    if includeStrip and element.mode == "filterStrip" then
        if not (skip and skip.maxIcons) then
            AddMaxIconsRow(ctx, element)
        end
    end
    if not (skip and skip.iconSize) then
        AddIconSizeRow(ctx, element)
    end
    if not ctx.caps.containerLayout then
        row(ns.L["Anchor"], GUI:CreateFormDropdown(ctx.detailArea, nil, NINE_POINT_OPTIONS, "anchor", element, onChange, {
            description = ns.L["Where on the frame this element is anchored. X/Y Offset below nudges it from this anchor point."],
        }))
    end
    local multiTracked = element.mode ~= "tracked"
        or not E.TrackedSpellCount
        or E.TrackedSpellCount(element) > 1
    if includeStrip and multiTracked then
        row(ns.L["Grow Direction"], GUI:CreateFormDropdown(ctx.detailArea, nil, AURA_GROW_OPTIONS, "growDirection", element, onChange, {
            description = ns.L["Direction icons within this row are added in after the first."],
        }))
        row(ns.L["Spacing"], GUI:CreateFormSlider(ctx.detailArea, nil, 0, 8, 1, "spacing", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Pixel gap between adjacent icons."],
        }))
        row(ns.L["Icons Per Row"], GUI:CreateFormSlider(ctx.detailArea, nil, 0, 10, 1, "iconsPerRow", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Wrap icons onto a new row after this many. 0 keeps them on a single row. Extra rows stack away from the anchored frame edge."],
        }))
        row(ns.L["Row Spacing"], GUI:CreateFormSlider(ctx.detailArea, nil, 0, 30, 1, "rowSpacing", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Pixel gap between wrapped rows. 0 uses the regular icon spacing. Increase this to make room for duration text below icons."],
        }))
    end
    if ctx.caps.singleStrip then
        local hint = GUI:CreateLabel(ctx.detailArea,
            ns.L["Positioned by its mover — drag the frame in Layout mode. X/Y offsets apply to additional strips only."],
            11, C.textMuted)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        hint:SetNonSpaceWrap(true)
        add(hint, 34, true)
    elseif not ctx.caps.containerLayout then
        row(ns.L["X Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetX", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Horizontal pixel offset from the anchor."],
        }))
        row(ns.L["Y Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetY", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Vertical pixel offset from the anchor."],
        }))
    end
end

local function AddSwipeWidgets(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange

    row(ns.L["Hide Duration Swipe"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "hideSwipe", element, onChange, {
        description = ns.L["Hide the cooldown swipe animation drawn over icons."],
    }))
    row(ns.L["Reverse Swipe"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "reverseSwipe", element, onChange, {
        description = ns.L["Reverse the swipe direction so the shaded portion grows instead of shrinks as time passes."],
    }))
    row(ns.L["Swipe Style"], GUI:CreateFormDropdown(ctx.detailArea, nil, SWIPE_STYLE_OPTIONS, "swipeStyle", element, onChange, {
        description = ns.L["Radial or linear (horizontal/vertical) cooldown animation over aura icons."],
    }))
end

local function AddDispelTooltipWidgets(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild

    row(ns.L["Hide Tooltips in Combat"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "tooltipHideInCombat", element, onChange, {
        description = ns.L["Suppress aura tooltips from this element while you are in combat."],
    }))

    row(ns.L["Custom Tooltip Anchor"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "_customTooltipAnchor", {
        _customTooltipAnchor = element.tooltipAnchor ~= nil,
        _quiTransientOptionsProxy = true,
    }, function(checked)
        if checked and element.tooltipAnchor == nil then
            element.tooltipAnchor = "ANCHOR_TOPRIGHT"
            element.tooltipAnchorX = 0
            element.tooltipAnchorY = 0
        elseif not checked then
            element.tooltipAnchor = nil
            element.tooltipAnchorX = nil
            element.tooltipAnchorY = nil
        end
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = ns.L["Anchor aura tooltips to each icon instead of the default tooltip position."],
    }))
    if element.tooltipAnchor ~= nil then
        local valid = false
        for _, opt in ipairs(TOOLTIP_ANCHOR_OPTIONS) do
            if opt.value == element.tooltipAnchor then valid = true break end
        end
        if not valid then element.tooltipAnchor = "ANCHOR_TOPRIGHT" end
        if type(element.tooltipAnchorX) ~= "number" then element.tooltipAnchorX = 0 end
        if type(element.tooltipAnchorY) ~= "number" then element.tooltipAnchorY = 0 end
        row(ns.L["Tooltip Anchor"], GUI:CreateFormDropdown(ctx.detailArea, nil, TOOLTIP_ANCHOR_OPTIONS, "tooltipAnchor", element, onChange, {
            description = ns.L["Where the tooltip appears relative to the icon."],
        }))
        row(ns.L["Tooltip X Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -50, 50, 1, "tooltipAnchorX", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Horizontal pixel offset from the tooltip anchor."],
        }))
        row(ns.L["Tooltip Y Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -50, 50, 1, "tooltipAnchorY", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Vertical pixel offset from the tooltip anchor."],
        }))
    end

    row(ns.L["Dispel Border Mode"], GUI:CreateFormDropdown(ctx.detailArea, nil, DISPEL_BORDER_MODE_OPTIONS, "dispelBorderMode", element, onChange, {
        description = ns.L["Which auras get a dispel-type border. All Auras ignores every other border filter, including harmful and helpful checks."],
    }))

    row(ns.L["Pandemic Glow"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "_pandemicGlow", {
        _pandemicGlow = type(element.pandemicGlow) == "table",
        _quiTransientOptionsProxy = true,
    }, function(checked)
        if checked and type(element.pandemicGlow) ~= "table" then
            element.pandemicGlow = { color = { 1, 0.85, 0.2, 1 } }
        elseif not checked then
            element.pandemicGlow = nil
        end
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = ns.L["Show a glow on each icon while the aura is inside its pandemic refresh window. The game decides when the window is active."],
    }))
    if type(element.pandemicGlow) == "table" then
        row(ns.L["Pandemic Glow Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element.pandemicGlow, onChange, nil, {
            description = ns.L["Tint and opacity of the pandemic glow."],
        }))
    end

    row(ns.L["Custom Dispel Ring Colors"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "_customDispelColors", {
        _customDispelColors = type(element.dispelColors) == "table",
        _quiTransientOptionsProxy = true,
    }, function(checked)
        if checked and type(element.dispelColors) ~= "table" then
            element.dispelColors = {}
        elseif not checked then
            element.dispelColors = nil
        end
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = ns.L["Override the engine's per-dispel-type ring colors for icons in this element. Types you never touch keep the engine color."],
    }))
    if type(element.dispelColors) == "table" then
        for _, entry in ipairs(DISPEL_TYPES) do
            local key = entry.key
            local stored = element.dispelColors[key]
            local proxy = {
                _quiTransientOptionsProxy = true,
                color = stored and { stored.r or 1, stored.g or 1, stored.b or 1, 1 }
                    or { 1, 1, 1, 1 },
            }
            row(string.format(ns.L["%s Ring Color"], entry.label),
                GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", proxy, function(r, g, b)
                    element.dispelColors[key] = { r = r, g = g, b = b }
                    onChange()
                end, nil, {
                    description = string.format(ns.L["Dispel ring color used for %s auras in this element."], entry.label),
                }))
        end
    end
end

local function AddTextRegionWidgets(ctx, element, key, label)
    local GUI = ctx.GUI
    local C = ctx.C
    local row = ctx.AddFormRow
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild

    if type(element[key]) ~= "table" then element[key] = {} end
    local region = element[key]

    local optionsAPI = GetOptionsAPI()
    local header
    if optionsAPI and type(optionsAPI.CreateAccentDotLabel) == "function" then
        local headerKey = tostring(ctx._detailScope) .. "\31" .. label
        header = ctx._accentDotLabels[headerKey]
        if not header then
            header = optionsAPI.CreateAccentDotLabel(ctx.detailArea, label, 0, true)
            ctx._accentDotLabels[headerKey] = header
        end
        add(header, 26, true)
    else
        header = GUI:CreateLabel(ctx.detailArea, "|cFFAAAAAA" .. label .. "|r", 11, C.textMuted)
        header:SetJustifyH("LEFT")
        add(header, 18, true)
    end

    row(ns.L["Show"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "show", region, onChange, {
        description = string.format(ns.L["Show the %s on each icon."], label),
    }))
    row(ns.L["Font Size"], GUI:CreateFormSlider(ctx.detailArea, nil, 6, 24, 1, "fontSize", region, onChange, { deferOnDrag = true }, {
        description = string.format(ns.L["Font size used for the %s."], label),
    }))
    row(ns.L["Text Anchor"], GUI:CreateFormDropdown(ctx.detailArea, nil, NINE_POINT_OPTIONS, "anchor", region, onChange, {
        description = ns.L["Where on the icon this text sits."],
    }))
    row(ns.L["X Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -30, 30, 1, "offsetX", region, onChange, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset from the text anchor."],
    }))
    row(ns.L["Y Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -30, 30, 1, "offsetY", region, onChange, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset from the text anchor."],
    }))
    row(ns.L["Text Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", region, onChange, nil, {
        description = string.format(ns.L["Color of the %s."], label),
    }))

    if key == "duration" and ctx.caps and ctx.caps.durationDecimals then
        row(ns.L["Decimals Under 3s"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "decimals", region, onChange, {
            description = ns.L["Show tenths of a second below 3 seconds."],
        }))
        row(ns.L["Hide Time Unit"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "hideUnit", region, onChange, {
            description = ns.L["Show 4 instead of 4s. Durations over 90 seconds keep their m/h/d unit."],
            keywords = { "unit", "seconds", "suffix" },
        }))
    end
end

local function AddSpellMapEditor(ctx, map, headerText, onMutate, browseCfg)
    local GUI = ctx.GUI
    local C = ctx.C
    local add = ctx.AddDetailWidget
    local notify = onMutate or ctx.onChange

    local header = GUI:CreateLabel(ctx.detailArea, "|cFFAAAAAA" .. headerText .. "|r", 11, C.textMuted)
    header:SetJustifyH("LEFT")
    add(header, 18, true)

    if not (SpellList and SpellList.CreateListFrame) then
        return
    end

    local ed = ctx._spellMapEditors[map]
    local manualRow, listFrame, browseButton

    if ed then
        ed.notify = notify
        manualRow = ed.manualRow
        listFrame = ed.listFrame
        browseButton = ed.browseButton
        ed.inputBox:SetText("")
        ed.RefreshList()
    else
        ed = { notify = notify }
        ctx._spellMapEditors[map] = ed

        manualRow = CreateFrame("Frame", nil, ctx.detailArea)
        manualRow:SetHeight(24)

        local inputBox = CreateFrame("EditBox", nil, manualRow, "BackdropTemplate")
        inputBox:SetSize(80, 20)
        inputBox:SetPoint("LEFT", 0, 0)
        SkinBase.ApplyPixelBackdrop(inputBox, 1, true, false, { 0.25, 0.25, 0.25, 1 }, { 0.06, 0.06, 0.08, 1 })
        inputBox:SetFontObject("GameFontNormalSmall")
        inputBox:SetAutoFocus(false)
        inputBox:SetMaxLetters(10)
        inputBox:SetTextInsets(4, 4, 0, 0)
        inputBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        local inputLabel = manualRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        inputLabel:SetPoint("LEFT", inputBox, "RIGHT", 4, 0)
        inputLabel:SetText(ns.L["Spell ID"])
        inputLabel:SetTextColor(0.5, 0.5, 0.5)

        local addManualButton = CreateFrame("Button", nil, manualRow, "BackdropTemplate")
        addManualButton:SetSize(40, 20)
        addManualButton:SetPoint("LEFT", inputLabel, "RIGHT", 8, 0)
        SkinBase.ApplyPixelBackdrop(addManualButton, 1, true, false, { 0.3, 0.3, 0.3, 1 }, { 0.15, 0.15, 0.15, 1 })
        local addManualText = addManualButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addManualText:SetPoint("CENTER")
        addManualText:SetText(ns.L["Add"])
        StyleSpellInputText(GUI, C, inputBox, inputLabel, addManualText)

        listFrame = SpellList.CreateListFrame(ctx.detailArea, map, nil, function()
            ed.notify()
        end, function(_, newHeight)
            ctx.UpdateDetailWidgetHeight(listFrame, newHeight)
        end)

        ed.RefreshList = function()
            if listFrame and type(listFrame.Refresh) == "function" then
                listFrame:Refresh()
            else
                ctx.rebuild()
            end
        end

        local function CommitManual()
            local spellID = tonumber(inputBox:GetText())
            if spellID and spellID > 0 then
                map[spellID] = true
                inputBox:SetText("")
                inputBox:ClearFocus()
                ed.notify()
                ed.RefreshList()
            end
        end
        addManualButton:SetScript("OnClick", CommitManual)
        inputBox:SetScript("OnEnterPressed", CommitManual)

        if browseCfg and browseCfg.key and SpellList.ToggleBrowsePopup then
            browseButton = GUI:CreateButton(manualRow, ns.L["Browse"], 70, 20)
            browseButton:ClearAllPoints()
            browseButton:SetPoint("LEFT", addManualButton, "RIGHT", 8, 0)
        end

        ed.manualRow = manualRow
        ed.inputBox = inputBox
        ed.listFrame = listFrame
        ed.browseButton = browseButton
    end

    if browseCfg and browseCfg.key and SpellList.ToggleBrowsePopup then
        local toggleSpell = browseCfg.onToggle or function(spellID)
            if map[spellID] then
                map[spellID] = nil
            else
                map[spellID] = true
            end
            notify()
        end
        local browseOpts = {
            title = browseCfg.title or headerText,
            presets = browseCfg.presets or {},
            isSelected = browseCfg.isSelected or function(spellID)
                return map[spellID] == true
            end,
            onToggle = function(spellID)
                toggleSpell(spellID)
                ed.RefreshList()
            end,
            onClose = browseCfg.onClose,
        }
        if browseButton then
            browseButton:SetScript("OnClick", function()
                SpellList.ToggleBrowsePopup(browseCfg.key, browseOpts)
            end)
        end
        if SpellList.RefreshBrowsePopup then
            SpellList.RefreshBrowsePopup(browseCfg.key, browseOpts)
        end
    end
    add(manualRow, 26, true)
    add(listFrame, math.max(1, listFrame:GetHeight() or 1), true)
end

local function BuildFilterBrowsePresets(auraType)
    if not SpellList then return {} end
    if auraType == "HARMFUL" then
        return (SpellList.GetDebuffBlacklistPresets and SpellList.GetDebuffBlacklistPresets()) or {}
    end
    local presets = {}
    for _, preset in ipairs((SpellList.GetDefaultPresets and SpellList.GetDefaultPresets()) or {}) do
        presets[#presets + 1] = preset
    end
    for _, preset in ipairs((SpellList.GetBuffBlacklistPresets and SpellList.GetBuffBlacklistPresets()) or {}) do
        presets[#presets + 1] = preset
    end
    return presets
end

local function AddTrackedSpellListEditor(ctx, element)
    if type(element.spells) ~= "table" then element.spells = {} end

    local mapView = ctx._trackedMapViews[element]
    if mapView then
        wipe(mapView)
    else
        mapView = {}
        ctx._trackedMapViews[element] = mapView
    end
    for _, sid in ipairs(element.spells) do mapView[sid] = true end

    local function ResolveTrackedSpellID(spellID)
        return E.ResolveTrackedSpellID and E.ResolveTrackedSpellID(spellID) or spellID
    end

    AddSpellMapEditor(ctx, mapView,
        ns.L["Tracked Spells (add at least one Spell ID):"],
        function()
            local arr = element.spells
            local normalized = {}
            for i = #arr, 1, -1 do arr[i] = nil end
            for sid in pairs(mapView) do normalized[ResolveTrackedSpellID(sid)] = true end
            for sid in pairs(normalized) do arr[#arr + 1] = sid end
            table.sort(arr)
            ctx.onChange()
            ctx.rebuild()
        end,
        {
            key = ctx.browsePrefix .. "tracked:" .. tostring(element.id),
            title = ns.L["Add Tracked Spells"],
            resolveAuraSpellIDs = true,
            presets = (SpellList and SpellList.GetDefaultPresets and SpellList.GetDefaultPresets()) or {},
            isSelected = function(spellID)
                local resolvedID = ResolveTrackedSpellID(spellID)
                for _, sid in ipairs(element.spells) do
                    if sid == spellID or sid == resolvedID then return true end
                end
                return false
            end,
            onToggle = function(spellID)
                local resolvedID = ResolveTrackedSpellID(spellID)
                local arr = element.spells
                for i = #arr, 1, -1 do
                    if arr[i] == spellID or arr[i] == resolvedID then
                        table.remove(arr, i)
                        mapView[spellID] = nil
                        mapView[resolvedID] = nil
                        ctx.NotifyChanged()
                        ctx.rebuild()
                        return
                    end
                end
                arr[#arr + 1] = resolvedID
                table.sort(arr)
                mapView[resolvedID] = true
                ctx.NotifyChanged()
                ctx.rebuild()
            end,
        })
end

local function AddRoleGateRow(ctx, element)
    local caps = ctx.caps
    if caps and caps.roleGate == false then return end
    if element.applyToRoles == nil then element.applyToRoles = "all" end
    ctx.AddFormRow(ns.L["Show On Roles"],
        ctx.GUI:CreateFormDropdown(ctx.detailArea, nil, APPLY_TO_ROLES_OPTIONS, "applyToRoles", element, ctx.onChange, {
            description = ns.L["Which group members' frames show this aura (by assigned role). 'Only Me' shows it on your own frame."],
            keywords = { "role", "tank", "healer", "dps", "personal" },
        }))
end

local function AddAuraTypeRow(ctx, element)
    ctx.AddFormRow(ns.L["Aura Type"], ctx.GUI:CreateFormDropdown(ctx.detailArea, nil, AURA_TYPE_OPTIONS, "auraType", element, function()
        ctx.NotifyChanged()
        ctx.rebuild()
    end, {
        description = ns.L["Whether this strip shows helpful buffs or harmful debuffs."],
    }))
end

local function AddWhatToShowRow(ctx, element)
    local state = sectionState(element)
    local derived = state.manualCustom and "custom" or EffectiveWhatToShow(element)
    local whatToShowProxy = { whatToShow = derived, _quiTransientOptionsProxy = true }
    ctx.AddFormRow(ns.L["What to Show"], ctx.GUI:CreateFormDropdown(ctx.detailArea, nil,
        WhatToShowOptions(element.auraType), "whatToShow", whatToShowProxy, function()
            local key = whatToShowProxy.whatToShow
            if key == "custom" then
                state.manualCustom = true
                ctx.SetDetailSectionExpanded("advanced", true)
                return
            end
            state.manualCustom = false
            E.ApplyWhatToShow(element, key)
            ctx.NotifyChanged()
            ctx.rebuild()
        end, {
            description = ns.L["Pick what this strip shows in plain terms. QUI writes the underlying filters. Choose Custom… (or edit Appearance & Advanced) for full control."],
            keywords = { "what to show", "intent", "dispellable", "defensives", "boss", "important" },
        }))
end

local function AddFilterStripConfig(ctx, element)
    local GUI = ctx.GUI
    local C = ctx.C
    local row = ctx.AddFormRow
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild
    local caps = ctx.caps
    local simple = caps.simpleMode == true

    if caps.fixedAuraType then
        element.auraType = caps.fixedAuraType
    end

    -- Simple Mode hoists the strip's identity — what it shows and how big —
    -- above the disclosure sections; the sections keep everything else.
    if simple then
        if not caps.fixedAuraType then
            AddAuraTypeRow(ctx, element)
        end
        AddWhatToShowRow(ctx, element)
        AddMaxIconsRow(ctx, element)
        AddIconSizeRow(ctx, element)
    end

    MakeSectionHeader(ctx, element, "basics", simple and ns.L["Placement"] or ns.L["Basics"])
    do
        if not simple and not caps.fixedAuraType then
            AddAuraTypeRow(ctx, element)
        end

        AddPlacementWidgets(ctx, element, true,
            simple and { maxIcons = true, iconSize = true } or nil)
    end

    MakeSectionHeader(ctx, element, "filters", ns.L["Filters"])
    do
        if not simple then
            AddWhatToShowRow(ctx, element)
        end
        row(ns.L["Nameplate Auras Only"], GUI:CreateFormCheckbox(ctx.detailArea, nil,
            "nameplateOnly", element, onChange, {
                description = ns.L["Only show auras Blizzard flags for nameplate display. Combines with everything above."],
                keywords = { "nameplate", "scope" },
            }))
        AddRoleGateRow(ctx, element)

        local unitPolarity = caps.unitPolarity
        if (unitPolarity == "friendly" and element.auraType == "HARMFUL")
            or (unitPolarity == "hostile" and element.auraType == "HELPFUL") then
            local warnText = (element.auraType == "HARMFUL")
                and ns.L["Blizzard disables per-spell debuff filtering on units you can assist, so critical incoming debuffs can't be hidden — the whitelist/blacklist below will not affect what shows here."]
                or ns.L["Blizzard disables per-spell buff filtering on units you cannot assist, so buffs can't be faked on enemies — the whitelist/blacklist below will not affect what shows here."]
            local warn = GUI:CreateLabel(ctx.detailArea, warnText, 11, C.warning)
            warn:SetJustifyH("LEFT")
            warn:SetWordWrap(true)
            warn:SetNonSpaceWrap(true)
            add(warn, 34, true)
        end

        if type(element.blacklist) ~= "table" then element.blacklist = {} end
        AddSpellMapEditor(ctx, element.blacklist,
            ns.L["Blacklisted Spells — never show. Buff lists apply on friendly units, debuff lists on enemies."],
            nil, {
                key = ctx.browsePrefix .. "blacklist:" .. tostring(element.id),
                title = ns.L["Add Blacklisted Spells"],
                presets = BuildFilterBrowsePresets(element.auraType),
            })
    end

    MakeSectionHeader(ctx, element, "advanced", ns.L["Appearance & Advanced"])
    do
        AddSwipeWidgets(ctx, element)
        AddTextRegionWidgets(ctx, element, "duration", ns.L["Duration Text"])
        AddTextRegionWidgets(ctx, element, "stack", ns.L["Stack Text"])

        row(ns.L["Sort Order"], GUI:CreateFormDropdown(ctx.detailArea, nil, SORT_OPTIONS, "sortRule", element, onChange, {
            description = ns.L["Order icons in this strip are displayed in."],
        }))
        row(ns.L["Reverse Sort"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "sortReverse", element, onChange, {
            description = ns.L["Reverse the sort order of icons in this strip."],
        }))

        if caps.cancelEligible and element.auraType == "HELPFUL" then
            row(ns.L["Right-Click to Cancel"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "rightClickCancel", element, onChange, {
                description = ns.L["Allow right-clicking an icon in this strip to cancel the aura."],
            }))
        end

        row(ns.L["Filter Mode"], GUI:CreateFormDropdown(ctx.detailArea, nil, FILTER_MODE_OPTIONS, "filterMode", element, function()
            ctx.NotifyChanged()
            rebuild()
        end, {
            description = ns.L["Off shows everything; Flags composes the raw aura filter tokens below; Classification shows only the categories ticked below; Spell Whitelist shows only the spells listed below."],
            keywords = { "filter", "include", "flags" },
        }))
        row(ns.L["Only My Auras"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "onlyMine", element, onChange, {
            description = ns.L["Only show auras you applied."],
            keywords = { "Only Mine", "mine only" },
        }))
        row(ns.L["Hide Permanent"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "hidePermanent", element, onChange, {
            description = ns.L["Hide auras with no remaining duration."],
        }))
        row(ns.L["Max Duration (seconds)"], GUI:CreateFormSlider(ctx.detailArea, nil, 0, 600, 5, "maxDurationSec", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Hide auras whose base duration is longer than this. 0 disables. Any value also hides permanent auras."],
        }))
        row(ns.L["Dispel Type Filter"], GUI:CreateFormDropdown(ctx.detailArea, nil, DISPEL_FILTER_MODE_OPTIONS, "dispelFilterMode", element, function()
            ctx.NotifyChanged()
            rebuild()
        end, {
            description = ns.L["Include or exclude auras by dispel type. Works on every unit."],
            keywords = { "dispel", "magic", "curse", "disease", "poison", "bleed" },
        }))
        if element.dispelFilterMode == "include" or element.dispelFilterMode == "exclude" then
            local bindTypes = element.dispelTypes
            local typesOnChange = onChange
            if bindTypes == "mine" then
                local DR = ns.QUI_DispelRoles
                local resolved = (DR and type(DR.PlayerDispelSchools) == "function" and DR.PlayerDispelSchools()) or {}
                local scratch = { _quiTransientOptionsProxy = true }
                for k, v in pairs(resolved) do scratch[k] = v end
                bindTypes = scratch
                typesOnChange = function(...)
                    local concrete = {}
                    for _, entry in ipairs(DISPEL_TYPES) do
                        if scratch[entry.key] then concrete[entry.key] = true end
                    end
                    element.dispelTypes = concrete
                    onChange(...)
                end
                local hint = GUI:CreateLabel(ctx.detailArea,
                    ns.L["Auto: matched to your class and spec dispels. Toggling a school pins a fixed set."],
                    11, C.textMuted)
                hint:SetJustifyH("LEFT")
                hint:SetWordWrap(true)
                hint:SetNonSpaceWrap(true)
                add(hint, 24, true)
            elseif type(bindTypes) ~= "table" then
                bindTypes = {}
                element.dispelTypes = bindTypes
            end
            for _, entry in ipairs(DISPEL_TYPES) do
                row(entry.label, GUI:CreateFormCheckbox(ctx.detailArea, nil, entry.key, bindTypes, typesOnChange, {
                    description = string.format(ns.L["Match auras with the %s dispel type."], entry.label),
                }))
            end
        end
        if element.auraType == "HELPFUL" then
            row(ns.L["Stealable (Purge)"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "gateStealable", element, onChange, {
                description = ns.L["Only show buffs that can be stolen or purged. Combines with the other filters."],
            }))
        end
        if element.auraType == "HARMFUL" then
            row(ns.L["Priority Debuffs"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "gatePriorityAura", element, onChange, {
                description = ns.L["Only show debuffs Blizzard flags as priority. Combines with the other filters."],
            }))
        end
        row(ns.L["Boss Auras"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "gateBossAura", element, onChange, {
            description = ns.L["Only show auras applied by bosses. Combines with the other filters."],
        }))
        row(ns.L["Role Auras"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "gateRoleAura", element, onChange, {
            description = ns.L["Only show role-relevant auras. Combines with the other filters."],
        }))
        row(ns.L["Boss or Role Auras"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "gateBossOrRoleAura", element, onChange, {
            description = ns.L["Only show auras that are boss-applied or role-relevant. Combines with the other filters."],
        }))

        row(ns.L["Hide Border"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "hideBorder", element, onChange, {
            description = ns.L["Hide the border drawn around icons in this strip."],
        }))
        row(ns.L["Custom Border Size"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "_customBorderSize", {
            _customBorderSize = element.borderSize ~= nil,
            _quiTransientOptionsProxy = true,
        }, function(checked)
            if checked and element.borderSize == nil then
                element.borderSize = 2
            elseif not checked then
                element.borderSize = nil
            end
            ctx.NotifyChanged()
            rebuild()
        end, {
            description = ns.L["Override the default border thickness for icons in this strip."],
        }))
        if element.borderSize ~= nil then
            row(ns.L["Border Size"], GUI:CreateFormSlider(ctx.detailArea, nil, 1, 6, 1, "borderSize", element, onChange, { deferOnDrag = true }, {
                description = ns.L["Border thickness in pixels for icons in this strip."],
            }))
        end
        row(ns.L["Custom Border Color"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "_customBorder", {
            _customBorder = element.borderColor ~= nil,
            _quiTransientOptionsProxy = true,
        }, function(checked)
            if checked and element.borderColor == nil then
                element.borderColor = { 1, 1, 1, 1 }
            elseif not checked then
                element.borderColor = nil
            end
            ctx.NotifyChanged()
            rebuild()
        end, {
            description = ns.L["Override the theme border color for icons in this strip."],
        }))
        if element.borderColor ~= nil then
            row(ns.L["Border Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "borderColor", element, onChange, nil, {
                description = ns.L["Border color for icons in this strip."],
            }))
        end

        AddDispelTooltipWidgets(ctx, element)

        local filterMode = element.filterMode or "off"
        if filterMode == "classify" then
            if type(element.classifications) ~= "table" then
                element.classifications = {}
            end
            local list = element.auraType == "HARMFUL" and HARMFUL_CLASSIFICATIONS or HELPFUL_CLASSIFICATIONS
            for _, entry in ipairs(list) do
                row(entry.label, GUI:CreateFormCheckbox(ctx.detailArea, nil, entry.key, element.classifications, onChange, {
                    description = ns.L["Include auras Blizzard flags as "] .. entry.label .. ".",
                }))
            end
        elseif filterMode == "flags" then
            if type(element.filterFlags) ~= "table" then
                element.filterFlags = {}
            end
            local tokens = element.auraType == "HARMFUL" and HARMFUL_FLAG_TOKENS or HELPFUL_FLAG_TOKENS
            for _, entry in ipairs(tokens) do
                local cur = element.filterFlags[entry.token]
                local scratchKey = tostring(element.id) .. "\31" .. entry.token
                local scratch = ctx._flagScratch[scratchKey]
                if not scratch then
                    scratch = {}
                    ctx._flagScratch[scratchKey] = scratch
                end
                scratch.value = (cur == true and "require") or (cur == "exclude" and "exclude") or "off"
                row(entry.label, GUI:CreateFormDropdown(ctx.detailArea, nil, TRI_STATE_OPTIONS, "value", scratch, function()
                    local v = scratch.value
                    if v == "require" then
                        element.filterFlags[entry.token] = true
                    elseif v == "exclude" then
                        element.filterFlags[entry.token] = "exclude"
                    else
                        element.filterFlags[entry.token] = nil
                    end
                    onChange()
                end, {
                    description = string.format(ns.L["Require or exclude the %s aura filter flag."], entry.label),
                }))
            end
        elseif filterMode == "whitelist" then
            if type(element.whitelist) ~= "table" then element.whitelist = {} end
            AddSpellMapEditor(ctx, element.whitelist,
                ns.L["Whitelisted Spells — only these show. Buff lists apply on friendly units, debuff lists on enemies; empty list shows everything."],
                nil, {
                    key = ctx.browsePrefix .. "whitelist:" .. tostring(element.id),
                    title = ns.L["Add Whitelisted Spells"],
                    presets = BuildFilterBrowsePresets(element.auraType),
                })
        end
    end
end

local function AddTrackedTypeConfig(ctx, element, skip)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild
    local caps = ctx.caps

    local displayType = element.displayType or "icon"
    if displayType == "healthTint" then
        if type(element.color) ~= "table" then element.color = { 0.2, 0.8, 0.2, 1 } end
        if type(element.healthTint) ~= "table" then element.healthTint = {} end
        row(ns.L["Tint Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
            description = ns.L["Color tint applied across the health bar while the aura is active."],
        }))
        row(ns.L["Tint Animation"], GUI:CreateFormDropdown(ctx.detailArea, nil, HEALTH_TINT_ANIMATION_OPTIONS, "animation", element.healthTint, onChange, {
            description = ns.L["How the health-bar tint appears when the aura is detected."],
        }))
    elseif displayType == "square" then
        if type(element.color) ~= "table" then element.color = { 0.2, 0.8, 0.2, 1 } end
        if not (skip and skip.iconSize) then
            row(ns.L["Square Size"], GUI:CreateFormSlider(ctx.detailArea, nil, 4, 40, 1, "iconSize", element, onChange, { deferOnDrag = true }, {
                description = ns.L["Pixel size of the colored square."],
            }))
        end
        if not caps.containerLayout then
            row(ns.L["Anchor"], GUI:CreateFormDropdown(ctx.detailArea, nil, NINE_POINT_OPTIONS, "anchor", element, onChange, {
                description = ns.L["Where on the frame the square is anchored."],
            }))
            row(ns.L["X Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetX", element, onChange, { deferOnDrag = true }, {
                description = ns.L["Horizontal pixel offset from the anchor."],
            }))
            row(ns.L["Y Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetY", element, onChange, { deferOnDrag = true }, {
                description = ns.L["Vertical pixel offset from the anchor."],
            }))
        end
        if not (skip and skip.color) then
            row(ns.L["Square Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
                description = ns.L["Fill color of the colored square."],
            }))
        end
    elseif displayType == "bar" then
        if type(element.color) ~= "table" then element.color = { 0.2, 0.8, 0.2, 1 } end
        if type(element.bar) ~= "table" then element.bar = { thickness = 12, length = 48 } end
        if not caps.containerLayout then
            row(ns.L["Anchor"], GUI:CreateFormDropdown(ctx.detailArea, nil, NINE_POINT_OPTIONS, "anchor", element, onChange, {
                description = ns.L["Where on the frame the bar is anchored."],
            }))
            row(ns.L["X Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetX", element, onChange, { deferOnDrag = true }, {
                description = ns.L["Horizontal pixel offset from the anchor."],
            }))
            row(ns.L["Y Offset"], GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetY", element, onChange, { deferOnDrag = true }, {
                description = ns.L["Vertical pixel offset from the anchor."],
            }))
        end
        row(ns.L["Orientation"], GUI:CreateFormDropdown(ctx.detailArea, nil, BAR_ORIENTATION_OPTIONS, "orientation", element.bar, onChange, {
            description = ns.L["Whether the bar drains horizontally or vertically as the aura ticks down."],
        }))
        if not (skip and skip.color) then
            row(ns.L["Bar Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
                description = ns.L["Fill color of the bar while the aura is active."],
            }))
        end
        row(ns.L["Background Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "backgroundColor", element.bar, onChange, nil, {
            description = ns.L["Color drawn behind the bar fill."],
        }))
        row(ns.L["Thickness"], GUI:CreateFormSlider(ctx.detailArea, nil, 1, 40, 1, "thickness", element.bar, onChange, { deferOnDrag = true }, {
            description = ns.L["Pixel thickness of the bar."],
        }))
        if not (skip and skip.length) then
            row(ns.L["Length"], GUI:CreateFormSlider(ctx.detailArea, nil, 4, 200, 1, "length", element.bar, onChange, { deferOnDrag = true }, {
                description = ns.L["Pixel length of the bar."],
            }))
        end
        row(ns.L["Match Frame Width / Height"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "matchFrameSize", element.bar, onChange, {
            description = ns.L["Stretch the bar to match the frame size."],
        }))
        row(ns.L["Hide Border"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "hideBorder", element.bar, onChange, {
            description = ns.L["Remove the border drawn around the bar."],
        }))
        row(ns.L["Border Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "borderColor", element.bar, onChange, nil, {
            description = ns.L["Color of the bar's border."],
        }))
        row(ns.L["Border Size"], GUI:CreateFormSlider(ctx.detailArea, nil, 1, 8, 1, "borderSize", element.bar, onChange, { deferOnDrag = true }, {
            description = ns.L["Pixel thickness of the bar's border."],
        }))
        local barCfg = element.bar
        row(ns.L["Color When Expiring"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "_lowTimeColorOn", {
            _lowTimeColorOn = barCfg.lowTimeColor ~= nil,
            _quiTransientOptionsProxy = true,
        }, function(checked)
            if checked and barCfg.lowTimeColor == nil then
                barCfg.lowTimeColor = { 1, 0.35, 0.2, 1 }
            elseif not checked then
                barCfg.lowTimeColor = nil
            end
            ctx.NotifyChanged()
            rebuild()
        end, {
            description = ns.L["Recolor the bar inside the game's refresh window (roughly the final 30% of the aura's duration). The window is engine-driven, so this keeps working in combat; a custom seconds threshold is not possible there."],
            keywords = { "low time", "expiring", "pandemic" },
        }))
        if barCfg.lowTimeColor then
            row(ns.L["Expiring Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "lowTimeColor", element.bar, onChange, nil, {
                description = ns.L["Bar color while the aura is inside the refresh window."],
            }))
        end
    elseif displayType == "border" then
        if type(element.color) ~= "table" then element.color = { 0.2, 0.8, 0.2, 1 } end
        if type(element.border) ~= "table" then element.border = { thickness = 2 } end
        row(ns.L["Border Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
            description = ns.L["Outline color drawn around the frame while the aura is active."],
        }))
        row(ns.L["Thickness"], GUI:CreateFormSlider(ctx.detailArea, nil, 1, 16, 1, "thickness", element.border, onChange, { deferOnDrag = true }, {
            description = ns.L["Pixel thickness of the border outline."],
        }))
    else
        AddPlacementWidgets(ctx, element, true, skip)
        AddSwipeWidgets(ctx, element)
        AddTextRegionWidgets(ctx, element, "duration", ns.L["Duration Text"])
        AddTextRegionWidgets(ctx, element, "stack", ns.L["Stack Text"])
        AddDispelTooltipWidgets(ctx, element)
    end
end

-- What Simple Mode keeps in view per display type; everything else folds into
-- the Appearance & Placement section.
local SIMPLE_TRACKED_HOISTS = {
    icon   = { iconSize = true },
    square = { iconSize = true, color = true },
    bar    = { color = true, length = true },
}

local function AddTrackedEssentialRows(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    local displayType = element.displayType or "icon"

    if displayType == "icon" then
        AddIconSizeRow(ctx, element)
    elseif displayType == "square" then
        if type(element.color) ~= "table" then element.color = { 0.2, 0.8, 0.2, 1 } end
        row(ns.L["Square Size"], GUI:CreateFormSlider(ctx.detailArea, nil, 4, 40, 1, "iconSize", element, onChange, { deferOnDrag = true }, {
            description = ns.L["Pixel size of the colored square."],
        }))
        row(ns.L["Square Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
            description = ns.L["Fill color of the colored square."],
        }))
    elseif displayType == "bar" then
        if type(element.color) ~= "table" then element.color = { 0.2, 0.8, 0.2, 1 } end
        if type(element.bar) ~= "table" then element.bar = { thickness = 12, length = 48 } end
        row(ns.L["Bar Color"], GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
            description = ns.L["Fill color of the bar while the aura is active."],
        }))
        row(ns.L["Length"], GUI:CreateFormSlider(ctx.detailArea, nil, 4, 200, 1, "length", element.bar, onChange, { deferOnDrag = true }, {
            description = ns.L["Pixel length of the bar."],
        }))
    end
end

local function AddTrackedConfig(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild
    local caps = ctx.caps
    local simple = caps.simpleMode == true

    AddTrackedSpellListEditor(ctx, element)

    local displayOptions = BuildTrackedDisplayOptions(caps.trackedDisplayTypes)
    row(ns.L["Display Type"], GUI:CreateFormDropdown(ctx.detailArea, nil, displayOptions, "displayType", element, function()
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = ns.L["How this tracked aura displays: an icon strip, a colored square, a duration bar, or a health-bar tint."],
    }))
    row(ns.L["Aura Type"], GUI:CreateFormDropdown(ctx.detailArea, nil, AURA_TYPE_OPTIONS, "auraType", element, onChange, {
        description = ns.L["Whether this tracked aura is a helpful buff or a harmful debuff."],
    }))
    row(ns.L["Only My Cast"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "onlyMine", element, onChange, {
        description = ns.L["Only track this aura when you applied it."],
        keywords = { "Only Mine", "mine only" },
    }))

    if simple then
        -- Essentials stay in view: the spells being tracked (hoisted above)
        -- plus size/color. The old 30-row wall folds into one collapsed section.
        AddTrackedEssentialRows(ctx, element)
        AddRoleGateRow(ctx, element)
        local displayType = element.displayType or "icon"
        if displayType == "icon" or displayType == "square" or displayType == "bar" then
            MakeSectionHeader(ctx, element, "appearance", ns.L["Appearance & Placement"])
            AddTrackedTypeConfig(ctx, element, SIMPLE_TRACKED_HOISTS[displayType])
        else
            AddTrackedTypeConfig(ctx, element, nil)
        end
        return
    end

    AddTrackedTypeConfig(ctx, element, nil)
    AddRoleGateRow(ctx, element)
end

local function AddMissingRaidBuffConfig(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild

    row(ns.L["Auto-Detect My Buff"], GUI:CreateFormCheckbox(ctx.detailArea, nil, "classDetection", element, function()
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = ns.L["Only show the raid buff provided by your current class. Turn this off to choose buffs manually."],
    }), true)

    if element.classDetection == false then
        if type(element.buffChecks) ~= "table" then
            element.buffChecks = {}
        end
        for _, entry in ipairs(MISSING_RAID_BUFF_OPTIONS) do
            row(entry.label, GUI:CreateFormCheckbox(ctx.detailArea, nil, entry.key, element.buffChecks, onChange, {
                description = ns.L["Show this icon when the unit is missing this raid buff."],
            }))
        end
        local merged = MissingRaidBuffs and MissingRaidBuffs.RaidBuffs
        if type(merged) == "table" then
            for _, entry in ipairs(merged) do
                if entry.source == "cdm" then
                    row(entry.label or entry.key, GUI:CreateFormCheckbox(ctx.detailArea, nil, entry.key, element.buffChecks, onChange, {
                        description = ns.L["Show this icon when the unit is missing this raid buff."],
                    }))
                end
            end
        end
    end

    AddPlacementWidgets(ctx, element, true)
    AddRoleGateRow(ctx, element)
end

local function ReleaseRows(activeRows, pool)
    for _, row in ipairs(activeRows) do
        row:Hide()
        row:ClearAllPoints()
        if row.enable then row.enable:SetScript("OnClick", nil) end
        if row.delete then row.delete:SetScript("OnClick", nil) end
        row:SetScript("OnClick", nil)
        table.insert(pool, row)
    end
    wipe(activeRows)
end

local function RenderDetail(ctx, element)
    ctx.ClearDetailWidgets()
    ctx.RelayoutDetail = nil
    ctx.BeginDetailSection = nil
    ctx.SetDetailSectionExpanded = nil
    ctx.UpdateDetailWidgetHeight = nil
    ctx._detailSectionCarets = {}
    ctx._detailSectionKey = nil
    if not element then
        ctx.detailArea:SetHeight(1)
        return 0
    end

    ctx._detailScope = element.id or tostring(element)

    local detailArea = ctx.detailArea
    ctx.detailY = -2
    ctx._pendingWidget = nil
    ctx._pendingHeight = 0
    local detailRows = {}

    local function EmitRow(left, leftH, right, rightH, span)
        local rowH = span and leftH or (right and math.max(leftH, rightH) or leftH)
        local rowFrame = table.remove(ctx._detailRowPool)
        if not rowFrame then
            rowFrame = CreateFrame("Frame", nil, detailArea)
        end
        rowFrame:Show()
        ctx.RegisterDetailWidget(rowFrame)
        rowFrame:ClearAllPoints()
        rowFrame:SetPoint("TOPLEFT", detailArea, "TOPLEFT", 0, ctx.detailY)
        rowFrame:SetPoint("TOPRIGHT", detailArea, "TOPRIGHT", 0, ctx.detailY)
        rowFrame:SetHeight(rowH)
        rowFrame._quiDetailHeight = rowH
        rowFrame._quiDetailSection = ctx._detailSectionKey
        rowFrame._quiDetailOwner = detailRows
        detailRows[#detailRows + 1] = rowFrame

        if rowFrame._quiColDiv then rowFrame._quiColDiv:Hide() end

        if span then
            if rowFrame._quiRowBG then rowFrame._quiRowBG:Hide() end
            rowFrame._quiDetailBackground = nil
        else
            local bg = rowFrame._quiRowBG
            if not bg then
                bg = rowFrame:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(rowFrame)
                rowFrame._quiRowBG = bg
            end
            bg:SetColorTexture(1, 1, 1, 0)
            bg:Show()
            rowFrame._quiDetailBackground = bg
        end

        rowFrame._quiLeft = left
        left:SetParent(rowFrame)
        left._quiDetailRow = rowFrame
        left:ClearAllPoints()
        if span then
            left:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", PAD, 0)
            left:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -PAD, 0)
        elseif right then
            left:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", PAD, 0)
            left:SetPoint("TOPRIGHT", rowFrame, "TOP", -(COL_GAP / 2), 0)
            rowFrame._quiRight = right
            right:SetParent(rowFrame)
            right._quiDetailRow = rowFrame
            right:ClearAllPoints()
            right:SetPoint("TOPLEFT", rowFrame, "TOP", COL_GAP / 2, 0)
            right:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -PAD, 0)

            local cdiv = rowFrame._quiColDiv
            if not cdiv then
                cdiv = rowFrame:CreateTexture(nil, "ARTWORK")
                rowFrame._quiColDiv = cdiv
            end
            cdiv:ClearAllPoints()
            cdiv:SetPoint("TOP", rowFrame, "TOP", 0, -6)
            cdiv:SetPoint("BOTTOM", rowFrame, "BOTTOM", 0, 6)
            cdiv:SetWidth(1)
            cdiv:SetColorTexture(1, 1, 1, 0.05)
            cdiv:Show()
        else
            left:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", PAD, 0)
            left:SetPoint("TOPRIGHT", rowFrame, "TOP", -(COL_GAP / 2), 0)
        end

        ctx.detailY = ctx.detailY - rowH
    end

    local function FlushPending()
        if ctx._pendingWidget then
            EmitRow(ctx._pendingWidget, ctx._pendingHeight, nil, nil, false)
            ctx._pendingWidget = nil
            ctx._pendingHeight = 0
        end
    end

    ctx.BeginDetailSection = function(header, height, sectionKey)
        FlushPending()
        ctx._detailSectionKey = nil
        EmitRow(header, height, nil, nil, true)
        ctx._detailSectionKey = sectionKey
    end

    ctx.AddDetailWidget = function(widget, height, span)
        if span then
            FlushPending()
            EmitRow(widget, height, nil, nil, true)
            return
        end
        if ctx._pendingWidget then
            EmitRow(ctx._pendingWidget, ctx._pendingHeight, widget, height, false)
            ctx._pendingWidget = nil
            ctx._pendingHeight = 0
        else
            ctx._pendingWidget = widget
            ctx._pendingHeight = height
        end
    end

    local optionsAPI = GetOptionsAPI()
    ctx.AddFormRow = function(label, widget, span)
        local cell = widget
        if optionsAPI and optionsAPI.BuildSettingRow then
            cell = widget._quiSettingCell
            if not cell then
                cell = optionsAPI.BuildSettingRow(detailArea, label, widget)
                if cell and cell ~= widget then
                    widget._quiSettingCell = cell
                end
            end
        end
        ctx.AddDetailWidget(cell or widget, FORM_ROW, span)
    end

    local function RelayoutDetail()
        local disclosure = sectionState(element)
        local y = -2
        local rowParity = 0
        for _, rowFrame in ipairs(detailRows) do
            local sectionKey = rowFrame._quiDetailSection
            local visible = not sectionKey or disclosure[sectionKey] == true
            if visible then
                rowFrame:ClearAllPoints()
                rowFrame:SetPoint("TOPLEFT", detailArea, "TOPLEFT", 0, y)
                rowFrame:SetPoint("TOPRIGHT", detailArea, "TOPRIGHT", 0, y)
                rowFrame:Show()
                if rowFrame._quiDetailBackground then
                    rowFrame._quiDetailBackground:SetColorTexture(
                        1, 1, 1, (rowParity % 2) == 1 and 0.02 or 0)
                    rowParity = rowParity + 1
                end
                y = y - rowFrame._quiDetailHeight
            else
                rowFrame:Hide()
            end
        end
        ctx.detailY = y
        local used = math.abs(y) + 8
        detailArea:SetHeight(used)
        return used
    end
    ctx.RelayoutDetail = RelayoutDetail
    ctx.SetDetailSectionExpanded = function(sectionKey, expanded)
        local disclosure = sectionState(element)
        disclosure[sectionKey] = expanded == true
        local caret = ctx._detailSectionCarets[sectionKey]
        if caret and ns.UIKit and ns.UIKit.SetChevronCaretExpanded then
            ns.UIKit.SetChevronCaretExpanded(caret, disclosure[sectionKey])
        end
        if not disclosure[sectionKey] and SpellList and SpellList.CloseBrowsePopup then
            SpellList.CloseBrowsePopup(ctx.browsePrefix)
        end
        RelayoutDetail()
        if ctx.RelayoutList then
            ctx.RelayoutList()
        end
    end
    ctx.UpdateDetailWidgetHeight = function(widget, newHeight)
        local rowFrame = widget and widget._quiDetailRow
        if not rowFrame or rowFrame._quiDetailOwner ~= detailRows or type(newHeight) ~= "number" then
            return
        end
        newHeight = math.max(1, newHeight)
        if rowFrame._quiDetailHeight == newHeight then
            return
        end
        rowFrame._quiDetailHeight = newHeight
        rowFrame:SetHeight(newHeight)
        RelayoutDetail()
        if ctx.RelayoutList then
            ctx.RelayoutList()
        end
    end

    -- Simple Mode: a plain-language readback of the element's real settings,
    -- pinned above the form so the controls below stay learnable.
    ctx.RefreshSummary = nil
    if ctx.caps.simpleMode then
        local summary = ctx._summaryLabel
        if not summary then
            summary = detailArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            CJKFont(summary, ctx.GUI.FONT_PATH or [[Interface\AddOns\QUI\assets\Quazii.ttf]], 11, "")
            summary:SetJustifyH("LEFT")
            summary:SetWordWrap(true)
            summary:SetNonSpaceWrap(true)
            local mc = ctx.C.textMuted or { 1, 1, 1, 0.6 }
            summary:SetTextColor(mc[1], mc[2], mc[3], mc[4] or 0.6)
            ctx._summaryLabel = summary
        end
        local T = ns.QUI_AuraDisplayTemplates
        if T and type(T.BuildElementSummary) == "function" then
            ctx.RefreshSummary = function()
                summary:SetText(T.BuildElementSummary(element, ctx.caps.summaryUnit))
            end
            ctx.RefreshSummary()
            ctx.AddDetailWidget(summary, 26, true)
        end
    end

    if not ctx.caps.singleStrip then
        ctx.AddFormRow(ns.L["Element Enabled"], ctx.GUI:CreateFormCheckbox(ctx.detailArea, nil, "enabled", element, function()
            ctx.NotifyChanged()
            ctx.rebuild()
        end, {
            description = ns.L["Toggle this element. When off, it does not display."],
        }), true)
    end

    if element.mode == "filterStrip" then
        AddFilterStripConfig(ctx, element)
    elseif element.mode == "missingRaidBuff" then
        AddMissingRaidBuffConfig(ctx, element)
    else
        AddTrackedConfig(ctx, element)
    end

    FlushPending()
    ctx._detailSectionKey = nil

    return RelayoutDetail()
end

local function RelayoutList(ctx)
    local contentHeight

    if ctx.caps.singleStrip then
        ctx.detailArea:ClearAllPoints()
        ctx.detailArea:SetParent(ctx.listArea)
        ctx.detailArea:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, 0)
        ctx.detailArea:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, 0)
        ctx.detailArea:Show()
        contentHeight = math.max(1, ctx.detailArea:GetHeight() or 1)
    else
        local listY = 0
        for index, row in ipairs(ctx.activeRows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, listY)
            row:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, listY)
            listY = listY - ROW_STEP

            if index == ctx.selectedIndex then
                listY = listY - 2
                ctx.detailArea:ClearAllPoints()
                ctx.detailArea:SetParent(ctx.listArea)
                ctx.detailArea:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", PAD, listY)
                ctx.detailArea:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, listY)
                ctx.detailArea:Show()
                listY = listY - math.max(1, ctx.detailArea:GetHeight() or 1) - 4
            end
        end

        if #ctx.bucket == 0 then
            ctx.emptyLabel:ClearAllPoints()
            ctx.emptyLabel:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, listY)
            ctx.emptyLabel:Show()
            listY = listY - 22
        else
            ctx.emptyLabel:Hide()
        end

        if ctx.selectedIndex == nil then
            ctx.detailArea:Hide()
        end

        if ctx.hasAddButtons then
            ctx.UpdateAddStripState()
            listY = listY - 8
            ctx.addRow:ClearAllPoints()
            ctx.addRow:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, listY)
            ctx.addRow:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, listY)
            ctx.addRow:Show()
            listY = listY - 30
        else
            ctx.addRow:Hide()
        end

        contentHeight = math.max(1, math.abs(listY))
    end

    ctx.listArea:SetHeight(contentHeight)
    local hostHeight = contentHeight + 8
    ctx.host:SetHeight(hostHeight)

    if not ctx.caps.singleStrip and ctx.onSelectionChanged then
        ctx.onSelectionChanged(ctx.selectedIndex)
    end
    if ctx.onLayoutChanged then
        ctx.onLayoutChanged(hostHeight)
    end
    return hostHeight
end

local function RebuildList(ctx)
    local bucket = ctx.bucket
    ctx.ReleaseRows()
    ctx.ClearDetailWidgets()

    if SpellList and SpellList.BeginBrowseScope then
        SpellList.BeginBrowseScope(ctx.browsePrefix)
    end

    if ctx.caps.singleStrip then
        local element
        for _, e in ipairs(bucket) do
            if e.mode == "filterStrip" then element = e break end
        end
        if not element then
            local seeded = type(ctx.caps.defaultBucketFn) == "function" and ctx.caps.defaultBucketFn() or nil
            if seeded then
                for _, e in ipairs(seeded) do
                    if e.mode == "filterStrip" then element = e break end
                end
            end
            element = element or (E.NewFilterStripElement and E.NewFilterStripElement(ctx.caps.fixedAuraType or "HELPFUL"))
            if element then
                bucket[#bucket + 1] = element
                ctx.NotifyChanged()
            end
        end
        ctx.emptyLabel:Hide()
        ctx.addRow:Hide()
        RenderDetail(ctx, element)
        if SpellList and SpellList.EndBrowseScope then
            SpellList.EndBrowseScope(ctx.browsePrefix)
        end
        RelayoutList(ctx)
        return
    end

    if #bucket == 0 then
        ctx.selectedIndex = nil
    elseif ctx.selectedIndex and ctx.selectedIndex > #bucket then
        ctx.selectedIndex = #bucket
    end

    local C = ctx.C
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }

    for index, element in ipairs(bucket) do
        local row = ctx.AcquireRow()
        row:SetParent(ctx.listArea)
        row:Show()

        local label, icon = GetElementLabel(element)
        row.name:ClearAllPoints()
        if icon then
            row.icon:SetTexture(icon)
            row.icon:Show()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        else
            row.icon:Hide()
            row.name:SetPoint("LEFT", row.enable, "RIGHT", 6, 0)
        end
        row.name:SetPoint("RIGHT", row.badge, "LEFT", -6, 0)
        local nameColor = element.enabled ~= false and "|cFFFFFFFF" or "|cFF808080"
        row.name:SetText(nameColor .. label .. "|r")

        if element.mode == "filterStrip" then
            row.badge:SetText("|cFF56D1FF" .. ns.L["STRIP"] .. "|r")
        elseif element.mode == "missingRaidBuff" then
            row.badge:SetText("|cFFFFD166" .. ns.L["RAID BUFF"] .. "|r")
        else
            row.badge:SetText("|cFFC8A2FF" .. ns.L["TRACKED"] .. "|r")
        end

        row.enable:SetToggleState(element.enabled ~= false)
        row.enable:SetScript("OnClick", function()
            element.enabled = (element.enabled == false)
            ctx.NotifyChanged()
            ctx.rebuild()
        end)

        local expanded = index == ctx.selectedIndex
        if ns.UIKit and ns.UIKit.SetChevronCaretExpanded and row.chevron then
            ns.UIKit.SetChevronCaretExpanded(row.chevron, expanded)
        end

        if expanded then
            row.bg:SetColorTexture(accent[1], accent[2], accent[3], 0.10)
        elseif (index % 2) == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.02)
        else
            row.bg:SetColorTexture(1, 1, 1, 0)
        end

        row:SetScript("OnClick", function()
            if ctx.selectedIndex == index then
                ctx.selectedIndex = nil
            else
                ctx.selectedIndex = index
            end
            ctx.rebuild()
        end)
        row.delete:SetScript("OnClick", function()
            table.remove(bucket, index)
            if ctx.selectedIndex == index then
                ctx.selectedIndex = nil
            elseif ctx.selectedIndex and ctx.selectedIndex > index then
                ctx.selectedIndex = ctx.selectedIndex - 1
            end
            ctx.NotifyChanged()
            ctx.rebuild()
        end)

        ctx.activeRows[#ctx.activeRows + 1] = row

        if expanded then
            RenderDetail(ctx, element)
        end
    end

    if SpellList and SpellList.EndBrowseScope then
        SpellList.EndBrowseScope(ctx.browsePrefix)
    end

    RelayoutList(ctx)
end

function AurasEditor.RenderAuras(host, auras, bucketKey, onChange, opts)
    local GUI = GetGUI()
    if not host or not GUI or type(auras) ~= "table" or not E then
        return 1
    end

    local caps = ResolveCapabilities(opts)

    if type(auras.elements) ~= "table" then
        auras.elements = {}
    end
    if E.EnsureSeeded then
        E.EnsureSeeded(auras, caps.defaultBucketFn)
    end

    bucketKey = bucketKey or "*"
    if not caps.allowSpecOverride then
        bucketKey = "*"
    end
    if bucketKey == "*" and type(auras.elements["*"]) ~= "table" then
        auras.elements["*"] = {}
    end

    local C = GUI.Colors or {}

    browseInstanceCounter = browseInstanceCounter + 1
    local browsePrefix = "aurased" .. browseInstanceCounter .. ":"

    local listArea = CreateFrame("Frame", nil, host)
    listArea:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    listArea:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    listArea:SetHeight(1)
    listArea:SetScript("OnHide", function()
        if SpellList and SpellList.CloseBrowsePopup then
            SpellList.CloseBrowsePopup(browsePrefix)
        end
    end)

    local emptyLabel = GUI:CreateLabel(listArea, ns.L["No aura elements in this bucket yet. Add one below."], 11, C.textMuted)
    emptyLabel:SetJustifyH("LEFT")
    emptyLabel:Hide()

    local detailArea = CreateFrame("Frame", nil, listArea)
    detailArea:SetHeight(1)
    detailArea:Hide()

    local addRow = CreateFrame("Frame", nil, listArea)
    addRow:SetHeight(26)
    local elementTypes = caps.elementTypes or {}
    local addTrackedButton, addStripButton, addMissingBuffButton
    local lastAddButton
    local function PlaceAddButton(button)
        button:ClearAllPoints()
        if lastAddButton then
            button:SetPoint("LEFT", lastAddButton, "RIGHT", 8, 0)
        else
            button:SetPoint("LEFT", addRow, "LEFT", 0, 0)
        end
        lastAddButton = button
    end
    if elementTypes.tracked then
        addTrackedButton = GUI:CreateButton(addRow, ns.L["Add Tracked Aura"], 130, 22)
        PlaceAddButton(addTrackedButton)
    end
    if elementTypes.filterStrip then
        addStripButton = GUI:CreateButton(addRow, ns.L["Add Filter Strip"], 130, 22)
        PlaceAddButton(addStripButton)
    end
    if elementTypes.missingRaidBuff then
        addMissingBuffButton = GUI:CreateButton(addRow, ns.L["Add Missing Raid Buff"], 170, 22)
        PlaceAddButton(addMissingBuffButton)
    end

    local rowPool = {}
    local activeRows = {}
    local detailWidgets = {}
    local detailRowPool = {}
    local detailWidgetBin = CreateFrame("Frame", nil, listArea)
    detailWidgetBin:Hide()

    local ctx = {
        GUI = GUI,
        _detailRowPool = detailRowPool,
        _sectionHeaders = {},
        _accentDotLabels = {},
        _spellMapEditors = {},
        _trackedMapViews = {},
        _flagScratch = {},
        C = C,
        host = host,
        auras = auras,
        caps = caps,
        bucket = auras.elements[bucketKey],
        onChangeRaw = onChange,
        listArea = listArea,
        emptyLabel = emptyLabel,
        detailArea = detailArea,
        addRow = addRow,
        addStripButton = addStripButton,
        activeRows = activeRows,
        browsePrefix = browsePrefix,
        selectedIndex = nil,
        hasAddButtons = (addTrackedButton ~= nil) or (addStripButton ~= nil) or (addMissingBuffButton ~= nil),
        onSelectionChanged = (type(opts) == "table" and type(opts.onSelectionChanged) == "function")
            and opts.onSelectionChanged or nil,
        onLayoutChanged = (type(opts) == "table" and type(opts.onLayoutChanged) == "function")
            and opts.onLayoutChanged or nil,
    }

    local function NotifyChanged()
        if type(onChange) == "function" then
            onChange()
        end
    end
    ctx.NotifyChanged = NotifyChanged
    ctx.onChange = function()
        NotifyChanged()
        if ctx.RefreshSummary then ctx.RefreshSummary() end
    end

    local rebuilding = false
    local rebuild
    rebuild = function()
        if rebuilding then
            return
        end
        rebuilding = true
        local ok, err = pcall(RebuildList, ctx)
        rebuilding = false
        if not ok then
            error(err, 0)
        end
    end
    ctx.rebuild = rebuild
    ctx.RelayoutList = function()
        return RelayoutList(ctx)
    end

    ctx.GUI = CreateDetailGUI(ctx, GUI)

    ctx.ClearDetailWidgets = function()
        for _, widget in ipairs(detailWidgets) do
            widget:Hide()
            widget:ClearAllPoints()
            if widget._quiLeft then
                widget._quiLeft:SetParent(detailWidgetBin)
                widget._quiLeft = nil
            end
            if widget._quiRight then
                widget._quiRight:SetParent(detailWidgetBin)
                widget._quiRight = nil
            end
            widget._quiDetailOwner = nil
            detailRowPool[#detailRowPool + 1] = widget
        end
        wipe(detailWidgets)
    end
    ctx.RegisterDetailWidget = function(widget)
        detailWidgets[#detailWidgets + 1] = widget
        return widget
    end

    ctx.UpdateAddStripState = function()
        local b = ctx.addStripButton
        if not b then return end
        local cap = ctx.caps.maxStripElements
        if not cap then
            b._atCap = false
            b:SetAlpha(1)
            return
        end
        local n = 0
        for _, e in ipairs(ctx.bucket) do
            if e.mode == "filterStrip" and e.enabled ~= false then
                n = n + 1
            end
        end
        local atCap = n >= cap
        b._atCap = atCap
        b:SetAlpha(atCap and 0.4 or 1)
    end

    ctx.AcquireRow = function()
        local row = table.remove(rowPool)
        if row then
            row:Show()
            return row
        end

        row = CreateFrame("Button", nil, listArea)
        row:SetHeight(ROW_HEIGHT)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetColorTexture(1, 1, 1, 0)

        local UIKit = ns.UIKit
        if UIKit and UIKit.CreateChevronCaret then
            row.chevron = UIKit.CreateChevronCaret(row, {
                point = "LEFT", relativeTo = row, relativePoint = "LEFT",
                xPixels = 8, sizePixels = 8, collapsedDirection = "right",
                expanded = false,
                r = (C.text and C.text[1]) or 1,
                g = (C.text and C.text[2]) or 1,
                b = (C.text and C.text[3]) or 1,
                a = 0.85,
            })
        end

        row.enable = SpellList and SpellList.CreateMiniToggle and SpellList.CreateMiniToggle(row) or nil
        if not row.enable then
            row.enable = CreateFrame("Button", nil, row)
            row.enable:SetSize(26, 14)
            row.enable.SetToggleState = function() end
        end
        row.enable:SetPoint("LEFT", row, "LEFT", 22, 0)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row.enable, "RIGHT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        CJKFont(row.name, (GUI.FONT_PATH) or [[Interface\AddOns\QUI\assets\Quazii.ttf]], 12, "")
        row.name:SetJustifyH("LEFT")

        row.delete = GUI:CreateButton(row, ns.L["Delete"], 56, 18)
        row.delete:SetPoint("RIGHT", row, "RIGHT", -6, 0)

        row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.badge:SetJustifyH("RIGHT")
        row.badge:SetPoint("RIGHT", row.delete, "LEFT", -8, 0)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.badge, "LEFT", -6, 0)

        return row
    end
    ctx.ReleaseRows = function()
        ReleaseRows(activeRows, rowPool)
    end

    ctx.AddTracked = function(spellID)
        spellID = tonumber(spellID) or spellID
        local element = E.NewTrackedElement(spellID and { spellID } or {}, DefaultTrackedDisplay(ctx.caps))
        ctx.bucket[#ctx.bucket + 1] = element
        ctx.selectedIndex = #ctx.bucket
        NotifyChanged()
        rebuild()
    end

    ctx.AddFilterStrip = function()
        local hasBuff = false
        for _, element in ipairs(ctx.bucket) do
            if element.mode == "filterStrip" and element.auraType == "HELPFUL" then
                hasBuff = true
            end
        end
        local element = E.NewFilterStripElement(hasBuff and "HARMFUL" or "HELPFUL")
        ctx.bucket[#ctx.bucket + 1] = element
        ctx.selectedIndex = #ctx.bucket
        NotifyChanged()
        rebuild()
    end

    ctx.AddMissingRaidBuff = function()
        if not E.NewMissingRaidBuffElement then return end
        local element = E.NewMissingRaidBuffElement()
        ctx.bucket[#ctx.bucket + 1] = element
        ctx.selectedIndex = #ctx.bucket
        NotifyChanged()
        rebuild()
    end

    if addStripButton then
        addStripButton:SetScript("OnClick", function(self)
            if self._atCap then return end
            ctx.AddFilterStrip()
        end)
        addStripButton:HookScript("OnEnter", function(self)
            if self._atCap and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetFrameStrata("TOOLTIP")
                GameTooltip:AddLine(ns.L["Maximum filter strips reached for these frames."], 1, 0.82, 0)
                GameTooltip:Show()
            end
        end)
        addStripButton:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    if addMissingBuffButton then
        addMissingBuffButton:SetScript("OnClick", function()
            ctx.AddMissingRaidBuff()
        end)
    end
    if addTrackedButton then
        addTrackedButton:SetScript("OnClick", function()
            ctx.AddTracked()
        end)
    end

    if opts and type(opts.forceSelectedIndex) == "number" then
        ctx.selectedIndex = opts.forceSelectedIndex
    end

    rebuild()
    return host:GetHeight()
end

return AurasEditor
