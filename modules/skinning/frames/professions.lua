local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinProfessions
end

local function StyleScrollBoxRow(row)
    if not row or SkinBase.IsStyled(row) then return end

    local node = row.GetElementData and row:GetElementData()
    if node then
        local data = node.GetData and node:GetData()
        if data and (data.isDivider or data.topPadding or data.bottomPadding) then
            return
        end
    end
    if not row.Label and not row.Text and not row.Icon then return end

    SkinBase.SkinScrollRow(row)
    SkinBase.LockPooledRowText(row, 4)

    local rowBd = SkinBase.GetBackdrop(row)
    if rowBd and rowBd.SetFrameLevel then
        rowBd:SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
    end

    if row.Label then
        SkinBase.LockFontObject(row.Label, { fontOnly = true })
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
    SkinBase.CreateBackdrop(panel, sr, sg, sb, sa * 0.3, dr, dg, db, da)
end

local function SkinTabs(frame)
    if not frame or not frame.TabSystem then return end
    local tabs = frame.TabSystem.tabs
    if not tabs then return end
    SkinBase.SkinTabGroup(tabs, frame, { hover = true })
end

local function HookRecipeRowHover()
    local mixin = _G.ProfessionsRecipeListRecipeMixin
    if not mixin or mixin.OnEnter == nil or SkinBase.GetFrameData(mixin, "hoverHooked") then return end
    hooksecurefunc(mixin, "OnEnter", function(self) SkinBase.SetRowHovered(self, true) end)
    hooksecurefunc(mixin, "OnLeave", function(self) SkinBase.SetRowHovered(self, false) end)
    SkinBase.SetFrameData(mixin, "hoverHooked", true)
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
        SkinBase.CreateBackdrop(schematicForm, sr, sg, sb, sa * 0.3, dr, dg, db, da)

        local details = schematicForm.Details
        if details then
            if details.BackgroundTop then details.BackgroundTop:SetAlpha(0) end
            if details.BackgroundMiddle then details.BackgroundMiddle:SetAlpha(0) end
            if details.BackgroundBottom then details.BackgroundBottom:SetAlpha(0) end
            if details.BackgroundMinimized then details.BackgroundMinimized:SetAlpha(0) end
            SkinBase.CreateBackdrop(details, sr, sg, sb, sa * 0.3, dr, dg, db, da)
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

local function SkinProfessions()
    if not IsEnabled() then return end

    local frame = _G.ProfessionsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    HookProfessionTableHeaderFonts()

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HideDecorations(frame)
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.SkinCloseButton(frame.CloseButton or _G.ProfessionsFrameCloseButton)

    SkinTabs(frame)
    SkinCraftingPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinOrdersPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinSpecPage(frame)

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

local function RefreshProfessionsColors()
    local frame = _G.ProfessionsFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    local mainBd = SkinBase.GetBackdrop(frame)
    if mainBd then
        SkinBase.SetBackdropColors(mainBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.RefreshTabGroup(frame.TabSystem.tabs, frame)
    end

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

SkinBase.OnAddOnLoaded("Blizzard_Professions", SkinProfessions, 0)
