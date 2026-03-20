local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- CRAFTING ORDERS (WORK ORDERS) SKINNING
---------------------------------------------------------------------------

-- Style a button (same pattern as auctionhouse)
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

-- Style tab button
local function StyleTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not tab or SkinBase.IsStyled(tab) then return end

    if tab.Left then tab.Left:SetAlpha(0) end
    if tab.Middle then tab.Middle:SetAlpha(0) end
    if tab.Right then tab.Right:SetAlpha(0) end
    if tab.LeftDisabled then tab.LeftDisabled:SetAlpha(0) end
    if tab.MiddleDisabled then tab.MiddleDisabled:SetAlpha(0) end
    if tab.RightDisabled then tab.RightDisabled:SetAlpha(0) end
    if tab.LeftActive then tab.LeftActive:SetAlpha(0) end
    if tab.MiddleActive then tab.MiddleActive:SetAlpha(0) end
    if tab.RightActive then tab.RightActive:SetAlpha(0) end
    if tab.LeftHighlight then tab.LeftHighlight:SetAlpha(0) end
    if tab.MiddleHighlight then tab.MiddleHighlight:SetAlpha(0) end
    if tab.RightHighlight then tab.RightHighlight:SetAlpha(0) end

    local highlight = tab:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
    local tabBackdrop = SkinBase.GetBackdrop(tab)
    tabBackdrop:ClearAllPoints()
    tabBackdrop:SetPoint("TOPLEFT", 3, -3)
    tabBackdrop:SetPoint("BOTTOMRIGHT", -3, 0)

    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })

    SkinBase.MarkStyled(tab)
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
    return settings and settings.skinCraftingOrders
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

    SkinBase.StripTextures(row)

    local rowBgR = math.min(bgr + 0.03, 1)
    local rowBgG = math.min(bgg + 0.03, 1)
    local rowBgB = math.min(bgb + 0.03, 1)
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * 0.5, rowBgR, rowBgG, rowBgB, 0.6)

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

    -- TAINT SAFETY: Defer to break taint chain from Update context.
    hooksecurefunc(scrollBox, "Update", function(self)
        C_Timer.After(0, function()
            SafeForEachFrame(self, function(row)
                StyleScrollBoxRow(row, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)
        end)
    end)

    -- Style existing rows (deferred)
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
    if list.Background then list.Background:SetAlpha(0) end
    SkinBase.StripTextures(list)
    if list.ScrollBox then
        HookScrollBox(list.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    if list.ScrollBar and list.ScrollBar.Background then
        list.ScrollBar.Background:Hide()
    end
end

-- Update a category button's backdrop to reflect selected state
local function UpdateCategorySelected(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = SkinBase.GetBackdrop(button)
    if not bd then return end
    local isSelected = button.SelectedTexture and button.SelectedTexture:IsShown()
    if isSelected then
        bd:SetBackdropBorderColor(sr, sg, sb, sa)
        bd:SetBackdropColor(math.min(bgr + 0.10, 1), math.min(bgg + 0.10, 1), math.min(bgb + 0.10, 1), 0.9)
    else
        bd:SetBackdropBorderColor(sr, sg, sb, sa * 0.5)
        bd:SetBackdropColor(math.min(bgr + 0.05, 1), math.min(bgg + 0.05, 1), math.min(bgb + 0.05, 1), 0.7)
    end
end

-- Style a category list button
local function StyleCategoryButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    SkinBase.StripTextures(button)
    if button.SelectedTexture then button.SelectedTexture:SetAlpha(0) end
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    SkinBase.CreateBackdrop(button, sr, sg, sb, sa * 0.5, math.min(bgr + 0.05, 1), math.min(bgg + 0.05, 1), math.min(bgb + 0.05, 1), 0.7)

    UpdateCategorySelected(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(button, "bgColor", { bgr, bgg, bgb })

    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetBackdrop(self)
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            local r, g, b = unpack(sc)
            bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), 1)
        end
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetBackdrop(self)
        local sc = SkinBase.GetFrameData(self, "skinColor")
        local bg = SkinBase.GetFrameData(self, "bgColor")
        if bd and sc and bg then
            UpdateCategorySelected(self, sc[1], sc[2], sc[3], 1, bg[1], bg[2], bg[3], 1)
        end
    end)

    SkinBase.MarkStyled(button)
end

---------------------------------------------------------------------------
-- TAB HANDLING
---------------------------------------------------------------------------

local selectedTab = 1

local function UpdateTabSelectedState(frame)
    if not frame then return end
    local tabs = { frame.BrowseTab, frame.OrdersTab }
    for i, tab in ipairs(tabs) do
        local bd = SkinBase.GetBackdrop(tab)
        local sc = SkinBase.GetFrameData(tab, "skinColor")
        local bg = SkinBase.GetFrameData(tab, "bgColor")
        if bd and sc and bg then
            local isSelected = (selectedTab == i)
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

    -- Money frame
    if frame.MoneyFrameInset then
        frame.MoneyFrameInset:Hide()
        if frame.MoneyFrameInset.NineSlice then frame.MoneyFrameInset.NineSlice:Hide() end
    end
    if frame.MoneyFrameBorder then frame.MoneyFrameBorder:Hide() end

    SkinBase.StripTextures(frame)
end

---------------------------------------------------------------------------
-- SKIN TABS
---------------------------------------------------------------------------

local function SkinTabs(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local tabs = { frame.BrowseTab, frame.OrdersTab }
    for _, tab in ipairs(tabs) do
        StyleTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Reposition tabs
    if tabs[1] then
        tabs[1]:ClearAllPoints()
        tabs[1]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -3, -30)
    end
    if tabs[2] and tabs[1] then
        tabs[2]:ClearAllPoints()
        tabs[2]:SetPoint("TOPLEFT", tabs[1], "TOPRIGHT", -5, 0)
    end

    -- Hook tab clicks to track selection
    if frame.BrowseTab and not SkinBase.GetFrameData(frame.BrowseTab, "clickHooked") then
        frame.BrowseTab:HookScript("OnClick", function()
            selectedTab = 1
            C_Timer.After(0, function() UpdateTabSelectedState(frame) end)
        end)
        SkinBase.SetFrameData(frame.BrowseTab, "clickHooked", true)
    end
    if frame.OrdersTab and not SkinBase.GetFrameData(frame.OrdersTab, "clickHooked") then
        frame.OrdersTab:HookScript("OnClick", function()
            selectedTab = 2
            C_Timer.After(0, function() UpdateTabSelectedState(frame) end)
        end)
        SkinBase.SetFrameData(frame.OrdersTab, "clickHooked", true)
    end

    UpdateTabSelectedState(frame)
end

---------------------------------------------------------------------------
-- SKIN BROWSE ORDERS PAGE
---------------------------------------------------------------------------

local function SkinBrowseOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local browseOrders = frame.BrowseOrders
    if not browseOrders then return end

    -- Search bar
    local searchBar = browseOrders.SearchBar
    if searchBar then
        if searchBar.SearchBox then
            StyleEditBox(searchBar.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if searchBar.SearchButton then
            StyleButton(searchBar.SearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if searchBar.FavoritesSearchButton then
            StyleButton(searchBar.FavoritesSearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Filter dropdown (don't strip textures — preserves the clear-filter X button)
        if searchBar.FilterDropdown then
            SkinBase.CreateBackdrop(searchBar.FilterDropdown, sr, sg, sb, sa, math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
        end
    end

    -- Category list
    local categoryList = browseOrders.CategoryList
    if categoryList then
        SkinBase.StripTextures(categoryList)
        if categoryList.NineSlice then categoryList.NineSlice:Hide() end
        if categoryList.Background then categoryList.Background:SetAlpha(0) end

        local function RefreshCategoryButtons(scrollBox)
            SafeForEachFrame(scrollBox, function(button)
                StyleCategoryButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                UpdateCategorySelected(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)
        end

        local scrollBox = categoryList.ScrollBox
        if scrollBox and not SkinBase.GetFrameData(scrollBox, "hooked") then
            hooksecurefunc(scrollBox, "Update", function(self)
                C_Timer.After(0, function()
                    RefreshCategoryButtons(self)
                end)
            end)

            C_Timer.After(0, function()
                RefreshCategoryButtons(scrollBox)
            end)

            SkinBase.SetFrameData(scrollBox, "hooked", true)
        end

        if categoryList.ScrollBar and categoryList.ScrollBar.Background then
            categoryList.ScrollBar.Background:Hide()
        end
    end

    -- Recipe list
    SkinListContainer(browseOrders.RecipeList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
end

---------------------------------------------------------------------------
-- SKIN MY ORDERS PAGE
---------------------------------------------------------------------------

local function SkinMyOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local myOrders = frame.MyOrdersPage
    if not myOrders then return end

    -- Order list
    SkinListContainer(myOrders.OrderList, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Refresh button
    if myOrders.RefreshButton then
        StyleButton(myOrders.RefreshButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
end

---------------------------------------------------------------------------
-- SKIN FORM PAGE
---------------------------------------------------------------------------

local function SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame then return end

    local form = frame.Form
    if not form then return end

    -- Left panel background
    if form.LeftPanelBackground then
        if form.LeftPanelBackground.NineSlice then form.LeftPanelBackground.NineSlice:Hide() end
        if form.LeftPanelBackground.Background then form.LeftPanelBackground.Background:SetAlpha(0) end
        SkinBase.CreateBackdrop(form.LeftPanelBackground, sr, sg, sb, sa * 0.3, math.min(bgr + 0.02, 1), math.min(bgg + 0.02, 1), math.min(bgb + 0.02, 1), 0.5)
    end

    -- Right panel background
    if form.RightPanelBackground then
        if form.RightPanelBackground.NineSlice then form.RightPanelBackground.NineSlice:Hide() end
        if form.RightPanelBackground.Background then form.RightPanelBackground.Background:SetAlpha(0) end
        SkinBase.CreateBackdrop(form.RightPanelBackground, sr, sg, sb, sa * 0.3, math.min(bgr + 0.02, 1), math.min(bgg + 0.02, 1), math.min(bgb + 0.02, 1), 0.5)
    end

    -- Back button
    if form.BackButton then
        StyleButton(form.BackButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- List order button
    if form.PaymentContainer then
        local pc = form.PaymentContainer
        if pc.ListOrderButton then
            StyleButton(pc.ListOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if pc.CancelOrderButton then
            StyleButton(pc.CancelOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Duration dropdown
        if pc.DurationDropdown then
            SkinBase.StripTextures(pc.DurationDropdown)
            SkinBase.CreateBackdrop(pc.DurationDropdown, sr, sg, sb, sa, math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
        end
        -- Note edit box border
        if pc.NoteEditBox and pc.NoteEditBox.Border then
            pc.NoteEditBox.Border:SetAlpha(0)
            SkinBase.CreateBackdrop(pc.NoteEditBox, sr, sg, sb, sa * 0.5, bgr, bgg, bgb, 0.8)
        end
    end

    -- Dropdowns on the form
    if form.MinimumQuality and form.MinimumQuality.Dropdown then
        SkinBase.StripTextures(form.MinimumQuality.Dropdown)
        SkinBase.CreateBackdrop(form.MinimumQuality.Dropdown, sr, sg, sb, sa, math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
    end
    if form.OrderRecipientDropdown then
        SkinBase.StripTextures(form.OrderRecipientDropdown)
        SkinBase.CreateBackdrop(form.OrderRecipientDropdown, sr, sg, sb, sa, math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
    end

    -- Recipient target edit box
    if form.OrderRecipientTarget then
        StyleEditBox(form.OrderRecipientTarget, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Current listings side panel
    if form.CurrentListings then
        local listings = form.CurrentListings
        if listings.NineSlice then listings.NineSlice:Hide() end
        SkinBase.StripTextures(listings)
        SkinBase.CreateBackdrop(listings, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        if listings.OrderList then
            SkinListContainer(listings.OrderList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if listings.CloseButton then
            StyleButton(listings.CloseButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end
end

---------------------------------------------------------------------------
-- MAIN ENTRY POINT
---------------------------------------------------------------------------

local function SkinCraftingOrders()
    if not IsEnabled() then return end

    local frame = _G.ProfessionsCustomerOrdersFrame
    if not frame or SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HideDecorations(frame)
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    StyleCloseButton(frame.CloseButton or _G.ProfessionsCustomerOrdersFrameCloseButton)

    SkinTabs(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinBrowseOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinMyOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.MarkSkinned(frame)
end

---------------------------------------------------------------------------
-- REFRESH COLORS (for live theme changes)
---------------------------------------------------------------------------

local function UpdateButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = button and SkinBase.GetBackdrop(button)
    if not bd then return end
    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    bd:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
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

local function RefreshCraftingOrdersColors()
    local frame = _G.ProfessionsCustomerOrdersFrame
    if not frame or not SkinBase.IsSkinned(frame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Main backdrop
    local mainBd = SkinBase.GetBackdrop(frame)
    if mainBd then
        mainBd:SetBackdropColor(bgr, bgg, bgb, bga)
        mainBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Tabs
    local tabs = { frame.BrowseTab, frame.OrdersTab }
    for _, tab in ipairs(tabs) do
        local bd = tab and SkinBase.GetBackdrop(tab)
        if bd then
            bd:SetBackdropColor(bgr, bgg, bgb, 0.9)
            bd:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end
    UpdateTabSelectedState(frame)

    -- Browse page
    local browseOrders = frame.BrowseOrders
    if browseOrders then
        local searchBar = browseOrders.SearchBar
        if searchBar then
            UpdateEditBoxColors(searchBar.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(searchBar.SearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(searchBar.FavoritesSearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateDropdownColors(searchBar.FilterDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- My orders page
    local myOrders = frame.MyOrdersPage
    if myOrders then
        UpdateButtonColors(myOrders.RefreshButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Form
    local form = frame.Form
    if form then
        UpdateButtonColors(form.BackButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdatePanelColors(form.LeftPanelBackground, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdatePanelColors(form.RightPanelBackground, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateDropdownColors(form.OrderRecipientDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateEditBoxColors(form.OrderRecipientTarget, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if form.MinimumQuality and form.MinimumQuality.Dropdown then
            UpdateDropdownColors(form.MinimumQuality.Dropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if form.PaymentContainer then
            local pc = form.PaymentContainer
            UpdateButtonColors(pc.ListOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(pc.CancelOrderButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateDropdownColors(pc.DurationDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            local noteBd = pc.NoteEditBox and SkinBase.GetBackdrop(pc.NoteEditBox)
            if noteBd then
                noteBd:SetBackdropColor(bgr, bgg, bgb, 0.8)
                noteBd:SetBackdropBorderColor(sr, sg, sb, sa * 0.5)
            end
        end
        -- Current listings
        if form.CurrentListings then
            local listingsBd = SkinBase.GetBackdrop(form.CurrentListings)
            if listingsBd then
                listingsBd:SetBackdropColor(bgr, bgg, bgb, bga)
                listingsBd:SetBackdropBorderColor(sr, sg, sb, sa)
            end
            UpdateButtonColors(form.CurrentListings.CloseButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end
end

-- Expose refresh function globally
_G.QUI_RefreshCraftingOrdersColors = RefreshCraftingOrdersColors

if ns.Registry then
    ns.Registry:Register("skinCraftingOrders", {
        refresh = _G.QUI_RefreshCraftingOrdersColors,
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
    if event == "ADDON_LOADED" and addon == "Blizzard_ProfessionsCustomerOrders" then
        C_Timer.After(0.1, SkinCraftingOrders)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

if C_AddOns.IsAddOnLoaded("Blizzard_ProfessionsCustomerOrders") then
    C_Timer.After(0.1, SkinCraftingOrders)
    initFrame:UnregisterEvent("ADDON_LOADED")
end
