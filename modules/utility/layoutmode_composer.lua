--[[
    QUI Layout Mode Composer — Group Frame Element Settings Popup
    Standalone popup with scaled preview, clickable overlays, widget bar,
    and element-level settings. Opened from layout mode settings panel.
    Adapted from options/tabs/frames/groupframedesigner.lua
]]

local ADDON_NAME, ns = ...

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

local function SafeGetVerticalScrollRange(scrollFrame)
    local ok, maxScroll = pcall(scrollFrame.GetVerticalScrollRange, scrollFrame)
    if not ok then return 0 end
    local ok2, safeMax = pcall(function() return math.max(0, maxScroll or 0) end)
    return ok2 and safeMax or 0
end

local function SafeGetVerticalScroll(scrollFrame)
    local ok, currentScroll = pcall(scrollFrame.GetVerticalScroll, scrollFrame)
    if not ok then return 0 end
    local ok2, safeCurrent = pcall(function() return currentScroll + 0 end)
    return ok2 and safeCurrent or 0
end

local function ComposerDebugPrint(...)
    local addon = _G.QUI
    if addon and addon.DebugPrint then
        addon:DebugPrint("|cff8BFF8B[ComposerDbg]|r", ...)
    end
end

local function ComposerFrameHeight(frame)
    local h = frame and frame.GetHeight and frame:GetHeight()
    if type(h) ~= "number" then return "nil" end
    return string.format("%.1f", h)
end

local function ComposerSectionSummary(sections)
    if not sections or #sections == 0 then
        return "(no sections)"
    end

    local parts = {}
    for i, section in ipairs(sections) do
        parts[#parts + 1] = string.format(
            "%d:%s[e=%s sh=%s ch=%s]",
            i,
            section._title or "?",
            section._expanded and "1" or "0",
            ComposerFrameHeight(section),
            type(section._contentHeight) == "number" and string.format("%.1f", section._contentHeight) or "nil"
        )
    end
    return table.concat(parts, " | ")
end

local function CreateQUIStyleCloseButton(parent, relativeTo, relativePoint, xOffset, yOffset, onClick)
    local GUI = _G.QUI and _G.QUI.GUI
    local C = GUI and GUI.Colors or {}
    local border = C.border or {0.24, 0.28, 0.34, 1}
    local text = C.text or {0.85, 0.88, 0.92, 1}

    local close = CreateFrame("Button", nil, parent, "BackdropTemplate")
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", relativeTo, "RIGHT", xOffset or 0, yOffset or 0)
    close:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    close:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
    close:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)

    local lineLen, lineWidth = 10, 1.5
    local xLine1 = close:CreateTexture(nil, "OVERLAY")
    xLine1:SetSize(lineLen, lineWidth)
    xLine1:SetPoint("CENTER")
    xLine1:SetColorTexture(text[1], text[2], text[3], 0.8)
    xLine1:SetRotation(math.rad(45))

    local xLine2 = close:CreateTexture(nil, "OVERLAY")
    xLine2:SetSize(lineLen, lineWidth)
    xLine2:SetPoint("CENTER")
    xLine2:SetColorTexture(text[1], text[2], text[3], 0.8)
    xLine2:SetRotation(math.rad(-45))

    close:SetScript("OnClick", onClick)
    close:SetScript("OnEnter", function(self)
        local gui = _G.QUI and _G.QUI.GUI
        local accent = gui and gui.Colors and gui.Colors.accent
        local ar = accent and accent[1] or 0.376
        local ag = accent and accent[2] or 0.647
        local ab = accent and accent[3] or 0.980
        pcall(self.SetBackdropBorderColor, self, ar, ag, ab, 1)
        self:SetBackdropColor(ar, ag, ab, 0.15)
        xLine1:SetColorTexture(ar, ag, ab, 1)
        xLine2:SetColorTexture(ar, ag, ab, 1)
    end)
    close:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, border[1], border[2], border[3], border[4] or 1)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
        xLine1:SetColorTexture(text[1], text[2], text[3], 0.8)
        xLine2:SetColorTexture(text[1], text[2], text[3], 0.8)
    end)

    return close
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

local function GetFontListWithDefault()
    local U = ns.QUI_LayoutMode_Utils
    local list = U and U.GetFontList and U.GetFontList() or {}
    table.insert(list, 1, { value = "", text = "(Frame Font)" })
    return list
end

---------------------------------------------------------------------------
-- VISUAL PROXY
---------------------------------------------------------------------------
local VISUAL_DB_KEYS = {
    general = true, layout = true, health = true, power = true, name = true,
    absorbs = true, healAbsorbs = true, healPrediction = true, indicators = true,
    healer = true, classPower = true, range = true, auras = true,
    privateAuras = true, auraIndicators = true, pinnedAuras = true, castbar = true,
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
local AURA_INDICATOR_TYPE_OPTIONS = {
    { value = "icon", text = "Icon" },
    { value = "bar", text = "Bar" },
    { value = "healthBarColor", text = "Health Bar Tint" },
}
local BAR_ORIENTATION_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal" },
    { value = "VERTICAL", text = "Vertical" },
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
local FAKE_DEFENSIVE_ICONS = { 135936, 135919, 135874 }  -- Shield Wall, Divine Shield, Ice Block
local FAKE_AURA_IND_ICONS = { 135928, 136051, 136085, 135907 }  -- Renew, Rejuv, PoM, Riptide
local FAKE_PRIVATE_AURA_ICON = 136116  -- generic aura
local FAKE_CLASS = "PALADIN"
local FAKE_NAME = "Healena"
local FAKE_HP_PCT = 65
local PREVIEW_ROLE_ATLAS = {
    TANK = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}
local PREVIEW_ROLE_ORDER = {
    { role = "HEALER", toggleKey = "showRoleHealer" },
    { role = "TANK", toggleKey = "showRoleTank" },
    { role = "DAMAGER", toggleKey = "showRoleDPS" },
}

---------------------------------------------------------------------------
-- DYNAMIC LAYOUT
---------------------------------------------------------------------------
-- Dual-column mode (set by the V2 Group Frames tile while rendering an
-- element tab). Pairs consecutive visible non-header rows into a
-- CreateSettingsCardGroup-style two-column layout: left cell on LEFT→CENTER,
-- right cell on CENTER→RIGHT, 1px center divider, alternating row-tint
-- background. Header rows remain full-width. Unpaired trailing row gets
-- full width too. Conditional (condFn) rows reflow on every Relayout so
-- visibility toggles re-pair cleanly.
local _composerDualColumn = false

local CARD_ROW_HEIGHT = 32

local function CreateDynamicLayout(content, onRelayout)
    local rows = {}
    local dualColumn = _composerDualColumn
    local L = {}
    function L:Row(widget, height, condFn, isHeader)
        rows[#rows + 1] = { widget = widget, height = height, condFn = condFn, isHeader = isHeader }
        if not isHeader and not dualColumn then
            widget:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        end
    end
    function L:Header(widget) self:Row(widget, widget.gap, nil, true) end
    function L:Finish()
        local hasCondRows = false
        for _, row in ipairs(rows) do
            if row.condFn then hasCondRows = true; break end
        end

        -- Card-style row chrome pooled across Relayout calls so the bg/divider
        -- textures aren't leaked on every visibility toggle.
        local rowFrames = {}
        local function AcquireRowFrame(idx)
            local rf = rowFrames[idx]
            if not rf then
                rf = CreateFrame("Frame", nil, content)
                rf._bg = rf:CreateTexture(nil, "BACKGROUND")
                rf._bg:SetAllPoints(rf)
                rf._bg:Hide()
                rf._divider = rf:CreateTexture(nil, "ARTWORK")
                rf._divider:SetWidth(1)
                rf._divider:SetColorTexture(1, 1, 1, 0.05)
                rf._divider:Hide()
                rowFrames[idx] = rf
            end
            return rf
        end

        local function HideAllRowFrames()
            for _, rf in pairs(rowFrames) do
                rf:Hide()
                rf._divider:Hide()
                rf._bg:Hide()
            end
        end

        local function RelayoutFullWidth()
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
        end

        local function RelayoutDualColumn()
            HideAllRowFrames()

            -- First pass: collect visible rows in order; build a layout plan
            -- that pairs non-header rows and keeps headers full-width.
            -- condFn is intentionally ignored here: V2 tile paradigm keeps
            -- every option visible regardless of related enable toggles
            -- (the old hide-when-disabled behavior lived in the legacy
            -- composer panel). Rows stay in the layout; the user sees
            -- the full surface and can flip toggles without settings
            -- disappearing.
            local plan = {}
            local pending  -- the row waiting to be paired
            for _, row in ipairs(rows) do
                if row.isHeader then
                    if pending then
                        plan[#plan + 1] = { left = pending }
                        pending = nil
                    end
                    plan[#plan + 1] = { header = row }
                else
                    if pending then
                        plan[#plan + 1] = { left = pending, right = row }
                        pending = nil
                    else
                        pending = row
                    end
                end
            end
            if pending then plan[#plan + 1] = { left = pending } end

            -- Second pass: place each plan entry.
            local ly = -10
            local rowIdx = 0
            for _, entry in ipairs(plan) do
                if entry.header then
                    local w = entry.header.widget
                    w:ClearAllPoints()
                    w:SetPoint("TOPLEFT", PAD, ly)
                    w:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, ly)
                    w:Show()
                    ly = ly - entry.header.height
                else
                    rowIdx = rowIdx + 1
                    local rf = AcquireRowFrame(rowIdx)
                    rf:ClearAllPoints()
                    rf:SetPoint("TOPLEFT", content, "TOPLEFT", PAD - 2, ly)
                    rf:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(PAD - 2), ly)
                    rf:SetHeight(CARD_ROW_HEIGHT)
                    rf:Show()

                    -- Alternating bg tint — odd rows (zero-indexed) pick up a
                    -- subtle 2% white fill, even rows stay unfilled.
                    if (rowIdx % 2) == 0 then
                        rf._bg:SetColorTexture(1, 1, 1, 0.02)
                        rf._bg:Show()
                    end

                    local left = entry.left.widget
                    left:ClearAllPoints()
                    left:SetPoint("LEFT", rf, "LEFT", 12, 0)
                    if entry.right then
                        left:SetPoint("RIGHT", rf, "CENTER", -12, 0)
                        local right = entry.right.widget
                        right:ClearAllPoints()
                        right:SetPoint("LEFT", rf, "CENTER", 12, 0)
                        right:SetPoint("RIGHT", rf, "RIGHT", -12, 0)
                        right:Show()
                        -- Center divider between columns
                        rf._divider:ClearAllPoints()
                        rf._divider:SetPoint("TOP", rf, "TOP", 0, -6)
                        rf._divider:SetPoint("BOTTOM", rf, "BOTTOM", 0, 6)
                        rf._divider:Show()
                    else
                        left:SetPoint("RIGHT", rf, "RIGHT", -12, 0)
                    end
                    left:Show()
                    ly = ly - CARD_ROW_HEIGHT
                end
            end
            content:SetHeight(math.abs(ly) + 10)
        end

        local function Relayout()
            if dualColumn then
                RelayoutDualColumn()
            else
                RelayoutFullWidth()
            end
            if onRelayout then onRelayout() end
        end

        for _, row in ipairs(rows) do
            if row.widget.track and not row.condFn then
                row.widget.track:HookScript("OnClick", Relayout)
            end
        end
        if hasCondRows then
            if not content._relayouts then content._relayouts = {} end
            content._relayouts[#content._relayouts + 1] = Relayout
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

-- When the V2 Group Frames tile renders an element tab, it sets this
-- flag so composer collapsibles open by default instead of showing as
-- collapsed section headers. Renderer-hosted tabs get the same flat-content
-- treatment via headerless/borderless markers —
-- this mirrors that behavior for element-builder tabs, which use
-- CreateComposerCollapsible instead of U.CreateCollapsible.
local _composerAutoExpand = false

-- Flat section renderer. Produces the same visual chrome U.CreateCollapsible
-- renders in borderless mode: accent dot + title label +
-- 1px accent underline, then body content. Keeps the element-tab visuals
-- consistent with the sliced-provider tabs (Range & Pet, Appearance, etc.)
-- inside the same Group Frames tile. Returns a frame satisfying the
-- collapsible-section contract (SetPoint/ClearAllPoints/GetHeight, ._title,
-- ._body, ._updateHeight) so RelayoutComposerSections can stack these
-- among regular sections.
local FLAT_HEADER_H = 24       -- matches Utils.HEADER_HEIGHT
local FLAT_HEADER_GAP = 6      -- matches Utils CARD_GAP so widgets line up
local FLAT_BODY_TOP_PAD = 8    -- matches Utils CARD_PAD

local function BuildFlatSection(parent, title, buildFn, sections, masterRelayout)
    local section = CreateFrame("Frame", nil, parent)
    section:SetHeight(1)
    section._title = title
    section._flat = true

    -- Accent color from GUI theme (falls back to the V2 mint default).
    local r, g, b = 0.2, 0.83, 0.6
    local colors = GUI and GUI.Colors
    if colors and colors.accent then
        r, g, b = colors.accent[1], colors.accent[2], colors.accent[3]
    end

    -- Accent dot
    local dot = section:CreateTexture(nil, "OVERLAY")
    dot:SetSize(4, 4)
    dot:SetPoint("TOPLEFT", section, "TOPLEFT", 2, -((FLAT_HEADER_H - 4) / 2))
    dot:SetColorTexture(r, g, b, 1)

    -- Title label (accent-colored)
    local label = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    label:SetTextColor(r, g, b, 1)
    label:SetText(title)

    -- 1px accent underline spanning the section width
    local underline = section:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -FLAT_HEADER_H)
    underline:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -FLAT_HEADER_H)
    underline:SetColorTexture(r, g, b, 0.3)

    local bodyTop = FLAT_HEADER_H + FLAT_HEADER_GAP + FLAT_BODY_TOP_PAD
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -bodyTop)
    body:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -bodyTop)
    body:SetHeight(1)
    section._body = body

    -- Measures the tallest child/region descending from body, same math as
    -- the collapsible path's MeasureBodyContentHeight. buildFn layers can
    -- also set body._contentHeight to short-circuit the measure.
    local function MeasureBody()
        local contentHeight = 0
        if type(body._contentHeight) == "number" and body._contentHeight > 0 then
            contentHeight = body._contentHeight
            body._contentHeight = nil
        end
        local bodyTop = body.GetTop and body:GetTop()
        if bodyTop then
            local maxOffset = 0
            local function Accumulate(region)
                if not region or not region.GetBottom then return end
                if region.IsShown and not region:IsShown() then return end
                local bottom = region:GetBottom()
                if bottom then
                    maxOffset = math.max(maxOffset, bodyTop - bottom)
                end
            end
            local childCount = body.GetNumChildren and body:GetNumChildren() or 0
            for i = 1, childCount do
                Accumulate(select(i, body:GetChildren()))
            end
            local regionCount = body.GetNumRegions and body:GetNumRegions() or 0
            for i = 1, regionCount do
                Accumulate(select(i, body:GetRegions()))
            end
            if maxOffset > 0 then
                contentHeight = math.max(contentHeight, math.ceil(maxOffset + 8))
            end
        end
        if contentHeight <= 0 then contentHeight = 1 end
        return contentHeight
    end

    local function UpdateFlatHeight()
        local h = MeasureBody()
        body:SetHeight(h)
        section:SetHeight(bodyTop + h)
        if masterRelayout then masterRelayout() end
    end
    section._updateHeight = UpdateFlatHeight

    buildFn(body, UpdateFlatHeight)
    UpdateFlatHeight()
    C_Timer.After(0, UpdateFlatHeight)

    if sections then sections[#sections + 1] = section end
    return section
end

local function CreateComposerCollapsible(parent, title, buildFn, sections, masterRelayout)
    if _composerAutoExpand then
        return BuildFlatSection(parent, title, buildFn, sections, masterRelayout)
    end
    local section = CreateFrame("Frame", nil, parent)
    section:SetHeight(COLLAPSIBLE_HEADER_H)
    section._title = title

    local btn = CreateFrame("Button", nil, section)
    btn:SetPoint("TOPLEFT", 0, 0)
    btn:SetPoint("TOPRIGHT", 0, 0)
    btn:SetHeight(COLLAPSIBLE_HEADER_H)

    local chevron = UIKit and UIKit.CreateChevronCaret and UIKit.CreateChevronCaret(btn, {
        point = "LEFT",
        relativeTo = btn,
        relativePoint = "LEFT",
        xPixels = 2,
        yPixels = 0,
        sizePixels = 10,
        lineWidthPixels = 6,
        lineHeightPixels = 1,
        expanded = false,
        collapsedDirection = "right",
        r = 0.376,
        g = 0.647,
        b = 0.980,
        a = 1,
    }) or btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not (UIKit and UIKit.CreateChevronCaret) then
        chevron:SetPoint("LEFT", 2, 0)
        chevron:SetText(">")
    end

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
    label:SetText(title)

    local underline = btn:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)

    local bodyClip = CreateFrame("Frame", nil, section)
    bodyClip:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -COLLAPSIBLE_HEADER_H)
    bodyClip:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -COLLAPSIBLE_HEADER_H)
    bodyClip:SetHeight(0)
    bodyClip:Hide()

    local body = CreateFrame("Frame", nil, bodyClip)
    body:SetPoint("TOPLEFT", bodyClip, "TOPLEFT", 0, 0)
    body:SetPoint("TOPRIGHT", bodyClip, "TOPRIGHT", 0, 0)
    body:SetHeight(1)
    body:SetAlpha(0)
    body._logicalSection = section
    bodyClip._logicalSection = section

    section._expanded = false
    section._contentHeight = 1
    section._body = body
    section._bodyClip = bodyClip

    local function LogSectionState(reason, extra)
        ComposerDebugPrint(
            string.format(
                "%s section=%s expanded=%s sectionH=%s bodyH=%s clipH=%s contentH=%s parentH=%s%s",
                reason,
                title,
                section._expanded and "1" or "0",
                ComposerFrameHeight(section),
                ComposerFrameHeight(body),
                ComposerFrameHeight(bodyClip),
                type(section._contentHeight) == "number" and string.format("%.1f", section._contentHeight) or "nil",
                ComposerFrameHeight(parent),
                extra and (" " .. extra) or ""
            )
        )
    end

    local function MeasureBodyContentHeight()
        local bodyTop = body.GetTop and body:GetTop()
        if not bodyTop then return nil end

        local maxOffset = 0
        local function Accumulate(region)
            if not region or not region.GetBottom then return end
            if region.IsShown and not region:IsShown() then return end
            local bottom = region:GetBottom()
            if bottom then
                maxOffset = math.max(maxOffset, bodyTop - bottom)
            end
        end

        local childCount = body.GetNumChildren and body:GetNumChildren() or 0
        for i = 1, childCount do
            Accumulate(select(i, body:GetChildren()))
        end

        local regionCount = body.GetNumRegions and body:GetNumRegions() or 0
        for i = 1, regionCount do
            Accumulate(select(i, body:GetRegions()))
        end

        if maxOffset <= 0 then
            return nil
        end
        return math.ceil(maxOffset + 8)
    end

    local function RefreshContentHeight()
        local contentHeight = 0
        if type(body._contentHeight) == "number" and body._contentHeight > 0 then
            contentHeight = math.max(contentHeight, body._contentHeight)
            body._contentHeight = nil
        end
        if type(bodyClip._contentHeight) == "number" and bodyClip._contentHeight > 0 then
            contentHeight = math.max(contentHeight, bodyClip._contentHeight)
            bodyClip._contentHeight = nil
        end

        local bodyHeight = body.GetHeight and body:GetHeight() or 0
        if bodyHeight and bodyHeight > 0 then
            contentHeight = math.max(contentHeight, bodyHeight)
        end

        local measuredHeight = MeasureBodyContentHeight()
        if measuredHeight and measuredHeight > 0 then
            contentHeight = math.max(contentHeight, measuredHeight)
        end

        if contentHeight <= 0 then
            contentHeight = section._contentHeight or 1
        end

        section._contentHeight = contentHeight
        body:SetHeight(contentHeight)
        return contentHeight
    end

    local function ApplyExpandedState(currentHeight)
        local maxHeight = section._contentHeight or 0
        local height = math.max(0, math.min(maxHeight, currentHeight or 0))
        bodyClip:SetHeight(height)
        section:SetHeight(COLLAPSIBLE_HEADER_H + height)
    end

    -- EditBox:SetText updates internal state but WoW doesn't re-render
    -- the visual FontString when the EditBox was created inside a hidden
    -- parent hierarchy. Walk children and call _refreshEditBox (which
    -- calls SetCursorPosition to force a visual refresh) when the section
    -- expands. Deferred by one frame so the visibility transition completes.
    local function RefreshChildEditBoxes(frame)
        for _, child in pairs({frame:GetChildren()}) do
            if child._refreshEditBox then child._refreshEditBox() end
            RefreshChildEditBoxes(child)
        end
    end

    local function DeferredRefreshEditBoxes()
        C_Timer.After(0, function()
            if not section._expanded then return end
            RefreshChildEditBoxes(body)
        end)
    end

    local function UpdateSectionHeight()
        local targetHeight = section._expanded and RefreshContentHeight() or 0
        ApplyExpandedState(targetHeight)
        body:SetAlpha(section._expanded and 1 or 0)
        bodyClip:SetShown(section._expanded)
        if section._expanded then DeferredRefreshEditBoxes() end
        LogSectionState("update", string.format("target=%s", type(targetHeight) == "number" and string.format("%.1f", targetHeight) or "nil"))
        if masterRelayout then masterRelayout() end
    end

    section._updateHeight = UpdateSectionHeight

    buildFn(body, UpdateSectionHeight)

    local function ApplyColors()
        local colors = GUI and GUI.Colors
        local r, g, b = 0.376, 0.647, 0.980
        if colors and colors.accent then r, g, b = colors.accent[1], colors.accent[2], colors.accent[3] end
        if UIKit and UIKit.SetChevronCaretColor then
            UIKit.SetChevronCaretColor(chevron, r, g, b, 1)
        else
            chevron:SetTextColor(r, g, b, 1)
        end
        label:SetTextColor(r, g, b, 1)
        underline:SetColorTexture(r, g, b, 0.3)
        btn:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
            if UIKit and UIKit.SetChevronCaretColor then
                UIKit.SetChevronCaretColor(chevron, 1, 1, 1, 1)
            else
                chevron:SetTextColor(1, 1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function()
            label:SetTextColor(r, g, b, 1)
            if UIKit and UIKit.SetChevronCaretColor then
                UIKit.SetChevronCaretColor(chevron, r, g, b, 1)
            else
                chevron:SetTextColor(r, g, b, 1)
            end
        end)
    end
    ApplyColors()

    btn:SetScript("OnClick", function()
        LogSectionState("click-before")
        section._expanded = not section._expanded
        local targetHeight = section._expanded and RefreshContentHeight() or 0
        local currentHeight = bodyClip:GetHeight() or 0
        if section._expanded then
            if UIKit and UIKit.SetChevronCaretExpanded then
                UIKit.SetChevronCaretExpanded(chevron, true)
            else
                chevron:SetText("v")
            end
        else
            if UIKit and UIKit.SetChevronCaretExpanded then
                UIKit.SetChevronCaretExpanded(chevron, false)
            else
                chevron:SetText(">")
            end
        end
        if UIKit and UIKit.AnimateValue and UIKit.CancelValueAnimation then
            UIKit.CancelValueAnimation(section, "composerCollapsible")
            bodyClip:Show()
            body:SetAlpha(1)
            if section._expanded then DeferredRefreshEditBoxes() end
            UIKit.AnimateValue(section, "composerCollapsible", {
                fromValue = currentHeight,
                toValue = targetHeight,
                duration = ((_G.QUI and _G.QUI.GUI and _G.QUI.GUI._sidebarAnimDuration) or 0.16),
                onUpdate = function(_, progressHeight)
                    ApplyExpandedState(progressHeight)
                    if masterRelayout then masterRelayout() end
                end,
                onFinish = function()
                    local resolvedHeight = section._expanded and RefreshContentHeight() or 0
                    ApplyExpandedState(resolvedHeight)
                    body:SetAlpha(section._expanded and 1 or 0)
                    bodyClip:SetShown(section._expanded)
                    LogSectionState("anim-finish", string.format("target=%s", type(resolvedHeight) == "number" and string.format("%.1f", resolvedHeight) or "nil"))
                    if masterRelayout then masterRelayout() end
                end,
            })
        else
            if UIKit and UIKit.CancelValueAnimation then
                UIKit.CancelValueAnimation(section, "composerCollapsible")
            end
            UpdateSectionHeight()
        end
        LogSectionState("click-after")
    end)

    RefreshContentHeight()
    C_Timer.After(0, function()
        if not section or not body then return end
        RefreshContentHeight()
        ApplyExpandedState(section._expanded and section._contentHeight or 0)
        LogSectionState("deferred")
        if masterRelayout then masterRelayout() end
    end)

    if sections then sections[#sections + 1] = section end
    return section
end

local function RelayoutComposerSections(content, sections)
    local cy = -4
    local prevSection
    for _, s in ipairs(sections) do
        if (not s._composerLayoutAnchored) or s._composerLayoutPrev ~= prevSection then
            s:ClearAllPoints()
            if prevSection then
                s:SetPoint("TOPLEFT", prevSection, "BOTTOMLEFT", 0, -2)
                s:SetPoint("TOPRIGHT", prevSection, "BOTTOMRIGHT", 0, -2)
            else
                s:SetPoint("TOPLEFT", content, "TOPLEFT", 0, cy)
                s:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, cy)
            end
            s._composerLayoutPrev = prevSection
            s._composerLayoutAnchored = true
        end
        cy = cy - s:GetHeight() - 2
        prevSection = s
    end
    content:SetHeight(math.abs(cy) + 8)
    ComposerDebugPrint(
        string.format(
            "relayout panel=%s contentH=%s sections=%s",
            content._composerElementKey or "?",
            ComposerFrameHeight(content),
            ComposerSectionSummary(sections)
        )
    )
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
    local healAbsorbs = gfdb.healAbsorbs; if not healAbsorbs then gfdb.healAbsorbs = {} healAbsorbs = gfdb.healAbsorbs end
    local healPred = gfdb.healPrediction; if not healPred then gfdb.healPrediction = {} healPred = gfdb.healPrediction end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Health Bar", function(body, updateH)
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormDropdown(body, "Health Texture", GetTextureList(), "texture", general, onChange, { description = "Statusbar texture used for the health bar. Supports SharedMedia — install the SharedMedia addon to add more." }), DROP_ROW)
        L:Row(GUI:CreateFormSlider(body, "Health Opacity", 0, 1, 0.05, "defaultHealthOpacity", general, onChange, nil, { description = "Opacity of the filled portion of the health bar. 1.0 is fully opaque." }), SLIDER_HEIGHT)
        L:Row(GUI:CreateFormDropdown(body, "Fill Direction", HEALTH_FILL_OPTIONS, "healthFillDirection", health, onChange, { description = "Direction the health fill drains toward as the unit loses health." }), DROP_ROW)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Health Text", function(body, updateH)
        local cond = function() return health.showHealthText end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Health Text", "showHealthText", health, onChange, { description = "Show the unit's health as text on this frame. Use Display Style below to pick the format." }), FORM_ROW)
        L:Row(GUI:CreateFormDropdown(body, "Display Style", HEALTH_DISPLAY_OPTIONS, "healthDisplayStyle", health, onChange, { description = "How health is formatted: percent only, raw value, value-plus-percent (either order), or missing health as a negative percent/value." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Font Size", 6, 24, 1, "healthFontSize", health, onChange, nil, { description = "Font size used for the health text." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "healthAnchor", health, onChange, { description = "Where on the frame the health text is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Text Justify", TEXT_JUSTIFY_OPTIONS, "healthJustify", health, onChange, { description = "Horizontal text alignment within the health text region (left, center, right)." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "healthOffsetX", health, onChange, nil, { description = "Horizontal pixel offset for the health text from its anchor. Positive moves right, negative moves left." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "healthOffsetY", health, onChange, nil, { description = "Vertical pixel offset for the health text from its anchor. Positive moves up, negative moves down." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormColorPicker(body, "Text Color", "healthTextColor", health, onChange, nil, { description = "Color used for the health text when class/reaction coloring is not applied to health text." }), FORM_ROW, cond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Absorb Shield", function(body, updateH)
        local absorbCond = function() return absorbs.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Absorb Shield", "enabled", absorbs, onChange, { description = "Overlay an indicator on the health bar showing the size of incoming damage absorbs." }), FORM_ROW)
        L:Row(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", absorbs, onChange, { description = "Tint the absorb overlay with the unit's class color instead of the Absorb Color swatch below." }), FORM_ROW, absorbCond)
        L:Row(GUI:CreateFormColorPicker(body, "Absorb Color", "color", absorbs, onChange, nil, { description = "Tint used for the absorb overlay when Use Class Color is off." }), FORM_ROW, function() return absorbs.enabled and not absorbs.useClassColor end)
        L:Row(GUI:CreateFormSlider(body, "Absorb Opacity", 0.1, 1, 0.05, "opacity", absorbs, onChange, nil, { description = "Opacity of the absorb shield overlay." }), SLIDER_HEIGHT, absorbCond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Heal Absorb", function(body, updateH)
        local haCond = function() return healAbsorbs.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Heal Absorb", "enabled", healAbsorbs, onChange, { description = "Overlay an indicator on the health bar showing active heal-absorb effects that must be healed through before real healing lands." }), FORM_ROW)
        L:Row(GUI:CreateFormColorPicker(body, "Heal Absorb Color", "color", healAbsorbs, onChange, nil, { description = "Tint used for the heal-absorb overlay." }), FORM_ROW, haCond)
        L:Row(GUI:CreateFormSlider(body, "Heal Absorb Opacity", 0.1, 1, 0.05, "opacity", healAbsorbs, onChange, nil, { description = "Opacity of the heal-absorb overlay." }), SLIDER_HEIGHT, haCond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Heal Prediction", function(body, updateH)
        local healCond = function() return healPred.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Heal Prediction", "enabled", healPred, onChange, { description = "Overlay an indicator on the health bar showing heals being cast on this unit before they land." }), FORM_ROW)
        L:Row(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", healPred, onChange, { description = "Tint the heal-prediction overlay with the caster's class color instead of the Heal Prediction Color swatch below." }), FORM_ROW, healCond)
        L:Row(GUI:CreateFormColorPicker(body, "Heal Prediction Color", "color", healPred, onChange, nil, { description = "Tint used for the incoming-heal overlay when Use Class Color is off." }), FORM_ROW, function() return healPred.enabled and not healPred.useClassColor end)
        L:Row(GUI:CreateFormSlider(body, "Heal Prediction Opacity", 0.1, 1, 0.05, "opacity", healPred, onChange, nil, { description = "Opacity of the incoming-heal overlay." }), SLIDER_HEIGHT, healCond)
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
        L:Row(GUI:CreateFormCheckbox(body, "Show Power Bar", "showPowerBar", power, onChange, { description = "Show a power bar (mana/rage/energy/focus/runic power) below the health bar on this frame." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Height", 1, 12, 1, "powerBarHeight", power, onChange, nil, { description = "Height of the power bar in pixels. Counted as part of the overall frame height." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Only Show for Healers", "powerBarOnlyHealers", power, onChange, { description = "Restrict the power bar to units specced as healers. Useful for focusing attention on mana pools in party/raid." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Only Show for Tanks", "powerBarOnlyTanks", power, onChange, { description = "Restrict the power bar to units specced as tanks. Useful when you only care about rage/runic-power/focus on your frontline." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Use Power Type Color", "powerBarUsePowerColor", power, onChange, { description = "Color the power bar by power type (blue mana, red rage, yellow energy, etc.). Disables the Custom Color swatch below while on." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormColorPicker(body, "Custom Color", "powerBarColor", power, onChange, nil, { description = "Solid color for the power bar when Use Power Type Color is off." }), FORM_ROW, cond)
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
        L:Row(GUI:CreateFormCheckbox(body, "Show Name", "showName", name, onChange, { description = "Show the unit's name on this frame." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Font Size", 6, 24, 1, "nameFontSize", name, onChange, nil, { description = "Font size used for the unit's name." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "nameAnchor", name, onChange, { description = "Where on the frame the name text is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Text Justify", TEXT_JUSTIFY_OPTIONS, "nameJustify", name, onChange, { description = "Horizontal text alignment within the name text region (left, center, right)." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Max Name Length (0 = unlimited)", 0, 20, 1, "maxNameLength", name, onChange, nil, { description = "Truncate names longer than this many characters. Set to 0 to disable truncation entirely." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "nameOffsetX", name, onChange, nil, { description = "Horizontal pixel offset for the name text from its anchor. Positive moves right, negative moves left." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "nameOffsetY", name, onChange, nil, { description = "Vertical pixel offset for the name text from its anchor. Positive moves up, negative moves down." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Use Class Color", "nameTextUseClassColor", name, onChange, { description = "Color the name text by the unit's class or reaction instead of the Text Color swatch below." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormColorPicker(body, "Text Color", "nameTextColor", name, onChange, nil, { description = "Color used for the name when Use Class Color is off." }), FORM_ROW, cond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function AddAuraDurationTextRows(body, layout, auras, prefix, labelPrefix, onChange, enabledCond)
    local textCond = function()
        return enabledCond() and auras["show" .. labelPrefix .. "DurationText"] ~= false
    end
    local staticColorCond = function()
        local useTimeColor = auras[prefix .. "DurationUseTimeColor"]
        if useTimeColor == nil then
            useTimeColor = auras.showDurationColor ~= false
        end
        return textCond() and not useTimeColor
    end

    layout:Row(GUI:CreateFormCheckbox(body, "Show " .. labelPrefix .. " Duration Text", "show" .. labelPrefix .. "DurationText", auras, onChange), FORM_ROW, enabledCond)
    layout:Row(GUI:CreateFormDropdown(body, "Duration Font", GetFontListWithDefault(), prefix .. "DurationFont", auras, onChange, nil, { searchable = true }), DROP_ROW, textCond)
    layout:Row(GUI:CreateFormSlider(body, "Duration Font Size", 6, 24, 1, prefix .. "DurationFontSize", auras, onChange), SLIDER_HEIGHT, textCond)
    layout:Row(GUI:CreateFormDropdown(body, "Duration Anchor", NINE_POINT_OPTIONS, prefix .. "DurationAnchor", auras, onChange), DROP_ROW, textCond)
    layout:Row(GUI:CreateFormSlider(body, "Duration X Offset", -40, 40, 1, prefix .. "DurationOffsetX", auras, onChange), SLIDER_HEIGHT, textCond)
    layout:Row(GUI:CreateFormSlider(body, "Duration Y Offset", -40, 40, 1, prefix .. "DurationOffsetY", auras, onChange), SLIDER_HEIGHT, textCond)
    layout:Row(GUI:CreateFormCheckbox(body, "Use Time-Based Duration Color", prefix .. "DurationUseTimeColor", auras, onChange), FORM_ROW, textCond)
    layout:Row(GUI:CreateFormColorPicker(body, "Duration Text Color", prefix .. "DurationColor", auras, onChange), FORM_ROW, staticColorCond)
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
        local reverseCond = function() return auras.showBuffs and not auras.buffHideSwipe end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Buffs", "showBuffs", auras, syncedOnChange, { description = "Show buff icons on this unit frame." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Buffs", 0, 8, 1, "maxBuffs", auras, syncedOnChange, nil, { description = "Hard cap on how many buff icons this frame displays at once." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 64, 1, "buffIconSize", auras, syncedOnChange, nil, { description = "Pixel size of each buff icon." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Hide Duration Swipe", "buffHideSwipe", auras, syncedOnChange, { description = "Hide the clockwise cooldown swipe animation drawn over buff icons. Duration text (if enabled) keeps working." }), FORM_ROW, cond)
        AddAuraDurationTextRows(body, L, auras, "buff", "Buff", syncedOnChange, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Reverse Swipe", "buffReverseSwipe", auras, syncedOnChange, { description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as time passes." }), FORM_ROW, reverseCond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "buffAnchor", auras, syncedOnChange, { description = "Which corner of the frame the first buff icon is anchored to." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "buffGrowDirection", auras, syncedOnChange, { description = "Direction additional buff icons are added in after the first." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "buffSpacing", auras, syncedOnChange, nil, { description = "Pixel gap between adjacent buff icons." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "buffOffsetX", auras, syncedOnChange, nil, { description = "Horizontal pixel offset for the buff block from its anchor corner." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "buffOffsetY", auras, syncedOnChange, nil, { description = "Vertical pixel offset for the buff block from its anchor corner." }), SLIDER_HEIGHT, cond)
        sectionRelayouts[#sectionRelayouts + 1] = L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Buff Filtering", function(body, updateH)
        local cond = function() return auras.showBuffs end
        local classCond = function() return auras.showBuffs and (auras.filterMode or "off") == "classification" end
        local classificationContainer = CreateFrame("Frame", nil, body)
        classificationContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormDropdown(body, "Filter Mode", FILTER_MODE_OPTIONS, "filterMode", auras, syncedOnChange, { description = "Choose how buffs are filtered: off shows everything, classification only shows the categories selected below, whitelist only shows listed spells." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Only My Buffs", "buffFilterOnlyMine", auras, syncedOnChange, { description = "Only show buffs cast by you. Hides buffs applied by other players or NPCs." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Hide Permanent Buffs", "buffHidePermanent", auras, syncedOnChange, { description = "Hide buffs with no remaining duration (e.g. class auras, flasks). Reduces visual noise on raid frames." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Deduplicate Defensives/Indicators", "buffDeduplicateDefensives", auras, syncedOnChange, { description = "Hide buff icons that are already shown by the defensive indicator or an aura indicator, preventing the same buff from appearing twice." }), FORM_ROW, cond)
        L:Row(classificationContainer, FORM_ROW * 3, classCond)
        local classY = 0
        local buffClass = auras.buffClassifications; if not buffClass then auras.buffClassifications = {} buffClass = auras.buffClassifications end
        local c1 = GUI:CreateFormCheckbox(classificationContainer, "Raid", "raid", buffClass, syncedOnChange, { description = "Include buffs flagged by Blizzard as raid-relevant (e.g. healing cooldowns, external buffs)." }); c1:SetPoint("TOPLEFT", 0, classY); c1:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local c2 = GUI:CreateFormCheckbox(classificationContainer, "Cancelable", "cancelable", buffClass, syncedOnChange, { description = "Include buffs you can right-click to cancel (mostly your own player buffs)." }); c2:SetPoint("TOPLEFT", 0, classY); c2:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local c5 = GUI:CreateFormCheckbox(classificationContainer, "Important", "important", buffClass, syncedOnChange, { description = "Include buffs flagged by Blizzard as important (key cooldowns and notable effects)." }); c5:SetPoint("TOPLEFT", 0, classY); c5:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
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
        local reverseCond = function() return auras.showDebuffs and not auras.debuffHideSwipe end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Show Debuffs", "showDebuffs", auras, syncedOnChange, { description = "Show debuff icons on this unit frame." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Debuffs", 0, 8, 1, "maxDebuffs", auras, syncedOnChange, nil, { description = "Hard cap on how many debuff icons this frame displays at once." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 64, 1, "debuffIconSize", auras, syncedOnChange, nil, { description = "Pixel size of each debuff icon." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Hide Duration Swipe", "debuffHideSwipe", auras, syncedOnChange, { description = "Hide the clockwise cooldown swipe animation drawn over debuff icons. Duration text (if enabled) keeps working." }), FORM_ROW, cond)
        AddAuraDurationTextRows(body, L, auras, "debuff", "Debuff", syncedOnChange, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Reverse Swipe", "debuffReverseSwipe", auras, syncedOnChange, { description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as time passes." }), FORM_ROW, reverseCond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "debuffAnchor", auras, syncedOnChange, { description = "Which corner of the frame the first debuff icon is anchored to." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "debuffGrowDirection", auras, syncedOnChange, { description = "Direction additional debuff icons are added in after the first." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "debuffSpacing", auras, syncedOnChange, nil, { description = "Pixel gap between adjacent debuff icons." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "debuffOffsetX", auras, syncedOnChange, nil, { description = "Horizontal pixel offset for the debuff block from its anchor corner." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "debuffOffsetY", auras, syncedOnChange, nil, { description = "Vertical pixel offset for the debuff block from its anchor corner." }), SLIDER_HEIGHT, cond)
        sectionRelayouts[#sectionRelayouts + 1] = L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Debuff Filtering", function(body, updateH)
        local cond = function() return auras.showDebuffs end
        local classCond = function() return auras.showDebuffs and (auras.filterMode or "off") == "classification" end
        local classificationContainer = CreateFrame("Frame", nil, body)
        classificationContainer:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormDropdown(body, "Filter Mode", FILTER_MODE_OPTIONS, "filterMode", auras, syncedOnChange, { description = "Choose how debuffs are filtered: off shows everything, classification only shows the categories selected below, whitelist only shows listed spells." }), DROP_ROW, cond)
        L:Row(classificationContainer, FORM_ROW * 3, classCond)
        local classY = 0
        local debuffClass = auras.debuffClassifications; if not debuffClass then auras.debuffClassifications = {} debuffClass = auras.debuffClassifications end
        local d1 = GUI:CreateFormCheckbox(classificationContainer, "Raid", "raid", debuffClass, syncedOnChange, { description = "Include debuffs flagged by Blizzard as raid-relevant (boss mechanics, dispellables, incoming damage effects)." }); d1:SetPoint("TOPLEFT", 0, classY); d1:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local d2 = GUI:CreateFormCheckbox(classificationContainer, "Crowd Control", "crowdControl", debuffClass, syncedOnChange, { description = "Include crowd-control debuffs (stuns, fears, roots, silences, etc.)." }); d2:SetPoint("TOPLEFT", 0, classY); d2:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
        local d3 = GUI:CreateFormCheckbox(classificationContainer, "Important", "important", debuffClass, syncedOnChange, { description = "Include debuffs flagged by Blizzard as important (key mechanics and notable effects)." }); d3:SetPoint("TOPLEFT", 0, classY); d3:SetPoint("RIGHT", classificationContainer, "RIGHT", 0, 0); classY = classY - FORM_ROW
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
        L:Row(GUI:CreateFormCheckbox(body, "Show Role Icon", "showRoleIcon", ind, onChange, { description = "Show the unit's assigned group role icon (tank/healer/DPS) on this frame." }), FORM_ROW)
        L:Row(GUI:CreateFormCheckbox(body, "Show Tank", "showRoleTank", ind, onChange, { description = "Include the tank role icon on units specced as tanks." }), FORM_ROW, roleCond)
        L:Row(GUI:CreateFormCheckbox(body, "Show Healer", "showRoleHealer", ind, onChange, { description = "Include the healer role icon on units specced as healers." }), FORM_ROW, roleCond)
        L:Row(GUI:CreateFormCheckbox(body, "Show DPS", "showRoleDPS", ind, onChange, { description = "Include the DPS role icon on units specced as damage dealers." }), FORM_ROW, roleCond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 6, 24, 1, "roleIconSize", ind, onChange, nil, { description = "Pixel size of the role icon." }), SLIDER_HEIGHT, roleCond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "roleIconAnchor", ind, onChange, { description = "Where on the frame the role icon is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW, roleCond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "roleIconOffsetX", ind, onChange, nil, { description = "Horizontal pixel offset for the role icon from its anchor. Positive moves right, negative moves left." }), SLIDER_HEIGHT, roleCond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "roleIconOffsetY", ind, onChange, nil, { description = "Vertical pixel offset for the role icon from its anchor. Positive moves up, negative moves down." }), SLIDER_HEIGHT, roleCond)
        L:Finish()
    end, sections, relayout)

    local function AddIndicatorCollapsible(label, showKey, sizeKey, anchorKey, offXKey, offYKey)
        CreateComposerCollapsible(content, label, function(body, updateH)
            local cond = function() return ind[showKey] end
            local L = CreateDynamicLayout(body, updateH)
            L:Row(GUI:CreateFormCheckbox(body, "Enable", showKey, ind, onChange, { description = "Show the " .. label .. " indicator on this unit frame." }), FORM_ROW)
            L:Row(GUI:CreateFormSlider(body, "Icon Size", 6, 32, 1, sizeKey, ind, onChange, nil, { description = "Pixel size of the " .. label .. " indicator." }), SLIDER_HEIGHT, cond)
            L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, anchorKey, ind, onChange, { description = "Where on the frame the " .. label .. " indicator is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW, cond)
            L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, offXKey, ind, onChange, nil, { description = "Horizontal pixel offset for the " .. label .. " indicator from its anchor." }), SLIDER_HEIGHT, cond)
            L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, offYKey, ind, onChange, nil, { description = "Vertical pixel offset for the " .. label .. " indicator from its anchor." }), SLIDER_HEIGHT, cond)
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
        L:Row(GUI:CreateFormCheckbox(body, "Show Threat Border", "showThreatBorder", ind, onChange, { description = "Outline the frame border when the unit has aggro on an NPC, making threat changes easy to spot at a glance." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Border Size", 1, 16, 1, "threatBorderSize", ind, onChange, nil, { description = "Pixel thickness of the threat border." }), SLIDER_HEIGHT, threatCond)
        L:Row(GUI:CreateFormColorPicker(body, "Threat Color", "threatColor", ind, onChange, nil, { description = "Color used for the threat border and optional fill tint." }), FORM_ROW, threatCond)
        L:Row(GUI:CreateFormSlider(body, "Threat Fill Opacity", 0, 0.5, 0.05, "threatFillOpacity", ind, onChange, nil, { description = "Opacity of a color tint applied across the health bar when the unit has aggro. Set to 0 to keep only the border." }), SLIDER_HEIGHT, threatCond)
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
        local desc = GUI:CreateLabel(body, "Colors the frame border when a dispellable debuff is active, including Blizzard private dispels when available.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        L:Row(desc, 26)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Dispel Overlay", "enabled", dispel, onChange, { description = "Outline the frame border in the dispel type's color when a dispellable debuff is active on the unit." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Border Size", 1, 16, 1, "borderSize", dispel, onChange, nil, { description = "Pixel thickness of the dispel border." }), SLIDER_HEIGHT, dispelCond)
        L:Row(GUI:CreateFormSlider(body, "Border Opacity", 0.1, 1, 0.05, "opacity", dispel, onChange, nil, { description = "Opacity of the dispel-type colored border." }), SLIDER_HEIGHT, dispelCond)
        L:Row(GUI:CreateFormSlider(body, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", dispel, onChange, nil, { description = "Opacity of a color tint applied across the health bar when a dispellable debuff is active. Set to 0 to keep only the border." }), SLIDER_HEIGHT, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Magic Color", "Magic", dispelColors, onChange, nil, { description = "Color used when the active dispellable debuff is of Magic type." }), FORM_ROW, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Curse Color", "Curse", dispelColors, onChange, nil, { description = "Color used when the active dispellable debuff is of Curse type." }), FORM_ROW, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Disease Color", "Disease", dispelColors, onChange, nil, { description = "Color used when the active dispellable debuff is of Disease type." }), FORM_ROW, dispelCond)
        L:Row(GUI:CreateFormColorPicker(body, "Poison Color", "Poison", dispelColors, onChange, nil, { description = "Color used when the active dispellable debuff is of Poison type." }), FORM_ROW, dispelCond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Target Highlight", function(body, updateH)
        local targetCond = function() return targetHL.enabled end
        local L = CreateDynamicLayout(body, updateH)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Target Highlight", "enabled", targetHL, onChange, { description = "Highlight the frame representing your current target so it stands out in party/raid at a glance." }), FORM_ROW)
        L:Row(GUI:CreateFormColorPicker(body, "Highlight Color", "color", targetHL, onChange, nil, { description = "Color used for the target highlight border and optional fill tint." }), FORM_ROW, targetCond)
        L:Row(GUI:CreateFormSlider(body, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", targetHL, onChange, nil, { description = "Opacity of a color tint applied across the targeted unit's health bar. Set to 0 to keep only the border highlight." }), SLIDER_HEIGHT, targetCond)
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
        L:Row(GUI:CreateFormCheckbox(body, "Enable Defensive Indicator", "enabled", def, onChange, { description = "Show a dedicated icon strip for active defensive cooldowns (Ironbark, Pain Suppression, etc.) on this frame." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Icons", 1, 5, 1, "maxIcons", def, onChange, nil, { description = "Hard cap on how many defensive icons this frame displays at once." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 32, 1, "iconSize", def, onChange, nil, { description = "Pixel size of each defensive icon." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Reverse Swipe", "reverseSwipe", def, onChange, { description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the defensive ticks down." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", def, onChange, { description = "Direction additional defensive icons are added in after the first." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "spacing", def, onChange, nil, { description = "Pixel gap between adjacent defensive icons." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Position", NINE_POINT_OPTIONS, "position", def, onChange, { description = "Where on the frame the defensive icon strip is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "offsetX", def, onChange, nil, { description = "Horizontal pixel offset for the defensive icons from their anchor." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "offsetY", def, onChange, nil, { description = "Vertical pixel offset for the defensive icons from their anchor." }), SLIDER_HEIGHT, cond)
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
        L:Row(GUI:CreateFormCheckbox(body, "Enable Private Auras", "enabled", pa, onChange, { description = "Anchor Blizzard private aura indicators (only visible to the afflicted player, e.g. raid mechanic markers) to this frame." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Max Per Frame", 1, 5, 1, "maxPerFrame", pa, onChange, nil, { description = "Hard cap on how many private aura slots this frame displays at once." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 10, 40, 1, "iconSize", pa, onChange, nil, { description = "Pixel size of each private aura icon." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", pa, onChange, { description = "Direction additional private aura icons are added in after the first." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "spacing", pa, onChange, nil, { description = "Pixel gap between adjacent private aura icons." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "anchor", pa, onChange, { description = "Where on the frame the first private aura icon is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "anchorOffsetX", pa, onChange, nil, { description = "Horizontal pixel offset for the private aura block from its anchor." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "anchorOffsetY", pa, onChange, nil, { description = "Vertical pixel offset for the private aura block from its anchor." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Border Scale", -100, 10, 0.5, "borderScale", pa, onChange, nil, { description = "Scale applied to the Blizzard-drawn border around each private aura icon. Negative values shrink, positive values enlarge." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Show Countdown", "showCountdown", pa, onChange, { description = "Show the cooldown swipe animation over private aura icons." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Show Countdown Numbers", "showCountdownNumbers", pa, onChange, { description = "Show the remaining-duration countdown text over private aura icons." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Reverse Swipe", "reverseSwipe", pa, onChange, { description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the aura ticks down." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Stack & Countdown Scale", 0.5, 5, 0.5, "textScale", pa, onChange, nil, { description = "Scale multiplier for the stack count and countdown number text on private aura icons." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Stack & Countdown X Offset", -20, 20, 1, "textOffsetX", pa, onChange, nil, { description = "Horizontal pixel offset for the stack count and countdown number text on private aura icons." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Stack & Countdown Y Offset", -20, 20, 1, "textOffsetY", pa, onChange, nil, { description = "Vertical pixel offset for the stack count and countdown number text on private aura icons." }), SLIDER_HEIGHT, cond)
        L:Finish()
    end, sections, relayout)

    relayout()
end

local function BuildAuraIndicatorsSettings(content, gfdb, onChange)
    local ai = gfdb.auraIndicators; if not ai then gfdb.auraIndicators = {} ai = gfdb.auraIndicators end
    local normalizeAuraIndicators = ns.Helpers and ns.Helpers.NormalizeAuraIndicatorConfig
    if normalizeAuraIndicators then normalizeAuraIndicators(ai) end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    CreateComposerCollapsible(content, "Aura Indicator Defaults", function(body, updateH)
        local cond = function() return ai.enabled end
        local reverseCond = function() return ai.enabled and not ai.hideSwipe end
        local L = CreateDynamicLayout(body, updateH)
        local desc = GUI:CreateLabel(body, "Icon indicators still use the shared strip settings below. Bars and health-bar tints are configured per aura entry.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        L:Row(desc, 40)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Aura Indicators", "enabled", ai, onChange, { description = "Track specific buffs/debuffs and display them as icons, bars, or health-bar tints on this frame. Configure tracked auras in the section below." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Icon Size", 8, 32, 1, "iconSize", ai, onChange, nil, { description = "Pixel size of each aura-indicator icon in the shared icon strip." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Max Indicators", 1, 10, 1, "maxIndicators", ai, onChange, nil, { description = "Hard cap on how many aura-indicator icons this frame displays in the shared icon strip." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Hide Duration Swipe", "hideSwipe", ai, onChange, { description = "Hide the clockwise cooldown swipe animation drawn over aura-indicator icons." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Reverse Swipe", "reverseSwipe", ai, onChange, { description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the aura ticks down." }), FORM_ROW, reverseCond)
        L:Row(GUI:CreateFormDropdown(body, "Anchor", NINE_POINT_OPTIONS, "anchor", ai, onChange, { description = "Where on the frame the aura-indicator icon strip is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormDropdown(body, "Grow Direction", AURA_GROW_OPTIONS, "growDirection", ai, onChange, { description = "Direction additional aura-indicator icons are added in after the first." }), DROP_ROW, cond)
        L:Row(GUI:CreateFormSlider(body, "Spacing", 0, 8, 1, "spacing", ai, onChange, nil, { description = "Pixel gap between adjacent aura-indicator icons." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "X Offset", -100, 100, 1, "anchorOffsetX", ai, onChange, nil, { description = "Horizontal pixel offset for the aura-indicator icon strip from its anchor." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Y Offset", -100, 100, 1, "anchorOffsetY", ai, onChange, nil, { description = "Vertical pixel offset for the aura-indicator icon strip from its anchor." }), SLIDER_HEIGHT, cond)
        L:Finish()
    end, sections, relayout)

    CreateComposerCollapsible(content, "Tracked Auras", function(body, updateH)
        if normalizeAuraIndicators then normalizeAuraIndicators(ai) end

        local auraRows = {}
        local suggestRows = {}
        local indicatorRows = {}
        local detailWidgets = {}
        local selectedAuraIndex = 1
        local selectedIndicatorIndex = 1

        local title = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", PAD, -6)

        local subtitle = GUI:CreateLabel(body, "Add tracked auras, then attach one or more indicator types to each aura.", 11, C and C.textMuted)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetPoint("TOPLEFT", PAD, -24)
        subtitle:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)

        local auraListArea = CreateFrame("Frame", nil, body)
        auraListArea:SetPoint("TOPLEFT", PAD, -48)
        auraListArea:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        auraListArea:SetHeight(1)
        local AURA_ROW_HEIGHT, AURA_ROW_STEP = 28, 30
        local INDICATOR_ROW_HEIGHT, INDICATOR_ROW_STEP = 24, 26

        local auraRowsContainer = CreateFrame("Frame", nil, auraListArea)
        auraRowsContainer:SetPoint("TOPLEFT", 0, 0)
        auraRowsContainer:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
        auraRowsContainer:SetHeight(1)

        local indicatorRowsContainer = CreateFrame("Frame", nil, auraListArea)
        indicatorRowsContainer:SetPoint("TOPLEFT", 0, 0)
        indicatorRowsContainer:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
        indicatorRowsContainer:SetHeight(1)

        local addHeader = auraListArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addHeader:SetJustifyH("LEFT")

        local inputRow = CreateFrame("Frame", nil, auraListArea)
        inputRow:SetHeight(24)

        local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
        inputBox:SetSize(80, 20)
        inputBox:SetPoint("LEFT", 4, 0)
        inputBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        inputBox:SetBackdropColor(0.06, 0.06, 0.08, 1)
        inputBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        inputBox:SetFontObject("GameFontNormalSmall")
        inputBox:SetAutoFocus(false)
        inputBox:SetMaxLetters(10)
        inputBox:SetTextInsets(4, 4, 0, 0)
        inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local inputLabel = inputRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        inputLabel:SetPoint("LEFT", inputBox, "RIGHT", 4, 0)
        inputLabel:SetText("Spell ID")
        inputLabel:SetTextColor(0.5, 0.5, 0.5)

        local addManualBtn = CreateFrame("Button", nil, inputRow, "BackdropTemplate")
        addManualBtn:SetSize(40, 20)
        addManualBtn:SetPoint("RIGHT", inputRow, "RIGHT", -2, 0)
        addManualBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        addManualBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        addManualBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        local addManualText = addManualBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addManualText:SetPoint("CENTER")
        addManualText:SetText("Add")

        local indicatorActionsRow = CreateFrame("Frame", nil, auraListArea)
        indicatorActionsRow:SetHeight(26)
        indicatorActionsRow:SetPoint("TOPLEFT", auraListArea, "TOPLEFT", 0, 0)
        indicatorActionsRow:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)

        local addIconBtn = GUI:CreateButton(indicatorActionsRow, "Add Icon", 74, 22)
        addIconBtn:SetPoint("LEFT", 0, 0)
        local addBarBtn = GUI:CreateButton(indicatorActionsRow, "Add Bar", 68, 22)
        addBarBtn:SetPoint("LEFT", addIconBtn, "RIGHT", 6, 0)
        local addTintBtn = GUI:CreateButton(indicatorActionsRow, "Add Tint", 72, 22)
        addTintBtn:SetPoint("LEFT", addBarBtn, "RIGHT", 6, 0)

        local selectedAuraLabel = auraListArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        selectedAuraLabel:SetJustifyH("LEFT")

        local detailArea = CreateFrame("Frame", nil, auraListArea)
        detailArea:SetPoint("TOPLEFT", auraListArea, "TOPLEFT", 0, 0)
        detailArea:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
        detailArea:SetHeight(1)

        local function CreateDropPlaceholder(parent, height)
            local placeholder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            placeholder:SetHeight(height)
            ApplyPixelBackdrop(placeholder, 1, true)
            placeholder:SetBackdropColor(C.accent[1] or 0.3, C.accent[2] or 0.7, C.accent[3] or 1, 0.12)
            placeholder:SetBackdropBorderColor(C.accent[1] or 0.3, C.accent[2] or 0.7, C.accent[3] or 1, 0.85)
            placeholder:Hide()
            return placeholder
        end

        local auraPlaceholder = CreateDropPlaceholder(auraRowsContainer, AURA_ROW_HEIGHT)
        local indicatorPlaceholder = CreateDropPlaceholder(indicatorRowsContainer, INDICATOR_ROW_HEIGHT)
        local auraDragState = {}
        local indicatorDragState = {}

        local function NotifyChanged()
            if normalizeAuraIndicators then normalizeAuraIndicators(ai) end
            if onChange then onChange() end
        end

        local function LayoutDraggableRows(container, rows, placeholder, rowHeight, rowStep, skipRow, insertIndex)
            local nextY = 0
            local placedPlaceholder = false

            for idx, row in ipairs(rows) do
                if skipRow and insertIndex == idx and not placedPlaceholder then
                    placeholder:ClearAllPoints()
                    placeholder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
                    placeholder:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    placeholder:Show()
                    nextY = nextY - rowStep
                    placedPlaceholder = true
                end

                if row ~= skipRow then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
                    row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    nextY = nextY - rowStep
                end
            end

            if skipRow and not placedPlaceholder then
                placeholder:ClearAllPoints()
                placeholder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nextY)
                placeholder:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                placeholder:Show()
                nextY = nextY - rowStep
            elseif placeholder then
                placeholder:Hide()
            end

            local usedHeight = math.max(0, math.abs(nextY))
            container:SetHeight(math.max(1, usedHeight))
            return usedHeight
        end

        local function ComputeDropIndex(rows, container, rowStep)
            local rowCount = #rows
            if rowCount <= 1 then
                return 1
            end

            local scale = UIParent:GetEffectiveScale() or 1
            local _, cursorY = GetCursorPosition()
            cursorY = (cursorY or 0) / scale
            local topY = container:GetTop()
            if not topY then
                return rowCount
            end

            local relative = topY - cursorY
            local slot = math.floor((relative + (rowStep * 0.5)) / rowStep) + 1
            if slot < 1 then slot = 1 end
            if slot > (rowCount + 1) then slot = rowCount + 1 end
            return slot
        end

        local function CommitReorder(list, fromIndex, toIndex)
            if type(list) ~= "table" then
                return false, fromIndex
            end

            local len = #list
            if fromIndex < 1 or fromIndex > len then
                return false, fromIndex
            end

            local targetIndex = toIndex
            if targetIndex > fromIndex then
                targetIndex = targetIndex - 1
            end
            if targetIndex < 1 then targetIndex = 1 end
            if targetIndex > len then targetIndex = len end
            if targetIndex == fromIndex then
                return false, fromIndex
            end

            local moving = table.remove(list, fromIndex)
            table.insert(list, targetIndex, moving)
            return true, targetIndex
        end

        local function RemapSelectedIndex(selectedIndex, fromIndex, toIndex)
            if not selectedIndex then
                return selectedIndex
            end
            if selectedIndex == fromIndex then
                return toIndex
            end
            if fromIndex < selectedIndex and toIndex >= selectedIndex then
                return selectedIndex - 1
            end
            if fromIndex > selectedIndex and toIndex <= selectedIndex then
                return selectedIndex + 1
            end
            return selectedIndex
        end

        local function CountIndicatorTypes(entry)
            local icons, bars, tints = 0, 0, 0
            for _, indicator in ipairs(entry.indicators or {}) do
                if indicator.type == "bar" then
                    bars = bars + 1
                elseif indicator.type == "healthBarColor" then
                    tints = tints + 1
                else
                    icons = icons + 1
                end
            end
            return icons, bars, tints
        end

        local function GetIndicatorLabel(indicator, index)
            if indicator.type == "bar" then
                return "Bar " .. index
            elseif indicator.type == "healthBarColor" then
                return "Health Bar Tint " .. index
            end
            return "Icon " .. index
        end

        local function AcquireAuraRow()
            local row = table.remove(auraRows)
            if row then
                row:Show()
                row:ClearAllPoints()
                return row
            end

            row = CreateFrame("Button", nil, auraListArea, "BackdropTemplate")
            row:SetHeight(28)
            row:RegisterForClicks("LeftButtonUp")
            row:SetMovable(true)
            row:RegisterForDrag("LeftButton")
            ApplyPixelBackdrop(row, 1, true)

            row.dragHandle = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.dragHandle:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            row.dragHandle:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
            row.dragHandle:SetWidth(22)
            ApplyPixelBackdrop(row.dragHandle, 1, true)
            row.dragHandle:SetBackdropColor(0.14, 0.14, 0.16, 0.65)
            row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
            row.dragHandle:EnableMouse(false)

            row.dragHint = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.dragHint:SetPoint("CENTER", row.dragHandle, "CENTER", 0, 0)
            row.dragHint:SetText("::")
            row.dragHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", row.dragHandle, "RIGHT", 6, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetJustifyH("LEFT")

            row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.summary:SetJustifyH("RIGHT")

            row.remove = CreateFrame("Button", nil, row)
            row.remove:SetSize(18, 18)
            row.remove:SetPoint("RIGHT", -4, 0)
            row.removeText = row.remove:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.removeText:SetPoint("CENTER")
            row.removeText:SetText("\195\151")
            row.removeText:SetTextColor(0.8, 0.3, 0.3)
            row.remove:SetScript("OnEnter", function() row.removeText:SetTextColor(1, 0.4, 0.4) end)
            row.remove:SetScript("OnLeave", function() row.removeText:SetTextColor(0.8, 0.3, 0.3) end)
            row.summary:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)

            return row
        end

        local activeAuraRows = {}
        local function ReleaseAuraRows()
            for _, row in ipairs(activeAuraRows) do
                row:Hide()
                row:ClearAllPoints()
                row.remove:SetScript("OnClick", nil)
                row:SetScript("OnDragStart", nil)
                row:SetScript("OnDragStop", nil)
                row:SetScript("OnUpdate", nil)
                row:SetScript("OnClick", nil)
                row:SetAlpha(1)
                if row.dragHandle then
                    row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
                end
                table.insert(auraRows, row)
            end
            wipe(activeAuraRows)
        end

        local function AcquireSuggestRow()
            local row = table.remove(suggestRows)
            if row then
                row:Show()
                row:ClearAllPoints()
                return row
            end

            row = CreateFrame("Frame", nil, auraListArea)
            row:SetHeight(22)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("LEFT", 4, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetJustifyH("LEFT")

            row.add = CreateFrame("Button", nil, row)
            row.add:SetSize(18, 18)
            row.add:SetPoint("RIGHT", -2, 0)
            row.addText = row.add:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.addText:SetPoint("CENTER")
            row.addText:SetText("+")
            row.addText:SetTextColor(0.3, 0.8, 0.3)

            return row
        end

        local activeSuggestRows = {}
        local function ReleaseSuggestRows()
            for _, row in ipairs(activeSuggestRows) do
                row:Hide()
                row:ClearAllPoints()
                row.add:SetScript("OnClick", nil)
                table.insert(suggestRows, row)
            end
            wipe(activeSuggestRows)
        end

        local function AcquireIndicatorRow()
            local row = table.remove(indicatorRows)
            if row then
                row:Show()
                row:ClearAllPoints()
                return row
            end

            row = CreateFrame("Button", nil, auraListArea, "BackdropTemplate")
            row:SetHeight(24)
            row:RegisterForClicks("LeftButtonUp")
            row:SetMovable(true)
            row:RegisterForDrag("LeftButton")
            ApplyPixelBackdrop(row, 1, true)

            row.dragHandle = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.dragHandle:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            row.dragHandle:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
            row.dragHandle:SetWidth(22)
            ApplyPixelBackdrop(row.dragHandle, 1, true)
            row.dragHandle:SetBackdropColor(0.14, 0.14, 0.16, 0.65)
            row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
            row.dragHandle:EnableMouse(false)

            row.dragHint = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.dragHint:SetPoint("CENTER", row.dragHandle, "CENTER", 0, 0)
            row.dragHint:SetText("::")
            row.dragHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", row.dragHandle, "RIGHT", 8, 0)
            row.label:SetJustifyH("LEFT")

            row.remove = CreateFrame("Button", nil, row)
            row.remove:SetSize(18, 18)
            row.remove:SetPoint("RIGHT", -4, 0)
            row.removeText = row.remove:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.removeText:SetPoint("CENTER")
            row.removeText:SetText("\195\151")
            row.removeText:SetTextColor(0.8, 0.3, 0.3)
            row.remove:SetScript("OnEnter", function() row.removeText:SetTextColor(1, 0.4, 0.4) end)
            row.remove:SetScript("OnLeave", function() row.removeText:SetTextColor(0.8, 0.3, 0.3) end)

            return row
        end

        local activeIndicatorRows = {}
        local function ReleaseIndicatorRows()
            for _, row in ipairs(activeIndicatorRows) do
                row:Hide()
                row:ClearAllPoints()
                row.remove:SetScript("OnClick", nil)
                row:SetScript("OnDragStart", nil)
                row:SetScript("OnDragStop", nil)
                row:SetScript("OnUpdate", nil)
                row:SetScript("OnClick", nil)
                row:SetAlpha(1)
                if row.dragHandle then
                    row.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
                end
                table.insert(indicatorRows, row)
            end
            wipe(activeIndicatorRows)
        end

        local function ClearDetailWidgets()
            for _, widget in ipairs(detailWidgets) do
                widget:Hide()
            end
            wipe(detailWidgets)
        end

        local function RegisterDetailWidget(widget)
            detailWidgets[#detailWidgets + 1] = widget
            return widget
        end

        local function AddNewAura(spellID)
            if not ai.entries then ai.entries = {} end
            ai.entries[#ai.entries + 1] = {
                spellID = tonumber(spellID) or spellID,
                enabled = true,
                onlyMine = false,
                indicators = {
                    { type = "icon", enabled = true },
                },
            }
            if normalizeAuraIndicators then normalizeAuraIndicators(ai) end
            selectedAuraIndex = #ai.entries
            selectedIndicatorIndex = 1
            NotifyChanged()
        end

        local RebuildAuraList

        local function AddIndicator(indicatorType)
            local entry = ai.entries and ai.entries[selectedAuraIndex]
            if not entry then return end
            entry.indicators[#entry.indicators + 1] = { type = indicatorType, enabled = true }
            if normalizeAuraIndicators then normalizeAuraIndicators(ai) end
            selectedIndicatorIndex = #entry.indicators
            NotifyChanged()
            if RebuildAuraList then RebuildAuraList() end
        end

        addIconBtn:SetScript("OnClick", function() AddIndicator("icon") end)
        addBarBtn:SetScript("OnClick", function() AddIndicator("bar") end)
        addTintBtn:SetScript("OnClick", function() AddIndicator("healthBarColor") end)

        addManualBtn:SetScript("OnClick", function()
            local id = tonumber(inputBox:GetText())
            if id and id > 0 then
                AddNewAura(id)
                inputBox:SetText("")
                inputBox:ClearFocus()
                if RebuildAuraList then RebuildAuraList() end
            end
        end)
        inputBox:SetScript("OnEnterPressed", function()
            local click = addManualBtn:GetScript("OnClick")
            if click then click(addManualBtn) end
        end)

        RebuildAuraList = function()
            if normalizeAuraIndicators then normalizeAuraIndicators(ai) end
            local entries = ai.entries or {}
            if #entries == 0 then
                selectedAuraIndex = 1
                selectedIndicatorIndex = 1
            else
                selectedAuraIndex = math.max(1, math.min(selectedAuraIndex, #entries))
                local selectedEntry = entries[selectedAuraIndex]
                local indicatorCount = #(selectedEntry and selectedEntry.indicators or {})
                selectedIndicatorIndex = math.max(1, math.min(selectedIndicatorIndex, math.max(indicatorCount, 1)))
            end

            ReleaseAuraRows()
            ReleaseSuggestRows()
            ReleaseIndicatorRows()
            ClearDetailWidgets()

            local specID = GetPlayerSpecID()
            local _, specName = specID and GetSpecializationInfoByID(specID) or nil, nil
            if specID then
                local _, specDisplayName = GetSpecializationInfoByID(specID)
                specName = specDisplayName
            end
            title:SetText("|cFF34D399" .. (specName or "Tracked Auras") .. "|r")

            local y = 0
            for idx, entry in ipairs(entries) do
                local row = AcquireAuraRow()
                row:SetParent(auraRowsContainer)

                local tex
                if C_Spell and C_Spell.GetSpellTexture then
                    local ok, t = pcall(C_Spell.GetSpellTexture, entry.spellID)
                    if ok and t then tex = t end
                end
                row.icon:SetTexture(tex or 134400)

                local spellName = GetSpellName(entry.spellID) or ("Spell " .. tostring(entry.spellID))
                row.name:SetText((entry.enabled ~= false and "|cFFFFFFFF" or "|cFF808080") .. spellName .. "|r")

                local iconCount, barCount, tintCount = CountIndicatorTypes(entry)
                row.summary:SetText(string.format(
                    "I:%d B:%d T:%d%s",
                    iconCount,
                    barCount,
                    tintCount,
                    entry.onlyMine and " |cff56D1FFMine|r" or ""
                ))

                local selected = idx == selectedAuraIndex
                row:SetBackdropColor(selected and 0.16 or 0.08, selected and 0.16 or 0.08, selected and 0.2 or 0.08, 0.9)
                row:SetBackdropBorderColor(
                    selected and (C.accent[1] or 0.3) or (C.border[1] or 0.2),
                    selected and (C.accent[2] or 0.7) or (C.border[2] or 0.2),
                    selected and (C.accent[3] or 1) or (C.border[3] or 0.2),
                    1
                )

                row:SetScript("OnClick", function()
                    if auraDragState.suppressClick then
                        auraDragState.suppressClick = nil
                        return
                    end
                    selectedAuraIndex = idx
                    selectedIndicatorIndex = 1
                    RebuildAuraList()
                end)
                row:SetScript("OnDragStart", function(self)
                    auraDragState.active = true
                    auraDragState.row = self
                    auraDragState.fromIndex = idx
                    auraDragState.toIndex = idx
                    auraDragState.baseStrata = self:GetFrameStrata()
                    auraDragState.baseLevel = self:GetFrameLevel()
                    auraDragState.baseAlpha = self:GetAlpha()
                    self:StartMoving()
                    self:SetFrameStrata("TOOLTIP")
                    self:SetFrameLevel(400)
                    self:SetAlpha(0.92)
                    self.dragHandle:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    LayoutDraggableRows(auraRowsContainer, activeAuraRows, auraPlaceholder, AURA_ROW_HEIGHT, AURA_ROW_STEP, self, auraDragState.toIndex)
                    self:SetScript("OnUpdate", function(dragged)
                        if not auraDragState.active then return end
                        local nextIndex = ComputeDropIndex(activeAuraRows, auraRowsContainer, AURA_ROW_STEP)
                        if nextIndex ~= auraDragState.toIndex then
                            auraDragState.toIndex = nextIndex
                            LayoutDraggableRows(auraRowsContainer, activeAuraRows, auraPlaceholder, AURA_ROW_HEIGHT, AURA_ROW_STEP, dragged, auraDragState.toIndex)
                        end
                    end)
                end)
                row:SetScript("OnDragStop", function(self)
                    if not auraDragState.active then
                        return
                    end
                    self:StopMovingOrSizing()
                    self:SetScript("OnUpdate", nil)
                    self:SetAlpha(auraDragState.baseAlpha or 1)
                    self:SetFrameStrata(auraDragState.baseStrata or "MEDIUM")
                    if auraDragState.baseLevel then
                        self:SetFrameLevel(auraDragState.baseLevel)
                    end
                    self.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
                    auraDragState.active = false
                    local changed, targetIndex = CommitReorder(entries, auraDragState.fromIndex or idx, auraDragState.toIndex or idx)
                    auraDragState.row = nil
                    auraDragState.fromIndex = nil
                    auraDragState.toIndex = nil
                    auraDragState.baseStrata = nil
                    auraDragState.baseLevel = nil
                    auraDragState.baseAlpha = nil
                    auraPlaceholder:Hide()
                    if changed then
                        selectedAuraIndex = RemapSelectedIndex(selectedAuraIndex, idx, targetIndex)
                        auraDragState.suppressClick = true
                        NotifyChanged()
                    end
                    RebuildAuraList()
                end)
                row.remove:SetScript("OnClick", function()
                    table.remove(entries, idx)
                    NotifyChanged()
                    RebuildAuraList()
                end)

                activeAuraRows[#activeAuraRows + 1] = row
            end

            local auraRowsHeight = LayoutDraggableRows(auraRowsContainer, activeAuraRows, auraPlaceholder, AURA_ROW_HEIGHT, AURA_ROW_STEP)
            y = -(auraRowsHeight + 4)
            addHeader:ClearAllPoints()
            addHeader:SetPoint("TOPLEFT", 0, y)
            addHeader:SetText("|cFFAAAAAAAdd Tracked Aura:|r")
            y = y - 16

            inputRow:ClearAllPoints()
            inputRow:SetPoint("TOPLEFT", 0, y)
            inputRow:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
            y = y - 28

            local assigned = {}
            for _, entry in ipairs(entries) do
                assigned[entry.spellID] = true
            end

            local suggestions = {}
            if specID and SPEC_TO_PRESET[specID] then
                for _, spell in ipairs(SPEC_TO_PRESET[specID].spells) do
                    if not assigned[spell.id] then
                        suggestions[#suggestions + 1] = spell
                    end
                end
            end
            if COMMON_DEFENSIVES_PRESET then
                for _, spell in ipairs(COMMON_DEFENSIVES_PRESET.spells) do
                    if not assigned[spell.id] then
                        suggestions[#suggestions + 1] = spell
                    end
                end
            end

            for _, spell in ipairs(suggestions) do
                local row = AcquireSuggestRow()
                row:SetParent(auraListArea)
                row:SetPoint("TOPLEFT", 0, y)
                row:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)

                local tex
                if C_Spell and C_Spell.GetSpellTexture then
                    local ok, t = pcall(C_Spell.GetSpellTexture, spell.id)
                    if ok and t then tex = t end
                end
                row.icon:SetTexture(tex or 134400)
                row.name:SetText(spell.name or GetSpellName(spell.id) or ("Spell " .. spell.id))
                row.add:SetScript("OnClick", function()
                    AddNewAura(spell.id)
                    RebuildAuraList()
                end)

                activeSuggestRows[#activeSuggestRows + 1] = row
                y = y - 22
            end

            local selectedEntry = entries[selectedAuraIndex]
            if selectedEntry then
                y = y - 10
                selectedAuraLabel:ClearAllPoints()
                selectedAuraLabel:SetPoint("TOPLEFT", 0, y)
                selectedAuraLabel:SetText("Configure: " .. (GetSpellName(selectedEntry.spellID) or ("Spell " .. tostring(selectedEntry.spellID))))
                y = y - 22

                indicatorActionsRow:ClearAllPoints()
                indicatorActionsRow:SetPoint("TOPLEFT", 0, y)
                indicatorActionsRow:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
                indicatorActionsRow:Show()
                y = y - 30

                local indicatorCount = #(selectedEntry.indicators or {})
                if indicatorCount == 0 then
                    selectedIndicatorIndex = 1
                else
                    selectedIndicatorIndex = math.max(1, math.min(selectedIndicatorIndex, indicatorCount))
                end

                for idx, indicator in ipairs(selectedEntry.indicators or {}) do
                    local row = AcquireIndicatorRow()
                    row:SetParent(indicatorRowsContainer)
                    row.label:SetText(GetIndicatorLabel(indicator, idx))

                    local selected = idx == selectedIndicatorIndex
                    row:SetBackdropColor(selected and 0.15 or 0.07, selected and 0.15 or 0.07, selected and 0.18 or 0.07, 0.9)
                    row:SetBackdropBorderColor(
                        selected and (C.accent[1] or 0.3) or (C.border[1] or 0.2),
                        selected and (C.accent[2] or 0.7) or (C.border[2] or 0.2),
                        selected and (C.accent[3] or 1) or (C.border[3] or 0.2),
                        1
                    )

                    row:SetScript("OnClick", function()
                        if indicatorDragState.suppressClick then
                            indicatorDragState.suppressClick = nil
                            return
                        end
                        selectedIndicatorIndex = idx
                        RebuildAuraList()
                    end)
                    row:SetScript("OnDragStart", function(self)
                        indicatorDragState.active = true
                        indicatorDragState.row = self
                        indicatorDragState.fromIndex = idx
                        indicatorDragState.toIndex = idx
                        indicatorDragState.baseStrata = self:GetFrameStrata()
                        indicatorDragState.baseLevel = self:GetFrameLevel()
                        indicatorDragState.baseAlpha = self:GetAlpha()
                        self:StartMoving()
                        self:SetFrameStrata("TOOLTIP")
                        self:SetFrameLevel(401)
                        self:SetAlpha(0.92)
                        self.dragHandle:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                        LayoutDraggableRows(indicatorRowsContainer, activeIndicatorRows, indicatorPlaceholder, INDICATOR_ROW_HEIGHT, INDICATOR_ROW_STEP, self, indicatorDragState.toIndex)
                        self:SetScript("OnUpdate", function(dragged)
                            if not indicatorDragState.active then return end
                            local nextIndex = ComputeDropIndex(activeIndicatorRows, indicatorRowsContainer, INDICATOR_ROW_STEP)
                            if nextIndex ~= indicatorDragState.toIndex then
                                indicatorDragState.toIndex = nextIndex
                                LayoutDraggableRows(indicatorRowsContainer, activeIndicatorRows, indicatorPlaceholder, INDICATOR_ROW_HEIGHT, INDICATOR_ROW_STEP, dragged, indicatorDragState.toIndex)
                            end
                        end)
                    end)
                    row:SetScript("OnDragStop", function(self)
                        if not indicatorDragState.active then
                            return
                        end
                        self:StopMovingOrSizing()
                        self:SetScript("OnUpdate", nil)
                        self:SetAlpha(indicatorDragState.baseAlpha or 1)
                        self:SetFrameStrata(indicatorDragState.baseStrata or "MEDIUM")
                        if indicatorDragState.baseLevel then
                            self:SetFrameLevel(indicatorDragState.baseLevel)
                        end
                        self.dragHandle:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
                        indicatorDragState.active = false
                        local changed, targetIndex = CommitReorder(selectedEntry.indicators, indicatorDragState.fromIndex or idx, indicatorDragState.toIndex or idx)
                        indicatorDragState.row = nil
                        indicatorDragState.fromIndex = nil
                        indicatorDragState.toIndex = nil
                        indicatorDragState.baseStrata = nil
                        indicatorDragState.baseLevel = nil
                        indicatorDragState.baseAlpha = nil
                        indicatorPlaceholder:Hide()
                        if changed then
                            selectedIndicatorIndex = RemapSelectedIndex(selectedIndicatorIndex, idx, targetIndex)
                            indicatorDragState.suppressClick = true
                            NotifyChanged()
                        end
                        RebuildAuraList()
                    end)
                    row.remove:SetScript("OnClick", function()
                        table.remove(selectedEntry.indicators, idx)
                        if normalizeAuraIndicators then normalizeAuraIndicators(ai) end
                        NotifyChanged()
                        RebuildAuraList()
                    end)

                    activeIndicatorRows[#activeIndicatorRows + 1] = row
                end

                indicatorRowsContainer:ClearAllPoints()
                indicatorRowsContainer:SetPoint("TOPLEFT", 0, y)
                indicatorRowsContainer:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)
                local indicatorRowsHeight = LayoutDraggableRows(indicatorRowsContainer, activeIndicatorRows, indicatorPlaceholder, INDICATOR_ROW_HEIGHT, INDICATOR_ROW_STEP)
                y = y - indicatorRowsHeight

                local selectedIndicator = selectedEntry.indicators and selectedEntry.indicators[selectedIndicatorIndex]
                if selectedIndicator then
                    y = y - 6
                    detailArea:ClearAllPoints()
                    detailArea:SetPoint("TOPLEFT", 0, y)
                    detailArea:SetPoint("RIGHT", auraListArea, "RIGHT", 0, 0)

                    local detailY = -2
                    local function AddDetailWidget(widget, height)
                        RegisterDetailWidget(widget)
                        widget:ClearAllPoints()
                        widget:SetPoint("TOPLEFT", PAD, detailY)
                        widget:SetPoint("RIGHT", detailArea, "RIGHT", -PAD, 0)
                        detailY = detailY - height
                    end

                    AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Aura Enabled", "enabled", selectedEntry, function()
                        NotifyChanged()
                        RebuildAuraList()
                    end, { description = "Toggle tracking of this aura. When off, none of its attached indicators display." }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Only My Cast", "onlyMine", selectedEntry, function()
                        NotifyChanged()
                        RebuildAuraList()
                    end, { description = "Only track this aura when you applied it. Useful for personal HoTs and dots so teammates' copies don't trigger your indicator." }), FORM_ROW)
                    AddDetailWidget(GUI:CreateFormDropdown(detailArea, "Indicator Type", AURA_INDICATOR_TYPE_OPTIONS, "type", selectedIndicator, function()
                        if normalizeAuraIndicators then normalizeAuraIndicators(ai) end
                        NotifyChanged()
                        RebuildAuraList()
                    end, { description = "How this indicator displays: icon in the shared strip, a standalone bar, or a tint applied across the health bar." }), DROP_ROW)

                    AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Indicator Enabled", "enabled", selectedIndicator, function()
                        NotifyChanged()
                        RebuildAuraList()
                    end, { description = "Toggle just this indicator without removing it. Useful for quickly disabling a bar/tint while keeping its configuration." }), FORM_ROW)

                    if selectedIndicator.type == "bar" then
                        AddDetailWidget(GUI:CreateFormDropdown(detailArea, "Orientation", BAR_ORIENTATION_OPTIONS, "orientation", selectedIndicator, function()
                            NotifyChanged()
                            RebuildAuraList()
                        end, { description = "Whether the bar drains horizontally or vertically as the tracked aura ticks down." }), DROP_ROW)
                        AddDetailWidget(GUI:CreateFormSlider(detailArea, "Thickness", 1, 20, 1, "thickness", selectedIndicator, onChange, nil, { description = "Pixel thickness of the bar (height for horizontal bars, width for vertical)." }), SLIDER_HEIGHT)
                        AddDetailWidget(GUI:CreateFormSlider(detailArea, "Width / Height", 4, 200, 1, "length", selectedIndicator, onChange, nil, { description = "Pixel length of the bar (width for horizontal, height for vertical)." }), SLIDER_HEIGHT)
                        AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Match Frame Width / Height", "matchFrameSize", selectedIndicator, function()
                            NotifyChanged()
                            RebuildAuraList()
                        end, { description = "Stretch the bar to match the frame's width (horizontal bars) or height (vertical bars), overriding the Width / Height slider above." }), FORM_ROW)
                        AddDetailWidget(GUI:CreateFormDropdown(detailArea, "Anchor", NINE_POINT_OPTIONS, "anchor", selectedIndicator, onChange, { description = "Where on the frame the bar is anchored. X/Y Offset below nudges it from this anchor point." }), DROP_ROW)
                        AddDetailWidget(GUI:CreateFormSlider(detailArea, "X Offset", -100, 100, 1, "offsetX", selectedIndicator, onChange, nil, { description = "Horizontal pixel offset for the bar from its anchor." }), SLIDER_HEIGHT)
                        AddDetailWidget(GUI:CreateFormSlider(detailArea, "Y Offset", -100, 100, 1, "offsetY", selectedIndicator, onChange, nil, { description = "Vertical pixel offset for the bar from its anchor." }), SLIDER_HEIGHT)
                        AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Bar Color", "color", selectedIndicator, onChange, nil, { description = "Fill color of the bar while the tracked aura is active and above the low-time threshold." }), FORM_ROW)
                        AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Background Color", "backgroundColor", selectedIndicator, onChange, nil, { description = "Color drawn behind the bar fill, visible in the drained portion." }), FORM_ROW)
                        AddDetailWidget(GUI:CreateFormCheckbox(detailArea, "Hide Border", "hideBorder", selectedIndicator, function()
                            NotifyChanged()
                            RebuildAuraList()
                        end, { description = "Remove the border drawn around the bar for a cleaner look." }), FORM_ROW)
                        AddDetailWidget(GUI:CreateFormSlider(detailArea, "Border Size", 1, 8, 1, "borderSize", selectedIndicator, onChange, nil, { description = "Pixel thickness of the bar's border." }), SLIDER_HEIGHT, function() return selectedIndicator.hideBorder ~= true end)
                        AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Border Color", "borderColor", selectedIndicator, onChange, nil, { description = "Color of the bar's border." }), FORM_ROW)
                        AddDetailWidget(GUI:CreateFormSlider(detailArea, "Low-Time Seconds", 0, 30, 0.5, "lowTimeThreshold", selectedIndicator, onChange, { precision = 1 }, { description = "When the remaining duration drops below this many seconds, the bar switches to the Low-Time Color. Set to 0 to disable." }), SLIDER_HEIGHT)
                        AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Low-Time Color", "lowTimeColor", selectedIndicator, onChange, nil, { description = "Bar fill color used once the remaining duration crosses the Low-Time Seconds threshold." }), FORM_ROW)
                    elseif selectedIndicator.type == "healthBarColor" then
                        AddDetailWidget(GUI:CreateFormColorPicker(detailArea, "Tint Color", "color", selectedIndicator, onChange, nil, { description = "Color tint applied across the health bar while the tracked aura is active." }), FORM_ROW)
                    else
                        local note = GUI:CreateLabel(detailArea, "Icon indicators use the shared icon-strip settings in the section above.", 11, C and C.textMuted)
                        note:SetJustifyH("LEFT")
                        AddDetailWidget(note, 28)
                    end

                    detailArea:SetHeight(math.abs(detailY) + 8)
                    y = y - (detailArea:GetHeight() + 4)
                else
                    indicatorActionsRow:Hide()
                    detailArea:SetHeight(1)
                end
            else
                selectedAuraLabel:SetText("No tracked auras yet.")
                selectedAuraLabel:ClearAllPoints()
                selectedAuraLabel:SetPoint("TOPLEFT", 0, y)
                indicatorActionsRow:Hide()
                detailArea:SetHeight(1)
                y = y - 24
            end

            auraListArea:SetHeight(math.max(1, math.abs(y)))
            body:SetHeight(56 + auraListArea:GetHeight())
            updateH()
        end

        RebuildAuraList()
    end, sections, relayout)

    relayout()
end

---------------------------------------------------------------------------
-- PINNED AURAS SETTINGS (per-spec individually anchored indicators)
---------------------------------------------------------------------------
local PINNED_DISPLAY_OPTIONS = {
    { value = "icon", text = "Icon" },
    { value = "square", text = "Colored Square" },
}

local PINNED_ANCHOR_SHORT = {
    TOPLEFT = "TL", TOP = "T", TOPRIGHT = "TR",
    LEFT = "L", CENTER = "C", RIGHT = "R",
    BOTTOMLEFT = "BL", BOTTOM = "B", BOTTOMRIGHT = "BR",
}

-- Rotation order for auto-assigning anchors to new pinned aura slots
local PINNED_ANCHOR_ROTATION = {
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
    "TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER",
}

local function NextPinnedAnchor(slots)
    -- Count how many slots use each anchor
    local used = {}
    for _, s in ipairs(slots) do
        local a = s.anchor or "TOPLEFT"
        used[a] = (used[a] or 0) + 1
    end
    -- Pick the first anchor with the fewest slots
    local bestAnchor, bestCount = PINNED_ANCHOR_ROTATION[1], math.huge
    for _, a in ipairs(PINNED_ANCHOR_ROTATION) do
        local c = used[a] or 0
        if c < bestCount then
            bestAnchor, bestCount = a, c
            if c == 0 then break end
        end
    end
    return bestAnchor
end

local function ShowPinnedSlotMenu(anchorFrame, slot, onChanged)
    if _G.QUI_PinnedSlotMenu then _G.QUI_PinnedSlotMenu:Hide() end

    local items = {}
    -- Section: Anchor Position
    items[#items + 1] = { label = "Anchor Position", isTitle = true }
    for _, opt in ipairs(NINE_POINT_OPTIONS) do
        local isSelected = (slot.anchor or "TOPLEFT") == opt.value
        items[#items + 1] = {
            label = opt.text,
            isSelected = isSelected,
            action = function() slot.anchor = opt.value; if onChanged then onChanged() end end,
        }
    end
    -- Divider
    items[#items + 1] = { isDivider = true }
    -- Section: Display Type
    items[#items + 1] = { label = "Display Type", isTitle = true }
    for _, opt in ipairs(PINNED_DISPLAY_OPTIONS) do
        local isSelected = (slot.displayType or "icon") == opt.value
        items[#items + 1] = {
            label = opt.text,
            isSelected = isSelected,
            action = function()
                slot.displayType = opt.value
                if opt.value == "square" and not slot.color then slot.color = {0.2, 0.8, 0.2, 1} end
                if onChanged then onChanged() end
            end,
        }
    end
    -- Color picker (only when square type)
    if (slot.displayType or "icon") == "square" then
        items[#items + 1] = { isDivider = true }
        items[#items + 1] = { isColorPicker = true }
    end

    local itemHeight = 20
    local titleHeight = 20
    local dividerHeight = 8
    local menuWidth = 150
    local colorPickerHeight = 28
    local totalH = 4
    for _, item in ipairs(items) do
        if item.isDivider then totalH = totalH + dividerHeight
        elseif item.isTitle then totalH = totalH + titleHeight
        elseif item.isColorPicker then totalH = totalH + colorPickerHeight
        else totalH = totalH + itemHeight end
    end

    local accentR, accentG, accentB = 0.204, 0.827, 0.6
    if C and C.accent then accentR, accentG, accentB = C.accent[1], C.accent[2], C.accent[3] end

    local menu = CreateFrame("Frame", "QUI_PinnedSlotMenu", UIParent, "BackdropTemplate")
    menu:SetSize(menuWidth, totalH)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(300)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
    menu:SetBackdropBorderColor(accentR * 0.5, accentG * 0.5, accentB * 0.5, 0.8)
    menu:EnableMouse(true)
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    menu:SetClampedToScreen(true)

    local y = -2
    for _, item in ipairs(items) do
        if item.isDivider then
            local div = menu:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetPoint("TOPLEFT", 6, y - 3)
            div:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
            div:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            y = y - dividerHeight
        elseif item.isTitle then
            local label = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 8, y)
            label:SetText(item.label)
            label:SetTextColor(accentR, accentG, accentB, 1)
            y = y - titleHeight
        elseif item.isColorPicker then
            local colorRow = CreateFrame("Button", nil, menu)
            colorRow:SetSize(menuWidth - 4, colorPickerHeight)
            colorRow:SetPoint("TOPLEFT", 2, y)

            local colorLabel = colorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            colorLabel:SetPoint("LEFT", 12, 0)
            colorLabel:SetText("Color")
            colorLabel:SetTextColor(0.8, 0.8, 0.8, 1)

            local swatch = colorRow:CreateTexture(nil, "ARTWORK")
            swatch:SetSize(16, 16)
            swatch:SetPoint("RIGHT", -8, 0)
            local sc = slot.color or {0.2, 0.8, 0.2, 1}
            swatch:SetColorTexture(sc[1] or 0.5, sc[2] or 0.5, sc[3] or 0.5, sc[4] or 1)

            colorRow:SetScript("OnClick", function()
                menu:Hide()
                local prev = { sc[1], sc[2], sc[3], sc[4] }
                local function SetColor(r, g, b, a)
                    if not slot.color then slot.color = {} end
                    slot.color[1] = r; slot.color[2] = g; slot.color[3] = b; slot.color[4] = a or 1
                    if onChanged then onChanged() end
                end
                local info = {}
                info.r, info.g, info.b = sc[1] or 0.2, sc[2] or 0.8, sc[3] or 0.2
                info.opacity = 1 - (sc[4] or 1)
                info.hasOpacity = true
                info.swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local rawAlpha = 0
                    if ColorPickerFrame.GetColorAlpha then
                        rawAlpha = ColorPickerFrame:GetColorAlpha() or 0
                    elseif OpacitySliderFrame then
                        rawAlpha = OpacitySliderFrame:GetValue() or 0
                    end
                    local a = 1 - rawAlpha
                    SetColor(r, g, b, a)
                end
                info.cancelFunc = function()
                    SetColor(prev[1], prev[2], prev[3], prev[4])
                end
                info.opacityFunc = info.swatchFunc
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            colorRow:SetScript("OnEnter", function() colorLabel:SetTextColor(1, 1, 1, 1) end)
            colorRow:SetScript("OnLeave", function() colorLabel:SetTextColor(0.8, 0.8, 0.8, 1) end)
            y = y - colorPickerHeight
        else
            local btn = CreateFrame("Button", nil, menu)
            btn:SetSize(menuWidth - 4, itemHeight)
            btn:SetPoint("TOPLEFT", 2, y)
            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 12, 0)
            label:SetText(item.label)
            local r, g, b = 0.8, 0.8, 0.8
            if item.isSelected then r, g, b = accentR, accentG, accentB end
            label:SetTextColor(r, g, b, 1)
            if item.isSelected then
                local check = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                check:SetPoint("RIGHT", -8, 0)
                check:SetText("*")
                check:SetTextColor(accentR, accentG, accentB, 1)
            end
            btn:SetScript("OnClick", function()
                menu:Hide()
                if item.action then item.action() end
            end)
            btn:SetScript("OnEnter", function()
                label:SetTextColor(1, 1, 1, 1)
            end)
            btn:SetScript("OnLeave", function()
                label:SetTextColor(r, g, b, 1)
            end)
            y = y - itemHeight
        end
    end

    menu:SetScript("OnUpdate", function(self)
        if not MouseIsOver(self) and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
            self:Hide()
        end
    end)

    menu:Show()
end

local function BuildPinnedAurasSettings(content, gfdb, onChange)
    local pa = gfdb.pinnedAuras; if not pa then gfdb.pinnedAuras = {} pa = gfdb.pinnedAuras end
    if not pa.specSlots then pa.specSlots = {} end
    local sections = {}
    local function relayout() RelayoutComposerSections(content, sections) end

    -- Global settings section
    CreateComposerCollapsible(content, "Pinned Auras", function(body, updateH)
        local cond = function() return pa.enabled end
        local L = CreateDynamicLayout(body, updateH)
        local desc = GUI:CreateLabel(body, "Per-spec aura indicators anchored to positions on group frames. Each spell gets its own anchor point.", 11, C and C.textMuted); desc:SetJustifyH("LEFT")
        L:Row(desc, 36)
        L:Row(GUI:CreateFormCheckbox(body, "Enable Pinned Auras", "enabled", pa, onChange, { description = "Enable per-spec pinned aura slots on group frames. Each tracked spell gets a dedicated anchor point, letting you place key auras at fixed positions." }), FORM_ROW)
        L:Row(GUI:CreateFormSlider(body, "Slot Size", 4, 20, 1, "slotSize", pa, onChange, nil, { description = "Pixel size of each pinned aura slot." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormSlider(body, "Edge Inset", 0, 10, 1, "edgeInset", pa, onChange, nil, { description = "Pixel inset from the frame edge when placing pinned aura slots. Higher values tuck the slots further inside the frame." }), SLIDER_HEIGHT, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Show Cooldown Swipe", "showSwipe", pa, onChange, { description = "Show the clockwise cooldown swipe animation over pinned aura slots." }), FORM_ROW, cond)
        L:Row(GUI:CreateFormCheckbox(body, "Reverse Swipe", "reverseSwipe", pa, onChange, { description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the aura ticks down." }), FORM_ROW, function() return pa.enabled and pa.showSwipe end)
        L:Finish()
    end, sections, relayout)

    -- Spell slots section with flat list + per-slot anchor
    CreateComposerCollapsible(content, "Spell Slots", function(body, updateH)
        local specID = GetPlayerSpecID()
        if not specID then
            local noSpec = GUI:CreateLabel(body, "No specialization detected. Choose a spec to configure pinned auras.", 11, C and C.textMuted)
            noSpec:SetJustifyH("LEFT")
            noSpec:SetPoint("TOPLEFT", PAD, -6)
            noSpec:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
            body:SetHeight(30)
            return
        end

        if not pa.specSlots[specID] then
            pa.specSlots[specID] = {}
        end
        local slots = pa.specSlots[specID]

        -- Spec label
        local specLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        specLabel:SetPoint("TOPLEFT", PAD, -6)
        local _, specName = GetSpecializationInfoByID(specID)
        specLabel:SetText("|cFF34D399" .. (specName or ("Spec " .. specID)) .. "|r")

        -- Spell list area
        local LIST_TOP = -24
        local spellListArea = CreateFrame("Frame", nil, body)
        spellListArea:SetPoint("TOPLEFT", PAD, LIST_TOP)
        spellListArea:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
        spellListArea:SetHeight(1)

        -- Persistent "Add Spells:" header
        local addSectionHeader = spellListArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addSectionHeader:SetJustifyH("LEFT")

        -- Persistent manual input row
        local inputRow = CreateFrame("Frame", nil, spellListArea)
        inputRow:SetHeight(24)

        local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
        inputBox:SetSize(80, 20)
        inputBox:SetPoint("LEFT", 4, 0)
        inputBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        inputBox:SetBackdropColor(0.06, 0.06, 0.08, 1)
        inputBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        inputBox:SetFontObject("GameFontNormalSmall")
        inputBox:SetAutoFocus(false)
        inputBox:SetMaxLetters(10)
        inputBox:SetTextInsets(4, 4, 0, 0)
        inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local inputLabel = inputRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        inputLabel:SetPoint("LEFT", inputBox, "RIGHT", 4, 0)
        inputLabel:SetText("Spell ID")
        inputLabel:SetTextColor(0.5, 0.5, 0.5)

        local addManualBtn = CreateFrame("Button", nil, inputRow, "BackdropTemplate")
        addManualBtn:SetSize(40, 20)
        addManualBtn:SetPoint("RIGHT", inputRow, "RIGHT", -2, 0)
        addManualBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        addManualBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        addManualBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        local addManualText = addManualBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addManualText:SetPoint("CENTER")
        addManualText:SetText("Add")

        -- Row pool for assigned spell rows
        local spellRowPool = {}
        local suggestRowPool = {}
        local activeSpellRows = {}
        local activeSuggestRows = {}

        local function AcquireSpellRow(parent)
            local row = table.remove(spellRowPool)
            if row then
                row:SetParent(parent)
                row:ClearAllPoints()
                row:Show()
                return row
            end
            row = CreateFrame("Button", nil, parent)
            row:SetHeight(28)
            row:RegisterForClicks("AnyUp")

            row._spellIcon = row:CreateTexture(nil, "ARTWORK")
            row._spellIcon:SetSize(16, 16)
            row._spellIcon:SetPoint("LEFT", 4, 0)
            row._spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row._nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row._nameText:SetPoint("LEFT", row._spellIcon, "RIGHT", 4, 0)
            row._nameText:SetJustifyH("LEFT")

            -- Anchor button (clickable, shows current anchor abbreviation)
            row._anchorBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            row._anchorBtn:SetSize(24, 16)
            row._anchorBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            row._anchorBtn:SetBackdropColor(0.1, 0.1, 0.12, 1)
            row._anchorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            row._anchorBtnText = row._anchorBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._anchorBtnText:SetPoint("CENTER")
            row._anchorBtnText:SetTextColor(0.7, 0.85, 1, 1)

            row._removeBtn = CreateFrame("Button", nil, row)
            row._removeBtn:SetSize(18, 18)
            row._removeBtn:SetPoint("RIGHT", -2, 0)
            row._removeBtnText = row._removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row._removeBtnText:SetPoint("CENTER")
            row._removeBtnText:SetText("\195\151")
            row._removeBtnText:SetTextColor(0.8, 0.3, 0.3)
            row._removeBtn:SetScript("OnEnter", function() row._removeBtnText:SetTextColor(1, 0.4, 0.4) end)
            row._removeBtn:SetScript("OnLeave", function() row._removeBtnText:SetTextColor(0.8, 0.3, 0.3) end)

            row._anchorBtn:SetPoint("RIGHT", row._removeBtn, "LEFT", -2, 0)
            row._nameText:SetPoint("RIGHT", row._anchorBtn, "LEFT", -4, 0)

            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                local dt = self._displayType or "icon"
                GameTooltip:SetText(self._spellName or "Spell")
                GameTooltip:AddLine("Right-click to configure", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return row
        end

        local function ReleaseSpellRow(row)
            row:Hide()
            row:ClearAllPoints()
            row._removeBtn:SetScript("OnClick", nil)
            row._anchorBtn:SetScript("OnClick", nil)
            row:SetScript("OnClick", nil)
            row._spellName = nil
            if row._spellIcon then row._spellIcon:SetVertexColor(1, 1, 1) end
            table.insert(spellRowPool, row)
        end

        local function AcquireSuggestRow(parent)
            local row = table.remove(suggestRowPool)
            if row then
                row:SetParent(parent)
                row:ClearAllPoints()
                row:Show()
                return row
            end
            row = CreateFrame("Frame", nil, parent)
            row:SetHeight(22)

            row._sIcon = row:CreateTexture(nil, "ARTWORK")
            row._sIcon:SetSize(14, 14)
            row._sIcon:SetPoint("LEFT", 4, 0)
            row._sIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row._sName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row._sName:SetPoint("LEFT", row._sIcon, "RIGHT", 4, 0)
            row._sName:SetJustifyH("LEFT")

            row._addBtn = CreateFrame("Button", nil, row)
            row._addBtn:SetSize(18, 18)
            row._addBtn:SetPoint("RIGHT", -2, 0)
            row._addBtnText = row._addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row._addBtnText:SetPoint("CENTER")
            row._addBtnText:SetText("+")
            row._addBtnText:SetTextColor(0.3, 0.8, 0.3)
            row._addBtn:SetScript("OnEnter", function() row._addBtnText:SetTextColor(0.4, 1, 0.4) end)
            row._addBtn:SetScript("OnLeave", function() row._addBtnText:SetTextColor(0.3, 0.8, 0.3) end)
            row._sName:SetPoint("RIGHT", row._addBtn, "LEFT", -4, 0)

            return row
        end

        local function ReleaseSuggestRow(row)
            row:Hide()
            row:ClearAllPoints()
            row._addBtn:SetScript("OnClick", nil)
            table.insert(suggestRowPool, row)
        end

        local function RebuildSpellList()
            -- Release all active rows back to pool
            for _, row in ipairs(activeSpellRows) do ReleaseSpellRow(row) end
            wipe(activeSpellRows)
            for _, row in ipairs(activeSuggestRows) do ReleaseSuggestRow(row) end
            wipe(activeSuggestRows)

            local y = 0

            -- Assigned spell rows
            for idx, slot in ipairs(slots) do
                local row = AcquireSpellRow(spellListArea)
                row:SetPoint("TOPLEFT", 0, y)
                row:SetPoint("RIGHT", spellListArea, "RIGHT", 0, 0)

                -- Populate icon
                local tex
                if C_Spell and C_Spell.GetSpellTexture then
                    local ok, t = pcall(C_Spell.GetSpellTexture, slot.spellID)
                    if ok and t then tex = t end
                end
                row._spellIcon:SetTexture(tex or 134400)

                -- Populate name
                local spellName2 = GetSpellName(slot.spellID) or ("Spell " .. slot.spellID)
                row._nameText:SetText(spellName2)
                row._spellName = spellName2

                -- Color spell icon based on display type
                if slot.displayType == "square" then
                    local color = slot.color or {0.2, 0.8, 0.2, 1}
                    row._spellIcon:SetVertexColor(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5)
                else
                    row._spellIcon:SetVertexColor(1, 1, 1)
                end

                -- Anchor button text
                local anchor = slot.anchor or "TOPLEFT"
                row._anchorBtnText:SetText(PINNED_ANCHOR_SHORT[anchor] or "TL")

                -- Shared menu builder for this slot
                local capturedIdx = idx
                local function ShowSlotMenu(anchorFrame)
                    ShowPinnedSlotMenu(anchorFrame, slot, function()
                        RebuildSpellList()
                        if onChange then onChange() end
                    end)
                end

                -- Left-click anchor button opens menu
                row._anchorBtn:RegisterForClicks("AnyUp")
                row._anchorBtn:SetScript("OnClick", function(self) ShowSlotMenu(self) end)
                row._anchorBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                    GameTooltip:SetText("Position: " .. (anchor or "TOPLEFT"))
                    local dt = (slot.displayType or "icon") == "square" and "Colored Square" or "Icon"
                    GameTooltip:AddLine("Display: " .. dt, 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                row._anchorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Right-click anywhere on row opens same menu
                row:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then ShowSlotMenu(self) end
                end)

                -- Remove button
                row._removeBtn:SetScript("OnClick", function()
                    table.remove(slots, capturedIdx)
                    RebuildSpellList()
                    if onChange then onChange() end
                end)

                activeSpellRows[#activeSpellRows + 1] = row
                y = y - 28
            end

            -- "Add Spells:" header
            y = y - 6
            addSectionHeader:ClearAllPoints()
            addSectionHeader:SetPoint("TOPLEFT", 0, y)
            addSectionHeader:SetText("|cFFAAAAAAAAdd Spells:|r")
            addSectionHeader:Show()
            y = y - 16

            -- Build set of already-assigned spellIDs
            local assignedSet = {}
            for _, s in ipairs(slots) do
                if s.spellID then assignedSet[s.spellID] = true end
            end

            -- Gather preset spells for current spec
            local presetSpells = {}
            if SPEC_TO_PRESET[specID] then
                for _, spell in ipairs(SPEC_TO_PRESET[specID].spells) do
                    if not assignedSet[spell.id] then
                        presetSpells[#presetSpells + 1] = spell
                    end
                end
            end
            if COMMON_DEFENSIVES_PRESET then
                for _, spell in ipairs(COMMON_DEFENSIVES_PRESET.spells) do
                    if not assignedSet[spell.id] then
                        presetSpells[#presetSpells + 1] = spell
                    end
                end
            end

            for _, spell in ipairs(presetSpells) do
                local row = AcquireSuggestRow(spellListArea)
                row:SetPoint("TOPLEFT", 0, y)
                row:SetPoint("RIGHT", spellListArea, "RIGHT", 0, 0)

                local sTex
                if C_Spell and C_Spell.GetSpellTexture then
                    local ok, t = pcall(C_Spell.GetSpellTexture, spell.id)
                    if ok and t then sTex = t end
                end
                row._sIcon:SetTexture(sTex or 134400)
                row._sName:SetText(spell.name or GetSpellName(spell.id) or ("Spell " .. spell.id))

                local spellId = spell.id
                row._addBtn:SetScript("OnClick", function()
                    slots[#slots + 1] = { spellID = spellId, displayType = "icon", anchor = NextPinnedAnchor(slots) }
                    RebuildSpellList()
                    if onChange then onChange() end
                end)

                activeSuggestRows[#activeSuggestRows + 1] = row
                y = y - 22
            end

            -- Reposition manual input row
            y = y - 8
            inputRow:ClearAllPoints()
            inputRow:SetPoint("TOPLEFT", 0, y)
            inputRow:SetPoint("RIGHT", spellListArea, "RIGHT", 0, 0)
            inputRow:Show()
            y = y - 28

            -- Wire manual add button
            addManualBtn:SetScript("OnClick", function()
                local text = inputBox:GetText()
                local id = tonumber(text)
                if id and id > 0 then
                    slots[#slots + 1] = { spellID = id, displayType = "icon", anchor = NextPinnedAnchor(slots) }
                    inputBox:SetText("")
                    inputBox:ClearFocus()
                    RebuildSpellList()
                    if onChange then onChange() end
                end
            end)
            inputBox:SetScript("OnEnterPressed", function(self)
                addManualBtn:GetScript("OnClick")(addManualBtn)
            end)

            spellListArea:SetHeight(math.max(1, math.abs(y)))
            body:SetHeight(math.abs(LIST_TOP) + math.abs(y) + 10)
            updateH()
        end

        RebuildSpellList()
    end, sections, relayout)

    relayout()
end

---------------------------------------------------------------------------
-- ELEMENT BUILDERS — dispatch table for QUI_BuildGroupFrameElement.
---------------------------------------------------------------------------
local ELEMENT_BUILDERS = {
    health = BuildHealthSettings, power = BuildPowerSettings,
    name = BuildNameSettings, buffs = BuildBuffsSettings,
    debuffs = BuildDebuffsSettings, indicators = BuildIndicatorsSettings,
    healer = BuildHealerSettings, defensive = BuildDefensiveSettings,
    auraIndicators = BuildAuraIndicatorsSettings, pinnedAuras = BuildPinnedAurasSettings,
    privateAuras = BuildPrivateAurasSettings,
}

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
    local previewBottomPad = powerH + borderSize
    local function PreviewBottomPadY(anchor, offY)
        if anchor and anchor:find("BOTTOM") then
            return offY + previewBottomPad
        end
        return offY
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
    local roleAtlas = nil
    if indDB.showRoleIcon ~= false then
        for _, previewRole in ipairs(PREVIEW_ROLE_ORDER) do
            if indDB[previewRole.toggleKey] ~= false then
                roleAtlas = PREVIEW_ROLE_ATLAS[previewRole.role]
                break
            end
        end
    end
    if roleAtlas then
        local roleSize = (indDB.roleIconSize or 12) * PREVIEW_SCALE
        local roleAnchor = indDB.roleIconAnchor or "TOPLEFT"
        local roleOffX = (indDB.roleIconOffsetX or 2) * PREVIEW_SCALE
        local roleOffY = (indDB.roleIconOffsetY or -2) * PREVIEW_SCALE
        local roleIcon = textFrame:CreateTexture(nil, "OVERLAY")
        roleIcon:SetSize(roleSize, roleSize)
        roleIcon:SetPoint(roleAnchor, frame, roleAnchor, roleOffX, PreviewBottomPadY(roleAnchor, roleOffY))
        roleIcon:SetAtlas(roleAtlas)
        childRefs.roleIcon = roleIcon
    end

    -- Helper: create a single indicator icon preview
    local function CreateIndicatorPip(showKey, sizeKey, anchorKey, offXKey, offYKey, refKey, config)
        if not indDB[showKey] then return end
        config = config or {}
        local pipSize = (indDB[sizeKey] or 12) * PREVIEW_SCALE
        local pipAnchor = indDB[anchorKey] or "TOPLEFT"
        local pipOffX = (indDB[offXKey] or 0) * PREVIEW_SCALE
        local pipOffY = (indDB[offYKey] or 0) * PREVIEW_SCALE
        local pip = textFrame:CreateTexture(nil, "OVERLAY")
        pip:SetSize(pipSize, pipSize)
        pip:SetPoint(pipAnchor, frame, pipAnchor, pipOffX, PreviewBottomPadY(pipAnchor, pipOffY))
        if config.atlas then
            pip:SetAtlas(config.atlas)
        end
        if config.texture then
            pip:SetTexture(config.texture)
        end
        if config.setup then
            config.setup(pip)
        end
        if config.texCoord then pip:SetTexCoord(unpack(config.texCoord)) end
        childRefs[refKey] = pip
    end

    CreateIndicatorPip("showReadyCheck", "readyCheckSize", "readyCheckAnchor", "readyCheckOffsetX", "readyCheckOffsetY", "readyCheck", {
        texture = "INTERFACE\\RAIDFRAME\\ReadyCheck-Ready",
    })
    CreateIndicatorPip("showResurrection", "resurrectionSize", "resurrectionAnchor", "resurrectionOffsetX", "resurrectionOffsetY", "resurrection", {
        texture = "Interface\\RaidFrame\\Raid-Icon-Rez",
    })
    CreateIndicatorPip("showSummonPending", "summonSize", "summonAnchor", "summonOffsetX", "summonOffsetY", "summon", {
        atlas = "RaidFrame-Icon-SummonPending",
    })
    CreateIndicatorPip("showLeaderIcon", "leaderSize", "leaderAnchor", "leaderOffsetX", "leaderOffsetY", "leader", {
        atlas = "groupfinder-icon-leader",
    })
    CreateIndicatorPip("showTargetMarker", "targetMarkerSize", "targetMarkerAnchor", "targetMarkerOffsetX", "targetMarkerOffsetY", "targetMarker", {
        texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcons",
        setup = function(texture)
            if SetRaidTargetIconTexture then
                SetRaidTargetIconTexture(texture, 6)
            end
        end,
    })
    CreateIndicatorPip("showPhaseIcon", "phaseSize", "phaseAnchor", "phaseOffsetX", "phaseOffsetY", "phase", {
        texture = "Interface\\TargetingFrame\\UI-PhasingIcon",
    })

    -- Buff icons
    local auraDB = db.auras or {}

    local function CalculatePreviewSlotOffset(index, iconSize, spacing, direction, totalCount)
        local step = (index - 1) * (iconSize + spacing)
        if direction == "RIGHT" then
            return step, 0
        elseif direction == "LEFT" then
            return -step, 0
        elseif direction == "CENTER" then
            local n = totalCount or 1
            local totalSpan = n * iconSize + math.max(n - 1, 0) * spacing
            return step - totalSpan / 2, 0
        elseif direction == "UP" then
            return 0, step
        elseif direction == "DOWN" then
            return 0, -step
        end
        return step, 0
    end

    local function ComposePreviewAnchor(horizontal, vertical)
        if vertical == "TOP" then
            if horizontal == "LEFT" then return "TOPLEFT" end
            if horizontal == "RIGHT" then return "TOPRIGHT" end
            return "TOP"
        elseif vertical == "BOTTOM" then
            if horizontal == "LEFT" then return "BOTTOMLEFT" end
            if horizontal == "RIGHT" then return "BOTTOMRIGHT" end
            return "BOTTOM"
        end

        if horizontal == "LEFT" then return "LEFT" end
        if horizontal == "RIGHT" then return "RIGHT" end
        return "CENTER"
    end

    local function GetPreviewIconAnchorForGrow(frameAnchor, direction)
        local horizontal = frameAnchor and frameAnchor:find("LEFT") and "LEFT"
            or frameAnchor and frameAnchor:find("RIGHT") and "RIGHT"
            or "CENTER"
        local vertical = frameAnchor and frameAnchor:find("TOP") and "TOP"
            or frameAnchor and frameAnchor:find("BOTTOM") and "BOTTOM"
            or "CENTER"

        if direction == "RIGHT" or direction == "CENTER" then
            horizontal = "LEFT"
        elseif direction == "LEFT" then
            horizontal = "RIGHT"
        elseif direction == "UP" then
            vertical = "BOTTOM"
        elseif direction == "DOWN" then
            vertical = "TOP"
        end

        return ComposePreviewAnchor(horizontal, vertical)
    end

    local function AccumulatePreviewIconBounds(iconAnchor, offX, offY, size, minX, maxX, minY, maxY)
        local left, right, bottom, top
        if iconAnchor:find("LEFT") then
            left, right = offX, offX + size
        elseif iconAnchor:find("RIGHT") then
            left, right = offX - size, offX
        else
            left, right = offX - size / 2, offX + size / 2
        end

        if iconAnchor:find("TOP") then
            top, bottom = offY, offY - size
        elseif iconAnchor:find("BOTTOM") then
            top, bottom = offY + size, offY
        else
            top, bottom = offY + size / 2, offY - size / 2
        end

        return math.min(minX or left, left),
            math.max(maxX or right, right),
            math.min(minY or bottom, bottom),
            math.max(maxY or top, top)
    end

    local function CreatePreviewAuraBounds(parentFrame, anchor, baseOffX, baseOffY, minX, maxX, minY, maxY)
        local bounds = CreateFrame("Frame", nil, parentFrame)
        bounds:SetFrameLevel(parentFrame:GetFrameLevel() + 8)
        bounds:SetSize(math.max(maxX - minX, 1), math.max(maxY - minY, 1))
        bounds:SetPoint("CENTER", parentFrame, anchor, baseOffX + (minX + maxX) / 2, baseOffY + (minY + maxY) / 2)
        return bounds
    end

    local function IsPreviewDurationTextEnabled(showKey)
        local specific = auraDB[showKey]
        if specific ~= nil then
            return specific ~= false
        end
        return auraDB.showDurationText ~= false
    end

    local function GetPreviewDurationFontPath(prefix)
        local fontName = auraDB[prefix .. "DurationFont"]
        if fontName and fontName ~= "" and LSM then
            local fetched = LSM:Fetch("font", fontName)
            if fetched then return fetched end
        end
        return fontPath
    end

    local function GetPreviewDurationTextColor(prefix)
        local useTimeColor = auraDB[prefix .. "DurationUseTimeColor"]
        if useTimeColor == nil then
            useTimeColor = auraDB.showDurationColor ~= false
        end
        if useTimeColor then
            return 0.2, 1, 0.2, 1
        end

        local c = auraDB[prefix .. "DurationColor"]
        if c then
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end
        return 1, 1, 1, 1
    end

    local function AddPreviewDurationText(parentFrame, icon, prefix, text)
        local duration = parentFrame:CreateFontString(nil, "OVERLAY")
        local size = auraDB[prefix .. "DurationFontSize"] or auraDB.durationFontSize or 9
        local anchor = auraDB[prefix .. "DurationAnchor"] or "BOTTOM"
        local offX = (auraDB[prefix .. "DurationOffsetX"] or 0) * PREVIEW_SCALE
        local offY = (auraDB[prefix .. "DurationOffsetY"] or -6) * PREVIEW_SCALE
        duration:SetFont(GetPreviewDurationFontPath(prefix), size * PREVIEW_SCALE, "OUTLINE")
        duration:SetPoint(anchor, icon, anchor, offX, offY)
        duration:SetJustifyH("CENTER")
        duration:SetText(text)
        duration:SetTextColor(GetPreviewDurationTextColor(prefix))
        return duration
    end

    if auraDB.showBuffs then
        local buffSize = (auraDB.buffIconSize or 14) * PREVIEW_SCALE
        local maxBuffs = auraDB.maxBuffs or 3
        local buffCount = math.min(maxBuffs, #FAKE_BUFF_ICONS)
        if buffCount > 0 then
            local buffAnchor = auraDB.buffAnchor or "TOPLEFT"
            local buffGrow = auraDB.buffGrowDirection or "RIGHT"
            local buffSpacing = (auraDB.buffSpacing or 2) * PREVIEW_SCALE
            local buffOffX = (auraDB.buffOffsetX or 2) * PREVIEW_SCALE
            local buffOffY = PreviewBottomPadY(buffAnchor, (auraDB.buffOffsetY or 16) * PREVIEW_SCALE)
            local buffIconAnchor = GetPreviewIconAnchorForGrow(buffAnchor, buffGrow)
            local minX, maxX, minY, maxY
            local buffContainer = CreateFrame("Frame", nil, frame)
            buffContainer:SetFrameLevel(frame:GetFrameLevel() + 8)
            buffContainer:SetSize(1, 1)
            buffContainer:SetPoint(buffAnchor, frame, buffAnchor, buffOffX, buffOffY)
            for i = 1, buffCount do
                local icon = buffContainer:CreateTexture(nil, "OVERLAY")
                icon:SetSize(buffSize, buffSize)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetTexture(FAKE_BUFF_ICONS[i])
                local offX, offY = CalculatePreviewSlotOffset(i, buffSize, buffSpacing, buffGrow, buffCount)
                icon:SetPoint(buffIconAnchor, buffContainer, buffAnchor, offX, offY)
                minX, maxX, minY, maxY = AccumulatePreviewIconBounds(buffIconAnchor, offX, offY, buffSize, minX, maxX, minY, maxY)
                if IsPreviewDurationTextEnabled("showBuffDurationText") then
                    AddPreviewDurationText(buffContainer, icon, "buff", i == 1 and "5m" or "45")
                end
            end
            childRefs.buffContainer = CreatePreviewAuraBounds(frame, buffAnchor, buffOffX, buffOffY, minX, maxX, minY, maxY)
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
            local debuffOffX = (auraDB.debuffOffsetX or -2) * PREVIEW_SCALE
            local debuffOffY = PreviewBottomPadY(debuffAnchor, (auraDB.debuffOffsetY or -18) * PREVIEW_SCALE)
            local debuffIconAnchor = GetPreviewIconAnchorForGrow(debuffAnchor, debuffGrow)
            local minX, maxX, minY, maxY
            local debuffContainer = CreateFrame("Frame", nil, frame)
            debuffContainer:SetFrameLevel(frame:GetFrameLevel() + 8)
            debuffContainer:SetSize(1, 1)
            debuffContainer:SetPoint(debuffAnchor, frame, debuffAnchor, debuffOffX, debuffOffY)
            for i = 1, debuffCount do
                local icon = debuffContainer:CreateTexture(nil, "OVERLAY")
                icon:SetSize(debuffSize, debuffSize)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetTexture(FAKE_DEBUFF_ICONS[i])
                local offX, offY = CalculatePreviewSlotOffset(i, debuffSize, debuffSpacing, debuffGrow, debuffCount)
                icon:SetPoint(debuffIconAnchor, debuffContainer, debuffAnchor, offX, offY)
                minX, maxX, minY, maxY = AccumulatePreviewIconBounds(debuffIconAnchor, offX, offY, debuffSize, minX, maxX, minY, maxY)
                if IsPreviewDurationTextEnabled("showDebuffDurationText") then
                    AddPreviewDurationText(debuffContainer, icon, "debuff", i == 1 and "12" or "45")
                end
            end
            childRefs.debuffContainer = CreatePreviewAuraBounds(frame, debuffAnchor, debuffOffX, debuffOffY, minX, maxX, minY, maxY)
        end
    end

    -- Helper: create a row of fake icons for an element preview
    local function CreateIconStrip(parentFrame, icons, count, size, anchor, grow, spacing, offX, offY, refKey)
        if count <= 0 then return end
        local totalW, totalH = size, size
        if grow == "LEFT" or grow == "RIGHT" or grow == "CENTER" then
            totalW = count * size + math.max(count - 1, 0) * spacing
        elseif grow == "UP" or grow == "DOWN" then
            totalH = count * size + math.max(count - 1, 0) * spacing
        end
        local container = CreateFrame("Frame", nil, parentFrame)
        container:SetFrameLevel(parentFrame:GetFrameLevel() + 8)
        container:SetSize(totalW, totalH)
        container:SetPoint(anchor, parentFrame, anchor, offX, offY)
        for i = 1, count do
            local icon = container:CreateTexture(nil, "OVERLAY")
            icon:SetSize(size, size)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(icons[((i - 1) % #icons) + 1])
            if grow == "LEFT" then
                local pos = (i - 1) * (size + spacing)
                if i == 1 then icon:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                else icon:SetPoint("RIGHT", container, "RIGHT", -pos, 0) end
            elseif grow == "RIGHT" then
                local pos = (i - 1) * (size + spacing)
                if i == 1 then icon:SetPoint("LEFT", container, "LEFT", 0, 0)
                else icon:SetPoint("LEFT", container, "LEFT", pos, 0) end
            elseif grow == "UP" then
                local pos = (i - 1) * (size + spacing)
                if i == 1 then icon:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
                else icon:SetPoint("BOTTOM", container, "BOTTOM", 0, pos) end
            elseif grow == "DOWN" then
                local pos = (i - 1) * (size + spacing)
                if i == 1 then icon:SetPoint("TOP", container, "TOP", 0, 0)
                else icon:SetPoint("TOP", container, "TOP", 0, -pos) end
            else -- CENTER or default
                local pos = (i - 1) * (size + spacing)
                if i == 1 then icon:SetPoint("LEFT", container, "LEFT", 0, 0)
                else icon:SetPoint("LEFT", container, "LEFT", pos, 0) end
            end
        end
        if refKey then childRefs[refKey] = container end
        return container
    end

    -- Defensive indicator preview
    local healerDB = db.healer or {}
    local defDB = healerDB.defensiveIndicator or {}
    if defDB.enabled then
        local defSize = (defDB.iconSize or 16) * PREVIEW_SCALE
        local defMax = defDB.maxIcons or 3
        local defCount = math.min(defMax, #FAKE_DEFENSIVE_ICONS)
        local defAnchor = defDB.position or "TOP"
        local defGrow = defDB.growDirection or "RIGHT"
        local defSpacing = (defDB.spacing or 2) * PREVIEW_SCALE
        local defOffX = (defDB.offsetX or 0) * PREVIEW_SCALE
        local defOffY = (defDB.offsetY or 0) * PREVIEW_SCALE
        if defAnchor == "BOTTOMLEFT" or defAnchor == "BOTTOM" or defAnchor == "BOTTOMRIGHT" then
            defOffY = defOffY + previewBottomPad
        end
        CreateIconStrip(frame, FAKE_DEFENSIVE_ICONS, defCount, defSize, defAnchor, defGrow, defSpacing, defOffX, defOffY, "defensiveContainer")
    end

    -- Aura indicator preview
    local aiDB = db.auraIndicators or {}
    if aiDB.enabled then
        local normalizeAuraIndicators = ns.Helpers and ns.Helpers.NormalizeAuraIndicatorConfig
        if normalizeAuraIndicators then normalizeAuraIndicators(aiDB) end

        local previewLayer = CreateFrame("Frame", nil, frame)
        previewLayer:SetAllPoints()
        previewLayer:SetFrameLevel(frame:GetFrameLevel() + 8)
        childRefs.auraIndicatorContainer = previewLayer

        local iconCount = 0
        for _, entry in ipairs(aiDB.entries or {}) do
            if entry.enabled ~= false then
                for _, indicator in ipairs(entry.indicators or {}) do
                    if indicator.enabled ~= false and indicator.type == "icon" then
                        iconCount = iconCount + 1
                    end
                end
            end
        end

        if iconCount > 0 then
            local aiSize = (aiDB.iconSize or 14) * PREVIEW_SCALE
            local aiMax = aiDB.maxIndicators or 3
            local aiAnchor = aiDB.anchor or "CENTER"
            local aiGrow = aiDB.growDirection or "RIGHT"
            local aiSpacing = (aiDB.spacing or 2) * PREVIEW_SCALE
            local aiOffX = (aiDB.anchorOffsetX or 0) * PREVIEW_SCALE
            local aiOffY = (aiDB.anchorOffsetY or 0) * PREVIEW_SCALE
            if aiAnchor == "BOTTOMLEFT" or aiAnchor == "BOTTOM" or aiAnchor == "BOTTOMRIGHT" then
                aiOffY = aiOffY + previewBottomPad
            end
            CreateIconStrip(previewLayer, FAKE_AURA_IND_ICONS, math.min(iconCount, aiMax), aiSize, aiAnchor, aiGrow, aiSpacing, aiOffX, aiOffY)
        end

        local firstTint = nil
        local fakeBarIndex = 0
        for _, entry in ipairs(aiDB.entries or {}) do
            if entry.enabled ~= false then
                for _, indicator in ipairs(entry.indicators or {}) do
                    if indicator.enabled ~= false and indicator.type == "healthBarColor" and not firstTint then
                        firstTint = indicator.color
                    elseif indicator.enabled ~= false and indicator.type == "bar" then
                        fakeBarIndex = fakeBarIndex + 1
                        local orientation = indicator.orientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL"
                        local thickness = (indicator.thickness or 4) * PREVIEW_SCALE
                        local matchFrameSize = indicator.matchFrameSize == true
                        local length = (indicator.length or 40) * PREVIEW_SCALE
                        local width = orientation == "HORIZONTAL" and (matchFrameSize and (w - borderSize * 2) or length) or thickness
                        local height = orientation == "VERTICAL" and (matchFrameSize and (h - previewBottomPad - borderSize * 2) or length) or thickness
                        local anchor = indicator.anchor or "BOTTOM"
                        local offX = (indicator.offsetX or 0) * PREVIEW_SCALE
                        local offY = (indicator.offsetY or 0) * PREVIEW_SCALE
                        if anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
                            offY = offY + previewBottomPad
                        end

                        local bar = CreateFrame("StatusBar", nil, previewLayer, "BackdropTemplate")
                        bar:SetStatusBarTexture(texturePath)
                        bar:SetOrientation(orientation)
                        bar:SetMinMaxValues(0, 1)
                        bar:SetValue(fakeBarIndex == 1 and 0.35 or 0.8)
                        bar:SetSize(width, height)
                        bar:SetPoint(anchor, frame, anchor, offX, offY)

                        local baseColor = indicator.color or {0.2, 0.8, 0.2, 1}
                        local shownColor = (indicator.lowTimeThreshold or 0) > 0 and (indicator.lowTimeColor or baseColor) or baseColor
                        bar:SetStatusBarColor(shownColor[1] or 0.2, shownColor[2] or 0.8, shownColor[3] or 0.2, shownColor[4] or 1)

                        local bg = bar:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints()
                        local bgColor = indicator.backgroundColor or { shownColor[1] or 0.2, shownColor[2] or 0.8, shownColor[3] or 0.2, 0.18 }
                        bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] or 0.18)

                        if not indicator.hideBorder then
                            local borderPx = (indicator.borderSize or 1) * px
                            bar:SetBackdrop({
                                edgeFile = "Interface\\Buttons\\WHITE8x8",
                                edgeSize = borderPx,
                            })
                            local bc = indicator.borderColor or {0, 0, 0, 1}
                            bar:SetBackdropBorderColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
                        end
                    end
                end
            end
        end

        if firstTint then
            healthBar:SetStatusBarColor(firstTint[1] or 0.2, firstTint[2] or 0.8, firstTint[3] or 0.2, firstTint[4] or 1)
        end
    end

    -- Private aura preview (with stack & countdown text)
    local paDB = db.privateAuras or {}
    if paDB.enabled then
        local paSize = (paDB.iconSize or 20) * PREVIEW_SCALE
        local paMax = paDB.maxPerFrame or 1
        local paAnchor = paDB.anchor or "CENTER"
        local paGrow = paDB.growDirection or "RIGHT"
        local paSpacing = (paDB.spacing or 2) * PREVIEW_SCALE
        local paOffX = (paDB.anchorOffsetX or 0) * PREVIEW_SCALE
        local paOffY = (paDB.anchorOffsetY or 0) * PREVIEW_SCALE
        if paAnchor == "BOTTOMLEFT" or paAnchor == "BOTTOM" or paAnchor == "BOTTOMRIGHT" then
            paOffY = paOffY + previewBottomPad
        end
        local paContainer = CreateIconStrip(frame, { FAKE_PRIVATE_AURA_ICON }, paMax, paSize, paAnchor, paGrow, paSpacing, paOffX, paOffY, "privateAuraContainer")

        -- Overlay stack count and countdown text on each icon
        if paContainer then
            local paTextScale = paDB.textScale or 2
            local paTextOffX = (paDB.textOffsetX or 0) * PREVIEW_SCALE
            local paTextOffY = (paDB.textOffsetY or 0) * PREVIEW_SCALE
            local paShowNumbers = paDB.showCountdownNumbers ~= false
            local baseFontSize = math.max(8, paSize * 0.55)
            local scaledFontSize = baseFontSize * paTextScale

            -- Walk the icon textures created by CreateIconStrip and attach text
            local textures = { paContainer:GetRegions() }
            for idx, tex in ipairs(textures) do
                if tex:IsObjectType("Texture") then
                    -- Stack count (bottom-right, like Blizzard default)
                    local stackText = paContainer:CreateFontString(nil, "OVERLAY")
                    stackText:SetFont(STANDARD_TEXT_FONT, scaledFontSize, "OUTLINE")
                    stackText:SetTextColor(1, 1, 1, 1)
                    stackText:SetText("2")
                    stackText:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", paTextOffX, paTextOffY)

                    -- Countdown number (center)
                    if paShowNumbers then
                        local cdText = paContainer:CreateFontString(nil, "OVERLAY")
                        cdText:SetFont(STANDARD_TEXT_FONT, scaledFontSize, "OUTLINE")
                        cdText:SetTextColor(1, 0.82, 0, 1)
                        cdText:SetText(idx == 1 and "5" or "12")
                        cdText:SetPoint("CENTER", tex, "CENTER", paTextOffX, paTextOffY)
                    end
                end
            end
        end
    end

    -- Healer: dispel overlay preview (colored border)
    local dispelDB = healerDB.dispelOverlay or {}
    if dispelDB.enabled then
        local dispelBorder = (dispelDB.borderSize or 2) * PREVIEW_SCALE
        local dispelAlpha = dispelDB.opacity or 0.8
        local dispelFill = dispelDB.fillOpacity or 0
        local magicColor = (dispelDB.colors and dispelDB.colors.Magic) or {0.2, 0.6, 1.0, 1}
        local dispelOverlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        dispelOverlay:SetAllPoints(frame)
        dispelOverlay:SetFrameLevel(frame:GetFrameLevel() + 6)
        local QUICore2 = ns.Addon
        local px2 = QUICore2 and QUICore2.GetPixelSize and QUICore2:GetPixelSize(dispelOverlay) or 1
        dispelOverlay:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = dispelBorder * px2,
        })
        dispelOverlay:SetBackdropBorderColor(magicColor[1], magicColor[2], magicColor[3], dispelAlpha)
        dispelOverlay:SetBackdropColor(magicColor[1], magicColor[2], magicColor[3], dispelFill)
        childRefs.dispelOverlay = dispelOverlay
    end

    -- Healer: target highlight preview (tinted fill)
    local targetHL = healerDB.targetHighlight or {}
    if targetHL.enabled then
        local hlFill = targetHL.fillOpacity or 0.15
        local hlColor = targetHL.color or {1, 1, 1, 1}
        local hlOverlay = frame:CreateTexture(nil, "ARTWORK", nil, 7)
        hlOverlay:SetAllPoints(frame)
        hlOverlay:SetColorTexture(hlColor[1] or 1, hlColor[2] or 1, hlColor[3] or 1, hlFill)
        childRefs.targetHighlight = hlOverlay
    end

    -- Indicators: threat border preview
    if indDB.showThreatBorder then
        local threatBorder = (indDB.threatBorderSize or 2) * PREVIEW_SCALE
        local threatColor = indDB.threatColor or {1, 0, 0, 1}
        local threatFill = indDB.threatFillOpacity or 0
        local threatOverlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        threatOverlay:SetAllPoints(frame)
        threatOverlay:SetFrameLevel(frame:GetFrameLevel() + 5)
        local px3 = QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(threatOverlay) or 1
        threatOverlay:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = threatBorder * px3,
        })
        threatOverlay:SetBackdropBorderColor(threatColor[1] or 1, threatColor[2] or 0, threatColor[3] or 0, threatColor[4] or 1)
        threatOverlay:SetBackdropColor(threatColor[1] or 1, threatColor[2] or 0, threatColor[3] or 0, threatFill)
        childRefs.threatOverlay = threatOverlay
    end

    -- Pinned aura indicators (fake preview, individually anchored)
    -- Always show in preview when slots exist, even if disabled, so user can see placement while configuring
    local pinnedDB = db.pinnedAuras or {}
    do
        local pinnedSpecID = GetPlayerSpecID()
        local pinnedSlots = pinnedSpecID and pinnedDB.specSlots and pinnedDB.specSlots[pinnedSpecID]
        if pinnedSlots and #pinnedSlots > 0 then
            local pSlotSize = (pinnedDB.slotSize or 8) * PREVIEW_SCALE
            local pInset = (pinnedDB.edgeInset or 2) * PREVIEW_SCALE
            local PINNED_INSET_DIR = {
                TOPLEFT     = { 1,  -1 },
                TOP         = { 0,  -1 },
                TOPRIGHT    = { -1, -1 },
                LEFT        = { 1,   0 },
                CENTER      = { 0,   0 },
                RIGHT       = { -1,  0 },
                BOTTOMLEFT  = { 1,   1 },
                BOTTOM      = { 0,   1 },
                BOTTOMRIGHT = { -1,  1 },
            }

            local pinnedLayer = CreateFrame("Frame", nil, frame)
            pinnedLayer:SetAllPoints()
            pinnedLayer:SetFrameLevel(frame:GetFrameLevel() + 8)

            for i, slot in ipairs(pinnedSlots) do
                local anchor = slot.anchor or "TOPLEFT"
                local displayType = slot.displayType or "icon"

                local pip = pinnedLayer:CreateTexture(nil, "OVERLAY")
                pip:SetSize(pSlotSize, pSlotSize)

                local insetDir = PINNED_INSET_DIR[anchor] or {0, 0}
                local offX = insetDir[1] * pInset + (slot.offsetX or 0) * PREVIEW_SCALE
                local offY = insetDir[2] * pInset + (slot.offsetY or 0) * PREVIEW_SCALE
                if anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
                    offY = offY + previewBottomPad
                end
                pip:SetPoint(anchor, frame, anchor, offX, offY)

                if displayType == "square" then
                    local color = slot.color or {0.5, 0.5, 0.5, 1}
                    pip:SetColorTexture(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5, color[4] or 1)
                else
                    local spellTex
                    if slot.spellID and C_Spell and C_Spell.GetSpellTexture then
                        local ok, t = pcall(C_Spell.GetSpellTexture, slot.spellID)
                        if ok and t then spellTex = t end
                    end
                    pip:SetTexture(spellTex or 134400)
                    pip:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end
        end
    end

    return wrapper
end


---------------------------------------------------------------------------
-- V2 TILE HOISTS — the Group Frames tile owns the preview block (dropdown
-- + hoisted preview) and element-level inner tabs; frame-level tabs render
-- through the shared schema surface.
--
-- QUI_BuildGroupFramePreview(host, contextMode)   — one-time setup of
--     the tile's preview block; creates a non-interactive preview.
-- QUI_RefreshGroupFramePreview([contextMode])     — rebuild the preview
--     with the current or newly-specified context.
-- QUI_BuildGroupFrameElement(host, elementKey, contextMode)
--     — dispatch to the element builder for one composer element
--     (health, power, name, buffs, debuffs, indicators, etc.).
---------------------------------------------------------------------------

local hoistedPreview = { host = nil, contextMode = "party", childRefs = nil }

local function ClearHoistedPreviewChildren(host)
    if not host then return end
    for _, child in pairs({host:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
        child:ClearAllPoints()
    end
end

local function BuildHoistedPreview()
    local host = hoistedPreview.host
    if not host or not host:IsShown() then return end
    -- Same GUI/C hoist the element dispatcher performs — CreateDesignerPreview
    -- and downstream helpers read these module locals.
    GUI = QUI and QUI.GUI
    C = (GUI and GUI.Colors) or {}
    ClearHoistedPreviewChildren(host)
    local childRefs = {}
    local ok, preview = pcall(CreateDesignerPreview, host, hoistedPreview.contextMode, childRefs)
    if not ok or not preview then return end
    hoistedPreview.childRefs = childRefs
    hoistedPreview.preview = preview

    -- CreateDesignerPreview anchors the wrapper TOPLEFT at (0,0); re-anchor
    -- vertically centered so elements that extend outside the mock's
    -- bounding box (buff/debuff containers hanging below, portrait on the
    -- side) have equal headroom top and bottom.
    preview:ClearAllPoints()
    preview:SetPoint("CENTER", host, "CENTER", 0, 0)
    preview:SetPoint("LEFT", host, "LEFT", 0, 0)
    preview:SetPoint("RIGHT", host, "RIGHT", 0, 0)
end

_G.QUI_BuildGroupFramePreview = function(host, contextMode)
    if not host then return end
    hoistedPreview.host = host
    if contextMode then hoistedPreview.contextMode = contextMode end
    BuildHoistedPreview()
end

_G.QUI_RefreshGroupFramePreview = function(contextMode)
    if contextMode then hoistedPreview.contextMode = contextMode end
    BuildHoistedPreview()
end

-- Widget-bar element settings. Each element's builder uses the composer's
-- own CreateComposerCollapsible (not U.CreateCollapsible), so the tile calls
-- this global directly per tab instead. All group-frame element data is context-aware, so the
-- Party/Raid switch should always route through the visual proxy.
local function MakeElementOnChange()
    return function()
        RefreshGF()
    end
end

_G.QUI_BuildGroupFrameElement = function(host, elementKey, contextMode)
    if not host or not elementKey then return false end
    local gfdb = GetGFDB()
    if not gfdb then return false end

    local builder = ELEMENT_BUILDERS[elementKey]
    if not builder then return false end

    -- GUI and C are forward-declared module locals that Composer:Embed
    -- populates on open. Element builders consume them directly, so we
    -- must initialise before dispatching — otherwise they silently no-op
    -- on every GUI:CreateFormX call.
    GUI = QUI and QUI.GUI
    C = (GUI and GUI.Colors) or {}
    if not GUI then return false end

    local target = CreateVisualProxy(gfdb, contextMode or "party")

    -- Flat render + dual-column rows — same visual language as the sliced
    -- provider tabs (Range & Pet, Appearance, etc.) and the other tiles
    -- (Action Bars, Unit Frames, CDM). Collapsibles become accent-dot
    -- sections; each section's rows pair into two columns.
    _composerAutoExpand = true
    _composerDualColumn = true
    local ok, err = pcall(builder, host, target, MakeElementOnChange())
    _composerAutoExpand = false
    _composerDualColumn = false
    if not ok then
        if geterrorhandler then geterrorhandler()(err) end
        return false
    end
    return true
end

-- Back-compat alias — Indicators tab was wired through this before the
-- generic dispatch landed. Callers can migrate to QUI_BuildGroupFrameElement.
_G.QUI_BuildGroupFrameIndicators = function(host)
    return _G.QUI_BuildGroupFrameElement(host, "indicators", "party")
end
