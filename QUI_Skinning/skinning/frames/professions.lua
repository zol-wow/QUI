local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- PROFESSIONS FRAME SKINNING
---------------------------------------------------------------------------

-- Check if skinning is enabled
local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinProfessions
end


-- Style a ScrollBox row entry. Keeps the professions-specific divider/padding
-- and no-content guards plus the SkillUps inset, delegating the backdrop to
-- SkinBase.
local function StyleScrollBoxRow(row)
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

    SkinBase.SkinScrollRow(row)
    SkinBase.SkinFrameText(row, { recurse = true })

    -- Inset backdrop past the skill-up icon area on recipe rows
    if row.SkillUps then
        local bd = SkinBase.GetBackdrop(row)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", row.SkillUps, "TOPRIGHT", 0, 0)
            bd:SetPoint("BOTTOMRIGHT")
        end
    end
end

---------------------------------------------------------------------------
-- HIDE DECORATIONS
---------------------------------------------------------------------------

local function HideDecorations(frame)
    if not frame then return end
    SkinBase.HidePortraitFrameChrome(frame)
    SkinBase.StripTextures(frame)
end

-- Hide a subpanel's NineSlice/Background and apply the standard SUBPANEL backdrop
local function SkinSubPanel(panel, sr, sg, sb, sa)
    if not panel then return end
    if panel.NineSlice then panel.NineSlice:Hide() end
    if panel.Background then panel.Background:SetAlpha(0) end
    local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(panel, sr, sg, sb, sa * 0.3, dr, dg, db, da)
end

---------------------------------------------------------------------------
-- SKIN TABS
---------------------------------------------------------------------------

local function SkinTabs(frame)
    if not frame or not frame.TabSystem then return end
    local tabs = frame.TabSystem.tabs
    if not tabs then return end
    SkinBase.SkinTabGroup(tabs, frame, { hover = true })
end

---------------------------------------------------------------------------
-- SKIN RECIPE LIST (shared between CraftingPage and OrdersPage)
---------------------------------------------------------------------------

local function SkinRecipeList(recipeList)
    if not recipeList then return end

    -- Hide decorations
    if recipeList.Background then recipeList.Background:SetAlpha(0) end
    if recipeList.BackgroundNineSlice then recipeList.BackgroundNineSlice:Hide() end
    SkinBase.StripTextures(recipeList)

    -- Search box
    if recipeList.SearchBox then
        SkinBase.SkinEditBox(recipeList.SearchBox)
    end

    -- Filter dropdown (don't strip textures — preserves clear-filter X button;
    -- backdrop sits below child controls)
    if recipeList.FilterDropdown then
        SkinBase.SkinDropdown(recipeList.FilterDropdown, { noStrip = true, belowChildren = true })
    end

    -- ScrollBox
    if recipeList.ScrollBox then
        SkinBase.HookScrollBoxAcquired(recipeList.ScrollBox, StyleScrollBoxRow)
    end
    if recipeList.ScrollBar and recipeList.ScrollBar.Background then
        recipeList.ScrollBar.Background:Hide()
    end
end

---------------------------------------------------------------------------
-- SKIN CRAFTING PAGE
---------------------------------------------------------------------------

-- Full color tuple kept: the raw CreateBackdrop panel styling below uses
-- per-panel alpha/boost tweaks the shared widget helpers don't express.
local function SkinCraftingPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local craftingPage = frame.CraftingPage
    if not craftingPage then return end

    -- Recipe list (left panel)
    SkinRecipeList(craftingPage.RecipeList)

    -- Schematic form (right panel)
    local schematicForm = craftingPage.SchematicForm
    if schematicForm then
        if schematicForm.NineSlice then schematicForm.NineSlice:Hide() end
        if schematicForm.Background then schematicForm.Background:SetAlpha(0) end
        if schematicForm.MinimalBackground then schematicForm.MinimalBackground:SetAlpha(0) end
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(schematicForm, sr, sg, sb, sa * 0.3, dr, dg, db, da)

        -- Details panel backgrounds
        local details = schematicForm.Details
        if details then
            if details.BackgroundTop then details.BackgroundTop:SetAlpha(0) end
            if details.BackgroundMiddle then details.BackgroundMiddle:SetAlpha(0) end
            if details.BackgroundBottom then details.BackgroundBottom:SetAlpha(0) end
            if details.BackgroundMinimized then details.BackgroundMinimized:SetAlpha(0) end
            SkinBase.CreateBackdrop(details, sr, sg, sb, sa * 0.3, dr, dg, db, da)
        end
    end

    -- Minimized search box
    if craftingPage.MinimizedSearchBox then
        SkinBase.SkinEditBox(craftingPage.MinimizedSearchBox)
    end

    -- Buttons
    if craftingPage.CreateButton then
        SkinBase.SkinButton(craftingPage.CreateButton)
    end
    if craftingPage.CreateAllButton then
        SkinBase.SkinButton(craftingPage.CreateAllButton)
    end
    if craftingPage.ViewGuildCraftersButton then
        SkinBase.SkinButton(craftingPage.ViewGuildCraftersButton)
    end
end

---------------------------------------------------------------------------
-- SKIN ORDERS PAGE (crafter side)
---------------------------------------------------------------------------

-- Full color tuple kept: the raw CreateBackdrop panel styling below uses
-- per-panel alpha/boost tweaks the shared widget helpers don't express.
local function SkinOrdersPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local ordersPage = frame.OrdersPage
    if not ordersPage then return end

    local browseFrame = ordersPage.BrowseFrame
    if browseFrame then
        -- Recipe list (left panel)
        SkinRecipeList(browseFrame.RecipeList)

        -- Order list (right panel)
        SkinBase.SkinListContainer(browseFrame.OrderList, StyleScrollBoxRow)

        -- Search / back buttons
        if browseFrame.SearchButton then
            SkinBase.SkinButton(browseFrame.SearchButton)
        end
        if browseFrame.FavoritesSearchButton then
            SkinBase.SkinButton(browseFrame.FavoritesSearchButton)
        end

        -- Order type tab buttons
        local orderTabs = { browseFrame.PublicOrdersButton, browseFrame.GuildOrdersButton, browseFrame.NpcOrdersButton, browseFrame.PersonalOrdersButton }
        for _, tab in ipairs(orderTabs) do
            if tab then
                SkinBase.SkinButton(tab)
            end
        end
    end

    -- Order view (individual order detail)
    local orderView = ordersPage.OrderView
    if orderView then
        -- The order view form uses similar structure to the customer orders form
        SkinSubPanel(orderView.OrderDetails, sr, sg, sb, sa)
        SkinSubPanel(orderView.OrderInfo, sr, sg, sb, sa)
        -- Buttons
        if orderView.CreateButton then
            SkinBase.SkinButton(orderView.CreateButton)
        end
        if orderView.StartOrderButton then
            SkinBase.SkinButton(orderView.StartOrderButton)
        end
        if orderView.CompleteOrderButton then
            SkinBase.SkinButton(orderView.CompleteOrderButton)
        end
        if orderView.DeclineOrderButton then
            SkinBase.SkinButton(orderView.DeclineOrderButton)
        end
        if orderView.ReleaseOrderButton then
            SkinBase.SkinButton(orderView.ReleaseOrderButton)
        end
        if orderView.BackButton then
            SkinBase.SkinButton(orderView.BackButton)
        end
    end
end

---------------------------------------------------------------------------
-- SKIN SPEC PAGE (specialization talent tree)
---------------------------------------------------------------------------

-- Style a spec pool tab (ProfessionSpecTabTemplate).
-- `owner` is the spec page that owns the tab and drives selection state —
-- SkinTab/RefreshTabSelected need it to compute IsTabSelected.
local function StyleSpecPoolTab(tab, owner)
    if not tab or SkinBase.IsStyled(tab) then return end
    SkinBase.SkinTab(tab, owner, { hover = true })
    SkinBase.RefreshTabSelected(tab, owner)
end

-- Skin all active spec pool tabs and hook the pool for future tabs
local function SkinSpecPoolTabs(specPage)
    local pool = specPage.tabsPool
    if not pool then return end

    for tab in pool:EnumerateActive() do
        StyleSpecPoolTab(tab, specPage)
    end

    -- Hook pool Acquire to catch future tabs
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

    -- Spec pool tabs (specialization tree tabs at top)
    SkinSpecPoolTabs(specPage)

    -- Footer
    if specPage.PanelFooter then
        SkinBase.StripTextures(specPage.PanelFooter)
    end

    -- Dividers
    if specPage.VerticalDivider then SkinBase.StripTextures(specPage.VerticalDivider) end
    if specPage.TopDivider then SkinBase.StripTextures(specPage.TopDivider) end

    -- Buttons
    if specPage.ApplyButton then
        SkinBase.SkinButton(specPage.ApplyButton)
    end
    if specPage.UnlockTabButton then
        SkinBase.SkinButton(specPage.UnlockTabButton)
    end
    if specPage.ViewTreeButton then
        SkinBase.SkinButton(specPage.ViewTreeButton)
    end
    if specPage.BackToPreviewButton then
        SkinBase.SkinButton(specPage.BackToPreviewButton)
    end
    if specPage.ViewPreviewButton then
        SkinBase.SkinButton(specPage.ViewPreviewButton)
    end
    if specPage.BackToFullTreeButton then
        SkinBase.SkinButton(specPage.BackToFullTreeButton)
    end

    -- Detailed view background
    local detailedView = specPage.DetailedView
    if detailedView then
        if detailedView.Background then detailedView.Background:SetAlpha(0) end
        if detailedView.SpendPointsButton then
            SkinBase.SkinButton(detailedView.SpendPointsButton)
        end
        if detailedView.UnlockPathButton then
            SkinBase.SkinButton(detailedView.UnlockPathButton)
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

    SkinBase.SkinCloseButton(frame.CloseButton or _G.ProfessionsFrameCloseButton)

    SkinTabs(frame)
    SkinCraftingPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinOrdersPage(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinSpecPage(frame)

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

---------------------------------------------------------------------------
-- REFRESH COLORS (for live theme changes)
---------------------------------------------------------------------------

-- Panel backdrops use frame-specific alphas/boosts (raw CreateBackdrop, not the
-- shared widget API) so they keep their own color refresh.
local function UpdatePanelColors(panel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = panel and SkinBase.GetBackdrop(panel)
    if not bd then return end
    bd:SetBackdropColor(SkinBase.GetDepthColor("SUBPANEL"))
    bd:SetBackdropBorderColor(sr, sg, sb, sa * 0.3)
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

    -- Main backdrop
    local mainBd = SkinBase.GetBackdrop(frame)
    if mainBd then
        mainBd:SetBackdropColor(bgr, bgg, bgb, bga)
        mainBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Tabs
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.RefreshTabGroup(frame.TabSystem.tabs, frame)
    end

    -- Crafting page
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

    -- Orders page
    local ordersPage = frame.OrdersPage
    if ordersPage and ordersPage.BrowseFrame then
        local bf = ordersPage.BrowseFrame
        UpdateRecipeListColors(bf.RecipeList)
        SkinBase.RefreshWidget(bf.SearchButton)
        SkinBase.RefreshWidget(bf.FavoritesSearchButton)
        local orderTabs = { bf.PublicOrdersButton, bf.GuildOrdersButton, bf.NpcOrdersButton, bf.PersonalOrdersButton }
        for _, tab in ipairs(orderTabs) do
            SkinBase.RefreshWidget(tab)
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

    -- Spec page
    local specPage = frame.SpecPage
    if specPage then
        -- Spec pool tabs (pooled — gather active tabs and refresh as a group)
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
