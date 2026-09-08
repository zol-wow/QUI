-- luacheck: globals CreateFrame UIParent Enum MenuUtil C_DamageMeter InCombatLockdown GetCursorPosition GameTooltip
local _, ns = ...

local DM = ns.QUI_DamageMeter
if not DM then return end

local Data = DM.Data
local WindowManager = DM.WindowManager
local Breakout = {}
Breakout.__index = Breakout
DM.Breakout = Breakout

local DEFAULT_WIDTH = 1100
local DEFAULT_HEIGHT = 640
local MIN_WIDTH = 780
local MIN_HEIGHT = 420
local HEADER_H = 28
local PAD = 8
local GAP = 6
local SECTION_HEADER_H = 22
local PLAYER_ROWS = 40
local SEGMENT_ROWS = 22
local SPELL_ROWS = 40
local TARGET_ROWS = 20
local COMPARE_ROWS = 40
local MIN_LEFT_W = 170
local MIN_MIDDLE_W = 320
local MIN_RIGHT_W = 260
local MIN_TOP_H = 140
local DEFAULT_LAYOUT = {
    width = DEFAULT_WIDTH,
    height = DEFAULT_HEIGHT,
    leftWidth = 220,
    middleWidth = 500,
    playersHeight = 360,
    spellsHeight = 390,
}

local function GetSettings()
    local core = _G.QUI
    local profile = core and core.db and core.db.profile
    local meter = profile and profile.damageMeter
    return meter and meter.native
end

local function GetLayout()
    local settings = GetSettings()
    if not settings then return DEFAULT_LAYOUT end
    settings.breakoutLayout = settings.breakoutLayout or {}
    local layout = settings.breakoutLayout
    for key, value in pairs(DEFAULT_LAYOUT) do
        if type(layout[key]) ~= "number" then layout[key] = value end
    end
    return layout
end

local function IsSecret(value)
    return ns.Helpers and ns.Helpers.IsSecretValue and ns.Helpers.IsSecretValue(value)
end

local function IsCombatDataRestricted()
    return Data._inCombat or (InCombatLockdown and InCombatLockdown()) or false
end

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function SetSectionEmpty(section, text)
    for i = 1, #section.rows do
        section.rows[i]:Hide()
        section.rows[i]._source = nil
        section.rows[i]._segment = nil
        section.rows[i]._spellID = nil
        section.rows[i]._target = nil
    end
    section.content:SetHeight(1)
    section.scroll:SetVerticalScroll(0)
    section.empty:SetText(text or ns.L["No data available"])
    section.empty:Show()
end

local function ShowSectionRows(section, count, rowHeight, rowGap)
    section.empty:Hide()
    for i = count + 1, #section.rows do
        section.rows[i]:Hide()
        section.rows[i]._source = nil
        section.rows[i]._segment = nil
        section.rows[i]._spellID = nil
        section.rows[i]._target = nil
    end
    local contentHeight = count > 0 and count * rowHeight + (count - 1) * rowGap or 1
    section.content:SetHeight(math.max(1, contentHeight))
    local maxScroll = math.max(0, contentHeight - section.scroll:GetHeight())
    local current = section.scroll:GetVerticalScroll() or 0
    if current > maxScroll then section.scroll:SetVerticalScroll(maxScroll) end
end

local function SessionSelected(self, segment)
    if segment.sessionID ~= nil then return self.sessionID == segment.sessionID end
    return self.sessionID == nil and self.sessionType == segment.sessionType
end

local function ReadableGUID(source)
    local guid = source and source.sourceGUID
    if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

local function SameSource(left, right)
    if not (left and right) then return false end
    if left.isLocalPlayer == true and right.isLocalPlayer == true then return true end
    local leftGUID = ReadableGUID(left)
    local rightGUID = ReadableGUID(right)
    return leftGUID ~= nil and rightGUID ~= nil and leftGUID == rightGUID
end

local function SameTarget(left, right)
    if not (left and right) then return false end
    local leftGUID = ReadableGUID(left)
    local rightGUID = ReadableGUID(right)
    if leftGUID ~= nil or rightGUID ~= nil then return leftGUID ~= nil and leftGUID == rightGUID end
    local leftID = left.sourceCreatureID
    local rightID = right.sourceCreatureID
    return not IsSecret(leftID) and leftID ~= nil and leftID == rightID
end

local function FindMatchingSource(selected, sources, fallbackToFirst)
    if not selected then return fallbackToFirst ~= false and sources and sources[1] or nil end
    for _, source in ipairs(sources or {}) do
        if source == selected or SameSource(selected, source) then return source end
    end
    local specIconID = selected.specIconID
    if type(specIconID) ~= "number" or specIconID <= 0 then
        return fallbackToFirst ~= false and sources and sources[1] or nil
    end
    local match
    for _, source in ipairs(sources or {}) do
        if source.specIconID == specIconID then
            if match then return selected end
            match = source
        end
    end
    return match or (fallbackToFirst ~= false and sources and sources[1] or nil)
end

local function BuildSpellMap(view)
    local result = {}
    for _, spell in ipairs((view and view.spells) or {}) do
        local spellID = spell.spellID
        local amount = spell.totalAmount
        if not IsSecret(spellID) and type(spellID) == "number"
            and not IsSecret(amount) and type(amount) == "number" then
            result[spellID] = amount
        end
    end
    return result
end

function Breakout:_RowMetrics()
    local windowID = self.ownerWindow and self.ownerWindow.windowID
    local rowHeight = DM.ResolveAppearance(windowID, "barHeight") or 18
    local rowGap = DM.ResolveAppearance(windowID, "barSpacing") or 2
    return rowHeight, rowGap
end

function Breakout:_LayoutRows(section)
    local rowHeight, rowGap = self:_RowMetrics()
    for i, row in ipairs(section.rows) do
        row:ClearAllPoints()
        row:SetHeight(rowHeight)
        row:SetPoint("LEFT", section.content, "LEFT", 0, 0)
        row:SetPoint("RIGHT", section.content, "RIGHT", 0, 0)
        if i == 1 then
            row:SetPoint("TOP", section.content, "TOP", 0, 0)
        else
            row:SetPoint("TOP", section.rows[i - 1], "BOTTOM", 0, -rowGap)
        end
        row.Icon:SetSize(rowHeight, rowHeight)
    end
end

function Breakout:_ShowSpellTooltip(row)
    local settings = GetSettings()
    if settings and settings.showSpellTooltips == false then return end
    local spellID = row._spellID
    if IsSecret(spellID) or type(spellID) ~= "number" or spellID <= 0 then return end
    if not GameTooltip or GameTooltip:IsForbidden() then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(spellID)
    GameTooltip:Show()
end

function Breakout:_CreateSection(key, title, rowCount)
    local frame = CreateFrame("Frame", nil, self.frame)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then self:Close() end
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.025, 0.025, 0.025, 0.94)
    if ns.UIKit and ns.UIKit.CreateBackdropBorder then
        frame.border = ns.UIKit.CreateBackdropBorder(frame, 1, 0.12, 0.12, 0.12, 1)
    end

    local titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
    titleLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -4)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetText(title)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -SECTION_HEADER_H)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then content:SetWidth(width) end
    end)
    scroll:SetScript("OnMouseWheel", function(scrollFrame, delta)
        local rowHeight, rowGap = self:_RowMetrics()
        local maxScroll = math.max(0, content:GetHeight() - scrollFrame:GetHeight())
        local nextOffset = Clamp((scrollFrame:GetVerticalScroll() or 0)
            - delta * (rowHeight + rowGap) * 2, 0, maxScroll)
        scrollFrame:SetVerticalScroll(nextOffset)
    end)

    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOP", content, "TOP", 0, -14)
    empty:SetTextColor(0.65, 0.65, 0.65)
    empty:SetText(ns.L["No data available"])
    empty:Hide()

    local section = {
        key = key,
        frame = frame,
        title = titleLabel,
        scroll = scroll,
        content = content,
        empty = empty,
        rows = {},
    }
    local rowHeight = 18
    for i = 1, rowCount do
        local row = CreateFrame("Button", nil, content)
        DM.AttachRowVisuals(row, rowHeight)
        row:EnableMouse(true)
        if row.RegisterForClicks then row:RegisterForClicks("AnyUp") end
        row:SetScript("OnClick", function(rowSelf, button)
            self:_OnRowClick(section, rowSelf, button)
        end)
        if key == "players" then
            row:SetScript("OnEnter", function(rowSelf)
                self.sourceRenderer:_ShowPlayerRowHover(rowSelf, false)
            end)
            row:SetScript("OnLeave", function(rowSelf)
                self.sourceRenderer:_HidePlayerRowHover(rowSelf, false)
            end)
        elseif key == "spells" or key == "comparison" then
            row:SetScript("OnEnter", function(rowSelf) self:_ShowSpellTooltip(rowSelf) end)
            row:SetScript("OnLeave", function(rowSelf)
                if GameTooltip and not GameTooltip:IsForbidden()
                    and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == rowSelf) then
                    GameTooltip:Hide()
                end
            end)
        end
        row:Hide()
        section.rows[i] = row
    end
    self.sections[key] = section
    return section
end

function Breakout:_ClampLayout()
    local layout = self.layout
    local contentWidth = self.frame:GetWidth() - PAD * 2
    local contentHeight = self.frame:GetHeight() - HEADER_H - PAD * 2
    layout.leftWidth = Clamp(layout.leftWidth, MIN_LEFT_W,
        contentWidth - GAP * 2 - MIN_MIDDLE_W - MIN_RIGHT_W)
    layout.middleWidth = Clamp(layout.middleWidth, MIN_MIDDLE_W,
        contentWidth - GAP * 2 - layout.leftWidth - MIN_RIGHT_W)
    layout.playersHeight = Clamp(layout.playersHeight, MIN_TOP_H, contentHeight - GAP - MIN_TOP_H)
    layout.spellsHeight = Clamp(layout.spellsHeight, MIN_TOP_H, contentHeight - GAP - MIN_TOP_H)
end

function Breakout:_LayoutSections()
    self:_ClampLayout()
    local layout = self.layout
    local width = self.frame:GetWidth()
    local contentHeight = self.frame:GetHeight() - HEADER_H - PAD * 2
    local leftX = PAD
    local middleX = leftX + layout.leftWidth + GAP
    local rightX = middleX + layout.middleWidth + GAP
    local rightWidth = width - PAD - rightX
    local topY = -(HEADER_H + PAD)

    local players = self.sections.players.frame
    players:ClearAllPoints()
    players:SetPoint("TOPLEFT", self.frame, "TOPLEFT", leftX, topY)
    players:SetSize(layout.leftWidth, layout.playersHeight)

    local segments = self.sections.segments.frame
    segments:ClearAllPoints()
    segments:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", leftX, PAD)
    segments:SetSize(layout.leftWidth, contentHeight - layout.playersHeight - GAP)

    local spells = self.sections.spells.frame
    spells:ClearAllPoints()
    spells:SetPoint("TOPLEFT", self.frame, "TOPLEFT", middleX, topY)
    spells:SetSize(layout.middleWidth, layout.spellsHeight)

    local targets = self.sections.targets.frame
    targets:ClearAllPoints()
    targets:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", middleX, PAD)
    targets:SetSize(layout.middleWidth, contentHeight - layout.spellsHeight - GAP)

    local comparison = self.sections.comparison.frame
    comparison:ClearAllPoints()
    comparison:SetPoint("TOPLEFT", self.frame, "TOPLEFT", rightX, topY)
    comparison:SetSize(rightWidth, contentHeight)

    self.splitters.left:ClearAllPoints()
    self.splitters.left:SetPoint("TOPLEFT", self.frame, "TOPLEFT", leftX + layout.leftWidth, topY)
    self.splitters.left:SetSize(GAP, contentHeight)
    self.splitters.middle:ClearAllPoints()
    self.splitters.middle:SetPoint("TOPLEFT", self.frame, "TOPLEFT", middleX + layout.middleWidth, topY)
    self.splitters.middle:SetSize(GAP, contentHeight)
    self.splitters.players:ClearAllPoints()
    self.splitters.players:SetPoint("TOPLEFT", self.frame, "TOPLEFT", leftX,
        topY - layout.playersHeight)
    self.splitters.players:SetSize(layout.leftWidth, GAP)
    self.splitters.spells:ClearAllPoints()
    self.splitters.spells:SetPoint("TOPLEFT", self.frame, "TOPLEFT", middleX,
        topY - layout.spellsHeight)
    self.splitters.spells:SetSize(layout.middleWidth, GAP)

    for _, section in pairs(self.sections) do self:_LayoutRows(section) end
    self._layoutRowHeight, self._layoutRowGap = self:_RowMetrics()
end

function Breakout:_UpdateSplitter(kind)
    if not GetCursorPosition then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = self.frame:GetEffectiveScale() or 1
    local left = self.frame:GetLeft()
    local bottom = self.frame:GetBottom()
    if not (left and bottom) then return end
    local x = cursorX / scale - left
    local y = cursorY / scale - bottom
    local contentTop = self.frame:GetHeight() - HEADER_H - PAD
    if kind == "left" then
        self.layout.leftWidth = x - PAD
    elseif kind == "middle" then
        self.layout.middleWidth = x - PAD - self.layout.leftWidth - GAP
    elseif kind == "players" then
        self.layout.playersHeight = contentTop - y
    elseif kind == "spells" then
        self.layout.spellsHeight = contentTop - y
    end
    self:_LayoutSections()
end

function Breakout:_CreateSplitter(kind)
    local splitter = CreateFrame("Frame", nil, self.frame)
    splitter:EnableMouse(true)
    splitter:RegisterForDrag("LeftButton")
    local highlight = splitter:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(splitter)
    local r, g, b = DM.GetAccentColor()
    highlight:SetColorTexture(r, g, b, 0.45)
    splitter:SetScript("OnDragStart", function(selfSplitter)
        selfSplitter:SetScript("OnUpdate", function() self:_UpdateSplitter(kind) end)
    end)
    splitter:SetScript("OnDragStop", function(selfSplitter)
        selfSplitter:SetScript("OnUpdate", nil)
        self:_UpdateSplitter(kind)
    end)
    self.splitters[kind] = splitter
end

function Breakout:_SetRendererContext()
    local context = self.contextWindow
    context.windowID = self.ownerWindow and self.ownerWindow.windowID
    context.damageMeterType = self.damageMeterType
    context.sessionType = self.sessionType
    context.sessionID = self.sessionID
    self.sourceRenderer.windowID = context.windowID
    self.sourceRenderer.damageMeterType = self.damageMeterType
    self.sourceRenderer.sessionType = self.sessionType
    self.sourceRenderer.sessionID = self.sessionID
    self.detailRenderer.parentWindow = context
    self.detailRenderer.parentWindowID = context.windowID
end

function Breakout:_ResolveSelectedSource(view)
    local previousSource = self.source
    self.source = FindMatchingSource(previousSource, view.sources)
    if previousSource and not SameSource(previousSource, self.source) then
        self.selectedTarget = nil
    end
    local inCombat = IsCombatDataRestricted()
    self.sourceGUID, self.sourceCreatureID, self.selectorKind =
        Data:ResolveSourceSelector(self.source, self.sessionType, self.sessionID, inCombat)
    self.restricted = self.source ~= nil
        and self.sourceGUID == nil and self.sourceCreatureID == nil
        and self.damageMeterType ~= (Enum and Enum.DamageMeterType and Enum.DamageMeterType.Deaths)
end

function Breakout:_RefreshPlayers(view)
    local section = self.sections.players
    local rowHeight, rowGap = self:_RowMetrics()
    local count = math.min(#(view.sources or {}), #section.rows)
    if count == 0 then
        SetSectionEmpty(section)
        return
    end
    for i = 1, count do
        local row = section.rows[i]
        row.Icon:Show()
        self.sourceRenderer:_SetRowSource(row, view.sources[i], view.maxAmount)
        row._source = view.sources[i]
        row.Bar:SetAlpha(SameSource(self.source, view.sources[i]) and 1 or 0.72)
        row:Show()
    end
    ShowSectionRows(section, count, rowHeight, rowGap)
end

function Breakout:_GetAvailableSessions()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return {} end
    local ok, sessions = ns.SafeCall("best-effort-style", C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" then return {} end
    return DM.TakeTrailingSessions(sessions, 20)
end

function Breakout:_SetSegmentRow(row, segment, selected)
    DM.ApplyRowBackgroundVisibility(row, self.ownerWindow and self.ownerWindow.windowID)
    row.Icon:Hide()
    row.Bar:ClearAllPoints()
    row.Bar:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.Bar:SetPoint("TOP", row, "TOP", 0, 0)
    row.Bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    row.Bar:SetMinMaxValues(0, 1)
    row.Bar:SetValue(selected and 1 or 0)
    local r, g, b = DM.GetAccentColor()
    row.Bar:SetStatusBarColor(r, g, b, selected and 0.55 or 0.18)
    row.Name:SetText(segment.label)
    row.Name:SetTextColor(1, 1, 1, 1)
    row.Value:SetText(segment.duration or "")
    row.Value:SetTextColor(0.8, 0.8, 0.8, 1)
    row._segment = segment
end

function Breakout:_CacheSegmentEntries()
    local S = Enum and Enum.DamageMeterSessionType
    local currentType = (S and S.Current) or 1
    local overallType = (S and S.Overall) or 0
    local entries = self.segmentEntries
    local current = entries[1]
    current.sessionType = currentType
    current.sessionID = nil
    current.label = DM.LabelForSession(currentType)
    current.duration = nil
    entries[1] = current
    local overall = entries[2]
    overall.sessionType = overallType
    overall.sessionID = nil
    overall.label = DM.LabelForSession(overallType)
    overall.duration = nil
    entries[2] = overall
    local count = 2
    for i = #self.availableSessions, 1, -1 do
        local session = self.availableSessions[i]
        if count >= SEGMENT_ROWS then break end
        count = count + 1
        local entry = entries[count]
        entry.sessionType = nil
        local sessionID = session.sessionID
        local name = session.name
        local durationSeconds = session.durationSeconds
        local cacheable = not IsSecret(sessionID) and not IsSecret(name) and not IsSecret(durationSeconds)
        if not cacheable or entry._sessionID ~= sessionID or entry._name ~= name
            or entry._durationSeconds ~= durationSeconds then
            entry.label, entry.duration = DM.BuildPreviousSessionLabel(session, true)
            entry._sessionID = cacheable and sessionID or nil
            entry._name = cacheable and name or nil
            entry._durationSeconds = cacheable and durationSeconds or nil
        end
        entry.sessionID = sessionID
        entries[count] = entry
    end
    self.segmentEntryCount = count
end

function Breakout:_RefreshSegments()
    local section = self.sections.segments
    local rowHeight, rowGap = self:_RowMetrics()
    local entries = self.segmentEntries
    local count = self.segmentEntryCount
    for i = 1, count do
        local entry = entries[i]
        self:_SetSegmentRow(section.rows[i], entry, SessionSelected(self, entry))
        section.rows[i]:Show()
    end
    ShowSectionRows(section, count, rowHeight, rowGap)
end

function Breakout:_GetBreakdownView(sourceGUID, sourceCreatureID, sessionID, reuse, limit)
    local T = Enum and Enum.DamageMeterType
    if T and (self.damageMeterType == T.HealingDone or self.damageMeterType == T.Hps) then
        local settings = GetSettings()
        if settings and settings.combineAbsorbsIntoHealing then
            return Data:GetCombinedHealingBreakdown(
                self.sessionType, sourceGUID, sourceCreatureID, sessionID, reuse, limit)
        end
    end
    return Data:GetBreakdownView(
        self.sessionType, self.damageMeterType, sourceGUID, sourceCreatureID, sessionID, reuse, limit)
end

function Breakout:_RefreshSpells()
    local section = self.sections.spells
    section.title:SetText(ns.L["Spells"])
    local rowHeight, rowGap = self:_RowMetrics()
    local T = Enum and Enum.DamageMeterType
    local deathsType = T and T.Deaths
    local enemyType = T and T.EnemyDamageTaken
    local reusableSpellView = self.currentSpellView
    self.currentSpellView = nil

    if self.restricted then
        SetSectionEmpty(section, ns.L["Breakdown unavailable during combat"])
        return
    end

    if deathsType and self.damageMeterType == deathsType then
        local events, maxHealth = DM.GetDeathRecapRows(self.source and self.source.deathRecapID)
        local count = math.min(#events, #section.rows)
        if count == 0 then
            SetSectionEmpty(section, ns.L["No death recap available"])
            return
        end
        local deathEvent = events[#events]
        local deathTime = deathEvent and deathEvent.timestamp
        for i = 1, count do
            local row = section.rows[i]
            row.Icon:Show()
            self.detailRenderer:_SetDeathRow(row, events[i], maxHealth, deathTime)
            row:Show()
        end
        ShowSectionRows(section, count, rowHeight, rowGap)
        return
    end

    if enemyType and self.damageMeterType == enemyType then
        local attackers = Data:GetEnemyAttackers(self.sessionType,
            self.sourceGUID, self.sourceCreatureID, self.sessionID)
        local count = math.min(#attackers, #section.rows)
        if count == 0 then SetSectionEmpty(section); return end
        local maxAmount = attackers[1].totalAmount
        for i = 1, count do
            local row = section.rows[i]
            row.Icon:Show()
            row._spellID = nil
            self.detailRenderer:_SetTargetRow(row, attackers[i], maxAmount)
            row:Show()
        end
        ShowSectionRows(section, count, rowHeight, rowGap)
        return
    end

    local view
    if self.selectedTarget then
        local targetName = self.selectedTarget.name
        if IsSecret(targetName) or type(targetName) ~= "string" then
            targetName = ns.L["Targets"]
        else
            targetName = DM.ShortenName(targetName)
        end
        section.title:SetText(ns.L["Spells"] .. ": " .. targetName)
        view = Data:GetPlayerTargetBreakdown(
            self.sessionType, self.source and self.source.name,
            self.selectedTarget.sourceGUID, self.selectedTarget.sourceCreatureID,
            self.sessionID, reusableSpellView, SPELL_ROWS)
    else
        view = self:_GetBreakdownView(self.sourceGUID, self.sourceCreatureID,
            self.sessionID, reusableSpellView, SPELL_ROWS)
    end
    self.currentSpellView = view
    local count = math.min(#(view.spells or {}), #section.rows)
    if count == 0 then SetSectionEmpty(section); return end
    for i = 1, count do
        local row = section.rows[i]
        row.Icon:Show()
        self.detailRenderer:_SetSpellRow(row, view.spells[i], view.maxAmount, view.totalAmount)
        row:Show()
    end
    ShowSectionRows(section, count, rowHeight, rowGap)
end

function Breakout:_RefreshTargets()
    local section = self.sections.targets
    local rowHeight, rowGap = self:_RowMetrics()
    local T = Enum and Enum.DamageMeterType
    if self.restricted or IsCombatDataRestricted() or not T
        or self.damageMeterType == T.Deaths or self.damageMeterType == T.EnemyDamageTaken then
        self.selectedTarget = nil
        SetSectionEmpty(section, self.restricted and ns.L["Breakdown unavailable during combat"] or nil)
        return
    end

    local targets
    if self.damageMeterType == T.DamageDone or self.damageMeterType == T.Dps then
        targets = Data:GetPlayerTargets(self.sessionType, self.source and self.source.name, self.sessionID)
    end
    local count = math.min(#(targets or {}), #section.rows)
    if count == 0 then
        self.selectedTarget = nil
        SetSectionEmpty(section)
        return
    end
    if self.selectedTarget then
        local selected
        for i = 1, count do
            local target = targets[i]
            if SameTarget(self.selectedTarget, target) then selected = target; break end
        end
        self.selectedTarget = selected
    end
    local maxAmount = targets[1].totalAmount
    for i = 1, count do
        local row = section.rows[i]
        row.Icon:Show()
        self.detailRenderer:_SetTargetRow(row, targets[i], maxAmount)
        row.Bar:SetAlpha((not self.selectedTarget or SameTarget(self.selectedTarget, targets[i])) and 1 or 0.72)
        row:Show()
    end
    ShowSectionRows(section, count, rowHeight, rowGap)
end

function Breakout:_AddComparisonDataset(datasets, label, source, sessionID)
    if #datasets >= 3 or not source then return end
    local sourceGUID, sourceCreatureID = Data:ResolveSourceSelector(
        source, nil, sessionID, IsCombatDataRestricted())
    if sourceGUID == nil and sourceCreatureID == nil then return end
    local view = self:_GetBreakdownView(sourceGUID, sourceCreatureID, sessionID)
    if not view or not view.spells or #view.spells == 0 then return end
    datasets[#datasets + 1] = { label = label, spells = BuildSpellMap(view) }
end

function Breakout:_BuildComparisonDatasets()
    local datasets = {}
    for i = #self.availableSessions, 1, -1 do
        if #datasets >= 3 then break end
        local session = self.availableSessions[i]
        if session.sessionID ~= self.sessionID then
            local view = Data:GetView(nil, self.damageMeterType, session.sessionID)
            local selected = FindMatchingSource(self.source, view.sources, false)
            self:_AddComparisonDataset(datasets,
                DM.BuildPreviousSessionLabel(session), selected, session.sessionID)
            if #datasets == 1 and self.source and type(self.source.specIconID) == "number" then
                for _, candidate in ipairs(view.sources or {}) do
                    if #datasets >= 3 then break end
                    if candidate.specIconID == self.source.specIconID
                        and not SameSource(candidate, selected)
                        and not IsSecret(candidate.name) then
                        self:_AddComparisonDataset(datasets,
                            DM.ShortenName(candidate.name) or "Player", candidate, session.sessionID)
                    end
                end
            end
        end
    end
    return datasets
end

function Breakout:_RefreshComparison()
    local section = self.sections.comparison
    local rowHeight, rowGap = self:_RowMetrics()
    local view = self.currentSpellView
    if self.selectedTarget or self.restricted or not view or not view.spells or #view.spells == 0 then
        section.title:SetText(ns.L["Comparison"])
        SetSectionEmpty(section, self.restricted and ns.L["Breakdown unavailable during combat"] or nil)
        return
    end

    local primaryLabel = self.sessionID ~= nil
        and (self.sessionLabel or tostring(self.sessionID)) or DM.LabelForSession(self.sessionType)
    if self.comparisonPrimaryLabel ~= primaryLabel then
        self.comparisonPrimaryLabel = primaryLabel
        self.comparisonPrimaryTitle = ns.L["Comparison"] .. ": " .. primaryLabel
    end
    local datasets
    if IsCombatDataRestricted() then
        section.title:SetText(self.comparisonPrimaryTitle)
    else
        datasets = self:_BuildComparisonDatasets()
        local labels = { primaryLabel }
        for _, dataset in ipairs(datasets) do labels[#labels + 1] = dataset.label end
        section.title:SetText(ns.L["Comparison"] .. ": " .. table.concat(labels, " / "))
    end

    local count = math.min(#view.spells, #section.rows)
    local visible = 0
    for i = 1, count do
        local spell = view.spells[i]
        local spellID = spell.spellID
        local amount = spell.totalAmount
        if not IsSecret(spellID) and type(spellID) == "number"
            and not IsSecret(amount) and type(amount) == "number" then
            visible = visible + 1
            local row = section.rows[visible]
            row.Icon:Show()
            self.detailRenderer:_SetSpellRow(row, spell, view.maxAmount, view.totalAmount)
            if datasets ~= nil then
                if #datasets == 0 then
                    row.Value:SetText(DM.FormatNumber(amount, "compact"))
                else
                    local values = { DM.FormatNumber(amount, "compact") }
                    for _, dataset in ipairs(datasets) do
                        local previous = dataset.spells[spellID]
                        values[#values + 1] = previous and DM.FormatNumber(previous, "compact") or "-"
                    end
                    row.Value:SetText(table.concat(values, " / "))
                end
            end
            row:Show()
        end
    end
    if visible == 0 then SetSectionEmpty(section); return end
    ShowSectionRows(section, visible, rowHeight, rowGap)
end

function Breakout:_OnRowClick(section, row, button)
    if button == "RightButton" then self:Close(); return end
    if section.key == "players" and row._source then
        self.source = row._source
        self.selectedTarget = nil
        self:Refresh()
    elseif section.key == "segments" and row._segment then
        local segment = row._segment
        self.sessionType = segment.sessionType
        self.sessionID = segment.sessionID
        self.sessionLabel = segment.sessionID and segment.label or nil
        self.selectedTarget = nil
        self:Refresh()
    elseif section.key == "targets" and row._target then
        if SameTarget(self.selectedTarget, row._target) then
            self.selectedTarget = nil
        else
            self.selectedTarget = row._target
        end
        self:Refresh()
    end
end

function Breakout:_OpenTypeMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(self.TypeButton, function(_, root)
        root:CreateTitle(ns.L["Meter Type"])
        for _, meterType in ipairs(DM.MeterTypes or {}) do
            local value = meterType
            root:CreateRadio(DM.LabelForType(value),
                function() return self.damageMeterType == value end,
                function()
                    self.damageMeterType = value
                    self.selectedTarget = nil
                    self:Refresh()
                end)
        end
    end)
end

function Breakout:_ClearContext()
    self.ownerWindow = nil
    self.source = nil
    self.sourceGUID = nil
    self.sourceCreatureID = nil
    self.selectorKind = nil
    self.sessionType = nil
    self.sessionID = nil
    self.sessionLabel = nil
    self.damageMeterType = nil
    self.restricted = nil
    self.currentSpellView = nil
    self.selectedTarget = nil
end

function Breakout:Open(ownerWindow, source, sourceGUID, sourceCreatureID, restricted)
    if not (ownerWindow and source) then return false end
    self.ownerWindow = ownerWindow
    self.source = source
    self.sourceGUID = sourceGUID
    self.sourceCreatureID = sourceCreatureID
    self.restricted = restricted == true
    self.sessionType = ownerWindow.sessionType
    self.sessionID = ownerWindow.sessionID
    self.sessionLabel = ownerWindow.sessionLabel
    self.damageMeterType = ownerWindow.damageMeterType
    self.selectedTarget = nil
    self.layout = GetLayout()
    self.frame:SetSize(self.layout.width, self.layout.height)
    self:_LayoutSections()
    self.frame:Show()
    self:Refresh()
    return true
end

function Breakout:Refresh()
    if not self.frame:IsShown() or not self.ownerWindow then return false end
    if WindowManager.windows[self.ownerWindow.windowID] ~= self.ownerWindow then
        self:Close()
        return false
    end

    local layout = GetLayout()
    local rowHeight, rowGap = self:_RowMetrics()
    if self.layout ~= layout or self._layoutRowHeight ~= rowHeight or self._layoutRowGap ~= rowGap then
        self.layout = layout
        self.frame:SetSize(layout.width, layout.height)
        self:_LayoutSections()
    end

    if not IsCombatDataRestricted() then
        self.availableSessions = self:_GetAvailableSessions()
        self:_CacheSegmentEntries()
    end
    self:_SetRendererContext()
    local view
    local T = Enum and Enum.DamageMeterType
    local settings = GetSettings()
    if T and (self.damageMeterType == T.HealingDone or self.damageMeterType == T.Hps)
        and settings and settings.combineAbsorbsIntoHealing then
        view = Data:GetCombinedHealingView(self.sessionType, self.sessionID)
    else
        view = Data:GetView(self.sessionType, self.damageMeterType, self.sessionID)
    end
    self:_ResolveSelectedSource(view)
    self:_SetRendererContext()

    local sourceName = self.source and DM.ShortenName(self.source.name)
    if not IsSecret(sourceName) and sourceName == nil then sourceName = "?" end
    self.TitleLabel:SetFormattedText("%s - %s", DM.LabelForType(self.damageMeterType), sourceName)
    self.TypeButton:SetText(DM.LabelForType(self.damageMeterType))
    self:_RefreshPlayers(view)
    self:_RefreshSegments()
    self:_RefreshTargets()
    self:_RefreshSpells()
    self:_RefreshComparison()
    return true
end

function Breakout:Close()
    if self.frame:IsShown() then self.frame:Hide() else self:_ClearContext() end
end

function Breakout:IsShown()
    return self.frame and self.frame:IsShown() or false
end

function Breakout.New()
    local self = setmetatable({
        sections = {},
        splitters = {},
        layout = GetLayout(),
        availableSessions = {},
        segmentEntries = {},
        contextWindow = {},
        sourceRenderer = setmetatable({}, DM.Window),
        detailRenderer = setmetatable({}, DM.Breakdown),
    }, Breakout)
    for i = 1, SEGMENT_ROWS do self.segmentEntries[i] = {} end
    self:_CacheSegmentEntries()

    local frame = CreateFrame("Frame", "QUI_DamageMeterBreakout", UIParent)
    frame:SetSize(self.layout.width, self.layout.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then self:Close() end
    end)
    local interaction
    local function FinishInteraction()
        if not interaction then return end
        interaction = nil
        frame:StopMovingOrSizing()
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then FinishInteraction() end
    end)
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnHide", function()
        FinishInteraction()
        self:_ClearContext()
    end)
    frame:Hide()
    self.frame = frame

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.01, 0.01, 0.01, 0.96)
    self.backdrop = bg
    if ns.UIKit and ns.UIKit.CreateBackdropBorder then
        self.border = ns.UIKit.CreateBackdropBorder(frame, 1, DM.GetAccentColor())
    end

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if interaction or IsCombatDataRestricted() then return end
        frame:StartMoving()
        interaction = "move"
    end)
    header:SetScript("OnDragStop", function()
        if interaction == "move" then FinishInteraction() end
    end)
    self.header = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -230, 0)
    title:SetJustifyH("LEFT")
    title:SetText("")
    self.TitleLabel = title

    self.TypeButton = ns.SkinBase.CreateButton(header, {
        text = ns.L["Damage Done"],
        width = 180,
        height = HEADER_H - 6,
        onClick = function() self:_OpenTypeMenu() end,
    })
    self.TypeButton:SetPoint("RIGHT", header, "RIGHT", -32, 0)

    if ns.UIKit and ns.UIKit.CreateCloseButton then
        self.CloseButton = ns.UIKit.CreateCloseButton(header, {
            size = HEADER_H - 4,
            point = "RIGHT",
            x = -2,
            onClick = function() self:Close() end,
        })
    end

    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    resize:SetFrameLevel(frame:GetFrameLevel() + 10)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or interaction or IsCombatDataRestricted() then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        frame:StartSizing("BOTTOMRIGHT")
        interaction = "resize"
    end)
    resize:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and interaction == "resize" then FinishInteraction() end
    end)
    self.resize = resize

    self:_CreateSection("players", ns.L["Players"], PLAYER_ROWS)
    self:_CreateSection("segments", ns.L["Segments"], SEGMENT_ROWS)
    self:_CreateSection("spells", ns.L["Spells"], SPELL_ROWS)
    self:_CreateSection("targets", ns.L["Targets"], TARGET_ROWS)
    self:_CreateSection("comparison", ns.L["Comparison"], COMPARE_ROWS)
    self:_CreateSplitter("left")
    self:_CreateSplitter("middle")
    self:_CreateSplitter("players")
    self:_CreateSplitter("spells")
    self:_LayoutSections()
    frame:SetScript("OnSizeChanged", function(_, width, height)
        if not (width and height and self.sections.players) then return end
        self.layout.width = math.floor(width + 0.5)
        self.layout.height = math.floor(height + 0.5)
        self:_LayoutSections()
    end)

    local specialFrames = _G.UISpecialFrames
    if type(specialFrames) == "table" then
        local found = false
        for _, name in ipairs(specialFrames) do
            if name == "QUI_DamageMeterBreakout" then found = true; break end
        end
        if not found then table.insert(specialFrames, "QUI_DamageMeterBreakout") end
    end

    return self
end

function WindowManager:GetBreakout()
    if not self.breakout and IsCombatDataRestricted() then return nil end
    if not self.breakout then self.breakout = Breakout.New() end
    return self.breakout
end

function WindowManager:OpenBreakout(ownerWindow, source, sourceGUID, sourceCreatureID, restricted)
    local breakout = self:GetBreakout()
    return breakout and breakout:Open(
        ownerWindow, source, sourceGUID, sourceCreatureID, restricted) or false
end

function WindowManager:RefreshBreakout()
    local breakout = self.breakout
    if breakout and breakout:IsShown() then breakout:Refresh() end
end

function WindowManager:CloseBreakout()
    if self.breakout then self.breakout:Close() end
end

function WindowManager:CloseBreakoutForOwner(ownerWindow)
    local breakout = self.breakout
    if breakout and breakout.ownerWindow == ownerWindow then breakout:Close() end
end

if not IsCombatDataRestricted() then WindowManager:GetBreakout() end
