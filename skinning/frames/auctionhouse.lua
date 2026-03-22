local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- AUCTION HOUSE SKINNING
---------------------------------------------------------------------------

-- Style a button (same pattern as instanceframes)
local function StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)

    -- Hide default textures
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

    -- Store colors for hover
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

-- Style a WowStyle1 dropdown button (different texture structure than standard buttons)
local function StyleDropdownButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    SkinBase.StripTextures(button)

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)

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

    -- Hide default textures
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

    -- Create backdrop
    SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)
    local tabBackdrop = SkinBase.GetBackdrop(tab)
    tabBackdrop:ClearAllPoints()
    tabBackdrop:SetPoint("TOPLEFT", 3, -3)
    tabBackdrop:SetPoint("BOTTOMRIGHT", -3, 0)

    -- Store colors for selected-state updates
    SkinBase.SetFrameData(tab, "skinColor", { sr, sg, sb, sa })
    SkinBase.SetFrameData(tab, "bgColor", { bgr, bgg, bgb })

    SkinBase.MarkStyled(tab)
end

-- Update bottom tab backdrops to reflect selected state
local function UpdateTabSelectedState()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not AuctionHouseFrame.Tabs then return end
    local selectedTab = AuctionHouseFrame.selectedTab or (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(AuctionHouseFrame))
    for i, tab in ipairs(AuctionHouseFrame.Tabs) do
        local bd = SkinBase.GetBackdrop(tab)
        local sc = SkinBase.GetFrameData(tab, "skinColor")
        local bg = SkinBase.GetFrameData(tab, "bgColor")
        if bd and sc and bg then
            local isSelected = (selectedTab == i)
            if isSelected then
                -- Selected: full border + brighter background
                bd:SetBackdropBorderColor(sc[1], sc[2], sc[3], sc[4])
                bd:SetBackdropColor(math.min(bg[1] + 0.10, 1), math.min(bg[2] + 0.10, 1), math.min(bg[3] + 0.10, 1), 1)
            else
                -- Inactive: dimmed border + normal background
                bd:SetBackdropBorderColor(sc[1] * 0.5, sc[2] * 0.5, sc[3] * 0.5, sc[4] * 0.6)
                bd:SetBackdropColor(bg[1], bg[2], bg[3], 0.7)
            end
        end
    end
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
    return settings and settings.skinAuctionHouse
end

-- Hide all Blizzard decorations on AuctionHouseFrame
local function HideAuctionHouseDecorations()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- PortraitFrameTemplate elements
    if AuctionHouseFrame.NineSlice then AuctionHouseFrame.NineSlice:Hide() end
    if AuctionHouseFrame.Bg then AuctionHouseFrame.Bg:Hide() end
    if AuctionHouseFrame.Background then AuctionHouseFrame.Background:Hide() end

    -- Portrait container
    if AuctionHouseFrame.PortraitContainer then AuctionHouseFrame.PortraitContainer:Hide() end

    -- Title bar background
    if AuctionHouseFrame.TitleContainer then
        if AuctionHouseFrame.TitleContainer.TitleBg then AuctionHouseFrame.TitleContainer.TitleBg:Hide() end
    end

    -- MoneyFrame inset
    if AuctionHouseFrame.MoneyFrameInset then
        AuctionHouseFrame.MoneyFrameInset:Hide()
        if AuctionHouseFrame.MoneyFrameInset.NineSlice then AuctionHouseFrame.MoneyFrameInset.NineSlice:Hide() end
    end

    -- MoneyFrameBorder
    if AuctionHouseFrame.MoneyFrameBorder then AuctionHouseFrame.MoneyFrameBorder:Hide() end

    -- Tab panel insets (top area)
    if AuctionHouseFrame.Inset then
        AuctionHouseFrame.Inset:Hide()
        if AuctionHouseFrame.Inset.NineSlice then AuctionHouseFrame.Inset.NineSlice:Hide() end
    end

    -- Strip remaining textures
    SkinBase.StripTextures(AuctionHouseFrame)
end

-- Skin bottom tabs (Buy, Sell, Auctions)
local function SkinAuctionHouseTabs(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not AuctionHouseFrame.Tabs then return end

    -- AH tabs are in AuctionHouseFrame.Tabs (BuyTab, SellTab, AuctionsTab)
    for _, tab in ipairs(AuctionHouseFrame.Tabs) do
        StyleTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Reposition tabs: left justify and tighten spacing
    local tabs = AuctionHouseFrame.Tabs
    if tabs[1] then
        tabs[1]:ClearAllPoints()
        tabs[1]:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", -3, -30)
    end
    for i = 2, #tabs do
        if tabs[i] and tabs[i - 1] then
            tabs[i]:ClearAllPoints()
            tabs[i]:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", -5, 0)
        end
    end

    -- Hook tab selection to update selected state visuals
    hooksecurefunc("PanelTemplates_SetTab", function(frame)
        if frame == AuctionHouseFrame then
            C_Timer.After(0, UpdateTabSelectedState)
        end
    end)

    -- Apply initial selected state
    UpdateTabSelectedState()
end

-- Skin search bar elements
local function SkinSearchBar(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- Search box
    local searchBar = AuctionHouseFrame.SearchBar
    if searchBar then
        -- Search input box
        if searchBar.SearchBox then
            StyleEditBox(searchBar.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Filter button (WowStyle1 dropdown — standard button textures don't apply)
        if searchBar.FilterButton then
            StyleDropdownButton(searchBar.FilterButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Search button
        if searchBar.SearchButton then
            StyleButton(searchBar.SearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Favorites search button (star) — raise frame level so it isn't
        -- obscured by the SearchBox EditBox, which captures mouse across its
        -- full rect and can swallow clicks on the overlapping star.
        if searchBar.FavoritesSearchButton then
            StyleButton(searchBar.FavoritesSearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            searchBar.FavoritesSearchButton:SetFrameLevel(searchBar.FavoritesSearchButton:GetFrameLevel() + 5)
        end
    end
end

-- Style a ScrollBox row entry (used for browse results and auctions lists)
local function StyleScrollBoxRow(row, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not row or SkinBase.IsStyled(row) then return end

    -- Hide default textures
    SkinBase.StripTextures(row)

    -- Create a subtle backdrop for the row
    local rowBgR = math.min(bgr + 0.03, 1)
    local rowBgG = math.min(bgg + 0.03, 1)
    local rowBgB = math.min(bgb + 0.03, 1)
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * 0.5, rowBgR, rowBgG, rowBgB, 0.6)

    -- Store colors for hover
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

-- Safely iterate a ScrollBox's visible frames (nil-safe for uninitialized ScrollBoxes)
local function SafeForEachFrame(scrollBox, callback)
    if scrollBox and scrollBox.ForEachFrame then
        pcall(scrollBox.ForEachFrame, scrollBox, callback)
    end
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

    -- Style existing rows (deferred — ScrollBox may not be fully initialized yet)
    C_Timer.After(0, function()
        SafeForEachFrame(scrollBox, function(row)
            StyleScrollBoxRow(row, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end)
    end)

    SkinBase.SetFrameData(scrollBox, "hooked", true)
end

-- Skin browse panel (item list / commodities list)
local function SkinBrowsePanel(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- Browse results frame
    local browseResults = AuctionHouseFrame.BrowseResultsFrame
    if browseResults then
        -- Strip inset decorations
        SkinBase.StripTextures(browseResults)
        -- Item list ScrollBox
        if browseResults.ItemList then
            if browseResults.ItemList.NineSlice then browseResults.ItemList.NineSlice:Hide() end
            SkinBase.StripTextures(browseResults.ItemList)
            if browseResults.ItemList.ScrollBox then
                HookScrollBox(browseResults.ItemList.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
            -- Hide scroll bar background
            if browseResults.ItemList.ScrollBar and browseResults.ItemList.ScrollBar.Background then
                browseResults.ItemList.ScrollBar.Background:Hide()
            end
        end
    end

    -- Commodities buy frame
    local commoditiesBuy = AuctionHouseFrame.CommoditiesBuyFrame
    if commoditiesBuy then
        SkinBase.StripTextures(commoditiesBuy)
        if commoditiesBuy.ItemList then
            if commoditiesBuy.ItemList.NineSlice then commoditiesBuy.ItemList.NineSlice:Hide() end
            SkinBase.StripTextures(commoditiesBuy.ItemList)
            if commoditiesBuy.ItemList.ScrollBox then
                HookScrollBox(commoditiesBuy.ItemList.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
            if commoditiesBuy.ItemList.ScrollBar and commoditiesBuy.ItemList.ScrollBar.Background then
                commoditiesBuy.ItemList.ScrollBar.Background:Hide()
            end
        end
        -- Buy button
        if commoditiesBuy.BuyDisplay then
            if commoditiesBuy.BuyDisplay.BuyButton then
                StyleButton(commoditiesBuy.BuyDisplay.BuyButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
            -- Quantity input
            if commoditiesBuy.BuyDisplay.QuantityInput and commoditiesBuy.BuyDisplay.QuantityInput.InputBox then
                StyleEditBox(commoditiesBuy.BuyDisplay.QuantityInput.InputBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
    end

    -- Item buy frame (single item auctions)
    local itemBuy = AuctionHouseFrame.ItemBuyFrame
    if itemBuy then
        SkinBase.StripTextures(itemBuy)
        if itemBuy.ItemList then
            if itemBuy.ItemList.NineSlice then itemBuy.ItemList.NineSlice:Hide() end
            SkinBase.StripTextures(itemBuy.ItemList)
            if itemBuy.ItemList.ScrollBox then
                HookScrollBox(itemBuy.ItemList.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
            if itemBuy.ItemList.ScrollBar and itemBuy.ItemList.ScrollBar.Background then
                itemBuy.ItemList.ScrollBar.Background:Hide()
            end
        end
        -- Buyout / Bid buttons
        if itemBuy.BuyoutFrame then
            if itemBuy.BuyoutFrame.BuyoutButton then
                StyleButton(itemBuy.BuyoutFrame.BuyoutButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
        if itemBuy.BidFrame then
            if itemBuy.BidFrame.BidButton then
                StyleButton(itemBuy.BidFrame.BidButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
    end
end

-- Skin sell panel
local function SkinSellPanel(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- Commodities sell frame
    local commoditiesSell = AuctionHouseFrame.CommoditiesSellFrame
    if commoditiesSell then
        SkinBase.StripTextures(commoditiesSell)
        -- Price input
        if commoditiesSell.PriceInput and commoditiesSell.PriceInput.MoneyInputFrame then
            local moneyInput = commoditiesSell.PriceInput.MoneyInputFrame
            if moneyInput.GoldBox then StyleEditBox(moneyInput.GoldBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
            if moneyInput.SilverBox then StyleEditBox(moneyInput.SilverBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
            if moneyInput.CopperBox then StyleEditBox(moneyInput.CopperBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
        end
        -- Quantity input
        if commoditiesSell.QuantityInput and commoditiesSell.QuantityInput.InputBox then
            StyleEditBox(commoditiesSell.QuantityInput.InputBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Duration dropdown
        if commoditiesSell.DurationDropdown then
            SkinBase.StripTextures(commoditiesSell.DurationDropdown)
            SkinBase.CreateBackdrop(commoditiesSell.DurationDropdown, sr, sg, sb, sa, math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
        end
        -- Post button
        if commoditiesSell.PostButton then
            StyleButton(commoditiesSell.PostButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Item sell frame (single items)
    local itemSell = AuctionHouseFrame.ItemSellFrame
    if itemSell then
        SkinBase.StripTextures(itemSell)
        -- Price input
        if itemSell.PriceInput and itemSell.PriceInput.MoneyInputFrame then
            local moneyInput = itemSell.PriceInput.MoneyInputFrame
            if moneyInput.GoldBox then StyleEditBox(moneyInput.GoldBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
            if moneyInput.SilverBox then StyleEditBox(moneyInput.SilverBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
            if moneyInput.CopperBox then StyleEditBox(moneyInput.CopperBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
        end
        -- Quantity input
        if itemSell.QuantityInput and itemSell.QuantityInput.InputBox then
            StyleEditBox(itemSell.QuantityInput.InputBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Duration dropdown
        if itemSell.DurationDropdown then
            SkinBase.StripTextures(itemSell.DurationDropdown)
            SkinBase.CreateBackdrop(itemSell.DurationDropdown, sr, sg, sb, sa, math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
        end
        -- Post button
        if itemSell.PostButton then
            StyleButton(itemSell.PostButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Secondary price input (bid vs buyout)
        if itemSell.SecondaryPriceInput and itemSell.SecondaryPriceInput.MoneyInputFrame then
            local moneyInput = itemSell.SecondaryPriceInput.MoneyInputFrame
            if moneyInput.GoldBox then StyleEditBox(moneyInput.GoldBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
            if moneyInput.SilverBox then StyleEditBox(moneyInput.SilverBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
            if moneyInput.CopperBox then StyleEditBox(moneyInput.CopperBox, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
        end
    end
end

-- Skin auctions panel (summary and all-auctions lists)
local function SkinAuctionsPanel(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local auctionsFrame = AuctionHouseFrame.AuctionsFrame
    if not auctionsFrame then return end

    SkinBase.StripTextures(auctionsFrame)

    -- Summary list
    if auctionsFrame.SummaryList then
        if auctionsFrame.SummaryList.NineSlice then auctionsFrame.SummaryList.NineSlice:Hide() end
        SkinBase.StripTextures(auctionsFrame.SummaryList)
        if auctionsFrame.SummaryList.ScrollBox then
            HookScrollBox(auctionsFrame.SummaryList.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if auctionsFrame.SummaryList.ScrollBar and auctionsFrame.SummaryList.ScrollBar.Background then
            auctionsFrame.SummaryList.ScrollBar.Background:Hide()
        end
    end

    -- All auctions list
    if auctionsFrame.AllAuctionsList then
        if auctionsFrame.AllAuctionsList.NineSlice then auctionsFrame.AllAuctionsList.NineSlice:Hide() end
        SkinBase.StripTextures(auctionsFrame.AllAuctionsList)
        if auctionsFrame.AllAuctionsList.ScrollBox then
            HookScrollBox(auctionsFrame.AllAuctionsList.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if auctionsFrame.AllAuctionsList.ScrollBar and auctionsFrame.AllAuctionsList.ScrollBar.Background then
            auctionsFrame.AllAuctionsList.ScrollBar.Background:Hide()
        end
    end

    -- Commodities auctions list
    if auctionsFrame.CommoditiesList then
        if auctionsFrame.CommoditiesList.NineSlice then auctionsFrame.CommoditiesList.NineSlice:Hide() end
        SkinBase.StripTextures(auctionsFrame.CommoditiesList)
        if auctionsFrame.CommoditiesList.ScrollBox then
            HookScrollBox(auctionsFrame.CommoditiesList.ScrollBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if auctionsFrame.CommoditiesList.ScrollBar and auctionsFrame.CommoditiesList.ScrollBar.Background then
            auctionsFrame.CommoditiesList.ScrollBar.Background:Hide()
        end
    end

    -- Cancel auctions button
    if auctionsFrame.CancelAuctionButton then
        StyleButton(auctionsFrame.CancelAuctionButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Bid frame button (if present)
    if auctionsFrame.BidFrame and auctionsFrame.BidFrame.BidButton then
        StyleButton(auctionsFrame.BidFrame.BidButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
end

-- Update a category button's backdrop to reflect selected state
local function UpdateCategorySelected(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = SkinBase.GetBackdrop(button)
    if not bd then return end
    local isSelected = button.SelectedTexture and button.SelectedTexture:IsShown()
    if isSelected then
        -- Selected: full border + brighter background
        bd:SetBackdropBorderColor(sr, sg, sb, sa)
        bd:SetBackdropColor(math.min(bgr + 0.10, 1), math.min(bgg + 0.10, 1), math.min(bgb + 0.10, 1), 0.9)
    else
        -- Deselected: subtle border + normal background
        bd:SetBackdropBorderColor(sr, sg, sb, sa * 0.5)
        bd:SetBackdropColor(math.min(bgr + 0.05, 1), math.min(bgg + 0.05, 1), math.min(bgb + 0.05, 1), 0.7)
    end
end

-- Suppress a category button's default textures (safe to call on every refresh;
-- the ScrollBox element initializer can restore alphas when recycling buttons)
local function SuppressCategoryTextures(button)
    if not button then return end
    SkinBase.StripTextures(button)
    if button.SelectedTexture then button.SelectedTexture:SetAlpha(0) end
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
end

-- Style a category list button (left side navigation)
local function StyleCategoryButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    -- Hide default textures but keep SelectedTexture for state detection (hidden visually)
    SuppressCategoryTextures(button)

    -- Create subtle backdrop
    SkinBase.CreateBackdrop(button, sr, sg, sb, sa * 0.5, math.min(bgr + 0.05, 1), math.min(bgg + 0.05, 1), math.min(bgb + 0.05, 1), 0.7)

    -- Apply initial selected state
    UpdateCategorySelected(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Store colors for hover
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

-- Skin the left-side categories list
local function SkinCategoriesList(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local categoriesList = AuctionHouseFrame.CategoriesList
    if not categoriesList then return end

    -- Strip decorations from the categories list container
    SkinBase.StripTextures(categoriesList)
    if categoriesList.NineSlice then categoriesList.NineSlice:Hide() end

    -- Helper to style + update selected state on all visible category buttons
    local function RefreshCategoryButtons(self)
        SafeForEachFrame(self, function(button)
            StyleCategoryButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            SuppressCategoryTextures(button)
            UpdateCategorySelected(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end)
    end

    -- Hook the ScrollBox to style category buttons as they're recycled
    local scrollBox = categoriesList.ScrollBox
    if scrollBox and not SkinBase.GetFrameData(scrollBox, "hooked") then
        -- TAINT SAFETY: Defer to break taint chain from Update context.
        hooksecurefunc(scrollBox, "Update", function(self)
            C_Timer.After(0, function()
                RefreshCategoryButtons(self)
            end)
        end)

        -- Style existing buttons (deferred — ScrollBox may not be fully initialized yet)
        C_Timer.After(0, function()
            RefreshCategoryButtons(scrollBox)
        end)

        SkinBase.SetFrameData(scrollBox, "hooked", true)
    end

    -- Hook category click to refresh selected states across all visible buttons
    if categoriesList.OnFilterClicked and not SkinBase.GetFrameData(categoriesList, "clickHooked") then
        hooksecurefunc(categoriesList, "OnFilterClicked", function()
            C_Timer.After(0, function()
                if scrollBox then
                    RefreshCategoryButtons(scrollBox)
                end
            end)
        end)
        SkinBase.SetFrameData(categoriesList, "clickHooked", true)
    end

    -- Hide scroll bar background
    if categoriesList.ScrollBar and categoriesList.ScrollBar.Background then
        categoriesList.ScrollBar.Background:Hide()
    end
end

-- Main entry point
local function SkinAuctionHouse()
    if not IsEnabled() then return end

    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or SkinBase.IsSkinned(AuctionHouseFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Hide all Blizzard decorations
    HideAuctionHouseDecorations()

    -- Create main backdrop
    SkinBase.CreateBackdrop(AuctionHouseFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Style close button
    local closeButton = AuctionHouseFrame.CloseButton or _G.AuctionHouseFrameCloseButton
    StyleCloseButton(closeButton)

    -- Style tabs
    SkinAuctionHouseTabs(sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Skin sub-panels (pcall each so one failure doesn't block the rest)
    pcall(SkinCategoriesList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    pcall(SkinSearchBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    pcall(SkinBrowsePanel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    pcall(SkinSellPanel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    pcall(SkinAuctionsPanel, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.MarkSkinned(AuctionHouseFrame)
end

---------------------------------------------------------------------------
-- REFRESH COLORS (for live theme changes)
---------------------------------------------------------------------------

-- Helper to update a styled button's colors
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

-- Helper to update a tab's colors
local function UpdateTabColors(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = tab and SkinBase.GetBackdrop(tab)
    if not bd then return end
    bd:SetBackdropColor(bgr, bgg, bgb, 0.9)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Helper to update an edit box's colors
local function UpdateEditBoxColors(editBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = editBox and SkinBase.GetBackdrop(editBox)
    if not bd then return end
    bd:SetBackdropColor(bgr, bgg, bgb, bga)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Helper to update a dropdown's colors
local function UpdateDropdownColors(dropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = dropdown and SkinBase.GetBackdrop(dropdown)
    if not bd then return end
    bd:SetBackdropColor(math.min(bgr + 0.07, 1), math.min(bgg + 0.07, 1), math.min(bgb + 0.07, 1), 1)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

local function RefreshAuctionHouseColors()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not SkinBase.IsSkinned(AuctionHouseFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Main backdrop
    local mainBd = SkinBase.GetBackdrop(AuctionHouseFrame)
    if mainBd then
        mainBd:SetBackdropColor(bgr, bgg, bgb, bga)
        mainBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Tabs
    if AuctionHouseFrame.Tabs then
        for _, tab in ipairs(AuctionHouseFrame.Tabs) do
            UpdateTabColors(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        UpdateTabSelectedState()
    end

    -- Search bar
    local searchBar = AuctionHouseFrame.SearchBar
    if searchBar then
        UpdateEditBoxColors(searchBar.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(searchBar.FilterButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(searchBar.SearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateButtonColors(searchBar.FavoritesSearchButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Commodities buy
    local commoditiesBuy = AuctionHouseFrame.CommoditiesBuyFrame
    if commoditiesBuy and commoditiesBuy.BuyDisplay then
        UpdateButtonColors(commoditiesBuy.BuyDisplay.BuyButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if commoditiesBuy.BuyDisplay.QuantityInput and commoditiesBuy.BuyDisplay.QuantityInput.InputBox then
            UpdateEditBoxColors(commoditiesBuy.BuyDisplay.QuantityInput.InputBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Item buy
    local itemBuy = AuctionHouseFrame.ItemBuyFrame
    if itemBuy then
        if itemBuy.BuyoutFrame and itemBuy.BuyoutFrame.BuyoutButton then
            UpdateButtonColors(itemBuy.BuyoutFrame.BuyoutButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if itemBuy.BidFrame and itemBuy.BidFrame.BidButton then
            UpdateButtonColors(itemBuy.BidFrame.BidButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Commodities sell
    local commoditiesSell = AuctionHouseFrame.CommoditiesSellFrame
    if commoditiesSell then
        UpdateButtonColors(commoditiesSell.PostButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateDropdownColors(commoditiesSell.DurationDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if commoditiesSell.PriceInput and commoditiesSell.PriceInput.MoneyInputFrame then
            local mi = commoditiesSell.PriceInput.MoneyInputFrame
            UpdateEditBoxColors(mi.GoldBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateEditBoxColors(mi.SilverBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateEditBoxColors(mi.CopperBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if commoditiesSell.QuantityInput and commoditiesSell.QuantityInput.InputBox then
            UpdateEditBoxColors(commoditiesSell.QuantityInput.InputBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Item sell
    local itemSell = AuctionHouseFrame.ItemSellFrame
    if itemSell then
        UpdateButtonColors(itemSell.PostButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        UpdateDropdownColors(itemSell.DurationDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if itemSell.PriceInput and itemSell.PriceInput.MoneyInputFrame then
            local mi = itemSell.PriceInput.MoneyInputFrame
            UpdateEditBoxColors(mi.GoldBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateEditBoxColors(mi.SilverBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateEditBoxColors(mi.CopperBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if itemSell.SecondaryPriceInput and itemSell.SecondaryPriceInput.MoneyInputFrame then
            local mi = itemSell.SecondaryPriceInput.MoneyInputFrame
            UpdateEditBoxColors(mi.GoldBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateEditBoxColors(mi.SilverBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateEditBoxColors(mi.CopperBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if itemSell.QuantityInput and itemSell.QuantityInput.InputBox then
            UpdateEditBoxColors(itemSell.QuantityInput.InputBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Auctions panel
    local auctionsFrame = AuctionHouseFrame.AuctionsFrame
    if auctionsFrame then
        UpdateButtonColors(auctionsFrame.CancelAuctionButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if auctionsFrame.BidFrame and auctionsFrame.BidFrame.BidButton then
            UpdateButtonColors(auctionsFrame.BidFrame.BidButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end
end

-- Expose refresh function globally
_G.QUI_RefreshAuctionHouseColors = RefreshAuctionHouseColors

if ns.Registry then
    ns.Registry:Register("skinAuctionHouse", {
        refresh = _G.QUI_RefreshAuctionHouseColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "Blizzard_AuctionHouseUI" then
        C_Timer.After(0.1, SkinAuctionHouse)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

if C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
    C_Timer.After(0.1, SkinAuctionHouse)
    frame:UnregisterEvent("ADDON_LOADED")
end
