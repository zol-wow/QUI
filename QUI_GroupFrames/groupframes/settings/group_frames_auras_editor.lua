local ADDON_NAME, ns = ...

-- Unified Auras editor: renders the element list for a single spec bucket of
-- auras.elements (the v46 model from groupframes_aura_model.lua). Each element
-- is a filterStrip (Buffs/Debuffs) or a tracked element (icon/square/bar/tint).
-- Reuses the spell-picker UX (suggestion grid + manual spellID) salvaged from
-- the old tracked-aura/pinned editors.

local Model = ns.QUI_GroupFramesAuraModel
local AuraDefaults = ns.QUI_GroupFramesAuraDefaults
local SpellList = ns.QUI_GroupFramesSpellListSettings

local AurasEditor = ns.QUI_GroupFramesAurasSettings or {}
ns.QUI_GroupFramesAurasSettings = AurasEditor

local FORM_ROW = 32
local DROP_ROW = 52
local SLIDER_HEIGHT = 65
local PAD = 10
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

local function GetPixelSize(frame)
    local core = ns.Addon
    return (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
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
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange

    if includeStrip then
        add(GUI:CreateFormSlider(ctx.detailArea, "Max Icons", 0, 10, 1, "maxIcons", element, onChange, nil, {
            description = "Hard cap on how many icons this element displays at once. 0 shows all matches.",
        }), SLIDER_HEIGHT)
    end
    add(GUI:CreateFormSlider(ctx.detailArea, "Icon Size", 4, 40, 1, "iconSize", element, onChange, nil, {
        description = "Pixel size of each icon.",
    }), SLIDER_HEIGHT)
    add(GUI:CreateFormDropdown(ctx.detailArea, "Anchor", NINE_POINT_OPTIONS, "anchor", element, onChange, {
        description = "Where on the frame this element is anchored. X/Y Offset below nudges it from this anchor point.",
    }), DROP_ROW)
    if includeStrip then
        add(GUI:CreateFormDropdown(ctx.detailArea, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", element, onChange, {
            description = "Direction additional icons are added in after the first.",
        }), DROP_ROW)
        add(GUI:CreateFormSlider(ctx.detailArea, "Spacing", 0, 8, 1, "spacing", element, onChange, nil, {
            description = "Pixel gap between adjacent icons.",
        }), SLIDER_HEIGHT)
    end
    add(GUI:CreateFormSlider(ctx.detailArea, "X Offset", -100, 100, 1, "offsetX", element, onChange, nil, {
        description = "Horizontal pixel offset from the anchor.",
    }), SLIDER_HEIGHT)
    add(GUI:CreateFormSlider(ctx.detailArea, "Y Offset", -100, 100, 1, "offsetY", element, onChange, nil, {
        description = "Vertical pixel offset from the anchor.",
    }), SLIDER_HEIGHT)
end

local function AddDurationTextWidgets(ctx, element)
    local GUI = ctx.GUI
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange

    add(GUI:CreateFormCheckbox(ctx.detailArea, "Hide Duration Swipe", "hideSwipe", element, onChange, {
        description = "Hide the cooldown swipe animation drawn over icons.",
    }), FORM_ROW)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Reverse Swipe", "reverseSwipe", element, onChange, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as time passes.",
    }), FORM_ROW)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Show Duration Text", "showDurationText", element, onChange, {
        description = "Show the remaining-time countdown text on each icon.",
    }), FORM_ROW)
    add(GUI:CreateFormSlider(ctx.detailArea, "Duration Font Size", 6, 24, 1, "durationFontSize", element, onChange, nil, {
        description = "Font size used for the remaining-time text.",
    }), SLIDER_HEIGHT)
end

-- Duration color-coding toggles. filterStrip-only (the model defines these
-- fields on filter strips, default true); the renderer reads them to color the
-- countdown text by remaining time and pulse icons near expiry.
local function AddDurationColorWidgets(ctx, element)
    local GUI = ctx.GUI
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange

    add(GUI:CreateFormCheckbox(ctx.detailArea, "Color Duration Text", "showDurationColor", element, onChange, {
        description = "Tint the remaining-time text by how much duration is left (e.g. red when low).",
    }), FORM_ROW)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Pulse When Expiring", "showExpiringPulse", element, onChange, {
        description = "Pulse the icon as the aura nears expiry to draw attention.",
    }), FORM_ROW)
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
    add(header, 18)

    if not (SpellList and SpellList.CreateListFrame) then
        return
    end

    -- Manual Spell ID add row (mirrors the tracked-aura picker's manual input).
    local manualRow = CreateFrame("Frame", nil, ctx.detailArea)
    manualRow:SetHeight(24)

    local inputBox = CreateFrame("EditBox", nil, manualRow, "BackdropTemplate")
    inputBox:SetSize(80, 20)
    inputBox:SetPoint("LEFT", 0, 0)
    inputBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GetPixelSize(inputBox),
    })
    inputBox:SetBackdropColor(0.06, 0.06, 0.08, 1)
    inputBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
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
    addManualButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GetPixelSize(addManualButton),
    })
    addManualButton:SetBackdropColor(0.15, 0.15, 0.15, 1)
    addManualButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local addManualText = addManualButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addManualText:SetPoint("CENTER")
    addManualText:SetText("Add")
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
    add(manualRow, 26)

    -- Preset toggle rows + "Other" remove rows. The list frame sizes itself; we
    -- rebuild the detail area on layout change so the running Y reflows.
    local presets = GetSpellListPresets(element, fieldName)
    local listFrame = SpellList.CreateListFrame(ctx.detailArea, listTable, presets, function()
        onChange()
    end, function()
        ctx.rebuild()
    end)
    add(listFrame, math.max(1, listFrame:GetHeight() or 1))
end

local function AddFilterStripConfig(ctx, element)
    local GUI = ctx.GUI
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild

    add(GUI:CreateFormDropdown(ctx.detailArea, "Aura Type", AURA_TYPE_OPTIONS, "auraType", element, function()
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = "Whether this strip shows helpful buffs or harmful debuffs.",
    }), DROP_ROW)

    AddPlacementWidgets(ctx, element, true)
    AddDurationTextWidgets(ctx, element)
    AddDurationColorWidgets(ctx, element)

    -- Filtering.
    add(GUI:CreateFormDropdown(ctx.detailArea, "Filter Mode", FILTER_MODE_OPTIONS, "filterMode", element, function()
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = "Off shows everything; Classification shows only the categories ticked below; Whitelist shows only the spells you list. The blacklist below always hides its spells, in every mode.",
        -- Whitelist and the always-on blacklist are spell-list editors (plain
        -- labels, not searchable widgets); surface their names as keywords here so
        -- a search for "whitelist"/"blacklist" lands on this strip's filtering.
        keywords = { "Whitelist", "Blacklist", "filter", "exclude", "include", "spell list" },
    }), DROP_ROW)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Only My Auras", "onlyMine", element, onChange, {
        description = "Only show auras you applied.",
        keywords = { "Only Mine", "mine only" },
    }), FORM_ROW)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Hide Permanent", "hidePermanent", element, onChange, {
        description = "Hide auras with no remaining duration.",
    }), FORM_ROW)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Deduplicate Defensives", "dedupeDefensives", element, onChange, {
        description = "Hide icons already shown by another tracked element.",
    }), FORM_ROW)

    local filterMode = element.filterMode or "off"
    if filterMode == "classification" then
        if type(element.classifications) ~= "table" then
            element.classifications = {}
        end
        local list = element.auraType == "HARMFUL" and HARMFUL_CLASSIFICATIONS or HELPFUL_CLASSIFICATIONS
        for _, entry in ipairs(list) do
            add(GUI:CreateFormCheckbox(ctx.detailArea, entry.label, entry.key, element.classifications, onChange, {
                description = "Include auras Blizzard flags as " .. entry.label .. ".",
            }), FORM_ROW)
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
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange

    if type(element.bar) ~= "table" then
        element.bar = {}
    end
    local bar = element.bar
    add(GUI:CreateFormDropdown(ctx.detailArea, "Orientation", BAR_ORIENTATION_OPTIONS, "orientation", bar, onChange, {
        description = "Whether the bar drains horizontally or vertically as the aura ticks down.",
    }), DROP_ROW)
    add(GUI:CreateFormSlider(ctx.detailArea, "Thickness", 1, 20, 1, "thickness", bar, onChange, nil, {
        description = "Pixel thickness of the bar.",
    }), SLIDER_HEIGHT)
    add(GUI:CreateFormSlider(ctx.detailArea, "Width / Height", 4, 200, 1, "length", bar, onChange, nil, {
        description = "Pixel length of the bar.",
    }), SLIDER_HEIGHT)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Match Frame Width / Height", "matchFrameSize", bar, onChange, {
        description = "Stretch the bar to match the frame size.",
    }), FORM_ROW)
    add(GUI:CreateFormColorPicker(ctx.detailArea, "Bar Color", "color", bar, onChange, nil, {
        description = "Fill color of the bar while the aura is active.",
    }), FORM_ROW)
    add(GUI:CreateFormColorPicker(ctx.detailArea, "Background Color", "backgroundColor", bar, onChange, nil, {
        description = "Color drawn behind the bar fill.",
    }), FORM_ROW)
    add(GUI:CreateFormCheckbox(ctx.detailArea, "Hide Border", "hideBorder", bar, onChange, {
        description = "Remove the border drawn around the bar.",
    }), FORM_ROW)
    add(GUI:CreateFormColorPicker(ctx.detailArea, "Border Color", "borderColor", bar, onChange, nil, {
        description = "Color of the bar's border.",
    }), FORM_ROW)
    add(GUI:CreateFormSlider(ctx.detailArea, "Border Size", 1, 8, 1, "borderSize", bar, onChange, nil, {
        description = "Pixel thickness of the bar's border.",
    }), SLIDER_HEIGHT)
    add(GUI:CreateFormSlider(ctx.detailArea, "Low-Time Seconds", 0, 30, 0.5, "lowTimeThreshold", bar, onChange, {
        precision = 1,
    }, {
        description = "When remaining duration drops below this, the bar switches to the Low-Time Color.",
    }), SLIDER_HEIGHT)
    add(GUI:CreateFormColorPicker(ctx.detailArea, "Low-Time Color", "lowTimeColor", bar, onChange, nil, {
        description = "Bar color used once the remaining duration crosses the Low-Time threshold.",
    }), FORM_ROW)
end

-- Per-spell "Only Mine" overrides for a multi-spell tracked icon strip. Each
-- row writes element.onlyMineSpells[spellID] = true/false; Model.EffectiveOnlyMine
-- prefers a per-spell value over the element-level onlyMine. Only meaningful when
-- the strip tracks more than one spell (a single spell uses element-level onlyMine).
local function AddPerSpellOnlyMineWidgets(ctx, element)
    local GUI = ctx.GUI
    local C = ctx.C
    local add = ctx.AddDetailWidget
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
    add(header, 18)

    for _, spellID in ipairs(spells) do
        local label = GetSpellName(spellID) or ("Spell " .. tostring(spellID))
        add(GUI:CreateFormCheckbox(ctx.detailArea, label, spellID, element.onlyMineSpells, onChange, {
            description = "Only show this spell when you applied it. Overrides the element-level Only My Cast for this spell.",
        }), FORM_ROW)
    end
end

local function AddTrackedConfig(ctx, element)
    local GUI = ctx.GUI
    local C = ctx.C
    local add = ctx.AddDetailWidget
    local onChange = ctx.onChange
    local rebuild = ctx.rebuild

    add(GUI:CreateFormDropdown(ctx.detailArea, "Display Type", TRACKED_DISPLAY_OPTIONS, "displayType", element, function()
        if element.displayType == "square" and type(element.color) ~= "table" then
            element.color = { 0.2, 0.8, 0.2, 1 }
        end
        ctx.NotifyChanged()
        rebuild()
    end, {
        description = "How this tracked aura displays: an icon strip, a colored square, a duration bar, or a health-bar tint.",
    }), DROP_ROW)

    add(GUI:CreateFormCheckbox(ctx.detailArea, "Only My Cast", "onlyMine", element, onChange, {
        description = "Only track this aura when you applied it.",
        -- Per-spell Only Mine overrides (multi-spell strips) render as plain
        -- per-spell checkboxes below; keyword it here so the override is findable.
        keywords = { "Only Mine", "Per-Spell Only Mine", "mine only" },
    }), FORM_ROW)

    local displayType = element.displayType or "icon"
    if displayType == "bar" then
        add(GUI:CreateFormDropdown(ctx.detailArea, "Anchor", NINE_POINT_OPTIONS, "anchor", element, onChange, {
            description = "Where on the frame the bar is anchored.",
        }), DROP_ROW)
        add(GUI:CreateFormSlider(ctx.detailArea, "X Offset", -100, 100, 1, "offsetX", element, onChange, nil, {
            description = "Horizontal pixel offset from the anchor.",
        }), SLIDER_HEIGHT)
        add(GUI:CreateFormSlider(ctx.detailArea, "Y Offset", -100, 100, 1, "offsetY", element, onChange, nil, {
            description = "Vertical pixel offset from the anchor.",
        }), SLIDER_HEIGHT)
        AddTrackedBarConfig(ctx, element)
    elseif displayType == "healthTint" then
        if type(element.color) ~= "table" then
            element.color = { 0.2, 0.8, 0.2, 1 }
        end
        if type(element.healthTint) ~= "table" then
            element.healthTint = {}
        end
        add(GUI:CreateFormColorPicker(ctx.detailArea, "Tint Color", "color", element, onChange, nil, {
            description = "Color tint applied across the health bar while the aura is active.",
        }), FORM_ROW)
        add(GUI:CreateFormDropdown(ctx.detailArea, "Tint Animation", HEALTH_TINT_ANIMATION_OPTIONS, "animation", element.healthTint, onChange, {
            description = "How the health-bar tint appears when the aura is detected.",
        }), DROP_ROW)
    elseif displayType == "square" then
        if type(element.color) ~= "table" then
            element.color = { 0.2, 0.8, 0.2, 1 }
        end
        add(GUI:CreateFormSlider(ctx.detailArea, "Square Size", 4, 40, 1, "iconSize", element, onChange, nil, {
            description = "Pixel size of the colored square.",
        }), SLIDER_HEIGHT)
        add(GUI:CreateFormDropdown(ctx.detailArea, "Anchor", NINE_POINT_OPTIONS, "anchor", element, onChange, {
            description = "Where on the frame the square is anchored.",
        }), DROP_ROW)
        add(GUI:CreateFormSlider(ctx.detailArea, "X Offset", -100, 100, 1, "offsetX", element, onChange, nil, {
            description = "Horizontal pixel offset from the anchor.",
        }), SLIDER_HEIGHT)
        add(GUI:CreateFormSlider(ctx.detailArea, "Y Offset", -100, 100, 1, "offsetY", element, onChange, nil, {
            description = "Vertical pixel offset from the anchor.",
        }), SLIDER_HEIGHT)
        add(GUI:CreateFormColorPicker(ctx.detailArea, "Square Color", "color", element, onChange, nil, {
            description = "Fill color of the colored square.",
        }), FORM_ROW)
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
        row.enable:SetScript("OnClick", nil)
        row.remove:SetScript("OnClick", nil)
        row.expand:SetScript("OnClick", nil)
        table.insert(pool, row)
    end
    wipe(activeRows)
end

---------------------------------------------------------------------------
-- DETAIL (per-element config) rendering. Builds widgets for the selected
-- element below the list.
---------------------------------------------------------------------------
local function RenderDetail(ctx, element)
    ctx.ClearDetailWidgets()
    if not element then
        ctx.detailArea:SetHeight(1)
        return 0
    end

    local detailY = -2
    ctx.detailY = detailY
    ctx.AddDetailWidget = function(widget, height)
        ctx.RegisterDetailWidget(widget)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", PAD, ctx.detailY)
        widget:SetPoint("TOPRIGHT", ctx.detailArea, "TOPRIGHT", -PAD, ctx.detailY)
        ctx.detailY = ctx.detailY - height
    end

    ctx.AddDetailWidget(ctx.GUI:CreateFormCheckbox(ctx.detailArea, "Element Enabled", "enabled", element, function()
        ctx.NotifyChanged()
        ctx.rebuild()
    end, {
        description = "Toggle this element. When off, it does not display.",
    }), FORM_ROW)

    if element.mode == "filterStrip" then
        AddFilterStripConfig(ctx, element)
    else
        AddTrackedConfig(ctx, element)
    end

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

    if #bucket == 0 then
        ctx.selectedIndex = nil
    elseif not ctx.selectedIndex or ctx.selectedIndex > #bucket then
        ctx.selectedIndex = math.min(ctx.selectedIndex or 1, #bucket)
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
        if icon then
            row.icon:SetTexture(icon)
            row.icon:Show()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        else
            row.icon:Hide()
            row.name:SetPoint("LEFT", row.enable, "RIGHT", 8, 0)
        end
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
        row.expand:SetText(expanded and "-" or "+")
        row:SetBackdropColor(expanded and 0.16 or 0.08, expanded and 0.16 or 0.08, expanded and 0.2 or 0.08, 0.9)
        row:SetBackdropBorderColor(
            expanded and accent[1] or ((C.border and C.border[1]) or 0.2),
            expanded and accent[2] or ((C.border and C.border[2]) or 0.2),
            expanded and accent[3] or ((C.border and C.border[3]) or 0.2),
            1
        )
        row.expand:SetScript("OnClick", function()
            ctx.selectedIndex = (ctx.selectedIndex == index) and nil or index
            ctx.rebuild()
        end)
        row.remove:SetScript("OnClick", function()
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
        local contentWidth = ctx.listArea:GetWidth()
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
    ctx.host:SetHeight(contentHeight + 8)
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
    if type(auras.elements[bucketKey]) ~= "table" then
        auras.elements[bucketKey] = {}
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
    local addTrackedButton = GUI:CreateButton(addRow, "Add Tracked Aura", 130, 22)
    addTrackedButton:SetPoint("LEFT", addStripButton, "RIGHT", 8, 0)
    GUI:AttachTooltip(addTrackedButton,
        "Add a tracked aura. Pick a suggested spell or enter a Spell ID below, or click this to add an empty tracked element you can fill in.",
        "Add Tracked Aura")

    -- Manual spellID input row.
    local inputRow = CreateFrame("Frame", nil, listArea)
    inputRow:SetHeight(24)

    local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
    inputBox:SetSize(80, 20)
    inputBox:SetPoint("LEFT", 0, 0)
    inputBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GetPixelSize(inputBox),
    })
    inputBox:SetBackdropColor(0.06, 0.06, 0.08, 1)
    inputBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
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
    addManualButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = GetPixelSize(addManualButton),
    })
    addManualButton:SetBackdropColor(0.15, 0.15, 0.15, 1)
    addManualButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local addManualText = addManualButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addManualText:SetPoint("CENTER")
    addManualText:SetText("Add")

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

        row = CreateFrame("Frame", nil, listArea, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = GetPixelSize(row),
        })

        row.enable = SpellList and SpellList.CreateMiniToggle and SpellList.CreateMiniToggle(row) or nil
        if not row.enable then
            -- Fallback simple button toggle.
            row.enable = CreateFrame("Button", nil, row)
            row.enable:SetSize(26, 14)
            row.enable.SetToggleState = function() end
        end
        row.enable:SetPoint("LEFT", row, "LEFT", 6, 0)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row.enable, "RIGHT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetJustifyH("LEFT")

        row.remove = CreateFrame("Button", nil, row)
        row.remove:SetSize(18, 18)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.removeText = row.remove:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.removeText:SetPoint("CENTER")
        row.removeText:SetText("x")
        row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        row.remove:SetScript("OnEnter", function()
            row.removeText:SetTextColor(1, 0.4, 0.4, 1)
        end)
        row.remove:SetScript("OnLeave", function()
            row.removeText:SetTextColor(0.8, 0.3, 0.3, 1)
        end)

        row.expand = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.expand:SetSize(18, 18)
        row.expand:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
        row.expand:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = GetPixelSize(row.expand),
        })
        row.expand:SetBackdropColor(0.12, 0.12, 0.14, 1)
        row.expand:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        row.expandText = row.expand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.expandText:SetPoint("CENTER")
        row.expand.SetText = function(_, t) row.expandText:SetText(t) end

        row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.badge:SetJustifyH("RIGHT")
        row.badge:SetPoint("RIGHT", row.expand, "LEFT", -8, 0)
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
        cell:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = GetPixelSize(cell),
        })
        cell:SetBackdropColor(0, 0, 0, 0)
        cell:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)

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
    addTrackedButton:SetScript("OnClick", function()
        ctx.AddTracked(nil)
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
