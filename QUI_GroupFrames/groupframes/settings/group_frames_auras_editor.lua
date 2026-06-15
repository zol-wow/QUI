local ADDON_NAME, ns = ...

-- Unified Auras editor: renders the element list for a single spec bucket of
-- auras.elements (the v46 model from groupframes_aura_model.lua). Each element
-- is a filterStrip (Buffs/Debuffs) or a tracked element (icon/square/bar/tint).
-- Reuses the spell-picker UX (suggestion grid + manual spellID) salvaged from
-- the old tracked-aura/pinned editors.

local Model = ns.QUI_GroupFramesAuraModel
local AuraDefaults = ns.QUI_GroupFramesAuraDefaults
local SpellList = ns.QUI_GroupFramesSpellListSettings
local SkinBase = ns.SkinBase

local AurasEditor = ns.QUI_GroupFramesAurasSettings or {}
ns.QUI_GroupFramesAurasSettings = AurasEditor

local FORM_ROW = 32
local PAD = 10
local COL_GAP = 12
local ROW_HEIGHT = 30
local ROW_STEP = 32
local SUGGEST_CELL_SIZE = 36
local SUGGEST_ICON_SIZE = 28
local SUGGEST_CELL_GAP = 2
local SUGGEST_CELL_STRIDE = SUGGEST_CELL_SIZE + SUGGEST_CELL_GAP
local FALLBACK_ICON = 134400

local NINE_POINT_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOP", text = "Top" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local AURA_GROW_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
    { value = "CENTER", text = "Center" },
    { value = "UP", text = "Up" },
    { value = "DOWN", text = "Down" },
}

local FILTER_MODE_OPTIONS = {
    { value = "off", text = "Off (Show All)" },
    { value = "classification", text = "Classification" },
    { value = "whitelist", text = "Whitelist (Only These Spells)" },
}

local AURA_TYPE_OPTIONS = {
    { value = "HELPFUL", text = "Buffs (Helpful)" },
    { value = "HARMFUL", text = "Debuffs (Harmful)" },
}

local TRACKED_DISPLAY_OPTIONS = {
    { value = "icon", text = "Icon" },
    { value = "square", text = "Colored Square" },
    { value = "bar", text = "Bar" },
    { value = "healthTint", text = "Health Bar Tint" },
}

local BAR_ORIENTATION_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal" },
    { value = "VERTICAL", text = "Vertical" },
}

local HEALTH_TINT_ANIMATION_OPTIONS = {
    { value = "fill", text = "Soft Fill" },
    { value = "fade", text = "Soft Fade" },
    { value = "fillFade", text = "Fill + Fade" },
    { value = "pulse", text = "Subtle Pulse" },
    { value = "instant", text = "Instant" },
}

-- Buff/debuff classification options, keyed by aura type (mirrors the old
-- Buffs/Debuffs filtering cards).
local HELPFUL_CLASSIFICATIONS = {
    { key = "raid", label = "Raid" },
    { key = "raidInCombat", label = "Raid (In Combat)" },
    { key = "cancelable", label = "Cancelable" },
    { key = "notCancelable", label = "Not Cancelable" },
    { key = "important", label = "Important" },
    { key = "bigDefensive", label = "Big Defensive" },
    { key = "externalDefensive", label = "External Defensive" },
}

local HARMFUL_CLASSIFICATIONS = {
    { key = "raid", label = "Raid" },
    { key = "raidInCombat", label = "Raid (In Combat)" },
    { key = "crowdControl", label = "Crowd Control" },
    { key = "important", label = "Important" },
}

local function GetGUI()
    return QUI and QUI.GUI or nil
end

-- Shared options API (BuildSettingRow lives here). ns is the suite-wide
-- namespace, so this resolves the same object the schema's GetOptionsAPI uses.
local function GetOptionsAPI()
    return ns.QUI_Options
end

local function GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name and name ~= "" then
            return name
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name and name ~= "" then
            return name
        end
    end
    return nil
end

local function GetSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and texture then
            return texture
        end
    end
    return FALLBACK_ICON
end

-- Apply the QUI settings font (Quazii) + standard text colors to the spell-ID
-- input pieces, so they match the rest of the settings UI instead of Blizzard's
-- GameFont + hardcoded greys. Any of box/label/addText may be nil.
local function StyleSpellInputText(GUI, C, box, label, addText)
    local fp = (GUI and GUI.FONT_PATH) or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
    local tc = (C and C.text) or { 1, 1, 1, 1 }
    local mc = (C and C.textMuted) or { 1, 1, 1, 0.45 }
    if box then
        box:SetFont(fp, 12, "")
        box:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
    if label then
        label:SetFont(fp, 11, "")
        label:SetTextColor(mc[1], mc[2], mc[3], mc[4] or 0.45)
    end
    if addText then
        addText:SetFont(fp, 11, "")
        addText:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
end

-- Pretty label/icon for an element. filterStrip => "Buffs"/"Debuffs"; tracked =>
-- the first spell's name (with a "+N" suffix when several spells share a strip).
local function GetElementLabel(element)
    if element.mode == "filterStrip" then
        if element.auraType == "HARMFUL" then
            return "Debuffs", nil
        end
        return "Buffs", nil
    end

    local spells = element.spells or {}
    local first = spells[1]
    if not first then
        return "Tracked (empty)", FALLBACK_ICON
    end
    local name = GetSpellName(first) or ("Spell " .. tostring(first))
    if #spells > 1 then
        name = name .. " +" .. tostring(#spells - 1)
    end
    return name, GetSpellTexture(first)
end

local function GetSuggestionSpells(bucket)
    if AuraDefaults and type(AuraDefaults.GetSuggestionSpells) == "function" then
        -- Suggestions exclude spells already tracked in this bucket. Flatten the
        -- bucket's tracked spell IDs into entry stubs the defaults engine reads.
        local existing = {}
        for _, element in ipairs(bucket or {}) do
            if element.mode == "tracked" then
                for _, sid in ipairs(element.spells or {}) do
                    existing[#existing + 1] = { spellID = sid }
                end
            end
        end
        return AuraDefaults.GetSuggestionSpells(existing)
    end
    return {}
end

---------------------------------------------------------------------------
-- PER-ELEMENT CONFIG WIDGETS
-- Each builder appends form widgets into ctx.detailArea via AddDetailWidget and
-- returns nothing; the caller tracks the running Y. Kept at file scope so the
-- big RenderAuras closure stays under the Lua 5.1 60-upvalue cap.
---------------------------------------------------------------------------

local function AddPlacementWidgets(ctx, element, includeStrip)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange

    if includeStrip then
        row("Max Icons", GUI:CreateFormSlider(ctx.detailArea, nil, 0, 10, 1, "maxIcons", element, onChange, { deferOnDrag = true }, {
            description = "Hard cap on how many icons this element displays at once. 0 shows all matches.",
        }))
    end
    row("Icon Size", GUI:CreateFormSlider(ctx.detailArea, nil, 4, 40, 1, "iconSize", element, onChange, { deferOnDrag = true }, {
        description = "Pixel size of each icon.",
    }))
    row("Anchor", GUI:CreateFormDropdown(ctx.detailArea, nil, NINE_POINT_OPTIONS, "anchor", element, onChange, {
        description = "Where on the frame this element is anchored. X/Y Offset below nudges it from this anchor point.",
    }))
    if includeStrip then
        row("Grow Direction", GUI:CreateFormDropdown(ctx.detailArea, nil, AURA_GROW_OPTIONS, "growDirection", element, onChange, {
            description = "Direction additional icons are added in after the first.",
        }))
        row("Spacing", GUI:CreateFormSlider(ctx.detailArea, nil, 0, 8, 1, "spacing", element, onChange, { deferOnDrag = true }, {
            description = "Pixel gap between adjacent icons.",
        }))
    end
    row("X Offset", GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetX", element, onChange, { deferOnDrag = true }, {
        description = "Horizontal pixel offset from the anchor.",
    }))
    row("Y Offset", GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetY", element, onChange, { deferOnDrag = true }, {
        description = "Vertical pixel offset from the anchor.",
    }))
end

local function AddDurationTextWidgets(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange

    row("Hide Duration Swipe", GUI:CreateFormCheckbox(ctx.detailArea, nil, "hideSwipe", element, onChange, {
        description = "Hide the cooldown swipe animation drawn over icons.",
    }))
    row("Reverse Swipe", GUI:CreateFormCheckbox(ctx.detailArea, nil, "reverseSwipe", element, onChange, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as time passes.",
    }))
    row("Show Duration Text", GUI:CreateFormCheckbox(ctx.detailArea, nil, "showDurationText", element, onChange, {
        description = "Show the remaining-time countdown text on each icon.",
    }))
    row("Duration Font Size", GUI:CreateFormSlider(ctx.detailArea, nil, 6, 24, 1, "durationFontSize", element, onChange, { deferOnDrag = true }, {
        description = "Font size used for the remaining-time text.",
    }))
end

-- Duration color-coding toggles. filterStrip-only (the model defines these
-- fields on filter strips, default true); the renderer reads them to color the
-- countdown text by remaining time and pulse icons near expiry.
local function AddDurationColorWidgets(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange

    row("Color Duration Text", GUI:CreateFormCheckbox(ctx.detailArea, nil, "showDurationColor", element, onChange, {
        description = "Tint the remaining-time text by how much duration is left (e.g. red when low).",
    }))
    row("Pulse When Expiring", GUI:CreateFormCheckbox(ctx.detailArea, nil, "showExpiringPulse", element, onChange, {
        description = "Pulse the icon as the aura nears expiry to draw attention.",
    }))
end

-- Curated suggestion presets for the whitelist/blacklist spell-list editors.
-- Mirrors the indicators editor: spec + tracked-cooldown suggestions for the
-- whitelist, the dedicated buff/debuff exclusion presets for the blacklist.
local function GetSpellListPresets(element, fieldName)
    if not SpellList then return {} end
    if fieldName == "blacklist" then
        if element.auraType == "HARMFUL" then
            return (SpellList.GetDebuffBlacklistPresets and SpellList.GetDebuffBlacklistPresets()) or {}
        end
        return (SpellList.GetBuffBlacklistPresets and SpellList.GetBuffBlacklistPresets()) or {}
    end
    return (SpellList.GetDefaultPresets and SpellList.GetDefaultPresets()) or {}
end

-- Whitelist / blacklist spell-list editor for a filterStrip element. Reuses the
-- shared spell-list widget (preset toggle rows + "Other" remove rows) and adds a
-- manual Spell ID input that writes into the {[spellID]=true} map. fieldName is
-- "whitelist" or "blacklist"; both are consumed by BuildFilterStripMatches.
local function AddSpellListEditor(ctx, element, fieldName, title)
    local GUI = ctx.GUI
    local C = ctx.C
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange

    if type(element[fieldName]) ~= "table" then
        element[fieldName] = {}
    end
    local listTable = element[fieldName]

    local header = GUI:CreateLabel(ctx.detailArea, "|cFFAAAAAA" .. title .. "|r", 11, C.textMuted)
    header:SetJustifyH("LEFT")
    add(header, 18, true)

    if not (SpellList and SpellList.CreateListFrame) then
        return
    end

    -- Manual Spell ID add row (mirrors the tracked-aura picker's manual input).
    local manualRow = CreateFrame("Frame", nil, ctx.detailArea)
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
    inputLabel:SetText("Spell ID")
    inputLabel:SetTextColor(0.5, 0.5, 0.5)

    local addManualButton = CreateFrame("Button", nil, manualRow, "BackdropTemplate")
    addManualButton:SetSize(40, 20)
    addManualButton:SetPoint("LEFT", inputLabel, "RIGHT", 8, 0)
    SkinBase.ApplyPixelBackdrop(addManualButton, 1, true, false, { 0.3, 0.3, 0.3, 1 }, { 0.15, 0.15, 0.15, 1 })
    local addManualText = addManualButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addManualText:SetPoint("CENTER")
    addManualText:SetText("Add")
    StyleSpellInputText(GUI, C, inputBox, inputLabel, addManualText)
    local function CommitManual()
        local spellID = tonumber(inputBox:GetText())
        if spellID and spellID > 0 then
            listTable[spellID] = true
            inputBox:SetText("")
            inputBox:ClearFocus()
            onChange()
            ctx.rebuild()
        end
    end
    addManualButton:SetScript("OnClick", CommitManual)
    inputBox:SetScript("OnEnterPressed", CommitManual)
    add(manualRow, 26, true)

    -- Preset toggle rows + "Other" remove rows. The list frame sizes itself; we
    -- rebuild the detail area on layout change so the running Y reflows.
    local presets = GetSpellListPresets(element, fieldName)
    local listFrame = SpellList.CreateListFrame(ctx.detailArea, listTable, presets, function()
        onChange()
    end, function()
        ctx.rebuild()
    end)
    add(listFrame, math.max(1, listFrame:GetHeight() or 1), true)
end

local function AddFilterStripConfig(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild

    row("Aura Type", GUI:CreateFormDropdown(ctx.detailArea, nil, AURA_TYPE_OPTIONS, "auraType", element, function()
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = "Whether this strip shows helpful buffs or harmful debuffs.",
    }))

    AddPlacementWidgets(ctx, element, true)
    AddDurationTextWidgets(ctx, element)
    AddDurationColorWidgets(ctx, element)

    -- Filtering.
    row("Filter Mode", GUI:CreateFormDropdown(ctx.detailArea, nil, FILTER_MODE_OPTIONS, "filterMode", element, function()
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = "Off shows everything; Classification shows only the categories ticked below; Whitelist shows only the spells you list. The blacklist below always hides its spells, in every mode.",
        -- Whitelist and the always-on blacklist are spell-list editors (plain
        -- labels, not searchable widgets); surface their names as keywords here so
        -- a search for "whitelist"/"blacklist" lands on this strip's filtering.
        keywords = { "Whitelist", "Blacklist", "filter", "exclude", "include", "spell list" },
    }))
    row("Only My Auras", GUI:CreateFormCheckbox(ctx.detailArea, nil, "onlyMine", element, onChange, {
        description = "Only show auras you applied.",
        keywords = { "Only Mine", "mine only" },
    }))
    row("Hide Permanent", GUI:CreateFormCheckbox(ctx.detailArea, nil, "hidePermanent", element, onChange, {
        description = "Hide auras with no remaining duration.",
    }))
    row("Deduplicate Defensives", GUI:CreateFormCheckbox(ctx.detailArea, nil, "dedupeDefensives", element, onChange, {
        description = "Hide icons already shown by another tracked element.",
    }))

    local filterMode = element.filterMode or "off"
    if filterMode == "classification" then
        if type(element.classifications) ~= "table" then
            element.classifications = {}
        end
        local list = element.auraType == "HARMFUL" and HARMFUL_CLASSIFICATIONS or HELPFUL_CLASSIFICATIONS
        for _, entry in ipairs(list) do
            row(entry.label, GUI:CreateFormCheckbox(ctx.detailArea, nil, entry.key, element.classifications, onChange, {
                description = "Include auras Blizzard flags as " .. entry.label .. ".",
            }))
        end
    elseif filterMode == "whitelist" then
        AddSpellListEditor(ctx, element, "whitelist", "Whitelist (only these spells are shown):")
    end

    -- Blacklist is an always-on exclusion: BuildFilterStripMatches applies it
    -- regardless of filterMode (even Off shows everything *except* these), so the
    -- editor is shown unconditionally. Whitelist (the inclusion mode) stays gated
    -- to filterMode == "whitelist" above.
    AddSpellListEditor(ctx, element, "blacklist", "Blacklist (these spells are always hidden):")
end

local function AddTrackedBarConfig(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange

    if type(element.bar) ~= "table" then
        element.bar = {}
    end
    local bar = element.bar
    row("Orientation", GUI:CreateFormDropdown(ctx.detailArea, nil, BAR_ORIENTATION_OPTIONS, "orientation", bar, onChange, {
        description = "Whether the bar drains horizontally or vertically as the aura ticks down.",
    }))
    row("Thickness", GUI:CreateFormSlider(ctx.detailArea, nil, 1, 20, 1, "thickness", bar, onChange, { deferOnDrag = true }, {
        description = "Pixel thickness of the bar.",
    }))
    row("Width / Height", GUI:CreateFormSlider(ctx.detailArea, nil, 4, 200, 1, "length", bar, onChange, { deferOnDrag = true }, {
        description = "Pixel length of the bar.",
    }))
    row("Match Frame Width / Height", GUI:CreateFormCheckbox(ctx.detailArea, nil, "matchFrameSize", bar, onChange, {
        description = "Stretch the bar to match the frame size.",
    }))
    row("Bar Color", GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", bar, onChange, nil, {
        description = "Fill color of the bar while the aura is active.",
    }))
    row("Background Color", GUI:CreateFormColorPicker(ctx.detailArea, nil, "backgroundColor", bar, onChange, nil, {
        description = "Color drawn behind the bar fill.",
    }))
    row("Hide Border", GUI:CreateFormCheckbox(ctx.detailArea, nil, "hideBorder", bar, onChange, {
        description = "Remove the border drawn around the bar.",
    }))
    row("Border Color", GUI:CreateFormColorPicker(ctx.detailArea, nil, "borderColor", bar, onChange, nil, {
        description = "Color of the bar's border.",
    }))
    row("Border Size", GUI:CreateFormSlider(ctx.detailArea, nil, 1, 8, 1, "borderSize", bar, onChange, { deferOnDrag = true }, {
        description = "Pixel thickness of the bar's border.",
    }))
    row("Low-Time Seconds", GUI:CreateFormSlider(ctx.detailArea, nil, 0, 30, 0.5, "lowTimeThreshold", bar, onChange, {
        precision = 1,
        deferOnDrag = true,
    }, {
        description = "When remaining duration drops below this, the bar switches to the Low-Time Color.",
    }))
    row("Low-Time Color", GUI:CreateFormColorPicker(ctx.detailArea, nil, "lowTimeColor", bar, onChange, nil, {
        description = "Bar color used once the remaining duration crosses the Low-Time threshold.",
    }))
end

-- Per-spell "Only Mine" overrides for a multi-spell tracked icon strip. Each
-- row writes element.onlyMineSpells[spellID] = true/false; Model.EffectiveOnlyMine
-- prefers a per-spell value over the element-level onlyMine. Only meaningful when
-- the strip tracks more than one spell (a single spell uses element-level onlyMine).
local function AddPerSpellOnlyMineWidgets(ctx, element)
    local GUI = ctx.GUI
    local C = ctx.C
    local add = ctx.AddDetailWidget
    local row = ctx.AddFormRow
    local onChange = ctx.onChange

    local spells = element.spells or {}
    if #spells <= 1 then
        return
    end
    if type(element.onlyMineSpells) ~= "table" then
        element.onlyMineSpells = {}
    end

    local header = GUI:CreateLabel(ctx.detailArea,
        "|cFFAAAAAAPer-Spell Only Mine (overrides the element setting above):|r", 11, C.textMuted)
    header:SetJustifyH("LEFT")
    add(header, 18, true)

    for _, spellID in ipairs(spells) do
        local label = GetSpellName(spellID) or ("Spell " .. tostring(spellID))
        row(label, GUI:CreateFormCheckbox(ctx.detailArea, nil, spellID, element.onlyMineSpells, onChange, {
            description = "Only show this spell when you applied it. Overrides the element-level Only My Cast for this spell.",
        }))
    end
end

local function AddTrackedConfig(ctx, element)
    local GUI = ctx.GUI
    local row = ctx.AddFormRow
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild

    -- No embedded spell editor: a tracked element carries the single spell it
    -- was created with (top-level Spell ID box / picker). Spells are added only
    -- from there, one tracked element per spell.

    row("Display Type", GUI:CreateFormDropdown(ctx.detailArea, nil, TRACKED_DISPLAY_OPTIONS, "displayType", element, function()
        if element.displayType == "square" and type(element.color) ~= "table" then
            element.color = { 0.2, 0.8, 0.2, 1 }
        end
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = "How this tracked aura displays: an icon strip, a colored square, a duration bar, or a health-bar tint.",
    }))

    row("Only My Cast", GUI:CreateFormCheckbox(ctx.detailArea, nil, "onlyMine", element, onChange, {
        description = "Only track this aura when you applied it.",
        -- Per-spell Only Mine overrides (multi-spell strips) render as plain
        -- per-spell checkboxes below; keyword it here so the override is findable.
        keywords = { "Only Mine", "Per-Spell Only Mine", "mine only" },
    }))

    local displayType = element.displayType or "icon"
    if displayType == "bar" then
        row("Anchor", GUI:CreateFormDropdown(ctx.detailArea, nil, NINE_POINT_OPTIONS, "anchor", element, onChange, {
            description = "Where on the frame the bar is anchored.",
        }))
        row("X Offset", GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetX", element, onChange, { deferOnDrag = true }, {
            description = "Horizontal pixel offset from the anchor.",
        }))
        row("Y Offset", GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetY", element, onChange, { deferOnDrag = true }, {
            description = "Vertical pixel offset from the anchor.",
        }))
        AddTrackedBarConfig(ctx, element)
    elseif displayType == "healthTint" then
        if type(element.color) ~= "table" then
            element.color = { 0.2, 0.8, 0.2, 1 }
        end
        if type(element.healthTint) ~= "table" then
            element.healthTint = {}
        end
        row("Tint Color", GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
            description = "Color tint applied across the health bar while the aura is active.",
        }))
        row("Tint Animation", GUI:CreateFormDropdown(ctx.detailArea, nil, HEALTH_TINT_ANIMATION_OPTIONS, "animation", element.healthTint, onChange, {
            description = "How the health-bar tint appears when the aura is detected.",
        }))
    elseif displayType == "square" then
        if type(element.color) ~= "table" then
            element.color = { 0.2, 0.8, 0.2, 1 }
        end
        row("Square Size", GUI:CreateFormSlider(ctx.detailArea, nil, 4, 40, 1, "iconSize", element, onChange, { deferOnDrag = true }, {
            description = "Pixel size of the colored square.",
        }))
        row("Anchor", GUI:CreateFormDropdown(ctx.detailArea, nil, NINE_POINT_OPTIONS, "anchor", element, onChange, {
            description = "Where on the frame the square is anchored.",
        }))
        row("X Offset", GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetX", element, onChange, { deferOnDrag = true }, {
            description = "Horizontal pixel offset from the anchor.",
        }))
        row("Y Offset", GUI:CreateFormSlider(ctx.detailArea, nil, -100, 100, 1, "offsetY", element, onChange, { deferOnDrag = true }, {
            description = "Vertical pixel offset from the anchor.",
        }))
        row("Square Color", GUI:CreateFormColorPicker(ctx.detailArea, nil, "color", element, onChange, nil, {
            description = "Fill color of the colored square.",
        }))
    else
        -- icon
        AddPlacementWidgets(ctx, element, true)
        AddDurationTextWidgets(ctx, element)
        AddPerSpellOnlyMineWidgets(ctx, element)
    end
end

---------------------------------------------------------------------------
-- ROW POOL
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- DETAIL (per-element config) rendering. Builds widgets for the selected
-- element below the list.
---------------------------------------------------------------------------
-- Detail widgets lay out in the QUI two-column standard: consecutive form
-- widgets pair left/right, advancing the running Y by the taller of the two.
-- A widget added with span=true (headers, the manual-add row, the spell-list
-- frame) flushes any half-filled row and takes the full width on its own.
local function RenderDetail(ctx, element)
    ctx.ClearDetailWidgets()
    if not element then
        ctx.detailArea:SetHeight(1)
        return 0
    end

    local detailArea = ctx.detailArea
    ctx.detailY = -2
    ctx._pendingWidget = nil
    ctx._pendingHeight = 0
    -- Parity counter for the alternating row tint. Span rows (headers, the
    -- spell-list frame) are visually distinct and do not stripe or count, so
    -- the zebra rhythm stays continuous across the form rows around them.
    local rowParity = 0

    -- Emit one detail row: a frame stacked at the running Y holding either a
    -- left/right form pair (with center divider) or a single full-width / lone
    -- widget. Mirrors CreateSettingsCardGroup's row styling (3% white tint on
    -- odd rows, 5% white center divider) so the auras editor matches the
    -- standard two-column settings look.
    local function EmitRow(left, leftH, right, rightH, span)
        local rowH = span and leftH or (right and math.max(leftH, rightH) or leftH)
        local rowFrame = CreateFrame("Frame", nil, detailArea)
        ctx.RegisterDetailWidget(rowFrame)
        rowFrame:ClearAllPoints()
        rowFrame:SetPoint("TOPLEFT", detailArea, "TOPLEFT", 0, ctx.detailY)
        rowFrame:SetPoint("TOPRIGHT", detailArea, "TOPRIGHT", 0, ctx.detailY)
        rowFrame:SetHeight(rowH)

        if not span then
            if (rowParity % 2) == 1 then
                local bg = rowFrame:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(rowFrame)
                bg:SetColorTexture(1, 1, 1, 0.02)
            end
            rowParity = rowParity + 1
        end

        left:SetParent(rowFrame)
        left:ClearAllPoints()
        if span then
            left:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", PAD, 0)
            left:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -PAD, 0)
        elseif right then
            left:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", PAD, 0)
            left:SetPoint("TOPRIGHT", rowFrame, "TOP", -(COL_GAP / 2), 0)
            right:SetParent(rowFrame)
            right:ClearAllPoints()
            right:SetPoint("TOPLEFT", rowFrame, "TOP", COL_GAP / 2, 0)
            right:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -PAD, 0)

            local cdiv = rowFrame:CreateTexture(nil, "ARTWORK")
            cdiv:SetPoint("TOP", rowFrame, "TOP", 0, -6)
            cdiv:SetPoint("BOTTOM", rowFrame, "BOTTOM", 0, 6)
            cdiv:SetWidth(1)
            cdiv:SetColorTexture(1, 1, 1, 0.05)
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

    -- Wrap a bare (label=nil) form widget in the standard BuildSettingRow cell
    -- so it renders on a single compact line (label left, control right) at the
    -- uniform FORM_ROW height, instead of the tall label-on-top layout. Pass
    -- span=true for a full-width row.
    local optionsAPI = GetOptionsAPI()
    ctx.AddFormRow = function(label, widget, span)
        local cell = (optionsAPI and optionsAPI.BuildSettingRow)
            and optionsAPI.BuildSettingRow(detailArea, label, widget)
            or widget
        ctx.AddDetailWidget(cell, FORM_ROW, span)
    end

    ctx.AddFormRow("Element Enabled", ctx.GUI:CreateFormCheckbox(ctx.detailArea, nil, "enabled", element, function()
        ctx.NotifyChanged()
        ctx.rebuild()
    end, {
        description = "Toggle this element. When off, it does not display.",
    }), true)

    if element.mode == "filterStrip" then
        AddFilterStripConfig(ctx, element)
    else
        AddTrackedConfig(ctx, element)
    end

    FlushPending()

    local used = math.abs(ctx.detailY) + 8
    ctx.detailArea:SetHeight(used)
    return used
end

---------------------------------------------------------------------------
-- LIST + ADD + PICKER rendering
---------------------------------------------------------------------------
local function RebuildList(ctx)
    local bucket = ctx.bucket
    ctx.ReleaseRows()
    ctx.ReleaseSuggestRows()
    ctx.ClearDetailWidgets()

    -- nil selectedIndex means "all collapsed" -- a valid state the expand/minus
    -- toggle relies on, so DON'T coerce nil to 1 here (that made the minus button
    -- never collapse). Only clamp a real index that ran past the list end.
    if #bucket == 0 then
        ctx.selectedIndex = nil
    elseif ctx.selectedIndex and ctx.selectedIndex > #bucket then
        ctx.selectedIndex = #bucket
    end

    local C = ctx.C
    local GUI = ctx.GUI
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local listY = 0

    -- Element rows.
    for index, element in ipairs(bucket) do
        local row = ctx.AcquireRow()
        row:SetParent(ctx.listArea)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, listY)
        row:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, listY)
        row:Show()

        local label, icon = GetElementLabel(element)
        row.icon:SetTexture(icon or FALLBACK_ICON)
        row.icon:Show()
        local nameColor = element.enabled ~= false and "|cFFFFFFFF" or "|cFF808080"
        row.name:SetText(nameColor .. label .. "|r")

        if element.mode == "filterStrip" then
            row.badge:SetText("|cFF56D1FFSTRIP|r")
        else
            row.badge:SetText("|cFFC8A2FFTRACKED|r")
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

        -- Alternating zebra (like the standard settings toggle rows); the
        -- expanded row gets a faint accent tint instead.
        if expanded then
            row.bg:SetColorTexture(accent[1], accent[2], accent[3], 0.10)
        elseif (index % 2) == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.02)
        else
            row.bg:SetColorTexture(1, 1, 1, 0)
        end

        -- Whole row toggles expand (collapse if already open, else open this one).
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
            end
            ctx.NotifyChanged()
            ctx.rebuild()
        end)

        ctx.activeRows[#ctx.activeRows + 1] = row
        listY = listY - ROW_STEP

        -- Inline config directly under the selected row.
        if expanded then
            listY = listY - 2
            ctx.detailArea:ClearAllPoints()
            ctx.detailArea:SetParent(ctx.listArea)
            ctx.detailArea:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", PAD, listY)
            ctx.detailArea:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, listY)
            ctx.detailArea:Show()
            local used = RenderDetail(ctx, element)
            listY = listY - used - 4
        end
    end

    if #bucket == 0 then
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

    -- Add controls.
    listY = listY - 8
    ctx.addRow:ClearAllPoints()
    ctx.addRow:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, listY)
    ctx.addRow:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, listY)
    ctx.addRow:Show()
    listY = listY - 30

    -- Tracked-aura picker (suggestion grid + manual spellID).
    listY = listY - 4
    ctx.pickerHeader:ClearAllPoints()
    ctx.pickerHeader:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, listY)
    ctx.pickerHeader:Show()
    listY = listY - 16

    ctx.inputRow:ClearAllPoints()
    ctx.inputRow:SetPoint("TOPLEFT", ctx.listArea, "TOPLEFT", 0, listY)
    ctx.inputRow:SetPoint("TOPRIGHT", ctx.listArea, "TOPRIGHT", 0, listY)
    listY = listY - 28

    local suggestions = GetSuggestionSpells(bucket)
    if #suggestions > 0 then
        -- Prefer the explicit width threaded from the host section; it is stable
        -- across the synchronous render and the in-place rebuild. Fall back to
        -- the live width, then a fixed default, only when none was supplied.
        local contentWidth = ctx.contentWidth or ctx.listArea:GetWidth()
        if type(contentWidth) ~= "number" or contentWidth < SUGGEST_CELL_STRIDE then
            contentWidth = 480
        end
        local cols = math.max(1, math.floor(contentWidth / SUGGEST_CELL_STRIDE))
        local rowsUsed = math.ceil(#suggestions / cols)
        for sIndex, spell in ipairs(suggestions) do
            local cell = ctx.AcquireSuggestCell()
            local col = (sIndex - 1) % cols
            local rIdx = math.floor((sIndex - 1) / cols)
            cell:SetParent(ctx.listArea)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", col * SUGGEST_CELL_STRIDE, listY - (rIdx * SUGGEST_CELL_STRIDE))
            cell._spell = spell
            cell.icon:SetTexture(spell.icon or GetSpellTexture(spell.id))
            cell:Show()
            cell:SetScript("OnClick", function()
                ctx.AddTracked(spell.id)
            end)
            ctx.activeSuggestRows[#ctx.activeSuggestRows + 1] = cell
        end
        listY = listY - (rowsUsed * SUGGEST_CELL_STRIDE) - 4
    end

    local contentHeight = math.max(1, math.abs(listY))
    ctx.listArea:SetHeight(contentHeight)
    local hostHeight = contentHeight + 8
    ctx.host:SetHeight(hostHeight)

    -- Report selection + height so the host can persist the open row and
    -- re-anchor the sections below this editor. Both are no-ops when the host
    -- did not supply hooks (e.g. the headless search-cache harvest).
    if ctx.onSelectionChanged then
        ctx.onSelectionChanged(ctx.selectedIndex)
    end
    if ctx.onLayoutChanged then
        ctx.onLayoutChanged(hostHeight)
    end
end

-- opts is optional. opts.forceSelectedIndex seeds the initially-expanded element
-- (used by the headless options-search harvest so per-element config labels get
-- rendered and captured). In-game callers omit opts and the list opens collapsed.
function AurasEditor.RenderAuras(host, auras, bucketKey, onChange, opts)
    local GUI = GetGUI()
    if not host or not GUI or type(auras) ~= "table" or not Model then
        return 1
    end

    if type(auras.elements) ~= "table" then
        auras.elements = {}
    end
    bucketKey = bucketKey or "*"
    -- Only the shared "*" bucket is auto-created. Spec buckets must NOT be
    -- created merely by viewing/editing — their presence is the override flag
    -- (see Model.EnableSpecOverride), so the schema only calls RenderAuras for a
    -- spec once override is on (bucket already exists).
    if bucketKey == "*" and type(auras.elements["*"]) ~= "table" then
        auras.elements["*"] = {}
    end

    local C = GUI.Colors or {}
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }

    local listArea = CreateFrame("Frame", nil, host)
    listArea:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    listArea:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    listArea:SetHeight(1)

    local emptyLabel = GUI:CreateLabel(listArea, "No aura elements in this bucket yet. Add one below.", 11, C.textMuted)
    emptyLabel:SetJustifyH("LEFT")
    emptyLabel:Hide()

    local detailArea = CreateFrame("Frame", nil, listArea)
    detailArea:SetHeight(1)
    detailArea:Hide()

    local pickerHeader = listArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pickerHeader:SetJustifyH("LEFT")
    pickerHeader:SetText("|cFFAAAAAAAdd Tracked Aura (click a suggestion or enter a Spell ID):|r")

    -- Add buttons row (Filter strip / Tracked aura).
    local addRow = CreateFrame("Frame", nil, listArea)
    addRow:SetHeight(26)
    local addStripButton = GUI:CreateButton(addRow, "Add Filter Strip", 130, 22)
    addStripButton:SetPoint("LEFT", 0, 0)

    -- Manual spellID input row.
    local inputRow = CreateFrame("Frame", nil, listArea)
    inputRow:SetHeight(24)

    local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
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

    local inputLabel = inputRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    inputLabel:SetPoint("LEFT", inputBox, "RIGHT", 4, 0)
    inputLabel:SetText("Spell ID")
    inputLabel:SetTextColor(0.5, 0.5, 0.5)

    local addManualButton = CreateFrame("Button", nil, inputRow, "BackdropTemplate")
    addManualButton:SetSize(40, 20)
    addManualButton:SetPoint("LEFT", inputLabel, "RIGHT", 8, 0)
    SkinBase.ApplyPixelBackdrop(addManualButton, 1, true, false, { 0.3, 0.3, 0.3, 1 }, { 0.15, 0.15, 0.15, 1 })
    local addManualText = addManualButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addManualText:SetPoint("CENTER")
    addManualText:SetText("Add")
    StyleSpellInputText(GUI, C, inputBox, inputLabel, addManualText)

    local rowPool = {}
    local activeRows = {}
    local suggestPool = {}
    local activeSuggestRows = {}
    local detailWidgets = {}

    local ctx = {
        GUI = GUI,
        C = C,
        host = host,
        auras = auras,
        bucket = auras.elements[bucketKey],
        onChangeRaw = onChange,
        listArea = listArea,
        emptyLabel = emptyLabel,
        detailArea = detailArea,
        pickerHeader = pickerHeader,
        addRow = addRow,
        inputRow = inputRow,
        activeRows = activeRows,
        activeSuggestRows = activeSuggestRows,
        selectedIndex = nil,
        -- Explicit content width from the host section (see group_frames_schema
        -- RenderAurasSection). Used for the suggestion-grid column math so the
        -- list height is identical on the synchronous tab render and on the
        -- in-place add/remove rebuild, regardless of when anchors settle.
        contentWidth = (type(opts) == "table" and type(opts.contentWidth) == "number" and opts.contentWidth > 0)
            and opts.contentWidth or nil,
        -- Host hooks (optional): onSelectionChanged(index) persists which row is
        -- expanded so a host-driven reflow can restore it; onLayoutChanged(height)
        -- lets the host re-anchor the sections below when this editor resizes.
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
    -- onChange used by widgets that mutate the model in place (no list rebuild).
    ctx.onChange = function()
        NotifyChanged()
    end

    -- Re-entrancy guard: the spell-list editor's CreateListFrame fires its
    -- onLayoutChanged callback (which calls rebuild) synchronously while it lays
    -- out its rows. That happens *inside* a RebuildList pass, so a naive rebuild
    -- would re-enter RebuildList -> RenderDetail -> AddSpellListEditor ->
    -- CreateListFrame -> onLayoutChanged -> rebuild ... without end. The outer
    -- pass already reads the list frame's final height after CreateListFrame
    -- returns, so a rebuild requested mid-pass is redundant -- drop it.
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

    ctx.ClearDetailWidgets = function()
        for _, widget in ipairs(detailWidgets) do
            widget:Hide()
        end
        wipe(detailWidgets)
    end
    ctx.RegisterDetailWidget = function(widget)
        detailWidgets[#detailWidgets + 1] = widget
        return widget
    end

    ctx.AcquireRow = function()
        local row = table.remove(rowPool)
        if row then
            row:Show()
            return row
        end

        -- Whole-row Button toggles expand; child buttons (enable, delete) consume
        -- their own clicks. The chevron is a Frame, so clicking it falls through
        -- to the row toggle.
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
            -- Fallback simple button toggle.
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
        row.name:SetFont((GUI.FONT_PATH) or [[Interface\AddOns\QUI\assets\Quazii.ttf]], 12, "")
        row.name:SetJustifyH("LEFT")

        -- Standard QUI ghost button (matches Alts row delete), not a raw red x.
        row.delete = GUI:CreateButton(row, "Delete", 56, 18)
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

    ctx.AcquireSuggestCell = function()
        local cell = table.remove(suggestPool)
        if cell then
            cell:Show()
            return cell
        end

        cell = CreateFrame("Button", nil, listArea, "BackdropTemplate")
        cell:SetSize(SUGGEST_CELL_SIZE, SUGGEST_CELL_SIZE)
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        SkinBase.ApplyPixelBackdrop(cell, 1, true, false, { 0.2, 0.2, 0.2, 0.5 }, { 0, 0, 0, 0 })

        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(SUGGEST_ICON_SIZE, SUGGEST_ICON_SIZE)
        cell.icon:SetPoint("CENTER")
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
        cell.highlight:SetAllPoints()
        cell.highlight:SetColorTexture(accent[1], accent[2], accent[3], 0.15)

        cell:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.8)
            if GameTooltip and self._spell then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetFrameStrata("TOOLTIP")
                GameTooltip:AddLine(self._spell.name or GetSpellName(self._spell.id) or ("Spell " .. tostring(self._spell.id)), 1, 1, 1)
                GameTooltip:AddLine("ID: " .. tostring(self._spell.id), 0.5, 0.5, 0.5)
                if self._spell.source then
                    GameTooltip:AddLine(self._spell.source, 0.45, 0.65, 0.95)
                end
                GameTooltip:AddLine("Click to add", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)
        cell:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)

        return cell
    end
    ctx.ReleaseSuggestRows = function()
        for _, cell in ipairs(activeSuggestRows) do
            cell:Hide()
            cell:ClearAllPoints()
            cell:SetScript("OnClick", nil)
            cell._spell = nil
            table.insert(suggestPool, cell)
        end
        wipe(activeSuggestRows)
    end

    ctx.AddTracked = function(spellID)
        spellID = tonumber(spellID) or spellID
        local element = Model.NewTrackedElement(spellID and { spellID } or {}, "icon")
        ctx.bucket[#ctx.bucket + 1] = element
        ctx.selectedIndex = #ctx.bucket
        NotifyChanged()
        rebuild()
    end

    ctx.AddFilterStrip = function()
        -- Default new strips to debuffs only if a buff strip already exists,
        -- otherwise buffs; the auraType dropdown lets the user flip it.
        local hasBuff = false
        for _, element in ipairs(ctx.bucket) do
            if element.mode == "filterStrip" and element.auraType == "HELPFUL" then
                hasBuff = true
            end
        end
        local element = Model.NewFilterStripElement(hasBuff and "HARMFUL" or "HELPFUL")
        ctx.bucket[#ctx.bucket + 1] = element
        ctx.selectedIndex = #ctx.bucket
        NotifyChanged()
        rebuild()
    end

    addStripButton:SetScript("OnClick", function()
        ctx.AddFilterStrip()
    end)
    addManualButton:SetScript("OnClick", function()
        local spellID = tonumber(inputBox:GetText())
        if spellID and spellID > 0 then
            inputBox:SetText("")
            inputBox:ClearFocus()
            ctx.AddTracked(spellID)
        end
    end)
    inputBox:SetScript("OnEnterPressed", function()
        local click = addManualButton:GetScript("OnClick")
        if click then
            click(addManualButton)
        end
    end)

    -- Harvest-only: open with a specific element expanded so its per-element
    -- config widgets render (and their labels get captured). Clamped by RebuildList.
    if opts and type(opts.forceSelectedIndex) == "number" then
        ctx.selectedIndex = opts.forceSelectedIndex
    end

    rebuild()
    return host:GetHeight()
end

return AurasEditor
