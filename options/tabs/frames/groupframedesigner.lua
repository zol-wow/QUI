--[[
    QUI Group Frame Designer
    Interactive preview-based editor for group frame settings.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local QUICore = ns.Addon

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList
local GetFontList = Shared.GetFontList

-- Constants
local FORM_ROW = 32
local DROP_ROW = 52
local SLIDER_HEIGHT = 65
local PAD = 10
local PREVIEW_SCALE = 2
local UIKit = ns.UIKit

local function SetSizePx(frame, widthPixels, heightPixels)
    if UIKit and UIKit.SetSizePx then
        UIKit.SetSizePx(frame, widthPixels, heightPixels)
    elseif QUICore and QUICore.SetPixelPerfectSize then
        QUICore:SetPixelPerfectSize(frame, widthPixels, heightPixels)
    else
        frame:SetSize(widthPixels or 0, heightPixels or 0)
    end
end

local function SetHeightPx(frame, heightPixels)
    if UIKit and UIKit.SetHeightPx then
        UIKit.SetHeightPx(frame, heightPixels)
    elseif QUICore and QUICore.SetPixelPerfectHeight then
        QUICore:SetPixelPerfectHeight(frame, heightPixels)
    else
        frame:SetHeight(heightPixels or 0)
    end
end

local function SetPointPx(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    if UIKit and UIKit.SetPointPx then
        UIKit.SetPointPx(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    elseif QUICore and QUICore.SetPixelPerfectPoint then
        QUICore:SetPixelPerfectPoint(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    else
        frame:SetPoint(point, relativeTo, relativePoint, xPixels or 0, yPixels or 0)
    end
end

local function RoundVirtual(value, frame)
    if QUICore and QUICore.PixelRound then
        return QUICore:PixelRound(value or 0, frame)
    end
    return value or 0
end

local function SetSnappedPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
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
        borderPixels = 1,
        withBackground = false,
        bgColor = { 0, 0, 0, 1 },
        borderColor = { 1, 1, 1, 1 },
        originalSetBackdropColor = frame.SetBackdropColor,
        originalSetBackdropBorderColor = frame.SetBackdropBorderColor,
    }

    if uikit and uikit.CreateBackground then
        state.bg = uikit.CreateBackground(frame, 0, 0, 0, 0)
        if state.bg and state.bg.Hide then
            state.bg:Hide()
        end
    end

    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end

    if uikit and uikit.CreateBorderLines and uikit.UpdateBorderLines then
        uikit.CreateBorderLines(frame)
    end

    frame.SetBackdropColor = function(self, r, g, b, a)
        local compat = self and self._quiPixelBackdropCompat
        if not compat then return end
        compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4] = r or 0, g or 0, b or 0, a or 1

        if compat.bg and compat.bg.SetVertexColor then
            compat.bg:SetVertexColor(compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
            if compat.withBackground then
                compat.bg:Show()
            else
                compat.bg:Hide()
            end
        elseif compat.originalSetBackdropColor then
            pcall(compat.originalSetBackdropColor, self, compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
        end
    end

    frame.SetBackdropBorderColor = function(self, r, g, b, a)
        local compat = self and self._quiPixelBackdropCompat
        if not compat then return end
        compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4] = r or 0, g or 0, b or 0, a or 1

        if uikit and uikit.UpdateBorderLines then
            uikit.UpdateBorderLines(self, compat.borderPixels or 1, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4], false)
        elseif compat.originalSetBackdropBorderColor then
            pcall(compat.originalSetBackdropBorderColor, self, compat.borderColor[1], compat.borderColor[2], compat.borderColor[3], compat.borderColor[4])
        end
    end

    if uikit and uikit.RegisterScaleRefresh then
        uikit.RegisterScaleRefresh(frame, "groupFrameDesignerBackdropCompat", function(owner)
            local compat = owner and owner._quiPixelBackdropCompat
            if not compat then return end
            if compat.bg and compat.bg.SetVertexColor then
                compat.bg:SetVertexColor(compat.bgColor[1], compat.bgColor[2], compat.bgColor[3], compat.bgColor[4])
                if compat.withBackground then
                    compat.bg:Show()
                else
                    compat.bg:Hide()
                end
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
-- HELPERS
---------------------------------------------------------------------------
local function GetGFDB()
    local db = GetDB()
    return db and db.quiGroupFrames
end

local function RefreshGF()
    if _G.QUI_RefreshGroupFrames then
        _G.QUI_RefreshGroupFrames()
    end
end

local function FindNearestScrollFrame(frame)
    local current = frame
    while current do
        if current.GetVerticalScroll and current.SetVerticalScroll then
            return current
        end
        current = current:GetParent()
    end
    return nil
end

---------------------------------------------------------------------------
-- DYNAMIC LAYOUT HELPER
-- Collects rows and lays them out vertically, collapsing hidden rows.
-- condFn: optional function returning true/false for conditional visibility.
-- isHeader: true for section headers (no RIGHT anchor).
-- Toggles (widgets with .track) that don't have a condFn are auto-hooked
-- to trigger relayout on click.
---------------------------------------------------------------------------
local function CreateDynamicLayout(content)
    local rows = {}
    local L = {}

    function L:Row(widget, height, condFn, isHeader)
        rows[#rows + 1] = { widget = widget, height = height, condFn = condFn, isHeader = isHeader }
        if not isHeader then
            widget:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        end
    end

    function L:Header(widget)
        self:Row(widget, widget.gap, nil, true)
    end

    function L:Finish()
        local function Relayout()
            local ly = -10
            for _, row in ipairs(rows) do
                local visible = true
                if row.condFn then visible = row.condFn() end
                if visible then
                    row.widget:ClearAllPoints()
                    row.widget:SetPoint("TOPLEFT", PAD, ly)
                    if not row.isHeader then
                        row.widget:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
                    end
                    row.widget:Show()
                    ly = ly - row.height
                else
                    row.widget:Hide()
                end
            end
            content:SetHeight(math.abs(ly) + 10)
        end

        -- Auto-hook toggles (widgets with .track and no condFn) to relayout
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
-- ELEMENT DEFINITIONS
---------------------------------------------------------------------------
-- Visual elements shown on Party/Raid designer sub-tabs (preview + widget bar)
-- Visual elements shown in Party/Raid Composer (preview + widget bar)
local COMPOSER_ELEMENT_KEYS = {
    "health", "power", "name",
    "buffs", "debuffs", "indicators",
    "healer", "defensive", "auraIndicators", "privateAuras",
}

-- General sub-tab elements (shared, not per-context)
local GENERAL_ELEMENT_KEYS = {
    "general", "clickCast",
}

-- Legacy alias used by search pre-build and overlay click routing
local VISUAL_ELEMENT_KEYS = COMPOSER_ELEMENT_KEYS

local ELEMENT_LABELS = {
    frame = "Frame",
    health = "Health",
    power = "Power",
    name = "Name",
    buffs = "Buffs",
    debuffs = "Debuffs",
    indicators = "Indicators",
    healer = "Healer",
    defensive = "Defensive",
    auraIndicators = "Aura Ind.",
    privateAuras = "Priv. Auras",
    general = "General",
    layout = "Layout",
    dimensions = "Dimensions",
    clickCast = "Click-Cast",
}

-- Keys that live under party/raid sub-tables in the DB
local VISUAL_DB_KEYS = {
    general = true, layout = true, health = true, power = true, name = true,
    absorbs = true, healPrediction = true, indicators = true,
    healer = true, classPower = true, range = true, auras = true,
    privateAuras = true, auraIndicators = true, castbar = true,
    portrait = true, pets = true, dimensions = true, spotlight = true,
}

-- Creates a proxy table that routes visual keys to the party or raid sub-table.
-- Shared keys (position, enabled, etc.) pass through to the real gfdb table.
local function CreateVisualProxy(gfdb, mode)
    local ctx = mode == "raid" and gfdb.raid or gfdb.party
    if not ctx then return gfdb end
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if VISUAL_DB_KEYS[key] then
                return ctx[key]
            end
            return gfdb[key]
        end,
        __newindex = function(_, key, value)
            if VISUAL_DB_KEYS[key] then
                ctx[key] = value
            else
                gfdb[key] = value
            end
        end,
    })
    rawset(proxy, "_composerMode", mode)
    return proxy
end

local SEARCH_TAB_INDEX = 6
local SEARCH_TAB_NAME = "Group Frames"
local SEARCH_SUBTAB_GENERAL_INDEX = 1
local SEARCH_SUBTAB_GENERAL_NAME = "General"
local SEARCH_SUBTAB_PARTY_INDEX = 2
local SEARCH_SUBTAB_PARTY_NAME = "Party"
local SEARCH_SUBTAB_RAID_INDEX = 3
local SEARCH_SUBTAB_RAID_NAME = "Raid"

local function SetGeneralSearchContext(sectionName)
    GUI:SetSearchContext({
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_GENERAL_INDEX,
        subTabName = SEARCH_SUBTAB_GENERAL_NAME,
        sectionName = sectionName,
    })
end

local function SetPartySearchContext(sectionName)
    GUI:SetSearchContext({
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_PARTY_INDEX,
        subTabName = SEARCH_SUBTAB_PARTY_NAME,
        sectionName = sectionName,
    })
end

local function SetRaidSearchContext(sectionName)
    GUI:SetSearchContext({
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_RAID_INDEX,
        subTabName = SEARCH_SUBTAB_RAID_NAME,
        sectionName = sectionName,
    })
end

local function SetComposerSearchContext(sectionName)
    GUI:SetSearchContext({
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_PARTY_INDEX,
        subTabName = SEARCH_SUBTAB_PARTY_NAME,
        sectionName = sectionName,
    })
end

---------------------------------------------------------------------------
-- ANCHOR MAP for text placement in preview
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
-- DROPDOWN OPTIONS for settings panels
---------------------------------------------------------------------------
local AURA_GROW_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
    { value = "UP", text = "Up" },
    { value = "DOWN", text = "Down" },
}

local HEALTH_DISPLAY_OPTIONS = {
    { value = "percent", text = "Percentage" },
    { value = "absolute", text = "Absolute" },
    { value = "both", text = "Both" },
    { value = "deficit", text = "Deficit" },
}

local HEALTH_FILL_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal (Left to Right)" },
    { value = "VERTICAL", text = "Vertical (Bottom to Top)" },
}

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

local FIVE_POINT_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
    { value = "TOP", text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
}

local TEXT_JUSTIFY_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
}

local FILTER_MODE_OPTIONS = {
    { value = "off", text = "Off (Show All)" },
    { value = "classification", text = "Classification" },
}

---------------------------------------------------------------------------
-- AURA FILTER PRESETS: Common healer/support spell IDs per spec
-- Spells on Blizzard's Midnight whitelist — spellId readable in combat
---------------------------------------------------------------------------
local AURA_FILTER_PRESETS = {
    {
        name = "Restoration Druid",
        specID = 105,
        spells = {
            { id = 774,    name = "Rejuvenation" },
            { id = 8936,   name = "Regrowth" },
            { id = 33763,  name = "Lifebloom" },
            { id = 155777, name = "Germination" },
            { id = 48438,  name = "Wild Growth" },
            { id = 102342, name = "Ironbark" },
            { id = 33786,  name = "Cyclone" },
        },
    },
    {
        name = "Restoration Shaman",
        specID = 264,
        spells = {
            { id = 61295,  name = "Riptide" },
            { id = 974,    name = "Earth Shield" },
            { id = 383648, name = "Earth Shield (Ele)" },
            { id = 98008,  name = "Spirit Link Totem" },
            { id = 108271, name = "Astral Shift" },
        },
    },
    {
        name = "Holy Paladin",
        specID = 65,
        spells = {
            { id = 53563,  name = "Beacon of Light" },
            { id = 156910, name = "Beacon of Faith" },
            { id = 200025, name = "Beacon of Virtue" },
            { id = 156322, name = "Eternal Flame" },
            { id = 223306, name = "Bestow Faith" },
            { id = 1022,   name = "Blessing of Protection" },
            { id = 6940,   name = "Blessing of Sacrifice" },
            { id = 1044,   name = "Blessing of Freedom" },
        },
    },
    {
        name = "Discipline Priest",
        specID = 256,
        spells = {
            { id = 194384, name = "Atonement" },
            { id = 17,     name = "Power Word: Shield" },
            { id = 41635,  name = "Prayer of Mending" },
            { id = 47788,  name = "Guardian Spirit" },
            { id = 33206,  name = "Pain Suppression" },
        },
    },
    {
        name = "Holy Priest",
        specID = 257,
        spells = {
            { id = 139,    name = "Renew" },
            { id = 77489,  name = "Echo of Light" },
            { id = 41635,  name = "Prayer of Mending" },
            { id = 47788,  name = "Guardian Spirit" },
            { id = 64844,  name = "Divine Hymn" },
        },
    },
    {
        name = "Mistweaver Monk",
        specID = 270,
        spells = {
            { id = 119611, name = "Renewing Mist" },
            { id = 124682, name = "Enveloping Mist" },
            { id = 115175, name = "Soothing Mist" },
            { id = 191840, name = "Essence Font" },
            { id = 116849, name = "Life Cocoon" },
        },
    },
    {
        name = "Preservation Evoker",
        specID = 1468,
        spells = {
            { id = 364343, name = "Echo" },
            { id = 366155, name = "Reversion" },
            { id = 367364, name = "Echo Reversion" },
            { id = 355941, name = "Dream Breath" },
            { id = 376788, name = "Echo Dream Breath" },
            { id = 363502, name = "Dream Flight" },
            { id = 373267, name = "Lifebind" },
        },
    },
    {
        name = "Augmentation Evoker",
        specID = 1473,
        spells = {
            { id = 410089, name = "Prescience" },
            { id = 395152, name = "Ebon Might" },
            { id = 360827, name = "Blistering Scales" },
            { id = 413984, name = "Shifting Sands" },
            { id = 410263, name = "Inferno's Blessing" },
            { id = 410686, name = "Symbiotic Bloom" },
            { id = 369459, name = "Source of Magic" },
        },
    },
    {
        name = "Common Defensives",
        spells = {
            { id = 31821,  name = "Aura Mastery" },
            { id = 97463,  name = "Rallying Cry" },
            { id = 15286,  name = "Vampiric Embrace" },
            { id = 64843,  name = "Divine Hymn" },
            { id = 51052,  name = "Anti-Magic Zone" },
            { id = 196718, name = "Darkness" },
        },
    },
}

-- Map specID → preset for auto-detection
local SPEC_TO_PRESET = {}
for _, preset in ipairs(AURA_FILTER_PRESETS) do
    if preset.specID then
        SPEC_TO_PRESET[preset.specID] = preset
    end
end

-- Find the "Common Defensives" preset (no specID)
local COMMON_DEFENSIVES_PRESET
for _, preset in ipairs(AURA_FILTER_PRESETS) do
    if not preset.specID then
        COMMON_DEFENSIVES_PRESET = preset
        break
    end
end

---------------------------------------------------------------------------
-- BLACKLIST PRESETS: Curated spell lists for buff/debuff blacklisting
---------------------------------------------------------------------------
local BUFF_BLACKLIST_PRESETS = {
    {
        name = "Raid Buffs",
        spells = {
            { id = 1459,   name = "Arcane Intellect" },
            { id = 6673,   name = "Battle Shout" },
            { id = 21562,  name = "Power Word: Fortitude" },
            { id = 1126,   name = "Mark of the Wild" },
            { id = 381753, name = "Skyfury" },
            { id = 381748, name = "Blessing of the Bronze" },
            { id = 369459, name = "Source of Magic" },
        },
    },
}

local DEBUFF_BLACKLIST_PRESETS = {
    {
        name = "Sated / Exhaustion",
        spells = {
            { id = 57723,  name = "Exhaustion" },
            { id = 57724,  name = "Sated" },
            { id = 80354,  name = "Temporal Displacement" },
            { id = 95809,  name = "Insanity" },
            { id = 160455, name = "Fatigued" },
            { id = 264689, name = "Fatigued" },
            { id = 390435, name = "Exhaustion" },
        },
    },
    {
        name = "Deserter",
        spells = {
            { id = 26013,  name = "Deserter" },
            { id = 71041,  name = "Dungeon Deserter" },
        },
    },
}

-- Get current player specID
local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local specID = GetSpecializationInfo(specIndex)
        return specID
    end
    return nil
end

---------------------------------------------------------------------------
-- FAKE DATA for preview
---------------------------------------------------------------------------
local FAKE_BUFF_ICONS = { 136034, 135940, 136081, 135932, 136063, 135987, 136070, 135864 }
local FAKE_DEBUFF_ICONS = { 136207, 136130, 135813, 136118, 135959, 136066, 136133, 135835 }
local FAKE_CLASS = "PALADIN"
local FAKE_NAME = "Healena"
local FAKE_HP_PCT = 65

---------------------------------------------------------------------------
-- PREVIEW FRAME BUILDER
---------------------------------------------------------------------------
local function CreateDesignerPreview(container, previewType, childRefs)
    local gfdb = GetGFDB()
    if not gfdb then return nil end

    local db = CreateVisualProxy(gfdb, previewType)
    local general = db.general or {}
    local dims = db.dimensions or {}

    -- Determine base dimensions from preview type
    local baseW, baseH
    if previewType == "raid" then
        baseW = dims.mediumRaidWidth or 160
        baseH = dims.mediumRaidHeight or 30
    else
        baseW = dims.partyWidth or 200
        baseH = dims.partyHeight or 40
    end

    local w, h = baseW * PREVIEW_SCALE, baseH * PREVIEW_SCALE
    local fontPath = GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF"
    local fontOutline = general.fontOutline or "OUTLINE"
    local classToken = FAKE_CLASS
    local healthPct = FAKE_HP_PCT

    -- Outer wrapper to center the preview
    local wrapper = CreateFrame("Frame", nil, container)
    wrapper:SetHeight(h + 20)
    wrapper:SetPoint("TOPLEFT", 0, 0)
    wrapper:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    -- Main preview frame
    local frame = CreateFrame("Frame", nil, wrapper, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetPoint("CENTER", wrapper, "CENTER", 0, 0)

    local borderPixels = general.borderSize or 1
    ApplyPixelBackdrop(frame, borderPixels, true)
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    local borderSize = borderPixels * px

    -- Background color
    local bgR, bgG, bgB, bgA = 0.08, 0.08, 0.08, 0.9
    if general.darkMode and general.darkModeBgColor then
        local c = general.darkModeBgColor
        bgR, bgG, bgB = c[1] or c.r or bgR, c[2] or c.g or bgG, c[3] or c.b or bgB
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

    local LSM = LibStub("LibSharedMedia-3.0", true)
    local textureName = general.texture or "Quazii v5"
    local texturePath = LSM and LSM:Fetch("statusbar", textureName) or "Interface\\TargetingFrame\\UI-StatusBar"
    healthBar:SetStatusBarTexture(texturePath)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(healthPct)
    local previewHealth = db.health or {}
    if previewHealth.healthFillDirection == "VERTICAL" then
        healthBar:SetOrientation("VERTICAL")
    end

    -- Health bar color
    if general.darkMode then
        local dmc = general.darkModeHealthColor
        if dmc then
            healthBar:SetStatusBarColor(dmc[1] or dmc.r or 0.2, dmc[2] or dmc.g or 0.2, dmc[3] or dmc.b or 0.2, general.darkModeHealthOpacity or 1)
        else
            healthBar:SetStatusBarColor(0.2, 0.2, 0.2, 1)
        end
    elseif general.useClassColor then
        local cc = RAID_CLASS_COLORS[classToken]
        if cc then
            healthBar:SetStatusBarColor(cc.r, cc.g, cc.b, general.defaultHealthOpacity or 1)
        end
    else
        healthBar:SetStatusBarColor(0.2, 0.8, 0.2, general.defaultHealthOpacity or 1)
    end
    childRefs.healthBar = healthBar

    -- Power bar
    local powerDB = db.power or {}
    if powerDB.showPowerBar ~= false then
        local powerH = (powerDB.powerBarHeight or 4) * PREVIEW_SCALE
        local powerBar = CreateFrame("StatusBar", nil, frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerH)
        powerBar:SetStatusBarTexture(texturePath)
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(80)
        if powerDB.powerBarUsePowerColor then
            powerBar:SetStatusBarColor(0.2, 0.4, 0.8, 1)
        else
            local c = powerDB.powerBarColor or {0.2, 0.4, 0.8, 1}
            powerBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        end
        childRefs.powerBar = powerBar

        -- Adjust health bar bottom to sit above power bar
        healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerH)
    else
        childRefs.powerBar = nil
    end

    -- Bottom-anchor offset: push elements above power bar in preview
    local powerH = (powerDB.showPowerBar ~= false) and ((powerDB.powerBarHeight or 4) * PREVIEW_SCALE) or 0
    local previewBottomPad = powerH + borderSize
    local function PreviewBottomPadY(anchor, offY)
        if anchor:find("BOTTOM") then return offY + previewBottomPad end
        return offY
    end

    -- Text frame (above health bar for overlaid text)
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
        local nameJustify = nameDB.nameJustify or nameAnchorInfo.justify
        nameText:SetJustifyH(nameJustify)
        nameText:SetJustifyV(nameAnchorInfo.justifyV)
        nameText:SetWordWrap(false)

        local displayName = FAKE_NAME
        local maxLen = nameDB.maxNameLength or 10
        if maxLen > 0 and #displayName > maxLen then
            displayName = displayName:sub(1, maxLen)
        end
        nameText:SetText(displayName)

        if nameDB.nameTextUseClassColor then
            local cc = RAID_CLASS_COLORS[classToken]
            if cc then
                nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
            else
                nameText:SetTextColor(1, 1, 1, 1)
            end
        elseif nameDB.nameTextColor then
            local tc = nameDB.nameTextColor
            nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        else
            nameText:SetTextColor(1, 1, 1, 1)
        end
        childRefs.nameText = nameText
    else
        childRefs.nameText = nil
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
        local healthJustify = healthDB.healthJustify or healthAnchorInfo.justify
        healthText:SetJustifyH(healthJustify)
        healthText:SetJustifyV(healthAnchorInfo.justifyV)
        healthText:SetWordWrap(false)

        local style = healthDB.healthDisplayStyle or "percent"
        local fakeHP = healthPct * 1000
        if style == "percent" then
            healthText:SetText(healthPct .. "%")
        elseif style == "absolute" then
            healthText:SetText(string.format("%.0fK", fakeHP / 1000))
        elseif style == "both" then
            healthText:SetText(string.format("%.0fK", fakeHP / 1000) .. " | " .. healthPct .. "%")
        elseif style == "deficit" then
            local deficit = 100000 - fakeHP
            if deficit > 0 then
                healthText:SetText("-" .. string.format("%.0fK", deficit / 1000))
            else
                healthText:SetText("")
            end
        else
            healthText:SetText(healthPct .. "%")
        end

        if healthDB.healthTextColor then
            local tc = healthDB.healthTextColor
            healthText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        else
            healthText:SetTextColor(1, 1, 1, 1)
        end
        childRefs.healthText = healthText
    else
        childRefs.healthText = nil
    end

    -- Role icon
    local indDB = db.indicators or {}
    local roleAnchor = indDB.roleIconAnchor or "TOPLEFT"
    local roleOffX = (indDB.roleIconOffsetX or 2) * PREVIEW_SCALE
    local roleOffY = (indDB.roleIconOffsetY or -2) * PREVIEW_SCALE
    if indDB.showRoleIcon ~= false then
        local roleSize = (indDB.roleIconSize or 12) * PREVIEW_SCALE
        local roleIcon = textFrame:CreateTexture(nil, "OVERLAY")
        roleIcon:SetSize(roleSize, roleSize)
        roleIcon:SetPoint(roleAnchor, textFrame, roleAnchor, roleOffX, roleOffY)
        roleIcon:SetAtlas("roleicon-tiny-healer")
        childRefs.roleIcon = roleIcon
    else
        childRefs.roleIcon = nil
    end

    -- Indicator icons (ready check, rez, summon, leader, target marker, phase)
    local iconScale = PREVIEW_SCALE
    local indicatorFrame = CreateFrame("Frame", nil, frame)
    indicatorFrame:SetAllPoints()
    indicatorFrame:SetFrameLevel(frame:GetFrameLevel() + 8)

    -- Helper to position a designer indicator from DB
    local function IndicatorPoint(tex, anchorKey, offXKey, offYKey, defAnchor, defX, defY)
        local a = indDB[anchorKey] or defAnchor
        local ox = (indDB[offXKey] or defX) * PREVIEW_SCALE
        local oy = (indDB[offYKey] or defY) * PREVIEW_SCALE
        tex:SetPoint(a, frame, a, ox, PreviewBottomPadY(a, oy))
    end

    -- Ready check
    local readyCheckIcon = indicatorFrame:CreateTexture(nil, "OVERLAY")
    readyCheckIcon:SetSize(16 * iconScale, 16 * iconScale)
    IndicatorPoint(readyCheckIcon, "readyCheckAnchor", "readyCheckOffsetX", "readyCheckOffsetY", "CENTER", 0, 0)
    readyCheckIcon:SetTexture("INTERFACE\\RAIDFRAME\\ReadyCheck-Ready")
    if indDB.showReadyCheck == false then readyCheckIcon:Hide() end
    childRefs.readyCheckIcon = readyCheckIcon

    -- Resurrection icon
    local resIcon = indicatorFrame:CreateTexture(nil, "OVERLAY")
    resIcon:SetSize(16 * iconScale, 16 * iconScale)
    IndicatorPoint(resIcon, "resurrectionAnchor", "resurrectionOffsetX", "resurrectionOffsetY", "CENTER", 0, 0)
    resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    if indDB.showResurrection == false then resIcon:Hide() end
    childRefs.resIcon = resIcon

    -- Summon pending icon
    local summonIcon = indicatorFrame:CreateTexture(nil, "OVERLAY")
    summonIcon:SetSize(16 * iconScale, 16 * iconScale)
    IndicatorPoint(summonIcon, "summonAnchor", "summonOffsetX", "summonOffsetY", "CENTER", 16, 0)
    summonIcon:SetAtlas("RaidFrame-Icon-SummonPending")
    if indDB.showSummonPending == false then summonIcon:Hide() end
    childRefs.summonIcon = summonIcon

    -- Leader icon
    local leaderIcon = indicatorFrame:CreateTexture(nil, "OVERLAY")
    leaderIcon:SetSize(12 * iconScale, 12 * iconScale)
    IndicatorPoint(leaderIcon, "leaderAnchor", "leaderOffsetX", "leaderOffsetY", "TOP", 0, 6)
    leaderIcon:SetAtlas("groupfinder-icon-leader")
    if indDB.showLeaderIcon == false then leaderIcon:Hide() end
    childRefs.leaderIcon = leaderIcon

    -- Target marker
    local targetMarker = indicatorFrame:CreateTexture(nil, "OVERLAY")
    targetMarker:SetSize(14 * iconScale, 14 * iconScale)
    IndicatorPoint(targetMarker, "targetMarkerAnchor", "targetMarkerOffsetX", "targetMarkerOffsetY", "TOPRIGHT", -2, -2)
    targetMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    SetRaidTargetIconTexture(targetMarker, 1)
    if indDB.showTargetMarker == false then targetMarker:Hide() end
    childRefs.targetMarker = targetMarker

    -- Phase icon
    local phaseIcon = indicatorFrame:CreateTexture(nil, "OVERLAY")
    phaseIcon:SetSize(16 * iconScale, 16 * iconScale)
    IndicatorPoint(phaseIcon, "phaseAnchor", "phaseOffsetX", "phaseOffsetY", "BOTTOMLEFT", 2, 2)
    phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
    if indDB.showPhaseIcon == false then phaseIcon:Hide() end
    childRefs.phaseIcon = phaseIcon

    childRefs.indicatorFrame = indicatorFrame

    -- Buff icons
    local auraDB = db.auras or {}
    if auraDB.showBuffs then
        local buffSize = (auraDB.buffIconSize or 14) * PREVIEW_SCALE
        local buffAnchor = auraDB.buffAnchor or "TOPLEFT"
        local buffGrow = auraDB.buffGrowDirection or "RIGHT"
        local buffSpacing = (auraDB.buffSpacing or 2) * PREVIEW_SCALE
        local maxBuffs = auraDB.maxBuffs or 3

        local buffContainer = CreateFrame("Frame", nil, frame)
        buffContainer:SetFrameLevel(frame:GetFrameLevel() + 8)
        local buffCount = math.min(maxBuffs, #FAKE_BUFF_ICONS)
        local buffContainerW = buffCount * buffSize + math.max(buffCount - 1, 0) * buffSpacing
        buffContainer:SetSize(math.max(buffContainerW, 1), buffSize)
        local offX = (auraDB.buffOffsetX or 2) * PREVIEW_SCALE
        local offY = (auraDB.buffOffsetY or 16) * PREVIEW_SCALE
        buffContainer:SetPoint(buffAnchor, frame, buffAnchor, offX, PreviewBottomPadY(buffAnchor, offY))

        for i = 1, math.min(maxBuffs, #FAKE_BUFF_ICONS) do
            local icon = buffContainer:CreateTexture(nil, "OVERLAY")
            icon:SetSize(buffSize, buffSize)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(FAKE_BUFF_ICONS[i])
            if i == 1 then
                icon:SetPoint("LEFT", buffContainer, "LEFT", 0, 0)
            else
                local growDir = buffGrow == "LEFT" and "RIGHT" or "LEFT"
                local prevIcon = buffContainer["icon" .. (i - 1)]
                if prevIcon then
                    icon:SetPoint(growDir, prevIcon, buffGrow == "LEFT" and "LEFT" or "RIGHT", buffGrow == "LEFT" and -buffSpacing or buffSpacing, 0)
                else
                    icon:SetPoint("LEFT", buffContainer, "LEFT", (i - 1) * (buffSize + buffSpacing), 0)
                end
            end
            buffContainer["icon" .. i] = icon
        end
        childRefs.buffContainer = buffContainer
    else
        childRefs.buffContainer = nil
    end

    -- Debuff icons
    if auraDB.showDebuffs ~= false then
        local debuffSize = (auraDB.debuffIconSize or 16) * PREVIEW_SCALE
        local debuffAnchor = auraDB.debuffAnchor or "BOTTOMRIGHT"
        local debuffGrow = auraDB.debuffGrowDirection or "LEFT"
        local debuffSpacing = (auraDB.debuffSpacing or 2) * PREVIEW_SCALE
        local maxDebuffs = auraDB.maxDebuffs or 3

        local debuffContainer = CreateFrame("Frame", nil, frame)
        debuffContainer:SetFrameLevel(frame:GetFrameLevel() + 8)
        local debuffCount = math.min(maxDebuffs, #FAKE_DEBUFF_ICONS)
        local debuffContainerW = debuffCount * debuffSize + math.max(debuffCount - 1, 0) * debuffSpacing
        debuffContainer:SetSize(math.max(debuffContainerW, 1), debuffSize)
        local offX = (auraDB.debuffOffsetX or -2) * PREVIEW_SCALE
        local offY = (auraDB.debuffOffsetY or -18) * PREVIEW_SCALE
        debuffContainer:SetPoint(debuffAnchor, frame, debuffAnchor, offX, PreviewBottomPadY(debuffAnchor, offY))

        for i = 1, math.min(maxDebuffs, #FAKE_DEBUFF_ICONS) do
            local icon = debuffContainer:CreateTexture(nil, "OVERLAY")
            icon:SetSize(debuffSize, debuffSize)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(FAKE_DEBUFF_ICONS[i])
            if i == 1 then
                local startAnchor = debuffGrow == "LEFT" and "RIGHT" or "LEFT"
                icon:SetPoint(startAnchor, debuffContainer, startAnchor, 0, 0)
            else
                local prevIcon = debuffContainer["icon" .. (i - 1)]
                if prevIcon then
                    if debuffGrow == "LEFT" then
                        icon:SetPoint("RIGHT", prevIcon, "LEFT", -debuffSpacing, 0)
                    else
                        icon:SetPoint("LEFT", prevIcon, "RIGHT", debuffSpacing, 0)
                    end
                else
                    local startAnchor = debuffGrow == "LEFT" and "RIGHT" or "LEFT"
                    icon:SetPoint(startAnchor, debuffContainer, startAnchor, (i - 1) * (debuffSize + debuffSpacing) * (debuffGrow == "LEFT" and -1 or 1), 0)
                end
            end
            debuffContainer["icon" .. i] = icon
        end
        childRefs.debuffContainer = debuffContainer
    else
        childRefs.debuffContainer = nil
    end

    -- Absorb + Heal prediction overlays (adjacent at the health fill edge)
    local absorbDB = db.absorbs or {}
    local healDB = db.healPrediction or {}
    local healthDB = db.health or {}
    local isVerticalPreview = (healthDB.healthFillDirection == "VERTICAL")

    local fillRight = w * (healthPct / 100)
    local fillTop = h * (healthPct / 100)  -- vertical: fill from bottom up
    local absorbW = w * 0.12
    local absorbH = h * 0.12
    local healW = w * 0.08
    local healH = h * 0.08

    -- Resolve class color for absorb/heal prediction
    local previewCC = RAID_CLASS_COLORS[classToken]
    local ccR, ccG, ccB = previewCC and previewCC.r or 1, previewCC and previewCC.g or 1, previewCC and previewCC.b or 1

    if absorbDB.enabled ~= false then
        local ac
        if absorbDB.useClassColor then
            ac = { ccR, ccG, ccB, 1 }
        else
            ac = absorbDB.color or {1, 1, 1, 1}
        end
        local aa = absorbDB.opacity or 0.3
        local absorbOverlay = healthBar:CreateTexture(nil, "OVERLAY", nil, 1)
        absorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Fill")
        absorbOverlay:SetVertexColor(ac[1], ac[2], ac[3], aa)
        if isVerticalPreview then
            absorbOverlay:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, fillTop)
            absorbOverlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, fillTop)
            absorbOverlay:SetHeight(absorbH)
        else
            absorbOverlay:SetPoint("TOPLEFT", healthBar, "TOPLEFT", fillRight, 0)
            absorbOverlay:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", fillRight, 0)
            absorbOverlay:SetWidth(absorbW)
        end
        childRefs.absorbOverlay = absorbOverlay
    else
        childRefs.absorbOverlay = nil
    end

    if healDB.enabled ~= false then
        local hc
        if healDB.useClassColor then
            hc = { ccR, ccG, ccB, 1 }
        else
            hc = healDB.color or {0.2, 1, 0.2}
        end
        local ha = healDB.opacity or 0.5
        local healOverlay = healthBar:CreateTexture(nil, "OVERLAY", nil, 1)
        healOverlay:SetTexture(texturePath)
        healOverlay:SetVertexColor(hc[1], hc[2], hc[3], ha)
        if isVerticalPreview then
            local healStart = fillTop + (absorbDB.enabled ~= false and absorbH or 0)
            healOverlay:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, healStart)
            healOverlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, healStart)
            healOverlay:SetHeight(healH)
        else
            local healStart = fillRight + (absorbDB.enabled ~= false and absorbW or 0)
            healOverlay:SetPoint("TOPLEFT", healthBar, "TOPLEFT", healStart, 0)
            healOverlay:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", healStart, 0)
            healOverlay:SetWidth(healW)
        end
        childRefs.healOverlay = healOverlay
    else
        childRefs.healOverlay = nil
    end

    -- Healer features preview
    local healerDB = db.healer or {}

    -- Dispel overlay (colored border indicating a dispellable debuff)
    -- Only visible in preview when healer tab is selected
    local dispelDB = healerDB.dispelOverlay or {}
    local dispelBorderPx = (dispelDB.borderSize or 3) * PREVIEW_SCALE
    local dispelFrame = CreateFrame("Frame", nil, frame)
    dispelFrame:SetAllPoints(frame)
    dispelFrame:SetFrameLevel(frame:GetFrameLevel() + 9)

    -- Use Magic color as the sample preview color
    local dispelColors = dispelDB.colors or {}
    local dc = dispelColors.Magic or { 0.2, 0.6, 1.0, 1 }
    local dOpacity = dispelDB.opacity or 0.8

    -- 4-edge border bars (matches runtime pattern)
    local function MakePreviewDispelBorder(parent)
        local bar = parent:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(dc[1], dc[2], dc[3], dOpacity)
        return bar
    end
    local bTop = MakePreviewDispelBorder(dispelFrame)
    bTop:SetPoint("TOPLEFT", dispelFrame, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", dispelFrame, "TOPRIGHT", 0, 0)
    bTop:SetHeight(dispelBorderPx)
    local bBottom = MakePreviewDispelBorder(dispelFrame)
    bBottom:SetPoint("BOTTOMLEFT", dispelFrame, "BOTTOMLEFT", 0, 0)
    bBottom:SetPoint("BOTTOMRIGHT", dispelFrame, "BOTTOMRIGHT", 0, 0)
    bBottom:SetHeight(dispelBorderPx)
    local bLeft = MakePreviewDispelBorder(dispelFrame)
    bLeft:SetPoint("TOPLEFT", dispelFrame, "TOPLEFT", 0, 0)
    bLeft:SetPoint("BOTTOMLEFT", dispelFrame, "BOTTOMLEFT", 0, 0)
    bLeft:SetWidth(dispelBorderPx)
    local bRight = MakePreviewDispelBorder(dispelFrame)
    bRight:SetPoint("TOPRIGHT", dispelFrame, "TOPRIGHT", 0, 0)
    bRight:SetPoint("BOTTOMRIGHT", dispelFrame, "BOTTOMRIGHT", 0, 0)
    bRight:SetWidth(dispelBorderPx)

    -- Fill texture
    local dFillOpacity = dispelDB.fillOpacity or 0
    if dFillOpacity > 0 then
        local fill = dispelFrame:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints(dispelFrame)
        fill:SetColorTexture(dc[1], dc[2], dc[3], dFillOpacity)
    end

    -- Hidden by default — shown only when healer tab is selected
    dispelFrame:Hide()
    if dispelDB.enabled == false then
        childRefs.dispelOverlay = nil
    else
        childRefs.dispelOverlay = dispelFrame
    end

    -- Threat border (colored border when unit has aggro)
    -- Only visible in preview when indicators tab is selected
    local indDB = db.indicators or {}
    local threatBorderPx = (indDB.threatBorderSize or 3) * PREVIEW_SCALE
    local threatFrame = CreateFrame("Frame", nil, frame)
    threatFrame:SetAllPoints(frame)
    threatFrame:SetFrameLevel(frame:GetFrameLevel() + 9)

    local threatColor = indDB.threatColor or { 1, 0, 0, 0.8 }
    local threatOpacity = threatColor[4] or 0.8

    local function MakePreviewThreatBorder(parent)
        local bar = parent:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(threatColor[1], threatColor[2], threatColor[3], threatOpacity)
        return bar
    end
    local tTop = MakePreviewThreatBorder(threatFrame)
    tTop:SetPoint("TOPLEFT", threatFrame, "TOPLEFT", 0, 0)
    tTop:SetPoint("TOPRIGHT", threatFrame, "TOPRIGHT", 0, 0)
    tTop:SetHeight(threatBorderPx)
    local tBottom = MakePreviewThreatBorder(threatFrame)
    tBottom:SetPoint("BOTTOMLEFT", threatFrame, "BOTTOMLEFT", 0, 0)
    tBottom:SetPoint("BOTTOMRIGHT", threatFrame, "BOTTOMRIGHT", 0, 0)
    tBottom:SetHeight(threatBorderPx)
    local tLeft = MakePreviewThreatBorder(threatFrame)
    tLeft:SetPoint("TOPLEFT", threatFrame, "TOPLEFT", 0, 0)
    tLeft:SetPoint("BOTTOMLEFT", threatFrame, "BOTTOMLEFT", 0, 0)
    tLeft:SetWidth(threatBorderPx)
    local tRight = MakePreviewThreatBorder(threatFrame)
    tRight:SetPoint("TOPRIGHT", threatFrame, "TOPRIGHT", 0, 0)
    tRight:SetPoint("BOTTOMRIGHT", threatFrame, "BOTTOMRIGHT", 0, 0)
    tRight:SetWidth(threatBorderPx)

    -- Fill
    local threatFillOpacity = indDB.threatFillOpacity or 0
    if threatFillOpacity > 0 then
        local tFill = threatFrame:CreateTexture(nil, "BACKGROUND")
        tFill:SetAllPoints(threatFrame)
        tFill:SetColorTexture(threatColor[1], threatColor[2], threatColor[3], threatFillOpacity)
    end

    threatFrame:Hide()
    if indDB.showThreatBorder == false then
        childRefs.threatBorder = nil
    else
        childRefs.threatBorder = threatFrame
    end

    -- Target highlight (white/colored border when targeting this unit)
    local targetDB = healerDB.targetHighlight or {}
    local targetFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    SetOutsidePx(targetFrame, frame, 1)
    targetFrame:SetFrameLevel(frame:GetFrameLevel() + 3)
    ApplyPixelBackdrop(targetFrame, 3, false)
    local tc = targetDB.color or { 1, 1, 1, 0.6 }
    targetFrame:SetBackdropBorderColor(tc[1], tc[2], tc[3], tc[4] or 0.6)
    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(targetFrame, "targetHighlightBorder", function(owner)
            SetOutsidePx(owner, frame, 1)
            ApplyPixelBackdrop(owner, 3, false)
            owner:SetBackdropBorderColor(tc[1], tc[2], tc[3], tc[4] or 0.6)
        end)
    end
    if targetDB.enabled == false then
        targetFrame:Hide()
    end
    childRefs.targetHighlight = targetFrame

    -- Defensive indicator (icons on frame, e.g. external CDs)
    local defDB = healerDB.defensiveIndicator or {}
    local defSize = (defDB.iconSize or 16) * PREVIEW_SCALE
    local defPos = defDB.position or "CENTER"
    local defOffX = (defDB.offsetX or 0) * PREVIEW_SCALE
    local defOffY = (defDB.offsetY or 0) * PREVIEW_SCALE
    local defMaxIcons = defDB.maxIcons or 3
    local defSpacing = (defDB.spacing or 2) * PREVIEW_SCALE
    local defGrowDir = defDB.growDirection or "RIGHT"
    local defStepX, defStepY = 0, 0
    if defGrowDir == "RIGHT" then defStepX = defSize + defSpacing
    elseif defGrowDir == "LEFT" then defStepX = -(defSize + defSpacing)
    elseif defGrowDir == "UP" then defStepY = defSize + defSpacing
    elseif defGrowDir == "DOWN" then defStepY = -(defSize + defSpacing)
    end

    local defTextures = { 135936, 135987, 136120, 135874, 236220 }
    local defContainer = CreateFrame("Frame", nil, frame)
    defContainer:SetSize(1, 1)
    defContainer:SetPoint(defPos, frame, defPos, defOffX, defOffY)
    defContainer:SetFrameLevel(frame:GetFrameLevel() + 5)

    for i = 1, defMaxIcons do
        local defIconFrame = CreateFrame("Frame", nil, defContainer)
        defIconFrame:SetSize(defSize, defSize)
        defIconFrame:SetPoint(defPos, defContainer, defPos, defStepX * (i - 1), defStepY * (i - 1))
        local defIcon = defIconFrame:CreateTexture(nil, "OVERLAY")
        defIcon:SetAllPoints()
        defIcon:SetTexture(defTextures[((i - 1) % #defTextures) + 1])
        defIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    if defDB.enabled == false then
        defContainer:Hide()
    end
    childRefs.defIcon = defContainer

    -- Private auras (boss debuff placeholders)
    local paDB = db.privateAuras or {}
    local paSize = (paDB.iconSize or 20) * PREVIEW_SCALE
    local paAnchor = paDB.anchor or "RIGHT"
    local paOffX = (paDB.anchorOffsetX or -2) * PREVIEW_SCALE
    local paOffY = (paDB.anchorOffsetY or 0) * PREVIEW_SCALE
    local paSpacing = (paDB.spacing or 2) * PREVIEW_SCALE
    local paGrow = paDB.growDirection or "RIGHT"
    local paMax = paDB.maxPerFrame or 2

    local paContainer = CreateFrame("Frame", nil, frame)
    local paCount = paMax
    local paContainerW = paCount * paSize + math.max(paCount - 1, 0) * paSpacing
    paContainer:SetSize(math.max(paContainerW, 1), paSize)
    paContainer:SetPoint(paAnchor, frame, paAnchor, paOffX, PreviewBottomPadY(paAnchor, paOffY))

    for i = 1, paMax do
        local iconFrame = CreateFrame("Frame", nil, paContainer)
        iconFrame:SetSize(paSize, paSize)
        if i == 1 then
            iconFrame:SetPoint("LEFT", paContainer, "LEFT", 0, 0)
        else
            local offset = (i - 1) * (paSize + paSpacing)
            if paGrow == "LEFT" then
                iconFrame:SetPoint("RIGHT", paContainer, "RIGHT", -offset, 0)
            else
                iconFrame:SetPoint("LEFT", paContainer, "LEFT", offset, 0)
            end
        end
        -- Red background
        local bg = iconFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.6, 0.1, 0.1, 0.9)
        -- "PA" label
        local label = iconFrame:CreateFontString(nil, "OVERLAY")
        label:SetFont(GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF", paSize * 0.4, "OUTLINE")
        label:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        label:SetText("PA")
        label:SetTextColor(1, 1, 1, 1)
    end
    if paDB.enabled == false then
        paContainer:Hide()
    end
    childRefs.paContainer = paContainer

    -- Aura indicators (icon row, same pattern as buffs/debuffs)
    local aiDB = db.auraIndicators or {}
    local aiIconSize = (aiDB.iconSize or 14) * PREVIEW_SCALE
    local aiAnchor = aiDB.anchor or "TOPLEFT"
    local aiGrow = aiDB.growDirection or "RIGHT"
    local aiSpacing = (aiDB.spacing or 2) * PREVIEW_SCALE
    local aiMax = aiDB.maxIndicators or 5
    local aiOffX = (aiDB.anchorOffsetX or 0) * PREVIEW_SCALE
    local aiOffY = (aiDB.anchorOffsetY or 0) * PREVIEW_SCALE

    local aiContainer = CreateFrame("Frame", nil, frame)
    aiContainer:SetHeight(aiIconSize)
    aiContainer:SetPoint(aiAnchor, frame, aiAnchor, aiOffX, PreviewBottomPadY(aiAnchor, aiOffY))
    aiContainer:SetFrameLevel(frame:GetFrameLevel() + 6)

    -- Show sample indicator icons from tracked spells or spec preset spells
    local sampleSpells = {}
    local tracked = aiDB.trackedSpells
    if tracked then
        for spellID, enabled in pairs(tracked) do
            if enabled then
                sampleSpells[#sampleSpells + 1] = tonumber(spellID) or spellID
            end
        end
    end

    -- If no tracked spells configured, show placeholder icons from the spec's preset list
    if #sampleSpells == 0 then
        local specID = GetPlayerSpecID()
        if specID then
            for _, preset in ipairs(AURA_FILTER_PRESETS) do
                if preset.specID == specID and preset.spells then
                    for _, spell in ipairs(preset.spells) do
                        sampleSpells[#sampleSpells + 1] = spell.id
                        if #sampleSpells >= aiMax then break end
                    end
                    break
                end
            end
        end
    end

    -- Fallback: generic placeholder icons
    if #sampleSpells == 0 then
        sampleSpells = { 136034, 135940, 136081, 135932, 136063, 135987, 136070, 135864, 136207, 136130 }
    end

    for i = 1, math.min(aiMax, #sampleSpells) do
        local icon = aiContainer:CreateTexture(nil, "OVERLAY")
        icon:SetSize(aiIconSize, aiIconSize)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Try to get spell texture
        local spellTex
        local sid = sampleSpells[i]
        if sid and C_Spell and C_Spell.GetSpellTexture then
            spellTex = C_Spell.GetSpellTexture(sid)
        end
        icon:SetTexture(spellTex or 134400)

        -- Determine first-icon anchor from container anchor + grow direction
        -- Vertical: match anchor (TOP/BOTTOM/center)
        -- Horizontal: match grow direction (LEFT grows leftward from RIGHT, RIGHT grows rightward from LEFT)
        local vertPart = aiAnchor:find("TOP") and "TOP" or (aiAnchor:find("BOTTOM") and "BOTTOM" or "")
        local firstHoriz = aiGrow == "LEFT" and "RIGHT" or "LEFT"
        local firstAnchor = vertPart .. firstHoriz

        if i == 1 then
            icon:SetPoint(firstAnchor, aiContainer, firstAnchor, 0, 0)
        else
            local prevIcon = aiContainer["icon" .. (i - 1)]
            if prevIcon then
                if aiGrow == "LEFT" then
                    icon:SetPoint("RIGHT", prevIcon, "LEFT", -aiSpacing, 0)
                else
                    icon:SetPoint("LEFT", prevIcon, "RIGHT", aiSpacing, 0)
                end
            end
        end
        aiContainer["icon" .. i] = icon
    end
    local aiCount = math.min(aiMax, #sampleSpells)
    local aiContainerW = aiCount * aiIconSize + math.max(aiCount - 1, 0) * aiSpacing
    aiContainer:SetWidth(math.max(aiContainerW, 1))

    if aiDB.enabled == false then
        aiContainer:Hide()
    end
    childRefs.auraIndicatorContainer = aiContainer

    return wrapper
end

---------------------------------------------------------------------------
-- HIT OVERLAY FACTORY
---------------------------------------------------------------------------
local function CreateHitOverlay(parent, previewFrame, elementKey, anchorFrame, mode, width, height, anchorPoint, anchorRelPoint, offX, offY, frameLevel)
    local overlay = CreateFrame("Button", nil, parent)
    overlay:SetFrameLevel(frameLevel or (previewFrame:GetFrameLevel() + 10))
    overlay.elementKey = elementKey

    if mode == "fill" then
        overlay:SetAllPoints(anchorFrame)
    elseif mode == "fixed" then
        overlay:SetSize(width or 30, height or 20)
        overlay:SetPoint(anchorPoint or "CENTER", anchorFrame, anchorRelPoint or anchorPoint or "CENTER", offX or 0, offY or 0)
    end

    -- Mint highlight border
    local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    highlight:SetAllPoints()
    ApplyPixelBackdrop(highlight, 2, false)
    highlight:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    highlight:Hide()
    overlay.highlight = highlight

    return overlay
end

---------------------------------------------------------------------------
-- DRAG CONFIG: Maps element keys to their DB offset keys for drag support
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- ELEMENT SETTINGS BUILDERS
---------------------------------------------------------------------------

-- HEALTH settings
local function BuildHealthSettings(content, gfdb, onChange)
    SetComposerSearchContext("Health")

    local general = gfdb.general or {}
    local health = gfdb.health
    if not health then gfdb.health = {} health = gfdb.health end
    local absorbs = gfdb.absorbs
    if not absorbs then gfdb.absorbs = {} absorbs = gfdb.absorbs end
    local healPred = gfdb.healPrediction
    if not healPred then gfdb.healPrediction = {} healPred = gfdb.healPrediction end

    local L = CreateDynamicLayout(content)
    local cond = function() return health.showHealthText end
    local absorbCond = function() return absorbs.enabled end
    local healCond = function() return healPred.enabled end

    L:Row(GUI:CreateFormDropdown(content, "Health Texture", GetTextureList(), "texture", general, onChange), DROP_ROW)
    L:Row(GUI:CreateFormSlider(content, "Health Opacity", 0, 1, 0.05, "defaultHealthOpacity", general, onChange), SLIDER_HEIGHT)
    L:Row(GUI:CreateFormDropdown(content, "Fill Direction", HEALTH_FILL_OPTIONS, "healthFillDirection", health, onChange), DROP_ROW)

    local htHeader = GUI:CreateSectionHeader(content, "Health Text")
    L:Row(htHeader, htHeader.gap)
    L:Row(GUI:CreateFormCheckbox(content, "Show Health Text", "showHealthText", health, onChange), FORM_ROW)
    L:Row(GUI:CreateFormDropdown(content, "Display Style", HEALTH_DISPLAY_OPTIONS, "healthDisplayStyle", health, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "Font Size", 6, 24, 1, "healthFontSize", health, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, "healthAnchor", health, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormDropdown(content, "Text Justify", TEXT_JUSTIFY_OPTIONS, "healthJustify", health, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "healthOffsetX", health, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "healthOffsetY", health, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormColorPicker(content, "Text Color", "healthTextColor", health, onChange), FORM_ROW, cond)

    L:Header(GUI:CreateSectionHeader(content, "Absorb Shield"))
    L:Row(GUI:CreateFormCheckbox(content, "Show Absorb Shield", "enabled", absorbs, onChange), FORM_ROW)
    L:Row(GUI:CreateFormCheckbox(content, "Use Class Color", "useClassColor", absorbs, onChange), FORM_ROW, absorbCond)
    L:Row(GUI:CreateFormColorPicker(content, "Absorb Color", "color", absorbs, onChange), FORM_ROW, function() return absorbs.enabled and not absorbs.useClassColor end)
    L:Row(GUI:CreateFormSlider(content, "Absorb Opacity", 0.1, 1, 0.05, "opacity", absorbs, onChange), SLIDER_HEIGHT, absorbCond)

    L:Header(GUI:CreateSectionHeader(content, "Heal Prediction"))
    L:Row(GUI:CreateFormCheckbox(content, "Show Heal Prediction", "enabled", healPred, onChange), FORM_ROW)
    L:Row(GUI:CreateFormCheckbox(content, "Use Class Color", "useClassColor", healPred, onChange), FORM_ROW, healCond)
    L:Row(GUI:CreateFormColorPicker(content, "Heal Prediction Color", "color", healPred, onChange), FORM_ROW, function() return healPred.enabled and not healPred.useClassColor end)
    L:Row(GUI:CreateFormSlider(content, "Heal Prediction Opacity", 0.1, 1, 0.05, "opacity", healPred, onChange), SLIDER_HEIGHT, healCond)

    L:Finish()
end

-- POWER settings
local function BuildPowerSettings(content, gfdb, onChange)
    SetComposerSearchContext("Power")
    local power = gfdb.power
    if not power then gfdb.power = {} power = gfdb.power end

    local L = CreateDynamicLayout(content)
    local cond = function() return power.showPowerBar end

    L:Row(GUI:CreateFormCheckbox(content, "Show Power Bar", "showPowerBar", power, onChange), FORM_ROW)
    L:Row(GUI:CreateFormSlider(content, "Height", 1, 12, 1, "powerBarHeight", power, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Only Show for Healers", "powerBarOnlyHealers", power, onChange), FORM_ROW, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Only Show for Tanks", "powerBarOnlyTanks", power, onChange), FORM_ROW, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Use Power Type Color", "powerBarUsePowerColor", power, onChange), FORM_ROW, cond)
    L:Row(GUI:CreateFormColorPicker(content, "Custom Color", "powerBarColor", power, onChange), FORM_ROW, cond)
    L:Finish()
end

-- NAME settings
local function BuildNameSettings(content, gfdb, onChange)
    SetComposerSearchContext("Name")
    local name = gfdb.name
    if not name then gfdb.name = {} name = gfdb.name end

    local L = CreateDynamicLayout(content)
    local cond = function() return name.showName end

    L:Row(GUI:CreateFormCheckbox(content, "Show Name", "showName", name, onChange), FORM_ROW)
    L:Row(GUI:CreateFormSlider(content, "Font Size", 6, 24, 1, "nameFontSize", name, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, "nameAnchor", name, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormDropdown(content, "Text Justify", TEXT_JUSTIFY_OPTIONS, "nameJustify", name, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "Max Name Length (0 = unlimited)", 0, 20, 1, "maxNameLength", name, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "nameOffsetX", name, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "nameOffsetY", name, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Use Class Color", "nameTextUseClassColor", name, onChange), FORM_ROW, cond)
    L:Row(GUI:CreateFormColorPicker(content, "Text Color", "nameTextColor", name, onChange), FORM_ROW, cond)
    L:Finish()
end


---------------------------------------------------------------------------
-- SPELL LIST UI: Shared helper for whitelist/blacklist management
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

-- Create a mini toggle matching QUI's pill-style toggle (reusable across rebuilds)
local function CreateMiniToggle(parent)
    local track = CreateFrame("Button", nil, parent, "BackdropTemplate")
    SetSizePx(track, 32, 16)
    ApplyPixelBackdrop(track, 1, true)

    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    SetSizePx(thumb, 12, 12)
    ApplyPixelBackdrop(thumb, 1, true)
    thumb:SetBackdropColor(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
    thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)

    track.thumb = thumb

    local function RefreshMiniToggleLayout(owner)
        SetSizePx(owner, 32, 16)
        ApplyPixelBackdrop(owner, 1, true)
        SetSizePx(thumb, 12, 12)
        ApplyPixelBackdrop(thumb, 1, true)
        thumb:SetBackdropColor(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
        thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
        thumb:ClearAllPoints()
        if owner._toggleOn then
            SetPointPx(thumb, "RIGHT", owner, "RIGHT", -2, 0)
        else
            SetPointPx(thumb, "LEFT", owner, "LEFT", 2, 0)
        end
    end

    function track:SetToggleState(on)
        self._toggleOn = on and true or false
        if self._toggleOn then
            self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self:SetBackdropBorderColor(C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1)
        else
            self:SetBackdropColor(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1)
            self:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
        end
        RefreshMiniToggleLayout(self)
    end

    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(track, "miniToggleLayout", RefreshMiniToggleLayout)
    end
    track:SetToggleState(false)
    return track
end

-- Rebuild toggle rows: preset spells as toggles, extra spells with × remove
local function RebuildSpellToggleRows(container, listTable, presets, onChange)
    if container._rows then
        for _, row in ipairs(container._rows) do
            row:Hide()
        end
    end
    container._rows = container._rows or {}

    local ROW_H = 26
    local HEADER_H = 22
    local y = 0
    local rowIndex = 0

    -- Track which spellIDs come from presets
    local presetSpellIds = {}

    -- Render preset sections
    for _, preset in ipairs(presets) do
        -- Section header
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
        -- Hide toggle/remove if this row was previously a spell row
        if headerRow.toggle then headerRow.toggle:Hide() end
        if headerRow.removeBtn then headerRow.removeBtn:Hide() end
        headerRow.text:SetText("|cFF" .. "56D1FF" .. preset.name .. "|r")
        headerRow:SetPoint("TOPLEFT", 0, y)
        headerRow:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        headerRow:Show()
        y = y - HEADER_H

        -- Spell toggle rows
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

            local displayName = spell.name or GetSpellName(spell.id) or ("Spell " .. spell.id)
            row.text:SetText(displayName)

            if row.toggle then row.toggle:Show() end
            if row.removeBtn then row.removeBtn:Hide() end

            local isOn = listTable[spell.id] == true
            row.toggle:SetToggleState(isOn)

            local spellId = spell.id
            row.toggle:SetScript("OnClick", function()
                local nowOn = listTable[spellId] ~= true
                if nowOn then
                    listTable[spellId] = true
                else
                    listTable[spellId] = nil
                end
                row.toggle:SetToggleState(nowOn)
                if onChange then onChange() end
            end)

            row:Show()
            y = y - ROW_H
        end
    end

    -- Extra spells not in any preset (leftover from spec changes) — show with × remove
    local extras = {}
    for spellId in pairs(listTable) do
        if not presetSpellIds[spellId] then
            table.insert(extras, spellId)
        end
    end
    table.sort(extras)

    if #extras > 0 then
        -- "Other" header
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
        headerRow.text:SetText("|cFF" .. "56D1FF" .. "Other" .. "|r")
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
                row.removeBtnText:SetText("\195\151") -- × character
                row.removeBtnText:SetTextColor(0.8, 0.3, 0.3)
                row.removeBtn:SetScript("OnEnter", function() row.removeBtnText:SetTextColor(1, 0.4, 0.4) end)
                row.removeBtn:SetScript("OnLeave", function() row.removeBtnText:SetTextColor(0.8, 0.3, 0.3) end)
            end

            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            row.text:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)

            local name = GetSpellName(spellId)
            row.text:SetText(name or ("Spell " .. spellId))

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

    for i = rowIndex + 1, #container._rows do
        container._rows[i]:Hide()
    end

    container:SetHeight(math.max(1, math.abs(y)))
end

-- Build the spell list section with spec-detected toggle rows
-- getListTable: function returning the currently active spell list table
-- Returns final y position and the spell list container frame
local function BuildSpellListSection(parent, getListTable, onChange, y, customPresets)
    -- Spell list entries container
    local spellListContainer = CreateFrame("Frame", nil, parent)
    spellListContainer:SetPoint("TOPLEFT", PAD, y)
    spellListContainer:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
    spellListContainer:SetHeight(1)

    local presets
    if customPresets then
        presets = customPresets
    else
        -- Determine which presets to show based on player spec
        local function GetPresetsForPlayer()
            local p = {}
            local specID = GetPlayerSpecID()
            if specID and SPEC_TO_PRESET[specID] then
                table.insert(p, SPEC_TO_PRESET[specID])
            end
            -- Always include common defensives
            if COMMON_DEFENSIVES_PRESET then
                table.insert(p, COMMON_DEFENSIVES_PRESET)
            end
            -- If no spec match, show all spec presets
            if #p <= 1 then
                for _, preset in ipairs(AURA_FILTER_PRESETS) do
                    if preset.specID then
                        table.insert(p, preset)
                    end
                end
            end
            return p
        end
        presets = GetPresetsForPlayer()
    end

    spellListContainer._presets = presets
    RebuildSpellToggleRows(spellListContainer, getListTable(), presets, onChange)

    return y, spellListContainer
end

-- BUFFS settings
local function BuildBuffsSettings(content, gfdb, onChange)
    SetComposerSearchContext("Buffs")
    local auras = gfdb.auras
    if not auras then gfdb.auras = {} auras = gfdb.auras end

    local L = CreateDynamicLayout(content)
    local cond = function() return auras.showBuffs end

    L:Row(GUI:CreateFormCheckbox(content, "Show Buffs", "showBuffs", auras, onChange), FORM_ROW)
    L:Row(GUI:CreateFormSlider(content, "Max Buffs", 0, 8, 1, "maxBuffs", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Icon Size", 8, 32, 1, "buffIconSize", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, "buffAnchor", auras, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormDropdown(content, "Grow Direction", AURA_GROW_OPTIONS, "buffGrowDirection", auras, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "Spacing", 0, 8, 1, "buffSpacing", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "buffOffsetX", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "buffOffsetY", auras, onChange), SLIDER_HEIGHT, cond)

    -- Filtering section
    L:Header(GUI:CreateSectionHeader(content, "Buff Filtering"))

    -- Classification container (managed separately due to dynamic height)
    local classificationContainer = CreateFrame("Frame", nil, content)
    classificationContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    -- Forward ref for relayout so dropdown onChange can trigger it
    local relayoutRef = {}
    local filterDrop = GUI:CreateFormDropdown(content, "Filter Mode", FILTER_MODE_OPTIONS, "filterMode", auras, function()
        if onChange then onChange() end
        if relayoutRef.fn then relayoutRef.fn() end
    end)
    L:Row(filterDrop, DROP_ROW, cond)

    local onlyMineCheck = GUI:CreateFormCheckbox(content, "Only My Buffs", "buffFilterOnlyMine", auras, onChange)
    L:Row(onlyMineCheck, FORM_ROW, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Hide Permanent Buffs", "buffHidePermanent", auras, onChange), FORM_ROW, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Deduplicate Defensives/Indicators", "buffDeduplicateDefensives", auras, onChange), FORM_ROW, cond)

    local classCond = function() return auras.showBuffs and (auras.filterMode or "off") == "classification" end
    L:Row(classificationContainer, FORM_ROW * 3, classCond)

    -- Classification checkboxes (inside container)
    local classY = 0
    local buffClass = auras.buffClassifications
    if not buffClass then auras.buffClassifications = {} buffClass = auras.buffClassifications end

    local c1 = GUI:CreateFormCheckbox(classificationContainer, "Raid", "raid", buffClass, onChange)
    c1:SetPoint("TOPLEFT", 0, classY)
    c1:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0)
    classY = classY - FORM_ROW

    local c2 = GUI:CreateFormCheckbox(classificationContainer, "Cancelable", "cancelable", buffClass, onChange)
    c2:SetPoint("TOPLEFT", 0, classY)
    c2:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0)
    classY = classY - FORM_ROW

    local c5 = GUI:CreateFormCheckbox(classificationContainer, "Important", "important", buffClass, onChange)
    c5:SetPoint("TOPLEFT", 0, classY)
    c5:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0)
    classY = classY - FORM_ROW

    classificationContainer:SetHeight(math.abs(classY))

    -- Blacklist section (always visible when buffs enabled)
    L:Header(GUI:CreateSectionHeader(content, "Blacklisted Buffs"))
    local blDesc = GUI:CreateLabel(content, "Blacklisted buffs are always hidden regardless of filter mode.", 11, C.textMuted)
    blDesc:SetJustifyH("LEFT")
    L:Row(blDesc, 30, cond)

    local relayout = L:Finish()

    -- Blacklist spell list (appended after dynamic layout)
    if not auras.buffBlacklist then auras.buffBlacklist = {} end

    local blEndY, blContainer = BuildSpellListSection(
        content,
        function() return auras.buffBlacklist end,
        function()
            if not blContainer then return end
            local newY = -(content:GetHeight() - 10)
            blContainer:ClearAllPoints()
            blContainer:SetPoint("TOPLEFT", PAD, newY)
            blContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            local listH = blContainer:GetHeight()
            content:SetHeight(math.abs(newY) + listH + 10)
            if onChange then onChange() end
        end,
        -(content:GetHeight() - 10),
        BUFF_BLACKLIST_PRESETS
    )

    local function RepositionBlacklist()
        local newY = -(content:GetHeight() - 10)
        blContainer:ClearAllPoints()
        blContainer:SetPoint("TOPLEFT", PAD, newY)
        blContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        local listH = blContainer:GetHeight()
        content:SetHeight(math.abs(newY) + listH + 10)
    end

    -- Wrap relayout so blacklist repositions when filter mode changes
    relayoutRef.fn = function()
        relayout()
        RepositionBlacklist()
    end

    RepositionBlacklist()
end

-- DEBUFFS settings
local function BuildDebuffsSettings(content, gfdb, onChange)
    SetComposerSearchContext("Debuffs")
    local auras = gfdb.auras
    if not auras then gfdb.auras = {} auras = gfdb.auras end

    local L = CreateDynamicLayout(content)
    local cond = function() return auras.showDebuffs end

    L:Row(GUI:CreateFormCheckbox(content, "Show Debuffs", "showDebuffs", auras, onChange), FORM_ROW)
    L:Row(GUI:CreateFormSlider(content, "Max Debuffs", 0, 8, 1, "maxDebuffs", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Icon Size", 8, 32, 1, "debuffIconSize", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, "debuffAnchor", auras, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormDropdown(content, "Grow Direction", AURA_GROW_OPTIONS, "debuffGrowDirection", auras, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "Spacing", 0, 8, 1, "debuffSpacing", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "debuffOffsetX", auras, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "debuffOffsetY", auras, onChange), SLIDER_HEIGHT, cond)

    -- Filtering section
    L:Header(GUI:CreateSectionHeader(content, "Debuff Filtering"))

    -- Classification container (managed separately due to dynamic height)
    local classificationContainer = CreateFrame("Frame", nil, content)
    classificationContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    local DEBUFF_FILTER_MODE_OPTIONS = {
        { value = "off", text = "Off (Show All)" },
        { value = "classification", text = "Classification" },
    }

    -- Forward ref for relayout so dropdown onChange can trigger it
    local relayoutRef = {}
    local filterDrop = GUI:CreateFormDropdown(content, "Filter Mode", DEBUFF_FILTER_MODE_OPTIONS, "filterMode", auras, function()
        if onChange then onChange() end
        if relayoutRef.fn then relayoutRef.fn() end
    end)
    L:Row(filterDrop, DROP_ROW, cond)

    local classCond = function() return auras.showDebuffs and (auras.filterMode or "off") == "classification" end
    L:Row(classificationContainer, FORM_ROW * 3, classCond)

    -- Classification checkboxes (inside container)
    local classY = 0
    local debuffClass = auras.debuffClassifications
    if not debuffClass then auras.debuffClassifications = {} debuffClass = auras.debuffClassifications end

    local d1 = GUI:CreateFormCheckbox(classificationContainer, "Raid", "raid", debuffClass, onChange)
    d1:SetPoint("TOPLEFT", 0, classY)
    d1:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0)
    classY = classY - FORM_ROW

    local d2 = GUI:CreateFormCheckbox(classificationContainer, "Crowd Control", "crowdControl", debuffClass, onChange)
    d2:SetPoint("TOPLEFT", 0, classY)
    d2:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0)
    classY = classY - FORM_ROW

    local d3 = GUI:CreateFormCheckbox(classificationContainer, "Important", "important", debuffClass, onChange)
    d3:SetPoint("TOPLEFT", 0, classY)
    d3:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0)
    classY = classY - FORM_ROW

    classificationContainer:SetHeight(math.abs(classY))

    -- Blacklist section (always visible when debuffs enabled)
    L:Header(GUI:CreateSectionHeader(content, "Blacklisted Debuffs"))
    local blDesc = GUI:CreateLabel(content, "Blacklisted debuffs are always hidden regardless of filter mode.", 11, C.textMuted)
    blDesc:SetJustifyH("LEFT")
    L:Row(blDesc, 30, cond)

    local relayout = L:Finish()

    -- Blacklist spell list (appended after dynamic layout)
    if not auras.debuffBlacklist then auras.debuffBlacklist = {} end

    local blEndY, blContainer = BuildSpellListSection(
        content,
        function() return auras.debuffBlacklist end,
        function()
            if not blContainer then return end
            local newY = -(content:GetHeight() - 10)
            blContainer:ClearAllPoints()
            blContainer:SetPoint("TOPLEFT", PAD, newY)
            blContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            local listH = blContainer:GetHeight()
            content:SetHeight(math.abs(newY) + listH + 10)
            if onChange then onChange() end
        end,
        -(content:GetHeight() - 10),
        DEBUFF_BLACKLIST_PRESETS
    )

    local function RepositionBlacklist()
        if not blContainer then return end
        local newY = -(content:GetHeight() - 10)
        blContainer:ClearAllPoints()
        blContainer:SetPoint("TOPLEFT", PAD, newY)
        blContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        local listH = blContainer:GetHeight()
        content:SetHeight(math.abs(newY) + listH + 10)
    end

    -- Wrap relayout so blacklist repositions when filter mode changes
    relayoutRef.fn = function()
        relayout()
        RepositionBlacklist()
    end

    RepositionBlacklist()
end

-- INDICATORS settings (includes role icon)
local function BuildIndicatorsSettings(content, gfdb, onChange)
    SetComposerSearchContext("Indicators")
    local ind = gfdb.indicators
    if not ind then gfdb.indicators = {} ind = gfdb.indicators end

    local L = CreateDynamicLayout(content)

    -- Role Icon section
    local roleCond = function() return ind.showRoleIcon end
    L:Header(GUI:CreateSectionHeader(content, "Role Icon"))
    L:Row(GUI:CreateFormCheckbox(content, "Show Role Icon", "showRoleIcon", ind, onChange), FORM_ROW)
    L:Row(GUI:CreateFormCheckbox(content, "Show Tank", "showRoleTank", ind, onChange), FORM_ROW, roleCond)
    L:Row(GUI:CreateFormCheckbox(content, "Show Healer", "showRoleHealer", ind, onChange), FORM_ROW, roleCond)
    L:Row(GUI:CreateFormCheckbox(content, "Show DPS", "showRoleDPS", ind, onChange), FORM_ROW, roleCond)
    L:Row(GUI:CreateFormSlider(content, "Icon Size", 6, 24, 1, "roleIconSize", ind, onChange), SLIDER_HEIGHT, roleCond)
    L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, "roleIconAnchor", ind, onChange), DROP_ROW, roleCond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "roleIconOffsetX", ind, onChange), SLIDER_HEIGHT, roleCond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "roleIconOffsetY", ind, onChange), SLIDER_HEIGHT, roleCond)

    local function AddIndicator(label, showKey, sizeKey, defSize, anchorKey, offXKey, offYKey)
        L:Header(GUI:CreateSectionHeader(content, label))
        L:Row(GUI:CreateFormCheckbox(content, "Enable", showKey, ind, onChange), FORM_ROW)
        local cond = function() return ind[showKey] end
        L:Row(GUI:CreateFormSlider(content, "Icon Size", 6, 32, 1, sizeKey, ind, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, anchorKey, ind, onChange), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, offXKey, ind, onChange), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, offYKey, ind, onChange), SLIDER_HEIGHT, cond)
    end

    AddIndicator("Ready Check", "showReadyCheck", "readyCheckSize", 16, "readyCheckAnchor", "readyCheckOffsetX", "readyCheckOffsetY")
    AddIndicator("Resurrection", "showResurrection", "resurrectionSize", 16, "resurrectionAnchor", "resurrectionOffsetX", "resurrectionOffsetY")
    AddIndicator("Summon Pending", "showSummonPending", "summonSize", 20, "summonAnchor", "summonOffsetX", "summonOffsetY")
    AddIndicator("Leader Icon", "showLeaderIcon", "leaderSize", 12, "leaderAnchor", "leaderOffsetX", "leaderOffsetY")
    AddIndicator("Raid Target Marker", "showTargetMarker", "targetMarkerSize", 14, "targetMarkerAnchor", "targetMarkerOffsetX", "targetMarkerOffsetY")
    AddIndicator("Phase Icon", "showPhaseIcon", "phaseSize", 16, "phaseAnchor", "phaseOffsetX", "phaseOffsetY")

    -- Threat section
    L:Header(GUI:CreateSectionHeader(content, "Threat"))
    L:Row(GUI:CreateFormCheckbox(content, "Show Threat Border", "showThreatBorder", ind, onChange), FORM_ROW)
    local threatCond = function() return ind.showThreatBorder end
    L:Row(GUI:CreateFormSlider(content, "Border Size", 1, 16, 1, "threatBorderSize", ind, onChange), SLIDER_HEIGHT, threatCond)
    L:Row(GUI:CreateFormColorPicker(content, "Threat Color", "threatColor", ind, onChange), FORM_ROW, threatCond)
    L:Row(GUI:CreateFormSlider(content, "Threat Fill Opacity", 0, 0.5, 0.05, "threatFillOpacity", ind, onChange), SLIDER_HEIGHT, threatCond)

    L:Finish()
end

-- HEALER settings
local function BuildHealerSettings(content, gfdb, onChange)
    SetComposerSearchContext("Healer")
    local healer = gfdb.healer
    if not healer then gfdb.healer = {} healer = gfdb.healer end

    local dispel = healer.dispelOverlay
    if not dispel then healer.dispelOverlay = {} dispel = healer.dispelOverlay end
    local dispelColors = dispel.colors
    if not dispelColors then
        dispel.colors = {
            Magic   = { 0.2, 0.6, 1.0, 1 },
            Curse   = { 0.6, 0.0, 1.0, 1 },
            Disease = { 0.6, 0.4, 0.0, 1 },
            Poison  = { 0.0, 0.6, 0.0, 1 },
        }
        dispelColors = dispel.colors
    end

    local targetHL = healer.targetHighlight
    if not targetHL then healer.targetHighlight = {} targetHL = healer.targetHighlight end

    local L = CreateDynamicLayout(content)
    local dispelCond = function() return dispel.enabled end
    local targetCond = function() return targetHL.enabled end

    -- Dispel overlay
    L:Header(GUI:CreateSectionHeader(content, "Dispel Overlay"))
    local dispelDesc = GUI:CreateLabel(content, "Colors the frame border when a dispellable debuff is active. Each dispel type has its own color.", 11, C.textMuted)
    dispelDesc:SetJustifyH("LEFT")
    L:Row(dispelDesc, 26)
    L:Row(GUI:CreateFormCheckbox(content, "Enable Dispel Overlay", "enabled", dispel, onChange), FORM_ROW)
    L:Row(GUI:CreateFormSlider(content, "Border Size", 1, 16, 1, "borderSize", dispel, onChange), SLIDER_HEIGHT, dispelCond)
    L:Row(GUI:CreateFormSlider(content, "Border Opacity", 0.1, 1, 0.05, "opacity", dispel, onChange), SLIDER_HEIGHT, dispelCond)
    L:Row(GUI:CreateFormSlider(content, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", dispel, onChange), SLIDER_HEIGHT, dispelCond)
    L:Row(GUI:CreateFormColorPicker(content, "Magic Color", "Magic", dispelColors, onChange), FORM_ROW, dispelCond)
    L:Row(GUI:CreateFormColorPicker(content, "Curse Color", "Curse", dispelColors, onChange), FORM_ROW, dispelCond)
    L:Row(GUI:CreateFormColorPicker(content, "Disease Color", "Disease", dispelColors, onChange), FORM_ROW, dispelCond)
    L:Row(GUI:CreateFormColorPicker(content, "Poison Color", "Poison", dispelColors, onChange), FORM_ROW, dispelCond)

    -- Target highlight
    L:Header(GUI:CreateSectionHeader(content, "Target Highlight"))
    L:Row(GUI:CreateFormCheckbox(content, "Enable Target Highlight", "enabled", targetHL, onChange), FORM_ROW)
    L:Row(GUI:CreateFormColorPicker(content, "Highlight Color", "color", targetHL, onChange), FORM_ROW, targetCond)
    L:Row(GUI:CreateFormSlider(content, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", targetHL, onChange), SLIDER_HEIGHT, targetCond)

    L:Finish()
end

-- DEFENSIVE settings
local function BuildDefensiveSettings(content, gfdb, onChange)
    SetComposerSearchContext("Defensive")
    local healer = gfdb.healer
    if not healer then gfdb.healer = {} healer = gfdb.healer end
    local def = healer.defensiveIndicator
    if not def then healer.defensiveIndicator = {} def = healer.defensiveIndicator end

    local L = CreateDynamicLayout(content)
    local cond = function() return def.enabled end

    L:Row(GUI:CreateFormCheckbox(content, "Enable Defensive Indicator", "enabled", def, onChange), FORM_ROW)
    L:Row(GUI:CreateFormSlider(content, "Max Icons", 1, 5, 1, "maxIcons", def, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Icon Size", 8, 32, 1, "iconSize", def, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", def, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "Spacing", 0, 8, 1, "spacing", def, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Position", NINE_POINT_OPTIONS, "position", def, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "offsetX", def, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "offsetY", def, onChange), SLIDER_HEIGHT, cond)

    L:Finish()
end

-- PRIVATE AURAS settings
local function BuildPrivateAurasSettings(content, gfdb, onChange)
    SetComposerSearchContext("Private Auras")
    local pa = gfdb.privateAuras
    if not pa then gfdb.privateAuras = {} pa = gfdb.privateAuras end

    local L = CreateDynamicLayout(content)
    local cond = function() return pa.enabled end

    L:Row(GUI:CreateFormCheckbox(content, "Enable Private Auras", "enabled", pa, onChange), FORM_ROW)
    L:Row(GUI:CreateFormSlider(content, "Max Per Frame", 1, 5, 1, "maxPerFrame", pa, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Icon Size", 10, 40, 1, "iconSize", pa, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", pa, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "Spacing", 0, 8, 1, "spacing", pa, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, "anchor", pa, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "anchorOffsetX", pa, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "anchorOffsetY", pa, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Show Countdown", "showCountdown", pa, onChange), FORM_ROW, cond)
    L:Row(GUI:CreateFormCheckbox(content, "Show Countdown Numbers", "showCountdownNumbers", pa, onChange), FORM_ROW, cond)
    L:Finish()
end

-- AURA INDICATORS settings
local function BuildAuraIndicatorsSettings(content, gfdb, onChange)
    SetComposerSearchContext("Aura Indicators")
    local ai = gfdb.auraIndicators
    if not ai then gfdb.auraIndicators = {} ai = gfdb.auraIndicators end

    local L = CreateDynamicLayout(content)
    local cond = function() return ai.enabled end

    local desc = GUI:CreateLabel(content, "Track specific spells as icons on group frames. Auto-detects your spec and shows relevant HoTs, buffs, and externals.", 11, C.textMuted)
    desc:SetJustifyH("LEFT")
    L:Row(desc, 30)
    L:Row(GUI:CreateFormCheckbox(content, "Enable Aura Indicators", "enabled", ai, onChange), FORM_ROW)

    L:Header(GUI:CreateSectionHeader(content, "Display"))
    L:Row(GUI:CreateFormSlider(content, "Icon Size", 8, 32, 1, "iconSize", ai, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Max Indicators", 1, 10, 1, "maxIndicators", ai, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormDropdown(content, "Anchor", NINE_POINT_OPTIONS, "anchor", ai, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormDropdown(content, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", ai, onChange), DROP_ROW, cond)
    L:Row(GUI:CreateFormSlider(content, "Spacing", 0, 8, 1, "spacing", ai, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "X Offset", -100, 100, 1, "anchorOffsetX", ai, onChange), SLIDER_HEIGHT, cond)
    L:Row(GUI:CreateFormSlider(content, "Y Offset", -100, 100, 1, "anchorOffsetY", ai, onChange), SLIDER_HEIGHT, cond)

    -- Tracked Spells section uses manual layout (dynamic spell list)
    local spellsHeader = GUI:CreateSectionHeader(content, "Tracked Spells")
    L:Header(spellsHeader)
    local spellsDesc = GUI:CreateLabel(content, "Toggle which spells are tracked as indicators for your current spec. Common defensives are always available.", 11, C.textMuted)
    spellsDesc:SetJustifyH("LEFT")
    L:Row(spellsDesc, 30, cond)

    -- Finish layout to get current Y position, then append spell list below
    local relayout = L:Finish()

    if not ai.trackedSpells then ai.trackedSpells = {} end

    -- Spell list is appended after the dynamic layout
    -- Calculate starting Y from content height set by Finish()
    local function GetSpellListY()
        return -(content:GetHeight() - 10)
    end

    local spellListEndY, spellListContainer
    spellListEndY, spellListContainer = BuildSpellListSection(
        content,
        function() return ai.trackedSpells end,
        function()
            local listH = spellListContainer:GetHeight()
            content:SetHeight(math.abs(spellListEndY) + listH + 10)
            if onChange then onChange() end
        end,
        GetSpellListY()
    )

    local listH = spellListContainer:GetHeight()
    content:SetHeight(math.abs(spellListEndY) + listH + 10)
end

-- ABSORBS settings

---------------------------------------------------------------------------
-- ADDITIONAL DROPDOWN OPTIONS (for non-visual settings)
---------------------------------------------------------------------------
local GROW_OPTIONS = {
    { value = "DOWN", text = "Down" },
    { value = "UP", text = "Up" },
    { value = "RIGHT", text = "Right (Horizontal)" },
    { value = "LEFT", text = "Left (Horizontal)" },
}

local GROUP_GROW_OPTIONS = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
}

local SORT_OPTIONS = {
    { value = "INDEX", text = "Group Index" },
    { value = "NAME", text = "Name" },
}

local GROUP_BY_OPTIONS = {
    { value = "GROUP", text = "Group Number" },
    { value = "ROLE", text = "Role" },
    { value = "CLASS", text = "Class" },
    { value = "NONE", text = "None (Flat List)" },
}

local ANCHOR_SIDE_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
}

local PET_ANCHOR_OPTIONS = {
    { value = "BOTTOM", text = "Below Group" },
    { value = "RIGHT", text = "Right of Group" },
    { value = "LEFT", text = "Left of Group" },
}

---------------------------------------------------------------------------
-- GENERAL SETTINGS (enable, appearance, fonts)
---------------------------------------------------------------------------
local function BuildGeneralSettings(content, gfdb, onChange)
    local y = -10
    SetGeneralSearchContext("General")

    -- Enable checkbox (requires reload)
    local enableCheck = GUI:CreateFormCheckbox(content, "Enable Group Frames (Req. Reload)", "enabled", gfdb, function()
        GUI:ShowConfirmation({
            title = "Reload UI?",
            message = "Enabling or disabling group frames requires a UI reload to take effect.",
            acceptText = "Reload",
            cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end)
    enableCheck:SetPoint("TOPLEFT", PAD, y)
    enableCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local infoText = GUI:CreateDescription(content, "Custom party and raid frames. Replaces Blizzard's default group frames when enabled.")
    infoText:SetPoint("TOPLEFT", PAD, y)
    infoText:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - 40

    ---------------------------------------------------------------------------
    -- Position
    ---------------------------------------------------------------------------
    local posHeader = GUI:CreateSectionHeader(content, "Position")
    posHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - posHeader.gap

    local unifiedCheck = GUI:CreateFormCheckbox(content, "Unified Party & Raid Position", "unifiedPosition", gfdb, function()
        GUI:ShowConfirmation({
            title = "Reload Required",
            message = "Changing group frame positioning mode requires a UI reload to take effect.",
            acceptText = "Reload Now",
            cancelText = "Later",
            isDestructive = false,
            onAccept = function() QUI:SafeReload() end,
        })
    end)
    unifiedCheck:SetPoint("TOPLEFT", PAD, y)
    unifiedCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local unifiedHint = GUI:CreateLabel(content,
        "When disabled, party and raid frames have separate movers and can be positioned independently.", 10, C.textMuted)
    unifiedHint:SetPoint("TOPLEFT", PAD + 4, y + 4)
    unifiedHint:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    unifiedHint:SetJustifyH("LEFT")
    y = y - 20

    content:SetHeight(math.abs(y) + 10)
end

---------------------------------------------------------------------------
-- APPEARANCE SETTINGS (per-context: party/raid)
-- Frame appearance + font + portrait + tooltips
---------------------------------------------------------------------------
local function BuildAppearanceSettings(content, gfdb, onChange)
    local y = -10
    local isRaid = rawget(gfdb, "_composerMode") == "raid"
    if isRaid then SetRaidSearchContext("Appearance") else SetPartySearchContext("Appearance") end

    ---------------------------------------------------------------------------
    -- Preview & Edit
    ---------------------------------------------------------------------------
    local previewDesc = GUI:CreateLabel(content,
        "Preview group frames when solo. Also available via /qui grouptest", 11, C.textMuted)
    previewDesc:SetPoint("TOPLEFT", PAD, y)
    previewDesc:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    previewDesc:SetJustifyH("LEFT")
    y = y - 24

    if not isRaid then
        local previewBtn = GUI:CreateButton(content, "Party Preview (5)", 150, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if editMode then editMode:ToggleTestMode("party") end
        end)
        previewBtn:SetPoint("TOPLEFT", PAD, y)
        local editBtn = GUI:CreateButton(content, "Edit Party", 120, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if not editMode then return end
            if editMode:IsEditMode() and editMode._lastTestPreviewType == "party" then
                editMode:DisableEditMode()
            else
                editMode:EnableEditMode("party")
            end
        end)
        editBtn:SetPoint("LEFT", previewBtn, "RIGHT", 10, 0)
        y = y - 36
    else
        local db = GetGFDB()
        local testMode = db and db.testMode
        if not testMode then
            if db then db.testMode = {} end
            testMode = db and db.testMode or {}
        end

        local raidSizeSlider = GUI:CreateFormSlider(content, "Raid Size", 10, 40, 5, "raidCount", testMode, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if editMode and (editMode:IsTestMode() or editMode:IsEditMode()) and editMode._lastTestPreviewType == "raid" then
                editMode:RefreshTestMode()
            end
        end)
        raidSizeSlider:SetPoint("TOPLEFT", PAD, y)
        raidSizeSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local previewBtn = GUI:CreateButton(content, "Raid Preview", 150, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if editMode then editMode:ToggleTestMode("raid") end
        end)
        previewBtn:SetPoint("TOPLEFT", PAD, y)
        local editBtn = GUI:CreateButton(content, "Edit Raid", 120, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if not editMode then return end
            if editMode:IsEditMode() and editMode._lastTestPreviewType == "raid" then
                editMode:DisableEditMode()
            else
                editMode:EnableEditMode("raid")
            end
        end)
        editBtn:SetPoint("LEFT", previewBtn, "RIGHT", 10, 0)
        y = y - 36
    end

    ---------------------------------------------------------------------------
    -- Frame Appearance
    ---------------------------------------------------------------------------
    local general = gfdb.general
    if not general then gfdb.general = {} general = gfdb.general end

    -- Border & Texture
    local borderSlider = GUI:CreateFormSlider(content, "Border Size", 0, 3, 1, "borderSize", general, onChange)
    borderSlider:SetPoint("TOPLEFT", PAD, y)
    borderSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    local texDrop = GUI:CreateFormDropdown(content, "Texture", GetTextureList(), "texture", general, onChange)
    texDrop:SetPoint("TOPLEFT", PAD, y)
    texDrop:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - DROP_ROW

    -- Dark Mode & Colors
    local darkCheck = GUI:CreateFormCheckbox(content, "Dark Mode", "darkMode", general, onChange)
    darkCheck:SetPoint("TOPLEFT", PAD, y)
    darkCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local classColorCheck = GUI:CreateFormCheckbox(content, "Use Class Color", "useClassColor", general, onChange)
    classColorCheck:SetPoint("TOPLEFT", PAD, y)
    classColorCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local bgColor = GUI:CreateFormColorPicker(content, "Background Color", "defaultBgColor", general, onChange)
    bgColor:SetPoint("TOPLEFT", PAD, y)
    bgColor:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local bgOpacity = GUI:CreateFormSlider(content, "Background Opacity", 0, 1, 0.05, "defaultBgOpacity", general, onChange)
    bgOpacity:SetPoint("TOPLEFT", PAD, y)
    bgOpacity:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    -- Dark mode colors section
    local dmHeader = GUI:CreateSectionHeader(content, "Dark Mode Colors")
    dmHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - dmHeader.gap

    local dmHealthColor = GUI:CreateFormColorPicker(content, "Health Color", "darkModeHealthColor", general, onChange)
    dmHealthColor:SetPoint("TOPLEFT", PAD, y)
    dmHealthColor:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local dmHealthOpacity = GUI:CreateFormSlider(content, "Health Opacity", 0, 1, 0.05, "darkModeHealthOpacity", general, onChange)
    dmHealthOpacity:SetPoint("TOPLEFT", PAD, y)
    dmHealthOpacity:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    local dmBgColor = GUI:CreateFormColorPicker(content, "Dark Mode BG Color", "darkModeBgColor", general, onChange)
    dmBgColor:SetPoint("TOPLEFT", PAD, y)
    dmBgColor:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local dmBgOpacity = GUI:CreateFormSlider(content, "Dark Mode BG Opacity", 0, 1, 0.05, "darkModeBgOpacity", general, onChange)
    dmBgOpacity:SetPoint("TOPLEFT", PAD, y)
    dmBgOpacity:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    ---------------------------------------------------------------------------
    -- Font
    ---------------------------------------------------------------------------
    local fontHeader = GUI:CreateSectionHeader(content, "Font")
    fontHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - fontHeader.gap

    local fontDrop = GUI:CreateFormDropdown(content, "Font", GetFontList(), "font", general, onChange)
    fontDrop:SetPoint("TOPLEFT", PAD, y)
    fontDrop:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - DROP_ROW

    local fontSizeSlider = GUI:CreateFormSlider(content, "Font Size", 8, 20, 1, "fontSize", general, onChange)
    fontSizeSlider:SetPoint("TOPLEFT", PAD, y)
    fontSizeSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    ---------------------------------------------------------------------------
    -- Tooltips
    ---------------------------------------------------------------------------
    local tooltipCheck = GUI:CreateFormCheckbox(content, "Show Tooltips on Hover", "showTooltips", general, onChange)
    tooltipCheck:SetPoint("TOPLEFT", PAD, y)
    tooltipCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Portrait
    ---------------------------------------------------------------------------
    local portrait = gfdb.portrait
    if not portrait then gfdb.portrait = {} portrait = gfdb.portrait end

    local portraitHeader = GUI:CreateSectionHeader(content, "Portrait")
    portraitHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - portraitHeader.gap

    local portraitCheck = GUI:CreateFormCheckbox(content, "Show Portrait", "showPortrait", portrait, onChange)
    portraitCheck:SetPoint("TOPLEFT", PAD, y)
    portraitCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    if portrait.showPortrait then
        local portraitSide = GUI:CreateFormDropdown(content, "Portrait Side", ANCHOR_SIDE_OPTIONS, "portraitSide", portrait, onChange)
        portraitSide:SetPoint("TOPLEFT", PAD, y)
        portraitSide:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local portraitSize = GUI:CreateFormSlider(content, "Portrait Size", 16, 60, 1, "portraitSize", portrait, onChange)
        portraitSize:SetPoint("TOPLEFT", PAD, y)
        portraitSize:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT
    end

    content:SetHeight(math.abs(y) + 10)
end

---------------------------------------------------------------------------
-- CONTEXT SETTINGS (per-context: party/raid)
-- Layout + Dimensions + Range + Pets + Spotlight(raid) + Preview/Copy
---------------------------------------------------------------------------
local function BuildContextSettings(content, gfdb, onChange)
    local y = -10
    local isRaid = rawget(gfdb, "_composerMode") == "raid"
    if isRaid then SetRaidSearchContext("Settings") else SetPartySearchContext("Settings") end

    ---------------------------------------------------------------------------
    -- Layout
    ---------------------------------------------------------------------------
    local layout = gfdb.layout
    if not layout then gfdb.layout = {} layout = gfdb.layout end
    local position = gfdb.position
    if not position then gfdb.position = {} position = gfdb.position end

    local layoutHeader = GUI:CreateSectionHeader(content, "Layout")
    layoutHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - layoutHeader.gap

    local growDrop = GUI:CreateFormDropdown(content, "Grow Direction", GROW_OPTIONS, "growDirection", layout, onChange)
    growDrop:SetPoint("TOPLEFT", PAD, y)
    growDrop:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - DROP_ROW

    local raidGroupBy = isRaid and (layout.groupBy or "GROUP") or nil
    local isFlat = (raidGroupBy == "NONE")

    if isRaid and not isFlat then
        local groupGrowDrop = GUI:CreateFormDropdown(content, "Group Grow Direction", GROUP_GROW_OPTIONS, "groupGrowDirection", layout, onChange)
        groupGrowDrop:SetPoint("TOPLEFT", PAD, y)
        groupGrowDrop:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - DROP_ROW
    end

    local spacingSlider = GUI:CreateFormSlider(content, "Frame Spacing", 0, 10, 1, "spacing", layout, onChange)
    spacingSlider:SetPoint("TOPLEFT", PAD, y)
    spacingSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    if isRaid and not isFlat then
        local groupSpacingSlider = GUI:CreateFormSlider(content, "Group Spacing", 0, 30, 1, "groupSpacing", layout, onChange)
        groupSpacingSlider:SetPoint("TOPLEFT", PAD, y)
        groupSpacingSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT
    end

    if not isRaid then
        local showPlayerCheck = GUI:CreateFormCheckbox(content, "Show Player in Group", "showPlayer", layout, onChange)
        showPlayerCheck:SetPoint("TOPLEFT", PAD, y)
        showPlayerCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showSoloCheck = GUI:CreateFormCheckbox(content, "Show Player Frame When Solo", "showSolo", layout, onChange)
        showSoloCheck:SetPoint("TOPLEFT", PAD, y)
        showSoloCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Self-first (shared setting — proxy routes non-visual keys to top-level DB)
        local selfFirstCheck = GUI:CreateFormCheckbox(content, "Always Show Self First", "selfFirst", gfdb, onChange)
        selfFirstCheck:SetPoint("TOPLEFT", PAD, y)
        selfFirstCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local sortHeader = GUI:CreateSectionHeader(content, "Sorting")
        sortHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - sortHeader.gap

        local roleSortCheck = GUI:CreateFormCheckbox(content, "Sort by Role (Tank > Healer > DPS)", "sortByRole", layout, onChange)
        roleSortCheck:SetPoint("TOPLEFT", PAD, y)
        roleSortCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    end

    -- Sorting (raid only)
    if isRaid then
        local sortHeader = GUI:CreateSectionHeader(content, "Sorting")
        sortHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - sortHeader.gap

        local groupByDrop = GUI:CreateFormDropdown(content, "Group By", GROUP_BY_OPTIONS, "groupBy", layout, onChange)
        groupByDrop:SetPoint("TOPLEFT", PAD, y)
        groupByDrop:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local groupBy = layout.groupBy or "GROUP"
        if groupBy == "NONE" then
            local flatSlider = GUI:CreateFormSlider(content, "Units Per Column", 1, 40, 1, "unitsPerFlat", layout, onChange)
            flatSlider:SetPoint("TOPLEFT", PAD, y)
            flatSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            y = y - SLIDER_HEIGHT
        end

        local sortDrop = GUI:CreateFormDropdown(content, "Sort Method", SORT_OPTIONS, "sortMethod", layout, onChange)
        sortDrop:SetPoint("TOPLEFT", PAD, y)
        sortDrop:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local roleSortCheck = GUI:CreateFormCheckbox(content, "Sort by Role (Tank > Healer > DPS)", "sortByRole", layout, onChange)
        roleSortCheck:SetPoint("TOPLEFT", PAD, y)
        roleSortCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    end

    ---------------------------------------------------------------------------
    -- Dimensions
    ---------------------------------------------------------------------------
    local dims = gfdb.dimensions
    if not dims then gfdb.dimensions = {} dims = gfdb.dimensions end

    local dimsHeader = GUI:CreateSectionHeader(content, "Dimensions")
    dimsHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - dimsHeader.gap

    if not isRaid then
        local partyW = GUI:CreateFormSlider(content, "Width", 80, 400, 1, "partyWidth", dims, onChange)
        partyW:SetPoint("TOPLEFT", PAD, y)
        partyW:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local partyH = GUI:CreateFormSlider(content, "Height", 16, 80, 1, "partyHeight", dims, onChange)
        partyH:SetPoint("TOPLEFT", PAD, y)
        partyH:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT
    else
        local smallHeader = GUI:CreateSectionHeader(content, "Small Raid (6-15 players)")
        smallHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - smallHeader.gap

        local smallW = GUI:CreateFormSlider(content, "Width", 60, 400, 1, "smallRaidWidth", dims, onChange)
        smallW:SetPoint("TOPLEFT", PAD, y)
        smallW:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local smallH = GUI:CreateFormSlider(content, "Height", 14, 100, 1, "smallRaidHeight", dims, onChange)
        smallH:SetPoint("TOPLEFT", PAD, y)
        smallH:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local medHeader = GUI:CreateSectionHeader(content, "Medium Raid (16-25 players)")
        medHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - medHeader.gap

        local medW = GUI:CreateFormSlider(content, "Width", 50, 300, 1, "mediumRaidWidth", dims, onChange)
        medW:SetPoint("TOPLEFT", PAD, y)
        medW:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local medH = GUI:CreateFormSlider(content, "Height", 12, 100, 1, "mediumRaidHeight", dims, onChange)
        medH:SetPoint("TOPLEFT", PAD, y)
        medH:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local largeHeader = GUI:CreateSectionHeader(content, "Large Raid (26-40 players)")
        largeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - largeHeader.gap

        local largeW = GUI:CreateFormSlider(content, "Width", 40, 250, 1, "largeRaidWidth", dims, onChange)
        largeW:SetPoint("TOPLEFT", PAD, y)
        largeW:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local largeH = GUI:CreateFormSlider(content, "Height", 10, 100, 1, "largeRaidHeight", dims, onChange)
        largeH:SetPoint("TOPLEFT", PAD, y)
        largeH:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT
    end

    -- Position
    local posHeader = GUI:CreateSectionHeader(content, "Position")
    posHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - posHeader.gap

    local xSlider = GUI:CreateFormSlider(content, "X Offset", -800, 800, 1, "offsetX", position, onChange)
    xSlider:SetPoint("TOPLEFT", PAD, y)
    xSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    local ySlider = GUI:CreateFormSlider(content, "Y Offset", -500, 500, 1, "offsetY", position, onChange)
    ySlider:SetPoint("TOPLEFT", PAD, y)
    ySlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - SLIDER_HEIGHT

    ---------------------------------------------------------------------------
    -- Range Check
    ---------------------------------------------------------------------------
    local range = gfdb.range
    if not range then gfdb.range = {} range = gfdb.range end

    local rangeHeader = GUI:CreateSectionHeader(content, "Range Check")
    rangeHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - rangeHeader.gap

    local rangeCheck = GUI:CreateFormCheckbox(content, "Enable Range Check (dim out-of-range members)", "enabled", range, onChange)
    rangeCheck:SetPoint("TOPLEFT", PAD, y)
    rangeCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    if range.enabled then
        local rangeAlpha = GUI:CreateFormSlider(content, "Out-of-Range Alpha", 0.1, 0.8, 0.05, "outOfRangeAlpha", range, onChange)
        rangeAlpha:SetPoint("TOPLEFT", PAD, y)
        rangeAlpha:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT
    end

    ---------------------------------------------------------------------------
    -- Pet Frames
    ---------------------------------------------------------------------------
    local pets = gfdb.pets
    if not pets then gfdb.pets = {} pets = gfdb.pets end

    local petHeader = GUI:CreateSectionHeader(content, "Pet Frames")
    petHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - petHeader.gap

    local petCheck = GUI:CreateFormCheckbox(content, "Enable Pet Frames", "enabled", pets, onChange)
    petCheck:SetPoint("TOPLEFT", PAD, y)
    petCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    if pets.enabled then
        local petWidth = GUI:CreateFormSlider(content, "Pet Frame Width", 40, 200, 1, "width", pets, onChange)
        petWidth:SetPoint("TOPLEFT", PAD, y)
        petWidth:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local petHeight = GUI:CreateFormSlider(content, "Pet Frame Height", 10, 40, 1, "height", pets, onChange)
        petHeight:SetPoint("TOPLEFT", PAD, y)
        petHeight:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local petAnchor = GUI:CreateFormDropdown(content, "Pet Anchor", PET_ANCHOR_OPTIONS, "anchorTo", pets, onChange)
        petAnchor:SetPoint("TOPLEFT", PAD, y)
        petAnchor:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - DROP_ROW
    end

    ---------------------------------------------------------------------------
    -- Spotlight (raid only)
    ---------------------------------------------------------------------------
    if isRaid then
        local spot = gfdb.spotlight
        if not spot then gfdb.spotlight = {} spot = gfdb.spotlight end

        local spotHeader = GUI:CreateSectionHeader(content, "Spotlight")
        spotHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - spotHeader.gap

        local spotDesc = GUI:CreateLabel(content, "Pin specific raid members (by role or name) to a separate highlighted group for tank-watch or healing assignment awareness.", 11, C.textMuted)
        spotDesc:SetPoint("TOPLEFT", PAD, y)
        spotDesc:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        spotDesc:SetJustifyH("LEFT")
        y = y - 30

        local spotCheck = GUI:CreateFormCheckbox(content, "Enable Spotlight", "enabled", spot, onChange)
        spotCheck:SetPoint("TOPLEFT", PAD, y)
        spotCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if spot.enabled then
            local spotGrow = GUI:CreateFormDropdown(content, "Spotlight Grow Direction", GROW_OPTIONS, "growDirection", spot, onChange)
            spotGrow:SetPoint("TOPLEFT", PAD, y)
            spotGrow:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            y = y - DROP_ROW

            local spotSpacing = GUI:CreateFormSlider(content, "Spotlight Spacing", 0, 10, 1, "spacing", spot, onChange)
            spotSpacing:SetPoint("TOPLEFT", PAD, y)
            spotSpacing:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            y = y - SLIDER_HEIGHT
        end
    end

    ---------------------------------------------------------------------------
    -- Copy All
    ---------------------------------------------------------------------------
    local srcLabel = isRaid and "Raid" or "Party"
    local dstLabel = isRaid and "Party" or "Raid"

    local copyAllBtn = GUI:CreateButton(content, "Copy All: " .. srcLabel .. " -> " .. dstLabel, 220, 28, function()
        GUI:ShowConfirmation({
            title = "Copy All Settings",
            message = "This will overwrite ALL " .. dstLabel .. " visual settings (layout, health, power, auras, indicators, etc.) with " .. srcLabel .. " settings. Continue?",
            acceptText = "Copy All",
            cancelText = "Cancel",
            isDestructive = true,
            onAccept = function()
                local src = gfdb.party
                local dst = gfdb.raid
                if isRaid then src, dst = dst, src end
                if not src or not dst then return end
                local function deepCopy(s)
                    if type(s) ~= "table" then return s end
                    local copy = {}
                    for k, v in pairs(s) do copy[k] = deepCopy(v) end
                    return copy
                end
                for key in pairs(VISUAL_DB_KEYS) do
                    if src[key] then
                        dst[key] = deepCopy(src[key])
                    end
                end
                RefreshGF()
            end,
        })
    end)
    copyAllBtn:SetPoint("TOPLEFT", PAD, y)
    y = y - 36

    content:SetHeight(math.abs(y) + 20)
end


---------------------------------------------------------------------------
-- CLICK-CAST SETTINGS
---------------------------------------------------------------------------
local function BuildClickCastSettings(content, gfdb, onChange)
    local y = -10
    SetGeneralSearchContext("Click-Cast")

    local cc = gfdb.clickCast
    if not cc then gfdb.clickCast = {} cc = gfdb.clickCast end

    local enableCheck = GUI:CreateFormCheckbox(content, "Enable Click-Casting", "enabled", cc, function()
        RefreshGF()
        if cc.enabled then
            print("|cFF34D399[QUI]|r Click-casting enabled. Reload recommended.")
        end
    end)
    enableCheck:SetPoint("TOPLEFT", PAD, y)
    enableCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local cliqueNote = GUI:CreateLabel(content, "Note: If Clique addon is loaded, QUI click-casting is disabled by default to avoid conflicts.", 11, C.textMuted)
    cliqueNote:SetPoint("TOPLEFT", PAD, y)
    cliqueNote:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    cliqueNote:SetJustifyH("LEFT")
    y = y - 30

    local perSpecCheck = GUI:CreateFormCheckbox(content, "Per-Spec Bindings", "perSpec", cc, RefreshGF)
    perSpecCheck:SetPoint("TOPLEFT", PAD, y)
    perSpecCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local smartResCheck = GUI:CreateFormCheckbox(content, "Smart Resurrection (auto-swap to res on dead targets)", "smartRes", cc, RefreshGF)
    smartResCheck:SetPoint("TOPLEFT", PAD, y)
    smartResCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local tooltipCheck = GUI:CreateFormCheckbox(content, "Show Binding Tooltip on Hover", "showTooltip", cc, RefreshGF)
    tooltipCheck:SetPoint("TOPLEFT", PAD, y)
    tooltipCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Unit Frame click-cast toggles
    if not cc.unitFrames then cc.unitFrames = {} end
    local ufLabel = GUI:CreateLabel(content, "Also apply click-casting to unit frames:", 11, C.textMuted)
    ufLabel:SetPoint("TOPLEFT", PAD, y)
    ufLabel:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    ufLabel:SetJustifyH("LEFT")
    y = y - 22

    local ufFrames = {
        { key = "player",       label = "Player" },
        { key = "target",       label = "Target" },
        { key = "targettarget", label = "Target of Target" },
        { key = "focus",        label = "Focus" },
        { key = "pet",          label = "Pet" },
    }

    local refreshClickCast = function()
        local GFCC_ref = ns.QUI_GroupFrameClickCast
        if GFCC_ref and GFCC_ref:IsEnabled() and not InCombatLockdown() then
            GFCC_ref:RefreshBindings()
        end
    end

    for _, info in ipairs(ufFrames) do
        local ufCheck = GUI:CreateFormCheckbox(content, info.label, info.key, cc.unitFrames, refreshClickCast)
        ufCheck:SetPoint("TOPLEFT", PAD, y)
        ufCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    end

    ---------------------------------------------------------------------------
    -- Global Ping Keybinds section
    ---------------------------------------------------------------------------
    local pingHeader = GUI:CreateSectionHeader(content, "Global Ping Keybinds")
    pingHeader:SetPoint("TOPLEFT", PAD, y)
    pingHeader:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - pingHeader.gap

    local pingNote = GUI:CreateLabel(content, "These keybinds work everywhere: nameplates, world mouseover, or current target. Pings the unit you're looking at.", 11, C.textMuted)
    pingNote:SetPoint("TOPLEFT", PAD, y)
    pingNote:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    pingNote:SetJustifyH("LEFT")
    y = y - 30

    local PING_KEYBIND_ENTRIES = {
        { binding = "QUI_PING",         label = "Ping (Contextual)" },
        { binding = "QUI_PING_ASSIST",  label = "Ping: Assist" },
        { binding = "QUI_PING_ATTACK",  label = "Ping: Attack" },
        { binding = "QUI_PING_WARNING", label = "Ping: Warning" },
        { binding = "QUI_PING_ONMYWAY", label = "Ping: On My Way" },
    }

    local function CreatePingKeybindRow(parent, entry, yPos)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(28)
        row:SetPoint("TOPLEFT", PAD, yPos)
        row:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", 0, 0)
        label:SetWidth(180)
        label:SetJustifyH("LEFT")
        label:SetText(entry.label)
        label:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local captureBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        captureBtn:SetPoint("LEFT", label, "RIGHT", 8, 0)
        captureBtn:SetSize(160, 24)
        ApplyPixelBackdrop(captureBtn, 1, true)
        captureBtn:SetBackdropColor(0.08, 0.08, 0.08, 1)
        captureBtn:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        local keyText = captureBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        keyText:SetPoint("CENTER", 0, 0)

        local function UpdateKeyText()
            local key1 = GetBindingKey(entry.binding)
            if key1 then
                keyText:SetText(key1)
                keyText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            else
                keyText:SetText("Not bound")
                keyText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            end
        end
        UpdateKeyText()

        local clearBtn = GUI:CreateButton(row, "Clear", 50, 24, function()
            local key1, key2 = GetBindingKey(entry.binding)
            if key1 then SetBinding(key1) end
            if key2 then SetBinding(key2) end
            SaveBindings(GetCurrentBindingSet())
            UpdateKeyText()
        end)
        clearBtn:SetPoint("LEFT", captureBtn, "RIGHT", 6, 0)

        captureBtn.isCapturing = false
        captureBtn:EnableKeyboard(false)
        captureBtn:SetScript("OnClick", function(self)
            if self.isCapturing then
                self.isCapturing = false
                self:EnableKeyboard(false)
                self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
                UpdateKeyText()
                return
            end
            self.isCapturing = true
            self:EnableKeyboard(true)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            keyText:SetText("Press a key...")
            keyText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        captureBtn:SetScript("OnKeyDown", function(self, key)
            if not self.isCapturing then return end
            if key == "ESCAPE" then
                self.isCapturing = false
                self:EnableKeyboard(false)
                self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
                UpdateKeyText()
                return
            end
            -- Ignore bare modifier keys
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
               or key == "LALT" or key == "RALT" then
                return
            end
            -- Build full key string with modifiers
            local mods = ""
            if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
            if IsControlKeyDown() then mods = mods .. "CTRL-" end
            if IsAltKeyDown() then mods = mods .. "ALT-" end
            local fullKey = mods .. key

            -- Clear any previous binding for this action
            local oldKey1, oldKey2 = GetBindingKey(entry.binding)
            if oldKey1 then SetBinding(oldKey1) end
            if oldKey2 then SetBinding(oldKey2) end

            SetBinding(fullKey, entry.binding)
            SaveBindings(GetCurrentBindingSet())

            self.isCapturing = false
            self:EnableKeyboard(false)
            self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            UpdateKeyText()
        end)
        captureBtn:SetScript("OnEnter", function(self)
            if not self.isCapturing then self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.7) end
        end)
        captureBtn:SetScript("OnLeave", function(self)
            if not self.isCapturing then self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1) end
        end)

        return row
    end

    for _, entry in ipairs(PING_KEYBIND_ENTRIES) do
        CreatePingKeybindRow(content, entry, y)
        y = y - 30
    end

    y = y - 5

    local GFCC = ns.QUI_GroupFrameClickCast

    local ACTION_TYPE_OPTIONS = {
        { value = "spell",        text = "Spell" },
        { value = "macro",        text = "Macro" },
        { value = "target",       text = "Target Unit" },
        { value = "focus",        text = "Set Focus" },
        { value = "assist",       text = "Assist" },
        { value = "menu",         text = "Unit Menu" },
        { value = "ping",         text = "Ping (Contextual)" },
        { value = "ping_assist",  text = "Ping: Assist" },
        { value = "ping_attack",  text = "Ping: Attack" },
        { value = "ping_warning", text = "Ping: Warning" },
        { value = "ping_onmyway", text = "Ping: On My Way" },
    }
    local BINDING_TYPE_OPTIONS = {
        { value = "mouse", text = "Mouse Button" },
        { value = "key",   text = "Keyboard Key" },
    }
    local BUTTON_OPTIONS = {
        { value = "LeftButton",   text = "Left Click" },
        { value = "RightButton",  text = "Right Click" },
        { value = "MiddleButton", text = "Middle Click" },
        { value = "Button4",      text = "Button 4" },
        { value = "Button5",      text = "Button 5" },
    }
    local MOD_OPTIONS = {
        { value = "",              text = "None" },
        { value = "shift",         text = "Shift" },
        { value = "ctrl",          text = "Ctrl" },
        { value = "alt",           text = "Alt" },
        { value = "shift-ctrl",    text = "Shift+Ctrl" },
        { value = "shift-alt",     text = "Shift+Alt" },
        { value = "ctrl-alt",      text = "Ctrl+Alt" },
        { value = "shift-ctrl-alt", text = "Shift+Ctrl+Alt" },
    }
    local ACTION_FALLBACK_ICONS = {
        target       = "Interface\\Icons\\Ability_Hunter_SniperShot",
        focus        = "Interface\\Icons\\Ability_TrickShot",
        assist       = "Interface\\Icons\\Ability_Hunter_MasterMarksman",
        macro        = "Interface\\Icons\\INV_Misc_Note_01",
        menu         = "Interface\\Icons\\INV_Misc_GroupNeedMore",
        ping         = "Interface\\Icons\\Ping_Chat_Default",
        ping_assist  = "Interface\\Icons\\Ping_Chat_Assist",
        ping_attack  = "Interface\\Icons\\Ping_Chat_Attack",
        ping_warning = "Interface\\Icons\\Ping_Chat_Warning",
        ping_onmyway = "Interface\\Icons\\Ping_Chat_OnMyWay",
    }
    local PING_DISPLAY_NAMES = {
        ping         = "Ping",
        ping_assist  = "Ping: Assist",
        ping_attack  = "Ping: Attack",
        ping_warning = "Ping: Warning",
        ping_onmyway = "Ping: On My Way",
    }

    -- Spec context label
    local specLabel = GUI:CreateLabel(content, "", 11, C.accent)
    specLabel:SetPoint("TOPLEFT", PAD, y)
    specLabel:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    specLabel:SetJustifyH("LEFT")
    specLabel:Hide()

    local function UpdateSpecLabel()
        if cc.perSpec then
            local specIndex = GetSpecialization()
            if specIndex then
                local _, specName = GetSpecializationInfo(specIndex)
                if specName then
                    specLabel:SetText("Editing bindings for: " .. specName)
                    specLabel:Show()
                    return
                end
            end
        end
        specLabel:Hide()
    end
    UpdateSpecLabel()
    if specLabel:IsShown() then y = y - 20 end

    -- Current bindings list
    local bindingsHeader = GUI:CreateSectionHeader(content, "Current Bindings")
    bindingsHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - bindingsHeader.gap

    local bindingListFrame = CreateFrame("Frame", nil, content)
    bindingListFrame:SetPoint("TOPLEFT", PAD, y)
    bindingListFrame:SetSize(400, 20)

    local RefreshBindingList

    -- Add binding form
    local addContainer = CreateFrame("Frame", nil, content)
    addContainer:SetPoint("TOPLEFT", bindingListFrame, "BOTTOMLEFT", 0, -10)
    addContainer:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    addContainer:SetHeight(400)
    addContainer:EnableMouse(false)

    local addHeader = GUI:CreateSectionHeader(addContainer, "Add Binding")
    addHeader:SetPoint("TOPLEFT", 0, 0)
    local ay = -addHeader.gap

    -- Drop zone for spellbook/macro drag
    local dropZone = CreateFrame("Button", nil, addContainer, "BackdropTemplate")
    dropZone:RegisterForClicks("LeftButtonUp")
    SetHeightPx(dropZone, 68)
    dropZone:SetPoint("TOPLEFT", 0, ay)
    dropZone:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    ApplyPixelBackdrop(dropZone, 1, true)
    dropZone:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.8)
    dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

    local dropLabel = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropLabel:SetPoint("CENTER", 0, 0)
    dropLabel:SetText("Drop a spell or macro here")
    dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

    local addState = { bindingType = "mouse", button = "LeftButton", key = nil, modifiers = "", actionType = "spell", spellName = "", macroText = "" }
    local spellInput, macroInput, actionDrop
    local spellInputContainer, macroInputContainer
    local mouseButtonContainer, keyCaptureContainer

    local function HandleCursorDrop()
        local cursorType, id1, id2, _, id4 = GetCursorInfo()
        if not cursorType then return false end

        if cursorType == "spell" then
            local slotIndex, bookType, spellID = id1, id2 or "spell", id4
            if not spellID and slotIndex then
                local spellBank = (bookType == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                local info = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                if info then spellID = info.spellID end
            end
            if spellID then
                local overrideID = C_Spell.GetOverrideSpell(spellID)
                if overrideID and overrideID ~= spellID then spellID = overrideID end
                local name = C_Spell.GetSpellName(spellID)
                if name then
                    addState.spellName = name
                    addState.actionType = "spell"
                    if spellInput then spellInput:SetText(name) end
                    if actionDrop then actionDrop.SetValue("spell", true) end
                    if spellInputContainer then spellInputContainer:Show() end
                    if macroInputContainer then macroInputContainer:Hide() end
                end
            end
            ClearCursor()
            return true
        elseif cursorType == "macro" then
            local macroIndex = id1
            if macroIndex then
                local name, _, body = GetMacroInfo(macroIndex)
                if body then
                    addState.actionType = "macro"
                    addState.macroText = body
                    addState.spellName = name or "Macro"
                    if macroInput then macroInput:SetText(body) end
                    if actionDrop then actionDrop.SetValue("macro", true) end
                    if macroInputContainer then macroInputContainer:Show() end
                    if spellInputContainer then spellInputContainer:Hide() end
                end
            end
            ClearCursor()
            return true
        end
        return false
    end

    dropZone:SetScript("OnReceiveDrag", HandleCursorDrop)
    dropZone:SetScript("OnClick", function()
        if GetCursorInfo() then HandleCursorDrop() end
    end)
    dropZone:SetScript("OnEnter", function(self)
        if GetCursorInfo() then
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            dropLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end
    end)
    dropZone:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
        dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    end)
    ay = ay - 78

    -- Binding type dropdown
    local bindingTypeDrop = GUI:CreateFormDropdown(addContainer, "Binding Type", BINDING_TYPE_OPTIONS, "bindingType", addState, function(val)
        addState.bindingType = val
        if mouseButtonContainer then mouseButtonContainer:SetShown(val == "mouse") end
        if keyCaptureContainer then keyCaptureContainer:SetShown(val == "key") end
    end)
    bindingTypeDrop:SetPoint("TOPLEFT", 0, ay)
    bindingTypeDrop:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    ay = ay - FORM_ROW

    -- Mouse button dropdown
    mouseButtonContainer = CreateFrame("Frame", nil, addContainer)
    mouseButtonContainer:SetHeight(FORM_ROW)
    mouseButtonContainer:SetPoint("TOPLEFT", 0, ay)
    mouseButtonContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)

    local buttonDrop = GUI:CreateFormDropdown(mouseButtonContainer, "Mouse Button", BUTTON_OPTIONS, "button", addState)
    buttonDrop:SetPoint("TOPLEFT", 0, 0)
    buttonDrop:SetPoint("RIGHT", mouseButtonContainer, "RIGHT", 0, 0)

    -- Keyboard key capture
    keyCaptureContainer = CreateFrame("Frame", nil, addContainer)
    keyCaptureContainer:SetHeight(FORM_ROW)
    keyCaptureContainer:SetPoint("TOPLEFT", 0, ay)
    keyCaptureContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    keyCaptureContainer:Hide()

    local keyLabel = keyCaptureContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyLabel:SetPoint("LEFT", 0, 0)
    keyLabel:SetText("Key")
    keyLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local keyCaptureBtn = CreateFrame("Button", nil, keyCaptureContainer, "BackdropTemplate")
    keyCaptureBtn:SetPoint("LEFT", keyCaptureContainer, "LEFT", 180, 0)
    keyCaptureBtn:SetPoint("RIGHT", keyCaptureContainer, "RIGHT", 0, 0)
    SetHeightPx(keyCaptureBtn, 26)
    ApplyPixelBackdrop(keyCaptureBtn, 1, true)
    keyCaptureBtn:SetBackdropColor(0.08, 0.08, 0.08, 1)
    keyCaptureBtn:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local keyCaptureText = keyCaptureBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyCaptureText:SetPoint("CENTER", 0, 0)
    keyCaptureText:SetText("Click to bind a key")
    keyCaptureText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

    local IGNORE_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }

    keyCaptureBtn:SetScript("OnClick", function(self)
        self.isCapturing = true
        keyCaptureText:SetText("Press a key...")
        keyCaptureText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        self:EnableKeyboard(true)
    end)
    keyCaptureBtn:SetScript("OnKeyDown", function(self, key)
        if not self.isCapturing then self:SetPropagateKeyboardInput(true) return end
        self:SetPropagateKeyboardInput(false)
        if IGNORE_KEYS[key] then self:SetPropagateKeyboardInput(true) return end
        if key == "ESCAPE" then
            self.isCapturing = false
            self:EnableKeyboard(false)
            self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            if addState.key then
                keyCaptureText:SetText(addState.key)
                keyCaptureText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            else
                keyCaptureText:SetText("Click to bind a key")
                keyCaptureText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            end
            return
        end
        addState.key = key
        self.isCapturing = false
        self:EnableKeyboard(false)
        self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        keyCaptureText:SetText(key)
        keyCaptureText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end)
    keyCaptureBtn:SetScript("OnEnter", function(self)
        if not self.isCapturing then self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.7) end
    end)
    keyCaptureBtn:SetScript("OnLeave", function(self)
        if not self.isCapturing then self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1) end
    end)
    ay = ay - FORM_ROW

    -- Modifier dropdown
    local modDrop = GUI:CreateFormDropdown(addContainer, "Modifier", MOD_OPTIONS, "modifiers", addState)
    modDrop:SetPoint("TOPLEFT", 0, ay)
    modDrop:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    ay = ay - FORM_ROW

    -- Action type dropdown
    actionDrop = GUI:CreateFormDropdown(addContainer, "Action Type", ACTION_TYPE_OPTIONS, "actionType", addState, function(val)
        addState.actionType = val
        if spellInputContainer then spellInputContainer:SetShown(val == "spell") end
        if macroInputContainer then macroInputContainer:SetShown(val == "macro") end
    end)
    actionDrop:SetPoint("TOPLEFT", 0, ay)
    actionDrop:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    ay = ay - FORM_ROW

    -- Spell name editbox
    spellInputContainer = CreateFrame("Frame", nil, addContainer)
    spellInputContainer:SetHeight(FORM_ROW)
    spellInputContainer:SetPoint("TOPLEFT", 0, ay)
    spellInputContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)

    local spellLabel = spellInputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellLabel:SetPoint("LEFT", 0, 0)
    spellLabel:SetText("Spell Name")
    spellLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local spellInputBg = CreateFrame("Frame", nil, spellInputContainer, "BackdropTemplate")
    spellInputBg:SetPoint("LEFT", spellInputContainer, "LEFT", 180, 0)
    spellInputBg:SetPoint("RIGHT", spellInputContainer, "RIGHT", 0, 0)
    SetHeightPx(spellInputBg, 24)
    ApplyPixelBackdrop(spellInputBg, 1, true)
    spellInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
    spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    spellInput = CreateFrame("EditBox", nil, spellInputBg)
    spellInput:SetPoint("LEFT", 8, 0)
    spellInput:SetPoint("RIGHT", -8, 0)
    spellInput:SetHeight(22)
    spellInput:SetAutoFocus(false)
    spellInput:SetFont(GUI.FONT_PATH, 11, "")
    spellInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    spellInput:SetText("")
    spellInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    spellInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    spellInput:SetScript("OnTextChanged", function(self) addState.spellName = self:GetText() end)
    spellInput:SetScript("OnEditFocusGained", function() spellInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    spellInput:SetScript("OnEditFocusLost", function() spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1) end)
    ay = ay - FORM_ROW

    -- Macro text editbox
    macroInputContainer = CreateFrame("Frame", nil, addContainer)
    macroInputContainer:SetHeight(FORM_ROW)
    macroInputContainer:SetPoint("TOPLEFT", 0, ay)
    macroInputContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
    macroInputContainer:Hide()

    local macroLabel = macroInputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    macroLabel:SetPoint("LEFT", 0, 0)
    macroLabel:SetText("Macro Text")
    macroLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local macroInputBg = CreateFrame("Frame", nil, macroInputContainer, "BackdropTemplate")
    macroInputBg:SetPoint("LEFT", macroInputContainer, "LEFT", 180, 0)
    macroInputBg:SetPoint("RIGHT", macroInputContainer, "RIGHT", 0, 0)
    SetHeightPx(macroInputBg, 24)
    ApplyPixelBackdrop(macroInputBg, 1, true)
    macroInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
    macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    macroInput = CreateFrame("EditBox", nil, macroInputBg)
    macroInput:SetPoint("LEFT", 8, 0)
    macroInput:SetPoint("RIGHT", -8, 0)
    macroInput:SetHeight(22)
    macroInput:SetAutoFocus(false)
    macroInput:SetFont(GUI.FONT_PATH, 11, "")
    macroInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    macroInput:SetText("")
    macroInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    macroInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    macroInput:SetScript("OnTextChanged", function(self) addState.macroText = self:GetText() end)
    macroInput:SetScript("OnEditFocusGained", function() macroInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    macroInput:SetScript("OnEditFocusLost", function() macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1) end)

    local function RefreshClickCastPixelFrames()
        SetHeightPx(dropZone, 68)
        ApplyPixelBackdrop(dropZone, 1, true)
        dropZone:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.8)
        if GetCursorInfo() then
            dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
        end

        SetHeightPx(keyCaptureBtn, 26)
        ApplyPixelBackdrop(keyCaptureBtn, 1, true)
        keyCaptureBtn:SetBackdropColor(0.08, 0.08, 0.08, 1)
        if keyCaptureBtn.isCapturing then
            keyCaptureBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            keyCaptureBtn:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end

        SetHeightPx(spellInputBg, 24)
        ApplyPixelBackdrop(spellInputBg, 1, true)
        spellInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        if spellInput and spellInput:HasFocus() then
            spellInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end

        SetHeightPx(macroInputBg, 24)
        ApplyPixelBackdrop(macroInputBg, 1, true)
        macroInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        if macroInput and macroInput:HasFocus() then
            macroInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end
    end

    -- Add Binding button
    local addBtnY = ay - FORM_ROW
    local addBtn = GUI:CreateButton(addContainer, "Add Binding", 130, 26, function()
        local actionType = addState.actionType
        if type(actionType) ~= "string" then print("|cFFFF5555[QUI]|r Invalid action type. Please re-select.") return end
        local newBinding = { modifiers = addState.modifiers, actionType = actionType }
        if addState.bindingType == "key" then
            if not addState.key or addState.key == "" then print("|cFFFF5555[QUI]|r Press a key to bind first.") return end
            newBinding.key = addState.key
        else
            newBinding.button = addState.button
        end
        if actionType == "spell" then
            local name = addState.spellName
            if not name or name == "" then print("|cFFFF5555[QUI]|r Enter a spell name.") return end
            local spellID = C_Spell.GetSpellIDForSpellIdentifier(name)
            if not spellID then print("|cFFFF5555[QUI]|r Spell not found: " .. name) return end
            newBinding.spell = C_Spell.GetSpellName(spellID) or name
        elseif actionType == "macro" then
            local text = addState.macroText
            if not text or text == "" then print("|cFFFF5555[QUI]|r Enter macro text.") return end
            newBinding.spell = "Macro"
            newBinding.macro = text
        else
            newBinding.spell = actionType
        end
        local ok, err = GFCC:AddBinding(newBinding)
        if not ok then print("|cFFFF5555[QUI]|r " .. (err or "Failed to add binding.")) return end
        addState.spellName = ""
        addState.macroText = ""
        addState.key = nil
        spellInput:SetText("")
        macroInput:SetText("")
        keyCaptureText:SetText("Click to bind a key")
        keyCaptureText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        RefreshBindingList()
    end)
    addBtn:SetPoint("TOPLEFT", 0, addBtnY)
    addContainer:SetHeight(math.abs(addBtnY) + 36)

    -- Refresh binding list
    RefreshBindingList = function()
        for _, child in ipairs({bindingListFrame:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        UpdateSpecLabel()
        local buttonNames = GFCC:GetButtonNames()
        local modLabels  = GFCC:GetModifierLabels()
        local bindings   = GFCC:GetEditableBindings()
        local listY = 0
        if #bindings == 0 then
            local emptyLabel = CreateFrame("Frame", nil, bindingListFrame)
            emptyLabel:SetSize(300, 28)
            emptyLabel:SetPoint("TOPLEFT", 0, 0)
            local emptyText = emptyLabel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            emptyText:SetPoint("LEFT", 0, 0)
            emptyText:SetText("No bindings configured yet.")
            emptyText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            listY = -28
        else
            for i, binding in ipairs(bindings) do
                local actionType = binding.actionType
                if type(actionType) ~= "string" then actionType = "spell" end
                local spellName = binding.spell
                if type(spellName) ~= "string" then spellName = nil end
                local row = CreateFrame("Frame", nil, bindingListFrame)
                row:SetSize(400, 28)
                row:SetPoint("TOPLEFT", 0, listY)
                local iconTex = row:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(24, 24)
                iconTex:SetPoint("LEFT", 0, 0)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if actionType == "spell" and spellName then
                    local spellID = C_Spell.GetSpellIDForSpellIdentifier(spellName)
                    if spellID then
                        local info = C_Spell.GetSpellInfo(spellID)
                        iconTex:SetTexture(info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
                    else
                        iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    end
                else
                    iconTex:SetTexture(ACTION_FALLBACK_ICONS[actionType] or "Interface\\Icons\\INV_Misc_QuestionMark")
                end
                local modLabel = modLabels[binding.modifiers or ""] or ""
                local triggerLabel = binding.key or (buttonNames[binding.button] or binding.button)
                local comboText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                comboText:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                comboText:SetWidth(140)
                comboText:SetJustifyH("LEFT")
                comboText:SetText(modLabel .. triggerLabel)
                comboText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                local spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                spellText:SetPoint("LEFT", comboText, "RIGHT", 8, 0)
                spellText:SetWidth(140)
                spellText:SetJustifyH("LEFT")
                local displayName = spellName or actionType
                if actionType == "macro" then displayName = "Macro"
                elseif actionType == "menu" then displayName = "Unit Menu"
                elseif PING_DISPLAY_NAMES[actionType] then displayName = PING_DISPLAY_NAMES[actionType] end
                spellText:SetText(displayName)
                spellText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
                local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                SetSizePx(removeBtn, 22, 22)
                ApplyPixelBackdrop(removeBtn, 1, true)
                removeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                removeBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                local xText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                xText:SetPoint("CENTER", 0, 0)
                xText:SetText("X")
                xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
                removeBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
                removeBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7) end)
                removeBtn:SetScript("OnClick", function() GFCC:RemoveBinding(i) RefreshBindingList() end)
                removeBtn:SetPoint("LEFT", spellText, "RIGHT", 8, 0)
                listY = listY - 30
            end
        end
        local listHeight = math.max(20, math.abs(listY))
        bindingListFrame:SetHeight(listHeight)
        local fixedTop = math.abs(y)
        local totalHeight = fixedTop + listHeight + 10 + addContainer:GetHeight() + 30
        content:SetHeight(totalHeight)
    end

    RefreshBindingList()
    RefreshClickCastPixelFrames()
    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(content, "clickCastPixelFrames", function()
            RefreshClickCastPixelFrames()
            if RefreshBindingList then RefreshBindingList() end
        end)
    end

    perSpecCheck.track:HookScript("OnClick", function()
        C_Timer.After(0.05, function() RefreshBindingList() end)
    end)
end

---------------------------------------------------------------------------
-- MISC SETTINGS (Range, Portrait, Pets, Spotlight)
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- ELEMENT BUILDERS TABLE
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- PREVIEW SETTINGS (context-aware: party vs raid)

local ELEMENT_BUILDERS = {
    -- Composer elements (visual preview-driven)
    health = BuildHealthSettings,
    power = BuildPowerSettings,
    name = BuildNameSettings,
    buffs = BuildBuffsSettings,
    debuffs = BuildDebuffsSettings,
    indicators = BuildIndicatorsSettings,
    healer = BuildHealerSettings,
    defensive = BuildDefensiveSettings,
    auraIndicators = BuildAuraIndicatorsSettings,
    privateAuras = BuildPrivateAurasSettings,
    -- General elements
    general = BuildGeneralSettings,
    clickCast = BuildClickCastSettings,
    -- Context elements (appearance / settings)
    appearance = BuildAppearanceSettings,
    contextSettings = BuildContextSettings,
}

---------------------------------------------------------------------------
-- WIDGET BAR
---------------------------------------------------------------------------
local function CreateWidgetBar(container, selectElementFunc, state, elementKeys)
    local bar = CreateFrame("Frame", nil, container)
    bar:SetHeight(1)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    local buttons = {}
    local orderedButtons = {}
    local fontPath = GUI.FONT_PATH or "Fonts\\FRIZQT__.TTF"
    local btnHeight = 24
    local btnSpacing = 4
    local rowGap = 4

    for _, key in ipairs(elementKeys) do
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
        btn:SetScript("OnClick", function()
            selectElementFunc(key)
        end)

        btn:SetScript("OnEnter", function(self)
            if state.selectedElement ~= key then
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if state.selectedElement ~= key then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)

        buttons[key] = btn
        orderedButtons[#orderedButtons + 1] = btn
    end

    local function RelayoutWidgetBar()
        local x, y = 0, 0
        local barWidth = container:GetWidth() - (PADDING * 2)
        if barWidth < 100 then barWidth = 700 end
        barWidth = RoundVirtual(barWidth, bar)

        for _, btn in ipairs(orderedButtons) do
            local btnWidth = RoundVirtual((btn.text:GetStringWidth() or 40) + 16, btn)
            if x + btnWidth > barWidth and x > 0 then
                x = 0
                y = RoundVirtual(y - (btnHeight + rowGap), bar)
            end

            btn:SetWidth(btnWidth)
            btn:ClearAllPoints()
            SetSnappedPoint(btn, "TOPLEFT", bar, "TOPLEFT", x, y)
            x = RoundVirtual(x + btnWidth + btnSpacing, bar)
        end

        local totalHeight = RoundVirtual(math.abs(y) + btnHeight, bar)
        bar:SetHeight(totalHeight)
        return totalHeight
    end

    local totalHeight = RelayoutWidgetBar()
    bar:SetScript("OnSizeChanged", function()
        totalHeight = RelayoutWidgetBar()
    end)

    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(bar, "widgetBarBorders", function(owner)
            for _, btn in ipairs(orderedButtons) do
                btn:SetHeight(RoundVirtual(btnHeight, btn))
                ApplyPixelBackdrop(btn, 1, true)
            end
            totalHeight = RelayoutWidgetBar()
            owner:SetHeight(totalHeight)
        end)
    end

    state.widgetBarButtons = buttons
    return bar, totalHeight
end

---------------------------------------------------------------------------
-- DESIGNER VIEW BUILDER (for one sub-tab: party or raid)
---------------------------------------------------------------------------
local function BuildDesignerView(tabContent, previewType)
    local gfdb = GetGFDB()
    if not gfdb then
        local info = GUI:CreateLabel(tabContent, "Group frame settings not available.", 12, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, -10)
        tabContent:SetHeight(100)
        return
    end

    -- State for this view
    local state = {
        selectedElement = nil,
        previewWrapper = nil,
        childRefs = {},
        hitOverlays = {},
        widgetBarButtons = {},
        settingsPanels = {},
        settingsArea = nil,
    }

    local y = -10

    -- Description
    local desc = GUI:CreateDescription(tabContent, "Click on a part of the preview frame or use the buttons below to configure it. Changes apply immediately.")
    desc:SetPoint("TOPLEFT", PAD, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - 26

    ---------------------------------------------------------------------------
    -- PREVIEW FRAME
    ---------------------------------------------------------------------------
    local childRefs = {}
    state.childRefs = childRefs

    local rebuildTimer = nil
    local function RebuildPreviewImmediate()
        if state.previewWrapper then
            state.previewWrapper:Hide()
            state.previewWrapper:SetParent(nil)
            state.previewWrapper = nil
        end
        for _, overlay in pairs(state.hitOverlays) do
            overlay:Hide()
            overlay:SetParent(nil)
        end
        wipe(state.hitOverlays)
        wipe(childRefs)

        local wrapper = CreateDesignerPreview(tabContent, previewType, childRefs)
        if not wrapper then return end

        wrapper:SetPoint("TOPLEFT", PAD, state._previewY or y)
        state.previewWrapper = wrapper

        local frame = childRefs.frame
        if not frame then return end

        -- Frame level tiers: frame=base, sub-regions=+1, small elements=+2
        local baseFLvl = frame:GetFrameLevel() + 10
        local subFLvl = baseFLvl + 2
        local elemFLvl = baseFLvl + 4

        -- Map sub-element keys to the widget bar tab they should select
        local CLICK_TARGET = {
            frame = "health",
            healthText = "health",
            absorbs = "health",
            role = "indicators",
            readyCheck = "indicators", resurrection = "indicators",
            summon = "indicators", leader = "indicators",
            targetMarker = "indicators", phase = "indicators",
        }

        -- Helper to create overlay, wire hover/click/drag, store in state
        local function MakeOverlay(key, anchorFrame, mode, fLvl, w, h, aPoint, arPoint, oX, oY)
            local overlay = CreateHitOverlay(tabContent, frame, key, anchorFrame, mode, w, h, aPoint, arPoint, oX, oY, fLvl)
            local selectKey = CLICK_TARGET[key] or key
            overlay:SetScript("OnEnter", function(self)
                self.highlight:Show()
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText(ELEMENT_LABELS[selectKey] or key)
                if DRAG_CONFIG[key] then
                    GameTooltip:AddLine("Drag to reposition", 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end)
            overlay:SetScript("OnLeave", function(self)
                if state.selectedElement ~= selectKey then
                    self.highlight:Hide()
                end
                GameTooltip:Hide()
            end)
            overlay:SetScript("OnClick", function(self)
                if self._dragFired then self._dragFired = false return end
                if state.selectElement then
                    state.selectElement(selectKey)
                end
            end)

            -- Drag support for elements with offset keys
            local dragCfg = DRAG_CONFIG[key]
            if dragCfg then
                overlay:RegisterForDrag("LeftButton")
                overlay:SetScript("OnDragStart", function(self)
                    self._dragFired = true
                    local gfdb = GetGFDB()
                    if not gfdb then return end
                    local proxy = CreateVisualProxy(gfdb, previewType)
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

                    -- Disable mouse on all OTHER overlays so they can't steal hover
                    for oKey, oFrame in pairs(state.hitOverlays) do
                        if oFrame ~= self then oFrame:EnableMouse(false) end
                    end

                    -- Ghost outline follows cursor
                    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                    ghost:SetFrameStrata("TOOLTIP")
                    local ow, oh = self:GetSize()
                    local sourcePx = QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(self) or 1
                    local ghostWidthPx = math.max((ow or 0) / sourcePx, 8)
                    local ghostHeightPx = math.max((oh or 0) / sourcePx, 8)
                    SetSizePx(ghost, ghostWidthPx, ghostHeightPx)
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
                    -- Clean up ghost
                    if self._dragGhost then
                        self._dragGhost:Hide()
                        self._dragGhost:SetParent(nil)
                        self._dragGhost = nil
                    end

                    -- Re-enable mouse on all overlays
                    for oKey, oFrame in pairs(state.hitOverlays) do
                        oFrame:EnableMouse(true)
                    end

                    if not self._dragDBTbl then return end

                    -- Compute final offset
                    local cx, cy = GetCursorPosition()
                    local scale = self:GetEffectiveScale()
                    local dx = (cx / scale - self._dragStartCX) / PREVIEW_SCALE
                    local dy = (cy / scale - self._dragStartCY) / PREVIEW_SCALE
                    self._dragDBTbl[dragCfg.xKey] = math.floor(self._dragStartValX + dx + 0.5)
                    self._dragDBTbl[dragCfg.yKey] = math.floor(self._dragStartValY + dy + 0.5)
                    self._dragDBTbl = nil

                    -- Rebuild preview + refresh live frames
                    RebuildPreviewImmediate()
                    RefreshGF()

                    -- Refresh settings panel to show new slider values
                    local panelKey = selectKey
                    if state.settingsPanels[panelKey] then
                        state.settingsPanels[panelKey]:Hide()
                        state.settingsPanels[panelKey]:SetParent(nil)
                        state.settingsPanels[panelKey] = nil
                    end
                    for pKey, panel in pairs(state.settingsPanels) do
                        panel:Hide()
                    end
                    if state.selectElement then state.selectElement(panelKey) end
                end)
                overlay:SetScript("OnUpdate", function(self)
                    if not self._dragGhost then return end
                    local cx, cy = GetCursorPosition()
                    local scale = self:GetEffectiveScale()
                    local dx = cx / scale - self._dragStartCX
                    local dy = cy / scale - self._dragStartCY
                    self._dragGhost:ClearAllPoints()
                    self._dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self._dragOlCX + dx, self._dragOlCY + dy)
                end)
            end

            state.hitOverlays[key] = overlay
        end

        -- Overlays for each element (frame = catch-all at lowest level)
        MakeOverlay("frame", frame, "fill", baseFLvl)
        if childRefs.healthBar then MakeOverlay("health", childRefs.healthBar, "fill", subFLvl) end
        if childRefs.powerBar then MakeOverlay("power", childRefs.powerBar, "fill", subFLvl) end
        if childRefs.nameText then
            local nameW = childRefs.nameText:GetStringWidth() or 60
            MakeOverlay("name", childRefs.nameText, "fixed", elemFLvl, nameW + 4, 20, "LEFT", "LEFT", -2, 0)
        end
        if childRefs.healthText then
            local htW = childRefs.healthText:GetStringWidth() or 40
            MakeOverlay("healthText", childRefs.healthText, "fixed", elemFLvl, htW + 4, 20, "RIGHT", "RIGHT", 2, 0)
        end
        if childRefs.buffContainer then MakeOverlay("buffs", childRefs.buffContainer, "fill", elemFLvl) end
        if childRefs.debuffContainer then MakeOverlay("debuffs", childRefs.debuffContainer, "fill", elemFLvl) end
        if childRefs.roleIcon and childRefs.roleIcon:IsShown() then MakeOverlay("role", childRefs.roleIcon, "fill", elemFLvl) end
        -- Individual indicator overlays (only for visible indicators)
        if childRefs.readyCheckIcon and childRefs.readyCheckIcon:IsShown() then MakeOverlay("readyCheck", childRefs.readyCheckIcon, "fill", elemFLvl) end
        if childRefs.resIcon and childRefs.resIcon:IsShown() then MakeOverlay("resurrection", childRefs.resIcon, "fill", elemFLvl) end
        if childRefs.summonIcon and childRefs.summonIcon:IsShown() then MakeOverlay("summon", childRefs.summonIcon, "fill", elemFLvl) end
        if childRefs.leaderIcon and childRefs.leaderIcon:IsShown() then MakeOverlay("leader", childRefs.leaderIcon, "fill", elemFLvl) end
        if childRefs.targetMarker and childRefs.targetMarker:IsShown() then MakeOverlay("targetMarker", childRefs.targetMarker, "fill", elemFLvl) end
        if childRefs.phaseIcon and childRefs.phaseIcon:IsShown() then MakeOverlay("phase", childRefs.phaseIcon, "fill", elemFLvl) end
        if childRefs.absorbOverlay then MakeOverlay("absorbs", childRefs.absorbOverlay, "fill", subFLvl) end
        if childRefs.dispelOverlay then MakeOverlay("healer", childRefs.dispelOverlay, "fill", subFLvl) end
        if childRefs.defIcon and childRefs.defIcon:IsShown() then MakeOverlay("defensive", childRefs.defIcon, "fill", elemFLvl) end
        if childRefs.auraIndicatorContainer and childRefs.auraIndicatorContainer:IsShown() then MakeOverlay("auraIndicators", childRefs.auraIndicatorContainer, "fill", elemFLvl) end
        if childRefs.paContainer and childRefs.paContainer:IsShown() then MakeOverlay("privateAuras", childRefs.paContainer, "fill", elemFLvl) end

        -- Re-highlight selected element (direct + sub-element overlays)
        if state.selectedElement then
            local sel = state.selectedElement
            local o = state.hitOverlays[sel]
            if o then o.highlight:Show() end
            -- Also highlight sub-element overlays belonging to this tab
            local INDICATOR_SUBS = { "role", "readyCheck", "resurrection", "summon", "leader", "targetMarker", "phase" }
            if sel == "indicators" then
                for _, subKey in ipairs(INDICATOR_SUBS) do
                    local so = state.hitOverlays[subKey]
                    if so then so.highlight:Show() end
                end
            end
            -- Show dispel overlay if healer tab is active
            if sel == "healer" and childRefs.dispelOverlay then
                childRefs.dispelOverlay:Show()
            end
            -- Show threat border if indicators tab is active
            if sel == "indicators" and childRefs.threatBorder then
                childRefs.threatBorder:Show()
            end
        end
    end

    local function RebuildPreview()
        if rebuildTimer then return end
        rebuildTimer = C_Timer.After(0.05, function()
            rebuildTimer = nil
            RebuildPreviewImmediate()
        end)
    end

    -- Expose RebuildPreview so sibling sections (Appearance, Settings) can trigger it
    tabContent._rebuildPreview = RebuildPreview

    state._previewY = y
    RebuildPreviewImmediate()
    local previewH = state.previewWrapper and state.previewWrapper:GetHeight() or 100
    y = y - previewH - 40

    ---------------------------------------------------------------------------
    -- WIDGET BAR
    ---------------------------------------------------------------------------
    -- Sub-element keys that map to a parent widget bar key
    local SUB_ELEMENT_MAP = {
        readyCheck = "indicators", resurrection = "indicators",
        summon = "indicators", leader = "indicators",
        targetMarker = "indicators", phase = "indicators",
    }

    -- Helper: show/hide highlights on all overlays that belong to a tab key
    local function SetOverlayHighlights(tabKey, show)
        -- Direct overlay
        local overlay = state.hitOverlays[tabKey]
        if overlay then
            if show then overlay.highlight:Show() else overlay.highlight:Hide() end
        end
        -- Sub-element overlays that map to this tab key
        for subKey, parentKey in pairs(SUB_ELEMENT_MAP) do
            if parentKey == tabKey then
                local subOverlay = state.hitOverlays[subKey]
                if subOverlay then
                    if show then subOverlay.highlight:Show() else subOverlay.highlight:Hide() end
                end
            end
        end
    end

    local function SelectElement(key)
        -- Deselect previous
        if state.selectedElement then
            local prevBtn = state.widgetBarButtons[state.selectedElement]
            if prevBtn then
                prevBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
                prevBtn:SetBackdropColor(0.12, 0.12, 0.12, 1)
            end
            SetOverlayHighlights(state.selectedElement, false)
            local prevPanel = state.settingsPanels[state.selectedElement]
            if prevPanel then prevPanel:Hide() end

            -- Hide dispel overlay when leaving healer tab
            if state.selectedElement == "healer" and childRefs.dispelOverlay then
                childRefs.dispelOverlay:Hide()
            end
            -- Hide threat border when leaving indicators tab
            if state.selectedElement == "indicators" and childRefs.threatBorder then
                childRefs.threatBorder:Hide()
            end
        end

        state.selectedElement = key

        -- Highlight button
        local btn = state.widgetBarButtons[key]
        if btn then
            btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            btn:SetBackdropColor(C.accent[1] * 0.2, C.accent[2] * 0.2, C.accent[3] * 0.2, 1)
        end

        -- Show dispel overlay when selecting healer tab
        if key == "healer" and childRefs.dispelOverlay then
            childRefs.dispelOverlay:Show()
        end
        -- Show threat border when selecting indicators tab
        if key == "indicators" and childRefs.threatBorder then
            childRefs.threatBorder:Show()
        end

        -- Highlight overlay(s)
        SetOverlayHighlights(key, true)

        -- Lazy-create or show settings panel
        local panel = state.settingsPanels[key]
        if not panel then
            local builder = ELEMENT_BUILDERS[key]
            if not builder then return end

            panel = CreateFrame("Frame", nil, state.settingsArea)
            panel:SetPoint("TOPLEFT", 0, 0)
            panel:SetPoint("RIGHT", state.settingsArea, "RIGHT", 0, 0)

            local currentGFDB = GetGFDB()
            if currentGFDB then
                local function onChangeHandler()
                    RefreshGF()
                    RebuildPreview()
                    local editMode = ns.QUI_GroupFrameEditMode
                    if editMode and (editMode:IsTestMode() or editMode:IsEditMode()) then
                        editMode:RefreshTestMode()
                    end
                end
                GUI._suppressSearchRegistration = true
                builder(panel, CreateVisualProxy(currentGFDB, previewType), onChangeHandler)
                GUI._suppressSearchRegistration = false
            end

            -- Keep scroll child height in sync when panel relayouts change height
            panel:HookScript("OnSizeChanged", function(self, w, h)
                if self:IsShown() and h and h > 0 then
                    state.settingsArea:SetHeight(h)
                    if state.refreshScrollBar then state.refreshScrollBar() end
                end
            end)

            state.settingsPanels[key] = panel
        end
        panel:Show()

        -- Resize scroll child to fit panel content
        local panelHeight = panel:GetHeight()
        if panelHeight and panelHeight > 0 then
            state.settingsArea:SetHeight(panelHeight)
        end

        -- Update scrollbar visibility for new content size
        if state.refreshScrollBar then state.refreshScrollBar() end
    end

    state.selectElement = SelectElement

    local widgetBar, widgetBarHeight = CreateWidgetBar(tabContent, SelectElement, state, VISUAL_ELEMENT_KEYS)
    widgetBar:SetPoint("TOPLEFT", PAD, y)
    state._widgetBarHeight = widgetBarHeight
    y = y - widgetBarHeight - 10

    ---------------------------------------------------------------------------
    -- SETTINGS AREA (inner scroll — preview + widget bar stay fixed above)
    ---------------------------------------------------------------------------
    local outerScroll = FindNearestScrollFrame(tabContent)

    local settingsScroll = CreateFrame("ScrollFrame", nil, tabContent, "UIPanelScrollFrameTemplate")
    settingsScroll:SetPoint("TOPLEFT", PAD, y)
    settingsScroll:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    settingsScroll:SetHeight(300) -- resized dynamically below
    settingsScroll:SetClipsChildren(true)

    local settingsChild = CreateFrame("Frame", nil, settingsScroll)
    settingsChild:SetWidth(settingsScroll:GetWidth() or 400)
    settingsChild:SetHeight(1)
    settingsScroll:SetScrollChild(settingsChild)
    state.settingsArea = settingsChild

    -- Style scrollbar to match the rest of the UI
    local scrollBar = settingsScroll.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", settingsScroll, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", settingsScroll, "BOTTOMRIGHT", 4, 16)
        local thumb = scrollBar:GetThumbTexture()
        if thumb then thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8) end
        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end

        -- Auto-hide scrollbar when content fits without scrolling
        scrollBar:HookScript("OnShow", function(self)
            C_Timer.After(0.066, function()
                local maxScroll = ns.GetSafeVerticalScrollRange(settingsScroll)
                if maxScroll <= 1 then
                    self:Hide()
                end
            end)
        end)
    end
    ns.ApplyScrollWheel(settingsScroll)

    -- Helper to refresh scrollbar visibility after content changes
    local function RefreshScrollBar()
        if scrollBar then
            C_Timer.After(0.066, function()
                local maxScroll = ns.GetSafeVerticalScrollRange(settingsScroll)
                if maxScroll <= 1 then
                    scrollBar:Hide()
                else
                    scrollBar:Show()
                end
            end)
        end
    end

    state.refreshScrollBar = RefreshScrollBar

    -- Dynamically size the inner scroll to fill remaining space in the parent
    local fixedHeaderH = math.abs(y)
    local function ResizeSettingsScroll()
        -- Use the immediate parent's height (section frame inside sectionHost),
        -- not the outer scroll viewport, since the Composer may be nested inside
        -- a sectionHost that is shorter than the full viewport.
        local parentH = tabContent:GetHeight()
        if (not parentH or parentH <= 0) and outerScroll then
            parentH = outerScroll:GetHeight()
        end
        if parentH and parentH > 0 then
            settingsScroll:SetHeight(math.max(parentH - fixedHeaderH - 10, 200))
        end
        local sw = settingsScroll:GetWidth()
        if sw and sw > 0 then
            settingsChild:SetWidth(sw)
        end
        RefreshScrollBar()
    end
    if outerScroll and outerScroll.HookScript then
        outerScroll:HookScript("OnSizeChanged", ResizeSettingsScroll)
    end
    -- Re-size when the Composer section frame itself resizes (e.g. sectionHost changed)
    tabContent:HookScript("OnSizeChanged", ResizeSettingsScroll)
    settingsScroll:HookScript("OnShow", ResizeSettingsScroll)
    C_Timer.After(0, ResizeSettingsScroll)

    -- Select first element by default
    SelectElement("health")

    -- Build all designer setting panels once so every option is indexed by search,
    -- even if the user never clicks each widget-bar element manually.
    -- Suppress sidebar section auto-registration so section headers within
    -- element builders don't pollute the sidebar (only Composer/Appearance/Settings).
    local currentGFDB = GetGFDB()
    if currentGFDB then
        local proxyGFDB = CreateVisualProxy(currentGFDB, previewType)
        local function preBuildOnChange()
            RefreshGF()
            RebuildPreview()
        end
        GUI._suppressSearchRegistration = true
        for _, key in ipairs(VISUAL_ELEMENT_KEYS) do
            if not state.settingsPanels[key] then
                local builder = ELEMENT_BUILDERS[key]
                if builder then
                    local panel = CreateFrame("Frame", nil, state.settingsArea)
                    panel:SetPoint("TOPLEFT", 0, 0)
                    panel:SetPoint("RIGHT", state.settingsArea, "RIGHT", 0, 0)
                    builder(panel, proxyGFDB, preBuildOnChange)
                    panel:Hide()
                    state.settingsPanels[key] = panel
                end
            end
        end
        GUI._suppressSearchRegistration = false
    end
end

---------------------------------------------------------------------------
-- GENERAL VIEW BUILDER (for the General sub-tab)
---------------------------------------------------------------------------
local function BuildGeneralView(tabContent)
    local gfdb = GetGFDB()
    if not gfdb then
        local info = GUI:CreateLabel(tabContent, "Group frame settings not available.", 12, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, -10)
        tabContent:SetHeight(100)
        return
    end

    -- State for this view (reuse same accordion pattern as designer)
    local state = {
        selectedElement = nil,
        widgetBarButtons = {},
        settingsPanels = {},
        settingsArea = nil,
    }

    local y = -10

    -- Description
    local desc = GUI:CreateDescription(tabContent, "Global group frame settings shared between party and raid.")
    desc:SetPoint("TOPLEFT", PAD, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - 26

    ---------------------------------------------------------------------------
    -- WIDGET BAR (general elements only)
    ---------------------------------------------------------------------------
    local function SelectElement(key)
        -- Deselect previous
        if state.selectedElement then
            local prevBtn = state.widgetBarButtons[state.selectedElement]
            if prevBtn then
                prevBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
                prevBtn:SetBackdropColor(0.12, 0.12, 0.12, 1)
            end
            local prevPanel = state.settingsPanels[state.selectedElement]
            if prevPanel then prevPanel:Hide() end
        end

        state.selectedElement = key

        -- Highlight button
        local btn = state.widgetBarButtons[key]
        if btn then
            btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            btn:SetBackdropColor(C.accent[1] * 0.2, C.accent[2] * 0.2, C.accent[3] * 0.2, 1)
        end

        -- Lazy-create or show settings panel
        local panel = state.settingsPanels[key]
        if not panel then
            local builder = ELEMENT_BUILDERS[key]
            if not builder then return end

            panel = CreateFrame("Frame", nil, state.settingsArea)
            panel:SetPoint("TOPLEFT", 0, 0)
            panel:SetPoint("RIGHT", state.settingsArea, "RIGHT", 0, 0)

            local currentGFDB = GetGFDB()
            if currentGFDB then
                builder(panel, currentGFDB, RefreshGF)
            end

            state.settingsPanels[key] = panel
        end
        panel:Show()

        -- Resize settings area to fit panel
        local panelHeight = panel:GetHeight()
        if panelHeight and panelHeight > 0 then
            state.settingsArea:SetHeight(panelHeight)
        end

        -- Resize total content
        local totalY = 26 + (state._widgetBarHeight or 0) + 10 + (panelHeight or 300) + 20
        tabContent:SetHeight(totalY)
    end

    local widgetBar, widgetBarHeight = CreateWidgetBar(tabContent, SelectElement, state, GENERAL_ELEMENT_KEYS)
    widgetBar:SetPoint("TOPLEFT", PAD, y)
    state._widgetBarHeight = widgetBarHeight
    y = y - widgetBarHeight - 10

    ---------------------------------------------------------------------------
    -- SETTINGS AREA
    ---------------------------------------------------------------------------
    local settingsArea = CreateFrame("Frame", nil, tabContent)
    settingsArea:SetPoint("TOPLEFT", PAD, y)
    settingsArea:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    settingsArea:SetHeight(300)
    state.settingsArea = settingsArea

    -- Select first element by default
    SelectElement("general")

    -- Build all general-settings panels once so their controls are searchable
    local currentGFDB = GetGFDB()
    if currentGFDB then
        for _, key in ipairs(GENERAL_ELEMENT_KEYS) do
            if not state.settingsPanels[key] then
                local builder = ELEMENT_BUILDERS[key]
                if builder then
                    local panel = CreateFrame("Frame", nil, state.settingsArea)
                    panel:SetPoint("TOPLEFT", 0, 0)
                    panel:SetPoint("RIGHT", state.settingsArea, "RIGHT", 0, 0)
                    builder(panel, currentGFDB, RefreshGF)
                    panel:Hide()
                    state.settingsPanels[key] = panel
                end
            end
        end
    end

    tabContent:SetHeight(800)
end

---------------------------------------------------------------------------
-- CONTEXT VIEW BUILDER (for Party or Raid sub-tab)
-- Each context has 3 sidebar sections: Composer, Appearance, Settings
---------------------------------------------------------------------------
local function BuildContextView(tabContent, contextMode)
    local gfdb = GetGFDB()
    if not gfdb then
        local info = GUI:CreateLabel(tabContent, "Group frame settings not available.", 12, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, -10)
        tabContent:SetHeight(100)
        return
    end

    local SUBTAB_INDEX = contextMode == "raid" and SEARCH_SUBTAB_RAID_INDEX or SEARCH_SUBTAB_PARTY_INDEX
    local contextLabel = contextMode == "raid" and "Raid" or "Party"

    local y = -10

    local desc = GUI:CreateDescription(tabContent, contextLabel .. " frame settings. Use the sidebar to switch between Composer, Appearance, and Settings.")
    desc:SetPoint("TOPLEFT", PAD, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - 26

    -- Host frame for section content
    local sectionHost = CreateFrame("Frame", nil, tabContent)
    sectionHost:SetPoint("TOPLEFT", 0, y)
    sectionHost:SetPoint("RIGHT", tabContent, "RIGHT", 0, 0)
    sectionHost:SetHeight(820)

    local sectionFrames = {}
    local activeSection = nil

    -- onChange that refreshes live frames, composer preview, AND edit mode test frames
    local function onChangeWithPreview()
        RefreshGF()
        -- Rebuild composer preview if it has been built
        local composerFrame = sectionFrames["Composer"]
        if composerFrame and composerFrame._rebuildPreview then
            composerFrame._rebuildPreview()
        end
        -- Refresh edit mode test frames so changes are reflected in real-time
        local editMode = ns.QUI_GroupFrameEditMode
        if editMode and (editMode:IsTestMode() or editMode:IsEditMode()) then
            editMode:RefreshTestMode()
        end
    end

    local function EnsureSectionFrame(section)
        if sectionFrames[section] then return sectionFrames[section] end
        local frame = CreateFrame("Frame", nil, sectionHost)
        if section == "Composer" then
            -- Composer manages its own inner scroll — fill the host
            frame:SetAllPoints(sectionHost)
        else
            -- Appearance/Settings: anchor top+right, let builder set height
            frame:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, 0)
            frame:SetPoint("RIGHT", sectionHost, "RIGHT", 0, 0)
        end

        if section == "Composer" then
            BuildDesignerView(frame, contextMode)
        elseif section == "Appearance" then
            -- Suppress section header sidebar registration (only Composer/Appearance/Settings should be sidebar entries)
            GUI._suppressSearchRegistration = true
            local proxy = CreateVisualProxy(gfdb, contextMode)
            BuildAppearanceSettings(frame, proxy, onChangeWithPreview)
            GUI._suppressSearchRegistration = false
        elseif section == "Settings" then
            GUI._suppressSearchRegistration = true
            local proxy = CreateVisualProxy(gfdb, contextMode)
            BuildContextSettings(frame, proxy, onChangeWithPreview)
            GUI._suppressSearchRegistration = false
        end

        sectionFrames[section] = frame
        return frame
    end

    local sectionNames = { "Composer", "Appearance", "Settings" }

    local function EnsureSidebarEntries()
        local key = SEARCH_TAB_INDEX * 10000 + SUBTAB_INDEX
        GUI.SectionRegistryOrder[key] = sectionNames
        local reg = {}
        for _, name in ipairs(sectionNames) do
            reg[name] = { frame = sectionHost, scrollParent = nil, contentParent = tabContent }
        end
        GUI.SectionRegistry[key] = reg
    end

    local outerScroll = FindNearestScrollFrame(tabContent)

    -- Size the host and tabContent based on the active section.
    -- Composer has its own inner scroll so it fills the viewport.
    -- Appearance/Settings set their own height — let the outer scroll handle overflow.
    local function ResizeForSection(section)
        local viewH = outerScroll and outerScroll.GetHeight and outerScroll:GetHeight() or nil
        if section == "Composer" then
            if viewH and viewH > 0 then
                local targetH = math.max(420, viewH - math.abs(y) - 20)
                sectionHost:SetHeight(targetH)
                tabContent:SetHeight(math.abs(y) + targetH + 20)
            else
                sectionHost:SetHeight(820)
                tabContent:SetHeight(900)
            end
        else
            -- Use the section frame's content height
            local frame = sectionFrames[section]
            local contentH = frame and frame:GetHeight() or 600
            if contentH < 100 then contentH = 600 end
            sectionHost:SetHeight(contentH)
            tabContent:SetHeight(math.abs(y) + contentH + 20)
        end
    end

    local function SelectSection(section)
        activeSection = section
        EnsureSectionFrame(section)
        for name, frame in pairs(sectionFrames) do
            frame:SetShown(name == section)
        end
        ResizeForSection(section)
        if GUI.MainFrame and GUI.MainFrame.activeTab == SEARCH_TAB_INDEX then
            GUI.MainFrame._sidebarActiveSectionKey = SEARCH_TAB_INDEX .. ":" .. SUBTAB_INDEX .. ":" .. section
            GUI:RefreshSidebarTree(GUI.MainFrame)
        end
        return true
    end

    -- Register sidebar sections
    EnsureSidebarEntries()
    if GUI.RegisterSectionNavigateHandler then
        for _, section in ipairs(sectionNames) do
            GUI:RegisterSectionNavigateHandler(SEARCH_TAB_INDEX, SUBTAB_INDEX, section, function()
                return SelectSection(section)
            end)
        end
    end

    if outerScroll and outerScroll.HookScript then
        outerScroll:HookScript("OnSizeChanged", function()
            if activeSection then ResizeForSection(activeSection) end
        end)
    end

    SelectSection("Composer")
    C_Timer.After(0, function()
        EnsureSidebarEntries()
        ResizeForSection(activeSection or "Composer")
        if GUI.MainFrame then
            GUI:RefreshSidebarTree(GUI.MainFrame)
        end
    end)
end

local function RegisterDesignerSearchNavigation()
    if not GUI or not GUI.RegisterNavigationItem then return end

    -- Register 3 sub-tabs: General, Party, Raid
    GUI:RegisterNavigationItem("subtab", {
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_GENERAL_INDEX,
        subTabName = SEARCH_SUBTAB_GENERAL_NAME,
    })
    GUI:RegisterNavigationItem("subtab", {
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_PARTY_INDEX,
        subTabName = SEARCH_SUBTAB_PARTY_NAME,
    })
    GUI:RegisterNavigationItem("subtab", {
        tabIndex = SEARCH_TAB_INDEX,
        tabName = SEARCH_TAB_NAME,
        subTabIndex = SEARCH_SUBTAB_RAID_INDEX,
        subTabName = SEARCH_SUBTAB_RAID_NAME,
    })

    -- Register sidebar sections for Party and Raid
    local sectionNames = { "Composer", "Appearance", "Settings" }
    for _, ctx in ipairs({
        { index = SEARCH_SUBTAB_PARTY_INDEX, name = SEARCH_SUBTAB_PARTY_NAME },
        { index = SEARCH_SUBTAB_RAID_INDEX, name = SEARCH_SUBTAB_RAID_NAME },
    }) do
        for _, section in ipairs(sectionNames) do
            GUI:RegisterNavigationItem("section", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = ctx.index,
                subTabName = ctx.name,
                sectionName = section,
            })
        end
    end
end

---------------------------------------------------------------------------
-- MAIN ENTRY POINT
---------------------------------------------------------------------------
local function CreateDesignerPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    GUI:CreateSubTabs(content, {
        { name = "General", builder = BuildGeneralView },
        { name = "Party", isDesigner = true, builder = function(tc) BuildContextView(tc, "party") end },
        { name = "Raid", isDesigner = true, builder = function(tc) BuildContextView(tc, "raid") end },
    })
    RegisterDesignerSearchNavigation()
    if GUI.SetSidebarSubTabSectionsHidden and GUI.MainFrame then
        GUI:SetSidebarSubTabSectionsHidden(GUI.MainFrame, SEARCH_TAB_INDEX, SEARCH_SUBTAB_GENERAL_INDEX, true)
    end

    -- Designer tabs use an inner scroll for settings, so disable outer
    -- scrolling by matching scroll child height to viewport. General tab
    -- keeps normal outer scrolling.
    local subTabGroup = GUI._lastSubTabGroup
    if subTabGroup then
        local origOnSelect = subTabGroup._onSelect
        subTabGroup._onSelect = function(index, tabInfo)
            if origOnSelect then origOnSelect(index, tabInfo) end
            if tabInfo and tabInfo.isDesigner then
                local viewH = scroll:GetHeight()
                content:SetHeight(viewH > 0 and viewH or 1)
            else
                content:SetHeight(800)
            end
        end
    end

    -- Initial state: General tab selected.
    C_Timer.After(0, function()
        content:SetHeight(800)
    end)
end

---------------------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------------------
ns.QUI_GroupFramesOptions = {
    CreateGroupFramesPage = CreateDesignerPage,
}
