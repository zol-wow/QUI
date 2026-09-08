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

local GetSkinColors = Helpers.CreateSkinColorGetter("characterFrame")

-- Border colour as TEXT colour, luminance-floored (black / hidden borders
-- otherwise turn headers and popup titles black or invisible).
local function GetTextAccent()
    local profile = Helpers.GetProfile and Helpers.GetProfile()
    return SkinBase.GetSkinTextAccent(profile and profile.general, "characterFrame")
end

local GetFontPath = Helpers.GetGeneralFont

local function ApplyPixelBackdrop(frame, borderPixels, withBackground, withInsets, borderColor, bgColor)
    SkinBase.ApplyPixelBackdrop(frame, borderPixels, withBackground, withInsets, borderColor, bgColor)
end

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

local function SkinToggleCollapseButton(ToggleCollapseButton)
    if ToggleCollapseButton and ToggleCollapseButton.RefreshIcon then
        local function UpdateToggleButton(button)
            local header = button.GetHeader and button:GetHeader()
            if not header then return end
            if header:IsCollapsed() then
                button:GetNormalTexture():SetAtlas("Gamepad_Expand", true)
                button:GetPushedTexture():SetAtlas("Gamepad_Expand", true)
            else
                button:GetNormalTexture():SetAtlas("Gamepad_Collapse", true)
                button:GetPushedTexture():SetAtlas("Gamepad_Collapse", true)
            end
        end
        hooksecurefunc(ToggleCollapseButton, "RefreshIcon", UpdateToggleButton)
        UpdateToggleButton(ToggleCollapseButton)
    end
end

local function SkinReputationEntry(child)
    if skinnedEntries[child] then return end

    local sr, sg, sb, sa = GetSkinColors()
    local fontPath = GetFontPath()

    if child.Right then
        SkinEntryHeader(child, fontPath, sr, sg, sb)
    end

    local ReputationBar = child.Content and child.Content.ReputationBar
    if ReputationBar then
        ReputationBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        UIKit.DisablePixelSnap(ReputationBar)

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

        if ReputationBar.BarText then
            CJKFont(ReputationBar.BarText, fontPath, 10, "")
            ReputationBar.BarText:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3], 1)
        end

        if not SkinBase.GetFrameData(ReputationBar, "backdrop") then
            local backdrop = CreateFrame("Frame", nil, ReputationBar:GetParent(), "BackdropTemplate")
            backdrop:SetFrameLevel(math.max(0, ReputationBar:GetFrameLevel() - 1))
            local dr, dg, db, da = SkinBase.GetDepthColor("ROW")
            SetExpandedPixelPoints(backdrop, ReputationBar, SkinBase.CHROME.BORDER_PX)
            ApplyPixelBackdrop(backdrop, SkinBase.CHROME.BORDER_PX, true, false, { sr, sg, sb, 1 }, { dr, dg, db, da })
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

    local sr, sg, sb, sa = GetSkinColors()
    local fontPath = GetFontPath()

    if child.Right then
        SkinEntryHeader(child, fontPath, sr, sg, sb)
    end

    local CurrencyIcon = child.Content and child.Content.CurrencyIcon
    if CurrencyIcon then
        CurrencyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        if not iconBorders[CurrencyIcon] then
            local border = CreateFrame("Frame", nil, CurrencyIcon:GetParent(), "BackdropTemplate")
            local drawLayer = CurrencyIcon.GetDrawLayer and CurrencyIcon:GetDrawLayer()
            border:SetFrameLevel((drawLayer == "OVERLAY") and child:GetFrameLevel() + 2 or child:GetFrameLevel() + 1)
            SetExpandedPixelPoints(border, CurrencyIcon, 1)
            ApplyPixelBackdrop(border, 1, false, false, { sr, sg, sb, 1 })
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
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    if not SkinBase.GetFrameData(detail, "qRepDetailChrome") then
        SkinBase.SetFrameData(detail, "qRepDetailChrome", true)
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
            if check and check.Label then
                SkinBase.SkinFontString(check.Label, { size = 11, color = RowToken("tabHover") })
            end
        end
        if SkinBase.ApplyButtonFontObjectsDeep then
            SkinBase.ApplyButtonFontObjectsDeep(detail, 2)
        end
        StyleCloseButton(detail.CloseButton)
        StyleThinScrollBar(detail.ScrollingDescriptionScrollBar)
    end
    SkinBase.CreateBackdrop(detail, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if detail.Title then detail.Title:SetTextColor(GetTextAccent()) end
end

-- Currency options popup: backdrop + title + close ONLY. The checkboxes and
-- the transfer toggle are part of the protected currency-transfer flow; a
-- write there taints RequestCurrencyFromAccountCharacter.
local function SkinTokenFramePopup()
    local popup = _G.TokenFramePopup or (TokenFrame and TokenFrame.Popup)
    if not popup then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    if not SkinBase.GetFrameData(popup, "qTokenPopupChrome") then
        SkinBase.SetFrameData(popup, "qTokenPopupChrome", true)
        if popup.Border then popup.Border:SetAlpha(0) end
        if popup.Title then
            SkinBase.SkinFontString(popup.Title, { size = 13, color = { GetTextAccent() } })
        end
        StyleCloseButton(popup.CloseButton)
    end
    SkinBase.CreateBackdrop(popup, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if popup.Title then popup.Title:SetTextColor(GetTextAccent()) end
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

    local sr, sg, sb = GetSkinColors()

    local chrome = GetChrome()
    if chrome and chrome.RefreshTheme then
        chrome.RefreshTheme()
    else
        SkinCharacterFrameTabs()
    end
    SkinReputationDetailFrame()
    SkinTokenFramePopup()

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
        bar:SetWidth(SkinBase.GetPixelSize(row, 1) * 2)
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

    local ar, ag, ab = GetTextAccent()
    local bar = EnsureRowAccentBar(row)
    if bar then
        bar:SetColorTexture(ar, ag, ab, 1)
        if selected then bar:Show() else bar:Hide() end
    end
    if row.Check and row.Check.SetVertexColor then
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
    if skinnedEntries[entry] then return end

    local sr, sg, sb = GetSkinColors()

    if entry.icon and not iconBorders[entry.icon] then
        entry.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = CreateFrame("Frame", nil, entry, "BackdropTemplate")
        SetExpandedPixelPoints(border, entry.icon, 1)
        ApplyPixelBackdrop(border, 1, false, false, { sr, sg, sb, 1 })
        iconBorders[entry.icon] = border
    end

    HookRowHover(entry)
    ApplyRowState(entry, false)

    skinnedEntries[entry] = true
end

local function StyleEquipMgrButton(btn)
    if not btn or skinnedEntries[btn] then return end

    local sr, sg, sb, sa = GetSkinColors()

    local origWidth = btn:GetWidth()

    if btn:GetNormalTexture() then btn:GetNormalTexture():SetTexture(nil) end
    if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetTexture(nil) end
    if btn:GetPushedTexture() then btn:GetPushedTexture():SetTexture(nil) end
    if btn:GetDisabledTexture() then btn:GetDisabledTexture():SetTexture(nil) end

    if not btn.SetBackdrop then
        return
    end
    ApplyPixelBackdrop(btn, 1, true, false, { sr, sg, sb, 0.5 }, { 0.15, 0.15, 0.15, 1 })

    SkinBase.ApplyButtonFontObjects(btn, { size = 11, color = { 0.9, 0.9, 0.9, 1 }, disabledColor = { 0.5, 0.5, 0.5, 1 } })

    btn:SetWidth(origWidth)

    btn:HookScript("OnEnter", function(self)
        local r, g, b = GetSkinColors()
        SetPixelBackdropColors(self, { r, g, b, 1 })
    end)
    btn:HookScript("OnLeave", function(self)
        local r, g, b = GetSkinColors()
        SetPixelBackdropColors(self, { r, g, b, 0.5 })
    end)

    skinnedEntries[btn] = true
end

local function SkinEquipmentManager()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_EquipMgrPopup
    if not popup then return end

    -- Popout chrome (backdrop, title, close) is the owner's; re-tint only.
    local chrome = GetChrome()
    if chrome and chrome.RefreshPopout then chrome.RefreshPopout(popup) end
    skinnedEntries[popup] = true

    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        SkinBase.HookScrollBoxAcquired(pane.ScrollBox, function(row)
            if IsSkinningEnabled() then SkinEquipmentSetEntry(row) end
        end)
    end

    if type(_G.PaperDollEquipmentManagerPane_InitButton) == "function"
        and not SkinBase.GetFrameData(pane, "qEquipInitHooked") then
        hooksecurefunc("PaperDollEquipmentManagerPane_InitButton", function(button)
            if not IsSkinningEnabled() or not button then return end
            RestyleEquipmentSetEntryText(button)
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

    local sr, sg, sb = GetSkinColors()

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
    end

    HideTitleRowArt(button)

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
        local ar, ag, ab = GetTextAccent()
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
