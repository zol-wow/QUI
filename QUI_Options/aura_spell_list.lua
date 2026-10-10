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
            if self.customClick then
                self.customClick()
                return
            end
            local opts = browse.opts
            if self.spellId and opts and type(opts.onToggle) == "function" then
                browse.dirty = true
                opts.onToggle(self.spellId)
                RebuildBrowseRows(browse.popup._search:GetText())
            end
        end)
        -- The real spell tooltip is often the only way to tell same-name
        -- variants apart without leaving the game.
        row:SetScript("OnEnter", function(self)
            if not (self.spellId and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = ns.SafeCall("best-effort-style",
                GameTooltip.SetSpellByID, GameTooltip, self.spellId)
            if ok then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        popup._spellRows[index] = row
    end
    row.customClick = nil
    row:ClearAllPoints()
    row:Show()
    return row
end

local BROWSE_SECTION_LIMIT = 12
local BROWSE_TOTAL_LIMIT = 300

-- The dynamic catalog (active auras, spellbook, talents, seen recorder) leads;
-- the caller's curated presets follow. Earlier sections win the per-id dedupe.
local function EffectiveBrowseSections(opts)
    local sections = {}
    if not (opts and opts.skipCatalog) then
        local Catalog = ns.QUI_AuraSpellCatalog
        if Catalog and type(Catalog.BuildSections) == "function" then
            for _, section in ipairs(Catalog.BuildSections()) do
                sections[#sections + 1] = section
            end
        end
    end
    for _, preset in ipairs((opts and opts.presets) or {}) do
        sections[#sections + 1] = preset
    end
    return sections
end

local function BrowseBadge(entry)
    local parts = {}
    if entry.harmful == true then
        parts[#parts + 1] = "|cFFE06C6C" .. ns.L["debuff"] .. "|r"
    elseif entry.harmful == false then
        parts[#parts + 1] = "|cFF7AC37A" .. ns.L["buff"] .. "|r"
    end
    local sources = entry.sources
    if sources then
        if sources.active then
            parts[#parts + 1] = entry.activeUnit == "player"
                and ("|cFF7AC37A" .. ns.L["active on you"] .. "|r")
                or ("|cFF7AC37A" .. ns.L["active now"] .. "|r")
        elseif sources.seen then
            parts[#parts + 1] = entry.seenUnit == "player"
                and ns.L["seen on you"] or ns.L["seen"]
        end
        if sources.spellbook then
            parts[#parts + 1] = "|cFF888888" .. ns.L["spellbook"] .. "|r"
        end
        if sources.talents then
            parts[#parts + 1] = "|cFF888888" .. ns.L["talent"] .. "|r"
        end
    end
    if #parts == 0 then return "" end
    return "  " .. table.concat(parts, " ")
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

    -- Pass 1: match spells per section. Without a search, sections are capped
    -- so the popup opens fast; matched-but-hidden entries become a "+ N more"
    -- hint. With a search, matches across sections are additionally merged by
    -- id so same-name variants can cluster with their combined evidence.
    local Catalog = ns.QUI_AuraSpellCatalog
    local matchedSections = {}
    local merged, nameGroups
    if lower and Catalog and type(Catalog.MergeVariantSource) == "function" then
        merged, nameGroups = {}, {}
    end
    for _, section in ipairs(EffectiveBrowseSections(opts)) do
        local entries = {}
        for _, spell in ipairs(section.spells or {}) do
            local id = spell.id or spell.spellID
            if id then
                local name = spell.name or GetSpellName(id) or (ns.L["Spell"] .. " " .. tostring(id))
                local displayID = BrowseDisplaySpellID(id, opts)
                if not lower
                    or ns.Helpers.FoldSearchUTF8(name):find(lower, 1, true)
                    or tostring(id):find(lower, 1, true)
                    or tostring(displayID):find(lower, 1, true) then
                    entries[#entries + 1] = {
                        id = id,
                        name = name,
                        icon = spell.icon,
                        harmful = spell.harmful,
                        displayID = displayID,
                    }
                    if merged then
                        local m = merged[id]
                        if not m then
                            m = { id = id, name = name, icon = spell.icon,
                                displayID = displayID }
                            merged[id] = m
                            local folded = ns.Helpers.FoldUTF8(name)
                            local group = nameGroups[folded]
                            if not group then
                                group = {}
                                nameGroups[folded] = group
                            end
                            group[#group + 1] = m
                        end
                        Catalog.MergeVariantSource(m, section.key, spell)
                    end
                end
            end
        end
        if #entries > 0 then
            matchedSections[#matchedSections + 1] = { name = section.name, entries = entries }
        end
    end

    -- Same-name variants (Benediction-style: talent entry, cast spell, the
    -- actual aura) cluster first, best evidence on top, so the player picks
    -- with information instead of guessing.
    local clusters = {}
    local clustered = {}
    if nameGroups then
        for _, group in pairs(nameGroups) do
            if #group >= 2 then
                table.sort(group, Catalog.CompareVariants)
                clusters[#clusters + 1] = group
                for _, m in ipairs(group) do clustered[m.id] = true end
            end
        end
        table.sort(clusters, function(a, b) return a[1].name < b[1].name end)
    end

    local model = {}
    local seen = {}
    local total = 0
    for _, group in ipairs(clusters) do
        local rows = {}
        for _, m in ipairs(group) do
            if total < BROWSE_TOTAL_LIMIT then
                seen[m.id] = true
                total = total + 1
                rows[#rows + 1] = m
            end
        end
        if #rows > 0 then
            model[#model + 1] = {
                name = string.format(ns.L["%s (%d IDs)"], group[1].name, #group),
                rows = rows,
                more = 0,
                addAll = (opts and opts.multiAdd) and group or nil,
            }
        end
    end
    for _, matched in ipairs(matchedSections) do
        local rows = {}
        local more = 0
        for _, entry in ipairs(matched.entries) do
            if not seen[entry.id] and not clustered[entry.id] then
                if (not lower and #rows >= BROWSE_SECTION_LIMIT)
                    or total >= BROWSE_TOTAL_LIMIT then
                    more = more + 1
                else
                    seen[entry.id] = true
                    total = total + 1
                    rows[#rows + 1] = entry
                end
            end
        end
        if #rows > 0 then
            model[#model + 1] = { name = matched.name, rows = rows, more = more }
        end
    end

    -- Nothing matched: the client can still resolve exact names of loaded
    -- spells the sections don't carry.
    if total == 0 and lower then
        local match = Catalog and type(Catalog.ExactNameMatch) == "function"
            and Catalog.ExactNameMatch(filter)
        if match then
            total = 1
            model[1] = { name = ns.L["Name Match"], rows = { {
                id = match.id,
                name = match.name,
                icon = match.icon,
                displayID = BrowseDisplaySpellID(match.id, opts),
            } }, more = 0 }
        end
    end

    -- Pass 2: render.
    local headerIndex, spellIndex = 0, 0
    local y = 0
    for _, section in ipairs(model) do
        headerIndex = headerIndex + 1
        local header = AcquireBrowseHeader(headerIndex)
        header:SetHeight(BROWSE_ROW_H)
        header:SetPoint("TOPLEFT", 0, y)
        header:SetPoint("RIGHT", popup._scrollChild, "RIGHT", 0, 0)
        header.text:SetText(section.name or "")
        y = y - BROWSE_ROW_H

        for _, entry in ipairs(section.rows) do
            spellIndex = spellIndex + 1
            local row = AcquireBrowseSpellRow(spellIndex)
            row:SetHeight(BROWSE_ROW_H)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", popup._scrollChild, "RIGHT", 0, 0)
            row.spellId = entry.id
            row.icon:SetTexture(entry.icon or GetSpellIcon(entry.id))
            local idLabel = tostring(entry.id)
            if entry.displayID ~= entry.id then
                idLabel = idLabel .. " -> " .. ns.L["Aura"] .. " " .. tostring(entry.displayID)
            end
            row.text:SetText(entry.name .. "  |cFF888888(" .. idLabel .. ")|r"
                .. BrowseBadge(entry))
            local selected = opts and type(opts.isSelected) == "function" and opts.isSelected(entry.id)
            if selected then
                row.bg:SetColorTexture(accent[1], accent[2], accent[3], 0.12)
                row.text:SetTextColor(accent[1], accent[2], accent[3], 1)
            else
                row.bg:SetColorTexture(1, 1, 1, 0)
                row.text:SetTextColor(text[1], text[2], text[3], 1)
            end
            y = y - BROWSE_ROW_H
        end

        if section.addAll then
            -- The safe pick when unsure: track every variant; IDs that never
            -- occur simply never match.
            local group = section.addAll
            spellIndex = spellIndex + 1
            local row = AcquireBrowseSpellRow(spellIndex)
            row:SetHeight(BROWSE_ROW_H)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", popup._scrollChild, "RIGHT", 0, 0)
            row.spellId = nil
            row.icon:SetTexture(nil)
            row.bg:SetColorTexture(1, 1, 1, 0)
            row.text:SetText(string.format(ns.L["+ Add all %d variants"], #group))
            row.text:SetTextColor(accent[1], accent[2], accent[3], 0.9)
            row.customClick = function()
                local o = browse.opts
                if not (o and type(o.onToggle) == "function") then return end
                browse.dirty = true
                for _, m in ipairs(group) do
                    if not (type(o.isSelected) == "function" and o.isSelected(m.id)) then
                        o.onToggle(m.id)
                    end
                end
                RebuildBrowseRows(browse.popup._search:GetText())
            end
            y = y - BROWSE_ROW_H
        end

        if section.more > 0 then
            headerIndex = headerIndex + 1
            local hint = AcquireBrowseHeader(headerIndex)
            hint:SetHeight(BROWSE_ROW_H)
            hint:SetPoint("TOPLEFT", 0, y)
            hint:SetPoint("RIGHT", popup._scrollChild, "RIGHT", 0, 0)
            hint.text:SetText("|cFF888888"
                .. string.format(ns.L["+ %d more - type to search"], section.more) .. "|r")
            y = y - BROWSE_ROW_H
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
    -- Fresh open: rebuild the dynamic catalog so Active Auras reflects now.
    local Catalog = ns.QUI_AuraSpellCatalog
    if Catalog and type(Catalog.InvalidateCache) == "function" then
        Catalog.InvalidateCache()
    end
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
