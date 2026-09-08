local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local GetCore = ns.Helpers.GetCore
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local function HidePVEDecorations()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame then return end

    if PVEFrame.shadows then
        PVEFrame.shadows:Hide()
        SkinBase.StripTextures(PVEFrame.shadows)
    end

    if _G.PVEFrameBlueBg then _G.PVEFrameBlueBg:Hide() end
    if _G.PVEFrameTLCorner then _G.PVEFrameTLCorner:Hide() end
    if _G.PVEFrameTRCorner then _G.PVEFrameTRCorner:Hide() end
    if _G.PVEFrameBRCorner then _G.PVEFrameBRCorner:Hide() end
    if _G.PVEFrameBLCorner then _G.PVEFrameBLCorner:Hide() end
    if _G.PVEFrameLLVert then _G.PVEFrameLLVert:Hide() end
    if _G.PVEFrameRLVert then _G.PVEFrameRLVert:Hide() end
    if _G.PVEFrameBottomLine then _G.PVEFrameBottomLine:Hide() end
    if _G.PVEFrameTopLine then _G.PVEFrameTopLine:Hide() end
    if _G.PVEFrameTopFiligree then _G.PVEFrameTopFiligree:Hide() end
    if _G.PVEFrameBottomFiligree then _G.PVEFrameBottomFiligree:Hide() end

    SkinBase.HidePortraitFrameChrome(PVEFrame)

    if _G.PVEFrameLeftInset then _G.PVEFrameLeftInset:Hide() end
    if PVEFrame.Inset then PVEFrame.Inset:Hide() end
    if _G.PVEFramePortrait then _G.PVEFramePortrait:Hide() end
    if _G.PVEFrameTitleBg then _G.PVEFrameTitleBg:Hide() end

    if _G.PVEFrameTopBorder then _G.PVEFrameTopBorder:Hide() end
    if _G.PVEFrameTopRightCorner then _G.PVEFrameTopRightCorner:Hide() end
    if _G.PVEFrameRightBorder then _G.PVEFrameRightBorder:Hide() end
    if _G.PVEFrameBottomRightCorner then _G.PVEFrameBottomRightCorner:Hide() end
    if _G.PVEFrameBottomBorder then _G.PVEFrameBottomBorder:Hide() end
    if _G.PVEFrameBottomLeftCorner then _G.PVEFrameBottomLeftCorner:Hide() end
    if _G.PVEFrameLeftBorder then _G.PVEFrameLeftBorder:Hide() end
    if _G.PVEFrameBtnCornerLeft then _G.PVEFrameBtnCornerLeft:Hide() end
    if _G.PVEFrameBtnCornerRight then _G.PVEFrameBtnCornerRight:Hide() end
    if _G.PVEFrameButtonBottomBorder then _G.PVEFrameButtonBottomBorder:Hide() end

    if _G.PVEFrameBg then _G.PVEFrameBg:Hide() end
    if _G.PVEFrameBackground then _G.PVEFrameBackground:Hide() end
    if _G.PVEFrameInset then _G.PVEFrameInset:Hide() end
    if _G.PVEFrameNineSlice then _G.PVEFrameNineSlice:Hide() end

    SkinBase.StripTextures(PVEFrame)
end

local function ButtonBoostColors(bgr, bgg, bgb)
    return math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1),
           math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1),
           math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
end

local function AddSkinColorHoverBorder(button)
    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            SkinBase.SetBackdropColors(bd, { SkinBase.HoverBrightenColor(sc[1], sc[2], sc[3], sc[4]) }, nil)
        end
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            SkinBase.SetBackdropColors(bd, { sc[1], sc[2], sc[3], sc[4] }, nil)
        end
    end)
end

local function StyleGroupFinderButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    if button.ring then button.ring:Hide() end
    if button.Ring then button.Ring:Hide() end
    if button.bg then button.bg:SetAlpha(0) end
    if button.Background then button.Background:Hide() end

    local backdrop = SkinBase.GetFrameData(button, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(button:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", backdrop)
    end

    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    SkinBase.ApplyFullBackdrop(backdrop, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)

    if button.icon then
        button.icon:SetSize(40, 40)
        button.icon:ClearAllPoints()
        button.icon:SetPoint("LEFT", 8, 0)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local iconBackdrop = SkinBase.GetFrameData(button.icon, "backdrop")
        if not iconBackdrop then
            iconBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(iconBackdrop, button.icon, 1)
            iconBackdrop:SetFrameLevel(button:GetFrameLevel())
            iconBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(iconBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(iconBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(button.icon, "backdrop", iconBackdrop)
        end
    end

    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })

    if button.name then
        SkinBase.SkinFontString(button.name, { fontOnly = true })
    end

    AddSkinColorHoverBorder(button)

    SkinBase.MarkStyled(button)
end

local function SkinPVEFrame()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame or SkinBase.IsSkinned(PVEFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HidePVEDecorations()

    SkinBase.CreateBackdrop(PVEFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.SkinCloseButton(PVEFrame.CloseButton or _G.PVEFrameCloseButton)

    local pveTabs = {}
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        if tab then pveTabs[#pveTabs + 1] = tab end
    end
    SkinBase.SkinTabGroup(pveTabs, PVEFrame, { resizeToText = true })

    local pveTab1, pveTab2, pveTab3 = _G.PVEFrameTab1, _G.PVEFrameTab2, _G.PVEFrameTab3
    if pveTab1 then
        pveTab1:ClearAllPoints()
        pveTab1:SetPoint("BOTTOMLEFT", PVEFrame, "BOTTOMLEFT", -3, -30)
    end
    if pveTab2 then
        pveTab2:ClearAllPoints()
        pveTab2:SetPoint("TOPLEFT", pveTab1 or PVEFrame, "TOPRIGHT", -5, 0)
    end
    if pveTab3 then
        pveTab3:ClearAllPoints()
        pveTab3:SetPoint("TOPLEFT", pveTab2 or pveTab1 or PVEFrame, "TOPRIGHT", -5, 0)
    end

    hooksecurefunc("PVEFrame_ShowFrame", function()
        C_Timer.After(0, function()
            local tab4 = _G.PVEFrameTab4
            if not tab4 or not tab4:IsShown() then return end
            local tab2 = _G.PVEFrameTab2
            local tab3 = _G.PVEFrameTab3
            local twoShown = tab2 and tab2:IsShown()
            local threeShown = tab3 and tab3:IsShown()
            tab4:ClearAllPoints()
            tab4:SetPoint("TOPLEFT", (twoShown and threeShown and tab3) or (twoShown and not threeShown and tab2) or _G.PVEFrameTab1, "TOPRIGHT", -5, 0)
        end)
    end)

    local GroupFinderFrame = _G.GroupFinderFrame
    if GroupFinderFrame then
        for i = 1, 4 do
            local button = GroupFinderFrame["groupButton" .. i]
            if button then
                StyleGroupFinderButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
    end

    SkinBase.MarkSkinned(PVEFrame)
end

local function HideLFDDecorations()
    local LFDQueueFrame = _G.LFDQueueFrame
    if not LFDQueueFrame then return end

    if _G.LFDParentFrame then
        SkinBase.StripTextures(_G.LFDParentFrame)
    end
    if _G.LFDParentFrameInset then
        SkinBase.StripTextures(_G.LFDParentFrameInset)
        _G.LFDParentFrameInset:Hide()
    end

    if LFDQueueFrame.Bg then LFDQueueFrame.Bg:Hide() end
    if LFDQueueFrame.Background then LFDQueueFrame.Background:Hide() end
    if LFDQueueFrame.NineSlice then LFDQueueFrame.NineSlice:Hide() end

    if _G.LFDQueueFrameBackground then _G.LFDQueueFrameBackground:Hide() end
    if _G.LFDQueueFrameRandomScrollFrameScrollBarBorder then
        _G.LFDQueueFrameRandomScrollFrameScrollBarBorder:Hide()
    end

    SkinBase.StripTextures(LFDQueueFrame)
end

local function HideRaidFinderDecorations()
    local RaidFinderFrame = _G.RaidFinderFrame
    if not RaidFinderFrame then return end

    SkinBase.StripTextures(RaidFinderFrame)

    if _G.RaidFinderFrameRoleBackground then
        _G.RaidFinderFrameRoleBackground:Hide()
    end
    if RaidFinderFrame.RoleBackground then
        RaidFinderFrame.RoleBackground:Hide()
    end

    local roleInset = _G.RaidFinderFrameRoleInset or (RaidFinderFrame.Inset)
    if roleInset then
        SkinBase.StripTextures(roleInset)
        roleInset:Hide()
    end

    local bottomInset = _G.RaidFinderFrameBottomInset
    if bottomInset then
        SkinBase.StripTextures(bottomInset)
        bottomInset:Hide()
    end

    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if RaidFinderQueueFrame then
        SkinBase.StripTextures(RaidFinderQueueFrame)
        if RaidFinderQueueFrame.Bg then RaidFinderQueueFrame.Bg:Hide() end
        if RaidFinderQueueFrame.Background then RaidFinderQueueFrame.Background:Hide() end

        local scrollFrame = _G.RaidFinderQueueFrameScrollFrame
        if scrollFrame then
            SkinBase.StripTextures(scrollFrame)
        end
    end

    if _G.RaidFinderQueueFrameBackground then _G.RaidFinderQueueFrameBackground:Hide() end

    for _, name in ipairs({"NineSlice", "Bg", "Border", "Background", "InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight"}) do
        local child = RaidFinderFrame[name]
        if child and child.Hide then child:Hide() end
    end
end

local function SkinLFDFrame()
    local LFDQueueFrame = _G.LFDQueueFrame
    if not LFDQueueFrame or SkinBase.IsSkinned(LFDQueueFrame) then return end

    HideLFDDecorations()

    local roles = { "Tank", "Healer", "DPS" }
    for _, role in ipairs(roles) do
        local button = _G["LFDQueueFrameRoleButton" .. role]
        if button then
            if button.background then button.background:SetAlpha(0) end
            if button.Background then button.Background:SetAlpha(0) end
            local bgTex = _G["LFDQueueFrameRoleButton" .. role .. "Background"]
            if bgTex then bgTex:SetAlpha(0) end

            if button.shortageBorder then button.shortageBorder:SetAlpha(0) end
            if button.cover then button.cover:SetAlpha(0) end
            if button.checkButton then
                SkinBase.SkinCheckBox(button.checkButton)
            end
            local incentiveIcon = _G["LFDQueueFrameRoleButton" .. role .. "IncentiveIcon"]
            if incentiveIcon then incentiveIcon:SetAlpha(0) end
        end
    end

    if _G.LFDQueueFrameFindGroupButton then
        SkinBase.SkinButton(_G.LFDQueueFrameFindGroupButton, { font = true })
    end

    local typeDropdown = LFDQueueFrame.TypeDropdown or _G.LFDQueueFrameTypeDropdown
    if typeDropdown then
        typeDropdown:SetWidth(200)
        SkinBase.SkinDropdown(typeDropdown, { keepArrow = true, insetY = 2 })
        SkinBase.LockDropdownText(typeDropdown)
    end

    local specificList = LFDQueueFrame.Specific
    if specificList and specificList.ScrollBox then
        SkinBase.HookScrollBoxRowFonts(specificList.ScrollBox, 2)
    end
    local followerList = LFDQueueFrame.Follower
    if followerList and followerList.ScrollBox then
        SkinBase.HookScrollBoxRowFonts(followerList.ScrollBox, 2)
    end

    SkinBase.MarkSkinned(LFDQueueFrame)
end

local function SkinRaidFinderFrame()
    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if not RaidFinderQueueFrame or SkinBase.IsSkinned(RaidFinderQueueFrame) then return end

    HideRaidFinderDecorations()

    local roles = { "Tank", "Healer", "DPS" }
    for _, role in ipairs(roles) do
        local button = _G["RaidFinderQueueFrameRoleButton" .. role]
        if button then
            if button.background then button.background:SetAlpha(0) end
            if button.Background then button.Background:SetAlpha(0) end
            local bgTex = _G["RaidFinderQueueFrameRoleButton" .. role .. "Background"]
            if bgTex then bgTex:SetAlpha(0) end

            if button.shortageBorder then button.shortageBorder:SetAlpha(0) end
            if button.cover then button.cover:SetAlpha(0) end
            if button.checkButton then
                SkinBase.SkinCheckBox(button.checkButton)
            end
            local incentiveIcon = _G["RaidFinderQueueFrameRoleButton" .. role .. "IncentiveIcon"]
            if incentiveIcon then incentiveIcon:SetAlpha(0) end
        end
    end

    if _G.RaidFinderFrameFindRaidButton then
        SkinBase.SkinButton(_G.RaidFinderFrameFindRaidButton, { font = true })
    end

    local selectionDropdown = RaidFinderQueueFrame.SelectionDropdown
    if selectionDropdown then
        selectionDropdown:SetWidth(200)
        SkinBase.SkinDropdown(selectionDropdown, { keepArrow = true, insetY = 2 })
        SkinBase.LockDropdownText(selectionDropdown)
    end

    SkinBase.MarkSkinned(RaidFinderQueueFrame)
end

local function HideLFGListDecorations()
    local LFGListFrame = _G.LFGListFrame
    if not LFGListFrame then return end

    if LFGListFrame.Bg then LFGListFrame.Bg:Hide() end
    if LFGListFrame.Background then LFGListFrame.Background:Hide() end
    if LFGListFrame.NineSlice then LFGListFrame.NineSlice:Hide() end

    if LFGListFrame.CategorySelection then
        local cs = LFGListFrame.CategorySelection
        if cs.Inset then
            cs.Inset:Hide()
            if cs.Inset.NineSlice then cs.Inset.NineSlice:Hide() end
        end
        SkinBase.StripTextures(cs)
    end

    if LFGListFrame.SearchPanel then
        local sp = LFGListFrame.SearchPanel
        if sp.ResultsInset then
            sp.ResultsInset:Hide()
            if sp.ResultsInset.NineSlice then sp.ResultsInset.NineSlice:Hide() end
        end
        if sp.AutoCompleteFrame then
            SkinBase.StripTextures(sp.AutoCompleteFrame)
        end
        SkinBase.StripTextures(sp)
    end

    if LFGListFrame.ApplicationViewer then
        local av = LFGListFrame.ApplicationViewer
        if av.Inset then
            av.Inset:Hide()
            if av.Inset.NineSlice then av.Inset.NineSlice:Hide() end
        end
        if av.InfoBackground then av.InfoBackground:Hide() end
        SkinBase.StripTextures(av)
    end

    if LFGListFrame.EntryCreation then
        local ec = LFGListFrame.EntryCreation
        if ec.Inset then
            ec.Inset:Hide()
            if ec.Inset.NineSlice then ec.Inset.NineSlice:Hide() end
        end
        SkinBase.StripTextures(ec)
    end

    SkinBase.StripTextures(LFGListFrame)
end

local function SkinLFGListFrame()
    local LFGListFrame = _G.LFGListFrame
    if not LFGListFrame or SkinBase.IsSkinned(LFGListFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    local actionTextColor = { 1.0, 0.82, 0.0, 1 }

    HideLFGListDecorations()

    if LFGListFrame.CategorySelection then
        local cs = LFGListFrame.CategorySelection
        local function StyleCategoryNavButtons()
            if cs.StartGroupButton then
                SkinBase.SkinButton(cs.StartGroupButton, { font = true, fontColor = actionTextColor })
                SkinBase.RefreshButtonVisualState(cs.StartGroupButton)
            end
            if cs.FindGroupButton then
                SkinBase.SkinButton(cs.FindGroupButton, { font = true, fontColor = actionTextColor })
                SkinBase.RefreshButtonVisualState(cs.FindGroupButton)
            end
        end
        StyleCategoryNavButtons()
        local function StyleCategoryButtons()
            if not cs.CategoryButtons then return end
            for _, catButton in pairs(cs.CategoryButtons) do
                if catButton then
                    SkinBase.SkinCategoryButton(catButton, {
                        font = true,
                        selectedTextColor = actionTextColor,
                    })
                    SkinBase.SetFrameData(catButton, "categorySelectedTextColor", actionTextColor)
                    SkinBase.RefreshCategorySelected(catButton)
                end
            end
        end
        StyleCategoryButtons()
        if type(_G.LFGListCategorySelection_UpdateCategoryButtons) == "function"
            and not SkinBase.GetFrameData(cs, "qCatButtonsHooked") then
            hooksecurefunc("LFGListCategorySelection_UpdateCategoryButtons", function()
                StyleCategoryButtons()
            end)
            SkinBase.SetFrameData(cs, "qCatButtonsHooked", true)
        end
        if type(_G.LFGListCategorySelection_UpdateNavButtons) == "function"
            and not SkinBase.GetFrameData(cs, "qCatNavButtonsHooked") then
            hooksecurefunc("LFGListCategorySelection_UpdateNavButtons", function(panel)
                if panel == cs then StyleCategoryNavButtons() end
            end)
            SkinBase.SetFrameData(cs, "qCatNavButtonsHooked", true)
        end
    end

    if LFGListFrame.SearchPanel then
        local sp = LFGListFrame.SearchPanel
        if sp.BackButton then
            SkinBase.SkinButton(sp.BackButton, { font = true })
        end
        if sp.SignUpButton then
            SkinBase.SkinButton(sp.SignUpButton, { font = true })
        end
        if sp.RefreshButton then
            SkinBase.SkinButton(sp.RefreshButton, { font = true })
        end
        if sp.SearchBox then
            SkinBase.SkinEditBox(sp.SearchBox)
        end
        if sp.FilterButton then
            SkinBase.SkinButton(sp.FilterButton, { font = true })
        end
        if sp.ScrollBox then
            SkinBase.HookScrollBoxRowFonts(sp.ScrollBox, 2)
        end
        if sp.AutoCompleteFrame and type(_G.LFGListSearchPanel_UpdateAutoComplete) == "function"
            and not SkinBase.GetFrameData(sp, "qAutoCompleteFontHooked") then
            hooksecurefunc("LFGListSearchPanel_UpdateAutoComplete", function(panel)
                local acf = panel and panel.AutoCompleteFrame
                if not acf or not acf.Results then return end
                for i = 1, #acf.Results do
                    if acf.Results[i] then SkinBase.ApplyButtonFontObjects(acf.Results[i]) end
                end
            end)
            SkinBase.SetFrameData(sp, "qAutoCompleteFontHooked", true)
        end
    end

    if LFGListFrame.ApplicationViewer then
        local av = LFGListFrame.ApplicationViewer
        if av.ScrollBox then
            SkinBase.HookScrollBoxRowFonts(av.ScrollBox, 3)
        end
        if av.RefreshButton then
            SkinBase.SkinButton(av.RefreshButton, { font = true })
        end
        if av.RemoveEntryButton then
            SkinBase.SkinButton(av.RemoveEntryButton, { font = true })
        end
        if av.EditButton then
            SkinBase.SkinButton(av.EditButton, { font = true })
        end
        if av.AutoAcceptButton then
            if av.AutoAcceptButton.Label then
                SkinBase.SkinFontString(av.AutoAcceptButton.Label, { fontOnly = true })
            end
        end
    end

    if LFGListFrame.EntryCreation then
        local ec = LFGListFrame.EntryCreation
        if ec.ListGroupButton then
            SkinBase.SkinButton(ec.ListGroupButton, { font = true })
        end
        if ec.CancelButton then
            SkinBase.SkinButton(ec.CancelButton, { font = true })
        end
    end

    SkinBase.MarkSkinned(LFGListFrame)
end

local function HideChallengesDecorations()
    local ChallengesFrame = _G.ChallengesFrame
    if not ChallengesFrame then return end

    if ChallengesFrame.Background then ChallengesFrame.Background:Hide() end
    if ChallengesFrame.Bg then ChallengesFrame.Bg:Hide() end
    if ChallengesFrame.NineSlice then ChallengesFrame.NineSlice:Hide() end

    if ChallengesFrame.SeasonChangeNoticeFrame then
        SkinBase.StripTextures(ChallengesFrame.SeasonChangeNoticeFrame)
    end

    SkinBase.StripTextures(ChallengesFrame)
end

local function StyleDungeonIcon(icon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not icon or SkinBase.IsStyled(icon) then return end

    if icon.Bg then icon.Bg:SetAlpha(0) end
    if icon.Background then icon.Background:SetAlpha(0) end

    if icon.Icon then
        icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local iconBackdrop = SkinBase.GetFrameData(icon.Icon, "backdrop")
        if not iconBackdrop then
            iconBackdrop = CreateFrame("Frame", nil, icon, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(iconBackdrop, icon.Icon, 1)
            iconBackdrop:SetFrameLevel(icon:GetFrameLevel())
            iconBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(iconBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(iconBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(icon.Icon, "backdrop", iconBackdrop)
        end
    end

    SkinBase.SetFrameData(icon, "skinColor", { sr, sg, sb, sa })

    SkinBase.MarkStyled(icon)
end

local function StyleAffixIcon(affix, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not affix or SkinBase.IsStyled(affix) then return end

    if affix.Border then affix.Border:SetAlpha(0) end

    if affix.Portrait then
        affix.Portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local portraitBackdrop = SkinBase.GetFrameData(affix.Portrait, "backdrop")
        if not portraitBackdrop then
            portraitBackdrop = CreateFrame("Frame", nil, affix, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(portraitBackdrop, affix.Portrait, 1)
            portraitBackdrop:SetFrameLevel(affix:GetFrameLevel())
            portraitBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(portraitBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(portraitBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(affix.Portrait, "backdrop", portraitBackdrop)
        end
    end

    SkinBase.MarkStyled(affix)
end

local function SkinChallengesFrame()
    local ChallengesFrame = _G.ChallengesFrame
    if not ChallengesFrame or SkinBase.IsSkinned(ChallengesFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HideChallengesDecorations()

    if ChallengesFrame.WeeklyInfo then
        local wi = ChallengesFrame.WeeklyInfo
        if wi.Child then
            if wi.Child.WeeklyChest then
                local chest = wi.Child.WeeklyChest
                if chest.Highlight then chest.Highlight:SetAlpha(0) end
            end
            if wi.Child.ThisWeekLabel then
                SkinBase.SkinFontString(wi.Child.ThisWeekLabel, { size = 14, outline = "OUTLINE", fontOnly = true })
                SkinBase.LockFontObject(wi.Child.ThisWeekLabel)
            end
        end
    end

    if ChallengesFrame.DungeonIcons then
        for _, icon in pairs(ChallengesFrame.DungeonIcons) do
            StyleDungeonIcon(icon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    if ChallengesFrame.Update and not SkinBase.GetFrameData(ChallengesFrame, "updateHooked") then
        hooksecurefunc(ChallengesFrame, "Update", function(self)
            C_Timer.After(0, function()
                if self.DungeonIcons then
                    local sr2, sg2, sb2, sa2, bgr2, bgg2, bgb2, bga2 = SkinBase.GetSkinColors()
                    for _, icon in pairs(self.DungeonIcons) do
                        StyleDungeonIcon(icon, sr2, sg2, sb2, sa2, bgr2, bgg2, bgb2, bga2)
                    end
                end
            end)
        end)
        SkinBase.SetFrameData(ChallengesFrame, "updateHooked", true)
    end

    if ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child then
        local affixContainer = ChallengesFrame.WeeklyInfo.Child.AffixesContainer
        if affixContainer and affixContainer.Affixes then
            for _, affix in pairs(affixContainer.Affixes) do
                StyleAffixIcon(affix, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
    end

    for i = 1, 4 do
        local affix = ChallengesFrame["Affix" .. i]
        if affix then
            StyleAffixIcon(affix, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    SkinBase.MarkSkinned(ChallengesFrame)
end

local function HidePVPDecorations()
    local PVPQueueFrame = _G.PVPQueueFrame
    if not PVPQueueFrame then return end

    if PVPQueueFrame.Bg then PVPQueueFrame.Bg:Hide() end
    if PVPQueueFrame.Background then PVPQueueFrame.Background:Hide() end
    if PVPQueueFrame.NineSlice then PVPQueueFrame.NineSlice:Hide() end

    if PVPQueueFrame.HonorInset then
        if PVPQueueFrame.HonorInset.NineSlice then PVPQueueFrame.HonorInset.NineSlice:Hide() end
    end

    if _G.HonorFrame then
        local hf = _G.HonorFrame
        if hf.Bg then hf.Bg:Hide() end
        if hf.Background then hf.Background:Hide() end
        if hf.NineSlice then hf.NineSlice:Hide() end
        if hf.Inset then
            hf.Inset:Hide()
            if hf.Inset.NineSlice then hf.Inset.NineSlice:Hide() end
        end
        if hf.BonusFrame then
            if hf.BonusFrame.ShadowOverlay then hf.BonusFrame.ShadowOverlay:Hide() end
            if hf.BonusFrame.WorldBattlesTexture then hf.BonusFrame.WorldBattlesTexture:Hide() end
            SkinBase.StripTextures(hf.BonusFrame)
        end
        SkinBase.StripTextures(hf)
    end

    if _G.ConquestFrame then
        local cf = _G.ConquestFrame
        if cf.Bg then cf.Bg:Hide() end
        if cf.Background then cf.Background:Hide() end
        if cf.NineSlice then cf.NineSlice:Hide() end
        if cf.Inset then
            cf.Inset:Hide()
            if cf.Inset.NineSlice then cf.Inset.NineSlice:Hide() end
        end
        if cf.ShadowOverlay then cf.ShadowOverlay:Hide() end
        SkinBase.StripTextures(cf)
    end

    SkinBase.StripTextures(PVPQueueFrame)
end

local function StylePVPActivityButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    if button.NormalTexture then button.NormalTexture:SetTexture(nil) end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then pushed:SetTexture(nil) end
    if button.HighlightTexture then button.HighlightTexture:SetTexture(nil) end
    if button.Bg then button.Bg:Hide() end
    if button.Border then button.Border:Hide() end
    if button.Ring then button.Ring:Hide() end

    local backdrop = SkinBase.GetFrameData(button, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(button:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", backdrop)
    end

    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true)

    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    Helpers.SetFrameBackdropColor(backdrop, btnBgR, btnBgG, btnBgB, 1)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)

    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.2)
        SkinBase.DisablePixelSnap(button.SelectedTexture)
    end

    if button.Reward then
        local reward = button.Reward
        if reward.Border then reward.Border:Hide() end
        if reward.CircleMask then reward.CircleMask:Hide() end
        if reward.Icon then
            reward.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local rewardIconBackdrop = SkinBase.GetFrameData(reward.Icon, "backdrop")
            if not rewardIconBackdrop then
                rewardIconBackdrop = CreateFrame("Frame", nil, reward, "BackdropTemplate")
                SkinBase.SetExpandedPixelPoints(rewardIconBackdrop, reward.Icon, 1)
                rewardIconBackdrop:SetFrameLevel(reward:GetFrameLevel())
                rewardIconBackdrop:EnableMouse(false)
                SkinBase.ApplyPixelBackdrop(rewardIconBackdrop, 1, false, false)
                Helpers.SetFrameBackdropBorderColor(rewardIconBackdrop, sr, sg, sb, sa)
                SkinBase.SetFrameData(reward.Icon, "backdrop", rewardIconBackdrop)
            end
        end
    end

    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })

    AddSkinColorHoverBorder(button)

    SkinBase.MarkStyled(button)
end

local function StylePVPRoleIcon(roleIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not roleIcon or SkinBase.IsStyled(roleIcon) then return end

    if roleIcon.background then roleIcon.background:SetAlpha(0) end
    if roleIcon.Background then roleIcon.Background:SetAlpha(0) end
    if roleIcon.shortageBorder then roleIcon.shortageBorder:SetAlpha(0) end
    if roleIcon.cover then roleIcon.cover:SetAlpha(0) end

    SkinBase.MarkStyled(roleIcon)
end

local function StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    if button.Bg then button.Bg:Hide() end
    if button.Border then button.Border:Hide() end
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end

    local backdrop = SkinBase.GetFrameData(button, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(button:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", backdrop)
    end

    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true)

    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    Helpers.SetFrameBackdropColor(backdrop, btnBgR, btnBgG, btnBgB, 0.9)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)

    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.3)
        SkinBase.DisablePixelSnap(button.SelectedTexture)
        button.SelectedTexture:SetAllPoints()
    end

    if button.Icon then
        button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local iconBackdrop = SkinBase.GetFrameData(button.Icon, "backdrop")
        if not iconBackdrop then
            iconBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(iconBackdrop, button.Icon, 1)
            iconBackdrop:SetFrameLevel(button:GetFrameLevel())
            iconBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(iconBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(iconBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(button.Icon, "backdrop", iconBackdrop)
        end
    end

    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        if bd then
            bd:SetBackdropBorderColor(1, 1, 1, 1)
        end
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        if bd then
            local cr, cg, cb, ca = SkinBase.GetSkinColors()
            Helpers.SetFrameBackdropBorderColor(bd, cr, cg, cb, ca)
        end
    end)

    -- HookScrollBoxAcquired composes callbacks through SkinBase.
    SkinBase.MarkStyled(button)
end

local function StyleConquestBar(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not bar or SkinBase.IsStyled(bar) then return end

    if bar.Border then bar.Border:Hide() end
    if bar.Background then bar.Background:Hide() end

    local backdrop = SkinBase.GetFrameData(bar, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(bar:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(bar, "backdrop", backdrop)
    end

    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true)
    Helpers.SetFrameBackdropColor(backdrop, bgr, bgg, bgb, 0.8)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)

    if bar.Reward then
        if bar.Reward.Ring then bar.Reward.Ring:Hide() end
        if bar.Reward.CircleMask then bar.Reward.CircleMask:Hide() end
        if bar.Reward.Icon then
            bar.Reward.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    SkinBase.MarkStyled(bar)
end

local function GetRoleIcons(frame)
    if not frame then return nil, nil, nil end
    if frame.RoleList then
        return frame.RoleList.TankIcon, frame.RoleList.HealerIcon, frame.RoleList.DPSIcon
    end
    return frame.TankIcon, frame.HealerIcon, frame.DPSIcon
end

local function StylePVPFrameRoleIcons(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local tankIcon, healerIcon, dpsIcon = GetRoleIcons(frame)
    if tankIcon then StylePVPRoleIcon(tankIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
    if healerIcon then StylePVPRoleIcon(healerIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
    if dpsIcon then StylePVPRoleIcon(dpsIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
end

local function SkinPVPFrame()
    local PVPQueueFrame = _G.PVPQueueFrame
    if not PVPQueueFrame or SkinBase.IsSkinned(PVPQueueFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HidePVPDecorations()

    for i = 1, 5 do
        local catButton = PVPQueueFrame["CategoryButton" .. i] or _G["PVPQueueFrameCategoryButton" .. i]
        if catButton then
            StyleGroupFinderButton(catButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            if catButton.Name then
                SkinBase.SkinFontString(catButton.Name, { fontOnly = true })
            end
        end
    end

    local HonorFrame = _G.HonorFrame
    if HonorFrame then
        if _G.HonorFrameQueueButton then
            SkinBase.SkinButton(_G.HonorFrameQueueButton, { font = true })
        end

        local typeDropdown = HonorFrame.TypeDropdown or _G.HonorFrameTypeDropdown
        if typeDropdown then
            typeDropdown:SetWidth(230)
            SkinBase.SkinDropdown(typeDropdown, { keepArrow = true, insetY = 2 })
            SkinBase.LockDropdownText(typeDropdown)
        end

        StylePVPFrameRoleIcons(HonorFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        if HonorFrame.BonusFrame then
            local bf = HonorFrame.BonusFrame
            local bonusButtons = { "RandomBGButton", "Arena1Button", "RandomEpicBGButton", "BrawlButton", "BrawlButton2", "SpecialEventButton" }
            for _, btnName in ipairs(bonusButtons) do
                if bf[btnName] then
                    StylePVPActivityButton(bf[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end
        end

        if HonorFrame.ConquestBar then
            StyleConquestBar(HonorFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        if HonorFrame.SpecificScrollBox then
            SkinBase.HookScrollBoxAcquired(HonorFrame.SpecificScrollBox, function(button)
                StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)
        end

        if HonorFrame.SpecificScrollBar then
            SkinBase.SkinTrimScrollBar(HonorFrame.SpecificScrollBar)
        end
    end

    local ConquestFrame = _G.ConquestFrame
    if ConquestFrame then
        if _G.ConquestJoinButton then
            SkinBase.SkinButton(_G.ConquestJoinButton, { font = true })
        end

        local conquestDropdown = ConquestFrame.TypeDropdown or _G.ConquestFrameTypeDropdown
        if conquestDropdown then
            conquestDropdown:SetWidth(230)
            SkinBase.SkinDropdown(conquestDropdown, { keepArrow = true, insetY = 2 })
            SkinBase.LockDropdownText(conquestDropdown)
        end

        StylePVPFrameRoleIcons(ConquestFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        local conquestButtons = { "RatedSoloShuffle", "RatedBGBlitz", "Arena2v2", "Arena3v3", "RatedBG" }
        for _, btnName in ipairs(conquestButtons) do
            if ConquestFrame[btnName] then
                StylePVPActivityButton(ConquestFrame[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        if ConquestFrame.ConquestBar then
            StyleConquestBar(ConquestFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    local TrainingGroundsFrame = _G.TrainingGroundsFrame
    if TrainingGroundsFrame then
        SkinBase.StripTextures(TrainingGroundsFrame)
        if TrainingGroundsFrame.Bg then TrainingGroundsFrame.Bg:Hide() end
        if TrainingGroundsFrame.Background then TrainingGroundsFrame.Background:Hide() end

        if TrainingGroundsFrame.Inset then
            SkinBase.StripTextures(TrainingGroundsFrame.Inset)
            if TrainingGroundsFrame.Inset.NineSlice then
                TrainingGroundsFrame.Inset.NineSlice:Hide()
            end
        end

        local bonusList = TrainingGroundsFrame.BonusTrainingGroundList
        if bonusList then
            if bonusList.WorldBattlesTexture then bonusList.WorldBattlesTexture:Hide() end
            if bonusList.ShadowOverlay then bonusList.ShadowOverlay:Hide() end
            if bonusList.RandomTrainingGroundButton then
                StylePVPActivityButton(bonusList.RandomTrainingGroundButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        if TrainingGroundsFrame.QueueButton then
            SkinBase.SkinButton(TrainingGroundsFrame.QueueButton, { font = true })
        end

        if TrainingGroundsFrame.TypeDropdown then
            TrainingGroundsFrame.TypeDropdown:SetWidth(230)
            SkinBase.SkinDropdown(TrainingGroundsFrame.TypeDropdown, { keepArrow = true, insetY = 2 })
            SkinBase.LockDropdownText(TrainingGroundsFrame.TypeDropdown)
        end

        StylePVPFrameRoleIcons(TrainingGroundsFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        if TrainingGroundsFrame.ConquestBar then
            StyleConquestBar(TrainingGroundsFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        local specificList = TrainingGroundsFrame.SpecificTrainingGroundList
        if specificList and specificList.ScrollBox then
            SkinBase.HookScrollBoxAcquired(specificList.ScrollBox, function(button)
                StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)

            if specificList.ScrollBar then
                SkinBase.SkinTrimScrollBar(specificList.ScrollBar)
            end
        end

        SkinBase.MarkSkinned(TrainingGroundsFrame)
    end

    SkinBase.MarkSkinned(PVPQueueFrame)
end

local function SkinInstanceFrames()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or not settings.skinInstanceFrames then return end

    SkinPVEFrame()
    SkinLFDFrame()
    SkinRaidFinderFrame()
    SkinLFGListFrame()
    SkinChallengesFrame()
    SkinPVPFrame()
end

local function UpdateGroupFinderButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = button and SkinBase.GetFrameData(button, "backdrop")
    if not bd then return end
    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa }, { btnBgR, btnBgG, btnBgB, 1 })
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    local iconBd = button.icon and SkinBase.GetFrameData(button.icon, "backdrop")
    if iconBd then
        Helpers.SetFrameBackdropBorderColor(iconBd, sr, sg, sb, sa)
    end
end

local function UpdatePVPActivityButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = button and SkinBase.GetFrameData(button, "backdrop")
    if not bd then return end
    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    Helpers.SetFrameBackdropColor(bd, btnBgR, btnBgG, btnBgB, 1)
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.2)
        SkinBase.DisablePixelSnap(button.SelectedTexture)
    end
    local rewardIconBd = button.Reward and button.Reward.Icon and SkinBase.GetFrameData(button.Reward.Icon, "backdrop")
    if rewardIconBd then
        Helpers.SetFrameBackdropBorderColor(rewardIconBd, sr, sg, sb, sa)
    end
end

local function UpdateConquestBarColors(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = bar and SkinBase.GetFrameData(bar, "backdrop")
    if not bd then return end
    Helpers.SetFrameBackdropColor(bd, bgr, bgg, bgb, 0.8)
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
end

local function UpdateDungeonIconColors(icon, sr, sg, sb, sa)
    if not icon or not icon.Icon then return end
    local bd = SkinBase.GetFrameData(icon.Icon, "backdrop")
    if not bd then return end
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
    SkinBase.SetFrameData(icon, "skinColor", { sr, sg, sb, sa })
end

local function UpdateAffixIconColors(affix, sr, sg, sb, sa)
    if not affix or not affix.Portrait then return end
    local bd = SkinBase.GetFrameData(affix.Portrait, "backdrop")
    if not bd then return end
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
end

local function RefreshInstanceFramesColors()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame or not SkinBase.IsSkinned(PVEFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    local pveBd = SkinBase.GetBackdrop(PVEFrame)
    if pveBd then
        SkinBase.SetBackdropColors(pveBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    local pveTabs = {}
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        if tab then pveTabs[#pveTabs + 1] = tab end
    end
    SkinBase.RefreshTabGroup(pveTabs, PVEFrame)

    local GroupFinderFrame = _G.GroupFinderFrame
    if GroupFinderFrame then
        for i = 1, 4 do
            UpdateGroupFinderButtonColors(GroupFinderFrame["groupButton" .. i], sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    SkinBase.RefreshWidget(_G.LFDQueueFrameFindGroupButton)
    local LFDQueueFrame = _G.LFDQueueFrame
    if LFDQueueFrame then
        local typeDropdown = LFDQueueFrame.TypeDropdown or _G.LFDQueueFrameTypeDropdown
        if typeDropdown then
            SkinBase.RefreshWidget(typeDropdown)
        end
    end

    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if RaidFinderQueueFrame and SkinBase.IsSkinned(RaidFinderQueueFrame) then
        SkinBase.RefreshWidget(_G.RaidFinderFrameFindRaidButton)
        if RaidFinderQueueFrame.SelectionDropdown then
            SkinBase.RefreshWidget(RaidFinderQueueFrame.SelectionDropdown)
        end
    end

    local LFGListFrame = _G.LFGListFrame
    if LFGListFrame and SkinBase.IsSkinned(LFGListFrame) then
        if LFGListFrame.CategorySelection then
            SkinBase.RefreshWidget(LFGListFrame.CategorySelection.StartGroupButton)
            SkinBase.RefreshWidget(LFGListFrame.CategorySelection.FindGroupButton)
            if LFGListFrame.CategorySelection.CategoryButtons then
                for _, catButton in pairs(LFGListFrame.CategorySelection.CategoryButtons) do
                    SkinBase.RefreshWidget(catButton)
                end
            end
        end
        if LFGListFrame.SearchPanel then
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.BackButton)
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.SignUpButton)
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.RefreshButton)
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.FilterButton)
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.SearchBox)
        end
        if LFGListFrame.ApplicationViewer then
            SkinBase.RefreshWidget(LFGListFrame.ApplicationViewer.RefreshButton)
            SkinBase.RefreshWidget(LFGListFrame.ApplicationViewer.RemoveEntryButton)
            SkinBase.RefreshWidget(LFGListFrame.ApplicationViewer.EditButton)
        end
        if LFGListFrame.EntryCreation then
            SkinBase.RefreshWidget(LFGListFrame.EntryCreation.ListGroupButton)
            SkinBase.RefreshWidget(LFGListFrame.EntryCreation.CancelButton)
        end
    end

    local ChallengesFrame = _G.ChallengesFrame
    if ChallengesFrame and SkinBase.IsSkinned(ChallengesFrame) then
        if ChallengesFrame.DungeonIcons then
            for _, icon in pairs(ChallengesFrame.DungeonIcons) do
                UpdateDungeonIconColors(icon, sr, sg, sb, sa)
            end
        end
        if ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child then
            local affixContainer = ChallengesFrame.WeeklyInfo.Child.AffixesContainer
            if affixContainer and affixContainer.Affixes then
                for _, affix in pairs(affixContainer.Affixes) do
                    UpdateAffixIconColors(affix, sr, sg, sb, sa)
                end
            end
        end
        for i = 1, 4 do
            local affix = ChallengesFrame["Affix" .. i]
            if affix then
                UpdateAffixIconColors(affix, sr, sg, sb, sa)
            end
        end
    end

    local PVPQueueFrame = _G.PVPQueueFrame
    if PVPQueueFrame and SkinBase.IsSkinned(PVPQueueFrame) then
        for i = 1, 5 do
            local catButton = PVPQueueFrame["CategoryButton" .. i] or _G["PVPQueueFrameCategoryButton" .. i]
            UpdateGroupFinderButtonColors(catButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        local HonorFrame = _G.HonorFrame
        if HonorFrame then
            SkinBase.RefreshWidget(_G.HonorFrameQueueButton)
            local typeDropdown = HonorFrame.TypeDropdown or _G.HonorFrameTypeDropdown
            if typeDropdown then
                SkinBase.RefreshWidget(typeDropdown)
            end
            if HonorFrame.BonusFrame then
                local bf = HonorFrame.BonusFrame
                local bonusButtons = { "RandomBGButton", "Arena1Button", "RandomEpicBGButton", "BrawlButton", "BrawlButton2", "SpecialEventButton" }
                for _, btnName in ipairs(bonusButtons) do
                    if bf[btnName] then
                        UpdatePVPActivityButtonColors(bf[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
                    end
                end
            end
            if HonorFrame.ConquestBar then
                UpdateConquestBarColors(HonorFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        local ConquestFrame = _G.ConquestFrame
        if ConquestFrame then
            SkinBase.RefreshWidget(_G.ConquestJoinButton)
            local conquestDropdown = ConquestFrame.TypeDropdown or _G.ConquestFrameTypeDropdown
            if conquestDropdown then
                SkinBase.RefreshWidget(conquestDropdown)
            end
            local conquestButtons = { "RatedSoloShuffle", "RatedBGBlitz", "Arena2v2", "Arena3v3", "RatedBG" }
            for _, btnName in ipairs(conquestButtons) do
                if ConquestFrame[btnName] then
                    UpdatePVPActivityButtonColors(ConquestFrame[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end
            if ConquestFrame.ConquestBar then
                UpdateConquestBarColors(ConquestFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        local TrainingGroundsFrame = _G.TrainingGroundsFrame
        if TrainingGroundsFrame and SkinBase.IsSkinned(TrainingGroundsFrame) then
            SkinBase.RefreshWidget(TrainingGroundsFrame.QueueButton)
            if TrainingGroundsFrame.TypeDropdown then
                SkinBase.RefreshWidget(TrainingGroundsFrame.TypeDropdown)
            end
            if TrainingGroundsFrame.ConquestBar then
                UpdateConquestBarColors(TrainingGroundsFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

    end
end

_G.QUI_RefreshInstanceFramesColors = RefreshInstanceFramesColors

if ns.Registry then
    ns.Registry:Register("skinInstanceFrames", {
        refresh = _G.QUI_RefreshInstanceFramesColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local pveHooked = false
local function HookPVEFrame()
    if pveHooked then return end
    local PVEFrame = _G.PVEFrame
    if not PVEFrame then return end
    PVEFrame:HookScript("OnShow", SkinInstanceFrames)
    pveHooked = true
end

local function RunAfterFirstFrame(callback, delay)
    if ns.RunAfterFirstFrame then
        return ns.RunAfterFirstFrame(callback, delay)
    end
    if C_Timer and C_Timer.After then
        return C_Timer.After(delay or 0, callback)
    end
    if type(callback) == "function" then
        return callback()
    end
    return nil
end

SkinBase.OnAddOnLoaded("Blizzard_GroupFinder", function()
    HookPVEFrame()
    SkinInstanceFrames()
end, 0)
SkinBase.OnAddOnLoaded("Blizzard_PVPUI", SkinInstanceFrames, 0)
SkinBase.OnAddOnLoaded("Blizzard_ChallengesUI", SkinInstanceFrames, 0)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        HookPVEFrame()
        RunAfterFirstFrame(function()
            SkinInstanceFrames()
        end, 0.25)
    end)
end
