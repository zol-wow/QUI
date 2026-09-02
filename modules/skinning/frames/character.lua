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

local CharacterSkinning = {}
local CONFIG = {
    PANEL_WIDTH_EXTENSION = 55,
    PANEL_HEIGHT_EXTENSION = 50,
}

local COLORS = {
    text = { 0.9, 0.9, 0.9, 1 },
}

local customBg = nil

local iconBorders = Helpers.CreateStateTable()
local skinnedEntries = Helpers.CreateStateTable()
local titleHighlights = Helpers.CreateStateTable()

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

local function StyleThinScrollBar(scrollBar, r, g, b)
    SkinBase.SkinTrimScrollBar(scrollBar, { color = r and { r, g, b } or nil })
end

local function IsSkinningEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinCharacterFrame
end

local function IsCharacterPaneEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.character
    return not (settings and settings.enabled == false)
end

local MaskNativeStatsPane = ns.QUI_MaskNativeStatsPane

local function RestoreNativeStatsPane()
    if not CharacterStatsPane then return end
    ns.SafeCallMethod("best-effort-style", CharacterStatsPane, "SetAlpha", 1)
    ns.SafeCallMethodIfPresent("best-effort-style", CharacterStatsPane, "EnableMouse", true)
    if CharacterStatsPane.ClassBackground then
        ns.SafeCallMethod("best-effort-style", CharacterStatsPane.ClassBackground, "SetAlpha", 1)
    end
end

local function CreateOrUpdateBackground()
    if not CharacterFrame then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    if not customBg then
        customBg = CreateFrame("Frame", "QUI_CharacterFrameBg_Skin", CharacterFrame, "BackdropTemplate")
        customBg:SetFrameStrata("BACKGROUND")
        customBg:SetFrameLevel(0)
        customBg:EnableMouse(false)
    end

    ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

    return customBg
end

local nineSliceHooked = Helpers.CreateStateTable()

local function HideNineSlice(nineSlice)
    if not nineSlice then return end
    nineSlice:Hide()
    nineSlice:SetAlpha(0)
    if not nineSliceHooked[nineSlice] then
        hooksecurefunc(nineSlice, "Show", function(self) self:Hide(); self:SetAlpha(0) end)
        nineSliceHooked[nineSlice] = true
    end
end

local function HideBlizzardDecorations()
    SkinBase.HidePortraitFrameChrome(CharacterFrame)
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    HideNineSlice(CharacterFrame.NineSlice)
    HideNineSlice(CharacterFrameInset and CharacterFrameInset.NineSlice)
    HideNineSlice(CharacterFrameInsetRight and CharacterFrameInsetRight.NineSlice)
    if CharacterFrameBg then CharacterFrameBg:Hide() end
    if IsCharacterPaneEnabled() then
        MaskNativeStatsPane()
    else
        RestoreNativeStatsPane()
    end
end

local function SetCharacterFrameBgExtended(extended)
    if not customBg then
        CreateOrUpdateBackground()
    end
    if not customBg then return end

    customBg:ClearAllPoints()

    if extended then
        customBg:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
        customBg:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT",
            CONFIG.PANEL_WIDTH_EXTENSION, -CONFIG.PANEL_HEIGHT_EXTENSION)
    else
        customBg:SetAllPoints(CharacterFrame)
    end

    customBg:Show()
    HideBlizzardDecorations()
end

local function SkinCharacterFrameTabs()
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("CharacterFrame", 3), CharacterFrame, { font = true })
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

local function SetupCharacterFrameSkinning()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end
    if not CharacterFrame then return end

    CreateOrUpdateBackground()

    HideBlizzardDecorations()
    SkinCharacterFrameTabs()

    if ReputationFrame and ReputationFrame.ScrollBox then
        SkinBase.HookScrollBoxAcquired(ReputationFrame.ScrollBox, function(row)
            if IsSkinningEnabled() then
                SkinReputationEntry(row)
                SkinBase.LockPooledRowText(row, 4)
            end
        end)
    end
    if ReputationFrame and ReputationFrame.ReputationDetailFrame and SkinBase.ApplyButtonFontObjectsDeep then
        SkinBase.ApplyButtonFontObjectsDeep(ReputationFrame.ReputationDetailFrame, 2)
    end
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

    if ReputationFrame then
        ReputationFrame:HookScript("OnShow", function()
            if IsSkinningEnabled() then
                SetCharacterFrameBgExtended(false)
            end
        end)
        if ReputationFrame:IsShown() then
            SetCharacterFrameBgExtended(false)
        end
    end

    if TokenFrame then
        TokenFrame:HookScript("OnShow", function()
            if IsSkinningEnabled() then
                SetCharacterFrameBgExtended(false)
            end
        end)
        if TokenFrame:IsShown() then
            SetCharacterFrameBgExtended(false)
        end
    end

    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            if IsSkinningEnabled() then
                local core = GetCore()
                local charSettings = core and core.db and core.db.profile and core.db.profile.character
                local charPaneEnabled = charSettings and charSettings.enabled
                if charPaneEnabled == nil then charPaneEnabled = true end

                if not charPaneEnabled then
                    SetCharacterFrameBgExtended(false)
                end
            end
        end)
        if PaperDollFrame:IsShown() then
            local core = GetCore()
            local charSettings = core and core.db and core.db.profile and core.db.profile.character
            local charPaneEnabled = charSettings and charSettings.enabled
            if charPaneEnabled == nil then charPaneEnabled = true end
            if not charPaneEnabled then
                SetCharacterFrameBgExtended(false)
            end
        end
    end

    CharacterFrame:HookScript("OnShow", function()
        C_Timer.After(0.01, function()
            if IsSkinningEnabled() then
                SkinCharacterFrameTabs()
                if not (PaperDollFrame and PaperDollFrame:IsShown()) then
                    SetCharacterFrameBgExtended(false)
                end
            end
        end)
    end)
end

local RefreshEquipmentManagerColors
local RefreshTitlePaneColors

local function RefreshCharacterFrameColors()
    if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
    if not IsSkinningEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    if customBg then
        ApplyPixelBackdrop(customBg, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    SkinCharacterFrameTabs()

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

local function RestyleEquipmentSetEntryText(entry)
    local text = entry and entry.text
    if not text then return end
    CJKFont(text, GetFontPath(), 11, "")
    if text.SetTextColor then
        text:SetTextColor(0.9, 0.9, 0.9, 1)
    end
end

local function SkinEquipmentSetEntry(entry)
    if not entry then return end
    RestyleEquipmentSetEntryText(entry)
    if skinnedEntries[entry] then return end

    local sr, sg, sb, sa = GetSkinColors()

    if entry.icon and not iconBorders[entry.icon] then
        entry.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = CreateFrame("Frame", nil, entry, "BackdropTemplate")
        SetExpandedPixelPoints(border, entry.icon, 1)
        ApplyPixelBackdrop(border, 1, false, false, { sr, sg, sb, 1 })
        iconBorders[entry.icon] = border
    end

    if entry.SelectedBar then
        entry.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
    end
    if entry.HighlightBar then
        entry.HighlightBar:SetColorTexture(sr, sg, sb, 0.15)
    end

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

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    local fontPath = GetFontPath()

    if not skinnedEntries[popup] then
        ApplyPixelBackdrop(popup, 1, true, false, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        skinnedEntries[popup] = true
    end
    SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

    if popup.title then
        CJKFont(popup.title, fontPath, 12, "")
        popup.title:SetTextColor(GetTextAccent())
    end

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
        StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)
    end

    StyleEquipMgrButton(PaperDollFrameEquipSet)
    StyleEquipMgrButton(PaperDollFrameSaveSet)
end

RefreshEquipmentManagerColors = function()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_EquipMgrPopup
    if not popup or not skinnedEntries[popup] then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    if popup.title then
        popup.title:SetTextColor(GetTextAccent())
    end

    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if pane and pane.ScrollBox then
        SkinBase.ForEachScrollBoxFrame(pane.ScrollBox, function(entry)
            if not skinnedEntries[entry] then return end
            RestyleEquipmentSetEntryText(entry)
            if entry.icon and iconBorders[entry.icon] then
                SetPixelBackdropColors(iconBorders[entry.icon], { sr, sg, sb, 1 })
            end
            if entry.SelectedBar then
                entry.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
            end
            if entry.HighlightBar then
                entry.HighlightBar:SetColorTexture(sr, sg, sb, 0.15)
            end
        end)
    end
    if pane then
        StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)
    end

    if PaperDollFrameEquipSet and skinnedEntries[PaperDollFrameEquipSet] then
        SetPixelBackdropColors(PaperDollFrameEquipSet, { sr, sg, sb, 0.5 })
    end
    if PaperDollFrameSaveSet and skinnedEntries[PaperDollFrameSaveSet] then
        SetPixelBackdropColors(PaperDollFrameSaveSet, { sr, sg, sb, 0.5 })
    end
end

local function SkinTitleEntry(button)
    if skinnedEntries[button] then return end

    local sr, sg, sb, sa = GetSkinColors()
    local fontPath = GetFontPath()

    if button.text then
        CJKFont(button.text, fontPath, 12, "")
        button.text:SetTextColor(0.9, 0.9, 0.9, 1)
    end

    if button.Check then
        button.Check:SetVertexColor(GetTextAccent())
    end

    if button.SelectedBar then
        button.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
    end

    if button.BgTop then button.BgTop:Hide() end
    if button.BgMiddle then button.BgMiddle:Hide() end
    if button.BgBottom then button.BgBottom:Hide() end

    if button.Highlight then
        button.Highlight:SetColorTexture(sr, sg, sb, 0.15)
    elseif not titleHighlights[button] then
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(sr, sg, sb, 0.15)
        titleHighlights[button] = highlight
    end

    skinnedEntries[button] = true
end

local function SkinTitleManagerPane()
    if not IsSkinningEnabled() then return end

    local popup = _G.QUI_TitlesPopup
    local pane = PaperDollFrame and PaperDollFrame.TitleManagerPane
    if not pane then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()
    local fontPath = GetFontPath()

    if popup and not skinnedEntries[popup] then
        ApplyPixelBackdrop(popup, 1, true, true, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })

        if popup.title then
            CJKFont(popup.title, fontPath, 14, "")
            popup.title:SetTextColor(GetTextAccent())
        end

        skinnedEntries[popup] = true
    end

    if skinnedEntries[pane] then return end

    if pane.Bg then pane.Bg:Hide() end

    if pane.ScrollBox then
        SkinBase.HookScrollBoxAcquired(pane.ScrollBox, function(row)
            SkinTitleEntry(row)
            SkinBase.LockPooledRowText(row, 3)
        end)
    end

    if type(_G.PaperDollTitlesPane_InitButton) == "function"
        and not SkinBase.GetFrameData(pane, "qTitleInitHooked") then
        hooksecurefunc("PaperDollTitlesPane_InitButton", function(button)
            if not IsSkinningEnabled() or not button then return end
            if button.BgTop then button.BgTop:Hide() end
            if button.BgMiddle then button.BgMiddle:Hide() end
            if button.BgBottom then button.BgBottom:Hide() end
        end)
        SkinBase.SetFrameData(pane, "qTitleInitHooked", true)
    end

    StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)

    skinnedEntries[pane] = true
end

RefreshTitlePaneColors = function()
    if not IsSkinningEnabled() then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    local popup = _G.QUI_TitlesPopup
    if popup and skinnedEntries[popup] then
        SetPixelBackdropColors(popup, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        if popup.title then
            popup.title:SetTextColor(GetTextAccent())
        end
    end

    local pane = PaperDollFrame and PaperDollFrame.TitleManagerPane
    if not pane or not skinnedEntries[pane] then return end

    if pane.ScrollBox then
        SkinBase.ForEachScrollBoxFrame(pane.ScrollBox, function(button)
            if not skinnedEntries[button] then return end
            if button.Check then
                button.Check:SetVertexColor(GetTextAccent())
            end
            if button.SelectedBar then
                button.SelectedBar:SetColorTexture(sr, sg, sb, 0.3)
            end
            if titleHighlights[button] then
                titleHighlights[button]:SetColorTexture(sr, sg, sb, 0.15)
            end
        end)
    end
    StyleThinScrollBar(pane.ScrollBar or (pane.ScrollBox and pane.ScrollBox.ScrollBar), sr, sg, sb)
end

local function SetupTitlePaneHook()
    if PaperDollFrame and PaperDollFrame.TitleManagerPane then
        PaperDollFrame.TitleManagerPane:HookScript("OnShow", function()
            SkinTitleManagerPane()
        end)
    end
end

local api = _G.QUI_CharacterFrameSkinning or {}
api.CONFIG = CONFIG
api.IsEnabled = IsSkinningEnabled
api.SetExtended = SetCharacterFrameBgExtended
api.Refresh = RefreshCharacterFrameColors
api.SkinEquipmentManager = SkinEquipmentManager
api.SkinTitleManager = SkinTitleManagerPane
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
