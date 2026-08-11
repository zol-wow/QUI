local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinCraftingOrders
end

local function SafeForEachFrame(scrollBox, callback)
    ns.SafeCallMethodIfPresent("best-effort-style", scrollBox, "ForEachFrame", callback)
end

local function skinRow(row)
    SkinBase.SkinScrollRow(row)
    SkinBase.LockPooledRowText(row, 4)
end

local function HookProfessionTableHeaderFonts()
    local mixin = _G.ProfessionsCrafterTableHeaderStringMixin
    if not mixin or mixin.Init == nil or SkinBase.GetFrameData(mixin, "headerFontHooked") then return end
    hooksecurefunc(mixin, "Init", function(self)
        SkinBase.ApplyButtonFontObjects(self)
    end)
    SkinBase.SetFrameData(mixin, "headerFontHooked", true)
end

local function SuppressCategoryTextures(button)
    if not button then return end
    SkinBase.StripTextures(button)
    if button.SelectedTexture then button.SelectedTexture:SetAlpha(0) end
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
end

local function HideDecorations(frame)
    if not frame then return end
    SkinBase.HidePortraitFrameChrome(frame)

    if frame.MoneyFrameInset then
        frame.MoneyFrameInset:Hide()
        if frame.MoneyFrameInset.NineSlice then frame.MoneyFrameInset.NineSlice:Hide() end
    end
    if frame.MoneyFrameBorder then frame.MoneyFrameBorder:Hide() end

    SkinBase.StripTextures(frame)
end

local function SkinTabs(frame)
    if not frame then return end
    local tabs = { frame.BrowseTab, frame.OrdersTab }
    SkinBase.SkinTabGroup(tabs, frame, { font = true })
    if tabs[1] then
        tabs[1]:ClearAllPoints()
        tabs[1]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -3, -30)
    end
    if tabs[2] and tabs[1] then
        tabs[2]:ClearAllPoints()
        tabs[2]:SetPoint("TOPLEFT", tabs[1], "TOPRIGHT", -5, 0)
    end
end

local function SkinBrowseOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local browseOrders = frame.BrowseOrders
    if not browseOrders then return end

    local searchBar = browseOrders.SearchBar
    if searchBar then
        if searchBar.SearchBox then
            SkinBase.SkinEditBox(searchBar.SearchBox, { font = true })
        end
        if searchBar.SearchButton then
            SkinBase.SkinButton(searchBar.SearchButton, { font = true })
        end
        if searchBar.FavoritesSearchButton then
            SkinBase.SkinButton(searchBar.FavoritesSearchButton, { font = true })
        end
        if searchBar.FilterDropdown then
            local dropdown = searchBar.FilterDropdown
            SkinBase.SkinDropdown(dropdown, { belowChildren = true })
            if dropdown.ValidateResetState then
                C_Timer.After(0, function() ns.SafeCallMethod("best-effort-style", dropdown, "ValidateResetState") end)
            end
        end
    end

    local categoryList = browseOrders.CategoryList
    if categoryList then
        SkinBase.StripTextures(categoryList)
        if categoryList.NineSlice then categoryList.NineSlice:Hide() end
        if categoryList.Background then categoryList.Background:SetAlpha(0) end

        local function StyleCategoryRow(button)
            SkinBase.SkinCategoryButton(button)
            SuppressCategoryTextures(button)
            SkinBase.RefreshCategorySelected(button)
            SkinBase.SkinFontString(button.Text)
            SkinBase.LockFontObject(button, { fontOnly = true })
            SkinBase.ApplyButtonFontObjects(button)
        end
        local function RefreshCategoryButtons(self)
            SafeForEachFrame(self, StyleCategoryRow)
        end

        SkinBase.HookScrollBoxAcquired(categoryList.ScrollBox, StyleCategoryRow)

        local catMixin = _G.ProfessionsCustomerOrdersCategoryButtonMixin
        if catMixin and catMixin.Init and not SkinBase.GetFrameData(categoryList, "categoryInitHooked") then
            hooksecurefunc(catMixin, "Init", function(self)
                if not IsEnabled() or self.isSpacer then return end
                StyleCategoryRow(self)
            end)
            SkinBase.SetFrameData(categoryList, "categoryInitHooked", true)
        end

        if categoryList.SetCategoryFilter and not SkinBase.GetFrameData(categoryList, "clickHooked") then
            hooksecurefunc(categoryList, "SetCategoryFilter", function()
                C_Timer.After(0, function()
                    if categoryList.ScrollBox then
                        RefreshCategoryButtons(categoryList.ScrollBox)
                    end
                end)
            end)
            SkinBase.SetFrameData(categoryList, "clickHooked", true)
        end

        if categoryList.ScrollBar then
            SkinBase.SkinTrimScrollBar(categoryList.ScrollBar)
        end
    end

    SkinBase.SkinListContainer(browseOrders.RecipeList, skinRow)
end

local function SkinMyOrders(frame)
    if not frame then return end

    local myOrders = frame.MyOrdersPage
    if not myOrders then return end

    SkinBase.SkinListContainer(myOrders.OrderList, skinRow)

    if myOrders.RefreshButton then
        SkinBase.SkinButton(myOrders.RefreshButton, { font = true })
    end
end

local function SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local form = frame.Form
    if not form then return end

    if form.LeftPanelBackground then
        if form.LeftPanelBackground.NineSlice then form.LeftPanelBackground.NineSlice:Hide() end
        if form.LeftPanelBackground.Background then form.LeftPanelBackground.Background:SetAlpha(0) end
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(form.LeftPanelBackground, sr, sg, sb, sa * 0.3, dr, dg, db, da)
    end

    if form.RightPanelBackground then
        if form.RightPanelBackground.NineSlice then form.RightPanelBackground.NineSlice:Hide() end
        if form.RightPanelBackground.Background then form.RightPanelBackground.Background:SetAlpha(0) end
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(form.RightPanelBackground, sr, sg, sb, sa * 0.3, dr, dg, db, da)
    end

    if form.BackButton then
        SkinBase.SkinButton(form.BackButton, { font = true })
    end

    if form.PaymentContainer then
        local pc = form.PaymentContainer
        if pc.ListOrderButton then
            SkinBase.SkinButton(pc.ListOrderButton, { font = true })
        end
        if pc.CancelOrderButton then
            SkinBase.SkinButton(pc.CancelOrderButton, { font = true })
        end
        if pc.DurationDropdown then
            SkinBase.SkinDropdown(pc.DurationDropdown)
        end
        if pc.NoteEditBox then
            SkinBase.SkinEditBox(pc.NoteEditBox, { borderAlpha = 0.5, bgAlpha = 0.8 })
        end
    end

    if form.MinimumQuality and form.MinimumQuality.Dropdown then
        SkinBase.SkinDropdown(form.MinimumQuality.Dropdown)
    end
    if form.OrderRecipientDropdown then
        SkinBase.SkinDropdown(form.OrderRecipientDropdown)
    end

    if form.OrderRecipientTarget then
        SkinBase.SkinEditBox(form.OrderRecipientTarget)
    end

    if form.CurrentListings then
        local listings = form.CurrentListings
        if listings.NineSlice then listings.NineSlice:Hide() end
        SkinBase.StripTextures(listings)
        SkinBase.CreateBackdrop(listings, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        if listings.OrderList then
            SkinBase.SkinListContainer(listings.OrderList, skinRow)
        end
        if listings.CloseButton then
            SkinBase.SkinButton(listings.CloseButton, { font = true })
        end
    end
end

local function SkinCraftingOrders()
    if not IsEnabled() then return end

    local frame = _G.ProfessionsCustomerOrdersFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HideDecorations(frame)
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.SkinCloseButton(frame.CloseButton or _G.ProfessionsCustomerOrdersFrameCloseButton)

    HookProfessionTableHeaderFonts()
    SkinTabs(frame)
    SkinBrowseOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinMyOrders(frame)
    SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.MarkSkinned(frame)
end

local function UpdatePanelColors(panel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = panel and SkinBase.GetBackdrop(panel)
    if not bd then return end
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa * 0.3 }, { SkinBase.GetDepthColor("SUBPANEL") })
end

local function RefreshCraftingOrdersColors()
    local frame = _G.ProfessionsCustomerOrdersFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    local mainBd = SkinBase.GetBackdrop(frame)
    if mainBd then
        SkinBase.SetBackdropColors(mainBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    SkinBase.RefreshTabGroup({ frame.BrowseTab, frame.OrdersTab }, frame)

    local browseOrders = frame.BrowseOrders
    if browseOrders then
        local searchBar = browseOrders.SearchBar
        if searchBar then
            SkinBase.RefreshWidget(searchBar.SearchBox)
            SkinBase.RefreshWidget(searchBar.SearchButton)
            SkinBase.RefreshWidget(searchBar.FavoritesSearchButton)
            SkinBase.RefreshWidget(searchBar.FilterDropdown)
        end
    end

    local myOrders = frame.MyOrdersPage
    if myOrders then
        SkinBase.RefreshWidget(myOrders.RefreshButton)
    end

    local form = frame.Form
    if form then
        SkinBase.RefreshWidget(form.BackButton)
        UpdatePanelColors(form.LeftPanelBackground, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdatePanelColors(form.RightPanelBackground, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        SkinBase.RefreshWidget(form.OrderRecipientDropdown)
        SkinBase.RefreshWidget(form.OrderRecipientTarget)
        if form.MinimumQuality and form.MinimumQuality.Dropdown then
            SkinBase.RefreshWidget(form.MinimumQuality.Dropdown)
        end
        if form.PaymentContainer then
            local pc = form.PaymentContainer
            SkinBase.RefreshWidget(pc.ListOrderButton)
            SkinBase.RefreshWidget(pc.CancelOrderButton)
            SkinBase.RefreshWidget(pc.DurationDropdown)
            SkinBase.RefreshWidget(pc.NoteEditBox)
        end
        if form.CurrentListings then
            local listingsBd = SkinBase.GetBackdrop(form.CurrentListings)
            if listingsBd then
                SkinBase.SetBackdropColors(listingsBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
            end
            SkinBase.RefreshWidget(form.CurrentListings.CloseButton)
        end
    end
end

_G.QUI_RefreshCraftingOrdersColors = RefreshCraftingOrdersColors

if ns.Registry then
    ns.Registry:Register("skinCraftingOrders", {
        refresh = _G.QUI_RefreshCraftingOrdersColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_ProfessionsCustomerOrders", SkinCraftingOrders, 0)
