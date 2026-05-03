--[[
    QUI CDM Spell Composer

    Full container editor popup with live preview, layout configuration,
    entry management, and per-entry override settings. Opens from Layout
    Mode via the "Open Spell Manager" button on CDM containers.

    Singleton frame: only one instance, reused across container switches.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local math_floor = math.floor
local math_abs = math.abs
local math_max = math.max
local table_insert = table.insert
local table_remove = table.remove
local string_lower = string.lower
local string_find = string.find
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_Spell = C_Spell
local C_Item = C_Item

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
-- Accent color: resolved from current theme at open time via RefreshAccentColor()
local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980  -- fallback (Sky Blue)

local function RefreshAccentColor()
    local GUI = QUI and QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        local a = GUI.Colors.accent
        ACCENT_R, ACCENT_G, ACCENT_B = a[1], a[2], a[3]
    end
end

local FRAME_WIDTH = 640
local FRAME_HEIGHT = 700
local NAV_WIDTH = 120
local GRID_CELL_SIZE = 36
local GRID_ICON_SIZE = 28
local GRID_GAP = 2
local GRID_CELL_STRIDE = GRID_CELL_SIZE + GRID_GAP  -- 38
local SECTION_HEADER_HEIGHT = 20
local FORM_ROW = 36
local TAB_HEIGHT = 26

local CONTAINER_LABELS = {
    essential   = "Essential Cooldowns",
    utility     = "Utility Cooldowns",
    buff        = "Buff Icons",
    trackedBar  = "Buff Bars",
}

local CONTAINER_ORDER = { "essential", "utility", "buff", "trackedBar" }

local CONTAINER_TYPES = {
    essential   = "cooldown",
    utility     = "cooldown",
    buff        = "aura",
    trackedBar  = "auraBar",
}

-- Phase G: Resolve container type for any key (built-in or custom).
-- Forward-declared here so all functions below can use it.
-- GetContainerDB is defined in the DB ACCESS section below.
local function ResolveContainerType(containerKey)
    if CONTAINER_TYPES[containerKey] then
        return CONTAINER_TYPES[containerKey]
    end
    -- Defer to runtime DB lookup for custom containers
    local core = Helpers.GetCore()
    local ncdm = core and core.db and core.db.profile and core.db.profile.ncdm
    if ncdm then
        local db = ncdm[containerKey] or (ncdm.containers and ncdm.containers[containerKey])
        if db and db.containerType then
            return db.containerType
        end
    end
    return "cooldown"
end

local TYPE_TAGS = {
    spell = "[Spell]",
    item  = "[Item]",
    slot  = "[Slot]",
    macro = "[Macro]",
}


---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local composerFrame = nil      -- singleton
local activeContainer = nil    -- current container key
local entryCells = {}          -- pooled entry grid cells
local addCells = {}            -- pooled add-source grid cells
local sectionHeaders = {}      -- pooled section header frames
local expandedOverride = nil   -- spellID of expanded override panel (or nil)
local previewIcons = {}        -- preview icon textures
local previewBars = {}         -- preview bar frames (for auraBar containers)
local searchBox = nil          -- search editbox for entry list
local addSearchBox = nil       -- search editbox for add list
local activeAddTab = nil       -- current add-source tab name
local containerTabs = {}       -- tab button frames
local BuildContainerTabs       -- forward declaration; assigned in CONTAINER TABS section

---------------------------------------------------------------------------
-- DB ACCESS
---------------------------------------------------------------------------
local function GetNcdmDB()
    local core = Helpers.GetCore()
    return core and core.db and core.db.profile and core.db.profile.ncdm
end

local function GetContainerDB(containerKey)
    local ncdm = GetNcdmDB()
    if not ncdm then return nil end
    -- Built-in containers live at ncdm[key] (user's saved data).
    -- Custom containers only exist in ncdm.containers[key].
    if ncdm[containerKey] then
        return ncdm[containerKey]
    end
    if ncdm.containers and ncdm.containers[containerKey] then
        return ncdm.containers[containerKey]
    end
    return nil
end

local function GetCDMSpellData()
    return ns.CDMSpellData
end

---------------------------------------------------------------------------
-- REFRESH HELPERS
---------------------------------------------------------------------------
local function RefreshCDM()
    -- Force layout for the active container even during edit mode.
    -- FireChangeCallback (from the data layer) already triggers RefreshAll
    -- for broad state sync.  Only force-layout the specific container here
    -- to avoid cascading double-refreshes that cause icon flicker.
    if activeContainer and _G.QUI_ForceLayoutContainer then
        _G.QUI_ForceLayoutContainer(activeContainer)
    end
    -- Buff bar icons/bars need an explicit poke — ForceLayoutContainer
    -- triggers QUI_OnBuffLayoutReady for icon positioning, but the bar
    -- side (CDMBars) is only refreshed via QUI_RefreshBuffBar.
    if _G.QUI_RefreshBuffBar then _G.QUI_RefreshBuffBar() end
end

---------------------------------------------------------------------------
-- ENTRY HELPERS
---------------------------------------------------------------------------
-- Some legacy customTrackers entries predate the typed schema and arrive
-- with entry.type == nil. Detect whether the id looks like an item first
-- (items are a finite namespace), then fall back to spell. Cached so the
-- lookup only runs once per entry.
local function ResolveEntryType(entry)
    if not entry then return nil end
    if entry.type then return entry.type end
    if type(entry.id) ~= "number" then return nil end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, entry.id)
        if ok and itemID then
            entry.type = "item"
            return "item"
        end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, entry.id)
        if ok and info and info.name then
            entry.type = "spell"
            return "spell"
        end
    end
    return nil
end

local function GetEntryIcon(entry)
    if not entry then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local etype = entry.type or ResolveEntryType(entry)
    if etype == "spell" then
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, entry.id)
            if ok and info and info.iconID then return info.iconID end
        end
    elseif etype == "item" then
        if C_Item and C_Item.GetItemIconByID then
            local ok, icon = pcall(C_Item.GetItemIconByID, entry.id)
            if ok and icon then return icon end
        end
    elseif etype == "slot" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID and C_Item and C_Item.GetItemIconByID then
            local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
            if ok and icon then return icon end
        end
    elseif etype == "macro" then
        if entry.macroName then
            local macroIndex = GetMacroIndexByName(entry.macroName)
            if macroIndex and macroIndex > 0 then
                local _, texID = GetMacroInfo(macroIndex)
                if texID then return texID end
            end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetEntryName(entry)
    if not entry then return "Unknown" end
    local etype = entry.type or ResolveEntryType(entry)
    if etype == "spell" then
        -- Try override spell first (hero talent transforms, e.g.,
        -- Divine Toll → Holy Bulwark) so the name matches the icon.
        if C_Spell and C_Spell.GetSpellInfo then
            local displayID = entry.id
            if C_Spell.GetOverrideSpell then
                local ook, oid = pcall(C_Spell.GetOverrideSpell, entry.id)
                if ook and oid and oid ~= entry.id then displayID = oid end
            end
            local ok, info = pcall(C_Spell.GetSpellInfo, displayID)
            if ok and info and info.name then return info.name end
            -- Fallback to base ID if override lookup failed
            if displayID ~= entry.id then
                ok, info = pcall(C_Spell.GetSpellInfo, entry.id)
                if ok and info and info.name then return info.name end
            end
        end
        return "Spell #" .. tostring(entry.id or "?")
    elseif etype == "item" then
        if C_Item and C_Item.GetItemNameByID then
            local ok, name = pcall(C_Item.GetItemNameByID, entry.id)
            if ok and name then return name end
        end
        return "Item #" .. tostring(entry.id or "?")
    elseif etype == "slot" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID and C_Item and C_Item.GetItemNameByID then
            local ok, name = pcall(C_Item.GetItemNameByID, itemID)
            if ok and name then return name end
        end
        return "Trinket Slot " .. tostring(entry.id or "?")
    elseif etype == "macro" then
        return entry.macroName or "Macro"
    end
    return "Unknown"
end

-- True if the entry is castable / usable by the player currently logged in.
-- Items, slots, macros are always considered "usable" here — the cross-class
-- mismatch concept only applies to spells. Non-spell types fall back to the
-- runtime hideNonUsable filter for their own usability rules.
--
-- Spell knownness is delegated to CDMSpellData:IsSpellKnown so this check
-- inherits the override-chain and CDM-viewer fallbacks needed to recognize
-- talent / hero-talent / alternate-ID variants that IsPlayerSpell and
-- IsSpellKnownOrOverridesKnown alone miss (e.g., a spell added on one spec
-- whose stored ID isn't the active spec's variant).
local function IsEntryUsableOnCurrentPlayer(entry)
    if type(entry) ~= "table" then return true end
    if entry.type ~= "spell" then return true end
    if type(entry.id) ~= "number" then return true end
    local spellData = ns.CDMSpellData
    if not spellData or type(spellData.IsSpellKnown) ~= "function" then return true end
    return spellData:IsSpellKnown(entry.id) == true
end

---------------------------------------------------------------------------
-- FRAME FACTORY HELPERS
---------------------------------------------------------------------------
local function CreateBackdropFrame(parent, level)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if level then f:SetFrameLevel(level) end
    return f
end

-- Explicit bg + 4 border textures. Avoids Blizzard's
-- Blizzard_SharedXML/Backdrop.lua SetupTextureCoordinates → GetWidth
-- recursion (C stack overflow) that can fire when SetBackdrop runs on a
-- frame inside a UIPanelScrollFrameTemplate child at certain
-- width/height/effectiveScale combinations. Mirrors the safe helper in
-- modules/cooldowns/owned/settings/containers_page_surface.lua.
local function SetSimpleBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    local bg = frame._bg
    if not bg then
        bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        frame._bg = bg
    end
    bg:SetColorTexture(bgR or 0.08, bgG or 0.08, bgB or 0.1, bgA or 1)

    local border = frame._border
    if not border then
        border = {}
        for i = 1, 4 do
            border[i] = frame:CreateTexture(nil, "BORDER")
        end
        border[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border[1]:SetHeight(1)
        border[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        border[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        border[2]:SetHeight(1)
        border[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        border[3]:SetWidth(1)
        border[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        border[4]:SetWidth(1)
        frame._border = border
    end
    local er, eg, eb, ea = borderR or 0.2, borderG or 0.2, borderB or 0.2, borderA or 1
    for i = 1, 4 do
        border[i]:SetColorTexture(er, eg, eb, ea)
    end

    -- Compatibility shims so callers can keep using SetBackdropColor /
    -- SetBackdropBorderColor (e.g. hover highlights). Override the
    -- BackdropTemplate methods (if present) — write to our textures
    -- instead, since we never called Blizzard's SetBackdrop.
    if not frame._setBackdropShimmed then
        frame.SetBackdropColor = function(self, r, g, b, a)
            if self._bg then self._bg:SetColorTexture(r, g, b, a or 1) end
        end
        frame.SetBackdropBorderColor = function(self, r, g, b, a)
            if not self._border then return end
            for i = 1, #self._border do
                self._border[i]:SetColorTexture(r, g, b, a or 1)
            end
        end
        frame._setBackdropShimmed = true
    end
end

local function CreateSmallButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 22, height or 20)
    SetSimpleBackdrop(btn, 0.12, 0.12, 0.15, 0.9, 0.3, 0.3, 0.3, 1)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    label:SetTextColor(0.9, 0.9, 0.9, 1)
    btn._label = label
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end)
    return btn
end

local function CreateAccentButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 140, height or 26)
    SetSimpleBackdrop(btn, ACCENT_R * 0.2, ACCENT_G * 0.2, ACCENT_B * 0.2, 0.9,
        ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    btn._label = label
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        self:SetBackdropColor(ACCENT_R * 0.3, ACCENT_G * 0.3, ACCENT_B * 0.3, 0.9)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        self:SetBackdropColor(ACCENT_R * 0.2, ACCENT_G * 0.2, ACCENT_B * 0.2, 0.9)
    end)
    return btn
end

local function AddButtonTooltip(btn, text)
    local origOnEnter = btn:GetScript("OnEnter")
    btn:SetScript("OnEnter", function(self)
        if origOnEnter then origOnEnter(self) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetFrameLevel(250)
        GameTooltip:SetText(text, 1, 1, 1)
        GameTooltip:Show()
    end)
    local origOnLeave = btn:GetScript("OnLeave")
    btn:SetScript("OnLeave", function(self)
        if origOnLeave then origOnLeave(self) end
        GameTooltip:Hide()
    end)
end

local function CreateSearchBox(parent, width, placeholder)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 200, 22)
    SetSimpleBackdrop(box, 0.06, 0.06, 0.08, 1, 0.25, 0.25, 0.25, 1)
    box:SetFontObject("GameFontNormalSmall")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(50)

    local ph = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ph:SetPoint("LEFT", 6, 0)
    ph:SetTextColor(0.4, 0.4, 0.4, 1)
    ph:SetText(placeholder or "Search...")
    box._placeholder = ph

    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            ph:Hide()
        else
            ph:Show()
        end
        if self._onSearch then self._onSearch(text) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end)
    return box
end

---------------------------------------------------------------------------
-- SCROLL FRAME BUILDER
-- Creates a basic scroll frame with mousewheel support. Returns the
-- scroll frame and the content frame to parent children into.
---------------------------------------------------------------------------
local function CreateScrollArea(parent, width, height)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetSize(width, height)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(width - 12) -- leave room for scrollbar
    content:SetHeight(1) -- will be set dynamically
    scrollFrame:SetScrollChild(content)

    -- Keep content width in sync when scroll frame is resized by anchors
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        if w and w > 16 then
            content:SetWidth(w - 12)
        end
    end)

    -- Scroll bar track + thumb
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.15, 0.15, 0.15, 0.4)

    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.5)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetHeight(20)

    local scrollPos = 0
    local maxScroll = 0

    local function UpdateScroll()
        local contentH = content:GetHeight()
        local frameH = scrollFrame:GetHeight()
        maxScroll = math_max(0, contentH - frameH)
        if scrollPos > maxScroll then scrollPos = maxScroll end
        if scrollPos < 0 then scrollPos = 0 end
        scrollFrame:SetVerticalScroll(scrollPos)

        -- Update thumb position and visibility
        if maxScroll <= 0 then
            track:Hide()
        else
            track:Show()
            local trackH = track:GetHeight()
            local ratio = frameH / contentH
            local thumbH = math_max(16, trackH * ratio)
            thumb:SetHeight(thumbH)
            local travel = trackH - thumbH
            local offset = (scrollPos / maxScroll) * travel
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -offset)
        end
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollPos = scrollPos - (delta * 30)
        UpdateScroll()
    end)

    content._updateScroll = UpdateScroll
    scrollFrame._content = content
    scrollFrame._thumb = thumb
    scrollFrame._resetScroll = function()
        scrollPos = 0
        UpdateScroll()
    end
    return scrollFrame, content
end

---------------------------------------------------------------------------
-- LIVE PREVIEW
---------------------------------------------------------------------------
local previewFrame = nil
local previewScaleSlider = nil
local previewScale = 1.5

local function BuildPreviewSection(parent)
    local container = CreateBackdropFrame(parent)
    container:SetHeight(180)
    SetSimpleBackdrop(container, 0.04, 0.04, 0.06, 1, 0.15, 0.15, 0.15, 1)

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Live Preview")
    title:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Icon grid area
    local gridArea = CreateFrame("Frame", nil, container)
    gridArea:SetPoint("TOPLEFT", 8, -24)
    gridArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 36)
    gridArea:SetClipsChildren(true)
    container._gridArea = gridArea

    -- Scale slider area
    local scaleLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleLabel:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 8, 10)
    scaleLabel:SetText("Preview Scale:")
    scaleLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    local scaleValueText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scaleValueText:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 10)
    scaleValueText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    -- Slider track
    local sliderTrack = CreateFrame("Button", nil, container)
    sliderTrack:SetHeight(6)
    sliderTrack:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    sliderTrack:SetPoint("RIGHT", scaleValueText, "LEFT", -8, 0)

    local trackBg = sliderTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.15, 0.15, 0.15, 1)

    local trackFill = sliderTrack:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("LEFT")
    trackFill:SetHeight(6)
    trackFill:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.6)

    local function UpdateScaleVisual()
        local pct = (previewScale - 0.5) / 2.5
        trackFill:SetWidth(math_max(1, sliderTrack:GetWidth() * pct))
        scaleValueText:SetText(string.format("%.1fx", previewScale))
    end

    sliderTrack:SetScript("OnClick", function(self)
        local x = select(1, GetCursorPosition()) / self:GetEffectiveScale()
        local left = self:GetLeft()
        local w = self:GetWidth()
        local pct = (x - left) / w
        pct = math_max(0, math.min(1, pct))
        previewScale = 0.5 + pct * 2.5
        previewScale = math_floor(previewScale * 10 + 0.5) / 10
        UpdateScaleVisual()
        if composerFrame and composerFrame._refreshPreview then
            composerFrame._refreshPreview()
        end
    end)

    container._updateScaleVisual = UpdateScaleVisual
    previewFrame = container
    return container
end

-- Forward declarations (needed by drag-and-drop which is defined between these two)
local RefreshPreview
local RefreshEntryList
local RefreshAddList
-- Forward-declared so RefreshPreview (defined below) can capture it as an
-- upvalue; the assignment lives further down with GetOrCreateEntryCell.
local IsEntryRegisteredInBlizzCDM

RefreshPreview = function()
    if not previewFrame or not activeContainer then return end

    local gridArea = previewFrame._gridArea
    if not gridArea then return end

    -- Clear old preview icons
    for _, obj in ipairs(previewIcons) do
        if obj.tex then obj.tex:Hide(); obj.tex:ClearAllPoints() end
        if obj.border then obj.border:Hide(); obj.border:ClearAllPoints() end
    end
    -- Clear old preview bars
    for _, bar in ipairs(previewBars) do
        if bar then bar:Hide(); bar:ClearAllPoints() end
    end

    local db = GetContainerDB(activeContainer)
    if not db then return end

    -- customBar containers store their list in `entries` (mixed types).
    local isCustomBar = (db.containerType == "customBar")
    local entries = isCustomBar and db.entries or db.ownedSpells
    if type(entries) ~= "table" then return end

    local containerType = ResolveContainerType(activeContainer) or "cooldown"
    local scale = previewScale or 1.5

    ---------------------------------------------------------------------------
    -- AURA BAR PREVIEW (bar mockups instead of icons)
    ---------------------------------------------------------------------------
    if containerType == "auraBar" then
        local barHeight = (db.barHeight or 25) * scale * 0.5
        local barWidth = (db.barWidth or 215) * scale * 0.5
        local spacing = (db.spacing or 2) * scale * 0.5
        local borderSize = (db.borderSize or 2) * scale * 0.5
        local hideIcon = db.hideIcon
        local iconSize = barHeight
        local textSize = math_max(8, math_floor((db.textSize or 14) * scale * 0.5))

        -- Resolve bar color
        local barR, barG, barB = 0.376, 0.647, 0.980
        if db.useClassColor then
            local _, class = UnitClass("player")
            local color = class and RAID_CLASS_COLORS[class]
            if color then barR, barG, barB = color.r, color.g, color.b end
        elseif db.barColor then
            barR = db.barColor[1] or barR
            barG = db.barColor[2] or barG
            barB = db.barColor[3] or barB
        end
        local barOpacity = db.barOpacity or 1.0
        local bgColor = db.bgColor or {0, 0, 0, 1}
        local bgOpacity = db.bgOpacity or 0.5

        local growUp = db.growUp
        local gridW = gridArea:GetWidth()
        local gridH = gridArea:GetHeight()

        -- Total stack height for vertical centering
        local count = #entries
        local totalH = count * barHeight + math_max(0, count - 1) * spacing
        local centerY = -gridH / 2
        local startY
        if growUp then
            startY = centerY - totalH / 2
        else
            startY = centerY + totalH / 2
        end

        local centerX = gridW / 2

        -- Dummy fill values for visual variety
        local fills = { 0.85, 0.60, 0.40, 0.25, 0.70, 0.55, 0.35 }

        for i, entry in ipairs(entries) do
            local bar = previewBars[i]
            if not bar then
                bar = CreateFrame("Frame", nil, gridArea)
                bar._bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
                bar._bg:SetAllPoints()
                bar._fill = bar:CreateTexture(nil, "ARTWORK")
                bar._border = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
                bar._icon = bar:CreateTexture(nil, "OVERLAY")
                bar._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                bar._iconBorder = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
                bar._nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                bar._nameText:SetJustifyH("LEFT")
                bar._timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                bar._timeText:SetJustifyH("RIGHT")
                previewBars[i] = bar
            end

            bar:ClearAllPoints()
            bar:SetSize(barWidth, barHeight)

            -- Vertical position
            local barY
            if growUp then
                barY = startY + (i - 1) * (barHeight + spacing) + barHeight / 2
            else
                barY = startY - (i - 1) * (barHeight + spacing) - barHeight / 2
            end
            bar:SetPoint("CENTER", gridArea, "TOPLEFT", centerX, barY)

            -- Border (behind bar)
            bar._border:ClearAllPoints()
            bar._border:SetPoint("TOPLEFT", bar, "TOPLEFT", -borderSize, borderSize)
            bar._border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", borderSize, -borderSize)
            bar._border:SetColorTexture(0, 0, 0, 1)
            bar._border:Show()

            -- Background
            bar._bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgOpacity)
            bar._bg:Show()

            -- Fill bar (percentage-based width)
            local fillPct = fills[((i - 1) % #fills) + 1]
            bar._fill:ClearAllPoints()
            bar._fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bar._fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar._fill:SetWidth(math_max(1, barWidth * fillPct))
            -- Per-spell bar color override
            local fillR, fillG, fillB = barR, barG, barB
            if db.colorOverrides and entry.id then
                local oc = db.colorOverrides[entry.id]
                if type(oc) == "table" then
                    fillR = oc[1] or fillR
                    fillG = oc[2] or fillG
                    fillB = oc[3] or fillB
                end
            end
            bar._fill:SetColorTexture(fillR, fillG, fillB, barOpacity)
            bar._fill:Show()

            -- Icon
            if hideIcon then
                bar._icon:Hide()
                bar._iconBorder:Hide()
            else
                bar._iconBorder:ClearAllPoints()
                bar._iconBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", -iconSize - borderSize, borderSize)
                bar._iconBorder:SetPoint("BOTTOMRIGHT", bar, "TOPLEFT", borderSize, -barHeight - borderSize)
                bar._iconBorder:SetColorTexture(0, 0, 0, 1)
                bar._iconBorder:Show()

                bar._icon:ClearAllPoints()
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", -iconSize, 0)
                bar._icon:SetSize(iconSize, iconSize)
                bar._icon:SetTexture(GetEntryIcon(entry))
                if IsEntryRegisteredInBlizzCDM(entry) then
                    bar._icon:SetVertexColor(1, 1, 1)
                else
                    bar._icon:SetVertexColor(1, 0.4, 0.4)
                end
                bar._icon:Show()
            end

            -- Text
            local fontObj = bar._nameText:GetFontObject()
            if fontObj then
                local fontPath = fontObj:GetFont()
                if fontPath then
                    bar._nameText:SetFont(fontPath, textSize, "OUTLINE")
                    bar._timeText:SetFont(fontPath, textSize, "OUTLINE")
                end
            end

            bar._nameText:ClearAllPoints()
            bar._nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
            bar._nameText:SetPoint("RIGHT", bar._timeText, "LEFT", -4, 0)
            bar._nameText:SetText(GetEntryName(entry))
            bar._nameText:SetTextColor(1, 1, 1, 1)
            bar._nameText:Show()

            local dummySecs = ({32, 18, 9, 5, 45, 22, 14})[((i - 1) % 7) + 1]
            bar._timeText:ClearAllPoints()
            bar._timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
            bar._timeText:SetWidth(barWidth * 0.25)
            bar._timeText:SetText(tostring(dummySecs) .. "s")
            bar._timeText:SetTextColor(1, 1, 1, 1)
            bar._timeText:Show()

            bar:Show()
        end

        if previewFrame._updateScaleVisual then
            previewFrame._updateScaleVisual()
        end
        return
    end

    ---------------------------------------------------------------------------
    -- ICON-BASED PREVIEW (cooldown and aura containers)
    ---------------------------------------------------------------------------
    local isCooldown = (containerType == "cooldown")
    local iconIdx = 0
    local ROW_GAP_PREVIEW = 5 * scale * 0.5

    -- Build row info for cooldown containers
    local rows = {}
    if isCooldown then
        for r = 1, 3 do
            local rowData = db["row" .. r]
            if rowData and rowData.iconCount and rowData.iconCount > 0 then
                local aspectRatio = rowData.aspectRatioCrop or 1.0
                rows[#rows + 1] = {
                    rowNum = r,
                    count = rowData.iconCount,
                    size = (rowData.iconSize or 40) * scale * 0.5,
                    height = ((rowData.iconSize or 40) / aspectRatio) * scale * 0.5,
                    padding = (rowData.padding or 2) * scale * 0.5,
                    borderSize = math_max(1, (rowData.borderSize or 1) * scale * 0.5),
                    borderColor = rowData.borderColorTable or {0, 0, 0, 1},
                    yOffset = (rowData.yOffset or 0) * scale * 0.5,
                }
            end
        end
    elseif isCustomBar then
        -- customBar: single row of icons laid out horizontally (legacy
        -- customTracker semantics). Uses iconSize/spacing/borderSize from
        -- the container, not the aura-container padding field.
        local iconSize = (db.iconSize or 28) * scale * 0.5
        local aspectRatio = db.aspectRatioCrop or 1.0
        local iconHeight = (iconSize / aspectRatio)
        local spacing = (db.spacing or 4) * scale * 0.5
        local borderSize = math_max(1, (db.borderSize or 2) * scale * 0.5)
        rows[1] = {
            count = #entries, size = iconSize, height = iconHeight,
            padding = spacing, borderSize = borderSize,
            borderColor = {0, 0, 0, 1}, yOffset = 0,
        }
    else
        -- Aura containers: single row with all icons
        local iconSize = (db.iconSize or 40) * scale * 0.5
        local padding = (db.padding or 2) * scale * 0.5
        rows[1] = {
            count = #entries, size = iconSize, height = iconSize,
            padding = padding, borderSize = 1,
            borderColor = {0, 0, 0, 1}, yOffset = 0,
        }
    end

    -- Sort entries by row assignment for correct preview layout
    if isCooldown and #rows > 1 then
        local buckets = {}
        local noRow = {}
        for _, e in ipairs(entries) do
            local ar = e and e.row
            if ar then
                if not buckets[ar] then buckets[ar] = {} end
                buckets[ar][#buckets[ar] + 1] = e
            else
                noRow[#noRow + 1] = e
            end
        end
        local sorted = {}
        local noRowIdx = 1
        for rn, rowInfo in ipairs(rows) do
            local actualRowNum = rowInfo.rowNum
            local rowStart = #sorted + 1
            if buckets[actualRowNum] then
                for _, e in ipairs(buckets[actualRowNum]) do
                    sorted[#sorted + 1] = e
                end
            end
            local assigned = buckets[actualRowNum] and #buckets[actualRowNum] or 0
            local remaining = rowInfo.count - assigned
            for _ = 1, remaining do
                if noRowIdx <= #noRow then
                    sorted[#sorted + 1] = noRow[noRowIdx]
                    noRowIdx = noRowIdx + 1
                end
            end
            -- Override row count to actual icons placed
            rowInfo._actualCount = #sorted - rowStart + 1
        end
        while noRowIdx <= #noRow do
            sorted[#sorted + 1] = noRow[noRowIdx]
            noRowIdx = noRowIdx + 1
        end
        entries = sorted
    end

    -- Calculate total height for vertical centering
    local totalHeight = 0
    local numRows = 0
    local entryCheck = 1
    for _, rowInfo in ipairs(rows) do
        local rowCount = rowInfo._actualCount or rowInfo.count
        local iconsInRow = math.min(rowCount, #entries - entryCheck + 1)
        if iconsInRow > 0 then
            totalHeight = totalHeight + rowInfo.height
            numRows = numRows + 1
            if numRows > 1 then totalHeight = totalHeight + ROW_GAP_PREVIEW end
            entryCheck = entryCheck + iconsInRow
        end
    end

    local growUp = (db.growthDirection == "UP")
    -- customBar entries are stored in "grow-source" order: entries[1] is
    -- placed first at the bar's anchor end. When growing LEFT (or UP),
    -- entries[1] ends up at the right (or bottom), so the preview must
    -- render the list reversed to match the in-game visual.
    if isCustomBar and (db.growDirection == "LEFT" or db.growDirection == "UP") then
        local reversed = {}
        for i = #entries, 1, -1 do reversed[#reversed + 1] = entries[i] end
        entries = reversed
    end
    local gridW = gridArea:GetWidth()
    local gridH = gridArea:GetHeight()
    local centerX = gridW / 2
    local centerY = -gridH / 2

    -- Start position: offset from center
    local currentY = centerY + (totalHeight / 2)
    if growUp then
        currentY = centerY - (totalHeight / 2)
    end

    local entryIdx = 1
    for _, rowInfo in ipairs(rows) do
        local rowCount = rowInfo._actualCount or rowInfo.count
        local iconsInRow = math.min(rowCount, #entries - entryIdx + 1)
        if iconsInRow > 0 then

        local rowWidth = (iconsInRow * rowInfo.size) + ((iconsInRow - 1) * rowInfo.padding)
        local rowStartX = centerX - rowWidth / 2 + rowInfo.size / 2

        local rowCenterY
        if growUp then
            rowCenterY = currentY + rowInfo.height / 2 + rowInfo.yOffset
        else
            rowCenterY = currentY - rowInfo.height / 2 + rowInfo.yOffset
        end

        for col = 1, iconsInRow do
            if entryIdx > #entries then break end
            local entry = entries[entryIdx]
            entryIdx = entryIdx + 1

            iconIdx = iconIdx + 1
            local obj = previewIcons[iconIdx]
            if not obj then
                obj = {}
                obj.border = gridArea:CreateTexture(nil, "BACKGROUND")
                obj.tex = gridArea:CreateTexture(nil, "ARTWORK")
                previewIcons[iconIdx] = obj
            end

            local x = rowStartX + ((col - 1) * (rowInfo.size + rowInfo.padding))
            local bSize = rowInfo.borderSize

            -- Border
            obj.border:ClearAllPoints()
            obj.border:SetSize(rowInfo.size + bSize * 2, rowInfo.height + bSize * 2)
            obj.border:SetPoint("CENTER", gridArea, "TOPLEFT", x, rowCenterY)
            local bc = rowInfo.borderColor
            obj.border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
            obj.border:Show()

            -- Icon
            obj.tex:ClearAllPoints()
            obj.tex:SetSize(rowInfo.size, rowInfo.height)
            obj.tex:SetPoint("CENTER", gridArea, "TOPLEFT", x, rowCenterY)
            obj.tex:SetTexture(GetEntryIcon(entry))
            obj.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if IsEntryRegisteredInBlizzCDM(entry) then
                obj.tex:SetVertexColor(1, 1, 1)
            else
                obj.tex:SetVertexColor(1, 0.4, 0.4)
            end
            obj.tex:Show()
        end

        if growUp then
            currentY = currentY + rowInfo.height + ROW_GAP_PREVIEW
        else
            currentY = currentY - rowInfo.height - ROW_GAP_PREVIEW
        end
        end -- if iconsInRow > 0
    end

    if previewFrame._updateScaleVisual then
        previewFrame._updateScaleVisual()
    end
end

---------------------------------------------------------------------------
-- PER-ENTRY OVERRIDE PANEL
---------------------------------------------------------------------------
local overridePanel = nil
local HideOverridePanel  -- forward declaration

local function BuildOverridePanel(parent)
    -- Parent to UIParent so the panel renders above everything, including
    -- the composer frame itself. Uses FULLSCREEN_DIALOG strata to guarantee
    -- it sits on top of the TOOLTIP-strata composer.
    local panel = CreateFrame("Frame", "QUI_CDMOverridePanel", UIParent, "BackdropTemplate")
    panel:SetHeight(180)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(500)
    SetSimpleBackdrop(panel, 0.06, 0.06, 0.08, 0.98, ACCENT_R * 0.5, ACCENT_G * 0.5, ACCENT_B * 0.5, 0.8)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Close button (X) in upper-right — raised above the panel's drag layer
    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    closeBtn:SetFrameLevel(panel:GetFrameLevel() + 10)
    closeBtn:RegisterForClicks("AnyUp")
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(0.6, 0.6, 0.6, 1)
    closeBtn:SetScript("OnClick", function()
        HideOverridePanel(true)
    end)
    closeBtn:SetScript("OnEnter", function()
        closeText:SetTextColor(0.9, 0.3, 0.3, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeText:SetTextColor(0.6, 0.6, 0.6, 1)
    end)
    panel._closeBtn = closeBtn

    -- ESC to close
    if not tContains(UISpecialFrames, "QUI_CDMOverridePanel") then
        tinsert(UISpecialFrames, "QUI_CDMOverridePanel")
    end

    -- Also clear expandedOverride state when hidden by any means
    panel:SetScript("OnHide", function()
        expandedOverride = nil
    end)

    panel:Hide()

    overridePanel = panel
    return panel
end

local function ShowOverridePanel(parentRow, containerKey, entry, entryIndex)
    if not overridePanel or not entry then return end

    -- Clear old contents — preserve close button
    local closeBtn = overridePanel._closeBtn
    local children = { overridePanel:GetChildren() }
    for _, child in ipairs(children) do
        if child ~= closeBtn then
            child:Hide()
            child:SetParent(nil)
        end
    end
    -- Hide dynamically created font strings only (not backdrop textures)
    local regions = { overridePanel:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("FontString") then
            region:Hide()
        end
    end

    local GUI = QUI and QUI.GUI
    if not GUI then return end

    local spellData = GetCDMSpellData()
    if not spellData then return end

    local spellID = entry.id
    if not spellID then
        overridePanel:Hide()
        return
    end

    local overrides = spellData:GetSpellOverride(containerKey, spellID) or {}

    -- Build a temp table that reads/writes through the override API
    local proxyDB = {}
    setmetatable(proxyDB, {
        __index = function(_, key)
            local ov = spellData:GetSpellOverride(containerKey, spellID)
            return ov and ov[key]
        end,
        __newindex = function(_, key, value)
            if value == nil then
                spellData:ClearSpellOverride(containerKey, spellID, key)
            else
                spellData:SetSpellOverride(containerKey, spellID, key, value)
            end
        end,
    })

    local function OnOverrideChange()
        RefreshCDM()
        C_Timer.After(0.05, RefreshPreview)
    end

    -- Spell name title
    local titleLabel = overridePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", overridePanel, "TOPLEFT", 8, -6)
    titleLabel:SetPoint("RIGHT", overridePanel, "RIGHT", -24, 0)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(GetEntryName(entry))
    titleLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    local sy = -24
    local function PlaceWidget(widget)
        widget:SetPoint("TOPLEFT", overridePanel, "TOPLEFT", 8, sy)
        widget:SetPoint("RIGHT", overridePanel, "RIGHT", -8, 0)
        sy = sy - FORM_ROW
    end

    -- Hidden toggle
    local hiddenCheck = GUI:CreateFormCheckbox(overridePanel, "Hidden", "hidden", proxyDB, OnOverrideChange,
        { description = "Hide this spell entirely from the CDM viewer. Useful for spells tracked automatically by the spec ruleset that you don't personally care about." })
    PlaceWidget(hiddenCheck)

    -- Glow toggle
    local glowCheck = GUI:CreateFormCheckbox(overridePanel, "Glow Enabled", "glowEnabled", proxyDB, OnOverrideChange,
        { description = "Allow this spell to show the proc/usable glow. Turn off if the glow for this specific spell becomes distracting." })
    PlaceWidget(glowCheck)

    -- Proc on Usable toggle (glow when spell is castable: off CD + has resources)
    local procCheck = GUI:CreateFormCheckbox(overridePanel, "Proc on Usable", "procOnUsable", proxyDB, OnOverrideChange,
        { description = "Glow this spell whenever it becomes castable (off cooldown AND resources available), not only on real proc auras." })
    PlaceWidget(procCheck)

    -- Glow color
    -- For color pickers, we need a real table reference. Use a temp table synced back.
    local glowColorDB = { glowColor = overrides.glowColor or { ACCENT_R, ACCENT_G, ACCENT_B, 1 } }
    local glowColorPicker = GUI:CreateFormColorPicker(overridePanel, "Glow Color", "glowColor", glowColorDB, function()
        spellData:SetSpellOverride(containerKey, spellID, "glowColor", glowColorDB.glowColor)
        OnOverrideChange()
    end, nil,
        { description = "Per-spell override for the proc/usable glow color. Falls back to the container's glow color when unchanged." })
    PlaceWidget(glowColorPicker)

    -- Bar color override (only for bar-type containers)
    local cType = ResolveContainerType(containerKey)
    if cType == "auraBar" then
        local containerDB = GetContainerDB(containerKey)
        if containerDB then
            if type(containerDB.colorOverrides) ~= "table" then
                containerDB.colorOverrides = {}
            end
            local existingColor = containerDB.colorOverrides[spellID]
            local barColorDB = { barColor = existingColor or (containerDB.barColor and {unpack(containerDB.barColor)}) or { ACCENT_R, ACCENT_G, ACCENT_B, 1 } }

            local barColorEnabled = existingColor ~= nil
            local barColorToggleDB = { barColorOverride = barColorEnabled }
            local barColorCheck = GUI:CreateFormCheckbox(overridePanel, "Bar Color Override", "barColorOverride", barColorToggleDB, function()
                barColorEnabled = barColorToggleDB.barColorOverride
                if barColorEnabled then
                    containerDB.colorOverrides[spellID] = barColorDB.barColor
                else
                    containerDB.colorOverrides[spellID] = nil
                end
                OnOverrideChange()
            end, { description = "Use a per-spell bar color for this aura-bar spell instead of the container's default bar color." })
            PlaceWidget(barColorCheck)

            local barColorPicker = GUI:CreateFormColorPicker(overridePanel, "Bar Color", "barColor", barColorDB, function()
                if barColorEnabled then
                    containerDB.colorOverrides[spellID] = barColorDB.barColor
                    OnOverrideChange()
                end
            end, nil,
                { description = "Per-spell bar color applied when Bar Color Override is on." })
            PlaceWidget(barColorPicker)
        end
    end

    -- Duration text toggle
    local durCheck = GUI:CreateFormCheckbox(overridePanel, "Hide Duration Text", "hideDurationText", proxyDB, OnOverrideChange,
        { description = "Hide the numeric countdown on this spell's icon/bar only, while leaving other spells in the container unchanged." })
    PlaceWidget(durCheck)

    -- Desaturate Ignore Aura — only for cooldown containers (essential/utility)
    if cType == "cooldown" then
        local desatIgnoreAura = GUI:CreateFormCheckbox(overridePanel, "Desaturate Ignore Aura", "desaturateIgnoreAura", proxyDB, OnOverrideChange,
            { description = "Skip the desaturation-while-buff-active behavior for this spell. Turn on if a linked buff causes the icon to appear dimmed when you want it bright." })
        PlaceWidget(desatIgnoreAura)
    end

    -- Size override (simple editbox, 0 = default, 1-80 = px)
    local sizeRow = CreateFrame("Frame", nil, overridePanel)
    sizeRow:SetHeight(FORM_ROW)
    local sizeLabel = sizeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("LEFT", 0, 0)
    sizeLabel:SetText("Size Override")
    sizeLabel:SetTextColor(0.85, 0.85, 0.85, 1)

    local sizeHint = sizeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeHint:SetPoint("LEFT", sizeLabel, "RIGHT", 6, 0)
    sizeHint:SetText("(0-80, 0 = default)")
    sizeHint:SetTextColor(0.45, 0.45, 0.45, 1)

    local sizeBox = CreateFrame("EditBox", nil, sizeRow, "BackdropTemplate")
    sizeBox:SetSize(48, 20)
    sizeBox:SetPoint("RIGHT", sizeRow, "RIGHT", 0, 0)
    SetSimpleBackdrop(sizeBox, 0.1, 0.1, 0.12, 1, 0.3, 0.3, 0.3, 1)
    sizeBox:SetFontObject("GameFontNormalSmall")
    sizeBox:SetTextInsets(4, 4, 0, 0)
    sizeBox:SetAutoFocus(false)
    sizeBox:SetMaxLetters(3)
    sizeBox:SetNumeric(true)
    sizeBox:SetText(tostring(overrides.sizeOverride or 0))
    sizeBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local val = tonumber(self:GetText()) or 0
        if val < 0 then val = 0 end
        if val > 80 then val = 80 end
        self:SetText(tostring(val))
        if val == 0 then
            spellData:ClearSpellOverride(containerKey, spellID, "sizeOverride")
        else
            spellData:SetSpellOverride(containerKey, spellID, "sizeOverride", val)
        end
        OnOverrideChange()
    end)
    sizeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sizeBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    sizeBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end)
    PlaceWidget(sizeRow)

    local totalHeight = math_abs(sy) + 32
    overridePanel:SetHeight(totalHeight)

    -- Position at cursor location
    overridePanel:ClearAllPoints()
    overridePanel:SetWidth(270)
    overridePanel:SetClampedToScreen(true)

    local uiScale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    overridePanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        cursorX / uiScale, cursorY / uiScale)
    overridePanel:Show()

    return totalHeight + 4
end

HideOverridePanel = function(clearState)
    if overridePanel then
        overridePanel:Hide()
    end
    if clearState then
        expandedOverride = nil
    end
end

---------------------------------------------------------------------------
-- CONTAINER KEY HELPERS (needed by entry list callbacks below)
---------------------------------------------------------------------------
-- Phase G: Build the ordered list of all container keys for tabs
local function GetAllTabKeys()
    if ns.CDMContainers and ns.CDMContainers.GetContainers then
        local all = ns.CDMContainers.GetContainers()
        local keys = {}
        for _, entry in ipairs(all) do
            keys[#keys + 1] = entry.key
        end
        return keys
    end
    return CONTAINER_ORDER
end

-- Phase G: Get display name for a container key
local function GetContainerLabel(containerKey)
    if CONTAINER_LABELS[containerKey] then
        return CONTAINER_LABELS[containerKey]
    end
    local db = GetContainerDB(containerKey)
    if db and db.name then
        return db.name
    end
    return containerKey
end

-- Phase G: Is this a built-in container?
local function IsBuiltInContainer(containerKey)
    return CONTAINER_LABELS[containerKey] ~= nil
end

---------------------------------------------------------------------------
-- ENTRY LIST (Bottom Section)
---------------------------------------------------------------------------
local entryListScroll = nil
local entryListContent = nil

-- Drag state (must be before BuildEntryListSection and GetOrCreateEntryCell)
local dragState = {
    active = false,
    fromIndex = nil,
    fromCell = nil,
    fromRowNum = nil,  -- row number the dragged entry belongs to
    fromSpecKey = nil, -- source bucket for spec-specific custom bars
}

local function BuildEntryListSection(parent)
    local container = CreateBackdropFrame(parent)
    SetSimpleBackdrop(container, 0.04, 0.04, 0.06, 1, 0.15, 0.15, 0.15, 1)

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Spell List")
    title:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Search box
    searchBox = CreateSearchBox(container, 200, "Filter spells...")
    searchBox:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -4)

    -- Scroll area
    local scrollF, content = CreateScrollArea(container, 10, 10) -- sized later
    scrollF:SetPoint("TOPLEFT", 4, -28)
    scrollF:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 4)

    entryListScroll = scrollF
    entryListContent = content

    -- Catch mouse-up on scroll frame to stop drag even if cursor leaves a row
    scrollF:EnableMouse(true)
    scrollF:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and dragState.active then
            StopDrag()
        end
    end)
    container._scrollFrame = scrollF
    container._content = content

    return container
end

-- True if the entry is currently in the user's Blizzard /cdm for the
-- container family the composer is editing. Family-grouped: cooldown
-- family covers essential+utility, aura family covers buff-icon+buff-bar.
-- Non-spell entries (items/macros/slots) and unknown families return true
-- so they aren't flagged. Spells that aren't in any Blizzard /cdm category
-- at all (i.e. added via QUI's All Cooldowns / Other Auras / Active Buffs /
-- Spell ID / Items tabs) also return true — Blizzard's /cdm has no slot
-- for them, so "missing from /cdm" is meaningless for those entries.
IsEntryRegisteredInBlizzCDM = function(entry)
    if not entry then return true end
    local etype = entry.type or ResolveEntryType(entry)
    if etype ~= "spell" then return true end
    local id = tonumber(entry.id) or tonumber(entry.spellID)
    if not id then return true end
    local spellData = GetCDMSpellData()
    if not spellData then return true end
    local family = activeContainer and ResolveContainerType(activeContainer) or nil
    if type(spellData.IsSpellInCDMCategory) == "function"
       and not spellData:IsSpellInCDMCategory(id, family) then
        return true
    end
    if family == "cooldown" then
        local fn = spellData.FindCooldownChildForSpell
        if not fn then return true end
        return fn(id) ~= nil
    elseif family == "aura" or family == "auraBar" then
        local fn = spellData.FindAuraChildForSpell
        if not fn then return true end
        return fn(id) ~= nil
    end
    return true
end

local function GetOrCreateEntryCell(index)
    if entryCells[index] then return entryCells[index] end

    local cell = CreateFrame("Button", nil, entryListContent, "BackdropTemplate")
    cell:SetSize(GRID_CELL_SIZE, GRID_CELL_SIZE)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:RegisterForDrag("LeftButton")

    -- Border (dim by default)
    SetSimpleBackdrop(cell, 0, 0, 0, 0, 0.2, 0.2, 0.2, 0.5)

    -- Icon
    cell._icon = cell:CreateTexture(nil, "ARTWORK")
    cell._icon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
    cell._icon:SetPoint("CENTER")
    cell._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Highlight overlay
    cell._highlight = cell:CreateTexture(nil, "HIGHLIGHT")
    cell._highlight:SetAllPoints()
    cell._highlight:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.15)

    -- Tooltip + border highlight on hover (suppressed during drag)
    cell:SetScript("OnEnter", function(self)
        if not self._entry then return end
        if dragState.active then return end
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetFrameLevel(250)
        local name = GetEntryName(self._entry)
        GameTooltip:AddLine(name, 1, 1, 1)
        if self._isDormant then
            GameTooltip:AddLine("Not Learned (Dormant)", 0.9, 0.6, 0.2)
            GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
        else
            if type(self._entry) == "table" and self._entry._legacySpellbookSlot ~= nil then
                GameTooltip:AddLine("Legacy data — may need review", 0.95, 0.6, 0.2)
            end
            if self._isUnknownToPlayer then
                GameTooltip:AddLine("Not usable on your current class", 0.95, 0.5, 0.5)
            elseif not IsEntryRegisteredInBlizzCDM(self._entry) then
                GameTooltip:AddLine("Not added to /cdm", 0.95, 0.6, 0.2)
            end
            -- Source-spec attribution: read from explicit _sourceSpecID
            -- (set by the v32 migration on each migrated entry) or fall
            -- back to the per-spec storage key the aggregated reader
            -- attached at render time.
            local entry = self._entry
            local srcSpec = type(entry) == "table"
                and (entry._sourceSpecID or tonumber(entry._renderSpecKey))
                or nil
            if type(srcSpec) == "number" and GetSpecializationInfoByID then
                local _, specName, _, _, _, classToken = GetSpecializationInfoByID(srcSpec)
                if specName then
                    local label = classToken and ("%s %s"):format(specName, classToken) or specName
                    GameTooltip:AddLine(("Source: %s"):format(label), 0.6, 0.85, 1)
                end
            end
            if self._dragTooltipText then
                GameTooltip:AddLine(self._dragTooltipText, 0.5, 0.5, 0.5)
            end
            GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function(self)
        if dragState.active then return end
        self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        GameTooltip:Hide()
    end)

    entryCells[index] = cell
    return cell
end

local function GetOrCreateSectionHeader(index)
    if sectionHeaders[index] then return sectionHeaders[index] end

    -- Explicit bg texture instead of SetBackdrop — avoid Blizzard's
    -- SetupTextureCoordinates recursion on scroll-child descendants.
    local f = CreateFrame("Frame", nil, entryListContent)
    f:SetHeight(SECTION_HEADER_HEIGHT)
    local fBg = f:CreateTexture(nil, "BACKGROUND")
    fBg:SetAllPoints(f)
    fBg:SetColorTexture(0, 0, 0, 0)
    f._bg = fBg
    -- Compatibility shim — callers still use SetBackdropColor for highlights.
    f.SetBackdropColor = function(self, r, g, b, a)
        if self._bg then self._bg:SetColorTexture(r, g, b, a or 1) end
    end

    f._label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f._label:SetPoint("LEFT", 6, 0)
    f._label:SetJustifyH("LEFT")

    sectionHeaders[index] = f
    return f
end

---------------------------------------------------------------------------
-- DRAG AND DROP REORDERING (adapted for icon grid)
---------------------------------------------------------------------------
local dropIndicator = nil

local function GetOrCreateDropIndicator()
    if dropIndicator then return dropIndicator end
    if not entryListContent then return nil end
    local line = entryListContent:CreateTexture(nil, "OVERLAY")
    line:SetWidth(2)
    line:SetHeight(GRID_CELL_SIZE)
    line:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    line:Hide()
    dropIndicator = line
    return line
end

-- Find which entry index and row the cursor is nearest in the grid.
-- Returns targetIdx (insert-before position in ownedSpells), targetRow (row number or nil),
--         bestCell, bestSide ("left"/"right"), isHeaderDrop (boolean).
local function GetDropTarget()
    if not entryListContent then return nil, nil end
    local scale = entryListContent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    -- Check section headers first — if cursor is over a row header (especially empty rows),
    -- treat it as a drop target for that row.
    for _, hdr in ipairs(sectionHeaders) do
        if hdr:IsShown() and hdr._rowNum and hdr:IsMouseOver() then
            -- Drop into this row — use a sentinel index; StopDrag handles row-only drops
            return nil, hdr._rowNum, hdr, nil, true
        end
    end

    local bestIdx = nil
    local bestRow = nil
    local bestDist = math.huge
    local bestCell = nil
    local bestSide = nil  -- "left" or "right"
    for i, cell in ipairs(entryCells) do
        if cell:IsShown() and cell._entryIndex then
            local cl = cell:GetLeft()
            local ct = cell:GetTop()
            if cl and ct then
                local cx = cl + GRID_CELL_SIZE / 2
                local cy = ct - GRID_CELL_SIZE / 2
                local dist = (cursorX - cx) * (cursorX - cx) + (cursorY - cy) * (cursorY - cy)
                if dist < bestDist then
                    bestDist = dist
                    bestCell = cell
                    bestRow = cell._rowNum
                    if cursorX < cx then
                        bestIdx = cell._entryIndex
                        bestSide = "left"
                    else
                        bestIdx = cell._entryIndex + 1
                        bestSide = "right"
                    end
                end
            end
        end
    end
    return bestIdx, bestRow, bestCell, bestSide, false
end

local function UpdateDropIndicator()
    local indicator = GetOrCreateDropIndicator()
    if not indicator or not dragState.active then
        if indicator then indicator:Hide() end
        return
    end

    local targetIdx, targetRow, bestCell, bestSide, isHeaderDrop = GetDropTarget()

    -- Always clear previously highlighted header first
    if dragState._highlightedHeader and dragState._highlightedHeader ~= bestCell then
        local hdr = dragState._highlightedHeader
        if hdr:GetHeight() <= 18 then
            hdr:SetBackdropColor(0.06, 0.06, 0.08, 0.3)
        else
            hdr:SetBackdropColor(ACCENT_R * 0.1, ACCENT_G * 0.1, ACCENT_B * 0.1, 0.8)
        end
        dragState._highlightedHeader = nil
    end

    if isHeaderDrop and bestCell then
        -- Hovering over a row header (empty row) — show a horizontal bar
        indicator:ClearAllPoints()
        indicator:SetHeight(2)
        indicator:SetPoint("TOPLEFT", bestCell, "BOTTOMLEFT", 0, -1)
        indicator:SetPoint("TOPRIGHT", bestCell, "BOTTOMRIGHT", 0, -1)
        indicator:Show()
        -- Highlight the header
        bestCell:SetBackdropColor(ACCENT_R * 0.2, ACCENT_G * 0.2, ACCENT_B * 0.2, 0.9)
        dragState._highlightedHeader = bestCell
        return
    end

    -- Not over a header — clear if still set
    if dragState._highlightedHeader then
        local hdr = dragState._highlightedHeader
        if hdr:GetHeight() <= 18 then
            hdr:SetBackdropColor(0.06, 0.06, 0.08, 0.3)
        else
            hdr:SetBackdropColor(ACCENT_R * 0.1, ACCENT_G * 0.1, ACCENT_B * 0.1, 0.8)
        end
        dragState._highlightedHeader = nil
    end

    if not targetIdx or not bestCell then
        indicator:Hide()
        return
    end

    if bestCell and dragState.fromSpecKey ~= bestCell._entrySpecKey then
        indicator:Hide()
        return
    end

    -- Anchor centered on the cell edge so the indicator is never clipped
    -- outside the scroll content area (especially at the first cell in a row)
    indicator:ClearAllPoints()
    indicator:SetWidth(2)
    indicator:SetHeight(GRID_CELL_SIZE)
    if bestSide == "right" then
        indicator:SetPoint("CENTER", bestCell, "RIGHT", 0, 0)
    else
        indicator:SetPoint("CENTER", bestCell, "LEFT", 0, 0)
    end
    indicator:Show()
end

local StopDrag  -- forward declaration

local function StartDrag(cell, entryIndex, rowNum)
    if InCombatLockdown() then return end
    dragState.active = true
    dragState.fromIndex = entryIndex
    dragState.fromCell = cell
    dragState.fromRowNum = rowNum or nil
    dragState.fromSpecKey = cell and cell._entrySpecKey or nil
    -- Highlight the dragged cell
    cell:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    -- Hide highlight textures on all other cells so hover glow doesn't
    -- compete with the drop indicator during drag
    for _, c in ipairs(entryCells) do
        if c ~= cell and c._highlight then
            c._highlight:Hide()
        end
    end

    if entryListContent then
        entryListContent:SetScript("OnUpdate", function()
            if not dragState.active then return end
            if not IsMouseButtonDown("LeftButton") then
                StopDrag()
                return
            end
            UpdateDropIndicator()
        end)
    end
end

StopDrag = function()
    if not dragState.active then return end
    local fromIdx = dragState.fromIndex
    local cell = dragState.fromCell
    local fromRowNum = dragState.fromRowNum

    -- Restore cell border
    if cell then
        cell:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
    end

    -- Restore highlight textures on all cells
    for _, c in ipairs(entryCells) do
        if c._highlight then
            c._highlight:Show()
        end
    end

    -- Dismiss any lingering tooltip
    GameTooltip:Hide()

    if dropIndicator then dropIndicator:Hide() end

    if entryListContent then
        entryListContent:SetScript("OnUpdate", nil)
    end

    local targetIdx, targetRow, targetCell = GetDropTarget()
    local fromSpecKey = dragState.fromSpecKey
    local targetSpecKey = targetCell and targetCell._entrySpecKey or nil

    -- Clean up all header highlights (reset every header to its default color)
    for _, hdr in ipairs(sectionHeaders) do
        if hdr:IsShown() then
            if hdr:GetHeight() <= 18 then
                hdr:SetBackdropColor(0.06, 0.06, 0.08, 0.3)
            else
                hdr:SetBackdropColor(ACCENT_R * 0.1, ACCENT_G * 0.1, ACCENT_B * 0.1, 0.8)
            end
        end
    end
    dragState._highlightedHeader = nil

    dragState.active = false
    dragState.fromIndex = nil
    dragState.fromCell = nil
    dragState.fromRowNum = nil
    dragState.fromSpecKey = nil

    if not fromIdx then return end
    -- Need either a cell target or a row header target
    if not targetIdx and not targetRow then return end

    local spellData = GetCDMSpellData()
    if not spellData or not activeContainer then return end

    if fromSpecKey ~= targetSpecKey then
        UIErrorsFrame:AddMessage("Can only reorder within the same source spec", 1.0, 0.3, 0.3, 1.0, 3)
        UIErrorsFrame:SetFrameStrata("TOOLTIP")
        return
    end

    local isCooldown = (ResolveContainerType(activeContainer) == "cooldown")
    local crossRow = isCooldown and targetRow and fromRowNum and targetRow ~= fromRowNum

    if crossRow then
        -- Cross-row drag: change entry's row and reorder within the target row
        local db = GetContainerDB(activeContainer)
        if not db then return end

        -- Capacity check: is the target row full?
        local rd = db["row" .. targetRow]
        if rd and rd.iconCount then
            local firstActiveRow = nil
            for r = 1, 3 do
                local rrd = db["row" .. r]
                if rrd and rrd.iconCount and rrd.iconCount > 0 then
                    if not firstActiveRow then firstActiveRow = r end
                end
            end
            local count = 0
            local spells = db.ownedSpells or {}
            for _, e in ipairs(spells) do
                if e and (e.row or firstActiveRow) == targetRow then
                    count = count + 1
                end
            end
            if count >= rd.iconCount then
                UIErrorsFrame:AddMessage("Row " .. targetRow .. " is full (" .. rd.iconCount .. "/" .. rd.iconCount .. ")", 1.0, 0.3, 0.3, 1.0, 3)
                UIErrorsFrame:SetFrameStrata("TOOLTIP")
                return
            end
        end

        -- Set the row first
        spellData:SetEntryRow(activeContainer, fromIdx, targetRow)
        -- If we have a specific position (cell drop, not header drop), reorder
        if targetIdx then
            local adjustedTarget = targetIdx
            if targetIdx > fromIdx then
                adjustedTarget = targetIdx - 1
            end
            if adjustedTarget ~= fromIdx then
                spellData:ReorderEntry(activeContainer, fromIdx, adjustedTarget, fromSpecKey)
            end
        end
        C_Timer.After(0.02, function()
            RefreshCDM()
            RefreshEntryList()
            RefreshPreview()
        end)
    else
        -- Same-row or non-row reorder
        if not targetIdx or targetIdx == fromIdx or targetIdx == fromIdx + 1 then
            return
        end

        local adjustedTarget = targetIdx
        if targetIdx > fromIdx then
            adjustedTarget = targetIdx - 1
        end

        spellData:ReorderEntry(activeContainer, fromIdx, adjustedTarget, fromSpecKey)
        C_Timer.After(0.02, function()
            RefreshCDM()
            RefreshEntryList()
            RefreshPreview()
        end)
    end
end

---------------------------------------------------------------------------
-- ENTRY CONTEXT MENU (right-click on grid cell)
---------------------------------------------------------------------------
local function ShowEntryContextMenu(anchorCell, entry, entryIndex, isDormant)
    if _G.QUI_EntryContextMenu then
        _G.QUI_EntryContextMenu:Hide()
    end

    local spellData = GetCDMSpellData()
    if not spellData then return end

    local isCooldown = (ResolveContainerType(activeContainer) == "cooldown")
    local db = GetContainerDB(activeContainer)
    if not db then return end

    -- Build menu items
    local items = {}
    if isDormant then
        local sid = entry.id or entry
        local isKnown = spellData.IsSpellKnown and spellData:IsSpellKnown(sid)
        if isKnown then
            items[#items + 1] = { label = "Restore", color = { ACCENT_R, ACCENT_G, ACCENT_B }, action = function()
                if InCombatLockdown() then return end
                spellData:RestoreDormantEntry(activeContainer, sid)
                C_Timer.After(0.02, function()
                    RefreshEntryList()
                    RefreshAddList()
                    RefreshPreview()
                end)
            end }
        end
        items[#items + 1] = { label = "Remove", color = { 0.9, 0.3, 0.3 }, action = function()
            if InCombatLockdown() then return end
            spellData:RemoveDormantEntry(activeContainer, sid)
            C_Timer.After(0.02, function()
                RefreshEntryList()
                RefreshAddList()
                RefreshPreview()
            end)
        end }
    else
        -- Settings
        items[#items + 1] = { label = "Settings", color = { ACCENT_R, ACCENT_G, ACCENT_B }, action = function()
            if expandedOverride == entry.id then
                HideOverridePanel(true)
            else
                expandedOverride = entry.id
                if not overridePanel then
                    BuildOverridePanel(entryListContent)
                end
                ShowOverridePanel(anchorCell, activeContainer, entry, entryIndex)
            end
        end }

        -- Row move (cooldown containers with 2+ rows) — show one item per other row
        if isCooldown then
            local activeRowNums = {}
            local rowCounts = {}
            local rowMax = {}
            local entries_all = db.ownedSpells or {}
            for r = 1, 3 do
                local rd = db["row" .. r]
                if rd and rd.iconCount and rd.iconCount > 0 then
                    activeRowNums[#activeRowNums + 1] = r
                    rowMax[r] = rd.iconCount
                    rowCounts[r] = 0
                end
            end
            -- Count entries per row
            for _, e in ipairs(entries_all) do
                if e then
                    local r = e.row or (activeRowNums[1] or 1)
                    if rowCounts[r] then
                        rowCounts[r] = rowCounts[r] + 1
                    end
                end
            end
            if #activeRowNums > 1 then
                local curRow = entry.row or activeRowNums[1]
                for _, rn in ipairs(activeRowNums) do
                    if rn ~= curRow then
                        local isFull = rowMax[rn] and rowCounts[rn] and rowCounts[rn] >= rowMax[rn]
                        local lbl = "Move to Row " .. rn
                        if isFull then
                            lbl = lbl .. "  (Full)"
                        end
                        items[#items + 1] = {
                            label = lbl,
                            color = isFull and { 0.4, 0.4, 0.4 } or { ACCENT_R, ACCENT_G, ACCENT_B },
                            action = isFull and function()
                                UIErrorsFrame:AddMessage("Row " .. rn .. " is full (" .. rowMax[rn] .. "/" .. rowMax[rn] .. ")", 1.0, 0.3, 0.3, 1.0, 3)
                                UIErrorsFrame:SetFrameStrata("TOOLTIP")
                            end or function()
                                if InCombatLockdown() then return end
                                spellData:SetEntryRow(activeContainer, entryIndex, rn)
                                C_Timer.After(0.02, function()
                                    RefreshCDM()
                                    RefreshEntryList()
                                    RefreshPreview()
                                end)
                            end,
                        }
                    end
                end
            end
        end

        -- Move to sibling container — only within the same type family:
        -- cooldown↔cooldown (essential/utility), aura↔auraBar (buff icons/buff bars)
        local containerType = ResolveContainerType(activeContainer)
        local SIBLING_TYPES = {
            cooldown = { cooldown = true },
            aura     = { aura = true, auraBar = true },
            auraBar  = { aura = true, auraBar = true },
        }
        local siblings = SIBLING_TYPES[containerType] or {}
        local allTabKeys = GetAllTabKeys()
        for _, key in ipairs(allTabKeys) do
            if key ~= activeContainer and siblings[ResolveContainerType(key)] then
                items[#items + 1] = { label = "Move to " .. GetContainerLabel(key), color = { ACCENT_R, ACCENT_G, ACCENT_B }, action = function()
                    if InCombatLockdown() then return end
                    spellData:MoveEntryBetweenContainers(activeContainer, key, entryIndex)
                    C_Timer.After(0.02, function()
                        RefreshCDM()
                        RefreshEntryList()
                        RefreshAddList()
                        RefreshPreview()
                    end)
                end }
            end
        end

        -- Remove
        items[#items + 1] = { label = "Remove", color = { 0.9, 0.3, 0.3 }, action = function()
            if InCombatLockdown() then return end
            local removeIndex = entryIndex
            local removeSpecKey = nil
            if db.containerType == "customBar" and db.specSpecific and type(entry) == "table" then
                removeIndex = entry._renderSpecIndex or entryIndex
                removeSpecKey = entry._renderSpecKey
            end
            spellData:RemoveEntry(activeContainer, removeIndex, removeSpecKey)
            C_Timer.After(0.02, function()
                RefreshCDM()
                RefreshEntryList()
                RefreshAddList()
                RefreshPreview()
            end)
        end }
    end

    local itemHeight = 24
    local menuWidth = 180
    local menuHeight = #items * itemHeight + 4

    local menu = CreateFrame("Frame", "QUI_EntryContextMenu", UIParent, "BackdropTemplate")
    menu:SetSize(menuWidth, menuHeight)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(300)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    menu:EnableMouse(true)
    menu:SetPoint("TOPLEFT", anchorCell, "BOTTOMLEFT", 0, -2)
    menu:SetClampedToScreen(true)

    for i, item in ipairs(items) do
        local btn = CreateFrame("Button", nil, menu)
        btn:SetSize(menuWidth - 4, itemHeight)
        btn:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * itemHeight))
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 8, 0)
        label:SetText(item.label)
        local c = item.color or { 0.8, 0.8, 0.8 }
        label:SetTextColor(c[1], c[2], c[3], 1)
        btn:SetScript("OnClick", function()
            menu:Hide()
            if item.action then item.action() end
        end)
        btn:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function()
            label:SetTextColor(c[1], c[2], c[3], 1)
        end)
    end

    menu:SetScript("OnUpdate", function(self)
        if not MouseIsOver(self) and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
            self:Hide()
        end
    end)

    menu:Show()
end

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- REFRESH ENTRY LIST (icon grid layout)
---------------------------------------------------------------------------
RefreshEntryList = function()
    if not entryListContent or not activeContainer then return end

    HideOverridePanel()
    if _G.QUI_EntryContextMenu then _G.QUI_EntryContextMenu:Hide() end

    local db = GetContainerDB(activeContainer)
    if not db then return end

    -- Self-heal dormancy before reading entries. The data layer's
    -- SPELLS_CHANGED debounce (0.3s) can lag behind a hero-talent or
    -- spec swap that happened just before the user opened the composer,
    -- leaving unlearned spells (e.g. Reaper's Mark after swapping
    -- Deathbringer → Sanlay'n) sitting in ownedSpells and rendering
    -- as "Not usable on your current class" instead of moving to the
    -- Dormant section. CheckDormantSpells is idempotent and bails on
    -- containers without an ownedSpells list (customBar), so calling
    -- it per-render is safe and free for unaffected containers.
    do
        local sd = ns.CDMSpellData
        if sd and type(sd.CheckDormantSpells) == "function"
           and not InCombatLockdown() then
            sd:CheckDormantSpells(activeContainer)
        end
    end

    -- customBar containers (migrated from customTrackers) store their
    -- entry list under `entries` (mixed spell/item/slot/macro types),
    -- not the CDM-native `ownedSpells`. They also have no concept of
    -- "dormant" since all entries are user-curated.
    local isCustomBar = (db.containerType == "customBar")

    local entries
    -- Aggregated view for spec-specific customBar containers: pull entries
    -- from every spec's list in db.global.ncdm.specTrackerSpells[key] so
    -- the user can see (and right-click → Remove) entries from any spec
    -- regardless of which spec they're currently on. Each entry carries
    -- render-time source metadata that the right-click menu and tooltip read;
    -- the entry itself stays in its per-spec list (so removes hit the correct list).
    if isCustomBar and db.specSpecific then
        entries = {}
        local globalDB = ns.Addon and ns.Addon.db and ns.Addon.db.global
        local byContainer = globalDB and globalDB.ncdm
            and globalDB.ncdm.specTrackerSpells
            and globalDB.ncdm.specTrackerSpells[activeContainer]
        if type(byContainer) == "table" then
            local specKeys = {}
            for k in pairs(byContainer) do specKeys[#specKeys + 1] = k end
            table.sort(specKeys)
            for _, specKey in ipairs(specKeys) do
                local list = byContainer[specKey]
                if type(list) == "table" then
                    for entryIndex, entry in ipairs(list) do
                        if type(entry) == "table" then
                            entry._renderSpecKey = specKey
                            entry._renderSpecIndex = entryIndex
                            entries[#entries + 1] = entry
                        end
                    end
                end
            end
        end
        -- Also surface any unmigrated entries still sitting in db.entries
        -- (defensive — should be empty after v32 migration).
        if type(db.entries) == "table" then
            for entryIndex, entry in ipairs(db.entries) do
                if type(entry) == "table" then
                    entry._renderSpecKey = false
                    entry._renderSpecIndex = entryIndex
                    entries[#entries + 1] = entry
                end
            end
        end
    elseif isCustomBar then
        entries = db.entries
    else
        entries = db.ownedSpells
    end
    if type(entries) ~= "table" then entries = {} end

    local dormant = db.dormantSpells
    if type(dormant) ~= "table" or isCustomBar then dormant = {} end

    local filterText = searchBox and searchBox:GetText() or ""
    local lowerFilter = string_lower(filterText)
    local hasFilter = (filterText ~= "")

    local spellData = GetCDMSpellData()

    -- Hide all existing cells and headers
    for _, cell in ipairs(entryCells) do
        cell:Hide()
        cell:ClearAllPoints()
    end
    for _, hdr in ipairs(sectionHeaders) do
        hdr:Hide()
        hdr:ClearAllPoints()
        hdr._rowNum = nil
    end

    local contentWidth = entryListContent:GetWidth()
    if contentWidth < GRID_CELL_STRIDE then
        C_Timer.After(0.01, RefreshEntryList)
        return
    end
    local cols = math_floor(contentWidth / GRID_CELL_STRIDE)
    if cols < 1 then cols = 1 end

    local sy = 0
    local cellIndex = 0
    local headerIndex = 0
    local colPos = 0

    local isCooldown = (ResolveContainerType(activeContainer) == "cooldown")

    -- Grid placement helpers
    local function FinishRow()
        if colPos > 0 then
            colPos = 0
            sy = sy - GRID_CELL_STRIDE
        end
    end

    local function PlaceCell(cell)
        cell:ClearAllPoints()
        cell:SetSize(GRID_CELL_SIZE, GRID_CELL_SIZE)
        cell:SetPoint("TOPLEFT", entryListContent, "TOPLEFT",
            colPos * GRID_CELL_STRIDE, sy)
        cell:Show()
        colPos = colPos + 1
        if colPos >= cols then
            colPos = 0
            sy = sy - GRID_CELL_STRIDE
        end
    end

    local function RenderSectionHeader(label, isEmpty, rowNum)
        FinishRow()
        headerIndex = headerIndex + 1
        local hdr = GetOrCreateSectionHeader(headerIndex)
        hdr:SetParent(entryListContent)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", entryListContent, "TOPLEFT", 0, sy)
        hdr:SetPoint("RIGHT", entryListContent, "RIGHT", 0, 0)
        hdr:SetBackdropColor(ACCENT_R * 0.1, ACCENT_G * 0.1, ACCENT_B * 0.1, 0.8)
        hdr._label:SetText(label)
        hdr._rowNum = rowNum or nil
        if isEmpty then
            hdr._label:SetTextColor(0.4, 0.4, 0.4, 1)
        else
            hdr._label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end
        hdr:Show()
        sy = sy - SECTION_HEADER_HEIGHT
        colPos = 0
    end

    local function RenderEntryCell(entry, idx, rowNum)
        local entryName = GetEntryName(entry)
        if hasFilter and not string_find(string_lower(entryName), lowerFilter, 1, true) then
            return
        end

        cellIndex = cellIndex + 1
        local cell = GetOrCreateEntryCell(cellIndex)
        cell:SetParent(entryListContent)
        cell._entry = entry
        cell._entryIndex = (isCustomBar and db.specSpecific and type(entry) == "table" and entry._renderSpecIndex) or idx
        cell._entrySpecKey = (isCustomBar and db.specSpecific and type(entry) == "table") and entry._renderSpecKey or nil
        cell._rowNum = rowNum or nil
        cell._isDormant = false
        cell._isUnknownToPlayer = not IsEntryUsableOnCurrentPlayer(entry)
        if isCooldown then
            cell._dragTooltipText = "Drag to reorder or move between rows"
        elseif isCustomBar and db.specSpecific and cell._entrySpecKey then
            cell._dragTooltipText = "Drag to reorder within this source spec"
        else
            cell._dragTooltipText = "Drag to reorder"
        end
        -- Mirrors the tooltip warning: red-tint icons that are usable on
        -- this class but currently absent from Blizzard's CDM viewer.
        -- Skip when unknown-to-player (already desaturated for that state).
        cell._isMissingFromCDM = (not cell._isUnknownToPlayer)
            and not IsEntryRegisteredInBlizzCDM(entry)

        cell._icon:SetTexture(GetEntryIcon(entry))
        cell._icon:SetDesaturated(cell._isUnknownToPlayer)
        if cell._isMissingFromCDM then
            cell._icon:SetVertexColor(1, 0.4, 0.4)
        else
            cell._icon:SetVertexColor(1, 1, 1)
        end
        cell._icon:Show()
        cell:SetAlpha(cell._isUnknownToPlayer and 0.6 or 1)

        -- Wire drag
        cell:SetScript("OnDragStart", function()
            StartDrag(cell, cell._entryIndex, rowNum)
        end)
        cell:SetScript("OnDragStop", function()
            StopDrag()
        end)

        -- OnClick handles both drag-stop (left) and context menu (right)
        cell:SetScript("OnClick", function(self, button)
            if button == "LeftButton" and dragState.active then
                StopDrag()
            elseif button == "RightButton" and self._entry then
                ShowEntryContextMenu(self, self._entry, self._entryIndex, false)
            end
        end)

        PlaceCell(cell)
    end

    local function RenderDormantCell(spellID)
        local entryName = ""
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            if ok and info then entryName = info.name or "" end
        end
        if entryName == "" then entryName = "Spell #" .. tostring(spellID) end

        if hasFilter and not string_find(string_lower(entryName), lowerFilter, 1, true) then
            return
        end

        cellIndex = cellIndex + 1
        local cell = GetOrCreateEntryCell(cellIndex)
        cell:SetParent(entryListContent)

        -- Dormant entries store as { id = spellID, type = "spell" } for context menu
        cell._entry = { id = spellID, type = "spell" }
        cell._entryIndex = nil
        cell._entrySpecKey = nil
        cell._rowNum = nil
        cell._isDormant = true
        cell._dragTooltipText = nil

        local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            if ok and info and info.iconID then icon = info.iconID end
        end
        cell._icon:SetTexture(icon)
        cell._icon:SetDesaturated(true)
        cell._icon:SetVertexColor(1, 1, 1)
        cell._icon:Show()
        cell:SetAlpha(0.6)
        cell._isMissingFromCDM = false

        -- No drag for dormant
        cell:SetScript("OnDragStart", nil)
        cell:SetScript("OnDragStop", nil)

        -- Right-click: restore
        cell:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                ShowEntryContextMenu(self, self._entry, nil, true)
            end
        end)

        PlaceCell(cell)
    end

    -- Build row grouping for cooldown containers
    local activeRowNums = {}
    if isCooldown then
        for r = 1, 3 do
            local rd = db["row" .. r]
            if rd and rd.iconCount and rd.iconCount > 0 then
                activeRowNums[#activeRowNums + 1] = r
            end
        end
    end

    local rowEntries = {}
    if isCooldown and #activeRowNums > 0 then
        for i, entry in ipairs(entries) do
            if entry then
                local r = entry.row or activeRowNums[1]
                if not rowEntries[r] then rowEntries[r] = {} end
                rowEntries[r][#rowEntries[r] + 1] = { entry = entry, idx = i }
            end
        end
    end

    -- Render
    if isCooldown and #activeRowNums > 0 then
        for _, rowNum in ipairs(activeRowNums) do
            local rowItems = rowEntries[rowNum]
            local count = rowItems and #rowItems or 0
            local rd = db["row" .. rowNum]
            local maxCount = rd and rd.iconCount or 0
            local isFull = count >= maxCount
            local headerLabel = "Row " .. rowNum .. "  (" .. count .. "/" .. maxCount .. ")"
            if isFull and count > 0 then
                headerLabel = headerLabel .. "  |cffff4d4dFull|r"
            end
            RenderSectionHeader(headerLabel, count == 0, rowNum)
            if count == 0 then
                -- Empty hint (as a small header) — also tagged for drop targeting
                headerIndex = headerIndex + 1
                local hdr = GetOrCreateSectionHeader(headerIndex)
                hdr:SetParent(entryListContent)
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", entryListContent, "TOPLEFT", 0, sy)
                hdr:SetPoint("RIGHT", entryListContent, "RIGHT", 0, 0)
                hdr:SetHeight(18)
                hdr:SetBackdropColor(0.06, 0.06, 0.08, 0.3)
                hdr._label:SetText("  (empty — drag or right-click icons to move between rows)")
                hdr._label:SetTextColor(0.35, 0.35, 0.35, 1)
                hdr._rowNum = rowNum
                hdr:Show()
                sy = sy - 18
            else
                for _, item in ipairs(rowItems) do
                    RenderEntryCell(item.entry, item.idx, rowNum)
                end
                FinishRow()
            end
        end
    else
        -- customBar entries render at the bar's anchor corner from index 1
        -- outward. For LEFT/UP growth the first entry ends up at the far
        -- right / bottom in-game — walk the list in reverse here so the
        -- grid matches that visual while RenderEntryCell still records
        -- each cell's true entryIndex for drag/remove.
        local reverse = isCustomBar and (db.growDirection == "LEFT" or db.growDirection == "UP")
        if reverse then
            for i = #entries, 1, -1 do
                local entry = entries[i]
                if entry then RenderEntryCell(entry, i) end
            end
        else
            for i, entry in ipairs(entries) do
                if entry then RenderEntryCell(entry, i) end
            end
        end
        FinishRow()
    end

    -- Dormant entries
    local hasDormant = false
    for spellID, _ in pairs(dormant) do
        if type(spellID) == "number" then
            if not hasDormant then
                hasDormant = true
                RenderSectionHeader("Dormant", false)
            end
            RenderDormantCell(spellID)
        end
    end
    if hasDormant then FinishRow() end

    entryListContent:SetHeight(math_max(8, math_abs(sy) + 8))
    if entryListContent._updateScroll then
        entryListContent._updateScroll()
    end
end

-- Refresh the entry grid and preview when /cdm composition changes.
-- Blizzard's standalone /cdm UI does NOT fire EDIT_MODE_LAYOUTS_UPDATED
-- (that's only for the broader edit-mode editor); it routes user toggles
-- through CooldownViewerSettingsDataProvider, which fires the
-- "CooldownViewerSettings.OnDataChanged" EventRegistry callback. The
-- Blizzard CooldownViewer itself listens to this same callback for its
-- own relayout, so by the time our callback runs the viewer's children
-- are already current. Pending flag coalesces bursts of events.
local composerCDMRefreshPending = false
local function ScheduleComposerCDMRefresh()
    if composerCDMRefreshPending then return end
    composerCDMRefreshPending = true
    C_Timer.After(0, function()
        composerCDMRefreshPending = false
        if composerFrame and composerFrame:IsShown() then
            RefreshEntryList()
            if RefreshPreview then RefreshPreview() end
        end
    end)
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback(
        "CooldownViewerSettings.OnDataChanged",
        ScheduleComposerCDMRefresh,
        "QUI_Composer")
end

-- Server-side cooldown table hotfixes still come through a real event.
local composerCDMEventFrame = CreateFrame("Frame")
composerCDMEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
composerCDMEventFrame:SetScript("OnEvent", ScheduleComposerCDMRefresh)

---------------------------------------------------------------------------
-- ADD SECTION (Below Entry List)
---------------------------------------------------------------------------
local addPanel = nil
local addListScroll = nil
local addListContent = nil
local addTabButtons = {}

local function BuildAddSection(parent)
    local container = CreateBackdropFrame(parent)
    SetSimpleBackdrop(container, 0.04, 0.04, 0.06, 1, 0.15, 0.15, 0.15, 1)

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Add Entries")
    title:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, container)
    tabBar:SetHeight(TAB_HEIGHT)
    tabBar:SetPoint("TOPLEFT", 4, -22)
    tabBar:SetPoint("RIGHT", container, "RIGHT", -4, 0)
    container._tabBar = tabBar

    -- Search box for add list
    addSearchBox = CreateSearchBox(container, 180, "Search to add...")
    addSearchBox:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -22)

    -- Scroll area
    local scrollF, content = CreateScrollArea(container, 10, 10)
    scrollF:SetPoint("TOPLEFT", 4, -52)
    scrollF:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 4)

    addListScroll = scrollF
    addListContent = content
    container._scrollFrame = scrollF
    container._content = content

    addPanel = container

    -- Auto-refresh the add list when the player's auras change AND the
    -- user is looking at the Active Buffs/Debuffs tab. Cheap guard so the
    -- event has zero cost on other tabs.
    container:RegisterUnitEvent("UNIT_AURA", "player")
    container:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_AURA" and unit == "player"
           and (activeAddTab == "active_buffs" or activeAddTab == "active_debuffs")
           and self:IsVisible() then
            RefreshAddList()
        end
    end)

    return container
end

local function GetOrCreateAddCell(index)
    if addCells[index] then return addCells[index] end

    local cell = CreateFrame("Button", nil, addListContent, "BackdropTemplate")
    cell:SetSize(GRID_CELL_SIZE, GRID_CELL_SIZE)
    cell:RegisterForClicks("RightButtonUp")

    SetSimpleBackdrop(cell, 0, 0, 0, 0, 0.2, 0.2, 0.2, 0.5)

    cell._icon = cell:CreateTexture(nil, "ARTWORK")
    cell._icon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
    cell._icon:SetPoint("CENTER")
    cell._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cell._highlight = cell:CreateTexture(nil, "HIGHLIGHT")
    cell._highlight:SetAllPoints()
    cell._highlight:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.15)

    cell:SetScript("OnEnter", function(self)
        if not self._sourceEntry then return end
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetFrameLevel(250)
        local name = self._sourceEntry.name or ""
        GameTooltip:AddLine(name, 1, 1, 1)
        local sid = self._sourceEntry.spellID or self._sourceEntry._entryID or ""
        if sid ~= "" then
            GameTooltip:AddLine("ID: " .. tostring(sid), 0.5, 0.5, 0.5)
        end
        if self._isOwned then
            GameTooltip:AddLine("Already added", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine("Right-click to add", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        GameTooltip:Hide()
    end)

    addCells[index] = cell
    return cell
end

RefreshAddList = function()
    if not addListContent or not activeContainer then return end

    local spellData = GetCDMSpellData()
    if not spellData then return end

    -- Hide all existing add cells
    for _, cell in ipairs(addCells) do
        cell:Hide()
        cell:ClearAllPoints()
    end

    local filterText = addSearchBox and addSearchBox:GetText() or ""
    local lowerFilter = string_lower(filterText)
    local hasFilter = (filterText ~= "")

    local sourceEntries = {}
    local containerType = ResolveContainerType(activeContainer) or "cooldown"

    -- Build owned set for duplicate detection within the active container only.
    -- A spell can appear in multiple containers (e.g. buff icon + buff bar).
    -- customBar containers keep entries under `entries`, everything else
    -- under `ownedSpells`.
    local ownedSet = {}
    local activeDB = GetContainerDB(activeContainer)
    local isCustomBar = (activeDB and activeDB.containerType == "customBar")
    local ownedEntries = activeDB and (isCustomBar and activeDB.entries or activeDB.ownedSpells)
    if type(ownedEntries) == "table" then
        for _, entry in ipairs(ownedEntries) do
            if type(entry) == "table" and entry.id then
                ownedSet[(entry.type or "spell") .. ":" .. entry.id] = true
            elseif type(entry) == "number" then
                ownedSet["spell:" .. entry] = true
            end
        end
    end

    if activeAddTab == "cdm_spells" or not activeAddTab then
        sourceEntries = spellData:GetAvailableSpells(activeContainer) or {}

    elseif activeAddTab == "all_cooldowns" then
        sourceEntries = spellData:GetAllLearnedCooldowns() or {}

    elseif activeAddTab == "other_auras" then
        sourceEntries = spellData:GetPassiveAuras() or {}

    elseif activeAddTab == "items" then
        local items = spellData:GetUsableItems() or {}
        for _, item in ipairs(items) do
            sourceEntries[#sourceEntries + 1] = {
                spellID = item.id or item.itemID,
                name = item.name or "",
                icon = item.icon or 0,
                _entryType = item.type or "item",
                _entryID = item.id or item.itemID,
                _slotID = item.slotID,
            }
        end

        -- Always append trinket slots 13/14 (equipped trinkets — useful to
        -- track by slot so switching trinkets doesn't break the bar).
        local function hasSlotEntry(slotID)
            for _, e in ipairs(sourceEntries) do
                if e._entryType == "slot" and (e._slotID == slotID or e._entryID == slotID) then
                    return true
                end
            end
            return false
        end
        for _, slotID in ipairs({13, 14}) do
            if not hasSlotEntry(slotID) then
                local itemID = GetInventoryItemID("player", slotID)
                local name = slotID == 13 and "Top Trinket (Slot 13)" or "Bottom Trinket (Slot 14)"
                local icon = 0
                if itemID and C_Item then
                    if C_Item.GetItemNameByID then
                        local ok, n = pcall(C_Item.GetItemNameByID, itemID)
                        if ok and n then name = n .. "  (" .. (slotID == 13 and "Top Slot" or "Bottom Slot") .. ")" end
                    end
                    if C_Item.GetItemIconByID then
                        local ok, i = pcall(C_Item.GetItemIconByID, itemID)
                        if ok and i then icon = i end
                    end
                end
                sourceEntries[#sourceEntries + 1] = {
                    spellID = slotID,
                    name = name,
                    icon = icon,
                    _entryType = "slot",
                    _entryID = slotID,
                    _slotID = slotID,
                }
            end
        end

        -- If the filter is numeric AND nothing in sourceEntries matches,
        -- treat it as an item ID lookup so the user can add items they
        -- don't currently own.
        if hasFilter then
            local asNum = tonumber(filterText)
            if asNum then
                local alreadyPresent = false
                for _, e in ipairs(sourceEntries) do
                    if e._entryID == asNum then alreadyPresent = true break end
                end
                if not alreadyPresent and C_Item and C_Item.GetItemNameByID then
                    local okN, resolvedName = pcall(C_Item.GetItemNameByID, asNum)
                    if okN and resolvedName then
                        local icon = 0
                        if C_Item.GetItemIconByID then
                            local okI, i = pcall(C_Item.GetItemIconByID, asNum)
                            if okI and i then icon = i end
                        end
                        sourceEntries[#sourceEntries + 1] = {
                            spellID = asNum,
                            name = resolvedName,
                            icon = icon,
                            _entryType = "item",
                            _entryID = asNum,
                        }
                    end
                end
            end
        end

    elseif activeAddTab == "active_buffs" then
        local auras = spellData:GetActiveAuras("HELPFUL") or {}
        for _, aura in ipairs(auras) do
            sourceEntries[#sourceEntries + 1] = {
                spellID = aura.spellID,
                name = aura.name or "",
                icon = aura.icon or 0,
            }
        end

    elseif activeAddTab == "active_debuffs" then
        local auras = spellData:GetActiveAuras("HARMFUL") or {}
        for _, aura in ipairs(auras) do
            sourceEntries[#sourceEntries + 1] = {
                spellID = aura.spellID,
                name = aura.name or "",
                icon = aura.icon or 0,
            }
        end

    elseif activeAddTab == "by_spell_id" then
        if hasFilter then
            local asNum = tonumber(filterText)
            if asNum then
                local name, icon = "", 0
                if C_Spell and C_Spell.GetSpellInfo then
                    local ok, info = pcall(C_Spell.GetSpellInfo, asNum)
                    if ok and info then
                        name = info.name or ""
                        icon = info.iconID or 0
                    end
                end
                sourceEntries[1] = {
                    spellID = asNum,
                    name = name ~= "" and name or ("Spell #" .. tostring(asNum)),
                    icon = icon,
                }
            end
        end

    end

    -- Grid layout
    local contentWidth = addListContent:GetWidth()
    if contentWidth < GRID_CELL_STRIDE then
        C_Timer.After(0.01, RefreshAddList)
        return
    end
    local cols = math_floor(contentWidth / GRID_CELL_STRIDE)
    if cols < 1 then cols = 1 end

    local sy = 0
    local colPos = 0
    local cellIndex = 0

    for _, entry in ipairs(sourceEntries) do
        local entryName = entry.name or ""
        local show = true
        if hasFilter and not string_find(string_lower(entryName), lowerFilter, 1, true) then
            local sidStr = tostring(entry.spellID or "")
            if not string_find(sidStr, filterText, 1, true) then
                show = false
            end
        end

        if show then
            local entryKey = (entry._entryType or "spell") .. ":" .. (entry._entryID or entry.spellID or 0)
            local isOwned = ownedSet[entryKey]
            if not isOwned and entry.spellID then
                isOwned = ownedSet["spell:" .. entry.spellID]
            end

            cellIndex = cellIndex + 1
            local cell = GetOrCreateAddCell(cellIndex)
            cell:SetParent(addListContent)
            cell._sourceEntry = entry
            cell._isOwned = isOwned

            cell._icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            if isOwned then
                cell._icon:SetDesaturated(true)
                cell:SetAlpha(0.4)
            else
                cell._icon:SetDesaturated(false)
                cell:SetAlpha(1)
            end

            -- Right-click to add directly
            if isOwned then
                cell:SetScript("OnClick", nil)
            else
                local entryRef = entry
                cell:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        if InCombatLockdown() then return end

                        local containerDB = GetContainerDB(activeContainer)
                        if not containerDB then return end

                        local addType = entryRef._entryType or "spell"
                        local addID = entryRef._entryID or entryRef.spellID

                        -- Capacity check for cooldown containers: find first row with room
                        local targetRow = nil
                        if ResolveContainerType(activeContainer) == "cooldown" then
                            local spells = containerDB.ownedSpells or {}
                            local firstActiveRow = nil
                            for r = 1, 3 do
                                local rd = containerDB["row" .. r]
                                if rd and rd.iconCount and rd.iconCount > 0 then
                                    if not firstActiveRow then firstActiveRow = r end
                                    local count = 0
                                    for _, e in ipairs(spells) do
                                        if e and (e.row or firstActiveRow) == r then
                                            count = count + 1
                                        end
                                    end
                                    if count < rd.iconCount and not targetRow then
                                        targetRow = r
                                    end
                                end
                            end
                            if not targetRow then
                                UIErrorsFrame:AddMessage("All rows are full — remove a spell or increase row size", 1.0, 0.3, 0.3, 1.0, 3)
                                UIErrorsFrame:SetFrameStrata("TOOLTIP")
                                return
                            end
                        end

                        if containerDB.removedSpells and addID then
                            containerDB.removedSpells[addID] = nil
                        end

                        -- Tab-of-origin is authoritative for entry.kind: spells added
                        -- from Passives/Buffs are auras; from CDM/Cooldowns/Items they
                        -- are cooldowns. by_spell_id and the mixed CDM tab on built-in
                        -- containers fall through to the runtime classifier.
                        local kindFromTab = nil
                        if activeAddTab == "other_auras" or activeAddTab == "active_buffs" then
                            kindFromTab = "aura"
                        elseif activeAddTab == "all_cooldowns" or activeAddTab == "items" then
                            kindFromTab = "cooldown"
                        end

                        local addResult
                        if addType == "slot" and entryRef._slotID then
                            if containerDB.removedSpells then
                                containerDB.removedSpells[entryRef._slotID] = nil
                            end
                            addResult = spellData:AddTrinketSlot(activeContainer, entryRef._slotID)
                        elseif addType == "item" then
                            addResult = spellData:AddItem(activeContainer, addID)
                        else
                            addResult = spellData:AddSpell(activeContainer, addID, kindFromTab)
                        end

                        -- Assign the new entry to the target row (first with capacity)
                        if addResult and targetRow then
                            local spells = containerDB.ownedSpells
                            if spells and #spells > 0 then
                                spells[#spells].row = targetRow
                            end
                        end

                        C_Timer.After(0.02, function()
                            RefreshCDM()
                            RefreshEntryList()
                            RefreshPreview()
                            RefreshAddList()
                        end)
                    end
                end)
            end

            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", addListContent, "TOPLEFT",
                colPos * GRID_CELL_STRIDE, sy)
            cell:Show()
            colPos = colPos + 1
            if colPos >= cols then
                colPos = 0
                sy = sy - GRID_CELL_STRIDE
            end
        end
    end

    -- Finish last row
    if colPos > 0 then
        sy = sy - GRID_CELL_STRIDE
    end

    -- Empty-state hints. by_spell_id is empty until a numeric filter is
    -- typed; active_buffs depends on what's on the player right now.
    local hintText
    if cellIndex == 0 then
        if activeAddTab == "by_spell_id" then
            hintText = "Type a numeric spell ID into the search box above to resolve it."
        elseif activeAddTab == "active_buffs" then
            hintText = "No buffs active on you right now. Pop a trinket, potion, or cast a spell, then click this tab again."
        elseif activeAddTab == "active_debuffs" then
            hintText = "No harmful debuffs on you right now."
        end
    end
    if hintText then
        local hint = addListContent._emptyHint
        if not hint then
            hint = addListContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hint:SetJustifyH("LEFT")
            hint:SetJustifyV("TOP")
            hint:SetTextColor(0.55, 0.55, 0.55, 1)
            addListContent._emptyHint = hint
        end
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", addListContent, "TOPLEFT", 6, -6)
        hint:SetPoint("RIGHT", addListContent, "RIGHT", -6, 0)
        hint:SetText(hintText)
        hint:Show()
        local minSy = -(hint:GetStringHeight() + 20)
        if sy > minSy then sy = minSy end
    elseif addListContent._emptyHint then
        addListContent._emptyHint:Hide()
    end

    addListContent:SetHeight(math_max(8, math_abs(sy) + 8))
    if addListContent._updateScroll then
        addListContent._updateScroll()
    end
end

local function BuildAddTabs()
    if not addPanel or not activeContainer then return end

    -- Clear old tabs
    for _, btn in ipairs(addTabButtons) do
        btn:Hide()
    end

    local tabBar = addPanel._tabBar
    if not tabBar then return end

    local containerType = ResolveContainerType(activeContainer) or "cooldown"
    local tabs = {}

    -- Built-ins (essential/utility/buff/trackedBar) keep their original
    -- focused tab set. Only user-created containers (customBar and any
    -- future custom container) get the unified rich picker so users can
    -- mix spells / items / auras / passives freely.
    local activeContainerDB = GetContainerDB(activeContainer)
    local isBuiltIn = activeContainerDB and activeContainerDB.builtIn ~= false
        and (activeContainer == "essential" or activeContainer == "utility"
             or activeContainer == "buff" or activeContainer == "trackedBar")

    if isBuiltIn then
        if containerType == "cooldown" then
            tabs = {
                { key = "cdm_spells",    label = "Blizzard CDM" },
                { key = "all_cooldowns", label = "All Cooldowns" },
                { key = "items",         label = "Items & Trinkets" },
            }
        elseif containerType == "aura" then
            tabs = {
                { key = "cdm_spells",     label = "Blizzard CDM" },
                { key = "other_auras",    label = "Other Auras" },
            }
        elseif containerType == "auraBar" then
            tabs = {
                { key = "cdm_spells",     label = "Blizzard CDM" },
                { key = "other_auras",    label = "Other Auras" },
            }
        end
    else
        -- Custom containers: unified picker regardless of container type.
        -- Labels compressed so 6 tabs share the row with the search box.
        -- Full meanings: CDM=Blizzard CDM, Cooldowns=All Cooldowns,
        -- Passives=Other Auras, Buffs=Active Buffs on player.
        tabs = {
            { key = "cdm_spells",     label = "CDM" },
            { key = "all_cooldowns",  label = "Cooldowns" },
            { key = "items",          label = "Items" },
            { key = "other_auras",    label = "Passives" },
            { key = "active_buffs",   label = "Buffs" },
            { key = "by_spell_id",    label = "Spell ID" },
        }
    end

    if not activeAddTab then
        activeAddTab = tabs[1] and tabs[1].key or "cdm_spells"
    end

    -- Validate activeAddTab is in current tab set
    local found = false
    for _, t in ipairs(tabs) do
        if t.key == activeAddTab then found = true break end
    end
    if not found then activeAddTab = tabs[1] and tabs[1].key or "cdm_spells" end

    local xOff = 0
    for i, tabInfo in ipairs(tabs) do
        local btn = addTabButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
            btn:SetHeight(TAB_HEIGHT - 2)
            addTabButtons[i] = btn
            btn._label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn._label:SetPoint("CENTER")
        end

        local tabWidth = math_max(80, btn._label:GetStringWidth() + 24)
        btn:SetParent(tabBar)
        btn._label:SetText(tabInfo.label)
        tabWidth = math_max(80, btn._label:GetStringWidth() + 24)
        btn:SetSize(tabWidth, TAB_HEIGHT - 2)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", tabBar, "LEFT", xOff, 0)

        local isActive = (tabInfo.key == activeAddTab)
        if isActive then
            SetSimpleBackdrop(btn, ACCENT_R * 0.15, ACCENT_G * 0.15, ACCENT_B * 0.15, 1,
                ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
            btn._label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        else
            SetSimpleBackdrop(btn, 0.08, 0.08, 0.1, 1, 0.2, 0.2, 0.2, 1)
            btn._label:SetTextColor(0.6, 0.6, 0.6, 1)
        end

        local tabKey = tabInfo.key
        btn:SetScript("OnClick", function()
            activeAddTab = tabKey
            BuildAddTabs()
            RefreshAddList()
        end)
        btn:SetScript("OnEnter", function(self)
            if tabKey ~= activeAddTab then
                self:SetBackdropBorderColor(ACCENT_R * 0.7, ACCENT_G * 0.7, ACCENT_B * 0.7, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if tabKey ~= activeAddTab then
                self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            end
        end)

        btn:Show()
        xOff = xOff + tabWidth + 3
    end
end

---------------------------------------------------------------------------
-- CONTAINER TABS (Top of Composer)
---------------------------------------------------------------------------

-- Phase G: New Container creation popup
local newContainerPopup = nil
local newContainerCallback = nil  -- invoked with newKey after Create

local function ShowNewContainerPopup(onCreated)
    newContainerCallback = onCreated
    if newContainerPopup then
        newContainerPopup:Show()
        newContainerPopup:Raise()
        return
    end

    local popup = CreateFrame("Frame", "QUI_CDMNewContainerPopup", UIParent, "BackdropTemplate")
    popup:SetSize(300, 180)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(250)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
    popup:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("New Container")
    title:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    -- Name label + editbox
    local nameLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", 12, -36)
    nameLabel:SetText("Name:")
    nameLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local nameBox = CreateFrame("EditBox", nil, popup, "BackdropTemplate")
    nameBox:SetSize(260, 22)
    nameBox:SetPoint("TOPLEFT", 12, -52)
    nameBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    nameBox:SetBackdropColor(0.06, 0.06, 0.08, 1)
    nameBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    nameBox:SetFontObject("GameFontNormalSmall")
    nameBox:SetTextInsets(6, 6, 0, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(30)
    nameBox:SetText("My Container")
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Type label + dropdown buttons
    local typeLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetPoint("TOPLEFT", 12, -82)
    typeLabel:SetText("Type:")
    typeLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Phase B.3: two unified options. Icons accept any mix of spells,
    -- items, trinkets, and auras; Bars render durations as horizontal bars.
    -- The entry list picker (Items / Cooldowns / Active Buffs / By Spell ID)
    -- lets the user fill in whatever content they want regardless of choice.
    local TYPE_OPTIONS = {
        { value = "cooldown", text = "Custom Icons" },
        { value = "auraBar",  text = "Custom Bars" },
    }

    local selectedType = "cooldown"
    local typeButtons = {}

    local function UpdateTypeButtons()
        for _, btn in ipairs(typeButtons) do
            if btn._value == selectedType then
                btn:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                btn._label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            else
                btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
                btn._label:SetTextColor(0.6, 0.6, 0.6, 1)
            end
        end
    end

    local btnX = 12
    for _, opt in ipairs(TYPE_OPTIONS) do
        local btn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        btn:SetSize(88, 22)
        btn:SetPoint("TOPLEFT", btnX, -98)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.1, 0.1, 0.12, 1)
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(opt.text)
        btn._label = label
        btn._value = opt.value
        btn:SetScript("OnClick", function()
            selectedType = opt.value
            UpdateTypeButtons()
        end)
        typeButtons[#typeButtons + 1] = btn
        btnX = btnX + 92
    end
    UpdateTypeButtons()

    -- Create + Cancel buttons
    local createBtn = CreateAccentButton(popup, "Create", 120, 26)
    createBtn:SetPoint("BOTTOMLEFT", 12, 12)
    createBtn:SetScript("OnClick", function()
        local name = nameBox:GetText()
        if not name or name == "" then name = "Custom" end
        if ns.CDMContainers and ns.CDMContainers.CreateContainer then
            local newKey = ns.CDMContainers.CreateContainer(name, selectedType)
            if newKey then
                -- Select mover in layout mode
                local elementKey = "cdmCustom_" .. newKey
                local um = ns.QUI_LayoutMode
                if um then
                    um:ActivateElement(elementKey)
                    local uiSelf = ns.QUI_LayoutMode_UI
                    if uiSelf and uiSelf._RebuildDrawer then
                        uiSelf:_RebuildDrawer()
                    end
                    um:SelectMover(elementKey)
                end

                -- Re-sync mover after layout mode hooks settle
                C_Timer.After(0.1, function()
                    if _G.QUI_LayoutModeSyncHandle then
                        _G.QUI_LayoutModeSyncHandle(elementKey)
                    end
                end)

                -- If a caller (e.g. Cooldown Manager tile's "+ New"
                -- button) registered a callback, invoke it with the
                -- new key. Otherwise fall back to popping the old
                -- Composer surface open for the new container.
                if newContainerCallback then
                    local cb = newContainerCallback
                    newContainerCallback = nil
                    cb(newKey)
                elseif _G.QUI_OpenCDMComposer then
                    _G.QUI_OpenCDMComposer(newKey)
                end
            end
        end
        popup:Hide()
    end)

    local cancelBtn = CreateSmallButton(popup, "Cancel", 80, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    cancelBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(0.5, 0.5, 0.5, 1)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(0.9, 0.3, 0.3, 1) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.5, 0.5, 0.5, 1) end)

    newContainerPopup = popup
    popup:Show()
end

-- Phase G: Right-click context menu for custom container tabs
local function ShowContainerContextMenu(containerKey, anchorFrame)
    -- Use a simple dropdown-like frame
    if _G.QUI_ContainerContextMenu then
        _G.QUI_ContainerContextMenu:Hide()
    end

    local menu = CreateFrame("Frame", "QUI_ContainerContextMenu", UIParent, "BackdropTemplate")
    menu:SetSize(140, 60)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(300)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.08, 0.08, 0.1, 0.98)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    menu:EnableMouse(true)
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)

    -- Rename option
    local renameBtn = CreateFrame("Button", nil, menu)
    renameBtn:SetSize(136, 24)
    renameBtn:SetPoint("TOPLEFT", 2, -2)
    local renameText = renameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    renameText:SetPoint("LEFT", 8, 0)
    renameText:SetText("Rename")
    renameText:SetTextColor(0.8, 0.8, 0.8, 1)
    renameBtn:SetScript("OnClick", function()
        menu:Hide()
        -- Simple rename via chat input
        StaticPopupDialogs["QUI_RENAME_CONTAINER"] = {
            text = "Enter new name:",
            button1 = "OK",
            button2 = "Cancel",
            hasEditBox = true,
            maxLetters = 30,
            OnAccept = function(self)
                local box = self.editBox or self.EditBox
                local newName = box and box:GetText()
                if newName and newName ~= "" and ns.CDMContainers then
                    ns.CDMContainers.RenameContainer(containerKey, newName)
                    BuildContainerTabs()
                    RefreshAll_Composer()
                end
            end,
            OnShow = function(self)
                local box = self.editBox or self.EditBox
                if box then
                    local db = GetContainerDB(containerKey)
                    box:SetText(db and db.name or containerKey)
                    box:HighlightText()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("QUI_RENAME_CONTAINER")
    end)
    renameBtn:SetScript("OnEnter", function(self)
        renameText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    renameBtn:SetScript("OnLeave", function(self)
        renameText:SetTextColor(0.8, 0.8, 0.8, 1)
    end)

    -- Delete option
    local deleteBtn = CreateFrame("Button", nil, menu)
    deleteBtn:SetSize(136, 24)
    deleteBtn:SetPoint("TOPLEFT", renameBtn, "BOTTOMLEFT", 0, 0)
    local deleteText = deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deleteText:SetPoint("LEFT", 8, 0)
    deleteText:SetText("Delete")
    deleteText:SetTextColor(0.9, 0.3, 0.3, 1)
    deleteBtn:SetScript("OnClick", function()
        menu:Hide()
        StaticPopupDialogs["QUI_DELETE_CONTAINER"] = {
            text = "Delete this container? This cannot be undone.",
            button1 = "Delete",
            button2 = "Cancel",
            OnAccept = function()
                if ns.CDMContainers and ns.CDMContainers.DeleteContainer then
                    ns.CDMContainers.DeleteContainer(containerKey)
                    activeContainer = "essential"
                    BuildContainerTabs()
                    RefreshAll_Composer()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("QUI_DELETE_CONTAINER")
    end)
    deleteBtn:SetScript("OnEnter", function(self)
        deleteText:SetTextColor(1, 0.4, 0.4, 1)
    end)
    deleteBtn:SetScript("OnLeave", function(self)
        deleteText:SetTextColor(0.9, 0.3, 0.3, 1)
    end)

    -- Auto-hide when clicking elsewhere
    menu:SetScript("OnUpdate", function(self)
        if not MouseIsOver(self) and IsMouseButtonDown("LeftButton") then
            self:Hide()
        end
    end)

    menu:Show()
end

BuildContainerTabs = function()
    if not composerFrame then return end

    local tabBar = composerFrame._tabBar
    if not tabBar then return end

    -- Phase G: Get all container keys (built-in + custom)
    local allKeys = GetAllTabKeys()

    -- Hide all existing tabs first
    for i, btn in ipairs(containerTabs) do
        if btn then btn:Hide() end
    end

    local yOff = -4
    for i, containerKey in ipairs(allKeys) do
        local btn = containerTabs[i]
        if not btn then
            btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
            containerTabs[i] = btn
            btn._label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn._label:SetPoint("LEFT", 8, 0)
            btn._label:SetPoint("RIGHT", -4, 0)
            btn._label:SetJustifyH("LEFT")
        end

        btn._label:SetText(GetContainerLabel(containerKey))
        btn:SetHeight(TAB_HEIGHT)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 2, yOff)
        btn:SetPoint("RIGHT", tabBar, "RIGHT", -2, 0)

        local isActive = (containerKey == activeContainer)
        if isActive then
            SetSimpleBackdrop(btn, ACCENT_R * 0.15, ACCENT_G * 0.15, ACCENT_B * 0.15, 1,
                ACCENT_R, ACCENT_G, ACCENT_B, 1)
            btn._label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        else
            SetSimpleBackdrop(btn, 0.06, 0.06, 0.08, 1, 0.2, 0.2, 0.2, 1)
            btn._label:SetTextColor(0.6, 0.6, 0.6, 1)
        end

        local key = containerKey
        local isBuiltIn = IsBuiltInContainer(key)
        btn:SetScript("OnClick", function()
            activeContainer = key
            expandedOverride = nil
            activeAddTab = nil
            BuildContainerTabs()
            RefreshAll_Composer()
        end)
        -- Phase G: Right-click context menu for custom containers
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and not isBuiltIn then
                ShowContainerContextMenu(key, self)
            end
        end)
        btn:SetScript("OnEnter", function(self)
            if key ~= activeContainer then
                self:SetBackdropBorderColor(ACCENT_R * 0.7, ACCENT_G * 0.7, ACCENT_B * 0.7, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if key ~= activeContainer then
                self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            end
        end)

        btn:Show()
        yOff = yOff - TAB_HEIGHT - 2
    end

    -- [+ New] button at bottom of nav
    local newIdx = #allKeys + 1
    local newBtn = containerTabs[newIdx]
    if not newBtn then
        newBtn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        newBtn:SetHeight(TAB_HEIGHT)
        containerTabs[newIdx] = newBtn
        newBtn._label = newBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        newBtn._label:SetPoint("LEFT", 8, 0)
        newBtn._label:SetJustifyH("LEFT")
    end
    newBtn._label:SetText("+ New")
    newBtn:ClearAllPoints()
    newBtn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 2, yOff)
    newBtn:SetPoint("RIGHT", tabBar, "RIGHT", -2, 0)
    SetSimpleBackdrop(newBtn, 0.06, 0.06, 0.08, 1, ACCENT_R * 0.4, ACCENT_G * 0.4, ACCENT_B * 0.4, 0.6)
    newBtn._label:SetTextColor(ACCENT_R * 0.6, ACCENT_G * 0.6, ACCENT_B * 0.6, 1)
    newBtn:SetScript("OnClick", function()
        ShowNewContainerPopup()
    end)
    newBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        newBtn._label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)
    newBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(ACCENT_R * 0.4, ACCENT_G * 0.4, ACCENT_B * 0.4, 0.6)
        newBtn._label:SetTextColor(ACCENT_R * 0.6, ACCENT_G * 0.6, ACCENT_B * 0.6, 1)
    end)
    newBtn:Show()
end

---------------------------------------------------------------------------
-- FOOTER BUTTONS
---------------------------------------------------------------------------
local function BuildFooter(parent)
    local footer = CreateFrame("Frame", nil, parent)
    footer:SetHeight(32)

    -- Reset to Blizzard Defaults
    local resetBtn = CreateSmallButton(footer, "Reset to Blizzard Defaults", 180, 24)
    resetBtn._label:SetTextColor(0.9, 0.6, 0.2, 1)
    resetBtn:SetPoint("LEFT", footer, "LEFT", 8, 0)
    resetBtn:SetSize(180, 24)
    resetBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        local spellData = GetCDMSpellData()
        if spellData and activeContainer then
            -- Confirm with a second click (toggle state)
            if resetBtn._confirmPending then
                spellData:ResnapshotFromBlizzard(activeContainer)
                resetBtn._confirmPending = false
                resetBtn._label:SetText("Reset to Blizzard Defaults")
                resetBtn._label:SetTextColor(0.9, 0.6, 0.2, 1)
                C_Timer.After(0.05, RefreshAll_Composer)
            else
                resetBtn._confirmPending = true
                resetBtn._label:SetText("Click Again to Confirm")
                resetBtn._label:SetTextColor(0.9, 0.3, 0.3, 1)
                -- Auto-cancel after 3 seconds
                C_Timer.After(3, function()
                    if resetBtn._confirmPending then
                        resetBtn._confirmPending = false
                        resetBtn._label:SetText("Reset to Blizzard Defaults")
                        resetBtn._label:SetTextColor(0.9, 0.6, 0.2, 1)
                    end
                end)
            end
        end
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.9, 0.6, 0.2, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetFrameLevel(250)
        GameTooltip:SetText("Reset Spell List", 1, 1, 1)
        GameTooltip:AddLine("Clears all customizations and re-snapshots spells from Blizzard's CDM data.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        GameTooltip:Hide()
    end)

    parent._footer = footer
    return footer
end

---------------------------------------------------------------------------
-- FULL REFRESH
---------------------------------------------------------------------------
function RefreshAll_Composer()
    if not composerFrame or not activeContainer then return end

    -- Update title
    if composerFrame._title then
        composerFrame._title:SetText("Spell Manager - " .. GetContainerLabel(activeContainer))
    end

    RefreshPreview()
    RefreshEntryList()
    BuildAddTabs()
    RefreshAddList()
end

---------------------------------------------------------------------------
-- COMPOSER LAYOUT
-- Paints the composer surface (nav panel + preview + entry list + add
-- section + footer) into a host frame supplied by the caller. The popup
-- chrome (titlebar, close button, drag) was removed when the composer
-- moved into the QUI options panel. The host is the V2 Cooldown Manager
-- tile's "Composer" sub-page body.
---------------------------------------------------------------------------
local function BuildComposerLayout(host)
    if not host then return end
    -- Cached layout is reused only if it's still attached to this host.
    -- When the tile tab-switches away, it reparents children to nil; the
    -- cached frame is detached and must be rebuilt the next time the
    -- Entries tab renders.
    if host._composerLayout then
        local cached = host._composerLayout
        if cached.GetParent and cached:GetParent() == host then
            composerFrame = cached
            return
        end
        host._composerLayout = nil
    end

    -- Outer scroll wrapper: the panel can be sized smaller than the
    -- composer's natural dimensions; rather than overflow the host, we
    -- scroll. The BackdropTemplate wrapper inside has a minimum size and
    -- stretches to fill the host when the host is larger.
    --
    -- When embedded via host._hideComposerNav (the tile's Entries tab),
    -- the composer IS the tab content — we let the scroll child match
    -- the viewport so there's no artificial empty space at the bottom
    -- and no scrollbar unless the content genuinely overflows. In the
    -- legacy popup path we keep the 640×670 minimum.
    local embedded = host._hideComposerNav
    local MIN_W = embedded and 400 or FRAME_WIDTH
    local MIN_H = embedded and 260 or (FRAME_HEIGHT - 30)
    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -18, 0)
    host._composerScroll = scroll

    -- Style the scroll bar to match QUI theme.
    local scrollBar = scroll.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, -2)
        scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 2)
        local thumb = scrollBar:GetThumbTexture()
        if thumb then thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8) end
        local up = scrollBar.ScrollUpButton or scrollBar.Back
        local down = scrollBar.ScrollDownButton or scrollBar.Forward
        if up then up:Hide(); up:SetAlpha(0) end
        if down then down:Hide(); down:SetAlpha(0) end
    end

    -- Composer layout host. We use explicit bg + 4 border textures rather
    -- than SetBackdrop({edgeSize=1, ...}) because the scroll-child resize
    -- (FitToHost) hits a Blizzard SetupTextureCoordinates recursion in
    -- Blizzard_SharedXML/Backdrop.lua at this frame's typical
    -- width/height/effectiveScale (≈640×670 @ 0.64), causing a C stack
    -- overflow on first paint of the V2 Cooldown Manager tile.
    local frame = CreateFrame("Frame", nil, scroll)
    frame:SetSize(MIN_W, MIN_H)
    scroll:SetScrollChild(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.97)
    frame._bg = bg
    local borders = {}
    for i = 1, 4 do borders[i] = frame:CreateTexture(nil, "BORDER") end
    borders[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borders[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borders[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borders[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borders[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borders[4]:SetWidth(1)
    for i = 1, 4 do
        borders[i]:SetColorTexture(ACCENT_R * 0.6, ACCENT_G * 0.6, ACCENT_B * 0.6, 0.8)
    end
    frame._border = borders
    host._composerLayout = frame
    composerFrame = frame

    -- Resize the scroll child to fill the viewport when the host grows
    -- beyond MIN_W/MIN_H; otherwise stay at the minimum so the scroll
    -- frame can pan it.
    --
    -- Embedded mode: the composer is the tile's Entries tab, so the
    -- scroll child should match the viewport exactly (no dead space,
    -- no scrollbar unless the entry/add sections genuinely exceed the
    -- viewport). Popup mode keeps the old "grow-only" behavior so the
    -- composer has room to breathe inside a floating window.
    local function FitToHost()
        local sw = scroll:GetWidth() or 0
        local sh = scroll:GetHeight() or 0
        local w, h
        if embedded then
            w = math.max(MIN_W, sw)
            h = math.max(MIN_H, sh)
            -- Prefer viewport height when the viewport is smaller than
            -- the scroll child's minimum, but clamp to MIN_H so the
            -- internal relayout has a sane floor.
            if sh > 0 and sh < MIN_H then h = sh end
            if sh >= MIN_H then h = sh end
        else
            w = math.max(MIN_W, sw)
            h = math.max(MIN_H, sh)
        end
        frame:SetSize(w, h)
    end
    scroll:HookScript("OnSizeChanged", FitToHost)
    FitToHost()

    -- Hosts that drive container selection via an external dropdown
    -- (the Cooldown Manager Containers sub-page) set host._hideComposerNav
    -- to claim both the container nav AND the preview. In that mode we
    -- skip the nav panel entirely and shift every content section to
    -- the frame's left edge, reclaiming the full width.
    local hostOwnsNav = host and host._hideComposerNav
    local contentLeft, footerLeft
    if hostOwnsNav then
        contentLeft = 0
        footerLeft = 0
    else
        -- Left navigation panel (vertical container list). Explicit bg
        -- texture instead of SetBackdrop — same Blizzard recursion bug
        -- as the parent frame above.
        local navPanel = CreateFrame("Frame", nil, frame)
        navPanel:SetWidth(NAV_WIDTH)
        navPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        navPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 36)
        local navBg = navPanel:CreateTexture(nil, "BACKGROUND")
        navBg:SetAllPoints(navPanel)
        navBg:SetColorTexture(0.04, 0.04, 0.06, 1)
        frame._navPanel = navPanel
        frame._tabBar = navPanel  -- BuildContainerTabs reads ._tabBar

        -- Nav border (right edge)
        local navBorder = navPanel:CreateTexture(nil, "ARTWORK")
        navBorder:SetWidth(1)
        navBorder:SetPoint("TOPRIGHT", navPanel, "TOPRIGHT", 0, 0)
        navBorder:SetPoint("BOTTOMRIGHT", navPanel, "BOTTOMRIGHT", 0, 0)
        navBorder:SetColorTexture(0.2, 0.2, 0.2, 1)

        contentLeft = NAV_WIDTH + 4
        footerLeft = NAV_WIDTH
    end

    -- Live Preview — suppressed when the host owns the nav (the tile
    -- hoists the preview above the sub-tabs). Entry section claims the
    -- space that would have held the preview.
    local entryY = -188
    if not hostOwnsNav then
        local preview = BuildPreviewSection(frame)
        preview:SetPoint("TOPLEFT", frame, "TOPLEFT", contentLeft, 0)
        preview:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    else
        entryY = 0
    end

    -- Entry List (below preview if present) — height set dynamically by Relayout below
    local entrySection = BuildEntryListSection(frame)
    entrySection:SetPoint("TOPLEFT", frame, "TOPLEFT", contentLeft, entryY)
    entrySection:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame._entrySection = entrySection

    -- Add section (below entry list)
    local addSection = BuildAddSection(frame)
    addSection:SetPoint("TOPLEFT", entrySection, "BOTTOMLEFT", 0, -4)
    addSection:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame._addSection = addSection

    -- Footer
    local footer = BuildFooter(frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", footerLeft, 4)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 4)
    frame._footer = footer

    -- Split the vertical space between entrySection and addSection so the
    -- composer fits whatever the current panel size is. Re-runs whenever
    -- the host (and therefore the wrapper) changes size.
    --
    -- Embedded mode skips the 188px preview reservation (the tile hoists
    -- the preview above the tab strip), so the entry/add sections claim
    -- that space instead of leaving it as dead air between rows.
    local PREVIEW_H = embedded and 0 or 188
    local FOOTER_H  = 36
    local GAP       = 4
    local MIN_SECT  = 80
    local function Relayout()
        local h = frame:GetHeight() or FRAME_HEIGHT
        local content = h - PREVIEW_H - FOOTER_H - GAP * 2
        local each = math.max(MIN_SECT, math.floor(content / 2))
        entrySection:SetHeight(each)
        addSection:SetHeight(each)
    end
    frame:HookScript("OnSizeChanged", Relayout)
    Relayout()

    -- Override panel (created lazily, parented to entry content)
    BuildOverridePanel(entryListContent)

    -- Wire search callbacks
    if searchBox then
        searchBox._onSearch = function()
            C_Timer.After(0.05, RefreshEntryList)
        end
    end
    if addSearchBox then
        addSearchBox._onSearch = function()
            C_Timer.After(0.05, RefreshAddList)
        end
    end

    -- Refresh preview method
    frame._refreshPreview = RefreshPreview
end

---------------------------------------------------------------------------
-- RE-THEME: apply current accent color to static frame elements
---------------------------------------------------------------------------
local function ReThemeComposer(frame)
    if not frame then return end
    -- Main frame border (explicit textures, not SetBackdrop — see BuildComposerLayout)
    if frame._border then
        for i = 1, #frame._border do
            frame._border[i]:SetColorTexture(ACCENT_R * 0.6, ACCENT_G * 0.6, ACCENT_B * 0.6, 0.8)
        end
    end
    -- Title bar background
    if frame._titleBg then
        frame._titleBg:SetColorTexture(ACCENT_R * 0.08, ACCENT_G * 0.08, ACCENT_B * 0.08, 1)
    end
    -- Title text
    if frame._title then
        frame._title:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end
end

---------------------------------------------------------------------------
-- EMBED INTO HOST (V2 tile sub-page builder calls this)
-- Paints the composer layout into `host` if not already done, then sets
-- the active container and refreshes.
---------------------------------------------------------------------------
local function ActivateContainer(containerKey)
    if not containerKey then containerKey = activeContainer or "essential" end
    local db = GetContainerDB(containerKey)
    if not db then containerKey = "essential" end

    if activeContainer == containerKey then
        BuildContainerTabs()
        RefreshAll_Composer()
        return
    end

    activeContainer = containerKey
    expandedOverride = nil
    activeAddTab = nil

    if searchBox then searchBox:SetText("") end
    if addSearchBox then addSearchBox:SetText("") end
    if entryListScroll and entryListScroll._resetScroll then entryListScroll._resetScroll() end
    if addListScroll and addListScroll._resetScroll then addListScroll._resetScroll() end

    BuildContainerTabs()
    RefreshAll_Composer()
end

_G.QUI_EmbedCDMComposer = function(host, containerKey)
    if not host then return end
    RefreshAccentColor()
    -- host._hideComposerNav tells BuildComposerLayout to skip the left
    -- nav panel and shift content to the frame's left edge. The tile
    -- provides its own container dropdown + preview.
    BuildComposerLayout(host)
    ReThemeComposer(composerFrame)
    ActivateContainer(containerKey)
end

-- Phase B.3: tile-level "+ New Container" button calls into the
-- composer's popup. The popup lives here so it reuses the composer's
-- container-creation flow; the tile passes a callback that's invoked
-- with the new container key after successful creation.
_G.QUI_ShowCDMNewContainerPopup = function(onCreated)
    ShowNewContainerPopup(onCreated)
end

-- Phase B.3: hoist the live preview to the Cooldown Manager tile. The
-- tile creates its preview frame above the sub-tab strip and calls
-- QUI_BuildCDMPreview once; subsequent container selections call
-- QUI_RefreshCDMPreview(containerKey). BuildPreviewSection is the
-- existing composer-internal builder — reusing it keeps the visual
-- language consistent. activeContainer is the file-local state used
-- by RefreshPreview to know what to render.
_G.QUI_BuildCDMPreview = function(host, initialContainerKey)
    if not host then return end
    RefreshAccentColor()
    local frame = BuildPreviewSection(host)
    frame:SetAllPoints(host)
    if initialContainerKey then
        local db = GetContainerDB(initialContainerKey)
        if db then activeContainer = initialContainerKey end
    end
    if RefreshPreview then RefreshPreview() end
end

_G.QUI_RefreshCDMPreview = function(containerKey)
    if containerKey then
        local db = GetContainerDB(containerKey)
        if db then activeContainer = containerKey end
    end
    if RefreshPreview then RefreshPreview() end
end

---------------------------------------------------------------------------
-- GLOBAL ENTRY POINT
-- Opens the QUI options panel and navigates to Cooldown Manager →
-- Composer sub-page. The sub-page builder calls _G.QUI_EmbedCDMComposer
-- on first activation; for already-embedded composers we update the
-- active container in place.
---------------------------------------------------------------------------
_G.QUI_OpenCDMComposer = function(containerKey)
    if containerKey then
        local db = GetContainerDB(containerKey)
        if db then activeContainer = containerKey end
    end

    local gui = _G.QUI and _G.QUI.GUI
    if not gui then return end
    if gui.Show and not (gui.MainFrame and gui.MainFrame:IsShown()) then
        gui:Show()
    end
    if gui.NavigateTo then
        gui:NavigateTo(4, 8)  -- Cooldown Manager → Composer sub-page
    end

    -- If already embedded, refresh in place to reflect the requested
    -- container. (Otherwise the V2 sub-page builder will embed for the
    -- first time and pick up activeContainer set above.)
    if composerFrame then
        ActivateContainer(containerKey)
    end
end

-- Global entry point to open the new container popup
_G.QUI_ShowNewCDMContainerPopup = function()
    RefreshAccentColor()
    ShowNewContainerPopup()
end
