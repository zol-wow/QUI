local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase
local AH_CATEGORY_TEXT_COLOR = { 0.72, 0.78, 0.85, 1 }
local AH_CATEGORY_SELECTED_TEXT_COLOR = { 1, 1, 1, 1 }

local function IsEnabled()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.skinAuctionHouse
end

local function HideAuctionHouseDecorations()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    SkinBase.HidePortraitFrameChrome(AuctionHouseFrame)

    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    local hideGold = settings and settings.showAuctionHouseGold == false
    if hideGold then
        if AuctionHouseFrame.MoneyFrameInset then
            AuctionHouseFrame.MoneyFrameInset:Hide()
            if AuctionHouseFrame.MoneyFrameInset.NineSlice then AuctionHouseFrame.MoneyFrameInset.NineSlice:Hide() end
        end
        if AuctionHouseFrame.MoneyFrameBorder then AuctionHouseFrame.MoneyFrameBorder:Hide() end
    else
        if AuctionHouseFrame.MoneyFrameInset then AuctionHouseFrame.MoneyFrameInset:Show() end
        if AuctionHouseFrame.MoneyFrameBorder then AuctionHouseFrame.MoneyFrameBorder:Show() end
    end

    if AuctionHouseFrame.Inset then AuctionHouseFrame.Inset:Hide() end

    SkinBase.StripTextures(AuctionHouseFrame)
end

local function SkinAuctionHouseTabs()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not AuctionHouseFrame.Tabs then return end

    SkinBase.SkinTabGroup(AuctionHouseFrame.Tabs, AuctionHouseFrame, { font = true, resizeToText = true })

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

local function FontAuctionHouseExtraTabs()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    if not (AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown()) then return end
    if not AuctionHouseFrame.GetChildren then return end
    local children = { AuctionHouseFrame:GetChildren() }
    for i = 1, #children do
        local obj = children[i]
        if not (issecretvalue and issecretvalue(obj)) -- @secret-policy: reject-secret-value (hierarchy-secret child is never a skinnable tab)
            and type(obj) == "table" and not SkinBase.IsStyled(obj)
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
    SkinBase.SkinTabGroup(tabs, auctionsFrame, { font = true, resizeToText = true })
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

local function SkinSearchBar()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local searchBar = AuctionHouseFrame.SearchBar
    if searchBar then
        if searchBar.SearchBox then
            SkinBase.SkinEditBox(searchBar.SearchBox, { font = true })
        end
        if searchBar.FilterButton then
            SkinBase.SkinDropdown(searchBar.FilterButton, { belowChildren = true })
        end
        if searchBar.SearchButton then
            SkinBase.SkinButton(searchBar.SearchButton, { font = true })
        end
        if searchBar.FavoritesSearchButton then
            SkinBase.SkinButton(searchBar.FavoritesSearchButton, { font = true })
            searchBar.FavoritesSearchButton:SetFrameLevel(searchBar.FavoritesSearchButton:GetFrameLevel() + 5)
        end
    end
end

local function skinRow(row)
    SkinBase.SkinScrollRow(row)
    SkinBase.LockPooledRowText(row, 4)
end

local function HookAuctionHeaderSkin()
    local mixin = _G.AuctionHouseTableHeaderStringMixin
    if not mixin or mixin.Init == nil or SkinBase.GetFrameData(mixin, "headerSkinHooked") then return end
    hooksecurefunc(mixin, "Init", function(self)
        if not IsEnabled() then return end
        if self.Left then self.Left:SetAlpha(0) end
        if self.Middle then self.Middle:SetAlpha(0) end
        if self.Right then self.Right:SetAlpha(0) end
        local hl = self.GetHighlightTexture and self:GetHighlightTexture()
        if hl then hl:SetAlpha(0) end
        SkinBase.ApplyButtonFontObjects(self)
    end)
    SkinBase.SetFrameData(mixin, "headerSkinHooked", true)
end

local function SkinBrowsePanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local browseResults = AuctionHouseFrame.BrowseResultsFrame
    if browseResults then
        SkinBase.StripTextures(browseResults)
        if browseResults.ItemList then
            SkinBase.SkinListContainer(browseResults.ItemList, skinRow)
        end
    end

    local commoditiesBuy = AuctionHouseFrame.CommoditiesBuyFrame
    if commoditiesBuy then
        SkinBase.StripTextures(commoditiesBuy)
        if commoditiesBuy.ItemList then
            SkinBase.SkinListContainer(commoditiesBuy.ItemList, skinRow)
        end
        if commoditiesBuy.BuyDisplay then
            if commoditiesBuy.BuyDisplay.BuyButton then
                SkinBase.SkinButton(commoditiesBuy.BuyDisplay.BuyButton, { font = true })
            end
            if commoditiesBuy.BuyDisplay.QuantityInput and commoditiesBuy.BuyDisplay.QuantityInput.InputBox then
                SkinBase.SkinEditBox(commoditiesBuy.BuyDisplay.QuantityInput.InputBox)
            end
        end
    end

    local itemBuy = AuctionHouseFrame.ItemBuyFrame
    if itemBuy then
        SkinBase.StripTextures(itemBuy)
        if itemBuy.ItemList then
            SkinBase.SkinListContainer(itemBuy.ItemList, skinRow)
        end
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

local function SkinSellPanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local commoditiesSell = AuctionHouseFrame.CommoditiesSellFrame
    if commoditiesSell then
        SkinBase.StripTextures(commoditiesSell)
        if commoditiesSell.PriceInput and commoditiesSell.PriceInput.MoneyInputFrame then
            local moneyInput = commoditiesSell.PriceInput.MoneyInputFrame
            if moneyInput.GoldBox then SkinBase.SkinEditBox(moneyInput.GoldBox) end
            if moneyInput.SilverBox then SkinBase.SkinEditBox(moneyInput.SilverBox) end
            if moneyInput.CopperBox then SkinBase.SkinEditBox(moneyInput.CopperBox) end
        end
        SkinQuantityInputFrame(commoditiesSell.QuantityInput)
        if commoditiesSell.DurationDropdown then
            SkinBase.SkinDropdown(commoditiesSell.DurationDropdown)
            LockDurationDropdownText(commoditiesSell.DurationDropdown)
        end
        if commoditiesSell.PostButton then
            SkinBase.SkinButton(commoditiesSell.PostButton, { font = true })
        end
    end

    local itemSell = AuctionHouseFrame.ItemSellFrame
    if itemSell then
        SkinBase.StripTextures(itemSell)
        if itemSell.PriceInput and itemSell.PriceInput.MoneyInputFrame then
            local moneyInput = itemSell.PriceInput.MoneyInputFrame
            if moneyInput.GoldBox then SkinBase.SkinEditBox(moneyInput.GoldBox) end
            if moneyInput.SilverBox then SkinBase.SkinEditBox(moneyInput.SilverBox) end
            if moneyInput.CopperBox then SkinBase.SkinEditBox(moneyInput.CopperBox) end
        end
        SkinQuantityInputFrame(itemSell.QuantityInput)
        if itemSell.DurationDropdown then
            SkinBase.SkinDropdown(itemSell.DurationDropdown)
            LockDurationDropdownText(itemSell.DurationDropdown)
        end
        if itemSell.PostButton then
            SkinBase.SkinButton(itemSell.PostButton, { font = true })
        end
        if itemSell.SecondaryPriceInput and itemSell.SecondaryPriceInput.MoneyInputFrame then
            local moneyInput = itemSell.SecondaryPriceInput.MoneyInputFrame
            if moneyInput.GoldBox then SkinBase.SkinEditBox(moneyInput.GoldBox) end
            if moneyInput.SilverBox then SkinBase.SkinEditBox(moneyInput.SilverBox) end
            if moneyInput.CopperBox then SkinBase.SkinEditBox(moneyInput.CopperBox) end
        end
    end
end

local function SkinAuctionsPanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local auctionsFrame = AuctionHouseFrame.AuctionsFrame
    if not auctionsFrame then return end

    SkinBase.StripTextures(auctionsFrame)
    SkinAuctionHouseAuctionsTabs(auctionsFrame)

    if auctionsFrame.SummaryList then
        SkinBase.SkinListContainer(auctionsFrame.SummaryList, skinRow)
    end

    if auctionsFrame.AllAuctionsList then
        SkinBase.SkinListContainer(auctionsFrame.AllAuctionsList, skinRow)
    end

    if auctionsFrame.CommoditiesList then
        SkinBase.SkinListContainer(auctionsFrame.CommoditiesList, skinRow)
    end

    if auctionsFrame.ItemList then
        SkinBase.SkinListContainer(auctionsFrame.ItemList, skinRow)
    end

    if auctionsFrame.CancelAuctionButton then
        SkinBase.SkinButton(auctionsFrame.CancelAuctionButton, { font = true })
    end

    if auctionsFrame.BidFrame and auctionsFrame.BidFrame.BidButton then
        SkinBase.SkinButton(auctionsFrame.BidFrame.BidButton, { font = true })
    end
end

local function SuppressCategoryTextures(button)
    if not button then return end
    SkinBase.StripTextures(button)
    if button.SelectedTexture then button.SelectedTexture:SetAlpha(0) end
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
end

local function SkinCategoriesList()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local categoriesList = AuctionHouseFrame.CategoriesList
    if not categoriesList then return end

    SkinBase.StripTextures(categoriesList)
    if categoriesList.NineSlice then categoriesList.NineSlice:Hide() end

    -- Idle rows use the muted AH colour; the selected row must read as
    -- selected (white), not be overwritten back to idle after every rebind.
    -- Blizzard's AuctionHouseFilterButton_SetUp resets the normal font
    -- object on each rebind, so the font FACE is reapplied (colour-free) and
    -- RefreshCategorySelected owns the state colour.
    local function StyleCategoryRow(button)
        SkinBase.SkinCategoryButton(button, {
            textColor = AH_CATEGORY_TEXT_COLOR,
            selectedTextColor = AH_CATEGORY_SELECTED_TEXT_COLOR,
        })
        SuppressCategoryTextures(button)
        SkinBase.ApplyButtonFontObjects(button)
        SkinBase.RefreshCategorySelected(button)
    end
    local function RefreshCategoryButtons(self)
        SkinBase.ForEachScrollBoxFrame(self, StyleCategoryRow)
    end

    local scrollBox = categoriesList.ScrollBox
    SkinBase.HookScrollBoxAcquired(scrollBox, StyleCategoryRow)

    if type(_G.AuctionHouseFilterButton_SetUp) == "function"
        and not SkinBase.GetFrameData(categoriesList, "setupHooked") then
        hooksecurefunc("AuctionHouseFilterButton_SetUp", function(button)
            if not IsEnabled() or not button then return end
            StyleCategoryRow(button)
        end)
        SkinBase.SetFrameData(categoriesList, "setupHooked", true)
    end

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

    if categoriesList.ScrollBar then
        SkinBase.SkinTrimScrollBar(categoriesList.ScrollBar)
    end
end

local function SkinAuctionHouse()
    if not IsEnabled() then return end

    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or SkinBase.IsSkinned(AuctionHouseFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    HideAuctionHouseDecorations()

    SkinBase.CreateBackdrop(AuctionHouseFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.SkinCloseButton(AuctionHouseFrame.CloseButton or _G.AuctionHouseFrameCloseButton)

    SkinAuctionHouseTabs()
    FontAuctionHouseExtraTabs()
    AuctionHouseFrame:HookScript("OnShow", function()
        C_Timer.After(0, FontAuctionHouseExtraTabs)
    end)
    HookAuctionHeaderSkin()

    ns.SafeCall("best-effort-style", SkinCategoriesList)
    ns.SafeCall("best-effort-style", SkinSearchBar)
    ns.SafeCall("best-effort-style", SkinBrowsePanel)
    ns.SafeCall("best-effort-style", SkinSellPanel)
    ns.SafeCall("best-effort-style", SkinAuctionsPanel)

    LockAuctionHouseTokenText()
    LockAuctionHouseBuyDialogText()

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

local function RefreshAuctionHouseColors()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not SkinBase.IsSkinned(AuctionHouseFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    local mainBd = SkinBase.GetBackdrop(AuctionHouseFrame)
    if mainBd then
        SkinBase.SetBackdropColors(mainBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    if AuctionHouseFrame.Tabs then
        SkinBase.RefreshTabGroup(AuctionHouseFrame.Tabs, AuctionHouseFrame)
    end
    if AuctionHouseFrame.AuctionsFrame then
        local tabs = { AuctionHouseFrame.AuctionsFrame.AuctionsTab, AuctionHouseFrame.AuctionsFrame.BidsTab }
        SkinBase.RefreshTabGroup(tabs, AuctionHouseFrame.AuctionsFrame)
    end

    local searchBar = AuctionHouseFrame.SearchBar
    if searchBar then
        SkinBase.RefreshWidget(searchBar.SearchBox)
        SkinBase.RefreshWidget(searchBar.FilterButton)
        SkinBase.RefreshWidget(searchBar.SearchButton)
        SkinBase.RefreshWidget(searchBar.FavoritesSearchButton)
    end

    local commoditiesBuy = AuctionHouseFrame.CommoditiesBuyFrame
    if commoditiesBuy and commoditiesBuy.BuyDisplay then
        SkinBase.RefreshWidget(commoditiesBuy.BuyDisplay.BuyButton)
        if commoditiesBuy.BuyDisplay.QuantityInput and commoditiesBuy.BuyDisplay.QuantityInput.InputBox then
            SkinBase.RefreshWidget(commoditiesBuy.BuyDisplay.QuantityInput.InputBox)
        end
    end

    local itemBuy = AuctionHouseFrame.ItemBuyFrame
    if itemBuy then
        if itemBuy.BuyoutFrame and itemBuy.BuyoutFrame.BuyoutButton then
            SkinBase.RefreshWidget(itemBuy.BuyoutFrame.BuyoutButton)
        end
        if itemBuy.BidFrame and itemBuy.BidFrame.BidButton then
            SkinBase.RefreshWidget(itemBuy.BidFrame.BidButton)
        end
    end

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

_G.QUI_RefreshAuctionHouseColors = RefreshAuctionHouseColors

if ns.Registry then
    ns.Registry:Register("skinAuctionHouse", {
        refresh = _G.QUI_RefreshAuctionHouseColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_AuctionHouseUI", SkinAuctionHouse, 0)
