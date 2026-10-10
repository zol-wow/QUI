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

    SkinBase.SkinTabGroup(AuctionHouseFrame.Tabs, AuctionHouseFrame, { font = true, resizeToText = true, dockBottom = true })
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

local function StyleAuctionBuyDialog(dialog)
    if not dialog or not IsEnabled() or (dialog.IsForbidden and dialog:IsForbidden()) then return end
    if dialog.Border then dialog.Border:SetAlpha(0) end
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(dialog, sr, sg, sb, sa, br, bg, bb, ba, 8)
    SkinBase.GetBackdrop(dialog):SetFrameLevel(math.max(0, dialog:GetFrameLevel() - 1))
    for _, key in ipairs({ "BuyNowButton", "CancelButton", "OkayButton" }) do
        local button = dialog[key]
        if button and not (button.IsForbidden and button:IsForbidden()) then
            SkinBase.SkinButton(button, { font = true, belowChildren = true })
            SkinBase.RefreshWidget(button)
        end
    end
    SkinBase.SkinFrameText(dialog.PriceFrame, { recurse = true })
    for _, text in ipairs({ dialog.ItemDisplay and dialog.ItemDisplay.ItemText, dialog.TimeLeftText }) do
        SkinBase.SkinFontString(text, { fontOnly = true })
        SkinBase.LockFontObject(text, { fontOnly = true })
    end
    LockAuctionHouseBuyDialogText()
    if not SkinBase.GetFrameData(dialog, "qAHBuyDialogHooked") then
        for _, method in ipairs({ "SetState", "SetItemID" }) do
            if type(dialog[method]) == "function" then hooksecurefunc(dialog, method, StyleAuctionBuyDialog) end
        end
        dialog:HookScript("OnShow", StyleAuctionBuyDialog)
        SkinBase.SetFrameData(dialog, "qAHBuyDialogHooked", true)
    end
end

local function StyleMultisellProgress(frame)
    if not IsEnabled() or not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    for _, key in ipairs({ "Fill", "Left", "Middle", "Right" }) do
        SkinBase.ClampTextureHidden(frame[key], true)
    end
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa, br, bg, bb, ba, 8)
    SkinBase.GetBackdrop(frame):SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    local bar = frame.ProgressBar
    if bar and not (bar.IsForbidden and bar:IsForbidden()) then
        for _, key in ipairs({ "Border", "TextBorder", "Background", "DropShadow" }) do
            SkinBase.ClampTextureHidden(bar[key], true)
        end
        ns.Helpers.ApplyBarStyle(bar, "Interface\\Buttons\\WHITE8x8")
        SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
        SkinBase.CreateBackdrop(bar, sr, sg, sb, sa, br, bg, bb, ba, 4)
        SkinBase.SkinFontString(bar.Text, { fontOnly = true })
        SkinBase.LockFontObject(bar.Text, { fontOnly = true })
        if bar.Icon then
            SkinBase.RoundIconTexture(bar, bar.Icon)
            local border = SkinBase.SkinIcon(bar.Icon, { crop = false })
            if border then
                SkinBase.SetFrameData(border, "chromeRadius", 4)
                SkinBase.SetBackdropColors(border, { sr, sg, sb, sa }, nil)
                border:SetShown(bar.Icon:IsShown())
            end
        end
    end
    if frame.CancelButton and not (frame.CancelButton.IsForbidden and frame.CancelButton:IsForbidden()) then
        SkinBase.SkinCloseButton(frame.CancelButton)
    end
    if not SkinBase.GetFrameData(frame, "qAHMultisellHooked") then
        frame:HookScript("OnShow", StyleMultisellProgress)
        for _, method in ipairs({ "Start", "Refresh" }) do
            if type(frame[method]) == "function" then hooksecurefunc(frame, method, StyleMultisellProgress) end
        end
        SkinBase.SetFrameData(frame, "qAHMultisellHooked", true)
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
            SkinBase.SkinDropdown(searchBar.FilterButton, { skinArrow = true, belowChildren = true })
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

local auctionRows = setmetatable({}, { __mode = "k" })

local function skinRow(row)
    if not row or not IsEnabled() or (row.IsForbidden and row:IsForbidden()) then return end
    local icon = row.Icon
    local iconAlpha = icon and icon:GetAlpha()
    local selectedAlpha = row.SelectedHighlight and row.SelectedHighlight:GetAlpha()
    local hoverAlpha = row.HighlightTexture and row.HighlightTexture:GetAlpha()
    SkinBase.SkinScrollRow(row)
    if icon then
        icon:SetAlpha(iconAlpha)
        SkinBase.SkinFontString(row.Text, { color = { 0.9, 0.9, 0.9, 1 } })
        SkinBase.RoundIconTexture(row, icon)
        local border = SkinBase.SkinIcon(icon, { crop = false })
        if border then
            SkinBase.SetFrameData(border, "chromeRadius", 3)
            local sr, sg, sb, sa = SkinBase.GetWindowColors()
            SkinBase.SetBackdropColors(border, { sr, sg, sb, sa }, nil)
            border:SetShown(icon:IsShown())
        end
        if row.IconBorder then SkinBase.ClampTextureHidden(row.IconBorder, true) end
        if not SkinBase.GetFrameData(row, "qAHSummaryHooked") then
            for _, method in ipairs({ "Init", "SetIconShown" }) do
                if type(row[method]) == "function" then hooksecurefunc(row, method, skinRow) end
            end
            SkinBase.SetFrameData(row, "qAHSummaryHooked", true)
        end
    end
    SkinBase.RefreshWidget(row)
    local backdrop = SkinBase.GetBackdrop(row)
    if backdrop then backdrop:SetFrameLevel(math.max(0, row:GetFrameLevel() - 1)) end
    SkinBase.ClampTextureHidden(row.NormalTexture or (row.GetNormalTexture and row:GetNormalTexture()), true)
    local r, g, b = SkinBase.GetSkinColors()
    for _, key in ipairs({ "SelectedHighlight", "HighlightTexture" }) do
        local texture = row[key]
        if texture then
            texture:SetTexture("Interface\\Buttons\\WHITE8x8")
            texture:SetTexCoord(0, 1, 0, 1)
            texture:ClearAllPoints()
            texture:SetAllPoints(row)
            texture:SetVertexColor(r, g, b, key == "SelectedHighlight" and 0.15 or 0.08)
            SkinBase.RoundBarTexture(row, texture)
        end
    end
    if row.SelectedHighlight then row.SelectedHighlight:SetAlpha(selectedAlpha) end
    if row.HighlightTexture then row.HighlightTexture:SetAlpha(hoverAlpha) end
    SkinBase.LockPooledRowText(row, 4)
    auctionRows[row] = true
end

local auctionHeaders = setmetatable({}, { __mode = "k" })

local function StyleAuctionHeader(header)
    if not IsEnabled() or not header or (header.IsForbidden and header:IsForbidden()) then return end
    auctionHeaders[header] = true
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        SkinBase.ClampTextureHidden(header[key], true)
    end
    local highlight = header.GetHighlightTexture and header:GetHighlightTexture()
    SkinBase.ClampTextureHidden(highlight, true)
    SkinBase.ApplyButtonFontObjects(header)
    if type(header.Init) == "function" and not SkinBase.GetFrameData(header, "qAHHeaderInitHooked") then
        hooksecurefunc(header, "Init", StyleAuctionHeader)
        SkinBase.SetFrameData(header, "qAHHeaderInitHooked", true)
    end
end

local function StyleAuctionListHeaders(list)
    local builder = list.tableBuilder
    if builder and type(builder.EnumerateHeaders) == "function" then
        for header in builder:EnumerateHeaders() do StyleAuctionHeader(header) end
    end
end

local function HookAuctionHeaderSkin()
    local mixin = _G.AuctionHouseTableHeaderStringMixin
    if not mixin or type(mixin.Init) ~= "function" or SkinBase.GetFrameData(mixin, "headerSkinHooked") then return end
    hooksecurefunc(mixin, "Init", StyleAuctionHeader)
    SkinBase.SetFrameData(mixin, "headerSkinHooked", true)
end

local function StyleCommodityBuyPanel()
    if not IsEnabled() then return end
    local frame = _G.AuctionHouseFrame
    local panel = frame and frame.CommoditiesBuyFrame
    if not panel or (panel.IsForbidden and panel:IsForbidden()) then return end
    local display = panel.BuyDisplay
    if not display or (display.IsForbidden and display:IsForbidden()) then return end
    if display.Background then SkinBase.ClampTextureHidden(display.Background, true) end
    if display.NineSlice then display.NineSlice:SetAlpha(0) end
    for _, button in pairs({ panel.BackButton, display.BuyButton }) do
        if not (button.IsForbidden and button:IsForbidden()) then
            SkinBase.SkinButton(button, { font = true, belowChildren = true })
            SkinBase.RefreshWidget(button)
            local backdrop = SkinBase.GetBackdrop(button)
            if backdrop then backdrop:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1)) end
        end
    end
    local quantity = display.QuantityInput
    if quantity and not (quantity.IsForbidden and quantity:IsForbidden()) then
        SkinBase.SkinEditBox(quantity.InputBox, { font = true })
        SkinBase.RefreshWidget(quantity.InputBox)
    end
    for _, key in ipairs({ "QuantityInput", "UnitPrice", "TotalPrice" }) do
        local control = display[key]
        if control and not (control.IsForbidden and control:IsForbidden()) then
            for _, labelKey in ipairs({ "Label", "LabelTitle" }) do
                local label = control[labelKey]
                SkinBase.SkinFontString(label, { color = { 0.9, 0.9, 0.9, 1 } })
                SkinBase.LockFontObject(label, { fontOnly = true })
            end
            SkinBase.SkinFontString(control.Subtext, { fontOnly = true })
            SkinBase.SkinFrameText(control.MoneyDisplayFrame, { recurse = true })
        end
    end
    if not SkinBase.GetFrameData(display, "qAHCommodityBuyHooked") then
        for _, method in ipairs({ "SetPrice", "SetItemIDAndPrice" }) do
            if type(display[method]) == "function" then hooksecurefunc(display, method, StyleCommodityBuyPanel) end
        end
        display:HookScript("OnShow", StyleCommodityBuyPanel)
        SkinBase.SetFrameData(display, "qAHCommodityBuyHooked", true)
    end
end

local function StyleAuctionBidControls(panel)
    if not IsEnabled() or not panel or (panel.IsForbidden and panel:IsForbidden()) then return end
    local bid, buyout = panel.BidFrame, panel.BuyoutFrame
    for _, button in pairs({ panel.BackButton, panel.CancelAuctionButton, bid and bid.BidButton, buyout and buyout.BuyoutButton }) do
        if button and not (button.IsForbidden and button:IsForbidden()) then
            SkinBase.SkinButton(button, { font = true, belowChildren = true })
            SkinBase.RefreshWidget(button)
            local backdrop = SkinBase.GetBackdrop(button)
            if backdrop then backdrop:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1)) end
        end
    end
    local money = bid and bid.BidAmount
    if money and not (money.IsForbidden and money:IsForbidden()) then
        for _, key in ipairs({ "gold", "silver", "copper" }) do
            local field = money[key]
            if field and not (field.IsForbidden and field:IsForbidden()) then
                local coin = field.texture
                local coinAlpha = coin and coin:GetAlpha()
                SkinBase.SkinEditBox(field, { font = false })
                if coin then coin:SetAlpha(coinAlpha) end
                SkinBase.SkinFontString(field.label, { fontOnly = true })
                SkinBase.SkinFontString(field, { fontOnly = true })
                SkinBase.LockFontObject(field, { fontOnly = true })
                SkinBase.RefreshWidget(field)
            end
        end
    end
    for _, control in pairs({ bid, buyout }) do
        if control and not (control.IsForbidden and control:IsForbidden())
            and type(control.SetPrice) == "function" and not SkinBase.GetFrameData(control, "qAHItemPriceHooked") then
            hooksecurefunc(control, "SetPrice", function() StyleAuctionBidControls(panel) end)
            SkinBase.SetFrameData(control, "qAHItemPriceHooked", true)
        end
    end
end

local function StyleItemBuyPanel()
    local frame = _G.AuctionHouseFrame
    if not frame then return end
    StyleAuctionBidControls(frame.ItemBuyFrame)
    StyleAuctionBidControls(frame.AuctionsFrame)
end

local function StyleAuctionLabel(label)
    if not label then return end
    SkinBase.SkinFontString(label, { fontOnly = true })
    SkinBase.LockFontObject(label, { fontOnly = true })
    if NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.GetRGB and label.GetTextColor then
        local nr, ng, nb = NORMAL_FONT_COLOR:GetRGB()
        local r, g, b, a = label:GetTextColor()
        if r == nr and g == ng and b == nb then label:SetTextColor(0.9, 0.9, 0.9, a or 1) end
    end
end

local function StyleTokenPanel(panel)
    if not IsEnabled() or not panel or (panel.IsForbidden and panel:IsForbidden()) then return end
    if panel.NineSlice then SkinBase.ClampTextureHidden(panel.NineSlice, true) end
    local scrollbar = panel.DummyScrollBar
    if scrollbar and not (scrollbar.IsForbidden and scrollbar:IsForbidden()) then
        SkinBase.SkinTrimScrollBar(scrollbar)
    end
    local dummy = panel.DummyItemList
    if dummy and not (dummy.IsForbidden and dummy:IsForbidden()) then
        SkinBase.ClampTextureHidden(dummy.Background, true)
        SkinBase.ClampTextureHidden(dummy.NineSlice, true)
        scrollbar = dummy.DummyScrollBar
        if scrollbar and not (scrollbar.IsForbidden and scrollbar:IsForbidden()) then
            SkinBase.SkinTrimScrollBar(scrollbar)
        end
    end
    for _, key in ipairs({ "Background", "CreateAuctionTabLeft", "CreateAuctionTabMiddle", "CreateAuctionTabRight" }) do
        SkinBase.ClampTextureHidden(panel[key], true)
    end
    for _, key in ipairs({ "Buyout", "PostButton", "DummyRefreshButton" }) do
        local button = panel[key]
        if button and not (button.IsForbidden and button:IsForbidden()) then
            SkinBase.SkinButton(button, { font = key ~= "DummyRefreshButton", belowChildren = true })
            SkinBase.RefreshWidget(button)
        end
    end
    for _, key in ipairs({ "BuyoutLabel", "BuyoutPriceLabel", "EstimatedTime", "CreateAuctionLabel", "TimeToSell" }) do
        StyleAuctionLabel(panel[key])
    end
    local tutorial = panel.GameTimeTutorial
    if tutorial and not (tutorial.IsForbidden and tutorial:IsForbidden()) then
        SkinBase.HidePortraitFrameChrome(tutorial)
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(tutorial, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)
        SkinBase.SkinCloseButton(tutorial.CloseButton)
        SkinBase.SkinFrameText(tutorial)
        for _, key in ipairs({ "LeftDisplay", "RightDisplay" }) do
            local display = tutorial[key]
            if display and not (display.IsForbidden and display:IsForbidden()) then
                for _, textKey in ipairs({ "Label", "Tutorial1", "Tutorial2", "Tutorial3" }) do
                    StyleAuctionLabel(display[textKey])
                end
                local store = display.StoreButton
                if store and not (store.IsForbidden and store:IsForbidden()) then
                    SkinBase.SkinButton(store, { font = true, belowChildren = true })
                    SkinBase.RefreshWidget(store)
                end
            end
        end
        if not SkinBase.GetFrameData(tutorial, "qAHTokenTutorialHooked") then
            tutorial:HookScript("OnShow", function() StyleTokenPanel(panel) end)
            SkinBase.SetFrameData(tutorial, "qAHTokenTutorialHooked", true)
        end
    end
    if not SkinBase.GetFrameData(panel, "qAHTokenPanelHooked") then
        panel:HookScript("OnShow", StyleTokenPanel)
        if type(panel.Refresh) == "function" then hooksecurefunc(panel, "Refresh", StyleTokenPanel) end
        SkinBase.SetFrameData(panel, "qAHTokenPanelHooked", true)
    end
end

local function StyleTokenPanels()
    local frame = _G.AuctionHouseFrame
    if frame then
        StyleTokenPanel(frame.WoWTokenResults)
        StyleTokenPanel(frame.WoWTokenSellFrame)
    end
end

local auctionLists = setmetatable({}, { __mode = "k" })

local function StyleAuctionListControls(list)
    if not list or not IsEnabled() or (list.IsForbidden and list:IsForbidden()) then return end
    auctionLists[list] = true
    StyleAuctionListHeaders(list)
    StyleAuctionLabel(list.ResultsText)
    local spinner = list.LoadingSpinner
    if spinner and not (spinner.IsForbidden and spinner:IsForbidden()) then
        StyleAuctionLabel(spinner.SearchingText)
    end
    if not SkinBase.GetFrameData(list, "qAHMessageHooked") then
        SkinBase.SetFrameData(list, "qAHMessageHooked", true)
        for _, method in ipairs({ "SetState", "SetCustomError", "UpdateTableBuilderLayout" }) do
            if type(list[method]) == "function" then
                hooksecurefunc(list, method, function() StyleAuctionListControls(list) end)
            end
        end
    end
    local refresh = list.RefreshFrame
    if not refresh or (refresh.IsForbidden and refresh:IsForbidden()) then return end
    local button = refresh.RefreshButton
    if button and not (button.IsForbidden and button:IsForbidden()) then
        SkinBase.SkinButton(button, { font = false, belowChildren = true })
        SkinBase.RefreshWidget(button)
    end
    if refresh.TotalQuantity then
        SkinBase.SkinFontString(refresh.TotalQuantity, { color = { 0.9, 0.9, 0.9, 1 } })
    end
    if not SkinBase.GetFrameData(refresh, "qAHRefreshHooked") then
        SkinBase.SetFrameData(refresh, "qAHRefreshHooked", true)
        for _, method in ipairs({ "SetQuantity", "Deactivate" }) do
            if type(refresh[method]) == "function" then
                hooksecurefunc(refresh, method, function() StyleAuctionListControls(list) end)
            end
        end
    end
end

local function SkinAuctionList(list)
    SkinBase.SkinListContainer(list, skinRow)
    StyleAuctionListControls(list)
end

local function SkinBrowsePanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local browseResults = AuctionHouseFrame.BrowseResultsFrame
    if browseResults then
        SkinBase.StripTextures(browseResults)
        if browseResults.ItemList then
            SkinAuctionList(browseResults.ItemList)
        end
    end

    local commoditiesBuy = AuctionHouseFrame.CommoditiesBuyFrame
    if commoditiesBuy then
        SkinBase.StripTextures(commoditiesBuy)
        if commoditiesBuy.ItemList then
            SkinAuctionList(commoditiesBuy.ItemList)
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

    StyleCommodityBuyPanel()

    StyleItemBuyPanel()

    local itemBuy = AuctionHouseFrame.ItemBuyFrame
    if itemBuy then
        SkinBase.StripTextures(itemBuy)
        if itemBuy.ItemList then
            SkinAuctionList(itemBuy.ItemList)
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

local function StyleLargeAuctionMoneyField(field)
    if not field or (field.IsForbidden and field:IsForbidden()) then return end
    local icon = field.Icon
    local alpha = icon and icon:GetAlpha()
    SkinBase.SkinEditBox(field, { font = false })
    if icon then icon:SetAlpha(alpha) end
    SkinBase.SkinFontString(field, { fontOnly = true })
    SkinBase.LockFontObject(field, { fontOnly = true })
    SkinBase.SkinFontString(field.Text, { fontOnly = true })
    SkinBase.RefreshWidget(field)
end

local function StyleSellInnerControls(panel)
    if not IsEnabled() or not panel or (panel.IsForbidden and panel:IsForbidden()) then return end
    for _, key in ipairs({ "PriceInput", "SecondaryPriceInput", "QuantityInput", "Duration", "Deposit", "TotalPrice" }) do
        local control = panel[key]
        if control and not (control.IsForbidden and control:IsForbidden()) then
            for _, labelKey in ipairs({ "Label", "LabelTitle", "Subtext", "PerItemPostfix" }) do
                StyleAuctionLabel(control[labelKey])
            end
            SkinBase.SkinFrameText(control.MoneyDisplayFrame, { recurse = true })
        end
    end
    local check = panel.BuyoutModeCheckButton
    if check and not (check.IsForbidden and check:IsForbidden()) then
        SkinBase.SkinCheckBox(check)
        StyleAuctionLabel(check.Text)
        local backdrop = SkinBase.GetBackdrop(check)
        if backdrop then
            local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()
            SkinBase.SetBackdropColors(backdrop, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
        end
        local ar, ag, ab = ns.UIKit.GetAccentColor()
        local checked = check:GetCheckedTexture()
        if checked then checked:SetVertexColor(ar, ag, ab, 1) end
        local disabled = check:GetDisabledCheckedTexture()
        if disabled then disabled:SetVertexColor(ar * 0.5, ag * 0.5, ab * 0.5, 1) end
    end
    local duration = panel.Duration
    local dropdown = duration and duration.Dropdown or panel.DurationDropdown
    if dropdown and not (dropdown.IsForbidden and dropdown:IsForbidden()) then
        SkinBase.SkinDropdown(dropdown, { skinArrow = true, belowChildren = true })
        SkinBase.RefreshWidget(dropdown)
        LockDurationDropdownText(dropdown)
    end
    if not SkinBase.GetFrameData(panel, "qAHSellInnerHooked") then
        panel:HookScript("OnShow", function() StyleSellInnerControls(panel) end)
        for _, method in ipairs({ "UpdatePostState", "UpdateDeposit", "UpdateTotalPrice" }) do
            if type(panel[method]) == "function" then
                hooksecurefunc(panel, method, function() StyleSellInnerControls(panel) end)
            end
        end
        SkinBase.SetFrameData(panel, "qAHSellInnerHooked", true)
    end
end

local function SkinSellPanel()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame then return end

    local commoditiesSell = AuctionHouseFrame.CommoditiesSellFrame
    if commoditiesSell then
        SkinBase.StripTextures(commoditiesSell)
        if commoditiesSell.PriceInput and commoditiesSell.PriceInput.MoneyInputFrame then
            local moneyInput = commoditiesSell.PriceInput.MoneyInputFrame
            if moneyInput.GoldBox then StyleLargeAuctionMoneyField(moneyInput.GoldBox) end
            if moneyInput.SilverBox then StyleLargeAuctionMoneyField(moneyInput.SilverBox) end
            if moneyInput.CopperBox then StyleLargeAuctionMoneyField(moneyInput.CopperBox) end
        end
        StyleSellInnerControls(commoditiesSell)
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
            if moneyInput.GoldBox then StyleLargeAuctionMoneyField(moneyInput.GoldBox) end
            if moneyInput.SilverBox then StyleLargeAuctionMoneyField(moneyInput.SilverBox) end
            if moneyInput.CopperBox then StyleLargeAuctionMoneyField(moneyInput.CopperBox) end
        end
        StyleSellInnerControls(itemSell)
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
            if moneyInput.GoldBox then StyleLargeAuctionMoneyField(moneyInput.GoldBox) end
            if moneyInput.SilverBox then StyleLargeAuctionMoneyField(moneyInput.SilverBox) end
            if moneyInput.CopperBox then StyleLargeAuctionMoneyField(moneyInput.CopperBox) end
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
        SkinAuctionList(auctionsFrame.SummaryList)
    end

    if auctionsFrame.BidsList then
        SkinAuctionList(auctionsFrame.BidsList)
    end

    if auctionsFrame.AllAuctionsList then
        SkinAuctionList(auctionsFrame.AllAuctionsList)
    end

    if auctionsFrame.CommoditiesList then
        SkinAuctionList(auctionsFrame.CommoditiesList)
    end

    if auctionsFrame.ItemList then
        SkinAuctionList(auctionsFrame.ItemList)
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
        if not IsEnabled() or not button or (button.IsForbidden and button:IsForbidden()) then return end
        local lines = button.Lines
        local linesAlpha = lines and lines:GetAlpha()
        SkinBase.SkinCategoryButton(button, {
            textColor = AH_CATEGORY_TEXT_COLOR,
            selectedTextColor = AH_CATEGORY_SELECTED_TEXT_COLOR,
        })
        SuppressCategoryTextures(button)
        if lines and linesAlpha then lines:SetAlpha(linesAlpha) end
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

local auctionItemDisplays = setmetatable({}, { __mode = "k" })

local function StyleAuctionItemDisplay(display)
    if not display or not IsEnabled() or (display.IsForbidden and display:IsForbidden()) then return end
    local item = display.ItemButton or display
    if item.IsForbidden and item:IsForbidden() then return end
    local icon = item.Icon or item.icon
    if not icon then return end
    auctionItemDisplays[display] = true
    if not SkinBase.GetFrameData(display, "qAHItemInstanceHooked") then
        for _, method in ipairs({ "SetItemInternal", "Reset" }) do
            if type(display[method]) == "function" then hooksecurefunc(display, method, StyleAuctionItemDisplay) end
        end
        SkinBase.SetFrameData(display, "qAHItemInstanceHooked", true)
    end
    if display.Background then SkinBase.ClampTextureHidden(display.Background, true) end
    if display.NineSlice then display.NineSlice:SetAlpha(0) end
    if display.GetRegions then
        for i = 1, display:GetNumRegions() do
            local region = select(i, display:GetRegions())
            if region.GetAtlas and region:GetAtlas() == "auctionhouse-itemheaderframe" then
                SkinBase.ClampTextureHidden(region, true)
            end
        end
    end
    local sr, sg, sb, sa, br, bg, bb, ba = SkinBase.GetWindowColors()
    SkinBase.CreateBackdrop(display, sr, sg, sb, sa, br, bg, bb, ba, 5)
    SkinBase.GetBackdrop(display):SetFrameLevel(math.max(0, display:GetFrameLevel() - 1))
    if item.CircleMask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(item.CircleMask) end
    SkinBase.RoundIconTexture(item, icon)
    local border = SkinBase.SkinIcon(icon)
    if border then SkinBase.SetFrameData(border, "chromeRadius", 4) end
    if border then
        local quality
        if display.itemLink and display.GetItemInfo then
            local _, _, nativeQuality = display:GetItemInfo()
            quality = nativeQuality
        end
        local colorData = quality and ColorManager and ColorManager.GetColorDataForItemQuality(quality)
        local color = colorData and colorData.color
        local r, g, b, a = sr, sg, sb, sa
        if color and color.GetRGBA then r, g, b, a = color:GetRGBA() end
        SkinBase.SetBackdropColors(border, { r, g, b, a }, nil)
    end
    if item.IconBorder then SkinBase.ClampTextureHidden(item.IconBorder, true) end
    local highlight = item.GetHighlightTexture and item:GetHighlightTexture()
    if highlight then
        highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        highlight:ClearAllPoints()
        highlight:SetAllPoints(icon)
        highlight:SetVertexColor(sr, sg, sb, 0.15)
        SkinBase.RoundIconTexture(item, highlight)
    end
    SkinBase.SkinFontString(item.Count, { fontOnly = true })
    SkinBase.SkinFontString(display.Name, { fontOnly = true })
end

local function RefreshAuctionItemDisplays()
    local frame = _G.AuctionHouseFrame
    if not frame or not IsEnabled() then return end
    for _, key in ipairs({ "CommoditiesBuyFrame", "ItemBuyFrame", "CommoditiesSellFrame", "ItemSellFrame", "AuctionsFrame", "WoWTokenResults", "WoWTokenSellFrame" }) do
        local panel = frame[key]
        if panel then StyleAuctionItemDisplay((panel.BuyDisplay and panel.BuyDisplay.ItemDisplay) or panel.ItemDisplay or panel.TokenDisplay) end
    end
    for display in pairs(auctionItemDisplays) do StyleAuctionItemDisplay(display) end
end

local function SkinAuctionHouse()
    if not IsEnabled() then return end

    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or SkinBase.IsSkinned(AuctionHouseFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()

    HideAuctionHouseDecorations()

    SkinBase.CreateBackdrop(AuctionHouseFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga, 8)

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
    StyleTokenPanels()
    StyleMultisellProgress(_G.AuctionHouseMultisellProgressFrame)
    LockAuctionHouseBuyDialogText()
    StyleAuctionBuyDialog(AuctionHouseFrame.BuyDialog)

    if SkinBase.SkinIcon and _G.AuctionHouseItemDisplayMixin
        and not SkinBase.GetFrameData(_G.AuctionHouseItemDisplayMixin, "qAHIconHooked") then
        hooksecurefunc(_G.AuctionHouseItemDisplayMixin, "SetItemInternal", StyleAuctionItemDisplay)
        if type(_G.AuctionHouseItemDisplayMixin.Reset) == "function" then
            hooksecurefunc(_G.AuctionHouseItemDisplayMixin, "Reset", StyleAuctionItemDisplay)
        end
        SkinBase.SetFrameData(_G.AuctionHouseItemDisplayMixin, "qAHIconHooked", true)
    end

    RefreshAuctionItemDisplays()
    SkinBase.MarkSkinned(AuctionHouseFrame)
end

local function RefreshAuctionHouseColors()
    local AuctionHouseFrame = _G.AuctionHouseFrame
    if not AuctionHouseFrame or not SkinBase.IsSkinned(AuctionHouseFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetWindowColors()

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
        StyleSellInnerControls(commoditiesSell)
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
        StyleSellInnerControls(itemSell)
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
    StyleTokenPanels()
    StyleMultisellProgress(_G.AuctionHouseMultisellProgressFrame)
    LockAuctionHouseBuyDialogText()
    StyleAuctionBuyDialog(AuctionHouseFrame.BuyDialog)
    StyleCommodityBuyPanel()
    StyleItemBuyPanel()
    RefreshAuctionItemDisplays()
    for row in pairs(auctionRows) do skinRow(row) end
    for list in pairs(auctionLists) do StyleAuctionListControls(list) end
    for header in pairs(auctionHeaders) do StyleAuctionHeader(header) end
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
