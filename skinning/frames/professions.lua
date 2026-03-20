local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- PROFESSIONS FRAME SKINNING
---------------------------------------------------------------------------

-- Style a button
local function StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)

    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.Center then button.Center:SetAlpha(0) end

    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local normal = button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end

    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })

    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetBackdrop(self)
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            local r, g, b, a = unpack(sc)
            bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetBackdrop(self)
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            bd:SetBackdropBorderColor(unpack(sc))
        end
    end)

    SkinBase.MarkStyled(button)
end

-- Style edit box
local function StyleEditBox(editBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not editBox or SkinBase.IsStyled(editBox) then return end

    SkinBase.StripTextures(editBox)
    SkinBase.CreateBackdrop(editBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.MarkStyled(editBox)
end

-- Style close button
local function StyleCloseButton(closeButton)
    if not closeButton then return end
    if closeButton.Border then closeButton.Border:SetAlpha(0) end
end

-- Check if skinning is enabled
local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinProfessions
end

-- Safely iterate a ScrollBox's visible frames
local function SafeForEachFrame(scrollBox, callback)
    if scrollBox and scrollBox.ForEachFrame then
        pcall(scrollBox.ForEachFrame, scrollBox, callback)
    end
end

-- Style a ScrollBox row entry
local function StyleScrollBoxRow(row, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not row or SkinBase.IsStyled(row) then return end

    -- Skip divider and padding spacer rows
    local node = row.GetElementData and row:GetElementData()
    if node then
        local data = node.GetData and node:GetData()
        if data and (data.isDivider or data.topPadding or data.bottomPadding) then
            return
        end
    end
    -- Fallback: skip frames with no visible text content (spacers)
    if not row.Label and not row.Text and not row.Icon then return end

    SkinBase.StripTextures(row)

    local rowBgR = math.min(bgr + 0.03, 1)
    local rowBgG = math.min(bgg + 0.03, 1)
    local rowBgB = math.min(bgb + 0.03, 1)
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * 0.5, rowBgR, rowBgG, rowBgB, 0.6)

    -- Inset backdrop past the skill-up icon area on recipe rows
    if row.SkillUps then
        local bd = SkinBase.GetBackdrop(row)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", row.SkillUps, "TOPRIGHT", 0, 0)
            bd:SetPoint("BOTTOMRIGHT")
        end
    end

    SkinBase.SetFrameData(row, "skinColor", { sr, sg, sb, sa * 0.5 })

    row:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetBackdrop(self)
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            local r, g, b, a = unpack(sc)
            bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    row:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetBackdrop(self)
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            bd:SetBackdropBorderColor(unpack(sc))
        end
    end)

    SkinBase.MarkStyled(row)
end

-- Hook a ScrollBox to style rows as they're recycled
local function HookScrollBox(scrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not scrollBox or SkinBase.GetFrameData(scrollBox, "hooked") then return end

    hooksecurefunc(scrollBox, "Update", function(self)
        C_Timer.After(0, function()
            SafeForEachFrame(self, function(row)
                StyleScrollBoxRow(row, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)
        end)
    end)

    C_Timer.After(0, function()
        SafeForEachFrame(scrollBox, function(row)
            StyleScrollBoxRow(row, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end)
    end)

    SkinBase.SetFrameData(scrollBox, "hooked", true)
end

-- Skin a list container (NineSlice + Background + ScrollBox + ScrollBar)
local function SkinListContainer(list, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not list then return end
    if list.NineSlice then list.NineSlice:Hide() end
    if list.BackgroundNineSlice then list.BackgroundNineSlice:Hide() end
    if list.Background then list.Background:SetAlpha(0) end
    SkinBase.StripTextures(list)
    if list.ScrollBox then
        HookScrollBox(list.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if list.ScrollBar and list.ScrollBar.Background then
        list.ScrollBar.Background:Hide()
    end
end

---------------------------------------------------------------------------
-- TAB HANDLING
-- ProfessionsFrame uses TabSystemTemplate (not PanelTemplates_SetTab)
---------------------------------------------------------------------------

local function UpdateTabSelectedState(frame)
    if not frame or not frame.TabSystem then return end
    local tabSystem = frame.TabSystem
    -- TabSystemTemplate stores tabs in tabSystem.tabs
    local tabs = tabSystem.tabs
    if not tabs then return end
    local selectedTabID = tabSystem.GetSelectedTab and tabSystem:GetSelectedTab() or nil
    for _, tab in ipairs(tabs) do
        local bd = SkinBase.GetBackdrop(tab)
        local sc = SkinBase.GetFrameData(tab, "skinColor")
        local bg = SkinBase.GetFrameData(tab, "bgColor")
        if bd and sc and bg then
            local isSelected = (tab.tabID == selectedTabID) or (tab.IsSelected and tab:IsSelected())
            if isSelected then
                bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
                bd:SetBackdropColor(math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1)
            else
                bd:SetBackdropBorderColor(sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6)
                bd:SetBackdropColor(bg[1], bg[2], bg[3], 0.7)
            end
        end
    end
end

-- Style a TabSystem tab button
local function StyleTabSystemTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not tab or SkinBase.IsStyled(tab) then return end

    SkinBase.StripTextures(tab)
    local highlight = tab:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
    local tabBackdrop = SkinBase.GetBackdrop(tab)
    if tabBackdrop then
        tabBackdrop:ClearAllPoints()
        tabBackdrop:SetPoint("TOPLEFT", 3, -3)
        tabBackdrop:SetPoint("BOTTOMRIGHT", -3, 0)
    end

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })

    SkinBase.MarkStyled(tab)
end

---------------------------------------------------------------------------
-- HIDE DECORATIONS
---------------------------------------------------------------------------

local function HideDecorations(frame)
    if not frame then return end

    -- PortraitFrameTemplate elements
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.Background then frame.Background:Hide() end
    if frame.PortraitContainer then frame.PortraitContainer:Hide() end
    if frame.TitleContainer then
        if frame.TitleContainer.TitleBg then frame.TitleContainer.TitleBg:Hide() end
    end

    SkinBase.StripTextures(frame)
end

---------------------------------------------------------------------------
-- SKIN TABS
---------------------------------------------------------------------------

local function SkinTabs(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame or not frame.TabSystem then return end

    local tabSystem = frame.TabSystem
    local tabs = tabSystem.tabs
    if not tabs then return end

    for _, tab in ipairs(tabs) do
        StyleTabSystemTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Hook tab selection to update visuals
    if not SkinBase.GetFrameData(tabSystem, "hooked") then
        hooksecurefunc(tabSystem, "SetTab", function()
            C_Timer.After(0, function() UpdateTabSelectedState(frame) end)
        end)
        SkinBase.SetFrameData(tabSystem, "hooked", true)
    end

    UpdateTabSelectedState(frame)
end

---------------------------------------------------------------------------
-- SKIN RECIPE LIST (shared between CraftingPage and OrdersPage)
---------------------------------------------------------------------------

local function SkinRecipeList(recipeList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not recipeList then return end

    -- Hide decorations
    if recipeList.Background then recipeList.Background:SetAlpha(0) end
    if recipeList.BackgroundNineSlice then recipeList.BackgroundNineSlice:Hide() end
    SkinBase.StripTextures(recipeList)

    -- Search box
    if recipeList.SearchBox then
        StyleEditBox(recipeList.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Filter dropdown (don't strip textures — preserves clear-filter X button)
    if recipeList.FilterDropdown then
        SkinBase.CreateBackdrop(recipeList.FilterDropdown, sr, sg, sb, sa, math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
    end

    -- ScrollBox
    if recipeList.ScrollBox then
        HookScrollBox(recipeList.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if recipeList.ScrollBar and recipeList.ScrollBar.Background then
        recipeList.ScrollBar.Background:Hide()
    end
end

---------------------------------------------------------------------------
-- SKIN CRAFTING PAGE
---------------------------------------------------------------------------

local function SkinCraftingPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local craftingPage = frame.CraftingPage
    if not craftingPage then return end

    -- Recipe list (left panel)
    SkinRecipeList(craftingPage.RecipeList, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Schematic form (right panel)
    local schematicForm = craftingPage.SchematicForm
    if schematicForm then
        if schematicForm.NineSlice then schematicForm.NineSlice:Hide() end
        if schematicForm.Background then schematicForm.Background:SetAlpha(0) end
        if schematicForm.MinimalBackground then schematicForm.MinimalBackground:SetAlpha(0) end
        SkinBase.CreateBackdrop(schematicForm, sr, sg, sb, sa * 0.3, math.min(bgr + 0.02, 1), math.min(bgg + 0.02, 1), math.min(bgb + 0.02, 1), 0.5)

        -- Details panel backgrounds
        local details = schematicForm.Details
        if details then
            if details.BackgroundTop then details.BackgroundTop:SetAlpha(0) end
            if details.BackgroundMiddle then details.BackgroundMiddle:SetAlpha(0) end
            if details.BackgroundBottom then details.BackgroundBottom:SetAlpha(0) end
            if details.BackgroundMinimized then details.BackgroundMinimized:SetAlpha(0) end
            SkinBase.CreateBackdrop(details, sr, sg, sb, sa * 0.3, math.min(bgr + 0.04, 1), math.min(bgg + 0.04, 1), math.min(bgb + 0.04, 1), 0.6)
        end
    end

    -- Minimized search box
    if craftingPage.MinimizedSearchBox then
        StyleEditBox(craftingPage.MinimizedSearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Buttons
    if craftingPage.CreateButton then
        StyleButton(craftingPage.CreateButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if craftingPage.CreateAllButton then
        StyleButton(craftingPage.CreateAllButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if craftingPage.ViewGuildCraftersButton then
        StyleButton(craftingPage.ViewGuildCraftersButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
end

---------------------------------------------------------------------------
-- SKIN ORDERS PAGE (crafter side)
---------------------------------------------------------------------------

local function SkinOrdersPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local ordersPage = frame.OrdersPage
    if not ordersPage then return end

    local browseFrame = ordersPage.BrowseFrame
    if browseFrame then
        -- Recipe list (left panel)
        SkinRecipeList(browseFrame.RecipeList, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        -- Order list (right panel)
        SkinListContainer(browseFrame.OrderList, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        -- Search / back buttons
        if browseFrame.SearchButton then
            StyleButton(browseFrame.SearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if browseFrame.FavoritesSearchButton then
            StyleButton(browseFrame.FavoritesSearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Order type tab buttons
        local orderTabs = { browseFrame.PublicOrdersButton, browseFrame.GuildOrdersButton, browseFrame.NpcOrdersButton, browseFrame.PersonalOrdersButton }
        for _, tab in ipairs(orderTabs) do
            if tab then
                StyleButton(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
    end

    -- Order view (individual order detail)
    local orderView = ordersPage.OrderView
    if orderView then
        -- The order view form uses similar structure to the customer orders form
        if orderView.OrderDetails then
            local od = orderView.OrderDetails
            if od.NineSlice then od.NineSlice:Hide() end
            if od.Background then od.Background:SetAlpha(0) end
            SkinBase.CreateBackdrop(od, sr, sg, sb, sa * 0.3, math.min(bgr + 0.02, 1), math.min(bgg + 0.02, 1), math.min(bgb + 0.02, 1), 0.5)
        end
        if orderView.OrderInfo then
            local oi = orderView.OrderInfo
            if oi.NineSlice then oi.NineSlice:Hide() end
            if oi.Background then oi.Background:SetAlpha(0) end
            SkinBase.CreateBackdrop(oi, sr, sg, sb, sa * 0.3, math.min(bgr + 0.02, 1), math.min(bgg + 0.02, 1), math.min(bgb + 0.02, 1), 0.5)
        end
        -- Buttons
        if orderView.CreateButton then
            StyleButton(orderView.CreateButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if orderView.StartOrderButton then
            StyleButton(orderView.StartOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if orderView.CompleteOrderButton then
            StyleButton(orderView.CompleteOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if orderView.DeclineOrderButton then
            StyleButton(orderView.DeclineOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if orderView.ReleaseOrderButton then
            StyleButton(orderView.ReleaseOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if orderView.BackButton then
            StyleButton(orderView.BackButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end
end

---------------------------------------------------------------------------
-- SKIN SPEC PAGE (specialization talent tree)
---------------------------------------------------------------------------

-- Style a spec pool tab (ProfessionSpecTabTemplate)
local function StyleSpecPoolTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not tab or SkinBase.IsStyled(tab) then return end

    SkinBase.StripTextures(tab)
    local highlight = tab:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
    local bd = SkinBase.GetBackdrop(tab)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", 3, -3)
        bd:SetPoint("BOTTOMRIGHT", -3, 0)
    end

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })

    SkinBase.MarkStyled(tab)
end

-- Skin all active spec pool tabs and hook the pool for future tabs
local function SkinSpecPoolTabs(specPage, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local pool = specPage.tabsPool
    if not pool then return end

    for tab in pool:EnumerateActive() do
        StyleSpecPoolTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Hook pool Acquire to catch future tabs
    if not SkinBase.GetFrameData(specPage, "tabPoolHooked") then
        hooksecurefunc(pool, "Acquire", function(self)
            C_Timer.After(0, function()
                for t in self:EnumerateActive() do
                    StyleSpecPoolTab(t, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end)
        end)
        SkinBase.SetFrameData(specPage, "tabPoolHooked", true)
    end
end

local function SkinSpecPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local specPage = frame.SpecPage
    if not specPage then return end

    -- Spec pool tabs (specialization tree tabs at top)
    SkinSpecPoolTabs(specPage, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Footer
    if specPage.PanelFooter then
        SkinBase.StripTextures(specPage.PanelFooter)
    end

    -- Dividers
    if specPage.VerticalDivider then SkinBase.StripTextures(specPage.VerticalDivider) end
    if specPage.TopDivider then SkinBase.StripTextures(specPage.TopDivider) end

    -- Buttons
    if specPage.ApplyButton then
        StyleButton(specPage.ApplyButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if specPage.UnlockTabButton then
        StyleButton(specPage.UnlockTabButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if specPage.ViewTreeButton then
        StyleButton(specPage.ViewTreeButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if specPage.BackToPreviewButton then
        StyleButton(specPage.BackToPreviewButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if specPage.ViewPreviewButton then
        StyleButton(specPage.ViewPreviewButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if specPage.BackToFullTreeButton then
        StyleButton(specPage.BackToFullTreeButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Detailed view background
    local detailedView = specPage.DetailedView
    if detailedView then
        if detailedView.Background then detailedView.Background:SetAlpha(0) end
        if detailedView.SpendPointsButton then
            StyleButton(detailedView.SpendPointsButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if detailedView.UnlockPathButton then
            StyleButton(detailedView.UnlockPathButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Tree view background
    local treeView = specPage.TreeView
    if treeView then
        if treeView.Background then treeView.Background:SetAlpha(0) end
    end
end

---------------------------------------------------------------------------
-- MAIN ENTRY POINT
---------------------------------------------------------------------------

local function SkinProfessions()
    if not IsEnabled() then return end

    local frame = _G.ProfessionsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HideDecorations(frame)
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    StyleCloseButton(frame.CloseButton or _G.ProfessionsFrameCloseButton)

    SkinTabs(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinCraftingPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinOrdersPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinSpecPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.MarkSkinned(frame)
end

---------------------------------------------------------------------------
-- REFRESH COLORS (for live theme changes)
---------------------------------------------------------------------------

local function UpdateButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = button and SkinBase.GetBackdrop(button)
    if not bd then return end
    bd:SetBackdropColor(math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
end

local function UpdateEditBoxColors(editBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = editBox and SkinBase.GetBackdrop(editBox)
    if not bd then return end
    bd:SetBackdropColor(bgr, bgg, bgb, bga)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

local function UpdateDropdownColors(dropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = dropdown and SkinBase.GetBackdrop(dropdown)
    if not bd then return end
    bd:SetBackdropColor(math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

local function UpdatePanelColors(panel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = panel and SkinBase.GetBackdrop(panel)
    if not bd then return end
    bd:SetBackdropColor(math.min(bgr + 0.02, 1), math.min(bgg + 0.02, 1), math.min(bgb + 0.02, 1), 0.5)
    bd:SetBackdropBorderColor(sr, sg, sb, sa * 0.3)
end

local function UpdateRecipeListColors(recipeList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not recipeList then return end
    UpdateEditBoxColors(recipeList.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    UpdateDropdownColors(recipeList.FilterDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
end

local function RefreshProfessionsColors()
    local frame = _G.ProfessionsFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Main backdrop
    local mainBd = SkinBase.GetBackdrop(frame)
    if mainBd then
        mainBd:SetBackdropColor(bgr, bgg, bgb, bga)
        mainBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Tabs
    if frame.TabSystem and frame.TabSystem.tabs then
        for _, tab in ipairs(frame.TabSystem.tabs) do
            local bd = SkinBase.GetBackdrop(tab)
            if bd then
                bd:SetBackdropColor(bgr, bgg, bgb, 0.9)
                bd:SetBackdropBorderColor(sr, sg, sb, sa)
            end
        end
        UpdateTabSelectedState(frame)
    end

    -- Crafting page
    local craftingPage = frame.CraftingPage
    if craftingPage then
        UpdateRecipeListColors(craftingPage.RecipeList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateEditBoxColors(craftingPage.MinimizedSearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdatePanelColors(craftingPage.SchematicForm, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if craftingPage.SchematicForm and craftingPage.SchematicForm.Details then
            local detBd = SkinBase.GetBackdrop(craftingPage.SchematicForm.Details)
            if detBd then
                detBd:SetBackdropColor(math.min(bgr + 0.04, 1), math.min(bgg + 0.04, 1), math.min(bgb + 0.04, 1), 0.6)
                detBd:SetBackdropBorderColor(sr, sg, sb, sa * 0.3)
            end
        end
        UpdateButtonColors(craftingPage.CreateButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(craftingPage.CreateAllButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(craftingPage.ViewGuildCraftersButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Orders page
    local ordersPage = frame.OrdersPage
    if ordersPage and ordersPage.BrowseFrame then
        local bf = ordersPage.BrowseFrame
        UpdateRecipeListColors(bf.RecipeList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(bf.SearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(bf.FavoritesSearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        local orderTabs = { bf.PublicOrdersButton, bf.GuildOrdersButton, bf.NpcOrdersButton, bf.PersonalOrdersButton }
        for _, tab in ipairs(orderTabs) do
            UpdateButtonColors(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if ordersPage.OrderView then
            UpdatePanelColors(ordersPage.OrderView.OrderDetails, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdatePanelColors(ordersPage.OrderView.OrderInfo, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(ordersPage.OrderView.CreateButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(ordersPage.OrderView.StartOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(ordersPage.OrderView.CompleteOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(ordersPage.OrderView.DeclineOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(ordersPage.OrderView.ReleaseOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(ordersPage.OrderView.BackButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Spec page
    local specPage = frame.SpecPage
    if specPage then
        -- Spec pool tabs
        if specPage.tabsPool then
            for tab in specPage.tabsPool:EnumerateActive() do
                local bd = SkinBase.GetBackdrop(tab)
                if bd then
                    bd:SetBackdropColor(bgr, bgg, bgb, 0.9)
                    bd:SetBackdropBorderColor(sr, sg, sb, sa)
                    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
                    SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })
                end
            end
        end
        UpdateButtonColors(specPage.ApplyButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(specPage.UnlockTabButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(specPage.ViewTreeButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(specPage.BackToPreviewButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(specPage.ViewPreviewButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(specPage.BackToFullTreeButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if specPage.DetailedView then
            UpdateButtonColors(specPage.DetailedView.SpendPointsButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(specPage.DetailedView.UnlockPathButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end
end

-- Expose refresh function globally
_G.QUI_RefreshProfessionsColors = RefreshProfessionsColors

if ns.Registry then
    ns.Registry:Register("skinProfessions", {
        refresh = _G.QUI_RefreshProfessionsColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "Blizzard_Professions" then
        C_Timer.After(0.1, SkinProfessions)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- If Blizzard_Professions loaded before QUI (e.g. after /reload), skin now
if C_AddOns.IsAddOnLoaded("Blizzard_Professions") then
    C_Timer.After(0.1, SkinProfessions)
    initFrame:UnregisterEvent("ADDON_LOADED")
end
