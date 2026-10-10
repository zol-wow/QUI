local _, ns = ...

local Shared = ns.QUI_SettingsLayoutShared or {}
ns.QUI_SettingsLayoutShared = Shared

function Shared.BuildNinePointAnchorOptions()
    local L = ns.L
    return {
        { value = "TOPLEFT", text = L["Top Left"] },
        { value = "TOP", text = L["Top"] },
        { value = "TOPRIGHT", text = L["Top Right"] },
        { value = "LEFT", text = L["Left"] },
        { value = "CENTER", text = L["Center"] },
        { value = "RIGHT", text = L["Right"] },
        { value = "BOTTOMLEFT", text = L["Bottom Left"] },
        { value = "BOTTOM", text = L["Bottom"] },
        { value = "BOTTOMRIGHT", text = L["Bottom Right"] },
    }
end

function Shared.FitsThreeColumns(label, widget, width)
    if not label or not widget or width < 560 then return false end
    local controlWidth = widget:GetWidth()
    if controlWidth > 100 then return false end
    local pin = widget._quiPinButton
    local pinWidth = pin and pin:IsShown() and (pin:GetWidth() + 4) or 0
    local labelWidth = label.GetStringWidth and label:GetStringWidth() or 118
    return math.max(110, labelWidth) + controlWidth + pinWidth + 16 <= (width - 64) / 3
end

function Shared.MakeLayout(content, U, startY, options)
    if U and U._layoutModePositionOnly then
        return U.MakeSuppressedProviderLayout(content)
    end
    local Opts = ns.QUI_Options
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14
    local y = startY or -10
    local trailingGap = 0
    local L = {}
    local sections = {}

    function L.headerAt(text)
        local GUI = _G.QUI and _G.QUI.GUI
        if options and options.searchSections and GUI and GUI.SetSearchSection then GUI:SetSearchSection(text) end
        local h = Opts.CreateAccentDotLabel(content, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
        trailingGap = 0
    end
    function L.sectionAt()
        local c = Opts.CreateSettingsCardGroup(content, y)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        c.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        return c
    end
    function L.closeSection(c)
        c.Finalize()
        y = y - c.frame:GetHeight() - SECTION_GAP
        trailingGap = SECTION_GAP
    end
    function L.placeCustom(frame, height)
        frame:SetParent(content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        frame:SetHeight(height)
        y = y - height - SECTION_GAP
        trailingGap = SECTION_GAP
    end

    local function relayoutSections()
        local cy = y
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, cy)
            s:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            cy = cy - s:GetHeight() - 4
        end
        content:SetHeight(math.abs(cy) - (#sections == 0 and trailingGap or 4) + 10)
    end
    function L.finish()
        content:SetHeight(math.abs(y) - trailingGap + 10)
        return content:GetHeight()
    end
    function L.intro(text)
        local G = QUI and QUI.GUI
        local frame = CreateFrame("Frame", nil, content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        local lbl = G:CreateLabel(frame, text, 11, G.Colors.textMuted)
        lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        lbl:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        local approxHeight = math.max(18, math.ceil(#text / 90) * 15)
        frame:SetHeight(approxHeight)
        y = y - approxHeight - 8
        trailingGap = 8
        return lbl, frame
    end
    function L.getY() return y end
    function L.setY(newY) y = newY; trailingGap = 0 end
    L.sections = sections
    L.relayoutSections = relayoutSections

    return L
end

function Shared.VerifyInitialBounds(frame, parent, repair, region)
    local firstLayoutFrame = false
    frame:SetScript("OnUpdate", function(self)
        if not parent:GetTop() then return end
        if not firstLayoutFrame then firstLayoutFrame = true; return end
        self:SetScript("OnUpdate", nil)
        if not (region or self):GetTop() then
            repair(self)
            self:Hide()
            self:Show()
        end
    end)
end

function Shared.RefreshInitialEditText(editBox, parent)
    local firstLayoutFrame = false
    editBox:SetScript("OnUpdate", function(self)
        if not parent:GetTop() then return end
        if not firstLayoutFrame then firstLayoutFrame = true; return end
        self:SetScript("OnUpdate", nil)
        if self:HasFocus() then return end
        local text = self:GetText()
        self:SetText("")
        self:SetText(text)
        self:SetCursorPosition(0)
    end)
end
