local ADDON_NAME, ns = ...

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local Module = {}
ns.QUI_UnitFramesCastbarPreview = Module

local Shared = ns.QUI_UnitFramesPreviewShared
local ANCHOR_MAP = Shared.ANCHOR_MAP
local ResolveStatusBarTexture = Shared.ResolveStatusBarTexture
local ResolveUnitFrameFont = Shared.ResolveUnitFrameFont

local ApplyHairlineBorder = Shared.ApplyHairlineBorder
local CreateHairlineBorder = Shared.CreateHairlineBorder

local ApplyTextAnchor = Shared.ApplyTextAnchor

local function ApplyIconAnchor(icon, bar, anchorKey, spacing)
    local anchor = ANCHOR_MAP[anchorKey] or "LEFT"
    spacing = spacing or 0
    icon:ClearAllPoints()
    if     anchor == "LEFT"        then icon:SetPoint("RIGHT",       bar, "LEFT",         -spacing,  0)
    elseif anchor == "RIGHT"       then icon:SetPoint("LEFT",        bar, "RIGHT",         spacing,  0)
    elseif anchor == "TOP"         then icon:SetPoint("BOTTOM",      bar, "TOP",                 0,  spacing)
    elseif anchor == "BOTTOM"      then icon:SetPoint("TOP",         bar, "BOTTOM",              0, -spacing)
    elseif anchor == "TOPLEFT"     then icon:SetPoint("BOTTOMRIGHT", bar, "TOPLEFT",      -spacing,  spacing)
    elseif anchor == "TOPRIGHT"    then icon:SetPoint("BOTTOMLEFT",  bar, "TOPRIGHT",      spacing,  spacing)
    elseif anchor == "BOTTOMLEFT"  then icon:SetPoint("TOPRIGHT",    bar, "BOTTOMLEFT",   -spacing, -spacing)
    elseif anchor == "BOTTOMRIGHT" then icon:SetPoint("TOPLEFT",     bar, "BOTTOMRIGHT",   spacing, -spacing)
    else                                icon:SetPoint("CENTER",      bar, "CENTER",              0,  0)
    end
end

local function ComputeBarScale(host, castDB)
    local iconAllowance = 0
    if castDB.showIcon then
        iconAllowance = (castDB.iconSize or 25) * (castDB.iconScale or 1) + 4
    end
    local hostW = math.max(((host and host:GetWidth()) or 0) - 40 - iconAllowance, 80)
    return math.min(1, hostW / (castDB.width or 250))
end

local CAST_PLAYER     = { kind = "cast",      duration = 2.5, spellName = ns.L["Frostbolt"],
                          spellIcon = "Interface\\Icons\\Spell_Frost_FrostBolt02" }
local CHANNEL_PLAYER  = { kind = "channel",   duration = 3.0, spellName = ns.L["Mind Flay"],
                          spellIcon = "Interface\\Icons\\Spell_Shadow_SiphonMana",
                          ticks = { 0.25, 0.5, 0.75, 1.0 } }
local EMPOWERED       = { kind = "empowered", duration = 2.5, spellName = ns.L["Fire Breath"],
                          spellIcon = "Interface\\Icons\\Ability_Evoker_Firebreath" }
local GCD_SEGMENT     = { kind = "gcd",       duration = 1.5, spellName = "",
                          spellIcon = nil }

local SCRIPT_TARGET = {
    { kind = "cast", duration = 2.5, spellName = ns.L["Polymorph"],
      spellIcon = "Interface\\Icons\\Spell_Nature_Polymorph", castType = "interruptible" },
    { kind = "cast", duration = 3.0, spellName = ns.L["Pyroblast"],
      spellIcon = "Interface\\Icons\\Spell_Fire_Fireball02",  castType = "notInterruptible" },
}

local SCRIPTS = {
    target       = SCRIPT_TARGET,
    focus        = SCRIPT_TARGET,
    pet          = { { kind = "cast", duration = 2.0, spellName = ns.L["Cleave"],
                       spellIcon = "Interface\\Icons\\Ability_Warrior_Cleave" } },
    targettarget = { { kind = "cast", duration = 2.0, spellName = ns.L["Heroic Strike"],
                       spellIcon = "Interface\\Icons\\Ability_Warrior_HeroicStrike" } },
    boss         = { { kind = "cast", duration = 4.0, spellName = ns.L["Apocalypse"],
                       spellIcon = "Interface\\Icons\\Achievement_Boss_Lichking" } },
}

local function BuildScript(unitKey, castDB)
    if unitKey == "player" then
        local script = { CAST_PLAYER, CHANNEL_PLAYER }
        if castDB.showEmpoweredLevel then script[#script + 1] = EMPOWERED    end
        if castDB.showGCD             then script[#script + 1] = GCD_SEGMENT end
        return script
    end
    return SCRIPTS[unitKey] or SCRIPTS.target
end

local function GetPlayerClassColor()
    return Shared.GetPlayerClassColorOr(1, 0.7, 0, 1)
end

local function ResolveSegmentColor(mock, seg)
    local castDB = mock._castDB
    if seg.kind == "gcd" then
        local c = castDB.gcdColor or castDB.color or { 1, 0.7, 0, 1 }
        return c[1], c[2], c[3], c[4] or 1
    end
    if seg.castType == "notInterruptible" then
        local c = castDB.notInterruptibleColor or { 0.7, 0.2, 0.2, 1 }
        return c[1], c[2], c[3], c[4] or 1
    end
    if mock._unitKey == "player" and castDB.useClassColor then
        return GetPlayerClassColor()
    end
    local c = castDB.color or { 1, 0.7, 0, 1 }
    return c[1], c[2], c[3], c[4] or 1
end

local function ApplySegmentEntry(mock, seg)
    local castDB = mock._castDB

    local name = seg.spellName or ""
    local maxLen = castDB.maxLength or 0
    if maxLen > 0 then name = ns.Helpers.TruncateUTF8(name, maxLen) end
    if castDB.showSpellText then mock.spellText:SetText(name) end

    if castDB.showIcon and seg.spellIcon then
        mock.icon:Show()
        mock.icon._art:SetTexture(seg.spellIcon)
    elseif not seg.spellIcon then
        mock.icon:Hide()
    end

    local r, g, b, a = ResolveSegmentColor(mock, seg)
    mock.fill:SetVertexColor(r, g, b, a)

    if mock._ticksEnabled and seg.kind == "channel" and seg.ticks then
        local barW = mock._barInnerW
        for i = 1, 4 do
            local t = mock.ticks[i]
            local pos = seg.ticks[i]
            if pos then
                t:Show()
                t:ClearAllPoints()
                t:SetPoint("TOP",    mock, "TOPLEFT",    barW * pos, 0)
                t:SetPoint("BOTTOM", mock, "BOTTOMLEFT", barW * pos, 0)
            else
                t:Hide()
            end
        end
    else
        for i = 1, 4 do mock.ticks[i]:Hide() end
    end

    if seg.kind == "empowered" and mock._showStageNumber then
        mock.empoweredText:Show()
    else
        mock.empoweredText:Hide()
    end
end

function Module.Build(host)
    local mock = CreateFrame("Frame", nil, host)
    mock:SetSize(200, 20)
    mock:SetPoint("BOTTOM", host, "BOTTOM", 0, 12)

    mock.bg = mock:CreateTexture(nil, "BACKGROUND", nil, -2)
    mock.bg:SetAllPoints(mock)
    mock.bg:SetColorTexture(0.149, 0.149, 0.149, 1)

    mock.fill = mock:CreateTexture(nil, "ARTWORK")
    mock.fill:SetPoint("TOPLEFT",    mock, "TOPLEFT",    0, 0)
    mock.fill:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", 0, 0)
    mock.fill:SetWidth(0)
    mock.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    mock.fill:SetVertexColor(1, 0.7, 0, 1)

    mock._border = CreateHairlineBorder(mock, { 0, 0, 0, 1 })

    local icon = CreateFrame("Frame", nil, mock)
    icon:SetSize(25, 25)
    icon._art = icon:CreateTexture(nil, "ARTWORK")
    icon._art:SetPoint("TOPLEFT",     icon, "TOPLEFT",     1, -1)
    icon._art:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icon._art:SetTexture("Interface\\Icons\\Spell_Frost_FrostBolt02")
    icon._art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon._border = CreateHairlineBorder(icon, { 0, 0, 0, 1 })
    mock.icon = icon

    mock.spellText     = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock.spellText:SetText(ns.L["Frostbolt"])
    mock.timeText      = mock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mock.timeText:SetText("1.4s")
    mock.empoweredText = mock:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mock.empoweredText:Hide()

    mock.ticks = {}
    for i = 1, 4 do
        local t = mock:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 0.9)
        t:Hide()
        mock.ticks[i] = t
    end

    mock._state = {
        segment      = nil,
        segmentIndex = nil,
        segmentT     = 0,
        script       = nil,
    }
    mock._barInnerW    = 0
    mock._scale        = 1
    mock._castDB       = nil
    mock._unitKey      = nil
    mock._lastUnit     = nil
    mock._ticksEnabled = false

    mock:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsVisible() then return end
        local s = self._state
        if not s or not s.script or #s.script == 0 then return end

        local castDB = self._castDB
        if not castDB then return end

        s.segmentT = (s.segmentT or 0) + elapsed

        if (not s.segment) or s.segmentT >= s.segment.duration then
            s.segmentIndex = ((s.segmentIndex or 0) % #s.script) + 1
            s.segment      = s.script[s.segmentIndex]
            s.segmentT     = 0
            ApplySegmentEntry(self, s.segment)
        end

        local seg, t, dur = s.segment, s.segmentT, s.segment.duration

        local pct
        if seg.kind == "cast" or seg.kind == "empowered" then
            pct = t / dur
        elseif seg.kind == "channel" then
            pct = castDB.channelFillForward and (t / dur) or (1 - t / dur)
        elseif seg.kind == "gcd" then
            pct = castDB.showGCDReverse and (1 - t / dur) or (t / dur)
        else
            pct = t / dur
        end
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end

        self.fill:SetWidth(math.max(0, self._barInnerW * pct))

        if castDB.showTimeText
            and not (seg.kind == "empowered" and castDB.hideTimeTextOnEmpowered) then
            self.timeText:Show()
            self.timeText:SetText(string.format("%.1fs", math.max(0, dur - t)))
        elseif seg.kind == "empowered" and castDB.hideTimeTextOnEmpowered then
            self.timeText:Hide()
        end

        if seg.kind == "empowered" and self._showStageNumber then
            local stage = math.min(4, math.floor(pct * 4) + 1)
            self.empoweredText:SetText(tostring(stage))
            local sc = self._stageColors and self._stageColors[stage]
            if sc then
                self.empoweredText:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
            end
            local fc = self._empoweredColors and self._empoweredColors[stage]
            if fc then
                self.fill:SetVertexColor(fc[1], fc[2], fc[3], fc[4] or 1)
            end
        end
    end)

    ApplyHairlineBorder(mock._border,      mock,      1)
    ApplyHairlineBorder(mock.icon._border, mock.icon, 1)
    mock.fill:SetWidth(100)

    return mock
end

function Module.Refresh(mock, unitKey, unitDB, general)
    if not mock then return end

    local castDB = unitDB and unitDB.castbar
    if not castDB or not castDB.enabled then
        mock:Hide()
        return
    end
    mock:Show()

    mock._castDB  = castDB
    mock._unitKey = unitKey

    local host  = mock:GetParent()
    local scale = ComputeBarScale(host, castDB)
    mock._scale = scale

    local barW = math.max(20, (castDB.width  or 250) * scale)
    local barH = math.max(4,  (castDB.height or  25) * scale)
    mock:SetSize(barW, barH)
    mock._barInnerW = barW

    mock.fill:SetTexture(ResolveStatusBarTexture(castDB.texture))
    local bg = castDB.bgColor or { 0.149, 0.149, 0.149, 1 }
    mock.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)

    ApplyHairlineBorder(mock._border, mock, castDB.borderSize or 1)

    if castDB.showIcon then
        mock.icon:Show()
        local iconBase = math.max(8, (castDB.iconSize or 25) * (castDB.iconScale or 1) * scale)
        mock.icon:SetSize(iconBase, iconBase)
        ApplyIconAnchor(mock.icon, mock, castDB.iconAnchor or "LEFT", (castDB.iconSpacing or 0) * scale)
        ApplyHairlineBorder(mock.icon._border, mock.icon, castDB.iconBorderSize or 2)
    else
        mock.icon:Hide()
    end

    local fontPath, fontOutline = ResolveUnitFrameFont()
    local fontSize = math.max(8, math.min(24, math.floor((castDB.fontSize or 12) * scale + 0.5)))

    if castDB.showSpellText then
        mock.spellText:Show()
        CJKFont(mock.spellText, fontPath, fontSize, fontOutline)
        mock.spellText:SetTextColor(1, 1, 1, 1)
        ApplyTextAnchor(
            mock.spellText, mock, castDB.spellTextAnchor or "LEFT",
            (castDB.spellTextOffsetX or 4) * scale,
            (castDB.spellTextOffsetY or 0) * scale, 4
        )
    else
        mock.spellText:Hide()
    end

    if castDB.showTimeText then
        mock.timeText:Show()
        CJKFont(mock.timeText, fontPath, fontSize, fontOutline)
        mock.timeText:SetTextColor(1, 1, 1, 1)
        ApplyTextAnchor(
            mock.timeText, mock, castDB.timeTextAnchor or "RIGHT",
            (castDB.timeTextOffsetX or -4) * scale,
            (castDB.timeTextOffsetY or 0) * scale, 4
        )
    else
        mock.timeText:Hide()
    end

    mock._ticksEnabled = (castDB.showChannelTicks == true) and unitKey ~= "boss" and unitKey ~= "pet"
    local tickColor     = castDB.channelTickColor or { 1, 1, 1, 0.9 }
    local tickThickness = math.max(1, (castDB.channelTickThickness or 1) * scale)
    for i = 1, 4 do
        local t = mock.ticks[i]
        t:SetColorTexture(tickColor[1], tickColor[2], tickColor[3], tickColor[4] or 0.9)
        t:SetWidth(tickThickness)
        t:Hide()
    end

    if unitKey == "player" and castDB.showEmpoweredLevel then
        mock._showStageNumber = true
        mock._stageColors     = castDB.empoweredStageColors or {}
        mock._empoweredColors = castDB.empoweredFillColors  or {}
        local lvlAnchor = castDB.empoweredLevelTextAnchor or "CENTER"
        ApplyTextAnchor(
            mock.empoweredText, mock, lvlAnchor,
            (castDB.empoweredLevelTextOffsetX or 0) * scale,
            (castDB.empoweredLevelTextOffsetY or 0) * scale, 4
        )
        local lvlFontSize = math.max(10, math.floor(fontSize * 1.2))
        CJKFont(mock.empoweredText, fontPath, lvlFontSize, fontOutline)
    else
        mock._showStageNumber = false
        mock.empoweredText:Hide()
    end

    mock._state.script = BuildScript(unitKey, castDB)

    if mock._lastUnit ~= unitKey then
        mock._lastUnit           = unitKey
        mock._state.segment      = nil
        mock._state.segmentIndex = nil
        mock._state.segmentT     = 0
    end

    if not mock._state.segment then
        mock._state.segmentIndex = 1
        mock._state.segment      = mock._state.script[1]
        mock._state.segmentT     = 0
        ApplySegmentEntry(mock, mock._state.segment)
    end
end
