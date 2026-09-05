local ADDON_NAME, ns = ...

local SpellList = ns.QUI_AuraSpellList or {}
ns.QUI_AuraSpellList = SpellList

local function GetAuraDefaults()
    return ns.QUI_GroupFramesAuraDefaults
end

local function GetSpellName(spellId)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = ns.SafeCall("best-effort-style", C_Spell.GetSpellName, spellId)
        if ok and name and name ~= "" then
            return name
        end
    end
    if GetSpellInfo then
        local ok, name = ns.SafeCall("best-effort-style", GetSpellInfo, spellId)
        if ok and name and name ~= "" then
            return name
        end
    end
    return nil
end

local function CreateMiniToggle(parent)
    local gui = QUI and QUI.GUI
    local colors = gui and gui.Colors or {}
    local accent = colors.accent or { 0.204, 0.827, 0.6, 1 }
    local toggleOff = colors.toggleOff or { 1, 1, 1, 0.12 }
    local toggleThumb = colors.toggleThumb or { 1, 1, 1, 1 }

    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(26, 14)

    local track = toggle:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints(toggle)
    track:SetColorTexture(toggleOff[1], toggleOff[2], toggleOff[3], toggleOff[4] or 1)
    toggle.track = track

    local trackMask = toggle:CreateMaskTexture()
    trackMask:SetTexture(ns.Helpers.AssetPath .. "pill_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    trackMask:SetAllPoints(track)
    track:AddMaskTexture(trackMask)
    toggle._trackMask = trackMask

    local thumb = toggle:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 10)
    thumb:SetColorTexture(toggleThumb[1], toggleThumb[2], toggleThumb[3], toggleThumb[4] or 1)
    thumb:SetPoint("LEFT", toggle, "LEFT", 2, 0)
    toggle.thumb = thumb

    local thumbMask = toggle:CreateMaskTexture()
    thumbMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    thumbMask:SetAllPoints(thumb)
    thumb:AddMaskTexture(thumbMask)
    toggle._thumbMask = thumbMask

    local hovered = false

    function toggle:SetToggleState(enabled)
        self._toggleOn = enabled == true

        local hoverBoost = hovered and 0.06 or 0
        if self._toggleOn then
            self.track:SetColorTexture(accent[1], accent[2], accent[3], math.min(1, (accent[4] or 1) + hoverBoost))
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("RIGHT", self, "RIGHT", -2, 0)
        else
            self.track:SetColorTexture(
                toggleOff[1],
                toggleOff[2],
                toggleOff[3],
                math.min(1, (toggleOff[4] or 1) + hoverBoost)
            )
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("LEFT", self, "LEFT", 2, 0)
        end

        if self._thumbMask then
            self._thumbMask:SetAllPoints(self.thumb)
        end
    end

    toggle:SetScript("OnEnter", function(self)
        hovered = true
        self:SetToggleState(self._toggleOn)
    end)

    toggle:SetScript("OnLeave", function(self)
        hovered = false
        self:SetToggleState(self._toggleOn)
    end)

    toggle:SetToggleState(false)
    return toggle
end

SpellList.CreateMiniToggle = CreateMiniToggle

local BUFF_BLACKLIST_PRESETS = {
    {
        name = ns.L["Raid Buffs"],
        spells = {
            { id = 1459, name = "Arcane Intellect" },
            { id = 6673, name = "Battle Shout" },
            { id = 21562, name = "Power Word: Fortitude" },
            { id = 1126, name = "Mark of the Wild" },
            { id = 381753, name = "Skyfury" },
            { id = 381748, name = "Blessing of the Bronze" },
            { id = 369459, name = "Source of Magic" },
        },
    },
}

local DEBUFF_BLACKLIST_PRESETS = {
    {
        name = ns.L["Sated / Exhaustion"],
        spells = {
            { id = 57723, name = "Exhaustion" },
            { id = 57724, name = "Sated" },
            { id = 80354, name = "Temporal Displacement" },
            { id = 95809, name = "Insanity" },
            { id = 160455, name = "Fatigued" },
            { id = 264689, name = "Fatigued" },
            { id = 390435, name = "Exhaustion" },
        },
    },
    {
        name = ns.L["Deserter"],
        spells = {
            { id = 26013, name = "Deserter" },
            { id = 71041, name = "Dungeon Deserter" },
        },
    },
}

local BROWSE_ROW_H = 24
local BROWSE_SCROLL_STEP = 45

local browse = {
    popup = nil,
    key = nil,
    opts = nil,
    scopeKept = false,
    dirty = false,
}

local function BrowseFont(fs, path, size, flags)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, path, size, flags)
    else
        fs:SetFont(path, size, flags)
    end
end

local function GetSpellIcon(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = ns.SafeCall("best-effort-style", C_Spell.GetSpellTexture, spellId)
        if ok and icon then
            return icon
        end
    end
    return 134400
end

local function BrowseDisplaySpellID(spellId, opts)
    if not (opts and opts.resolveAuraSpellIDs) then
        return spellId
    end
    local elements = ns.AuraElements
    if elements and elements.ResolveTrackedSpellID then
        return elements.ResolveTrackedSpellID(spellId)
    end
    return spellId
end

local RebuildBrowseRows

local function EnsureBrowsePopup()
    if browse.popup then
        return browse.popup
    end

    local gui = QUI and QUI.GUI
    local SkinBase = ns.SkinBase
    if not gui or not SkinBase or not SkinBase.ApplyPixelBackdrop then
        return nil
    end
    local C = gui.Colors or {}
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local text = C.text or { 1, 1, 1, 1 }
    local muted = C.textMuted or { 1, 1, 1, 0.45 }
    local fontPath = gui.FONT_PATH or [[Interface\AddOns\QUI\assets\Quazii.ttf]]

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(320, 400)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(1000)
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    SkinBase.ApplyPixelBackdrop(popup, 1, true)
    popup:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    popup:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.8)
    popup:Hide()

    popup._accent = accent
    popup._text = text
    popup._muted = muted
    popup._fontPath = fontPath

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetPoint("RIGHT", popup, "RIGHT", -32, 0)
    title:SetJustifyH("LEFT")
    BrowseFont(title, fontPath, 12, "")
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    popup._title = title

    SkinBase.CreateCloseButton(popup, {
        size = 20,
        point = "TOPRIGHT",
        x = -6,
        y = -6,
        onClick = function() popup:Hide() end,
    })

    local searchBg = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    searchBg:SetPoint("TOPLEFT", 8, -28)
    searchBg:SetPoint("RIGHT", popup, "RIGHT", -8, 0)
    searchBg:SetHeight(24)
    SkinBase.ApplyPixelBackdrop(searchBg, 1, true)
    searchBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
    searchBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local search = CreateFrame("EditBox", nil, searchBg)
    search:SetPoint("LEFT", 8, 0)
    search:SetPoint("RIGHT", -8, 0)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    BrowseFont(search, fontPath, 11, "")
    search:SetTextColor(text[1], text[2], text[3], 1)
    search:SetText("")
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    popup._search = search

    local placeholder = searchBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetText(ns.L["Search spells..."])
    BrowseFont(placeholder, fontPath, 11, "")
    placeholder:SetTextColor(muted[1], muted[2], muted[3], 0.6)
    popup._placeholder = placeholder

    local SCROLLBAR_WIDTH = 4
    local scroll = CreateFrame("ScrollFrame", nil, popup)
    scroll:SetPoint("TOPLEFT", 8, -58)
    scroll:SetPoint("BOTTOMRIGHT", -(8 + SCROLLBAR_WIDTH + 2), 8)
    popup._scroll = scroll

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(scroll:GetWidth() or 296)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    popup._scrollChild = scrollChild

    -- Rows are laid out synchronously into scrollChild; measure overflow from
    -- it rather than the native range, which lags a layout pass behind.
    local function BrowseRange()
        return math.max(0, (scrollChild:GetHeight() or 0) - (scroll:GetHeight() or 0))
    end

    scroll:SetScript("OnSizeChanged", function(_, w)
        scrollChild:SetWidth(w or 296)
    end)

    local scrollBar = ns.UIKit.CreateScrollBar(scroll, {
        parent = popup,
        anchor = popup,
        offsetX = -8,
        insetTop = 58,
        insetBottom = 8,
        width = SCROLLBAR_WIDTH,
        getRange = BrowseRange,
    })
    popup._updateThumb = function() scrollBar:Update() end
    popup._scrollCtl = ns.UIKit.AttachSmoothScroll(scroll, {
        step = BROWSE_SCROLL_STEP,
        getRange = BrowseRange,
    })

    local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    empty:SetPoint("TOPLEFT", 4, -4)
    empty:SetText(ns.L["No matching spells."])
    BrowseFont(empty, fontPath, 11, "")
    empty:SetTextColor(muted[1], muted[2], muted[3], 0.8)
    empty:Hide()
    popup._empty = empty

    popup._headerRows = {}
    popup._spellRows = {}

    local searchTimer
    search:SetScript("OnTextChanged", function(self, userInput)
        local txt = self:GetText()
        placeholder:SetShown(not txt or txt == "")
        if not userInput then return end
        if searchTimer then searchTimer:Cancel() end
        searchTimer = C_Timer.NewTimer(0.15, function()
            searchTimer = nil
            RebuildBrowseRows(txt)
        end)
    end)

    popup:SetScript("OnHide", function()
        local opts = browse.opts
        local dirty = browse.dirty
        browse.key = nil
        browse.opts = nil
        browse.dirty = false
        search:SetText("")
        placeholder:Show()
        if dirty and opts and type(opts.onClose) == "function" then
            opts.onClose()
        end
    end)

    browse.popup = popup
    return popup
end

local function AcquireBrowseHeader(index)
    local popup = browse.popup
    local row = popup._headerRows[index]
    if not row then
        row = CreateFrame("Frame", nil, popup._scrollChild)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", 2, 0)
        row.text:SetJustifyH("LEFT")
        BrowseFont(row.text, popup._fontPath, 10, "")
        local a = popup._accent
        row.text:SetTextColor(a[1], a[2], a[3], 0.8)
        popup._headerRows[index] = row
    end
    row:ClearAllPoints()
    row:Show()
    return row
end

local function AcquireBrowseSpellRow(index)
    local popup = browse.popup
    local row = popup._spellRows[index]
    if not row then
        row = CreateFrame("Button", nil, popup._scrollChild)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        BrowseFont(row.text, popup._fontPath, 11, "")
        local a = popup._accent
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(a[1], a[2], a[3], 0.15)
        row:SetScript("OnClick", function(self)
            local opts = browse.opts
            if self.spellId and opts and type(opts.onToggle) == "function" then
                browse.dirty = true
                opts.onToggle(self.spellId)
                RebuildBrowseRows(browse.popup._search:GetText())
            end
        end)
        popup._spellRows[index] = row
    end
    row:ClearAllPoints()
    row:Show()
    return row
end

RebuildBrowseRows = function(filter)
    local popup = browse.popup
    if not popup then return end
    for _, row in ipairs(popup._headerRows) do row:Hide() end
    for _, row in ipairs(popup._spellRows) do row:Hide() end

    local opts = browse.opts
    local accent = popup._accent
    local text = popup._text
    local lower = (type(filter) == "string" and filter ~= "" and ns.Helpers.FoldSearchUTF8(filter)) or nil
    local headerIndex, spellIndex = 0, 0
    local y = 0
    local seen = {}

    for _, preset in ipairs((opts and opts.presets) or {}) do
        local headerPlaced = false
        for _, spell in ipairs(preset.spells or {}) do
            local id = spell.id or spell.spellID
            if id and not seen[id] then
                local name = spell.name or GetSpellName(id) or (ns.L["Spell"] .. " " .. tostring(id))
                local displayID = BrowseDisplaySpellID(id, opts)
                if not lower
                    or ns.Helpers.FoldSearchUTF8(name):find(lower, 1, true)
                    or tostring(id):find(lower, 1, true)
                    or tostring(displayID):find(lower, 1, true) then
                    seen[id] = true
                    if not headerPlaced then
                        headerPlaced = true
                        headerIndex = headerIndex + 1
                        local header = AcquireBrowseHeader(headerIndex)
                        header:SetHeight(BROWSE_ROW_H)
                        header:SetPoint("TOPLEFT", 0, y)
                        header:SetPoint("RIGHT", popup._scrollChild, "RIGHT", 0, 0)
                        header.text:SetText(preset.name or "")
                        y = y - BROWSE_ROW_H
                    end
                    spellIndex = spellIndex + 1
                    local row = AcquireBrowseSpellRow(spellIndex)
                    row:SetHeight(BROWSE_ROW_H)
                    row:SetPoint("TOPLEFT", 0, y)
                    row:SetPoint("RIGHT", popup._scrollChild, "RIGHT", 0, 0)
                    row.spellId = id
                    row.icon:SetTexture(spell.icon or GetSpellIcon(id))
                    local idLabel = tostring(id)
                    if displayID ~= id then
                        idLabel = idLabel .. " -> " .. ns.L["Aura"] .. " " .. tostring(displayID)
                    end
                    row.text:SetText(name .. "  |cFF888888(" .. idLabel .. ")|r")
                    local selected = opts and type(opts.isSelected) == "function" and opts.isSelected(id)
                    if selected then
                        row.bg:SetColorTexture(accent[1], accent[2], accent[3], 0.12)
                        row.text:SetTextColor(accent[1], accent[2], accent[3], 1)
                    else
                        row.bg:SetColorTexture(1, 1, 1, 0)
                        row.text:SetTextColor(text[1], text[2], text[3], 1)
                    end
                    y = y - BROWSE_ROW_H
                end
            end
        end
    end

    popup._empty:SetShown(spellIndex == 0)
    popup._scrollChild:SetHeight(math.max(1, math.abs(y)))

    -- Shorter result set: pull the offset (or in-flight target) back in range.
    if popup._scrollCtl then popup._scrollCtl:Refresh() end
    if popup._updateThumb then
        C_Timer.After(0, popup._updateThumb)
    end
end

function SpellList.ToggleBrowsePopup(key, opts)
    local popup = EnsureBrowsePopup()
    if not popup then return end
    if popup:IsShown() and browse.key == key then
        popup:Hide()
        return
    end
    if popup:IsShown() then
        popup:Hide()
    end
    browse.key = key
    browse.opts = opts
    browse.dirty = false
    popup._title:SetText((opts and opts.title) or ns.L["Browse Spells"])
    popup._search:SetText("")
    popup._placeholder:Show()
    if popup._scrollCtl then
        popup._scrollCtl:ScrollTo(0, true)
    else
        popup._scroll:SetVerticalScroll(0)
    end
    RebuildBrowseRows(nil)
    popup:Show()
    popup:Raise()
end

function SpellList.RefreshBrowsePopup(key, opts)
    if browse.key ~= key then return end
    browse.scopeKept = true
    if not (browse.popup and browse.popup:IsShown()) then return end
    browse.opts = opts
    if opts and opts.title then
        browse.popup._title:SetText(opts.title)
    end
    RebuildBrowseRows(browse.popup._search:GetText())
end

function SpellList.BeginBrowseScope(prefix)
    if type(prefix) ~= "string" or prefix == "" then return end
    if type(browse.key) == "string" and browse.key:sub(1, #prefix) == prefix then
        browse.scopeKept = false
    end
end

function SpellList.EndBrowseScope(prefix)
    if type(prefix) ~= "string" or prefix == "" then return end
    if browse.popup and browse.popup:IsShown()
        and type(browse.key) == "string"
        and browse.key:sub(1, #prefix) == prefix
        and not browse.scopeKept then
        browse.popup:Hide()
    end
end

function SpellList.CloseBrowsePopup(prefix)
    if not (browse.popup and browse.popup:IsShown()) then return end
    if prefix == nil
        or (type(browse.key) == "string" and browse.key:sub(1, #prefix) == prefix) then
        browse.popup:Hide()
    end
end

local function RebuildSpellToggleRows(container, listTable, onChange)
    if type(listTable) ~= "table" then
        container:SetHeight(1)
        return
    end

    if container._rows then
        for _, row in ipairs(container._rows) do
            row:Hide()
        end
    end
    container._rows = container._rows or {}

    local rowHeight = 26
    local y = 0
    local rowIndex = 0

    local extras = {}
    for spellId in pairs(listTable) do
        extras[#extras + 1] = spellId
    end
    table.sort(extras)

    for _, spellId in ipairs(extras) do
        rowIndex = rowIndex + 1
        local row = container._rows[rowIndex]
        if not row then
            row = CreateFrame("Frame", nil, container)
            row:SetHeight(rowHeight)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetJustifyH("LEFT")
            row.removeBtn = CreateFrame("Button", nil, row)
            row.removeBtn:SetSize(18, 18)
            row.removeBtn:SetPoint("RIGHT", -2, 0)
            row.removeBtnText = row.removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.removeBtnText:SetPoint("CENTER")
            row.removeBtnText:SetText("x")
            row.removeBtnText:SetTextColor(0.8, 0.3, 0.3)
            row.removeBtn:SetScript("OnEnter", function()
                row.removeBtnText:SetTextColor(1, 0.4, 0.4)
            end)
            row.removeBtn:SetScript("OnLeave", function()
                row.removeBtnText:SetTextColor(0.8, 0.3, 0.3)
            end)
            container._rows[rowIndex] = row
        end

        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        row.text:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)
        row.text:SetText(GetSpellName(spellId) or (ns.L["Spell"] .. " " .. spellId))
        row.removeBtn:Show()
        row.removeBtn:SetScript("OnClick", function()
            listTable[spellId] = nil
            RebuildSpellToggleRows(container, listTable, onChange)
            if onChange then
                onChange()
            end
        end)

        row:Show()
        y = y - rowHeight
    end

    for i = rowIndex + 1, #container._rows do
        container._rows[i]:Hide()
    end

    container:SetHeight(math.max(1, math.abs(y)))
    if type(container._onLayoutChanged) == "function" then
        container:_onLayoutChanged(container:GetHeight())
    end
end

function SpellList.GetDefaultPresets()
    local AuraDefaults = GetAuraDefaults()
    if AuraDefaults and type(AuraDefaults.GetDefaultPresets) == "function" then
        return AuraDefaults.GetDefaultPresets()
    end
    return {}
end

function SpellList.GetBuffBlacklistPresets()
    return BUFF_BLACKLIST_PRESETS
end

function SpellList.GetDebuffBlacklistPresets()
    return DEBUFF_BLACKLIST_PRESETS
end

function SpellList.CreateListFrame(parent, listTable, presets, onChange, onLayoutChanged)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(1)
    frame._onLayoutChanged = onLayoutChanged
    function frame:Refresh()
        RebuildSpellToggleRows(self, listTable, onChange)
    end
    frame:Refresh()
    return frame
end

return SpellList
