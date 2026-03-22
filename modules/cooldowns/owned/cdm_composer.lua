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
    -- Force layout for the active container even during edit mode
    if activeContainer and _G.QUI_ForceLayoutContainer then
        _G.QUI_ForceLayoutContainer(activeContainer)
    end
    if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
    if _G.QUI_RefreshBuffBar then _G.QUI_RefreshBuffBar() end
end

---------------------------------------------------------------------------
-- ENTRY HELPERS
---------------------------------------------------------------------------
local function GetEntryIcon(entry)
    if not entry then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if entry.type == "spell" then
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, entry.id)
            if ok and info and info.iconID then return info.iconID end
        end
    elseif entry.type == "item" then
        if C_Item and C_Item.GetItemIconByID then
            local ok, icon = pcall(C_Item.GetItemIconByID, entry.id)
            if ok and icon then return icon end
        end
    elseif entry.type == "slot" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID and C_Item and C_Item.GetItemIconByID then
            local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
            if ok and icon then return icon end
        end
    elseif entry.type == "macro" then
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
    if entry.type == "spell" then
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, entry.id)
            if ok and info and info.name then return info.name end
        end
        return "Spell #" .. tostring(entry.id or "?")
    elseif entry.type == "item" then
        if C_Item and C_Item.GetItemNameByID then
            local ok, name = pcall(C_Item.GetItemNameByID, entry.id)
            if ok and name then return name end
        end
        return "Item #" .. tostring(entry.id or "?")
    elseif entry.type == "slot" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID and C_Item and C_Item.GetItemNameByID then
            local ok, name = pcall(C_Item.GetItemNameByID, itemID)
            if ok and name then return name end
        end
        return "Trinket Slot " .. tostring(entry.id or "?")
    elseif entry.type == "macro" then
        return entry.macroName or "Macro"
    end
    return "Unknown"
end

---------------------------------------------------------------------------
-- FRAME FACTORY HELPERS
---------------------------------------------------------------------------
local function CreateBackdropFrame(parent, level)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if level then f:SetFrameLevel(level) end
    return f
end

local function SetSimpleBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bgR or 0.08, bgG or 0.08, bgB or 0.1, bgA or 1)
    frame:SetBackdropBorderColor(borderR or 0.2, borderG or 0.2, borderB or 0.2, borderA or 1)
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

    local entries = db.ownedSpells
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
    local hiddenCheck = GUI:CreateFormCheckbox(overridePanel, "Hidden", "hidden", proxyDB, OnOverrideChange)
    PlaceWidget(hiddenCheck)

    -- Glow toggle
    local glowCheck = GUI:CreateFormCheckbox(overridePanel, "Glow Enabled", "glowEnabled", proxyDB, OnOverrideChange)
    PlaceWidget(glowCheck)

    -- Glow color
    -- For color pickers, we need a real table reference. Use a temp table synced back.
    local glowColorDB = { glowColor = overrides.glowColor or { ACCENT_R, ACCENT_G, ACCENT_B, 1 } }
    local glowColorPicker = GUI:CreateFormColorPicker(overridePanel, "Glow Color", "glowColor", glowColorDB, function()
        spellData:SetSpellOverride(containerKey, spellID, "glowColor", glowColorDB.glowColor)
        OnOverrideChange()
    end)
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
            end)
            PlaceWidget(barColorCheck)

            local barColorPicker = GUI:CreateFormColorPicker(overridePanel, "Bar Color", "barColor", barColorDB, function()
                if barColorEnabled then
                    containerDB.colorOverrides[spellID] = barColorDB.barColor
                    OnOverrideChange()
                end
            end)
            PlaceWidget(barColorPicker)
        end
    end

    -- Duration text toggle
    local durCheck = GUI:CreateFormCheckbox(overridePanel, "Hide Duration Text", "hideDurationText", proxyDB, OnOverrideChange)
    PlaceWidget(durCheck)

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
    fromRow = nil,
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

    -- Tooltip + border highlight on hover
    cell:SetScript("OnEnter", function(self)
        if not self._entry then return end
        self:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetFrameLevel(250)
        local name = GetEntryName(self._entry)
        GameTooltip:AddLine(name, 1, 1, 1)
        if self._isDormant then
            GameTooltip:AddLine("Not Learned (Dormant)", 0.9, 0.6, 0.2)
            GameTooltip:AddLine("Right-click to restore", 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine("Drag to reorder", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        GameTooltip:Hide()
    end)

    entryCells[index] = cell
    return cell
end

local function GetOrCreateSectionHeader(index)
    if sectionHeaders[index] then return sectionHeaders[index] end

    local f = CreateFrame("Frame", nil, entryListContent, "BackdropTemplate")
    f:SetHeight(SECTION_HEADER_HEIGHT)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

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

-- Find which entry index the cursor is nearest in the grid
local function GetDropTargetIndex()
    if not entryListContent then return nil end
    local scale = entryListContent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local bestIdx = nil
    local bestDist = math.huge
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
                    if cursorX < cx then
                        bestIdx = cell._entryIndex
                    else
                        bestIdx = cell._entryIndex + 1
                    end
                end
            end
        end
    end
    return bestIdx
end

local function UpdateDropIndicator()
    local indicator = GetOrCreateDropIndicator()
    if not indicator or not dragState.active then
        if indicator then indicator:Hide() end
        return
    end

    local targetIdx = GetDropTargetIndex()
    if not targetIdx then
        indicator:Hide()
        return
    end

    -- Find anchor cell: the cell at targetIdx (line goes to its left)
    -- or the cell at targetIdx-1 (line goes to its right)
    local anchorCell = nil
    local anchorRight = false
    for i, cell in ipairs(entryCells) do
        if cell:IsShown() and cell._entryIndex then
            if cell._entryIndex == targetIdx then
                anchorCell = cell
                anchorRight = false
                break
            elseif cell._entryIndex == targetIdx - 1 then
                anchorCell = cell
                anchorRight = true
            end
        end
    end

    if anchorCell then
        indicator:ClearAllPoints()
        indicator:SetHeight(GRID_CELL_SIZE)
        if anchorRight then
            indicator:SetPoint("LEFT", anchorCell, "RIGHT", 0, 0)
        else
            indicator:SetPoint("RIGHT", anchorCell, "LEFT", 0, 0)
        end
        indicator:Show()
    else
        indicator:Hide()
    end
end

local StopDrag  -- forward declaration

local function StartDrag(cell, entryIndex)
    if InCombatLockdown() then return end
    dragState.active = true
    dragState.fromIndex = entryIndex
    dragState.fromRow = cell
    -- Highlight the dragged cell
    cell:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)

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
    local cell = dragState.fromRow

    -- Restore cell border
    if cell then
        cell:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
    end

    if dropIndicator then dropIndicator:Hide() end

    if entryListContent then
        entryListContent:SetScript("OnUpdate", nil)
    end

    local targetIdx = GetDropTargetIndex()
    dragState.active = false
    dragState.fromIndex = nil
    dragState.fromRow = nil

    if not targetIdx or not fromIdx or targetIdx == fromIdx or targetIdx == fromIdx + 1 then
        return
    end

    local adjustedTarget = targetIdx
    if targetIdx > fromIdx then
        adjustedTarget = targetIdx - 1
    end

    local spellData = GetCDMSpellData()
    if spellData and activeContainer then
        spellData:ReorderEntry(activeContainer, fromIdx, adjustedTarget)
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
        items[1] = { label = "Restore", color = { ACCENT_R, ACCENT_G, ACCENT_B }, action = function()
            if InCombatLockdown() then return end
            spellData:RestoreRemovedEntry(activeContainer, entry.id or entry)
            C_Timer.After(0.02, function()
                RefreshEntryList()
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

        -- Row cycle (cooldown containers with 2+ rows)
        if isCooldown then
            local activeRowNums = {}
            for r = 1, 3 do
                local rd = db["row" .. r]
                if rd and rd.iconCount and rd.iconCount > 0 then
                    activeRowNums[#activeRowNums + 1] = r
                end
            end
            if #activeRowNums > 1 then
                local curRow = entry.row or activeRowNums[1]
                local nextRow = activeRowNums[1]
                for ri, rn in ipairs(activeRowNums) do
                    if rn == curRow and activeRowNums[ri + 1] then
                        nextRow = activeRowNums[ri + 1]
                        break
                    end
                end
                items[#items + 1] = { label = "Move to Row " .. nextRow .. "  (R" .. curRow .. ")", color = { ACCENT_R, ACCENT_G, ACCENT_B }, action = function()
                    if InCombatLockdown() then return end
                    spellData:SetEntryRow(activeContainer, entryIndex, nextRow)
                    C_Timer.After(0.02, function()
                        RefreshCDM()
                        RefreshEntryList()
                        RefreshPreview()
                    end)
                end }
            end
        end

        -- Move to next container
        local allTabKeys = GetAllTabKeys()
        local ci = 0
        for j, key in ipairs(allTabKeys) do
            if key == activeContainer then ci = j break end
        end
        local targetKey = allTabKeys[(ci % #allTabKeys) + 1]
        items[#items + 1] = { label = "Move to " .. GetContainerLabel(targetKey), color = { ACCENT_R, ACCENT_G, ACCENT_B }, action = function()
            if InCombatLockdown() then return end
            spellData:MoveEntryBetweenContainers(activeContainer, targetKey, entryIndex)
            C_Timer.After(0.02, function()
                RefreshCDM()
                RefreshEntryList()
                RefreshPreview()
            end)
        end }

        -- Remove
        items[#items + 1] = { label = "Remove", color = { 0.9, 0.3, 0.3 }, action = function()
            if InCombatLockdown() then return end
            spellData:RemoveEntry(activeContainer, entryIndex)
            C_Timer.After(0.02, function()
                RefreshCDM()
                RefreshEntryList()
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
-- ADD CONTEXT MENU (right-click on add grid cell)
---------------------------------------------------------------------------
local function ShowAddContextMenu(anchorCell, sourceEntry)
    if _G.QUI_AddContextMenu then
        _G.QUI_AddContextMenu:Hide()
    end

    local spellData = GetCDMSpellData()
    if not spellData then return end

    local menu = CreateFrame("Frame", "QUI_AddContextMenu", UIParent, "BackdropTemplate")
    menu:SetSize(160, 28)
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

    local btn = CreateFrame("Button", nil, menu)
    btn:SetSize(156, 24)
    btn:SetPoint("TOPLEFT", 2, -2)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetText("Add to " .. GetContainerLabel(activeContainer))
    label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    btn:SetScript("OnClick", function()
        menu:Hide()
        if InCombatLockdown() then return end

        local addType = sourceEntry._entryType or "spell"
        local addID = sourceEntry._entryID or sourceEntry.spellID

        local containerDB = GetContainerDB(activeContainer)
        if containerDB and containerDB.removedSpells and addID then
            containerDB.removedSpells[addID] = nil
        end

        if addType == "slot" and sourceEntry._slotID then
            if containerDB and containerDB.removedSpells then
                containerDB.removedSpells[sourceEntry._slotID] = nil
            end
            spellData:AddTrinketSlot(activeContainer, sourceEntry._slotID)
        elseif addType == "item" then
            spellData:AddItem(activeContainer, addID)
        else
            spellData:AddSpell(activeContainer, addID)
        end

        C_Timer.After(0.02, function()
            RefreshCDM()
            RefreshEntryList()
            RefreshPreview()
            RefreshAddList()
        end)
    end)
    btn:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1, 1) end)
    btn:SetScript("OnLeave", function() label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end)

    menu:SetScript("OnUpdate", function(self)
        if not MouseIsOver(self) and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
            self:Hide()
        end
    end)

    menu:Show()
end

---------------------------------------------------------------------------
-- REFRESH ENTRY LIST (icon grid layout)
---------------------------------------------------------------------------
RefreshEntryList = function()
    if not entryListContent or not activeContainer then return end

    HideOverridePanel()
    if _G.QUI_EntryContextMenu then _G.QUI_EntryContextMenu:Hide() end

    local db = GetContainerDB(activeContainer)
    if not db then return end

    local entries = db.ownedSpells
    if type(entries) ~= "table" then entries = {} end

    local dormant = db.dormantSpells
    if type(dormant) ~= "table" then dormant = {} end

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

    local function RenderSectionHeader(label, isEmpty)
        FinishRow()
        headerIndex = headerIndex + 1
        local hdr = GetOrCreateSectionHeader(headerIndex)
        hdr:SetParent(entryListContent)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", entryListContent, "TOPLEFT", 0, sy)
        hdr:SetPoint("RIGHT", entryListContent, "RIGHT", 0, 0)
        hdr:SetBackdropColor(ACCENT_R * 0.1, ACCENT_G * 0.1, ACCENT_B * 0.1, 0.8)
        hdr._label:SetText(label)
        if isEmpty then
            hdr._label:SetTextColor(0.4, 0.4, 0.4, 1)
        else
            hdr._label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end
        hdr:Show()
        sy = sy - SECTION_HEADER_HEIGHT
        colPos = 0
    end

    local function RenderEntryCell(entry, idx)
        local entryName = GetEntryName(entry)
        if hasFilter and not string_find(string_lower(entryName), lowerFilter, 1, true) then
            return
        end

        cellIndex = cellIndex + 1
        local cell = GetOrCreateEntryCell(cellIndex)
        cell:SetParent(entryListContent)
        cell._entry = entry
        cell._entryIndex = idx
        cell._isDormant = false

        cell._icon:SetTexture(GetEntryIcon(entry))
        cell._icon:SetDesaturated(false)
        cell._icon:Show()
        cell:SetAlpha(1)

        -- Wire drag
        cell:SetScript("OnDragStart", function()
            StartDrag(cell, idx)
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
        cell._isDormant = true

        local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            if ok and info and info.iconID then icon = info.iconID end
        end
        cell._icon:SetTexture(icon)
        cell._icon:SetDesaturated(true)
        cell._icon:Show()
        cell:SetAlpha(0.6)

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
            RenderSectionHeader("Row " .. rowNum .. "  (" .. count .. ")", count == 0)
            if count == 0 then
                -- Empty hint (as a small header)
                headerIndex = headerIndex + 1
                local hdr = GetOrCreateSectionHeader(headerIndex)
                hdr:SetParent(entryListContent)
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", entryListContent, "TOPLEFT", 0, sy)
                hdr:SetPoint("RIGHT", entryListContent, "RIGHT", 0, 0)
                hdr:SetHeight(18)
                hdr:SetBackdropColor(0.06, 0.06, 0.08, 0.3)
                hdr._label:SetText("  (empty — right-click icons to move between rows)")
                hdr._label:SetTextColor(0.35, 0.35, 0.35, 1)
                hdr:Show()
                sy = sy - 18
            else
                for _, item in ipairs(rowItems) do
                    RenderEntryCell(item.entry, item.idx)
                end
                FinishRow()
            end
        end
    else
        for i, entry in ipairs(entries) do
            if entry then
                RenderEntryCell(entry, i)
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

    if _G.QUI_AddContextMenu then _G.QUI_AddContextMenu:Hide() end

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
    local ownedSet = {}
    local activeDB = GetContainerDB(activeContainer)
    if activeDB and type(activeDB.ownedSpells) == "table" then
        for _, entry in ipairs(activeDB.ownedSpells) do
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

            -- Right-click to add
            if isOwned then
                cell:SetScript("OnClick", nil)
            else
                local entryRef = entry
                cell:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        ShowAddContextMenu(self, entryRef)
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

    if containerType == "cooldown" then
        tabs = {
            { key = "cdm_spells",    label = "Blizzard CDM" },
            { key = "all_cooldowns", label = "All Cooldowns" },
            { key = "items",         label = "Items & Trinkets" },
        }
    elseif containerType == "aura" then
        tabs = {
            { key = "cdm_spells",     label = "Blizzard CDM" },
        }
    elseif containerType == "auraBar" then
        tabs = {
            { key = "cdm_spells",     label = "Blizzard CDM" },
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

local function ShowNewContainerPopup()
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

    local TYPE_OPTIONS = {
        { value = "cooldown", text = "Cooldown Icons" },
        { value = "aura",     text = "Aura Icons" },
        { value = "auraBar",  text = "Aura Bars" },
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

                -- Open the Composer for the new container
                if _G.QUI_OpenCDMComposer then
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
-- MAIN FRAME CREATION
---------------------------------------------------------------------------
local function CreateComposerFrame()
    if composerFrame then return composerFrame end

    local frame = CreateFrame("Frame", "QUI_CDMComposer", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    frame:SetBackdropBorderColor(ACCENT_R * 0.6, ACCENT_G * 0.6, ACCENT_B * 0.6, 0.8)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(30)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(ACCENT_R * 0.08, ACCENT_G * 0.08, ACCENT_B * 0.08, 1)
    frame._titleBg = titleBg

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    frame._title = titleText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(0.6, 0.6, 0.6, 1)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetScript("OnEnter", function()
        closeText:SetTextColor(0.9, 0.3, 0.3, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeText:SetTextColor(0.6, 0.6, 0.6, 1)
    end)

    -- Left navigation panel (vertical container list)
    local navPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    navPanel:SetWidth(NAV_WIDTH)
    navPanel:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
    navPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 36)
    navPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    navPanel:SetBackdropColor(0.04, 0.04, 0.06, 1)
    frame._navPanel = navPanel
    frame._tabBar = navPanel  -- reuse _tabBar reference for BuildContainerTabs

    -- Nav border (right edge)
    local navBorder = navPanel:CreateTexture(nil, "ARTWORK")
    navBorder:SetWidth(1)
    navBorder:SetPoint("TOPRIGHT", navPanel, "TOPRIGHT", 0, 0)
    navBorder:SetPoint("BOTTOMRIGHT", navPanel, "BOTTOMRIGHT", 0, 0)
    navBorder:SetColorTexture(0.2, 0.2, 0.2, 1)

    -- Content area (right of nav)
    local contentLeft = NAV_WIDTH + 4
    local contentTop = -32

    -- Live Preview
    local preview = BuildPreviewSection(frame)
    preview:SetPoint("TOPLEFT", frame, "TOPLEFT", contentLeft, contentTop)
    preview:SetPoint("RIGHT", frame, "RIGHT", -8, 0)

    -- Entry List (below preview)
    local entryListTop = contentTop - 188
    local entrySection = BuildEntryListSection(frame)
    entrySection:SetPoint("TOPLEFT", frame, "TOPLEFT", contentLeft, entryListTop)
    entrySection:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    entrySection:SetHeight(200)
    frame._entrySection = entrySection

    -- Add section (below entry list)
    local addSection = BuildAddSection(frame)
    addSection:SetPoint("TOPLEFT", entrySection, "BOTTOMLEFT", 0, -4)
    addSection:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    addSection:SetHeight(160)
    frame._addSection = addSection

    -- Footer
    local footer = BuildFooter(frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", NAV_WIDTH, 4)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 4)

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

    -- ESC-to-close via UISpecialFrames
    if not tContains(UISpecialFrames, "QUI_CDMComposer") then
        tinsert(UISpecialFrames, "QUI_CDMComposer")
    end

    frame:Hide()
    composerFrame = frame
    return frame
end

---------------------------------------------------------------------------
-- RE-THEME: apply current accent color to static frame elements
---------------------------------------------------------------------------
local function ReThemeComposer(frame)
    if not frame then return end
    -- Main frame border
    frame:SetBackdropBorderColor(ACCENT_R * 0.6, ACCENT_G * 0.6, ACCENT_B * 0.6, 0.8)
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
-- GLOBAL ENTRY POINT
---------------------------------------------------------------------------
_G.QUI_OpenCDMComposer = function(containerKey)
    if not containerKey then containerKey = "essential" end

    -- Resolve accent color from current theme before creating/refreshing
    RefreshAccentColor()

    -- Validate container key
    local db = GetContainerDB(containerKey)
    if not db then
        -- Fallback to essential
        containerKey = "essential"
    end

    local frame = CreateComposerFrame()
    ReThemeComposer(frame)

    if frame:IsShown() and activeContainer == containerKey then
        -- Already showing this container, just refresh
        RefreshAll_Composer()
        return
    end

    activeContainer = containerKey
    expandedOverride = nil
    activeAddTab = nil

    -- Clear search boxes
    if searchBox then searchBox:SetText("") end
    if addSearchBox then addSearchBox:SetText("") end

    -- Reset scroll positions
    if entryListScroll and entryListScroll._resetScroll then
        entryListScroll._resetScroll()
    end
    if addListScroll and addListScroll._resetScroll then
        addListScroll._resetScroll()
    end

    BuildContainerTabs()
    RefreshAll_Composer()

    frame:Show()
    frame:Raise()
end

-- Global entry point to open the new container popup
_G.QUI_ShowNewCDMContainerPopup = function()
    -- Ensure composer frame exists (popup is parented to it)
    CreateComposerFrame()
    RefreshAccentColor()
    ShowNewContainerPopup()
end

---------------------------------------------------------------------------
-- CLOSE ON LAYOUT MODE EXIT
-- Hook into the existing edit mode exit handler to close the Composer.
---------------------------------------------------------------------------
local originalEditModeExitCDM = _G.QUI_OnEditModeExitCDM

_G.QUI_OnEditModeExitCDM = function()
    -- Close the override panel and Composer when exiting layout mode
    HideOverridePanel(true)
    if composerFrame and composerFrame:IsShown() then
        composerFrame:Hide()
    end

    -- Call original handler
    if originalEditModeExitCDM then
        originalEditModeExitCDM()
    end
end
