--[[
    QUI Layout Mode Composer — Group Frame Element Settings Popup
    Standalone popup with scaled preview, clickable overlays, widget bar,
    and element-level settings. Opened from layout mode settings panel.
    Adapted from options/tabs/frames/groupframedesigner.lua
]]

local ADDON_NAME, ns = ...

local QUI_LayoutMode_Composer = {}
ns.QUI_LayoutMode_Composer = QUI_LayoutMode_Composer

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local FORM_ROW = 32
local DROP_ROW = 52
local SLIDER_HEIGHT = 65
local PAD = 10
local PREVIEW_SCALE = 2
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- PIXEL HELPERS (from groupframedesigner.lua)
---------------------------------------------------------------------------
local function SetSizePx(frame, widthPixels, heightPixels)
    if UIKit and UIKit.SetSizePx then
        UIKit.SetSizePx(frame, widthPixels, heightPixels)
    else
        frame:SetSize(widthPixels or 0, heightPixels or 0)
    end
end

local function SetHeightPx(frame, heightPixels)
    if UIKit and UIKit.SetHeightPx then
        UIKit.SetHeightPx(frame, heightPixels)
    else
        frame:SetHeight(heightPixels or 0)
    end
end

local function SetPointPx(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    if UIKit and UIKit.SetPointPx then
        UIKit.SetPointPx(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    else
        frame:SetPoint(point, relativeTo, relativePoint, xPixels or 0, yPixels or 0)
    end
end

local function RoundVirtual(value, frame)
    local QUICore = ns.Addon
    if QUICore and QUICore.PixelRound then
        return QUICore:PixelRound(value or 0, frame)
    end
    return value or 0
end

local function SetSnappedPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
    local QUICore = ns.Addon
    if QUICore and QUICore.SetSnappedPoint then
        QUICore:SetSnappedPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
    else
        frame:SetPoint(point, relativeTo, relativePoint, xOffset or 0, yOffset or 0)
    end
end

local function SetOutsidePx(frame, anchor, sizePixels)
    if UIKit and UIKit.SetOutsidePx then
        UIKit.SetOutsidePx(frame, anchor, sizePixels or 1)
    else
        local offset = sizePixels or 1
        SetPointPx(frame, "TOPLEFT", anchor, "TOPLEFT", -offset, offset)
        SetPointPx(frame, "BOTTOMRIGHT", anchor, "BOTTOMRIGHT", offset, -offset)
    end
end

local function EnsurePixelBackdropCompat(frame)
    if not frame then return nil end
    local uikit = ns.UIKit or UIKit
    if frame._quiPixelBackdropCompat then
        return frame._quiPixelBackdropCompat
    end
    local state = {
        borderPixels = 1, withBackground = false,
        bgColor = { 0, 0, 0, 1 }, borderColor = { 1, 1, 1, 1 },
        originalSetBackdropColor = frame.SetBackdropColor,
        originalSetBackdropBorderColor = frame.SetBackdropBorderColor,
    }
    if uikit and uikit.CreateBackground then
        state.bg = uikit.CreateBackground(frame, 0, 0, 0, 0)
        if state.bg then state.bg:Hide() end
    end
    if uikit and uikit.CreateBorderLines then
        uikit.CreateBorderLines(frame, 1, 1, 1, 1, 1, false)
    end
    frame.SetBackdropColor = function(self, r, g, b, a)
        local compat = self._quiPixelBackdropCompat
        if not compat then return end
        compat.bgColor = { r or 0, g or 0, b or 0, a or 1 }
        if compat.bg and compat.bg.SetVertexColor then
            compat.bg:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
            if compat.withBackground then compat.bg:Show() else compat.bg:Hide() end
        end
    end
    frame.SetBackdropBorderColor = function(self, r, g, b, a)
        local compat = self._quiPixelBackdropCompat
        if not compat then return end
        compat.borderColor = { r or 1, g or 1, b or 1, a or 1 }
        if uikit and uikit.UpdateBorderLines then
            uikit.UpdateBorderLines(self, compat.borderPixels or 1, r or 1, g or 1, b or 1, a or 1, false)
        elseif compat.originalSetBackdropBorderColor then
            pcall(compat.originalSetBackdropBorderColor, self, r, g, b, a)
        end
    end
    if uikit and uikit.RegisterScaleRefresh then
        uikit.RegisterScaleRefresh(frame, "composerBackdropCompat", function(owner)
            local compat = owner and owner._quiPixelBackdropCompat
            if not compat then return end
            if compat.bg and compat.bg.SetVertexColor then
                compat.bg:SetVertexColor(compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
                if compat.withBackground then compat.bg:Show() else compat.bg:Hide() end
            end
            if uikit and uikit.UpdateBorderLines then
                uikit.UpdateBorderLines(owner, compat.borderPixels or 1, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4], false)
            end
        end)
    end
    frame._quiPixelBackdropCompat = state
    return state
end

local function ApplyPixelBackdrop(frame, borderPixels, withBackground)
    if not frame then return end
    local uikit = ns.UIKit or UIKit
    local QUICore = ns.Addon
    if uikit and uikit.CreateBorderLines and uikit.UpdateBorderLines and uikit.CreateBackground then
        local compat = EnsurePixelBackdropCompat(frame)
        if not compat then return end
        compat.borderPixels = borderPixels or 1
        compat.withBackground = withBackground and true or false
        frame:SetBackdropColor(compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
        frame:SetBackdropBorderColor(compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4])
        return
    end
    if not frame.SetBackdrop then return end
    if QUICore and QUICore.SetPixelPerfectBackdrop then
        QUICore:SetPixelPerfectBackdrop(frame, borderPixels or 1, withBackground and "Interface\\Buttons\\WHITE8x8" or nil)
        return
    end
    local px = QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    local edgeSize = (borderPixels or 1) * px
    frame:SetBackdrop({
        bgFile = withBackground and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edgeSize,
    })
end

---------------------------------------------------------------------------
-- DB HELPERS
---------------------------------------------------------------------------
local function GetGFDB()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    local db = core and core.db and core.db.profile
    return db and db.quiGroupFrames
end

local function RefreshGF()
    if _G.QUI_RefreshGroupFrames then _G.QUI_RefreshGroupFrames() end
end

local function GetTextureList()
    local LSM = ns.LSM
    if not LSM then return {} end
    local list = {}
    for name in pairs(LSM:HashTable("statusbar")) do list[#list+1] = {value = name, text = name} end
    table.sort(list, function(a,b) return a.text < b.text end)
    return list
end

---------------------------------------------------------------------------
-- VISUAL PROXY
---------------------------------------------------------------------------
local VISUAL_DB_KEYS = {
    general = true, layout = true, health = true, power = true, name = true,
    absorbs = true, healPrediction = true, indicators = true,
    healer = true, classPower = true, range = true, auras = true,
    privateAuras = true, auraIndicators = true, castbar = true,
    portrait = true, pets = true, dimensions = true, spotlight = true,
}

local function CreateVisualProxy(gfdb, mode)
    local ctx = mode == "raid" and gfdb.raid or gfdb.party
    if not ctx then return gfdb end
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if VISUAL_DB_KEYS[key] then return ctx[key] end
            return gfdb[key]
        end,
        __newindex = function(_, key, value)
            if VISUAL_DB_KEYS[key] then ctx[key] = value
            else gfdb[key] = value end
        end,
    })
    rawset(proxy, "_composerMode", mode)
    return proxy
end

---------------------------------------------------------------------------
-- ANCHOR MAP
---------------------------------------------------------------------------
local ANCHOR_MAP = {
    LEFT   = { leftPoint = "LEFT",   rightPoint = "RIGHT",  justify = "LEFT",   justifyV = "MIDDLE" },
    RIGHT  = { leftPoint = "LEFT",   rightPoint = "RIGHT",  justify = "RIGHT",  justifyV = "MIDDLE" },
    CENTER = { leftPoint = "LEFT",   rightPoint = "RIGHT",  justify = "CENTER", justifyV = "MIDDLE" },
    TOP    = { leftPoint = "TOPLEFT", rightPoint = "TOPRIGHT", justify = "CENTER", justifyV = "TOP" },
    BOTTOM = { leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT", justify = "CENTER", justifyV = "BOTTOM" },
    TOPLEFT     = { leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",    justify = "LEFT",   justifyV = "TOP" },
    TOPRIGHT    = { leftPoint = "TOPLEFT",    rightPoint = "TOPRIGHT",    justify = "RIGHT",  justifyV = "TOP" },
    BOTTOMLEFT  = { leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT", justify = "LEFT",   justifyV = "BOTTOM" },
    BOTTOMRIGHT = { leftPoint = "BOTTOMLEFT", rightPoint = "BOTTOMRIGHT", justify = "RIGHT",  justifyV = "BOTTOM" },
}

---------------------------------------------------------------------------
-- DROPDOWN OPTIONS (element-level)
---------------------------------------------------------------------------
local AURA_GROW_OPTIONS = {
    { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" },
    { value = "CENTER", text = "Center" }, { value = "UP", text = "Up" }, { value = "DOWN", text = "Down" },
}
local HEALTH_DISPLAY_OPTIONS = {
    { value = "percent", text = "Percentage" }, { value = "absolute", text = "Absolute" },
    { value = "both", text = "Both" }, { value = "deficit", text = "Deficit" },
}
local HEALTH_FILL_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal (Left to Right)" },
    { value = "VERTICAL", text = "Vertical (Bottom to Top)" },
}
local NINE_POINT_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" }, { value = "TOP", text = "Top" },
    { value = "TOPRIGHT", text = "Top Right" }, { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" }, { value = "RIGHT", text = "Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" }, { value = "BOTTOM", text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}
local TEXT_JUSTIFY_OPTIONS = {
    { value = "LEFT", text = "Left" }, { value = "CENTER", text = "Center" }, { value = "RIGHT", text = "Right" },
}
local FILTER_MODE_OPTIONS = {
    { value = "off", text = "Off (Show All)" }, { value = "classification", text = "Classification" },
}

---------------------------------------------------------------------------
-- SPELL PRESETS
---------------------------------------------------------------------------
local AURA_FILTER_PRESETS = {
    { name = "Restoration Druid", specID = 105, spells = {
        { id = 774, name = "Rejuvenation" }, { id = 8936, name = "Regrowth" },
        { id = 33763, name = "Lifebloom" }, { id = 155777, name = "Germination" },
        { id = 48438, name = "Wild Growth" }, { id = 102342, name = "Ironbark" }, { id = 33786, name = "Cyclone" },
    }},
    { name = "Restoration Shaman", specID = 264, spells = {
        { id = 61295, name = "Riptide" }, { id = 974, name = "Earth Shield" },
        { id = 383648, name = "Earth Shield (Ele)" }, { id = 98008, name = "Spirit Link Totem" },
        { id = 108271, name = "Astral Shift" },
    }},
    { name = "Holy Paladin", specID = 65, spells = {
        { id = 53563, name = "Beacon of Light" }, { id = 156910, name = "Beacon of Faith" },
        { id = 200025, name = "Beacon of Virtue" }, { id = 156322, name = "Eternal Flame" },
        { id = 223306, name = "Bestow Faith" }, { id = 1022, name = "Blessing of Protection" },
        { id = 6940, name = "Blessing of Sacrifice" }, { id = 1044, name = "Blessing of Freedom" },
    }},
    { name = "Discipline Priest", specID = 256, spells = {
        { id = 194384, name = "Atonement" }, { id = 17, name = "Power Word: Shield" },
        { id = 41635, name = "Prayer of Mending" }, { id = 10060, name = "Power Infusion" },
        { id = 47788, name = "Guardian Spirit" }, { id = 33206, name = "Pain Suppression" },
    }},
    { name = "Holy Priest", specID = 257, spells = {
        { id = 139, name = "Renew" }, { id = 77489, name = "Echo of Light" },
        { id = 41635, name = "Prayer of Mending" }, { id = 10060, name = "Power Infusion" },
        { id = 47788, name = "Guardian Spirit" }, { id = 64844, name = "Divine Hymn" },
    }},
    { name = "Mistweaver Monk", specID = 270, spells = {
        { id = 119611, name = "Renewing Mist" }, { id = 124682, name = "Enveloping Mist" },
        { id = 115175, name = "Soothing Mist" }, { id = 191840, name = "Essence Font" },
        { id = 116849, name = "Life Cocoon" },
    }},
    { name = "Preservation Evoker", specID = 1468, spells = {
        { id = 364343, name = "Echo" }, { id = 366155, name = "Reversion" },
        { id = 367364, name = "Echo Reversion" }, { id = 355941, name = "Dream Breath" },
        { id = 376788, name = "Echo Dream Breath" }, { id = 363502, name = "Dream Flight" },
        { id = 373267, name = "Lifebind" },
    }},
    { name = "Augmentation Evoker", specID = 1473, spells = {
        { id = 410089, name = "Prescience" }, { id = 395152, name = "Ebon Might" },
        { id = 360827, name = "Blistering Scales" }, { id = 413984, name = "Shifting Sands" },
        { id = 410263, name = "Inferno's Blessing" }, { id = 410686, name = "Symbiotic Bloom" },
        { id = 369459, name = "Source of Magic" },
    }},
    { name = "Common Defensives", spells = {
        { id = 31821, name = "Aura Mastery" }, { id = 97463, name = "Rallying Cry" },
        { id = 15286, name = "Vampiric Embrace" }, { id = 64843, name = "Divine Hymn" },
        { id = 51052, name = "Anti-Magic Zone" }, { id = 196718, name = "Darkness" },
    }},
}

local SPEC_TO_PRESET = {}
for _, preset in ipairs(AURA_FILTER_PRESETS) do
    if preset.specID then SPEC_TO_PRESET[preset.specID] = preset end
end

local COMMON_DEFENSIVES_PRESET
for _, preset in ipairs(AURA_FILTER_PRESETS) do
    if not preset.specID then COMMON_DEFENSIVES_PRESET = preset; break end
end

local BUFF_BLACKLIST_PRESETS = {
    { name = "Raid Buffs", spells = {
        { id = 1459, name = "Arcane Intellect" }, { id = 6673, name = "Battle Shout" },
        { id = 21562, name = "Power Word: Fortitude" }, { id = 1126, name = "Mark of the Wild" },
        { id = 381753, name = "Skyfury" }, { id = 381748, name = "Blessing of the Bronze" },
        { id = 369459, name = "Source of Magic" },
    }},
}

local DEBUFF_BLACKLIST_PRESETS = {
    { name = "Sated / Exhaustion", spells = {
        { id = 57723, name = "Exhaustion" }, { id = 57724, name = "Sated" },
        { id = 80354, name = "Temporal Displacement" }, { id = 95809, name = "Insanity" },
        { id = 160455, name = "Fatigued" }, { id = 264689, name = "Fatigued" },
        { id = 390435, name = "Exhaustion" },
    }},
    { name = "Deserter", spells = {
        { id = 26013, name = "Deserter" }, { id = 71041, name = "Dungeon Deserter" },
    }},
}

local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then return GetSpecializationInfo(specIndex) end
    return nil
end

---------------------------------------------------------------------------
-- FAKE DATA
---------------------------------------------------------------------------
local FAKE_BUFF_ICONS = { 136034, 135940, 136081, 135932, 136063, 135987, 136070, 135864 }
local FAKE_DEBUFF_ICONS = { 136207, 136130, 135813, 136118, 135959, 136066, 136133, 135835 }
local FAKE_CLASS = "PALADIN"
local FAKE_NAME = "Healena"
local FAKE_HP_PCT = 65

---------------------------------------------------------------------------
-- DYNAMIC LAYOUT
---------------------------------------------------------------------------
local function CreateDynamicLayout(content, onRelayout)
    local rows = {}
    local L = {}
    function L:Row(widget, height, condFn, isHeader)
        rows[#rows + 1] = { widget = widget, height = height, condFn = condFn, isHeader = isHeader }
        if not isHeader then widget:SetPoint("RIGHT", content, "RIGHT", -PAD, 0) end
    end
    function L:Header(widget) self:Row(widget, widget.gap, nil, true) end
    function L:Finish()
        local function Relayout()
            local ly = -10
            for _, row in ipairs(rows) do
                local visible = true
                if row.condFn then visible = row.condFn() end
                if visible then
                    row.widget:ClearAllPoints()
                    row.widget:SetPoint("TOPLEFT", PAD, ly)
                    if not row.isHeader then row.widget:SetPoint("RIGHT", content, "RIGHT", -PAD, 0) end
                    row.widget:Show()
                    ly = ly - row.height
                else
                    row.widget:Hide()
                end
            end
            content:SetHeight(math.abs(ly) + 10)
            if onRelayout then onRelayout() end
        end
        for _, row in ipairs(rows) do
            if row.widget.track and not row.condFn then
                row.widget.track:HookScript("OnClick", Relayout)
            end
        end
        Relayout()
        return Relayout
    end
    return L
end

---------------------------------------------------------------------------
-- COMPOSER COLLAPSIBLE SECTIONS
---------------------------------------------------------------------------
local GUI  -- forward-declared, set on Open()
local C    -- forward-declared, set on Open()
local COLLAPSIBLE_HEADER_H = 24

local function CreateComposerCollapsible(parent, title, buildFn, sections, masterRelayout)
    local section = CreateFrame("Frame", nil, parent)
    section:SetHeight(COLLAPSIBLE_HEADER_H)

    local btn = CreateFrame("Button", nil, section)
    btn:SetPoint("TOPLEFT", 0, 0)
    btn:SetPoint("TOPRIGHT", 0, 0)
    btn:SetHeight(COLLAPSIBLE_HEADER_H)

    local chevron = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chevron:SetPoint("LEFT", 2, 0)
    chevron:SetText(">")

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
    label:SetText(title)

    local underline = btn:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", 0, -COLLAPSIBLE_HEADER_H)
    body:SetPoint("RIGHT", 0, 0)
    body:SetHeight(1)
    body:Hide()

    section._expanded = false
    section._body = body

    local function UpdateSectionHeight()
        if section._expanded then
            section:SetHeight(COLLAPSIBLE_HEADER_H + body:GetHeight())
        else
            section:SetHeight(COLLAPSIBLE_HEADER_H)
        end
        if masterRelayout then masterRelayout() end
    end

    section._updateHeight = UpdateSectionHeight

    buildFn(body, UpdateSectionHeight)

    local function ApplyColors()
        local colors = GUI and GUI.Colors
        local r, g, b = 0.376, 0.647, 0.980
        if colors and colors.accent then r, g, b = colors.accent[1], colors.accent[2], colors.accent[3] end
        chevron:SetTextColor(r, g, b, 1)
        label:SetTextColor(r, g, b, 1)
        underline:SetColorTexture(r, g, b, 0.3)
        btn:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
            chevron:SetTextColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function()
            label:SetTextColor(r, g, b, 1)
            chevron:SetTextColor(r, g, b, 1)
        end)
    end
    ApplyColors()

    btn:SetScript("OnClick", function()
        section._expanded = not section._expanded
        if section._expanded then
            chevron:SetText("v")
            body:Show()
        else
            chevron:SetText(">")
            body:Hide()
        end
        UpdateSectionHeight()
    end)

    if sections then sections[#sections + 1] = section end
    return section
end

local function RelayoutComposerSections(content, sections)
    local cy = -4
    for _, s in ipairs(sections) do
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", content, "TOPLEFT", 0, cy)
        s:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        cy = cy - s:GetHeight() - 2
    end
    content:SetHeight(math.abs(cy) + 8)
end

---------------------------------------------------------------------------
-- SPELL LIST UI
---------------------------------------------------------------------------
local function GetSpellName(spellId)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellId)
        if ok and name and name ~= "" then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellId)
        if ok and name and name ~= "" then return name end
    end
    return nil
end

local function CreateMiniToggle(parent)
    local GUI = QUI and QUI.GUI
    local C = GUI and GUI.Colors or {}
    local track = CreateFrame("Button", nil, parent, "BackdropTemplate")
    SetSizePx(track, 32, 16)
    ApplyPixelBackdrop(track, 1, true)
    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    SetSizePx(thumb, 12, 12)
    ApplyPixelBackdrop(thumb, 1, true)
    thumb:SetBackdropColor(C.toggleThumb and C.toggleThumb[1] or 1, C.toggleThumb and C.toggleThumb[2] or 1, C.toggleThumb and C.toggleThumb[3] or 1, 1)
    thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    track.thumb = thumb
    local function RefreshLayout(owner)
        SetSizePx(owner, 32, 16)
        ApplyPixelBackdrop(owner, 1, true)
        SetSizePx(thumb, 12, 12)
        ApplyPixelBackdrop(thumb, 1, true)
        thumb:SetBackdropColor(C.toggleThumb and C.toggleThumb[1] or 1, C.toggleThumb and C.toggleThumb[2] or 1, C.toggleThumb and C.toggleThumb[3] or 1, 1)
        thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
        thumb:ClearAllPoints()
        if owner._toggleOn then SetPointPx(thumb, "RIGHT", owner, "RIGHT", -2, 0)
        else SetPointPx(thumb, "LEFT", owner, "LEFT", 2, 0) end
    end
    function track:SetToggleState(on)
        self._toggleOn = on and true or false
        if self._toggleOn then
            self:SetBackdropColor(C.accent and C.accent[1] or 0.376, C.accent and C.accent[2] or 0.647, C.accent and C.accent[3] or 0.980, 1)
            self:SetBackdropBorderColor((C.accent and C.accent[1] or 0.376) * 0.8, (C.accent and C.accent[2] or 0.647) * 0.8, (C.accent and C.accent[3] or 0.980) * 0.8, 1)
        else
            self:SetBackdropColor(C.toggleOff and C.toggleOff[1] or 0.15, C.toggleOff and C.toggleOff[2] or 0.15, C.toggleOff and C.toggleOff[3] or 0.15, 1)
            self:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
        end
        RefreshLayout(self)
    end
    if UIKit and UIKit.RegisterScaleRefresh then UIKit.RegisterScaleRefresh(track, "composerMiniToggle", RefreshLayout) end
    track:SetToggleState(false)
    return track
end

local function RebuildSpellToggleRows(container, listTable, presets, onChange)
    if container._rows then
        for _, row in ipairs(container._rows) do row:Hide() end
    end
    container._rows = container._rows or {}
    local ROW_H, HEADER_H = 26, 22
    local y, rowIndex = 0, 0
    local presetSpellIds = {}
    for _, preset in ipairs(presets) do
        rowIndex = rowIndex + 1
        local headerRow = container._rows[rowIndex]
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, container)
            headerRow:SetHeight(HEADER_H)
            container._rows[rowIndex] = headerRow
            headerRow.text = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerRow.text:SetPoint("LEFT", 2, 0)
            headerRow.text:SetJustifyH("LEFT")
        end
        if headerRow.toggle then headerRow.toggle:Hide() end
        if headerRow.removeBtn then headerRow.removeBtn:Hide() end
        headerRow.text:SetText("|cFF56D1FF" .. preset.name .. "|r")
        headerRow:SetPoint("TOPLEFT", 0, y)
        headerRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        headerRow:Show()
        y = y - HEADER_H
        for _, spell in ipairs(preset.spells) do
            presetSpellIds[spell.id] = true
            rowIndex = rowIndex + 1
            local row = container._rows[rowIndex]
            if not row then
                row = CreateFrame("Frame", nil, container)
                row:SetHeight(ROW_H)
                container._rows[rowIndex] = row
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -44, 0)
                row.text:SetJustifyH("LEFT")
                row.toggle = CreateMiniToggle(row)
                row.toggle:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            end
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            row.text:SetText(spell.name or GetSpellName(spell.id) or ("Spell " .. spell.id))
            if row.toggle then row.toggle:Show() end
            if row.removeBtn then row.removeBtn:Hide() end
            row.toggle:SetToggleState(listTable[spell.id] == true)
            local spellId = spell.id
            row.toggle:SetScript("OnClick", function()
                local nowOn = listTable[spellId] ~= true
                if nowOn then listTable[spellId] = true else listTable[spellId] = nil end
                row.toggle:SetToggleState(nowOn)
                if onChange then onChange() end
            end)
            row:Show()
            y = y - ROW_H
        end
    end
    -- Extra spells not in presets
    local extras = {}
    for spellId in pairs(listTable) do
        if not presetSpellIds[spellId] then extras[#extras+1] = spellId end
    end
    table.sort(extras)
    if #extras > 0 then
        rowIndex = rowIndex + 1
        local headerRow = container._rows[rowIndex]
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, container)
            headerRow:SetHeight(HEADER_H)
            container._rows[rowIndex] = headerRow
            headerRow.text = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerRow.text:SetPoint("LEFT", 2, 0)
            headerRow.text:SetJustifyH("LEFT")
        end
        if headerRow.toggle then headerRow.toggle:Hide() end
        if headerRow.removeBtn then headerRow.removeBtn:Hide() end
        headerRow.text:SetText("|cFF56D1FFOther|r")
        headerRow:SetPoint("TOPLEFT", 0, y)
        headerRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        headerRow:Show()
        y = y - HEADER_H
        for _, spellId in ipairs(extras) do
            rowIndex = rowIndex + 1
            local row = container._rows[rowIndex]
            if not row then
                row = CreateFrame("Frame", nil, container)
                row:SetHeight(ROW_H)
                container._rows[rowIndex] = row
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetJustifyH("LEFT")
                row.removeBtn = CreateFrame("Button", nil, row)
                row.removeBtn:SetSize(18, 18)
                row.removeBtn:SetPoint("RIGHT", -2, 0)
                row.removeBtnText = row.removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.removeBtnText:SetPoint("CENTER")
                row.removeBtnText:SetText("\195\151")
                row.removeBtnText:SetTextColor(0.8, 0.3, 0.3)
                row.removeBtn:SetScript("OnEnter", function() row.removeBtnText:SetTextColor(1, 0.4, 0.4) end)
                row.removeBtn:SetScript("OnLeave", function() row.removeBtnText:SetTextColor(0.8, 0.3, 0.3) end)
            end
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            row.text:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)
            row.text:SetText(GetSpellName(spellId) or ("Spell " .. spellId))
            if row.toggle then row.toggle:Hide() end
            if row.removeBtn then row.removeBtn:Show() end
            row.removeBtn:SetScript("OnClick", function()
                listTable[spellId] = nil
                RebuildSpellToggleRows(container, listTable, presets, onChange)
                if onChange then onChange() end
            end)
            row:Show()
            y = y - ROW_H
        end
    end
    for i = rowIndex + 1, #container._rows do container._rows[i]:Hide() end
    container:SetHeight(math.max(1, math.abs(y)))
end

local function BuildSpellListSection(parent, getListTable, onChange, y, customPresets)
    local spellListContainer = CreateFrame("Frame", nil, parent)
    spellListContainer:SetPoint("TOPLEFT", PAD, y)
    spellListContainer:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
    spellListContainer:SetHeight(1)
    local presets
    if customPresets then
        presets = customPresets
    else
        local specID = GetPlayerSpecID()
        presets = {}
        if specID and SPEC_TO_PRESET[specID] then presets[#presets+1] = SPEC_TO_PRESET[specID] end
        if COMMON_DEFENSIVES_PRESET then presets[#presets+1] = COMMON_DEFENSIVES_PRESET end
    end
    local listTable = getListTable()
    if listTable then RebuildSpellToggleRows(spellListContainer, listTable, presets, onChange) end
    return y, spellListContainer
end

---------------------------------------------------------------------------
-- ELEMENT BUILDERS (adapted from groupframedesigner.lua)
-- Each takes (content, gfdb_proxy, onChange) and uses CreateDynamicLayout
---------------------------------------------------------------------------

local function BuildHealthSettings(content, gfdb, onChange)
    local general = gfdb.general or {}
    local health = gfdb.health; if not health then gfdb.health = {} health = gfdb.health end
    local absorbs = gfdb.absorbs; if not absorbs then gfdb.absorbs = {} absorbs = gfdb.absorbs end
    local healPred = gfdb.healPrediction; if not healPred then gfdb.healPrediction = {} healPred = gfdb.healPrediction end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Health Bar", function(body, updateH)
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormDropdown(body, "Health Texture", GetTextureList(), "texture", general, onChange), DROP_ROW)
        L:Row(GUI:CreateFormSlider(body, "Health Opacity", 0, 1, 0.05, "defaultHealthOpacity", general, onChange), SLIDER_HEIGHT)
        L:Row(GUI:CreateFormDropdown(body, "Fill Direction", HEALTH_FILL_OPTIONS, "healthFillDirection", health, onChange), DROP_ROW)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Health Text", function(body, updateH)
        local cond = function() return health.showHealthText end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Health Text", "showHealthText", health, onChange), FORM_ROW)
        L:Row(GUI:CreateFormDropdown(body, "Display Style", HEALTH_DISPLAY_OPTIONS, "healthDisplayStyle", health, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Font Size", 6, 24, 1, "healthFontSize", health, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "healthAnchor", health, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Text Justify", TEXT_JUSTIFY_OPTIONS, "healthJustify", health, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "healthOffsetX", health, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "healthOffsetY", health, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormColorPicker(body, "Text Color", "healthTextColor", health, onChange), FORM_ROW, cond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Absorb Shield", function(body, updateH)
        local absorbCond = function() return absorbs.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Absorb Shield", "enabled", absorbs, onChange), FORM_ROW)
        L:Row(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", absorbs, onChange), FORM_ROW, absorbCond)
        L:Row(GUI:CreateFormColorPicker(body, "Absorb Color", "color", absorbs, onChange), FORM_ROW, function() return absorbs.enabled and not absorbs.useClassColor end)
        L:Row(GUI:CreateFormSlider(body, "Absorb Opacity", 0.1, 1, 0.05, "opacity", absorbs, onChange), SLIDER_HEIGHT, absorbCond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Heal Prediction", function(body, updateH)
        local healCond = function() return healPred.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Heal Prediction", "enabled", healPred, onChange), FORM_ROW)
        L:Row(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", healPred, onChange), FORM_ROW, healCond)
        L:Row(GUI:CreateFormColorPicker(body, "Heal Prediction Color", "color", healPred, onChange), FORM_ROW, function() return healPred.enabled and not healPred.useClassColor end)
        L:Row(GUI:CreateFormSlider(body, "Heal Prediction Opacity", 0.1, 1, 0.05, "opacity", healPred, onChange), SLIDER_HEIGHT, healCond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildPowerSettings(content, gfdb, onChange)
    local power = gfdb.power; if not power then gfdb.power = {} power = gfdb.power end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Power Bar", function(body, updateH)
        local cond = function() return power.showPowerBar end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Power Bar", "showPowerBar", power, onChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Height", 1, 12, 1, "powerBarHeight", power, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Only Show for Healers", "powerBarOnlyHealers", power, onChange), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Only Show for Tanks", "powerBarOnlyTanks", power, onChange), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Use Power Type Color", "powerBarUsePowerColor", power, onChange), FORM_ROW, cond)
        L:Row(GUI:CreateFormColorPicker(body, "Custom Color", "powerBarColor", power, onChange), FORM_ROW, cond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildNameSettings(content, gfdb, onChange)
    local name = gfdb.name; if not name then gfdb.name = {} name = gfdb.name end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Name Text", function(body, updateH)
        local cond = function() return name.showName end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Name", "showName", name, onChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Font Size", 6, 24, 1, "nameFontSize", name, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "nameAnchor", name, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Text Justify", TEXT_JUSTIFY_OPTIONS, "nameJustify", name, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Max Name Length (0 = unlimited)", 0, 20, 1, "maxNameLength", name, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "nameOffsetX", name, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "nameOffsetY", name, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Use Class Color", "nameTextUseClassColor", name, onChange), FORM_ROW, cond)
        L:Row(GUI:CreateFormColorPicker(body, "Text Color", "nameTextColor", name, onChange), FORM_ROW, cond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildBuffsSettings(content, gfdb, onChange)
    local auras = gfdb.auras; if not auras then gfdb.auras = {} auras = gfdb.auras end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    -- Collect per-section relayouts so cross-collapsible cond deps stay in sync
    local sectionRelayouts = {}
    local function syncedOnChange()
        if onChange then onChange() end
        for _, fn in ipairs(sectionRelayouts) do fn() end
    end

    CreateComposerCollapsible(content, "Buffs", function(body, updateH)
        local cond = function() return auras.showBuffs end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Buffs", "showBuffs", auras, syncedOnChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Buffs", 0, 8, 1, "maxBuffs", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 32, 1, "buffIconSize", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "buffAnchor", auras, syncedOnChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "buffGrowDirection", auras, syncedOnChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "buffSpacing", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "buffOffsetX", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "buffOffsetY", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        sectionRelayouts[#sectionRelayouts + 1] = L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Buff Filtering", function(body, updateH)
        local cond = function() return auras.showBuffs end
        local classCond = function() return auras.showBuffs and (auras.filterMode or "off") == "classification" end
        local classificationContainer = CreateFrame("Frame", nil, body)
        classificationContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormDropdown(body, "Filter Mode", FILTER_MODE_OPTIONS, "filterMode", auras, syncedOnChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Only My Buffs", "buffFilterOnlyMine", auras, syncedOnChange), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Hide Permanent Buffs", "buffHidePermanent", auras, syncedOnChange), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Deduplicate Defensives/Indicators", "buffDeduplicateDefensives", auras, syncedOnChange), FORM_ROW, cond)
        L:Row(classificationContainer, FORM_ROW * 3, classCond)
        local classY = 0
        local buffClass = auras.buffClassifications; if not buffClass then auras.buffClassifications = {} buffClass = auras.buffClassifications end
        local c1 = GUI:CreateFormCheckbox(classificationContainer, "Raid", "raid", buffClass, syncedOnChange); c1:SetPoint("TOPLEFT", 0, classY); c1:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local c2 = GUI:CreateFormCheckbox(classificationContainer, "Cancelable", "cancelable", buffClass, syncedOnChange); c2:SetPoint("TOPLEFT", 0, classY); c2:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local c5 = GUI:CreateFormCheckbox(classificationContainer, "Important", "important", buffClass, syncedOnChange); c5:SetPoint("TOPLEFT", 0, classY); c5:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        classificationContainer:SetHeight(math.abs(classY))
        sectionRelayouts[#sectionRelayouts + 1] = L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Buff Blacklist", function(body, updateH)
        local desc = GUI:CreateLabel(body, "Blacklisted buffs are always hidden regardless of filter mode.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        desc:SetPoint("TOPLEFT", PAD, -6)
        desc:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        if not auras.buffBlacklist then auras.buffBlacklist = {} end
        local _, blContainer = BuildSpellListSection(body, function() return auras.buffBlacklist end, function()
            if not blContainer then return end
            blContainer:ClearAllPoints()
            blContainer:SetPoint("TOPLEFT", PAD, -30)
            blContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
            body:SetHeight(30 + blContainer:GetHeight() + 10)
            updateH()
            if onChange then onChange() end
        end, -30, BUFF_BLACKLIST_PRESETS)
        blContainer:ClearAllPoints()
        blContainer:SetPoint("TOPLEFT", PAD, -30)
        blContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        body:SetHeight(30 + blContainer:GetHeight() + 10)
    end, sections, relayout)

    relayout()
end

local function BuildDebuffsSettings(content, gfdb, onChange)
    local auras = gfdb.auras; if not auras then gfdb.auras = {} auras = gfdb.auras end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    -- Collect per-section relayouts so cross-collapsible cond deps stay in sync
    local sectionRelayouts = {}
    local function syncedOnChange()
        if onChange then onChange() end
        for _, fn in ipairs(sectionRelayouts) do fn() end
    end

    CreateComposerCollapsible(content, "Debuffs", function(body, updateH)
        local cond = function() return auras.showDebuffs end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Debuffs", "showDebuffs", auras, syncedOnChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Debuffs", 0, 8, 1, "maxDebuffs", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 32, 1, "debuffIconSize", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "debuffAnchor", auras, syncedOnChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "debuffGrowDirection", auras, syncedOnChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "debuffSpacing", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "debuffOffsetX", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "debuffOffsetY", auras, syncedOnChange), SLIDER_HEIGHT, cond)
        sectionRelayouts[#sectionRelayouts + 1] = L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Debuff Filtering", function(body, updateH)
        local cond = function() return auras.showDebuffs end
        local classCond = function() return auras.showDebuffs and (auras.filterMode or "off") == "classification" end
        local classificationContainer = CreateFrame("Frame", nil, body)
        classificationContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormDropdown(body, "Filter Mode", FILTER_MODE_OPTIONS, "filterMode", auras, syncedOnChange), DROP_ROW, cond)
        L:Row(classificationContainer, FORM_ROW * 3, classCond)
        local classY = 0
        local debuffClass = auras.debuffClassifications; if not debuffClass then auras.debuffClassifications = {} debuffClass = auras.debuffClassifications end
        local d1 = GUI:CreateFormCheckbox(classificationContainer, "Raid", "raid", debuffClass, syncedOnChange); d1:SetPoint("TOPLEFT", 0, classY); d1:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local d2 = GUI:CreateFormCheckbox(classificationContainer, "Crowd Control", "crowdControl", debuffClass, syncedOnChange); d2:SetPoint("TOPLEFT", 0, classY); d2:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local d3 = GUI:CreateFormCheckbox(classificationContainer, "Important", "important", debuffClass, syncedOnChange); d3:SetPoint("TOPLEFT", 0, classY); d3:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        classificationContainer:SetHeight(math.abs(classY))
        sectionRelayouts[#sectionRelayouts + 1] = L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Debuff Blacklist", function(body, updateH)
        local desc = GUI:CreateLabel(body, "Blacklisted debuffs are always hidden regardless of filter mode.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        desc:SetPoint("TOPLEFT", PAD, -6)
        desc:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        if not auras.debuffBlacklist then auras.debuffBlacklist = {} end
        local _, blContainer = BuildSpellListSection(body, function() return auras.debuffBlacklist end, function()
            if not blContainer then return end
            blContainer:ClearAllPoints()
            blContainer:SetPoint("TOPLEFT", PAD, -30)
            blContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
            body:SetHeight(30 + blContainer:GetHeight() + 10)
            updateH()
            if onChange then onChange() end
        end, -30, DEBUFF_BLACKLIST_PRESETS)
        blContainer:ClearAllPoints()
        blContainer:SetPoint("TOPLEFT", PAD, -30)
        blContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        body:SetHeight(30 + blContainer:GetHeight() + 10)
    end, sections, relayout)

    relayout()
end

local function BuildIndicatorsSettings(content, gfdb, onChange)
    local ind = gfdb.indicators; if not ind then gfdb.indicators = {} ind = gfdb.indicators end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Role Icon", function(body, updateH)
        local roleCond = function() return ind.showRoleIcon end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Role Icon", "showRoleIcon", ind, onChange), FORM_ROW)
        L:Row(GUI:CreateFormCheckbox(body, "Show Tank", "showRoleTank", ind, onChange), FORM_ROW, roleCond)
        L:Row(GUI:CreateFormCheckbox(body, "Show Healer", "showRoleHealer", ind, onChange), FORM_ROW, roleCond)
        L:Row(GUI:CreateFormCheckbox(body, "Show DPS", "showRoleDPS", ind, onChange), FORM_ROW, roleCond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 6, 24, 1, "roleIconSize", ind, onChange), SLIDER_HEIGHT, roleCond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "roleIconAnchor", ind, onChange), DROP_ROW, roleCond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "roleIconOffsetX", ind, onChange), SLIDER_HEIGHT, roleCond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "roleIconOffsetY", ind, onChange), SLIDER_HEIGHT, roleCond)
        L:Finish()
    end, sections, relayout)

    local function AddIndicatorCollapsible(label, showKey, sizeKey, anchorKey, offXKey, offYKey)
        CreateComposerCollapsible(content, label, function(body, updateH)
            local cond = function() return ind[showKey] end
            local L = CreateDynamicLayout(body, updateH)
            L:Row(GUI:CreateFormCheckbox(body, "Enable", showKey, ind, onChange), FORM_ROW)
            L:Row(GUI:CreateFormSlider(body, "Icon Size", 6, 32, 1, sizeKey, ind, onChange), SLIDER_HEIGHT, cond)
            L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, anchorKey, ind, onChange), DROP_ROW, cond)
            L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, offXKey, ind, onChange), SLIDER_HEIGHT, cond)
            L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, offYKey, ind, onChange), SLIDER_HEIGHT, cond)
            L:Finish()
        end, sections, relayout)
    end

    AddIndicatorCollapsible("Ready Check", "showReadyCheck", "readyCheckSize", "readyCheckAnchor", "readyCheckOffsetX", "readyCheckOffsetY")
    AddIndicatorCollapsible("Resurrection", "showResurrection", "resurrectionSize", "resurrectionAnchor", "resurrectionOffsetX", "resurrectionOffsetY")
    AddIndicatorCollapsible("Summon Pending", "showSummonPending", "summonSize", "summonAnchor", "summonOffsetX", "summonOffsetY")
    AddIndicatorCollapsible("Leader Icon", "showLeaderIcon", "leaderSize", "leaderAnchor", "leaderOffsetX", "leaderOffsetY")
    AddIndicatorCollapsible("Raid Target Marker", "showTargetMarker", "targetMarkerSize", "targetMarkerAnchor", "targetMarkerOffsetX", "targetMarkerOffsetY")
    AddIndicatorCollapsible("Phase Icon", "showPhaseIcon", "phaseSize", "phaseAnchor", "phaseOffsetX", "phaseOffsetY")

    CreateComposerCollapsible(content, "Threat", function(body, updateH)
        local threatCond = function() return ind.showThreatBorder end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Threat Border", "showThreatBorder", ind, onChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Border Size", 1, 16, 1, "threatBorderSize", ind, onChange), SLIDER_HEIGHT, threatCond)
        L:Row(GUI:CreateFormColorPicker(body, "Threat Color", "threatColor", ind, onChange), FORM_ROW, threatCond)
        L:Row(GUI:CreateFormSlider(body, "Threat Fill Opacity", 0, 0.5, 0.05, "threatFillOpacity", ind, onChange), SLIDER_HEIGHT, threatCond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildHealerSettings(content, gfdb, onChange)
    local healer = gfdb.healer; if not healer then gfdb.healer = {} healer = gfdb.healer end
    local dispel = healer.dispelOverlay; if not dispel then healer.dispelOverlay = {} dispel = healer.dispelOverlay end
    local dispelColors = dispel.colors
    if not dispelColors then
        dispel.colors = { Magic = {0.2,0.6,1.0,1}, Curse = {0.6,0.0,1.0,1}, Disease = {0.6,0.4,0.0,1}, Poison = {0.0,0.6,0.0,1} }
        dispelColors = dispel.colors
    end
    local targetHL = healer.targetHighlight; if not targetHL then healer.targetHighlight = {} targetHL = healer.targetHighlight end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Dispel Overlay", function(body, updateH)
        local dispelCond = function() return dispel.enabled end
        local L = CreateDynamicLayout(body, updateH)
        local desc = GUI:CreateLabel(body, "Colors the frame border when a dispellable debuff is active.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        L:Row(desc, 26)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Dispel Overlay", "enabled", dispel, onChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Border Size", 1, 16, 1, "borderSize", dispel, onChange), SLIDER_HEIGHT, dispelCond)
        L:Row(GUI:CreateFormSlider(body, "Border Opacity", 0.1, 1, 0.05, "opacity", dispel, onChange), SLIDER_HEIGHT, dispelCond)
        L:Row(GUI:CreateFormSlider(body, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", dispel, onChange), SLIDER_HEIGHT, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Magic Color", "Magic", dispelColors, onChange), FORM_ROW, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Curse Color", "Curse", dispelColors, onChange), FORM_ROW, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Disease Color", "Disease", dispelColors, onChange), FORM_ROW, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Poison Color", "Poison", dispelColors, onChange), FORM_ROW, dispelCond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Target Highlight", function(body, updateH)
        local targetCond = function() return targetHL.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Target Highlight", "enabled", targetHL, onChange), FORM_ROW)
        L:Row(GUI:CreateFormColorPicker(body, "Highlight Color", "color", targetHL, onChange), FORM_ROW, targetCond)
        L:Row(GUI:CreateFormSlider(body, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", targetHL, onChange), SLIDER_HEIGHT, targetCond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildDefensiveSettings(content, gfdb, onChange)
    local healer = gfdb.healer; if not healer then gfdb.healer = {} healer = gfdb.healer end
    local def = healer.defensiveIndicator; if not def then healer.defensiveIndicator = {} def = healer.defensiveIndicator end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Defensive Indicator", function(body, updateH)
        local cond = function() return def.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Defensive Indicator", "enabled", def, onChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Icons", 1, 5, 1, "maxIcons", def, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 32, 1, "iconSize", def, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", def, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "spacing", def, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Position", NINE_POINT_OPTIONS, "position", def, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "offsetX", def, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "offsetY", def, onChange), SLIDER_HEIGHT, cond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildPrivateAurasSettings(content, gfdb, onChange)
    local pa = gfdb.privateAuras; if not pa then gfdb.privateAuras = {} pa = gfdb.privateAuras end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Private Auras", function(body, updateH)
        local cond = function() return pa.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Private Auras", "enabled", pa, onChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Per Frame", 1, 5, 1, "maxPerFrame", pa, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 10, 40, 1, "iconSize", pa, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", pa, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "spacing", pa, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "anchor", pa, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "anchorOffsetX", pa, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "anchorOffsetY", pa, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Show Countdown", "showCountdown", pa, onChange), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Show Countdown Numbers", "showCountdownNumbers", pa, onChange), FORM_ROW, cond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildAuraIndicatorsSettings(content, gfdb, onChange)
    local ai = gfdb.auraIndicators; if not ai then gfdb.auraIndicators = {} ai = gfdb.auraIndicators end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Aura Indicators", function(body, updateH)
        local cond = function() return ai.enabled end
        local L = CreateDynamicLayout(body, updateH)
        local desc = GUI:CreateLabel(body, "Track specific spells as icons on group frames. Auto-detects your spec.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        L:Row(desc, 30)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Aura Indicators", "enabled", ai, onChange), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 32, 1, "iconSize", ai, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Max Indicators", 1, 10, 1, "maxIndicators", ai, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "anchor", ai, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", ai, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "spacing", ai, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "anchorOffsetX", ai, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "anchorOffsetY", ai, onChange), SLIDER_HEIGHT, cond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Tracked Spells", function(body, updateH)
        local desc = GUI:CreateLabel(body, "Toggle which spells are tracked for your current spec.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        desc:SetPoint("TOPLEFT", PAD, -6)
        desc:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        if not ai.trackedSpells then ai.trackedSpells = {} end
        local _, spellListContainer = BuildSpellListSection(body, function() return ai.trackedSpells end, function()
            if not spellListContainer then return end
            spellListContainer:ClearAllPoints()
            spellListContainer:SetPoint("TOPLEFT", PAD, -30)
            spellListContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
            body:SetHeight(30 + spellListContainer:GetHeight() + 10)
            updateH()
            if onChange then onChange() end
        end, -30)
        spellListContainer:ClearAllPoints()
        spellListContainer:SetPoint("TOPLEFT", PAD, -30)
        spellListContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        body:SetHeight(30 + spellListContainer:GetHeight() + 10)
    end, sections, relayout)

    relayout()
end

---------------------------------------------------------------------------
-- ELEMENT TABLES
---------------------------------------------------------------------------
local COMPOSER_ELEMENT_KEYS = {
    "health", "power", "name", "buffs", "debuffs",
    "indicators", "healer", "defensive", "auraIndicators", "privateAuras",
}

local ELEMENT_LABELS = {
    health = "Health", power = "Power", name = "Name",
    buffs = "Buffs", debuffs = "Debuffs", indicators = "Indicators",
    healer = "Healer", defensive = "Defensive",
    auraIndicators = "Aura Ind.", privateAuras = "Priv. Auras",
}

local ELEMENT_BUILDERS = {
    health = BuildHealthSettings, power = BuildPowerSettings,
    name = BuildNameSettings, buffs = BuildBuffsSettings,
    debuffs = BuildDebuffsSettings, indicators = BuildIndicatorsSettings,
    healer = BuildHealerSettings, defensive = BuildDefensiveSettings,
    auraIndicators = BuildAuraIndicatorsSettings, privateAuras = BuildPrivateAurasSettings,
}

---------------------------------------------------------------------------
-- WIDGET BAR
---------------------------------------------------------------------------
local function CreateWidgetBar(container, selectElementFunc, state)
    local bar = CreateFrame("Frame", nil, container)
    bar:SetHeight(1)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    local buttons, orderedButtons = {}, {}
    local fontPath = (GUI and GUI.FONT_PATH) or "Fonts\\FRIZQT__.TTF"
    local btnHeight, btnSpacing, rowGap = 24, 4, 4
    for _, key in ipairs(COMPOSER_ELEMENT_KEYS) do
        local label = ELEMENT_LABELS[key]
        local btn = CreateFrame("Button", nil, bar, "BackdropTemplate")
        btn:SetHeight(RoundVirtual(btnHeight, btn))
        ApplyPixelBackdrop(btn, 1, true)
        btn:SetBackdropColor(0.12, 0.12, 0.12, 1)
        btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetFont(fontPath, 11, "")
        text:SetTextColor(C.text[1], C.text[2], C.text[3])
        text:SetText(label)
        text:SetPoint("CENTER")
        btn:SetWidth(RoundVirtual((text:GetStringWidth() or 40) + 16, btn))
        btn.elementKey = key
        btn.text = text
        btn:SetScript("OnClick", function() selectElementFunc(key) end)
        btn:SetScript("OnEnter", function(self)
            if state.selectedElement ~= key then self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.6) end
        end)
        btn:SetScript("OnLeave", function(self)
            if state.selectedElement ~= key then self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end
        end)
        buttons[key] = btn
        orderedButtons[#orderedButtons + 1] = btn
    end
    local function RelayoutBar()
        local x, y = 0, 0
        local barWidth = container:GetWidth() - (PAD * 2)
        if barWidth < 100 then barWidth = 560 end
        barWidth = RoundVirtual(barWidth, bar)
        for _, btn in ipairs(orderedButtons) do
            local btnWidth = RoundVirtual((btn.text:GetStringWidth() or 40) + 16, btn)
            if x + btnWidth > barWidth and x > 0 then x = 0; y = RoundVirtual(y - (btnHeight + rowGap), bar) end
            btn:SetWidth(btnWidth)
            btn:ClearAllPoints()
            SetSnappedPoint(btn, "TOPLEFT", bar, "TOPLEFT", x, y)
            x = RoundVirtual(x + btnWidth + btnSpacing, bar)
        end
        local totalHeight = RoundVirtual(math.abs(y) + btnHeight, bar)
        bar:SetHeight(totalHeight)
        return totalHeight
    end
    local totalHeight = RelayoutBar()
    bar:SetScript("OnSizeChanged", function() totalHeight = RelayoutBar() end)
    state.widgetBarButtons = buttons
    return bar, totalHeight
end

---------------------------------------------------------------------------
-- POPUP FRAME
---------------------------------------------------------------------------
local composerFrame = nil

local function GetOrCreateFrame()
    if composerFrame then return composerFrame end

    GUI = QUI and QUI.GUI
    C = GUI and GUI.Colors or {}

    composerFrame = CreateFrame("Frame", "QUI_ComposerPopup", UIParent, "BackdropTemplate")
    composerFrame:SetSize(620, 720)
    composerFrame:SetPoint("CENTER")
    composerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    composerFrame:SetFrameLevel(300)
    composerFrame:SetMovable(true)
    composerFrame:SetClampedToScreen(true)
    composerFrame:EnableMouse(true)
    composerFrame:RegisterForDrag("LeftButton")
    composerFrame:SetScript("OnDragStart", composerFrame.StartMoving)
    composerFrame:SetScript("OnDragStop", composerFrame.StopMovingOrSizing)
    composerFrame:Hide()

    composerFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    composerFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.97)
    local GUI = _G.QUI and _G.QUI.GUI
    local C = GUI and GUI.Colors
    local ar = C and C.accent and C.accent[1] or 0.376
    local ag = C and C.accent and C.accent[2] or 0.647
    local ab = C and C.accent and C.accent[3] or 0.980
    composerFrame:SetBackdropBorderColor(ar, ag, ab, 0.8)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, composerFrame)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText("Group Frame Composer")
    titleText:SetTextColor(1, 1, 1, 1)
    composerFrame._titleText = titleText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtnText:SetFont(GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF", 18, "")
    closeBtnText:SetPoint("CENTER", 0, 0)
    closeBtnText:SetText("\195\151")
    closeBtnText:SetTextColor(0.8, 0.3, 0.3, 1)
    closeBtn:SetScript("OnEnter", function() closeBtnText:SetTextColor(1, 0.4, 0.4, 1) end)
    closeBtn:SetScript("OnLeave", function() closeBtnText:SetTextColor(0.8, 0.3, 0.3, 1) end)
    closeBtn:SetScript("OnClick", function() QUI_LayoutMode_Composer:Close() end)

    -- Content area
    local contentArea = CreateFrame("Frame", nil, composerFrame)
    contentArea:SetPoint("TOPLEFT", PAD, -32)
    contentArea:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    composerFrame._contentArea = contentArea

    return composerFrame
end

---------------------------------------------------------------------------
-- PREVIEW FRAME BUILDER (2x scaled replica of group frame)
---------------------------------------------------------------------------
local function CreateDesignerPreview(container, previewType, childRefs)
    local gfdb = GetGFDB()
    if not gfdb then return nil end
    childRefs = childRefs or {}

    local db = CreateVisualProxy(gfdb, previewType)
    local general = db.general or {}
    local dims = db.dimensions or {}
    local QUICore = ns.Addon

    local baseW, baseH
    if previewType == "raid" then
        baseW = dims.mediumRaidWidth or 160
        baseH = dims.mediumRaidHeight or 30
    else
        baseW = dims.partyWidth or 200
        baseH = dims.partyHeight or 40
    end

    local w, h = baseW * PREVIEW_SCALE, baseH * PREVIEW_SCALE
    local fontPath = (GUI and GUI.FONT_PATH) or "Fonts\\FRIZQT__.TTF"
    local fontOutline = general.fontOutline or "OUTLINE"

    -- Wrapper to center the preview
    local wrapper = CreateFrame("Frame", nil, container)
    wrapper:SetHeight(h + 20)
    wrapper:SetPoint("TOPLEFT", 0, 0)
    wrapper:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    -- Main frame
    local frame = CreateFrame("Frame", nil, wrapper, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetPoint("CENTER", wrapper, "CENTER", 0, 0)

    local borderPixels = general.borderSize or 1
    ApplyPixelBackdrop(frame, borderPixels, true)
    local px = QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    local borderSize = borderPixels * px

    -- Background color
    local bgR, bgG, bgB, bgA = 0.08, 0.08, 0.08, 0.9
    if general.darkMode and general.darkModeBgColor then
        local c = general.darkModeBgColor
        bgR, bgG, bgB = c[1] or bgR, c[2] or bgG, c[3] or bgB
        bgA = general.darkModeBgOpacity or 1
    elseif general.defaultBgColor then
        local c = general.defaultBgColor
        bgR, bgG, bgB = c[1] or bgR, c[2] or bgG, c[3] or bgB
        bgA = general.defaultBgOpacity or 1
    end
    frame:SetBackdropColor(bgR, bgG, bgB, bgA)
    frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    childRefs.frame = frame

    -- Health bar
    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetPoint("TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    local LSM = ns.LSM
    local textureName = general.texture or "Quazii v5"
    local texturePath = LSM and LSM:Fetch("statusbar", textureName) or "Interface\\TargetingFrame\\UI-StatusBar"
    healthBar:SetStatusBarTexture(texturePath)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(FAKE_HP_PCT)
    local previewHealth = db.health or {}
    if previewHealth.healthFillDirection == "VERTICAL" then healthBar:SetOrientation("VERTICAL") end
    childRefs.healthBar = healthBar

    -- Health bar color
    if general.darkMode then
        local dmc = general.darkModeHealthColor
        if dmc then healthBar:SetStatusBarColor(dmc[1] or 0.2, dmc[2] or 0.2, dmc[3] or 0.2, general.darkModeHealthOpacity or 1)
        else healthBar:SetStatusBarColor(0.2, 0.2, 0.2, 1) end
    elseif general.useClassColor then
        local cc = RAID_CLASS_COLORS[FAKE_CLASS]
        if cc then healthBar:SetStatusBarColor(cc.r, cc.g, cc.b, general.defaultHealthOpacity or 1) end
    else
        healthBar:SetStatusBarColor(0.2, 0.8, 0.2, general.defaultHealthOpacity or 1)
    end

    -- Power bar
    local powerDB = db.power or {}
    local powerH = 0
    if powerDB.showPowerBar ~= false then
        powerH = (powerDB.powerBarHeight or 4) * PREVIEW_SCALE
        local powerBar = CreateFrame("StatusBar", nil, frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerH)
        powerBar:SetStatusBarTexture(texturePath)
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(80)
        if powerDB.powerBarUsePowerColor then powerBar:SetStatusBarColor(0.2, 0.4, 0.8, 1)
        else local c = powerDB.powerBarColor or {0.2, 0.4, 0.8, 1}; powerBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1) end
        childRefs.powerBar = powerBar
        healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerH)
    end

    -- Text frame
    local textFrame = CreateFrame("Frame", nil, frame)
    textFrame:SetAllPoints(healthBar)
    textFrame:SetFrameLevel(healthBar:GetFrameLevel() + 2)

    -- Name text
    local nameDB = db.name or {}
    if nameDB.showName ~= false then
        local nameAnchor = nameDB.nameAnchor or "LEFT"
        local nameAnchorInfo = ANCHOR_MAP[nameAnchor] or ANCHOR_MAP.LEFT
        local nameOffsetX = (nameDB.nameOffsetX or 4) * PREVIEW_SCALE
        local nameOffsetY = (nameDB.nameOffsetY or 0) * PREVIEW_SCALE
        local namePadX = math.abs(nameOffsetX)
        local nameText = textFrame:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(fontPath, (nameDB.nameFontSize or 12) * PREVIEW_SCALE, fontOutline)
        nameText:SetPoint(nameAnchorInfo.leftPoint, textFrame, nameAnchorInfo.leftPoint, namePadX, nameOffsetY)
        nameText:SetPoint(nameAnchorInfo.rightPoint, textFrame, nameAnchorInfo.rightPoint, -namePadX, nameOffsetY)
        nameText:SetJustifyH(nameDB.nameJustify or nameAnchorInfo.justify)
        nameText:SetJustifyV(nameAnchorInfo.justifyV)
        nameText:SetWordWrap(false)
        local displayName = FAKE_NAME
        local maxLen = nameDB.maxNameLength or 10
        if maxLen > 0 and #displayName > maxLen then displayName = displayName:sub(1, maxLen) end
        nameText:SetText(displayName)
        if nameDB.nameTextUseClassColor then
            local cc = RAID_CLASS_COLORS[FAKE_CLASS]
            if cc then nameText:SetTextColor(cc.r, cc.g, cc.b, 1) else nameText:SetTextColor(1, 1, 1, 1) end
        elseif nameDB.nameTextColor then
            local tc = nameDB.nameTextColor; nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        else nameText:SetTextColor(1, 1, 1, 1) end
        childRefs.nameText = nameText
    end

    -- Health text
    local healthDB = db.health or {}
    if healthDB.showHealthText ~= false then
        local healthAnchor = healthDB.healthAnchor or "RIGHT"
        local healthAnchorInfo = ANCHOR_MAP[healthAnchor] or ANCHOR_MAP.RIGHT
        local healthOffsetX = (healthDB.healthOffsetX or -4) * PREVIEW_SCALE
        local healthOffsetY = (healthDB.healthOffsetY or 0) * PREVIEW_SCALE
        local healthPadX = math.abs(healthOffsetX)
        local healthText = textFrame:CreateFontString(nil, "OVERLAY")
        healthText:SetFont(fontPath, (healthDB.healthFontSize or 12) * PREVIEW_SCALE, fontOutline)
        healthText:SetPoint(healthAnchorInfo.leftPoint, textFrame, healthAnchorInfo.leftPoint, healthPadX, healthOffsetY)
        healthText:SetPoint(healthAnchorInfo.rightPoint, textFrame, healthAnchorInfo.rightPoint, -healthPadX, healthOffsetY)
        healthText:SetJustifyH(healthDB.healthJustify or healthAnchorInfo.justify)
        healthText:SetJustifyV(healthAnchorInfo.justifyV)
        healthText:SetWordWrap(false)
        local style = healthDB.healthDisplayStyle or "percent"
        local fakeHP = FAKE_HP_PCT * 1000
        if style == "percent" then healthText:SetText(FAKE_HP_PCT .. "%")
        elseif style == "absolute" then healthText:SetText(string.format("%.0fK", fakeHP / 1000))
        elseif style == "both" then healthText:SetText(string.format("%.0fK", fakeHP / 1000) .. " | " .. FAKE_HP_PCT .. "%")
        elseif style == "deficit" then local deficit = 100000 - fakeHP; healthText:SetText(deficit > 0 and ("-" .. string.format("%.0fK", deficit / 1000)) or "")
        else healthText:SetText(FAKE_HP_PCT .. "%") end
        if healthDB.healthTextColor then local tc = healthDB.healthTextColor; healthText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        else healthText:SetTextColor(1, 1, 1, 1) end
        childRefs.healthText = healthText
    end

    -- Role icon
    local indDB = db.indicators or {}
    if indDB.showRoleIcon ~= false then
        local roleSize = (indDB.roleIconSize or 12) * PREVIEW_SCALE
        local roleAnchor = indDB.roleIconAnchor or "TOPLEFT"
        local roleOffX = (indDB.roleIconOffsetX or 2) * PREVIEW_SCALE
        local roleOffY = (indDB.roleIconOffsetY or -2) * PREVIEW_SCALE
        local roleIcon = textFrame:CreateTexture(nil, "OVERLAY")
        roleIcon:SetSize(roleSize, roleSize)
        roleIcon:SetPoint(roleAnchor, textFrame, roleAnchor, roleOffX, roleOffY)
        roleIcon:SetAtlas("roleicon-tiny-healer")
        childRefs.roleIcon = roleIcon
    end

    -- Buff icons
    local auraDB = db.auras or {}
    local previewBottomPad = powerH + borderSize
    local function PreviewBottomPadY(anchor, offY)
        if anchor:find("BOTTOM") then return offY + previewBottomPad end
        return offY
    end

    if auraDB.showBuffs then
        local buffSize = (auraDB.buffIconSize or 14) * PREVIEW_SCALE
        local maxBuffs = auraDB.maxBuffs or 3
        local buffCount = math.min(maxBuffs, #FAKE_BUFF_ICONS)
        if buffCount > 0 then
            local buffAnchor = auraDB.buffAnchor or "TOPLEFT"
            local buffSpacing = (auraDB.buffSpacing or 2) * PREVIEW_SCALE
            local buffContainer = CreateFrame("Frame", nil, frame)
            buffContainer:SetFrameLevel(frame:GetFrameLevel() + 8)
            buffContainer:SetSize(buffCount * buffSize + math.max(buffCount - 1, 0) * buffSpacing, buffSize)
            buffContainer:SetPoint(buffAnchor, frame, buffAnchor, (auraDB.buffOffsetX or 2) * PREVIEW_SCALE, PreviewBottomPadY(buffAnchor, (auraDB.buffOffsetY or 16) * PREVIEW_SCALE))
            for i = 1, buffCount do
                local icon = buffContainer:CreateTexture(nil, "OVERLAY")
                icon:SetSize(buffSize, buffSize)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetTexture(FAKE_BUFF_ICONS[i])
                if i == 1 then icon:SetPoint("LEFT", buffContainer, "LEFT", 0, 0)
                else icon:SetPoint("LEFT", buffContainer, "LEFT", (i - 1) * (buffSize + buffSpacing), 0) end
            end
            childRefs.buffContainer = buffContainer
        end
    end

    -- Debuff icons
    if auraDB.showDebuffs ~= false then
        local debuffSize = (auraDB.debuffIconSize or 16) * PREVIEW_SCALE
        local maxDebuffs = auraDB.maxDebuffs or 3
        local debuffCount = math.min(maxDebuffs, #FAKE_DEBUFF_ICONS)
        if debuffCount > 0 then
            local debuffAnchor = auraDB.debuffAnchor or "BOTTOMRIGHT"
            local debuffGrow = auraDB.debuffGrowDirection or "LEFT"
            local debuffSpacing = (auraDB.debuffSpacing or 2) * PREVIEW_SCALE
            local debuffContainer = CreateFrame("Frame", nil, frame)
            debuffContainer:SetFrameLevel(frame:GetFrameLevel() + 8)
            debuffContainer:SetSize(debuffCount * debuffSize + math.max(debuffCount - 1, 0) * debuffSpacing, debuffSize)
            debuffContainer:SetPoint(debuffAnchor, frame, debuffAnchor, (auraDB.debuffOffsetX or -2) * PREVIEW_SCALE, PreviewBottomPadY(debuffAnchor, (auraDB.debuffOffsetY or -18) * PREVIEW_SCALE))
            for i = 1, debuffCount do
                local icon = debuffContainer:CreateTexture(nil, "OVERLAY")
                icon:SetSize(debuffSize, debuffSize)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetTexture(FAKE_DEBUFF_ICONS[i])
                local startAnchor = debuffGrow == "LEFT" and "RIGHT" or "LEFT"
                if i == 1 then icon:SetPoint(startAnchor, debuffContainer, startAnchor, 0, 0)
                else
                    local offset = (i - 1) * (debuffSize + debuffSpacing)
                    icon:SetPoint(startAnchor, debuffContainer, startAnchor, debuffGrow == "LEFT" and -offset or offset, 0)
                end
            end
            childRefs.debuffContainer = debuffContainer
        end
    end

    return wrapper
end

---------------------------------------------------------------------------
-- HIT OVERLAY + DRAG CONFIG
---------------------------------------------------------------------------
local function CreateHitOverlay(parent, previewFrame, elementKey, anchorFrame, mode, width, height, anchorPoint, anchorRelPoint, offX, offY, frameLevel)
    local overlay = CreateFrame("Button", nil, parent)
    overlay:SetFrameLevel(frameLevel or (previewFrame:GetFrameLevel() + 10))
    overlay.elementKey = elementKey
    if mode == "fill" then overlay:SetAllPoints(anchorFrame)
    elseif mode == "fixed" then
        overlay:SetSize(width or 30, height or 20)
        overlay:SetPoint(anchorPoint or "CENTER", anchorFrame, anchorRelPoint or anchorPoint or "CENTER", offX or 0, offY or 0)
    end
    local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    highlight:SetAllPoints()
    ApplyPixelBackdrop(highlight, 2, false)
    highlight:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    highlight:Hide()
    overlay.highlight = highlight
    return overlay
end

local DRAG_CONFIG = {
    name        = { sub = "name",       xKey = "nameOffsetX",       yKey = "nameOffsetY" },
    healthText  = { sub = "health",     xKey = "healthOffsetX",     yKey = "healthOffsetY" },
    role        = { sub = "indicators", xKey = "roleIconOffsetX",   yKey = "roleIconOffsetY" },
    buffs       = { sub = "auras",      xKey = "buffOffsetX",       yKey = "buffOffsetY" },
    debuffs     = { sub = "auras",      xKey = "debuffOffsetX",     yKey = "debuffOffsetY" },
    privateAuras    = { sub = "privateAuras",    xKey = "anchorOffsetX", yKey = "anchorOffsetY" },
    auraIndicators  = { sub = "auraIndicators",  xKey = "anchorOffsetX", yKey = "anchorOffsetY" },
    defensive       = { sub = "healer",          xKey = "offsetX",       yKey = "offsetY",  nested = "defensiveIndicator" },
    readyCheck      = { sub = "indicators", xKey = "readyCheckOffsetX",    yKey = "readyCheckOffsetY" },
    resurrection    = { sub = "indicators", xKey = "resurrectionOffsetX",  yKey = "resurrectionOffsetY" },
    summon          = { sub = "indicators", xKey = "summonOffsetX",        yKey = "summonOffsetY" },
    leader          = { sub = "indicators", xKey = "leaderOffsetX",        yKey = "leaderOffsetY" },
    targetMarker    = { sub = "indicators", xKey = "targetMarkerOffsetX",  yKey = "targetMarkerOffsetY" },
    phase           = { sub = "indicators", xKey = "phaseOffsetX",         yKey = "phaseOffsetY" },
}

local CLICK_TARGET = {
    frame = "health", healthText = "health", absorbs = "health",
    role = "indicators",
    readyCheck = "indicators", resurrection = "indicators",
    summon = "indicators", leader = "indicators",
    targetMarker = "indicators", phase = "indicators",
}

local SUB_ELEMENT_MAP = {
    readyCheck = "indicators", resurrection = "indicators",
    summon = "indicators", leader = "indicators",
    targetMarker = "indicators", phase = "indicators",
}

---------------------------------------------------------------------------
-- BUILD COMPOSER CONTENT (preview + widget bar + scrollable element settings)
---------------------------------------------------------------------------
local function BuildComposerContent(contentArea, contextMode)
    local gfdb = GetGFDB()
    if not gfdb then return end

    local proxyGFDB = CreateVisualProxy(gfdb, contextMode)

    local state = {
        selectedElement = nil, settingsPanels = {},
        childRefs = {}, hitOverlays = {}, widgetBarButtons = {},
    }

    -- Preview frame (rebuilt on settings change)
    local previewContainer = CreateFrame("Frame", nil, contentArea)
    previewContainer:SetPoint("TOPLEFT", 0, 0)
    previewContainer:SetPoint("RIGHT", contentArea, "RIGHT", 0, 0)
    previewContainer:SetHeight(1)

    -- Helper: show/hide highlights on overlays belonging to a tab key
    local function SetOverlayHighlights(tabKey, show)
        local overlay = state.hitOverlays[tabKey]
        if overlay then if show then overlay.highlight:Show() else overlay.highlight:Hide() end end
        for subKey, parentKey in pairs(SUB_ELEMENT_MAP) do
            if parentKey == tabKey then
                local subOverlay = state.hitOverlays[subKey]
                if subOverlay then if show then subOverlay.highlight:Show() else subOverlay.highlight:Hide() end end
            end
        end
    end

    local function RebuildPreviewImmediate()
        -- Clean up previous
        for _, overlay in pairs(state.hitOverlays) do overlay:Hide(); overlay:SetParent(nil) end
        wipe(state.hitOverlays)
        for _, child in pairs({previewContainer:GetChildren()}) do child:Hide(); child:SetParent(nil) end
        wipe(state.childRefs)

        local childRefs = state.childRefs
        local preview = CreateDesignerPreview(previewContainer, contextMode, childRefs)
        if not preview then return end
        previewContainer:SetHeight(preview:GetHeight())

        local frame = childRefs.frame
        if not frame then return end

        -- Create hit overlays on the preview
        local baseFLvl = frame:GetFrameLevel() + 10
        local subFLvl = baseFLvl + 2
        local elemFLvl = baseFLvl + 4
        local QUICore = ns.Addon

        local function MakeOverlay(key, anchorFrame, mode, fLvl, w, h, aPoint, arPoint, oX, oY)
            local selectKey = CLICK_TARGET[key] or key
            local overlay = CreateHitOverlay(previewContainer, frame, key, anchorFrame, mode, w, h, aPoint, arPoint, oX, oY, fLvl)
            overlay:SetScript("OnEnter", function(self)
                self.highlight:Show()
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText(ELEMENT_LABELS[selectKey] or key)
                if DRAG_CONFIG[key] then GameTooltip:AddLine("Drag to reposition", 0.7, 0.7, 0.7) end
                GameTooltip:Show()
            end)
            overlay:SetScript("OnLeave", function(self)
                if state.selectedElement ~= selectKey then self.highlight:Hide() end
                GameTooltip:Hide()
            end)
            overlay:SetScript("OnClick", function(self)
                if self._dragFired then self._dragFired = false; return end
                if state.selectElement then state.selectElement(selectKey) end
            end)

            -- Drag support
            local dragCfg = DRAG_CONFIG[key]
            if dragCfg then
                overlay:RegisterForDrag("LeftButton")
                overlay:SetScript("OnDragStart", function(self)
                    self._dragFired = true
                    local gfdb2 = GetGFDB()
                    if not gfdb2 then return end
                    local proxy = CreateVisualProxy(gfdb2, contextMode)
                    local dbTbl = proxy[dragCfg.sub]
                    if not dbTbl then return end
                    if dragCfg.nested then dbTbl = dbTbl[dragCfg.nested] end
                    if not dbTbl then return end
                    GameTooltip:Hide()
                    self.highlight:Show()
                    local cx, cy = GetCursorPosition()
                    local scale = self:GetEffectiveScale()
                    self._dragStartCX = cx / scale
                    self._dragStartCY = cy / scale
                    self._dragStartValX = dbTbl[dragCfg.xKey] or 0
                    self._dragStartValY = dbTbl[dragCfg.yKey] or 0
                    self._dragDBTbl = dbTbl
                    for oKey, oFrame in pairs(state.hitOverlays) do
                        if oFrame ~= self then oFrame:EnableMouse(false) end
                    end
                    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                    ghost:SetFrameStrata("TOOLTIP")
                    local ow, oh = self:GetSize()
                    local sourcePx = QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(self) or 1
                    SetSizePx(ghost, math.max((ow or 0) / sourcePx, 8), math.max((oh or 0) / sourcePx, 8))
                    ApplyPixelBackdrop(ghost, 1, false)
                    ghost:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
                    local olCX, olCY = self:GetCenter()
                    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", olCX, olCY)
                    ghost:EnableMouse(false)
                    self._dragGhost = ghost
                    self._dragOlCX = olCX
                    self._dragOlCY = olCY
                end)
                overlay:SetScript("OnDragStop", function(self)
                    if self._dragGhost then self._dragGhost:Hide(); self._dragGhost:SetParent(nil); self._dragGhost = nil end
                    for _, oFrame in pairs(state.hitOverlays) do oFrame:EnableMouse(true) end
                    if not self._dragDBTbl then return end
                    local cx, cy = GetCursorPosition()
                    local scale = self:GetEffectiveScale()
                    local dx = (cx / scale - self._dragStartCX) / PREVIEW_SCALE
                    local dy = (cy / scale - self._dragStartCY) / PREVIEW_SCALE
                    self._dragDBTbl[dragCfg.xKey] = math.floor(self._dragStartValX + dx + 0.5)
                    self._dragDBTbl[dragCfg.yKey] = math.floor(self._dragStartValY + dy + 0.5)
                    self._dragDBTbl = nil
                    RebuildPreviewImmediate()
                    RefreshGF()
                    -- Rebuild settings panel to show updated slider values
                    if state.settingsPanels[selectKey] then
                        state.settingsPanels[selectKey]:Hide()
                        state.settingsPanels[selectKey]:SetParent(nil)
                        state.settingsPanels[selectKey] = nil
                    end
                    if state.selectElement then state.selectElement(selectKey) end
                end)
                overlay:SetScript("OnUpdate", function(self)
                    if not self._dragGhost then return end
                    local cx, cy = GetCursorPosition()
                    local scale = self:GetEffectiveScale()
                    self._dragGhost:ClearAllPoints()
                    self._dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self._dragOlCX + (cx / scale - self._dragStartCX), self._dragOlCY + (cy / scale - self._dragStartCY))
                end)
            end
            state.hitOverlays[key] = overlay
        end

        -- Create overlays for each element
        MakeOverlay("frame", frame, "fill", baseFLvl)
        if childRefs.healthBar then MakeOverlay("health", childRefs.healthBar, "fill", subFLvl) end
        if childRefs.powerBar then MakeOverlay("power", childRefs.powerBar, "fill", subFLvl) end
        if childRefs.nameText then
            MakeOverlay("name", childRefs.nameText, "fixed", elemFLvl, (childRefs.nameText:GetStringWidth() or 60) + 4, 20, "LEFT", "LEFT", -2, 0)
        end
        if childRefs.healthText then
            MakeOverlay("healthText", childRefs.healthText, "fixed", elemFLvl, (childRefs.healthText:GetStringWidth() or 40) + 4, 20, "RIGHT", "RIGHT", 2, 0)
        end
        if childRefs.buffContainer then MakeOverlay("buffs", childRefs.buffContainer, "fill", elemFLvl) end
        if childRefs.debuffContainer then MakeOverlay("debuffs", childRefs.debuffContainer, "fill", elemFLvl) end
        if childRefs.roleIcon then MakeOverlay("role", childRefs.roleIcon, "fill", elemFLvl) end

        -- Re-highlight selected element
        if state.selectedElement then SetOverlayHighlights(state.selectedElement, true) end
    end

    local rebuildTimer
    local function RebuildPreview()
        if rebuildTimer then return end
        rebuildTimer = C_Timer.After(0.05, function()
            rebuildTimer = nil
            RebuildPreviewImmediate()
        end)
    end

    RebuildPreviewImmediate()

    local function onChangeHandler()
        RefreshGF()
        RebuildPreview()
        local editMode = ns.QUI_GroupFrameEditMode
        if editMode and (editMode.IsTestMode and editMode:IsTestMode() or editMode.IsEditMode and editMode:IsEditMode()) then
            if editMode.RefreshTestMode then editMode:RefreshTestMode() end
        end
    end

    local y = -(previewContainer:GetHeight() + 8)

    -- Widget bar
    local function SelectElement(key)
        -- Deselect previous
        if state.selectedElement then
            local prevBtn = state.widgetBarButtons[state.selectedElement]
            if prevBtn then
                prevBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
                prevBtn:SetBackdropColor(0.12, 0.12, 0.12, 1)
            end
            SetOverlayHighlights(state.selectedElement, false)
        end
        -- Hide all panels
        for _, panel in pairs(state.settingsPanels) do panel:Hide() end
        state.selectedElement = key
        -- Highlight button
        if state.widgetBarButtons and state.widgetBarButtons[key] then
            state.widgetBarButtons[key]:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            state.widgetBarButtons[key]:SetBackdropColor(C.accent[1] * 0.2, C.accent[2] * 0.2, C.accent[3] * 0.2, 1)
        end
        -- Highlight overlays
        SetOverlayHighlights(key, true)
        -- Show or create panel
        local panel = state.settingsPanels[key]
        if not panel then
            local builder = ELEMENT_BUILDERS[key]
            if not builder then return end
            panel = CreateFrame("Frame", nil, state.settingsArea)
            panel:SetPoint("TOPLEFT", 0, 0)
            panel:SetPoint("RIGHT", state.settingsArea, "RIGHT", 0, 0)
            builder(panel, proxyGFDB, onChangeHandler)
            state.settingsPanels[key] = panel
        end
        panel:Show()
        -- Resize scroll area to match panel, and keep in sync when collapsibles toggle
        local function SyncScrollHeight()
            local h = panel:GetHeight()
            if h and h > 0 then state.settingsArea:SetHeight(h) end
            if state.refreshScrollBar then state.refreshScrollBar() end
        end
        if not panel._scrollSyncHooked then
            panel._scrollSyncHooked = true
            panel:HookScript("OnSizeChanged", SyncScrollHeight)
        end
        SyncScrollHeight()
    end

    state.selectElement = SelectElement
    local widgetBar, widgetBarHeight = CreateWidgetBar(contentArea, SelectElement, state)
    widgetBar:SetPoint("TOPLEFT", 0, y)
    y = y - widgetBarHeight - 8

    -- Scroll frame for settings
    local SCROLL_STEP = 40
    local scrollFrame = CreateFrame("ScrollFrame", nil, contentArea, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, y)
    scrollFrame:SetPoint("BOTTOMRIGHT", -18, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(contentArea:GetWidth() - 24)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    state.settingsArea = scrollChild

    -- Auto-resize scroll child width
    contentArea:HookScript("OnSizeChanged", function(self, w)
        if w and w > 0 then scrollChild:SetWidth(w - 24) end
    end)

    -- Style scrollbar to match QUI theme
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, -2)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 2)
        local thumb = scrollBar:GetThumbTexture()
        if thumb then thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8) end
        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end
    end

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local ok1, currentScroll = pcall(self.GetVerticalScroll, self)
        local ok2, maxScroll = pcall(self.GetVerticalScrollRange, self)
        if not ok1 or not ok2 then return end
        local newScroll = math.max(0, math.min((currentScroll or 0) - (delta * SCROLL_STEP), maxScroll or 0))
        pcall(self.SetVerticalScroll, self, newScroll)
    end)

    state.refreshScrollBar = function()
        if scrollBar and scrollBar.SetShown then
            local ok, maxScroll = pcall(scrollFrame.GetVerticalScrollRange, scrollFrame)
            scrollBar:SetShown(ok and maxScroll and maxScroll > 1)
        end
    end

    -- Pre-build all panels for search
    for _, key in ipairs(COMPOSER_ELEMENT_KEYS) do
        if not state.settingsPanels[key] then
            local builder = ELEMENT_BUILDERS[key]
            if builder then
                local panel = CreateFrame("Frame", nil, scrollChild)
                panel:SetPoint("TOPLEFT", 0, 0)
                panel:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
                builder(panel, proxyGFDB, onChangeHandler)
                panel:Hide()
                state.settingsPanels[key] = panel
            end
        end
    end

    -- Select first element
    SelectElement("health")
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_LayoutMode_Composer:Open(contextMode)
    GUI = QUI and QUI.GUI
    C = GUI and GUI.Colors or {}

    local frame = GetOrCreateFrame()

    -- Refresh border accent color
    if C.accent then
        frame:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    end

    -- Clear previous content
    local contentArea = frame._contentArea
    for _, child in pairs({contentArea:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    frame._contextMode = contextMode
    frame._titleText:SetText((contextMode == "raid" and "Raid" or "Party") .. " Composer")

    BuildComposerContent(contentArea, contextMode)
    frame:Show()
end

function QUI_LayoutMode_Composer:Close()
    if composerFrame then composerFrame:Hide() end
end


---------------------------------------------------------------------------
-- AUTO-CLOSE ON LAYOUT MODE EXIT
---------------------------------------------------------------------------
C_Timer.After(2, function()
    local um = ns.QUI_LayoutMode
    if um and um._exitCallbacks then
        um._exitCallbacks[#um._exitCallbacks + 1] = function()
            QUI_LayoutMode_Composer:Close()
        end
    end
end)
