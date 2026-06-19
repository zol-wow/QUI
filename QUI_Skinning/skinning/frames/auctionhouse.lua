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

    -- Lock each main tab's font objects: tab selection/hover re-asserts the stock
    -- font object, reverting the QUI face (the auctions sub-tabs already do this).
    for _, tab in ipairs(AuctionHouseFrame.Tabs) do
        SkinBase.LockFrameTextObjects(tab, 2)
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
end

local function SkinAuctionHouseAuctionsTabs(auctionsFrame)
    if not auctionsFrame then return end
    local tabs = { auctionsFrame.AuctionsTab, auctionsFrame.BidsTab }
    SkinBase.SkinTabGroup(tabs, auctionsFrame, { font = true })
    for _, tab in ipairs(tabs) do
        SkinBase.LockFrameTextObjects(tab, 2)
    end
end

local function LockDurationDropdownText(dropdown)
    if not dropdown then return end
    local text = dropdown.Text or (dropdown.GetFontString and dropdown:GetFontString())
    if text then
        SkinBase.SkinFontString(text, { fontOnly = true })
        SkinBase.LockFontObject(text, { fontOnly = true })
    end
    SkinBase.LockFrameTextObjects(dropdown, 2)
end

local function LockTokenFrameText(frame)
    if not frame then return end
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 4)

    for _, key in ipairs({ "BuyoutPrice", "MarketPrice" }) do
        local fontString = frame[key]
        if fontString then
            SkinBase.SkinFontString(fontString, { fontOnly = true })
            SkinBase.LockFontObject(fontString, { fontOnly = true })
        end
    end
end

local function LockAuctionHouseTokenText()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    LockTokenFrameText(AuctionHouseFrame.WoWTokenResults)
    LockTokenFrameText(AuctionHouseFrame.WoWTokenSellFrame)

    local tutorial = AuctionHouseFrame.WoWTokenResults and AuctionHouseFrame.WoWTokenResults.GameTimeTutorial
    if tutorial then
        LockTokenFrameText(tutorial)
        LockTokenFrameText(tutorial.LeftDisplay)
        LockTokenFrameText(tutorial.RightDisplay)
    end
end

local function LockAuctionHouseBuyDialogText()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    local notification = AuctionHouseFrame and AuctionHouseFrame.BuyDialog and AuctionHouseFrame.BuyDialog.Notification
    if not notification then return end

    SkinBase.SkinFrameText(notification, { recurse = true })
    SkinBase.LockFrameTextObjects(notification, 2)
    if notification.Text then
        SkinBase.SkinFontString(notification.Text, { fontOnly = true })
        SkinBase.LockFontObject(notification.Text, { fontOnly = true })
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
            SkinBase.SkinButton(searchBar.FavoritesSearchButton, { font = true })
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
    SkinBase.SkinFrameText(row, { recurse = true })
    -- AH result rows are TableBuilder-backed: each cell re-applies its font
    -- OBJECT (Number*/Price* font objects) on every populate / scroll-recycle,
    -- reverting the one-shot SkinFrameText face above. Lock so the QUI face
    -- re-applies on each swap (fontOnly keeps the quality/price text colors).
    SkinBase.LockFrameTextObjects(row, 4)
end

-- TableBuilder sortable column headers (AuctionHouseTableHeaderStringMixin) are
-- pooled and re-Init'd on every table relayout (Reset->ConstructHeader->Init), so
-- SkinListContainer's row hook never reaches them and the one-shot SkinFrameText is
-- reverted each relayout. One mixin hook covers every list sharing the template.
local function HookAuctionHeaderSkin()
    local mixin = _G.AuctionHouseTableHeaderStringMixin
    if not mixin or mixin.Init == nil or mixin.__quiHeaderSkinHooked then return end
    hooksecurefunc(mixin, "Init", function(self)
        if not IsEnabled() then return end
        -- Suppress the inherited ColumnDisplayButtonShort slice art (keep the sort Arrow)
        if self.Left then self.Left:SetAlpha(0) end
        if self.Middle then self.Middle:SetAlpha(0) end
        if self.Right then self.Right:SetAlpha(0) end
        local hl = self.GetHighlightTexture and self:GetHighlightTexture()
        if hl then hl:SetAlpha(0) end
        SkinBase.ApplyButtonFontObjects(self)
    end)
    mixin.__quiHeaderSkinHooked = true
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
            LockDurationDropdownText(commoditiesSell.DurationDropdown)
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
            LockDurationDropdownText(itemSell.DurationDropdown)
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
    SkinAuctionHouseAuctionsTabs(auctionsFrame)

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

    -- Single-item buy list (same AuctionHouseItemListTemplate: pooled rows + headers)
    if auctionsFrame.ItemList then
        SkinBase.SkinListContainer(auctionsFrame.ItemList, skinRow)
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

-- Skin the left-side categories list
local function SkinCategoriesList()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local categoriesList = AuctionHouseFrame.CategoriesList
    if not categoriesList then return end

    -- Strip decorations from the categories list container
    SkinBase.StripTextures(categoriesList)
    if categoriesList.NineSlice then categoriesList.NineSlice:Hide() end

    -- Per-button styler (used both on acquisition and by OnFilterClicked refresh).
    local function StyleCategoryRow(button)
        SkinBase.SkinCategoryButton(button)
        SuppressCategoryTextures(button)
        SkinBase.RefreshCategorySelected(button)
        -- Reapply the QUI font: Blizzard's element initializer calls
        -- SetNormalFontObject on every rebind, reverting the label font.
        SkinBase.SkinFontString(button.Text)
        SkinBase.LockFrameTextObjects(button, 2)
        -- SetUp's SetNormalFontObject REPLACES the font object SkinCategoryButton
        -- drove once (the once-guard won't re-drive). Re-drive on every bind so the
        -- normal + hover/disable font objects stay on the QUI face.
        SkinBase.ApplyButtonFontObjects(button)
    end
    local function RefreshCategoryButtons(self)
        SafeForEachFrame(self, StyleCategoryRow)
    end

    local scrollBox = categoriesList.ScrollBox
    SkinBase.HookScrollBoxAcquired(scrollBox, StyleCategoryRow)

    -- Texture flash on load/expand: the shared element initializer
    -- AuctionHouseFilterButton_SetUp re-asserts the Blizzard nav-button atlas and
    -- normalTexture:SetAlpha(1.0) on EVERY bind (load, expand/collapse,
    -- scroll-recycle), and those rebinds DON'T re-fire the acquired-frame
    -- callback for already-visible buttons. Hook the initializer (once) so the
    -- texture suppression + selected-state backdrop re-run right after Blizzard,
    -- in the same layout pass — mirrors the LockFrameTextObjects font fix above.
    if type(_G.AuctionHouseFilterButton_SetUp) == "function"
        and not SkinBase.GetFrameData(categoriesList, "setupHooked") then
        hooksecurefunc("AuctionHouseFilterButton_SetUp", function(button)
            if not IsEnabled() or not button then return end
            -- Full re-skin after Blizzard's SetUp: re-suppress textures, re-drive
            -- font objects, re-assert selected backdrop (same layout pass = no flash).
            StyleCategoryRow(button)
        end)
        SkinBase.SetFrameData(categoriesList, "setupHooked", true)
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
    SkinBase.SkinCloseButton(AuctionHouseFrame.CloseButton or _G.AuctionHouseFrameCloseButton)

    -- Style tabs
    SkinAuctionHouseTabs()
    HookAuctionHeaderSkin()

    -- Skin sub-panels (pcall each so one failure doesn't block the rest)
    pcall(SkinCategoriesList)
    pcall(SkinSearchBar)
    pcall(SkinBrowsePanel)
    pcall(SkinSellPanel)
    pcall(SkinAuctionsPanel)

    SkinBase.SkinFrameText(AuctionHouseFrame, { recurse = true })
    LockAuctionHouseTokenText()
    LockAuctionHouseBuyDialogText()
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
    if AuctionHouseFrame.AuctionsFrame then
        local tabs = { AuctionHouseFrame.AuctionsFrame.AuctionsTab, AuctionHouseFrame.AuctionsFrame.BidsTab }
        SkinBase.RefreshTabGroup(tabs, AuctionHouseFrame.AuctionsFrame)
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
        LockDurationDropdownText(commoditiesSell.DurationDropdown)
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
        LockDurationDropdownText(itemSell.DurationDropdown)
    end

    -- Auctions panel
    local auctionsFrame = AuctionHouseFrame.AuctionsFrame
    if auctionsFrame then
        SkinBase.RefreshWidget(auctionsFrame.CancelAuctionButton)
        if auctionsFrame.BidFrame and auctionsFrame.BidFrame.BidButton then
            SkinBase.RefreshWidget(auctionsFrame.BidFrame.BidButton)
        end
    end

    LockAuctionHouseTokenText()
    LockAuctionHouseBuyDialogText()
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
