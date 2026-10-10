local addonName, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase
local UIKit = ns.UIKit

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local GetCore = ns.Helpers.GetCore

-- Shell, bottom tabs, close button and popout chrome are owned by
-- ns.CharacterChrome (modules/skinning/frames/character_chrome.lua). This
-- file keeps the Reputation / Currency / Equipment Manager / Titles pane
-- skinning and asks the owner for everything else.
local function GetChrome()
    return ns.CharacterChrome
end

local CONFIG = {
    PANEL_WIDTH_EXTENSION = 55,
    PANEL_HEIGHT_EXTENSION = 50,
}

local COLORS = {
    text = { 0.9, 0.9, 0.9, 1 },
}

local iconBorders = Helpers.CreateStateTable()
local skinnedEntries = Helpers.CreateStateTable()
local rowAccentBars = Helpers.CreateStateTable()
local rowHoverHooked = Helpers.CreateStateTable()

local function GetWindowColors()
    local profile = Helpers.GetProfile and Helpers.GetProfile()
    return SkinBase.GetWindowColors(profile and profile.general, "characterFrame")
end

-- Border colour as TEXT colour, luminance-floored (black / hidden borders
-- otherwise turn headers and popup titles black or invisible).
local function GetTextAccent()
    local profile = Helpers.GetProfile and Helpers.GetProfile()
    return SkinBase.GetSkinTextAccent(profile and profile.general, "characterFrame")
end

local GetFontPath = Helpers.GetGeneralFont


local function SetPixelBackdropColors(frame, borderColor, bgColor)
    SkinBase.SetBackdropColors(frame, borderColor, bgColor)
end

local SetExpandedPixelPoints = SkinBase.SetExpandedPixelPoints

-- Scrollbar thumbs use the shared scrollThumb role (never the skin bar colour).
local function StyleThinScrollBar(scrollBar)
    local chrome = GetChrome()
    if chrome and chrome.StyleScrollbar then
        chrome.StyleScrollbar(scrollBar)
    else
        SkinBase.SkinTrimScrollBar(scrollBar)
    end
end

-- Palette tokens for row state (white text graded by alpha, accent marker).
local ROW_FALLBACK = {
    tabSelectedText = { 1, 1, 1, 1 },
    tabNormal = { 1, 1, 1, 0.55 },
    tabHover = { 1, 1, 1, 0.85 },
    selectedWash = { 1, 1, 1, 0.10 },
}

local function RowToken(name)
    local chrome = GetChrome()
    if chrome and chrome.Token then return chrome.Token(name) end
    local gui = _G.QUI and _G.QUI.GUI
    local colors = gui and gui.Colors
    return (colors and colors[name]) or ROW_FALLBACK[name]
end

local function IsSkinningEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinCharacterFrame
end

local function SetCharacterFrameBgExtended(extended)
    local chrome = GetChrome()
    if chrome and chrome.SetExtended then
        return chrome.SetExtended(extended)
    end
end

local function SkinCharacterFrameTabs()
    local chrome = GetChrome()
    if chrome and chrome.StyleTabs then chrome.StyleTabs() end
end

local function StyleCloseButton(button)
    local chrome = GetChrome()
    if button and chrome and chrome.StyleCloseButton then chrome.StyleCloseButton(button) end
end

local function SkinEntryHeader(child, fontPath, sr, sg, sb)
    if child.Name then
        CJKFont(child.Name, fontPath, 13, "")
        child.Name:SetTextColor(GetTextAccent())
    end

    if child.Left then child.Left:SetAlpha(0) end
    if child.Middle then child.Middle:SetAlpha(0) end
    if child.HighlightLeft then child.HighlightLeft:SetAlpha(0) end
    if child.HighlightMiddle then child.HighlightMiddle:SetAlpha(0) end

    if child.SetTitleColor and CreateColor then
        local titleColor = CreateColor(sr, sg, sb, 1)
        child:SetTitleColor(false, titleColor)
        child:SetTitleColor(true, titleColor)
        if child.CheckHighlightTitle then child:CheckHighlightTitle() end
    end

    local function UpdateCollapseIcon(texture, atlas)
        if not atlas or atlas == "Options_ListExpand_Right" or atlas == "Options_ListExpand_Right_Expanded" then
            if child.IsCollapsed and child:IsCollapsed() then
                texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Expand", true)
            else
                texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Collapse", true)
            end
        end
    end

    UpdateCollapseIcon(child.Right)
    UpdateCollapseIcon(child.HighlightRight)
    hooksecurefunc(child.Right, "SetAtlas", UpdateCollapseIcon)
    hooksecurefunc(child.HighlightRight, "SetAtlas", UpdateCollapseIcon)
end

local function SkinToggleCollapseButton(button)
    if not button or not button.RefreshIcon then return end
    if SkinBase.GetFrameData(button, "characterCollapseGlyph") then return end
    SkinBase.SkinButton(button, { strip = true, font = false })
    local backdrop = SkinBase.GetBackdrop(button)
    if backdrop then SkinBase.ApplyChromeBackdrop(backdrop, { radius = 4 }) end
    local glyph = button:CreateFontString(nil, "OVERLAY")
    glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
    SkinBase.SkinFontString(glyph, { size = 14 })
    SkinBase.SetFrameData(button, "characterCollapseGlyph", glyph)
    local function UpdateToggleButton(owner)
        local header = owner.GetHeader and owner:GetHeader()
        if not header then return end
        glyph:SetText(header:IsCollapsed() and "+" or "−")
    end
    hooksecurefunc(button, "RefreshIcon", UpdateToggleButton)
    UpdateToggleButton(button)
end

local function SkinReputationEntry(child)
    if skinnedEntries[child] then return end

    local sr, sg, sb, sa = GetWindowColors()
    local fontPath = GetFontPath()

    if child.Right then
        SkinEntryHeader(child, fontPath, GetTextAccent())
    end

    local ReputationBar = child.Content and child.Content.ReputationBar
    if ReputationBar then
        if ReputationBar.SetStatusBarTexture then
            ns.Helpers.ApplyBarStyle(ReputationBar, "Interface\\Buttons\\WHITE8x8")
            UIKit.DisablePixelSnap(ReputationBar)
        elseif ReputationBar.Fill then
            Helpers.ApplyTextureStyle(ReputationBar, ReputationBar.Fill, "Interface\\Buttons\\WHITE8x8")
            UIKit.DisablePixelSnap(ReputationBar.Fill)
        end

        local fill = ReputationBar.GetStatusBarTexture and ReputationBar:GetStatusBarTexture() or ReputationBar.Fill
        SkinBase.RoundBarTexture(ReputationBar, fill)

        if ReputationBar.LeftTexture then
            ReputationBar.LeftTexture:SetTexture(nil)
            ReputationBar.LeftTexture:Hide()
        end
        if ReputationBar.RightTexture then
            ReputationBar.RightTexture:SetTexture(nil)
            ReputationBar.RightTexture:Hide()
        end
        if ReputationBar.Background then
            ReputationBar.Background:Hide()
        end

        local barText = ReputationBar.BarText or ReputationBar.Text
        if barText then
            CJKFont(barText, fontPath, 10, "")
            barText:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3], 1)
        end

        if not SkinBase.GetFrameData(ReputationBar, "backdrop") then
            local backdrop = CreateFrame("Frame", nil, ReputationBar, "BackdropTemplate")
            backdrop:SetFrameLevel(math.max(0, ReputationBar:GetFrameLevel() - 1))
            local dr, dg, db, da = SkinBase.GetDepthColor("ROW")
            SetExpandedPixelPoints(backdrop, ReputationBar, SkinBase.CHROME.BORDER_PX)
            SkinBase.ApplyChromeBackdrop(backdrop, { radius = 3, withBackground = true, borderColor = { sr, sg, sb, 1 }, bgColor = { dr, dg, db, da } })
            backdrop:Show()
            SkinBase.SetFrameData(ReputationBar, "backdrop", backdrop)
        end

        if child.Content.Name then
            CJKFont(child.Content.Name, fontPath, 11, "")
        end
    end

    SkinToggleCollapseButton(child.ToggleCollapseButton)

    skinnedEntries[child] = true
end

local function SkinCurrencyEntry(child)
    if skinnedEntries[child] then return end

    local sr, sg, sb, sa = GetWindowColors()
    local fontPath = GetFontPath()

    if child.Right then
        SkinEntryHeader(child, fontPath, GetTextAccent())
    end

    local CurrencyIcon = child.Content and child.Content.CurrencyIcon
    if CurrencyIcon then
        CurrencyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Helpers.ApplyIconStyle(CurrencyIcon:GetParent(), CurrencyIcon)

        if not iconBorders[CurrencyIcon] then
            local border = CreateFrame("Frame", nil, CurrencyIcon:GetParent(), "BackdropTemplate")
            local drawLayer = CurrencyIcon.GetDrawLayer and CurrencyIcon:GetDrawLayer()
            border:SetFrameLevel((drawLayer == "OVERLAY") and child:GetFrameLevel() + 2 or child:GetFrameLevel() + 1)
            SetExpandedPixelPoints(border, CurrencyIcon, 1)
            SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false, borderColor = { sr, sg, sb, 1 } })
            SkinBase.RoundIconTexture(CurrencyIcon:GetParent(), CurrencyIcon)
            iconBorders[CurrencyIcon] = border
        end
    end

    if child.Content then
        if child.Content.Name then
            CJKFont(child.Content.Name, fontPath, 11, "")
        end
        if child.Content.Count then
            CJKFont(child.Content.Count, fontPath, 11, "")
        end
    end

    SkinToggleCollapseButton(child.ToggleCollapseButton)

    skinnedEntries[child] = true
end

-- Reputation detail: backdrop + fonts (was fonts-only: parchment next to dark).
local function SkinReputationDetailFrame()
    local detail = ReputationFrame and ReputationFrame.ReputationDetailFrame
    if not detail then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetWindowColors()
    if not SkinBase.GetFrameData(detail, "qRepDetailChrome") then
        SkinBase.SetFrameData(detail, "qRepDetailChrome", true)
        SkinBase.StripTextures(detail)
        if type(detail.Refresh) == "function" then
            hooksecurefunc(detail, "Refresh", SkinReputationDetailFrame)
        end
        if detail.Border then detail.Border:SetAlpha(0) end
        if detail.Divider then detail.Divider:SetAlpha(0) end
        if detail.Title then
            SkinBase.SkinFontString(detail.Title, { size = 13, color = { GetTextAccent() } })
        end
        if detail.ScrollingDescription then
            SkinBase.SkinFrameText(detail.ScrollingDescription, { recurse = true })
        end
        for _, key in ipairs({ "AtWarCheckbox", "MakeInactiveCheckbox", "WatchFactionCheckbox" }) do
            local check = detail[key]
            if check then
                SkinBase.SkinCheckBox(check)
                local backdrop = SkinBase.GetBackdrop(check)
                if backdrop then
                    SkinBase.SetInsetPixelPoints(backdrop, check, 6)
                    SkinBase.ApplyChromeBackdrop(backdrop, { radius = 3, withBackground = true })
                end
                SkinBase.SkinFontString(check.Label, { size = 11, fontOnly = true })
            end
        end
        if SkinBase.ApplyButtonFontObjectsDeep then
            SkinBase.ApplyButtonFontObjectsDeep(detail, 2)
        end
        StyleCloseButton(detail.CloseButton)
        StyleThinScrollBar(detail.ScrollingDescriptionScrollBar)
    end
    SkinBase.CreateBackdrop(detail, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)
    for _, key in ipairs({ "MakeInactiveCheckbox", "WatchFactionCheckbox" }) do
        local check = detail[key]
        if check and check.Label then
            local color = check.IsEnabled and not check:IsEnabled() and RowToken("disabled") or RowToken("tabHover")
            SkinBase.SkinFontString(check.Label, { size = 11, color = color })
            if not SkinBase.GetFrameData(check.Label, "qReputationDetailColorHooked") then
                SkinBase.SetFrameData(check.Label, "qReputationDetailColorHooked", true)
                hooksecurefunc(check.Label, "SetTextColor", function(label, r, g, b, a)
                    local expected = check.IsEnabled and not check:IsEnabled() and RowToken("disabled") or RowToken("tabHover")
                    if r ~= expected[1] or g ~= expected[2] or b ~= expected[3] or a ~= (expected[4] or 1) then
                        label:SetTextColor(expected[1], expected[2], expected[3], expected[4] or 1)
                    end
                end)
            end
        end
    end
    if detail.ViewRenownButton then SkinBase.SkinButton(detail.ViewRenownButton) end
    if detail.Title then detail.Title:SetTextColor(GetTextAccent()) end
end

-- Currency options popup: backdrop + title + close ONLY. The checkboxes and
-- the transfer toggle are part of the protected currency-transfer flow; a
-- write there taints RequestCurrencyFromAccountCharacter.
local function SkinTokenFramePopup()
    local popup = _G.TokenFramePopup or (TokenFrame and TokenFrame.Popup)
    if not popup then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetWindowColors()
    if not SkinBase.GetFrameData(popup, "qTokenPopupChrome") then
        SkinBase.SetFrameData(popup, "qTokenPopupChrome", true)
        if popup.Border then popup.Border:SetAlpha(0) end
        if popup.Title then
            SkinBase.SkinFontString(popup.Title, { size = 13, color = { GetTextAccent() } })
        end
        StyleCloseButton(popup.CloseButton or popup["$parent.CloseButton"])
        SkinBase.SkinButton(popup.CurrencyTransferToggleButton)
        for _, key in ipairs({ "InactiveCheckbox", "BackpackCheckbox" }) do
            local check = popup[key]
            if check then
                SkinBase.SkinCheckBox(check)
                local backdrop = SkinBase.GetBackdrop(check)
                if backdrop then
                    SkinBase.SetInsetPixelPoints(backdrop, check, 6)
                    SkinBase.ApplyChromeBackdrop(backdrop, { radius = 3, withBackground = true })
                end
                SkinBase.SkinFontString(check.Text or check.Label, { size = 11, fontOnly = true })
            end
        end
    end
    SkinBase.CreateBackdrop(popup, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)
    if popup.Title then popup.Title:SetTextColor(GetTextAccent()) end
end

local function StyleCurrencyLogRow(row)
    if not row or not IsSkinningEnabled() then return end
    SkinBase.SkinScrollRow(row)
    SkinBase.StripTextures(row.BackgroundHighlight)
    if row.CurrencyIcon then
        row.CurrencyIcon:SetAlpha(1)
        row.CurrencyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SkinBase.RoundIconTexture(row, row.CurrencyIcon)
    end
    if row.Arrow then row.Arrow:SetAlpha(1) end
    for _, key in ipairs({ "SourceName", "DestinationName", "CurrencyQuantity" }) do
        SkinBase.SkinFontString(row[key], { size = 11, color = { 0.9, 0.9, 0.9, 1 } })
    end
end

local function SkinCurrencyTransferLog()
    local log = _G.CurrencyTransferLog
    if not log or not IsSkinningEnabled() then return end
    local toggle = TokenFrame and TokenFrame.CurrencyTransferLogToggleButton
    if toggle then
        SkinBase.SkinButton(toggle, { strip = true, font = false, belowChildren = true })
        SkinBase.RefreshWidget(toggle)
        if not SkinBase.GetFrameData(toggle, "qCurrencyLogGlyph") then
            local glyph = toggle:CreateFontString(nil, "OVERLAY")
            glyph:SetPoint("CENTER")
            SkinBase.SkinFontString(glyph, { size = 9, color = { 1, 1, 1, 1 } })
            glyph:SetText("Log")
            SkinBase.SetFrameData(toggle, "qCurrencyLogGlyph", glyph)
        end
    end
    if not SkinBase.IsSkinned(log) then
        SkinBase.SkinWindow(log)
        SkinBase.MarkSkinned(log)
        log:HookScript("OnShow", SkinCurrencyTransferLog)
        if type(log.Refresh) == "function" then hooksecurefunc(log, "Refresh", SkinCurrencyTransferLog) end
        SkinBase.HookScrollBoxAcquired(log.ScrollBox, StyleCurrencyLogRow)
    end
    SkinBase.ClampTextureHidden(log.Background, true)
    SkinBase.StripTextures(log.Inset)
    SkinBase.KillNineSlice(log.Inset and log.Inset.NineSlice, true)
    SkinBase.SkinTrimScrollBar(log.ScrollBar)
    local sr, sg, sb, sa, r, g, b, a = GetWindowColors()
    SkinBase.SetBackdropColors(SkinBase.GetBackdrop(log), { sr, sg, sb, sa }, { r, g, b, a })
    local title = log.GetTitleText and log:GetTitleText()
    SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } })
    SkinBase.SkinFontString(log.EmptyLogMessage, { size = 12, color = { 0.85, 0.85, 0.85, 1 } })
    local mixin = _G.CurrencyTransferLogEntryMixin
    if mixin and type(mixin.Initialize) == "function" and not SkinBase.GetFrameData(mixin, "qCurrencyLogRowsHooked") then
        hooksecurefunc(mixin, "Initialize", StyleCurrencyLogRow)
        SkinBase.SetFrameData(mixin, "qCurrencyLogRowsHooked", true)
    end
    SkinBase.ForEachScrollBoxFrame(log.ScrollBox, StyleCurrencyLogRow)
end

local function SkinNativeSidePaneText(pane)
    for _, key in ipairs({ "Title", "Subtitle", "EmptyText" }) do
        SkinBase.SkinFontString(pane[key], { fontOnly = true })
    end
    SkinBase.SkinFrameText(pane.Description, { recurse = true })
    SkinBase.SkinFrameText(pane.Content, { recurse = true })
end

local function SkinNativeSidePane(pane)
    if not pane then return end
    SkinNativeSidePaneText(pane)
    SkinBase.SkinTrimScrollBar(pane.DescriptionScrollBar)
    if type(pane.Refresh) == "function" and not SkinBase.GetFrameData(pane, "qCharacterSidePaneHooked") then
        hooksecurefunc(pane, "Refresh", function(self)
            if IsSkinningEnabled() then SkinNativeSidePaneText(self) end
        end)
        SkinBase.SetFrameData(pane, "qCharacterSidePaneHooked", true)
    end
end

local function SkinNativeCharacterPanes()
    if not IsSkinningEnabled() or not (ns.Client and ns.Client.isForever) then return end
    for _, frame in pairs({ _G.SkillsFrame, _G.StatisticsFrame, _G.PVPRankFrame }) do
        SkinBase.SkinFrameText(frame, { recurse = true })
        if frame.ScrollBox and not SkinBase.GetFrameData(frame, "qCharacterNativeRowsHooked") then
            SkinBase.HookScrollBoxAcquired(frame.ScrollBox, function(row)
                if IsSkinningEnabled() then SkinBase.LockPooledRowText(row, 4) end
            end)
            SkinBase.SetFrameData(frame, "qCharacterNativeRowsHooked", true)
        end
        SkinBase.SkinTrimScrollBar(frame.ScrollBar)
        SkinNativeSidePane(frame.SkillDetailFrame or frame.DetailFrame)
    end
    SkinNativeSidePane(TokenFrame and TokenFrame.DetailFrame)
    SkinNativeSidePane(ReputationFrame and ReputationFrame.ReputationDetailFrame)
end

local function SkinCharacterListControls()
    SkinCurrencyTransferLog()
    for _, pane in pairs({ _G.ReputationFrame, _G.TokenFrame }) do
        if pane.filterDropdown then
            SkinBase.SkinDropdown(pane.filterDropdown, { skinArrow = true })
            SkinBase.RefreshWidget(pane.filterDropdown)
        end
        if pane.ScrollBar then SkinBase.SkinTrimScrollBar(pane.ScrollBar) end
    end
end

local function SetupCharacterFrameSkinning()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    if not CharacterFrame then return end

    local chrome = GetChrome()
    if chrome and chrome.Initialize then chrome.Initialize() end

    if ReputationFrame and ReputationFrame.ScrollBox then
        SkinBase.HookScrollBoxAcquired(ReputationFrame.ScrollBox, function(row)
            if IsSkinningEnabled() then
                SkinReputationEntry(row)
                SkinBase.LockPooledRowText(row, 4)
            end
        end)
    end
    SkinReputationDetailFrame()
    SkinTokenFramePopup()
    SkinNativeCharacterPanes()
    SkinCharacterListControls()
    if TokenFrame and TokenFrame.ScrollBox then
        SkinBase.HookScrollBoxAcquired(TokenFrame.ScrollBox, function(row)
            if IsSkinningEnabled() then
                SkinCurrencyEntry(row)
                SkinBase.LockPooledRowText(row, 4)
            end
        end)
        if _G.TokenEntryMixin and _G.TokenEntryMixin.Initialize
            and not SkinBase.GetFrameData(TokenFrame, "qTokenIconHooked") then
            hooksecurefunc(_G.TokenEntryMixin, "Initialize", function(self)
                if not IsSkinningEnabled() then return end
                local icon = self.Content and self.Content.CurrencyIcon
                if icon then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            end)
            SkinBase.SetFrameData(TokenFrame, "qTokenIconHooked", true)
        end
    end

    -- Shell anchoring on tab changes and the deferred OnShow catch-up are the
    -- chrome owner's (CharacterChrome.Initialize installs them once).
    if not (PaperDollFrame and PaperDollFrame:IsShown()) then
        SetCharacterFrameBgExtended(false)
    end
end

local RefreshEquipmentManagerColors
local RefreshTitlePaneColors

local function RefreshCharacterFrameColors()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end

    local sr, sg, sb = GetWindowColors()

    local chrome = GetChrome()
    if chrome and chrome.RefreshTheme then
        chrome.RefreshTheme()
    else
        SkinCharacterFrameTabs()
    end
    SkinReputationDetailFrame()
    SkinTokenFramePopup()
    SkinNativeCharacterPanes()
    SkinCharacterListControls()

    if ReputationFrame and ReputationFrame.ScrollBox then
        SkinBase.ForEachScrollBoxFrame(ReputationFrame.ScrollBox, function(child)
            if not skinnedEntries[child] then return end
            if child.Right and child.Name then
                child.Name:SetTextColor(GetTextAccent())
            end
            local ReputationBar = child.Content and child.Content.ReputationBar
            local repBd = ReputationBar and SkinBase.GetFrameData(ReputationBar, "backdrop")
            if repBd then
                SetPixelBackdropColors(repBd, { sr, sg, sb, 1 })
            end
        end)
    end

    if TokenFrame and TokenFrame.ScrollBox then
        SkinBase.ForEachScrollBoxFrame(TokenFrame.ScrollBox, function(child)
            if not skinnedEntries[child] then return end
            if child.Right and child.Name then
                child.Name:SetTextColor(GetTextAccent())
            end
            local CurrencyIcon = child.Content and child.Content.CurrencyIcon
            if CurrencyIcon and iconBorders[CurrencyIcon] then
                SetPixelBackdropColors(iconBorders[CurrencyIcon], { sr, sg, sb, 1 })
            end
        end)
    end

    if RefreshEquipmentManagerColors then RefreshEquipmentManagerColors() end

    if RefreshTitlePaneColors then RefreshTitlePaneColors() end
end

-- Row state contract (equipment sets, titles): selected = white 1.0 text +
-- 2-px accent bar + accent check glyph; unselected white .55; hover .85. The
-- Blizzard SelectedBar / HighlightBar textures become the faint accent wash.
-- State lives in SkinBase frame data, never on the Blizzard row; we do NOT use
-- SkinBase.SetButtonSelected here because its art suppression would hide the
-- equipment-set icon (the row's NormalTexture).
local function IsRowSelected(row)
    local flag = SkinBase.GetFrameData(row, "qRowSelected")
    if flag ~= nil then return flag end
    local bar = row.SelectedBar
    return (bar and bar.IsShown and bar:IsShown()) and true or false
end

local function EnsureRowAccentBar(row)
    local bar = rowAccentBars[row]
    if not bar and row.CreateTexture then
        bar = row:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        bar:SetWidth(SkinBase.GetPixelSize(row, 1))
        UIKit.DisablePixelSnap(bar)
        bar:Hide()
        rowAccentBars[row] = bar
    end
    return bar
end

local function ApplyRowState(row, hovered)
    if not row then return end
    local selected = IsRowSelected(row)
    local color
    if selected then
        color = RowToken("tabSelectedText")
    elseif hovered then
        color = RowToken("tabHover")
    else
        color = RowToken("tabNormal")
    end
    local text = row.text
    if text and text.SetTextColor then
        text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end

    local profile = Helpers.GetProfile and Helpers.GetProfile()
    local ar, ag, ab = SkinBase.GetSkinColors(profile and profile.general, "characterFrame")
    local bar = EnsureRowAccentBar(row)
    if bar then
        bar:SetColorTexture(ar, ag, ab, 1)
        if selected then bar:Show() else bar:Hide() end
    end
    if row.Check and row.Check.SetVertexColor then
        if row.Check.SetDesaturated then row.Check:SetDesaturated(true) end
        row.Check:SetVertexColor(ar, ag, ab)
    end
    local wash = RowToken("selectedWash")
    if row.SelectedBar and row.SelectedBar.SetColorTexture then
        row.SelectedBar:SetColorTexture(ar, ag, ab, wash[4] or 0.10)
    end
    local highlight = row.HighlightBar or row.Highlight
    if highlight and highlight.SetColorTexture then
        highlight:SetColorTexture(ar, ag, ab, 0.06)
    end
end

-- Called from the Blizzard InitButton post-hooks after SelectedBar visibility
-- is final for this bind.
local function SyncRowSelection(row)
    if not row then return end
    local bar = row.SelectedBar
    local selected = (bar and bar.IsShown and bar:IsShown()) and true or false
    SkinBase.SetFrameData(row, "qRowSelected", selected)
    local hovered = row.IsMouseOver and row:IsMouseOver() or false
    ApplyRowState(row, hovered)
end

local function HookRowHover(row)
    if not row or rowHoverHooked[row] or not row.HookScript then return end
    row:HookScript("OnEnter", function(self) ApplyRowState(self, true) end)
    row:HookScript("OnLeave", function(self) ApplyRowState(self, false) end)
    rowHoverHooked[row] = true
end

local function RestyleEquipmentSetEntryText(entry)
    local text = entry and entry.text
    if not text then return end
    CJKFont(text, GetFontPath(), 11, "")
    SyncRowSelection(entry)
end

local function SkinEquipmentSetEntry(entry)
    if not entry then return end
    RestyleEquipmentSetEntryText(entry)
    for _, key in ipairs({ "BgTop", "BgMiddle", "BgBottom" }) do
        if entry[key] then SkinBase.ClampTextureHidden(entry[key]) end
    end
    if entry.icon and not entry.setID then
        entry.icon:SetTexture("Interface\\AddOns\\QUI\\assets\\character\\add.tga")
        entry.icon:SetVertexColor(0.9, 0.9, 0.9, 1)
    elseif entry.icon then
        entry.icon:SetVertexColor(1, 1, 1, 1)
    end
    if skinnedEntries[entry] then return end

    local sr, sg, sb = GetWindowColors()

    if entry.icon and not iconBorders[entry.icon] then
        entry.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Helpers.ApplyIconStyle(entry, entry.icon)
        SkinBase.RoundIconTexture(entry, entry.icon)
        local border = CreateFrame("Frame", nil, entry, "BackdropTemplate")
        SkinBase.UsePhysicalPixelScale(border)
        SetExpandedPixelPoints(border, entry.icon, 1)
        SkinBase.ApplyChromeBackdrop(border, { radius = 3, withBackground = false, borderColor = { sr, sg, sb, 1 } })
        iconBorders[entry.icon] = border
    end

    HookRowHover(entry)
    ApplyRowState(entry, false)

    skinnedEntries[entry] = true
end

local function StyleEquipMgrButton(btn)
    local chrome = GetChrome()
    if chrome and chrome.StyleActionButton then chrome.StyleActionButton(btn) end
end

local function SkinEquipmentManager()
    local chrome = GetChrome()
    if not IsSkinningEnabled() and not (chrome and chrome.GetOwnership().enhancement) then return end

    local popup = _G.QUI_EquipMgrPopup
    if popup then
        local chrome = GetChrome()
        if chrome and chrome.RefreshPopout then chrome.RefreshPopout(popup) end
        skinnedEntries[popup] = true
    end

    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        SkinBase.HookScrollBoxAcquired(pane.ScrollBox, function(row)
            local owner = GetChrome()
            if IsSkinningEnabled() or (owner and owner.GetOwnership().enhancement) then SkinEquipmentSetEntry(row) end
        end)
    end

    if type(_G.PaperDollEquipmentManagerPane_InitButton) == "function"
        and not SkinBase.GetFrameData(pane, "qEquipInitHooked") then
        hooksecurefunc("PaperDollEquipmentManagerPane_InitButton", function(button)
            if not button then return end
            local owner = GetChrome()
            if not IsSkinningEnabled() and not (owner and owner.GetOwnership().enhancement) then return end
            SkinEquipmentSetEntry(button)
            if button.icon then button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end)
        SkinBase.SetFrameData(pane, "qEquipInitHooked", true)
    end

    if pane then
        StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar))
    end

    StyleEquipMgrButton(PaperDollFrameEquipSet)
    StyleEquipMgrButton(PaperDollFrameSaveSet)
end

RefreshEquipmentManagerColors = function()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_EquipMgrPopup
    if not popup or not skinnedEntries[popup] then return end

    local sr, sg, sb = GetWindowColors()

    local chrome = GetChrome()
    if chrome and chrome.RefreshPopout then chrome.RefreshPopout(popup) end

    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        SkinBase.ForEachScrollBoxFrame(pane.ScrollBox, function(entry)
            if not skinnedEntries[entry] then return end
            RestyleEquipmentSetEntryText(entry)
            if entry.icon and iconBorders[entry.icon] then
                SetPixelBackdropColors(iconBorders[entry.icon], { sr, sg, sb, 1 })
            end
        end)
    end
    if pane then
        StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar))
    end

    if PaperDollFrameEquipSet and skinnedEntries[PaperDollFrameEquipSet] then
        SetPixelBackdropColors(PaperDollFrameEquipSet, { sr, sg, sb, 0.5 })
    end
    if PaperDollFrameSaveSet and skinnedEntries[PaperDollFrameSaveSet] then
        SetPixelBackdropColors(PaperDollFrameSaveSet, { sr, sg, sb, 0.5 })
    end
end

local function HideTitleRowArt(button)
    if button.BgTop then button.BgTop:Hide() end
    if button.BgMiddle then button.BgMiddle:Hide() end
    if button.BgBottom then button.BgBottom:Hide() end
    if button.Stripe then button.Stripe:SetAlpha(0) end
end

local function SkinTitleEntry(button)
    if skinnedEntries[button] then return end

    if button.text then
        CJKFont(button.text, GetFontPath(), 12, "")
        button.text:SetWordWrap(false)
        button.text:SetMaxLines(1)
    end

    HideTitleRowArt(button)
    if button.GetHighlightTexture then SkinBase.ClampTextureHidden(button:GetHighlightTexture(), true) end

    if not button.Highlight and not SkinBase.GetFrameData(button, "qRowHighlight") and button.CreateTexture then
        -- Title rows ship without a highlight texture; give the hover state a
        -- surface so the .85 rung reads on the row, not just the text.
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        SkinBase.SetFrameData(button, "qRowHighlight", highlight)
    end

    HookRowHover(button)
    SyncRowSelection(button)

    skinnedEntries[button] = true
end

local function RefreshTitleEntry(button)
    SyncRowSelection(button)
    local highlight = SkinBase.GetFrameData(button, "qRowHighlight")
    if highlight then
        local profile = Helpers.GetProfile and Helpers.GetProfile()
        local ar, ag, ab = SkinBase.GetSkinColors(profile and profile.general, "characterFrame")
        highlight:SetColorTexture(ar, ag, ab, 0.06)
    end
end

local function SkinTitleManagerPane()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_TitlesPopup
    local pane = PaperDollFrame and PaperDollFrame.TitleManagerPane
    if not pane then return end

    if popup and not skinnedEntries[popup] then
        local chrome = GetChrome()
        if chrome and chrome.RefreshPopout then chrome.RefreshPopout(popup) end
        skinnedEntries[popup] = true
    end

    if skinnedEntries[pane] then return end

    if pane.Bg then pane.Bg:Hide() end
    if pane.Border then pane.Border:Hide() end

    if pane.ScrollBox then
        SkinBase.HookScrollBoxAcquired(pane.ScrollBox, function(row)
            SkinTitleEntry(row)
            RefreshTitleEntry(row)
            SkinBase.LockPooledRowText(row, 3)
        end)
    end

    if type(_G.PaperDollTitlesPane_InitButton) == "function"
        and not SkinBase.GetFrameData(pane, "qTitleInitHooked") then
        hooksecurefunc("PaperDollTitlesPane_InitButton", function(button)
            if not IsSkinningEnabled() or not button then return end
            HideTitleRowArt(button)
            if skinnedEntries[button] then RefreshTitleEntry(button) end
        end)
        SkinBase.SetFrameData(pane, "qTitleInitHooked", true)
    end

    StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar))

    skinnedEntries[pane] = true
end

RefreshTitlePaneColors = function()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_TitlesPopup
    if popup and skinnedEntries[popup] then
        local chrome = GetChrome()
        if chrome and chrome.RefreshPopout then chrome.RefreshPopout(popup) end
    end

    local pane = PaperDollFrame and PaperDollFrame.TitleManagerPane
    if not pane or not skinnedEntries[pane] then return end

    if pane.ScrollBox then
        SkinBase.ForEachScrollBoxFrame(pane.ScrollBox, function(button)
            if not skinnedEntries[button] then return end
            RefreshTitleEntry(button)
        end)
    end
    StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar))
end

local function SetupTitlePaneHook()
    if PaperDollFrame and PaperDollFrame.TitleManagerPane then
        PaperDollFrame.TitleManagerPane:HookScript("OnShow", function()
            SkinTitleManagerPane()
        end)
    end
end

-- Cross-module API. IsEnabled / OwnsBackground answer "does the skin gate
-- draw the shell" so the enhancement pane knows whether to delegate.
local function OwnsBackground()
    local chrome = GetChrome()
    if chrome and chrome.OwnsShell then return chrome.OwnsShell() end
    return IsSkinningEnabled() and true or false
end

local api = _G.QUI_CharacterFrameSkinning or {}
api.CONFIG = CONFIG
api.IsEnabled = IsSkinningEnabled
api.OwnsBackground = OwnsBackground
api.SetExtended = SetCharacterFrameBgExtended
api.Refresh = RefreshCharacterFrameColors
api.SkinEquipmentManager = SkinEquipmentManager
api.SkinTitleManager = SkinTitleManagerPane
api.StyleCloseButton = StyleCloseButton
_G.QUI_CharacterFrameSkinning = api

_G.QUI_RefreshCharacterFrameColors = RefreshCharacterFrameColors

if ns.Registry then
    ns.Registry:Register("skinCharacter", {
        refresh = _G.QUI_RefreshCharacterFrameColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local characterFrameSkinningInitialized = false

local function InitializeCharacterFrameSkinning()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if characterFrameSkinningInitialized or not CharacterFrame then return end
    characterFrameSkinningInitialized = true

    SetupCharacterFrameSkinning()
    SetupTitlePaneHook()
end

SkinBase.OnAddOnLoaded("Blizzard_CharacterFrame", InitializeCharacterFrameSkinning, 0)
SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", InitializeCharacterFrameSkinning, 0)
SkinBase.OnAddOnLoaded("Blizzard_Statistics", SkinNativeCharacterPanes, 0)
SkinBase.OnAddOnLoaded("Blizzard_TokenUI", SkinNativeCharacterPanes, 0)
