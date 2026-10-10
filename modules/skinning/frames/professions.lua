local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinProfessions
end

local function StyleRecipeLabel(row)
    if not row or not row.Label or not row.Count or not row.SkillUps then return end
    local countWidth = row.Count:IsShown() and row.Count:GetStringWidth() or 0
    local lockWidth = row.LockedIcon and row.LockedIcon:IsShown() and row.LockedIcon:GetWidth() or 0
    local width = row:GetWidth() - row.SkillUps:GetWidth() - countWidth - lockWidth - 10
    row.Label:SetWidth(math.max(1, width))
end

local function UpdateRecipeCategoryIndicator(row)
    local node = row.GetElementData and row:GetElementData()
    local glyph = SkinBase.GetFrameData(row, "qRecipeCategoryIndicator")
    if glyph then glyph:SetText(node and node.IsCollapsed and node:IsCollapsed() and "+" or "-") end
end

local function StyleRecipeCategoryIndicator(row)
    if not SkinBase.GetFrameData(row, "qRecipeCategoryIndicator") then
        local glyph = row:CreateFontString(nil, "OVERLAY")
        SkinBase.SkinFontString(glyph, { color = { 0.9, 0.9, 0.9, 1 } })
        glyph:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        glyph:SetWidth(16)
        glyph:SetJustifyH("CENTER")
        SkinBase.SetFrameData(row, "qRecipeCategoryIndicator", glyph)
        row:HookScript("OnClick", UpdateRecipeCategoryIndicator)
        if row.UpdateCollapsedState then hooksecurefunc(row, "UpdateCollapsedState", UpdateRecipeCategoryIndicator) end
        local button = row.GetCollapseButton and row:GetCollapseButton() or row.CollapseButton
        if button then SkinBase.StripTextures(button) end
    end
    UpdateRecipeCategoryIndicator(row)
end

local function StyleRecipeCategory(row)
    if not row then return end
    local node = row.GetElementData and row:GetElementData()
    local data = node and node.GetData and node:GetData()
    local category = data and data.categoryInfo
    if not category then return end
    StyleRecipeCategoryIndicator(row)
    local label = row.Label or (row.GetTitleRegion and row:GetTitleRegion())
    if not label or SkinBase.GetFrameData(label, "qRecipeCategoryColorApplying") then return end
    local shade = category and category.unlearned and 0.55 or 0.9
    local r, g, b = label:GetTextColor()
    if not r or not g or not b or math.abs(r - shade) > 0.0001 or math.abs(g - shade) > 0.0001 or math.abs(b - shade) > 0.0001 then
        SkinBase.SetFrameData(label, "qRecipeCategoryColorApplying", true)
        SkinBase.SkinFontString(label, { color = { shade, shade, shade, 1 } })
        SkinBase.SetFrameData(label, "qRecipeCategoryColorApplying", false)
    end
    if not SkinBase.GetFrameData(label, "qRecipeCategoryLabelHooked") then
        SkinBase.SetFrameData(label, "qRecipeCategoryLabelHooked", true)
        hooksecurefunc(label, "SetTextColor", function() StyleRecipeCategory(row) end)
    end
    if row.Init and not SkinBase.GetFrameData(row, "qRecipeCategoryInitHooked") then
        hooksecurefunc(row, "Init", StyleRecipeCategory)
        SkinBase.SetFrameData(row, "qRecipeCategoryInitHooked", true)
    end
end

local function StyleScrollBoxRow(row)
    if not row then return end
    local node = row.GetElementData and row:GetElementData()
    if node then
        local data = node.GetData and node:GetData()
        if data and (data.isDivider or data.topPadding or data.bottomPadding) then
            return
        end
    end
    StyleRecipeCategory(row)
    if SkinBase.IsStyled(row) then StyleRecipeLabel(row); return end

    if not row.Label and not row.Text and not row.Icon and not row.GetTitleRegion then return end

    SkinBase.SkinScrollRow(row)
    SkinBase.LockPooledRowText(row, 4)

    local rowBd = SkinBase.GetBackdrop(row)
    if rowBd and rowBd.SetFrameLevel then
        rowBd:SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
    end

    if row.Label then
        SkinBase.LockFontObject(row.Label, { fontOnly = true })
    end
    StyleRecipeLabel(row)
    if row.Init and not SkinBase.GetFrameData(row, "qRecipeLabelHooked") then
        SkinBase.SetFrameData(row, "qRecipeLabelHooked", true)
        hooksecurefunc(row, "Init", StyleRecipeLabel)
    end
end

local function StyleOrderListRow(row)
    if not row or SkinBase.IsStyled(row) then return end

    local node = row.GetElementData and row:GetElementData()
    if node then
        local data = node.GetData and node:GetData()
        if data and (data.isDivider or data.topPadding or data.bottomPadding) then
            return
        end
    end

    SkinBase.SkinScrollRow(row)
    SkinBase.LockPooledRowText(row, 4)
end

local function HideDecorations(frame)
    if not frame then return end
    SkinBase.HidePortraitFrameChrome(frame)
    SkinBase.StripTextures(frame)
end

local function SkinSubPanel(panel, sr, sg, sb, sa)
    if not panel then return end
    if panel.NineSlice then panel.NineSlice:Hide() end
    if panel.Background then panel.Background:SetAlpha(0) end
    local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(panel, sr, sg, sb, sa * 0.3, dr, dg, db, da, 6)
end

local function SkinTabs(frame)
    if not frame then return end
    local tabs = frame.TabSystem and frame.TabSystem.tabs
    if tabs then SkinBase.SkinTabGroup(tabs, frame, { hover = true, dockBottom = true }) end
    if frame.ProfessionsOverviewTab then
        SkinBase.SkinTab(frame.ProfessionsOverviewTab, frame, { hover = true })
    end
    SkinBase.SkinTabGroup(frame.rightProfessionTabs, frame, { hover = true })
end

local function HookRecipeRowHover()
    for _, name in ipairs({ "ProfessionsRecipeListRecipeMixin", "ProfessionsRecipeListCategoryMixin" }) do
        local mixin = _G[name]
        if mixin and mixin.OnEnter and mixin.OnLeave and not SkinBase.GetFrameData(mixin, "hoverHooked") then
            hooksecurefunc(mixin, "OnEnter", function(self) SkinBase.SetRowHovered(self, true) end)
            hooksecurefunc(mixin, "OnLeave", function(self) SkinBase.SetRowHovered(self, false) end)
            SkinBase.SetFrameData(mixin, "hoverHooked", true)
        end
    end
end

local function SkinRecipeList(recipeList)
    if not recipeList then return end
    HookRecipeRowHover()

    if recipeList.Background then recipeList.Background:SetAlpha(0) end
    if recipeList.BackgroundNineSlice then recipeList.BackgroundNineSlice:Hide() end
    SkinBase.StripTextures(recipeList)

    if recipeList.SearchBox then
        SkinBase.SkinEditBox(recipeList.SearchBox)
    end

    if recipeList.FilterDropdown then
        SkinBase.SkinDropdown(recipeList.FilterDropdown, { belowChildren = true })
    end

    if recipeList.ScrollBox then
        SkinBase.HookScrollBoxAcquired(recipeList.ScrollBox, StyleScrollBoxRow)
    end
    if recipeList.ScrollBar then
        SkinBase.SkinTrimScrollBar(recipeList.ScrollBar)
    end
end

local function SkinCraftingPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local craftingPage = frame.CraftingPage
    if not craftingPage then return end

    SkinRecipeList(craftingPage.RecipeList)

    local schematicForm = craftingPage.SchematicForm
    if schematicForm then
        if schematicForm.NineSlice then schematicForm.NineSlice:Hide() end
        if schematicForm.Background then schematicForm.Background:SetAlpha(0) end
        if schematicForm.MinimalBackground then schematicForm.MinimalBackground:SetAlpha(0) end
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(schematicForm, sr, sg, sb, sa * 0.3, dr, dg, db, da, 6)

        local details = schematicForm.Details
        if details then
            if details.BackgroundTop then details.BackgroundTop:SetAlpha(0) end
            if details.BackgroundMiddle then details.BackgroundMiddle:SetAlpha(0) end
            if details.BackgroundBottom then details.BackgroundBottom:SetAlpha(0) end
            if details.BackgroundMinimized then details.BackgroundMinimized:SetAlpha(0) end
            SkinBase.CreateBackdrop(details, sr, sg, sb, sa * 0.3, dr, dg, db, da, 6)
        end
    end

    if craftingPage.MinimizedSearchBox then
        SkinBase.SkinEditBox(craftingPage.MinimizedSearchBox)
    end

    if craftingPage.CreateButton then
        SkinBase.SkinButton(craftingPage.CreateButton, { font = true })
    end
    if craftingPage.CreateAllButton then
        SkinBase.SkinButton(craftingPage.CreateAllButton, { font = true })
    end
    if craftingPage.ViewGuildCraftersButton then
        SkinBase.SkinButton(craftingPage.ViewGuildCraftersButton, { font = true })
    end
end

local function SkinOrdersPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local ordersPage = frame.OrdersPage
    if not ordersPage then return end

    local browseFrame = ordersPage.BrowseFrame
    if browseFrame then
        SkinRecipeList(browseFrame.RecipeList)

        SkinBase.SkinListContainer(browseFrame.OrderList, StyleOrderListRow)

        if browseFrame.SearchButton then
            SkinBase.SkinButton(browseFrame.SearchButton, { font = true })
        end
        if browseFrame.FavoritesSearchButton then
            SkinBase.SkinButton(browseFrame.FavoritesSearchButton, { font = true })
        end

        local orderTabs = { browseFrame.PublicOrdersButton, browseFrame.GuildOrdersButton, browseFrame.NpcOrdersButton, browseFrame.PersonalOrdersButton }
        for _, tab in ipairs(orderTabs) do
            if tab then
                SkinBase.SkinTab(tab, browseFrame, { hover = true })
            end
        end
    end

    local orderView = ordersPage.OrderView
    if orderView then
        SkinSubPanel(orderView.OrderDetails, sr, sg, sb, sa)
        SkinSubPanel(orderView.OrderInfo, sr, sg, sb, sa)
        local noteTitle = orderView.OrderInfo and orderView.OrderInfo.NoteBox and orderView.OrderInfo.NoteBox.NoteTitle
        if noteTitle then
            SkinBase.SkinFontString(noteTitle, { fontOnly = true })
            SkinBase.LockFontObject(noteTitle, { fontOnly = true })
        end
        if orderView.CreateButton then
            SkinBase.SkinButton(orderView.CreateButton, { font = true })
        end
        if orderView.StartOrderButton then
            SkinBase.SkinButton(orderView.StartOrderButton, { font = true })
        end
        if orderView.CompleteOrderButton then
            SkinBase.SkinButton(orderView.CompleteOrderButton, { font = true })
        end
        if orderView.DeclineOrderButton then
            SkinBase.SkinButton(orderView.DeclineOrderButton, { font = true })
        end
        if orderView.ReleaseOrderButton then
            SkinBase.SkinButton(orderView.ReleaseOrderButton, { font = true })
        end
        if orderView.BackButton then
            SkinBase.SkinButton(orderView.BackButton, { font = true })
        end
    end
end

local function StyleSpecPoolTab(tab, owner)
    if not tab or SkinBase.IsStyled(tab) then return end
    SkinBase.SkinTab(tab, owner, { hover = true })
    SkinBase.RefreshTabSelected(tab, owner)
end

local function SkinSpecPoolTabs(specPage)
    local pool = specPage.tabsPool
    if not pool then return end

    for tab in pool:EnumerateActive() do
        StyleSpecPoolTab(tab, specPage)
    end

    if not SkinBase.GetFrameData(specPage, "tabPoolHooked") then
        hooksecurefunc(pool, "Acquire", function(self)
            C_Timer.After(0, function()
                for t in self:EnumerateActive() do
                    StyleSpecPoolTab(t, specPage)
                end
            end)
        end)
        SkinBase.SetFrameData(specPage, "tabPoolHooked", true)
    end
end

local function SkinSpecPage(frame)
    if not frame then return end

    local specPage = frame.SpecPage
    if not specPage then return end

    SkinSpecPoolTabs(specPage)

    if specPage.PanelFooter then
        SkinBase.StripTextures(specPage.PanelFooter)
    end

    if specPage.VerticalDivider then SkinBase.StripTextures(specPage.VerticalDivider) end
    if specPage.TopDivider then SkinBase.StripTextures(specPage.TopDivider) end

    if specPage.ApplyButton then
        SkinBase.SkinButton(specPage.ApplyButton, { font = true })
    end
    if specPage.UnlockTabButton then
        SkinBase.SkinButton(specPage.UnlockTabButton, { font = true })
    end
    if specPage.ViewTreeButton then
        SkinBase.SkinButton(specPage.ViewTreeButton, { font = true })
    end
    if specPage.BackToPreviewButton then
        SkinBase.SkinButton(specPage.BackToPreviewButton, { font = true })
    end
    if specPage.ViewPreviewButton then
        SkinBase.SkinButton(specPage.ViewPreviewButton, { font = true })
    end
    if specPage.BackToFullTreeButton then
        SkinBase.SkinButton(specPage.BackToFullTreeButton, { font = true })
    end

    local detailedView = specPage.DetailedView
    if detailedView then
        if detailedView.Background then detailedView.Background:SetAlpha(0) end
        if detailedView.SpendPointsButton then
            SkinBase.SkinButton(detailedView.SpendPointsButton, { font = true })
        end
        if detailedView.UnlockPathButton then
            SkinBase.SkinButton(detailedView.UnlockPathButton, { font = true })
        end
    end

    local treeView = specPage.TreeView
    if treeView then
        if treeView.Background then treeView.Background:SetAlpha(0) end
    end
end

local function HookProfessionTableHeaderFonts()
    local mixin = _G.ProfessionsCrafterTableHeaderStringMixin
    if not mixin or mixin.Init == nil or SkinBase.GetFrameData(mixin, "headerFontHooked") then return end
    hooksecurefunc(mixin, "Init", function(self)
        SkinBase.ApplyButtonFontObjects(self)
    end)
    SkinBase.SetFrameData(mixin, "headerFontHooked", true)
end

local function StyleProfessionNeutralText(label)
    if not label or not IsEnabled() or SkinBase.GetFrameData(label, "qProfessionColorApplying") then return end
    SkinBase.SetFrameData(label, "qProfessionColorApplying", true)
    SkinBase.SkinFontString(label, { color = { 0.9, 0.9, 0.9, 1 } })
    SkinBase.SetFrameData(label, "qProfessionColorApplying", false)
    if not SkinBase.GetFrameData(label, "qProfessionColorHooked") then
        hooksecurefunc(label, "SetTextColor", StyleProfessionNeutralText)
        SkinBase.SetFrameData(label, "qProfessionColorHooked", true)
    end
end

local function StyleProfessionTitle(frame)
    if not frame or not IsEnabled() then return end
    local title = frame.GetTitleText and frame:GetTitleText()
    if not title then title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText) end
    if title then SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } }) end
end

local function StyleProfessionGlyph(button, text, size)
    if not button then return end
    SkinBase.SkinButton(button, { strip = true, font = false, belowChildren = true })
    SkinBase.RefreshWidget(button)
    SkinBase.ClampTextureHidden(button.Icon, true, { preserveLayout = true })
    if not SkinBase.GetFrameData(button, "qProfessionControlGlyph") then
        local glyph = button:CreateFontString(nil, "OVERLAY")
        glyph:SetPoint("CENTER")
        SkinBase.SkinFontString(glyph, { size = size or 14, color = { 0.9, 0.9, 0.9, 1 } })
        glyph:SetText(text)
        SkinBase.SetFrameData(button, "qProfessionControlGlyph", glyph)
    end
end

local function StyleProfessionForm(form)
    if not form or not IsEnabled() then return end
    SkinBase.KillNineSlice(form.NineSlice, true)
    SkinBase.ClampTextureHidden(form.Background, true, { preserveLayout = true })
    SkinBase.ClampTextureHidden(form.MinimalBackground, true, { preserveLayout = true })
    for _, key in ipairs({ "Reagents", "OptionalReagents", "FinishingReagents" }) do
        local section = form[key]
        if section and section.Label then
            StyleProfessionNeutralText(section.Label)
        end
    end
    local details = form.Details
    if details then
        for _, key in ipairs({ "BackgroundTop", "BackgroundMiddle", "BackgroundBottom", "BackgroundMinimized" }) do
            SkinBase.ClampTextureHidden(details[key], true)
        end
        local sr, sg, sb, sa = SkinBase.GetWindowColors()
        local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(details, sr, sg, sb, sa * 0.3, r, g, b, a, 6)
    end
    local choices = details and details.CraftingChoicesContainer
    if choices then
        for _, key in ipairs({ "FinishingReagentSlotContainer", "ConcentrateContainer" }) do
            StyleProfessionNeutralText(choices[key] and choices[key].Label)
        end
    end
    for _, key in ipairs({ "TrackRecipeCheckbox", "AllocateBestQualityCheckbox" }) do
        local checkbox = form[key]
        if checkbox then
            SkinBase.SkinCheckBox(checkbox)
            local backdrop = SkinBase.GetBackdrop(checkbox)
            if backdrop then
                backdrop:ClearAllPoints()
                backdrop:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 5, -5)
                backdrop:SetPoint("BOTTOMRIGHT", checkbox, "BOTTOMRIGHT", -5, 5)
                SkinBase.ApplyChromeBackdrop(backdrop, { radius = 3, withBackground = true })
            end
        end
    end
    for _, method in ipairs({ "Init", "Refresh" }) do
        local flag = "qProfessionForm" .. method
        if form[method] and not SkinBase.GetFrameData(form, flag) then
            hooksecurefunc(form, method, StyleProfessionForm)
            SkinBase.SetFrameData(form, flag, true)
        end
    end
end

local function StyleProfessionRankBar(bar)
    if not bar then return end
    SkinBase.ClampTextureHidden(bar.Background, true)
    SkinBase.ClampTextureHidden(bar.Border, true)
    if bar.Fill then
        local width = SkinBase.GetFrameData(bar, "qRankOriginalWidth")
        if not width then
            width = bar:GetWidth()
            SkinBase.SetFrameData(bar, "qRankOriginalWidth", width)
        end
        bar:SetSize(width - 28, 22)
        local pixel = SkinBase.GetPixelSize(bar, 1)
        bar.Fill:ClearAllPoints()
        bar.Fill:SetPoint("TOPLEFT", bar, "TOPLEFT", pixel, -pixel)
        bar.Fill:SetSize(bar:GetWidth() - 2 * pixel, bar:GetHeight() - 2 * pixel)
        if bar.Mask and type(bar.GetMaskWidth) == "function" then
            bar.Mask:ClearAllPoints()
            bar.Mask:SetPoint("LEFT", bar.Fill, "LEFT", 0, 0)
            bar.Mask:SetHeight(bar.Fill:GetHeight())
            if not SkinBase.GetFrameData(bar, "qRankMaskWidthHooked") then
                local nativeGetMaskWidth = bar.GetMaskWidth
                bar.GetMaskWidth = function(self, progress)
                    local width = nativeGetMaskWidth(self, progress)
                    if IsEnabled() and self.Fill then
                        return width - (self:GetWidth() - self.Fill:GetWidth()) * progress
                    end
                    return width
                end
                SkinBase.SetFrameData(bar, "qRankMaskWidthHooked", true)
            end
            if bar.ratio ~= nil then bar.Mask:SetWidth(bar:GetMaskWidth(bar.ratio)) end
        end
        if bar.Rank then
            bar.Rank:ClearAllPoints()
            bar.Rank:SetPoint("TOPLEFT", bar, "TOPLEFT", pixel, -pixel)
            bar.Rank:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -pixel, pixel)
        end
        if not SkinBase.GetBackdrop(bar) then SkinBase.CreateBackdrop(bar, nil, nil, nil, nil, nil, nil, nil, nil, 4) end
        SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(bar), { radius = 4, withBackground = true })
        SkinBase.RoundBarTexture(bar, bar.Fill)
    end
    local dropdown = bar.ExpansionDropdownButton
    if dropdown then
        SkinBase.SkinDropdown(dropdown, { skinArrow = true })
        SkinBase.ClampTextureHidden(dropdown.Texture, true, { preserveLayout = true })
        dropdown:SetSize(22, 22)
        dropdown:ClearAllPoints()
        dropdown:SetPoint("LEFT", bar, "RIGHT", 4, 0)
    end
end

local function StyleProfessionOrderView(view)
    if not view or not IsEnabled() then return end
    local info = view.OrderInfo
    if info then
        for _, key in ipairs({ "BackButton", "StartOrderButton", "DeclineOrderButton", "ReleaseOrderButton" }) do
            SkinBase.SkinButton(info[key], { strip = true, font = true })
        end
        for _, key in ipairs({ "PostedByTitle", "CommissionTitle", "ConsortiumCutTitle", "FinalTipTitle", "TimeRemainingTitle" }) do
            StyleProfessionNeutralText(info[key])
        end
        local note = info.NoteBox
        if note then
            SkinBase.StripTextures(note.Background)
            SkinBase.CreateBackdrop(note, nil, nil, nil, nil, nil, nil, nil, nil, 4)
            StyleProfessionNeutralText(note.NoteTitle)
        end
        local rewards = info.NPCRewardsFrame
        if rewards then
            SkinBase.ClampTextureHidden(rewards.Background, true)
            SkinBase.CreateBackdrop(rewards, nil, nil, nil, nil, nil, nil, nil, nil, 4)
            StyleProfessionNeutralText(rewards.RewardText)
        end
    end
    StyleProfessionForm(view.OrderDetails and view.OrderDetails.SchematicForm)
    StyleProfessionRankBar(view.RankBar)
    if view.HookScript and not SkinBase.GetFrameData(view, "qOrderViewShowHooked") then
        view:HookScript("OnShow", StyleProfessionOrderView)
        SkinBase.SetFrameData(view, "qOrderViewShowHooked", true)
    end
end

local function StyleProfessionTopControls(frame)
    if not frame or not IsEnabled() then return end
    StyleProfessionTitle(frame)
    for _, method in ipairs({ "SetTitle", "SetTitleFormatted" }) do
        local flag = "qProfession" .. method
        if frame[method] and not SkinBase.GetFrameData(frame, flag) then
            hooksecurefunc(frame, method, StyleProfessionTitle)
            SkinBase.SetFrameData(frame, flag, true)
        end
    end
    local sizing = frame.MaximizeMinimize
    if sizing then
        StyleProfessionGlyph(sizing.MaximizeButton, "+")
        StyleProfessionGlyph(sizing.MinimizeButton, "-")
    end
    local spec = frame.SpecPage
    if spec then
        for _, pair in ipairs({
            { spec.TreeView, "TreeDescription" },
            { spec.TreePreview, "Description" },
        }) do
            local label = pair[1] and pair[1][pair[2]]
            if label then
                StyleProfessionNeutralText(label)
            end
        end
    end
    local orders = frame.OrdersPage
    StyleProfessionOrderView(orders and orders.OrderView)
    local browse = orders and orders.BrowseFrame
    if browse then
        local list = browse.RecipeList
        local filter = list and list.FilterDropdown
        if filter then
            SkinBase.LockDropdownText(filter, 2)
            StyleProfessionNeutralText(filter.Text or (filter.GetFontString and filter:GetFontString()))
        end
        StyleProfessionNeutralText(list and list.NoResultsText)
        StyleProfessionNeutralText(browse.OrderList and browse.OrderList.ResultsText)
    end
    local page = frame and frame.CraftingPage
    if not page then return end
    local help = page.TutorialButton
    if help then
        help:SetSize(22, 22)
        help:ClearAllPoints()
        help:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -2)
        StyleProfessionGlyph(help, "?")
    end
    StyleProfessionGlyph(page.LinkButton, "L", 11)
    for _, slot in ipairs(page.InventorySlots or {}) do
        SkinBase.ClampTextureHidden(slot.GetNormalTexture and slot:GetNormalTexture(), true)
        local icon = slot.icon or slot.Icon
        local border = SkinBase.SkinIcon(icon, { parent = slot })
        SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
        SkinBase.RoundIconTexture(slot, icon)
        SkinBase.HandleIconBorder(slot.IconBorder, border)
        SkinBase.ClampTextureHidden(slot.IconBorder, true)
    end
    SkinBase.StripTextures(page.GearSlotDivider)
    StyleProfessionForm(page.SchematicForm)
    local filter = page.RecipeList and page.RecipeList.FilterDropdown
    if filter then
        SkinBase.LockDropdownText(filter, 2)
        StyleProfessionNeutralText(filter.Text or (filter.GetFontString and filter:GetFontString()))
    end
    StyleProfessionRankBar(page.RankBar)
    if page.LinkButton and page.RankBar and page.RankBar.ExpansionDropdownButton then
        page.LinkButton:ClearAllPoints()
        page.LinkButton:SetPoint("LEFT", page.RankBar.ExpansionDropdownButton, "RIGHT", 8, 0)
    end
    SkinBase.SkinEditBox(page.CreateMultipleInputBox)
    local spinner = page.CreateMultipleInputBox
    if spinner then
        if spinner.DecrementButton then SkinBase.SkinNextPrevButton(spinner.DecrementButton, "prev") end
        if spinner.IncrementButton then SkinBase.SkinNextPrevButton(spinner.IncrementButton, "next") end
    end
end

local function SkinProfessions()
    if not IsEnabled() then return end

    local frame = _G.ProfessionsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    HookProfessionTableHeaderFonts()

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()

    HideDecorations(frame)
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)

    SkinBase.SkinCloseButton(frame.CloseButton or _G.ProfessionsFrameCloseButton)

    SkinTabs(frame)
    StyleProfessionTopControls(frame)
    if frame.BookPage then
        SkinBase.SkinFrameText(frame.BookPage, { recurse = true })
        SkinBase.LockFrameTextObjects(frame.BookPage, 4)
        SkinBase.ApplyButtonFontObjectsDeep(frame.BookPage, 4)
    end
    SkinCraftingPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinOrdersPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinSpecPage(frame)

    if frame.HookScript then
        frame:HookScript("OnShow", function()
            StyleProfessionTopControls(frame)
            SkinTabs(frame)
        end)
    end
    SkinBase.MarkSkinned(frame)
end

local function UpdatePanelColors(panel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = panel and SkinBase.GetBackdrop(panel)
    if not bd then return end
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa * 0.3 }, { SkinBase.GetDepthColor("SUBPANEL") })
end

local function UpdateRecipeListColors(recipeList)
    if not recipeList then return end
    SkinBase.RefreshWidget(recipeList.SearchBox)
    SkinBase.RefreshWidget(recipeList.FilterDropdown)
end

local StyleProfessionBook

local function RefreshProfessionsColors()
    if StyleProfessionBook then StyleProfessionBook() end
    local frame = _G.ProfessionsFrame
    StyleProfessionTopControls(frame)
    if not frame or not SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()

    local mainBd = SkinBase.GetBackdrop(frame)
    if mainBd then
        SkinBase.SetBackdropColors(mainBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.RefreshTabGroup(frame.TabSystem.tabs, frame)
    end
    if frame.ProfessionsOverviewTab then
        SkinBase.RefreshTabGroup({ frame.ProfessionsOverviewTab }, frame)
    end
    SkinBase.RefreshTabGroup(frame.rightProfessionTabs, frame)
    if frame.BookPage then SkinBase.SkinFrameText(frame.BookPage, { recurse = true }) end

    local craftingPage = frame.CraftingPage
    if craftingPage then
        UpdateRecipeListColors(craftingPage.RecipeList)
        SkinBase.RefreshWidget(craftingPage.MinimizedSearchBox)
        UpdatePanelColors(craftingPage.SchematicForm, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if craftingPage.SchematicForm then
            UpdatePanelColors(craftingPage.SchematicForm.Details, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        SkinBase.RefreshWidget(craftingPage.CreateButton)
        SkinBase.RefreshWidget(craftingPage.CreateAllButton)
        SkinBase.RefreshWidget(craftingPage.ViewGuildCraftersButton)
    end

    local ordersPage = frame.OrdersPage
    if ordersPage and ordersPage.BrowseFrame then
        local bf = ordersPage.BrowseFrame
        UpdateRecipeListColors(bf.RecipeList)
        SkinBase.RefreshWidget(bf.SearchButton)
        SkinBase.RefreshWidget(bf.FavoritesSearchButton)
        local orderTabs = { bf.PublicOrdersButton, bf.GuildOrdersButton, bf.NpcOrdersButton, bf.PersonalOrdersButton }
        for _, tab in ipairs(orderTabs) do
            if tab then
                SkinBase.RefreshTabSelected(tab, bf)
            end
        end
        if ordersPage.OrderView then
            UpdatePanelColors(ordersPage.OrderView.OrderDetails, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdatePanelColors(ordersPage.OrderView.OrderInfo, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            SkinBase.RefreshWidget(ordersPage.OrderView.CreateButton)
            SkinBase.RefreshWidget(ordersPage.OrderView.StartOrderButton)
            SkinBase.RefreshWidget(ordersPage.OrderView.CompleteOrderButton)
            SkinBase.RefreshWidget(ordersPage.OrderView.DeclineOrderButton)
            SkinBase.RefreshWidget(ordersPage.OrderView.ReleaseOrderButton)
            SkinBase.RefreshWidget(ordersPage.OrderView.BackButton)
        end
    end

    local specPage = frame.SpecPage
    if specPage then
        if specPage.tabsPool then
            local poolTabs = {}
            for tab in specPage.tabsPool:EnumerateActive() do poolTabs[#poolTabs + 1] = tab end
            SkinBase.RefreshTabGroup(poolTabs, specPage)
        end
        SkinBase.RefreshWidget(specPage.ApplyButton)
        SkinBase.RefreshWidget(specPage.UnlockTabButton)
        SkinBase.RefreshWidget(specPage.ViewTreeButton)
        SkinBase.RefreshWidget(specPage.BackToPreviewButton)
        SkinBase.RefreshWidget(specPage.ViewPreviewButton)
        SkinBase.RefreshWidget(specPage.BackToFullTreeButton)
        if specPage.DetailedView then
            SkinBase.RefreshWidget(specPage.DetailedView.SpendPointsButton)
            SkinBase.RefreshWidget(specPage.DetailedView.UnlockPathButton)
        end
    end
end

_G.QUI_RefreshProfessionsColors = RefreshProfessionsColors

if ns.Registry then
    ns.Registry:Register("skinProfessions", {
        refresh = _G.QUI_RefreshProfessionsColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function StyleProfessionBookRow(row)
    if not row then return end
    SkinBase.StripTextures(row)
    if row.icon then row.icon:SetAlpha(1) end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
    local backdrop = SkinBase.GetBackdrop(row)
    if backdrop then
        backdrop:SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", row, "TOPLEFT", -8, 4)
        backdrop:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 8, -6)
    end
    for _, key in ipairs({ "professionName", "specialization", "missingHeader" }) do
        SkinBase.SkinFontString(row[key], { color = { 1, 1, 1, 1 } })
    end
    for _, key in ipairs({ "rank", "missingText" }) do
        SkinBase.SkinFontString(row[key], { color = { 0.85, 0.85, 0.85, 1 } })
    end
    local bar = row.statusBar
    if bar then
        SkinBase.StripTextures(bar)
        SkinBase.SkinStatusBar(bar)
        SkinBase.RefreshWidget(bar)
        local fill = bar:GetStatusBarTexture()
        if fill then
            fill:SetAlpha(1)
            SkinBase.RoundBarTexture(bar, fill)
        end
        SkinBase.SkinFontString(bar.rankText, { color = { 1, 1, 1, 1 } })
    end
    for _, key in ipairs({ "SpellButton1", "SpellButton2" }) do
        local button = row[key]
        if button then
            SkinBase.SkinButton(button, { font = false, belowChildren = true, radius = 4 })
            SkinBase.RefreshWidget(button)
            local name = button:GetName()
            SkinBase.ClampTextureHidden(name and _G[name .. "NameFrame"], true)
            if button.IconTexture then
                button.IconTexture:SetAlpha(1)
                button.IconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                SkinBase.RoundIconTexture(button, button.IconTexture)
            end
            SkinBase.SkinFontString(button.spellString, { color = { 1, 1, 1, 1 } })
            SkinBase.SkinFontString(button.subSpellString, { color = { 0.85, 0.85, 0.85, 1 } })
        end
    end
end

StyleProfessionBook = function()
    local frame = _G.ProfessionsBookFrame
    if not frame or not IsEnabled() or InCombatLockdown() then return end
    if not SkinBase.IsSkinned(frame) then
        SkinBase.SkinWindow(frame)
        frame:HookScript("OnShow", StyleProfessionBook)
        if type(_G.ProfessionsBookFrame_Update) == "function" then
            hooksecurefunc("ProfessionsBookFrame_Update", StyleProfessionBook)
        end
        SkinBase.MarkSkinned(frame)
    end
    SkinBase.StripTextures(frame)
    local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
    SkinBase.SetBackdropColors(SkinBase.GetBackdrop(frame), { sr, sg, sb, sa }, { r, g, b, a })
    local help = frame.MainHelpButton
    if help then
        help:SetSize(22, 22)
        help:ClearAllPoints()
        help:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -2)
        SkinBase.SkinButton(help, { strip = true, font = false, belowChildren = true })
        SkinBase.RefreshWidget(help)
        if not SkinBase.GetFrameData(help, "qProfessionBookHelpGlyph") then
            local glyph = help:CreateFontString(nil, "OVERLAY")
            glyph:SetPoint("CENTER")
            SkinBase.SkinFontString(glyph, { size = 14, color = { 1, 1, 1, 1 } })
            glyph:SetText("?")
            SkinBase.SetFrameData(help, "qProfessionBookHelpGlyph", glyph)
        end
    end
    SkinBase.ClampTextureHidden(_G.ProfessionsBookPage1, true)
    SkinBase.ClampTextureHidden(_G.ProfessionsBookPage2, true)
    local title = frame.GetTitleText and frame:GetTitleText()
    SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } })
    for _, name in ipairs({ "PrimaryProfession1", "PrimaryProfession2",
        "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }) do
        StyleProfessionBookRow(_G[name])
    end
end

SkinBase.OnAddOnLoaded("Blizzard_ProfessionsBook", StyleProfessionBook, 0)
SkinBase.OnAddOnLoaded("Blizzard_Professions", SkinProfessions, 0)
