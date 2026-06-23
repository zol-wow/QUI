local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase
local AH_CATEGORY_TEXT_COLOR = { 0.72, 0.78, 0.85, 1 }

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

-- Return true if `frame` (or an ancestor, up to `depth`) is anchored to `target`
-- — or to a direct child of `target`. GetPoint MayReturnNothing and can hand back
-- a secret relativeTo when anchoring is secret, so the whole probe is pcall-wrapped
-- (== on a secret value throws).
local function FrameAnchorsTo(frame, target, depth)
    if not frame or depth < 0 then return false end
    if frame.GetNumPoints then
        local ok, hit = pcall(function()
            for i = 1, frame:GetNumPoints() do
                local _, rel = frame:GetPoint(i)
                if rel == target then return true end
                if rel and rel.GetParent and rel:GetParent() == target then return true end
            end
            return false
        end)
        if ok and hit then return true end
    end
    return FrameAnchorsTo(frame.GetParent and frame:GetParent() or nil, target, depth - 1)
end

-- Apply the QUI font to bottom tabs added by OTHER addons. These are not children
-- of AuctionHouseFrame and never enter AuctionHouseFrame.Tabs — they are separate
-- top-level Buttons (often grouped under an unnamed container) anchored to the AH
-- frame, so the .Tabs sweep and the global font system both miss them. Detect them
-- structurally (a shown Button with a fontstring whose own/ancestor anchor targets
-- AuctionHouseFrame) and drive their font objects. Font-only: art/position
-- untouched. Per-frame guard keeps the per-open _G walk cheap; the walk only runs
-- while the AH is open.
local function FontAuctionHouseExtraTabs()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    -- Our own + Blizzard tabs (already skinned; keeps the guard flags coherent).
    if AuctionHouseFrame.Tabs then
        for _, tab in ipairs(AuctionHouseFrame.Tabs) do
            if tab and not SkinBase.GetFrameData(tab, "qAHTabFonted") then
                SkinBase.ApplyButtonFontObjects(tab)
                SkinBase.SetFrameData(tab, "qAHTabFonted", true)
            end
        end
    end

    if not (AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown()) then return end
    for _, obj in pairs(_G) do
        if type(obj) == "table" and obj ~= AuctionHouseFrame
            and not SkinBase.GetFrameData(obj, "qAHTabFonted") then
            local ok, isTab = pcall(function()
                return obj.IsObjectType and obj:IsObjectType("Button")
                    and obj.GetFontString and obj:GetFontString()
                    and obj.IsShown and obj:IsShown()
                    and FrameAnchorsTo(obj, AuctionHouseFrame, 2)
            end)
            if ok and isTab then
                SkinBase.ApplyButtonFontObjects(obj)
                SkinBase.SetFrameData(obj, "qAHTabFonted", true)
            end
        end
    end
end

local function SkinAuctionHouseAuctionsTabs(auctionsFrame)
    if not auctionsFrame then return end
    local tabs = { auctionsFrame.AuctionsTab, auctionsFrame.BidsTab }
    SkinBase.SkinTabGroup(tabs, auctionsFrame, { font = true })
end

local function LockDurationDropdownText(dropdown)
    if not dropdown then return end
    local text = dropdown.Text or (dropdown.GetFontString and dropdown:GetFontString())
    if text then
        SkinBase.SkinFontString(text, { fontOnly = true })
        SkinBase.LockFontObject(text, { fontOnly = true })
    end
end

local function LockTokenFrameText(frame)
    if not frame then return end
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
            -- belowChildren keeps the QUI backdrop BELOW the dropdown's children so the
            -- clear-filters "X" (ClearFiltersButton, over the top-right corner) renders on
            -- top. Lowering our own backdrop is stable; raising the X is not — the
            -- dropdown/menu machinery re-levels its child buttons on show/interaction. The
            -- opt does the same SetFrameLevel(max(0, level-1)) as the old manual block.
            -- WowStyle1FilterDropdownTemplate (a DropdownButton) — route through the
            -- canonical SkinDropdown (default strip, like every other QUI dropdown)
            -- so it reads as a dropdown, not a button. belowChildren keeps the QUI
            -- backdrop below the ClearFiltersButton "X" overlay so it stays on top.
            SkinBase.SkinDropdown(searchBar.FilterButton, { belowChildren = true })
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
    -- AH result rows are TableBuilder-backed: each cell re-applies its font
    -- OBJECT (Number*/Price* font objects) on every populate / scroll-recycle.
    -- LockPooledRowText does the guarded recursive pass once, then locks so the
    -- QUI face re-applies on each swap.
    SkinBase.LockPooledRowText(row, 4)
end

-- TableBuilder sortable column headers (AuctionHouseTableHeaderStringMixin) are
-- pooled and re-Init'd on every table relayout (Reset->ConstructHeader->Init), so
-- SkinListContainer's row hook never reaches them and the one-shot SkinFrameText is
-- reverted each relayout. One mixin hook covers every list sharing the template.
local function HookAuctionHeaderSkin()
    local mixin = _G.AuctionHouseTableHeaderStringMixin
    if not mixin or mixin.Init == nil or SkinBase.GetFrameData(mixin, "headerSkinHooked") then return end
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
    SkinBase.SetFrameData(mixin, "headerSkinHooked", true)
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

local function SkinQuantityInputFrame(quantityInput)
    if not quantityInput then return end
    if quantityInput.InputBox then
        SkinBase.SkinEditBox(quantityInput.InputBox)
    end
    if quantityInput.MaxButton then
        SkinBase.SkinButton(quantityInput.MaxButton, { font = true })
    end
end

local function RefreshQuantityInputFrame(quantityInput)
    if not quantityInput then return end
    SkinBase.RefreshWidget(quantityInput.InputBox)
    SkinBase.RefreshWidget(quantityInput.MaxButton)
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
        SkinQuantityInputFrame(commoditiesSell.QuantityInput)
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
        SkinQuantityInputFrame(itemSell.QuantityInput)
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
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end
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
        -- SetUp's SetNormalFontObject REPLACES the font object SkinCategoryButton
        -- drove once (the once-guard won't re-drive). Re-drive on every bind so the
        -- normal + hover/disable font objects stay on the QUI face.
        SkinBase.ApplyButtonFontObjects(button, { color = AH_CATEGORY_TEXT_COLOR })
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

    -- Canonical thin QUI scrollbar (was a bare Background:Hide()).
    if categoriesList.ScrollBar then
        SkinBase.SkinTrimScrollBar(categoriesList.ScrollBar)
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
    -- Re-font on every open so bottom tabs added by other addons still pick up the QUI
    -- font (per-tab guard keeps it cheap). The initial pass below is synchronous; the
    -- OnShow hook defers one frame because other addons create/reshow their tabs in their
    -- own AH OnShow (which may run after ours), so it waits for the frame to settle.
    FontAuctionHouseExtraTabs()
    AuctionHouseFrame:HookScript("OnShow", function()
        C_Timer.After(0, FontAuctionHouseExtraTabs)
    end)
    HookAuctionHeaderSkin()

    -- Skin sub-panels (pcall each so one failure doesn't block the rest)
    pcall(SkinCategoriesList)
    pcall(SkinSearchBar)
    pcall(SkinBrowsePanel)
    pcall(SkinSellPanel)
    pcall(SkinAuctionsPanel)

    LockAuctionHouseTokenText()
    LockAuctionHouseBuyDialogText()

    -- Item-display icons: crop + quality border. Hook the base item-display
    -- mixin's icon setter (self = the ItemDisplay button) so every browse / sell /
    -- auctions item icon is skinned as it is set. Idempotent per mixin + per icon.
    if SkinBase.SkinIcon and _G.AuctionHouseItemDisplayMixin
        and not SkinBase.GetFrameData(_G.AuctionHouseItemDisplayMixin, "qAHIconHooked") then
        hooksecurefunc(_G.AuctionHouseItemDisplayMixin, "SetItemInternal", function(self)
            if self and self.Icon then
                local border = SkinBase.SkinIcon(self.Icon)
                if border and self.IconBorder then
                    SkinBase.HandleIconBorder(self.IconBorder, border)
                end
            end
        end)
        SkinBase.SetFrameData(_G.AuctionHouseItemDisplayMixin, "qAHIconHooked", true)
    end

    SkinBase.MarkSkinned(AuctionHouseFrame)
end

---------------------------------------------------------------------------
-- REFRESH COLORS (for live theme changes)
---------------------------------------------------------------------------

local function RefreshAuctionHouseColors()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not SkinBase.IsSkinned(AuctionHouseFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Main backdrop. Route through SetBackdropColors so the new theme color is
    -- written into the persisted backdrop data; a bare setter would be discarded
    -- by the next scale-refresh rebuild.
    local mainBd = SkinBase.GetBackdrop(AuctionHouseFrame)
    if mainBd then
        SkinBase.SetBackdropColors(mainBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
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
        RefreshQuantityInputFrame(commoditiesSell.QuantityInput)
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
        RefreshQuantityInputFrame(itemSell.QuantityInput)
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

SkinBase.OnAddOnLoaded("Blizzard_AuctionHouseUI", SkinAuctionHouse, 0)
