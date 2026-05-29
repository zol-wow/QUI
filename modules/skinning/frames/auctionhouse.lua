local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- AUCTION HOUSE SKINNING
---------------------------------------------------------------------------

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

    SkinBase.HidePortraitFrameChrome(AuctionHouseFrame)

    -- MoneyFrame inset (AH-specific — not part of PortraitFrameTemplate)
    if AuctionHouseFrame.MoneyFrameInset then
        AuctionHouseFrame.MoneyFrameInset:Hide()
        if AuctionHouseFrame.MoneyFrameInset.NineSlice then AuctionHouseFrame.MoneyFrameInset.NineSlice:Hide() end
    end
    if AuctionHouseFrame.MoneyFrameBorder then AuctionHouseFrame.MoneyFrameBorder:Hide() end

    -- Hide the full Inset frame (helper already covered its NineSlice/Bg)
    if AuctionHouseFrame.Inset then AuctionHouseFrame.Inset:Hide() end

    -- Strip remaining textures
    SkinBase.StripTextures(AuctionHouseFrame)
end

-- Skin bottom tabs (Buy, Sell, Auctions)
local function SkinAuctionHouseTabs()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not AuctionHouseFrame.Tabs then return end

    SkinBase.SkinTabGroup(AuctionHouseFrame.Tabs, AuctionHouseFrame, { font = true })

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
end

-- Skin search bar elements
local function SkinSearchBar()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- Search box
    local searchBar = AuctionHouseFrame.SearchBar
    if searchBar then
        -- Search input box
        if searchBar.SearchBox then
            SkinBase.SkinEditBox(searchBar.SearchBox, { font = true })
        end
        -- Filter button (WowStyle1 dropdown — standard button textures don't apply)
        if searchBar.FilterButton then
            SkinBase.SkinButton(searchBar.FilterButton, { strip = true, font = true })
            -- Keep the QUI backdrop BELOW the dropdown's children so the
            -- clear-filters "X" (ClearFiltersButton, over the top-right corner)
            -- renders on top. Lowering our own backdrop is stable; raising the X
            -- is not — the dropdown/menu machinery re-levels its child buttons on
            -- show/interaction (Blizzard_Menu MenuTemplates: "Machinery is
            -- broken"), so a one-time level bump on the X gets undone on the
            -- first click. Mirrors the proven professions.lua belowChildren path.
            local filterBd = SkinBase.GetBackdrop(searchBar.FilterButton)
            if filterBd then
                filterBd:SetFrameLevel(math.max(0, searchBar.FilterButton:GetFrameLevel() - 1))
            end
        end
        -- Search button
        if searchBar.SearchButton then
            SkinBase.SkinButton(searchBar.SearchButton, { font = true })
        end
        -- Favorites search button (star) — raise frame level so it isn't
        -- obscured by the SearchBox EditBox, which captures mouse across its
        -- full rect and can swallow clicks on the overlapping star.
        if searchBar.FavoritesSearchButton then
            SkinBase.SkinButton(searchBar.FavoritesSearchButton)
            searchBar.FavoritesSearchButton:SetFrameLevel(searchBar.FavoritesSearchButton:GetFrameLevel() + 5)
        end
    end
end

-- Safely iterate a ScrollBox's visible frames (nil-safe for uninitialized ScrollBoxes)
local function SafeForEachFrame(scrollBox, callback)
    if scrollBox and scrollBox.ForEachFrame then
        pcall(scrollBox.ForEachFrame, scrollBox, callback)
    end
end

-- Style each pooled ScrollBox row as it's acquired (shared by all lists).
local function skinRow(row)
    SkinBase.SkinScrollRow(row)
end

-- Skin browse panel (item list / commodities list)
local function SkinBrowsePanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- Browse results frame
    local browseResults = AuctionHouseFrame.BrowseResultsFrame
    if browseResults then
        -- Strip inset decorations
        SkinBase.StripTextures(browseResults)
        -- Item list ScrollBox
        if browseResults.ItemList then
            SkinBase.SkinListContainer(browseResults.ItemList, skinRow)
        end
    end

    -- Commodities buy frame
    local commoditiesBuy = AuctionHouseFrame.CommoditiesBuyFrame
    if commoditiesBuy then
        SkinBase.StripTextures(commoditiesBuy)
        if commoditiesBuy.ItemList then
            SkinBase.SkinListContainer(commoditiesBuy.ItemList, skinRow)
        end
        -- Buy button
        if commoditiesBuy.BuyDisplay then
            if commoditiesBuy.BuyDisplay.BuyButton then
                SkinBase.SkinButton(commoditiesBuy.BuyDisplay.BuyButton, { font = true })
            end
            -- Quantity input
            if commoditiesBuy.BuyDisplay.QuantityInput and commoditiesBuy.BuyDisplay.QuantityInput.InputBox then
                SkinBase.SkinEditBox(commoditiesBuy.BuyDisplay.QuantityInput.InputBox)
            end
        end
    end

    -- Item buy frame (single item auctions)
    local itemBuy = AuctionHouseFrame.ItemBuyFrame
    if itemBuy then
        SkinBase.StripTextures(itemBuy)
        if itemBuy.ItemList then
            SkinBase.SkinListContainer(itemBuy.ItemList, skinRow)
        end
        -- Buyout / Bid buttons
        if itemBuy.BuyoutFrame then
            if itemBuy.BuyoutFrame.BuyoutButton then
                SkinBase.SkinButton(itemBuy.BuyoutFrame.BuyoutButton, { font = true })
            end
        end
        if itemBuy.BidFrame then
            if itemBuy.BidFrame.BidButton then
                SkinBase.SkinButton(itemBuy.BidFrame.BidButton, { font = true })
            end
        end
    end
end

-- Skin sell panel
local function SkinSellPanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- Commodities sell frame
    local commoditiesSell = AuctionHouseFrame.CommoditiesSellFrame
    if commoditiesSell then
        SkinBase.StripTextures(commoditiesSell)
        -- Price input
        if commoditiesSell.PriceInput and commoditiesSell.PriceInput.MoneyInputFrame then
            local moneyInput = commoditiesSell.PriceInput.MoneyInputFrame
            if moneyInput.GoldBox then SkinBase.SkinEditBox(moneyInput.GoldBox) end
            if moneyInput.SilverBox then SkinBase.SkinEditBox(moneyInput.SilverBox) end
            if moneyInput.CopperBox then SkinBase.SkinEditBox(moneyInput.CopperBox) end
        end
        -- Quantity input
        if commoditiesSell.QuantityInput and commoditiesSell.QuantityInput.InputBox then
            SkinBase.SkinEditBox(commoditiesSell.QuantityInput.InputBox)
        end
        -- Duration dropdown
        if commoditiesSell.DurationDropdown then
            SkinBase.SkinDropdown(commoditiesSell.DurationDropdown)
        end
        -- Post button
        if commoditiesSell.PostButton then
            SkinBase.SkinButton(commoditiesSell.PostButton, { font = true })
        end
    end

    -- Item sell frame (single items)
    local itemSell = AuctionHouseFrame.ItemSellFrame
    if itemSell then
        SkinBase.StripTextures(itemSell)
        -- Price input
        if itemSell.PriceInput and itemSell.PriceInput.MoneyInputFrame then
            local moneyInput = itemSell.PriceInput.MoneyInputFrame
            if moneyInput.GoldBox then SkinBase.SkinEditBox(moneyInput.GoldBox) end
            if moneyInput.SilverBox then SkinBase.SkinEditBox(moneyInput.SilverBox) end
            if moneyInput.CopperBox then SkinBase.SkinEditBox(moneyInput.CopperBox) end
        end
        -- Quantity input
        if itemSell.QuantityInput and itemSell.QuantityInput.InputBox then
            SkinBase.SkinEditBox(itemSell.QuantityInput.InputBox)
        end
        -- Duration dropdown
        if itemSell.DurationDropdown then
            SkinBase.SkinDropdown(itemSell.DurationDropdown)
        end
        -- Post button
        if itemSell.PostButton then
            SkinBase.SkinButton(itemSell.PostButton, { font = true })
        end
        -- Secondary price input (bid vs buyout)
        if itemSell.SecondaryPriceInput and itemSell.SecondaryPriceInput.MoneyInputFrame then
            local moneyInput = itemSell.SecondaryPriceInput.MoneyInputFrame
            if moneyInput.GoldBox then SkinBase.SkinEditBox(moneyInput.GoldBox) end
            if moneyInput.SilverBox then SkinBase.SkinEditBox(moneyInput.SilverBox) end
            if moneyInput.CopperBox then SkinBase.SkinEditBox(moneyInput.CopperBox) end
        end
    end
end

-- Skin auctions panel (summary and all-auctions lists)
local function SkinAuctionsPanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local auctionsFrame = AuctionHouseFrame.AuctionsFrame
    if not auctionsFrame then return end

    SkinBase.StripTextures(auctionsFrame)

    -- Summary list
    if auctionsFrame.SummaryList then
        SkinBase.SkinListContainer(auctionsFrame.SummaryList, skinRow)
    end

    -- All auctions list
    if auctionsFrame.AllAuctionsList then
        SkinBase.SkinListContainer(auctionsFrame.AllAuctionsList, skinRow)
    end

    -- Commodities auctions list
    if auctionsFrame.CommoditiesList then
        SkinBase.SkinListContainer(auctionsFrame.CommoditiesList, skinRow)
    end

    -- Cancel auctions button
    if auctionsFrame.CancelAuctionButton then
        SkinBase.SkinButton(auctionsFrame.CancelAuctionButton, { font = true })
    end

    -- Bid frame button (if present)
    if auctionsFrame.BidFrame and auctionsFrame.BidFrame.BidButton then
        SkinBase.SkinButton(auctionsFrame.BidFrame.BidButton, { font = true })
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

    -- Per-button styler (used both on acquisition and by OnFilterClicked refresh).
    local function StyleCategoryRow(button)
        StyleCategoryButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        SuppressCategoryTextures(button)
        UpdateCategorySelected(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        -- Reapply the QUI font: Blizzard's element initializer calls
        -- SetNormalFontObject on every rebind, reverting the label font.
        SkinBase.SkinFontString(button.Text)
    end
    local function RefreshCategoryButtons(self)
        SafeForEachFrame(self, StyleCategoryRow)
    end

    local scrollBox = categoriesList.ScrollBox
    SkinBase.HookScrollBoxAcquired(scrollBox, StyleCategoryRow)

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
    SkinBase.SkinCloseButton(AuctionHouseFrame.CloseButton or _G.AuctionHouseFrameCloseButton)

    -- Style tabs
    SkinAuctionHouseTabs()

    -- Skin sub-panels (pcall each so one failure doesn't block the rest)
    pcall(SkinCategoriesList, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    pcall(SkinSearchBar)
    pcall(SkinBrowsePanel)
    pcall(SkinSellPanel)
    pcall(SkinAuctionsPanel)

    SkinBase.MarkSkinned(AuctionHouseFrame)
end

---------------------------------------------------------------------------
-- REFRESH COLORS (for live theme changes)
---------------------------------------------------------------------------

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
        SkinBase.RefreshTabGroup(AuctionHouseFrame.Tabs, AuctionHouseFrame)
    end

    -- Search bar
    local searchBar = AuctionHouseFrame.SearchBar
    if searchBar then
        SkinBase.RefreshWidget(searchBar.SearchBox)
        SkinBase.RefreshWidget(searchBar.FilterButton)
        SkinBase.RefreshWidget(searchBar.SearchButton)
        SkinBase.RefreshWidget(searchBar.FavoritesSearchButton)
    end

    -- Commodities buy
    local commoditiesBuy = AuctionHouseFrame.CommoditiesBuyFrame
    if commoditiesBuy and commoditiesBuy.BuyDisplay then
        SkinBase.RefreshWidget(commoditiesBuy.BuyDisplay.BuyButton)
        if commoditiesBuy.BuyDisplay.QuantityInput and commoditiesBuy.BuyDisplay.QuantityInput.InputBox then
            SkinBase.RefreshWidget(commoditiesBuy.BuyDisplay.QuantityInput.InputBox)
        end
    end

    -- Item buy
    local itemBuy = AuctionHouseFrame.ItemBuyFrame
    if itemBuy then
        if itemBuy.BuyoutFrame and itemBuy.BuyoutFrame.BuyoutButton then
            SkinBase.RefreshWidget(itemBuy.BuyoutFrame.BuyoutButton)
        end
        if itemBuy.BidFrame and itemBuy.BidFrame.BidButton then
            SkinBase.RefreshWidget(itemBuy.BidFrame.BidButton)
        end
    end

    -- Commodities sell
    local commoditiesSell = AuctionHouseFrame.CommoditiesSellFrame
    if commoditiesSell then
        SkinBase.RefreshWidget(commoditiesSell.PostButton)
        SkinBase.RefreshWidget(commoditiesSell.DurationDropdown)
        if commoditiesSell.PriceInput and commoditiesSell.PriceInput.MoneyInputFrame then
            local mi = commoditiesSell.PriceInput.MoneyInputFrame
            SkinBase.RefreshWidget(mi.GoldBox)
            SkinBase.RefreshWidget(mi.SilverBox)
            SkinBase.RefreshWidget(mi.CopperBox)
        end
        if commoditiesSell.QuantityInput and commoditiesSell.QuantityInput.InputBox then
            SkinBase.RefreshWidget(commoditiesSell.QuantityInput.InputBox)
        end
    end

    -- Item sell
    local itemSell = AuctionHouseFrame.ItemSellFrame
    if itemSell then
        SkinBase.RefreshWidget(itemSell.PostButton)
        SkinBase.RefreshWidget(itemSell.DurationDropdown)
        if itemSell.PriceInput and itemSell.PriceInput.MoneyInputFrame then
            local mi = itemSell.PriceInput.MoneyInputFrame
            SkinBase.RefreshWidget(mi.GoldBox)
            SkinBase.RefreshWidget(mi.SilverBox)
            SkinBase.RefreshWidget(mi.CopperBox)
        end
        if itemSell.SecondaryPriceInput and itemSell.SecondaryPriceInput.MoneyInputFrame then
            local mi = itemSell.SecondaryPriceInput.MoneyInputFrame
            SkinBase.RefreshWidget(mi.GoldBox)
            SkinBase.RefreshWidget(mi.SilverBox)
            SkinBase.RefreshWidget(mi.CopperBox)
        end
        if itemSell.QuantityInput and itemSell.QuantityInput.InputBox then
            SkinBase.RefreshWidget(itemSell.QuantityInput.InputBox)
        end
    end

    -- Auctions panel
    local auctionsFrame = AuctionHouseFrame.AuctionsFrame
    if auctionsFrame then
        SkinBase.RefreshWidget(auctionsFrame.CancelAuctionButton)
        if auctionsFrame.BidFrame and auctionsFrame.BidFrame.BidButton then
            SkinBase.RefreshWidget(auctionsFrame.BidFrame.BidButton)
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
