local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- CRAFTING ORDERS (WORK ORDERS) SKINNING
---------------------------------------------------------------------------

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

-- Style each pooled ScrollBox row as it's acquired (shared by all lists).
local function skinRow(row)
    SkinBase.SkinScrollRow(row)
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

-- Suppress a category button's default textures (safe to call on every refresh;
-- the ScrollBox element initializer restores NormalTexture alpha to 1.0 when
-- it re-binds a button — see ProfessionsCustomerOrdersCategoryButtonMixin:Init).
local function SuppressCategoryTextures(button)
    if not button then return end
    SkinBase.StripTextures(button)
    if button.SelectedTexture then button.SelectedTexture:SetAlpha(0) end
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
end

-- Style a category list button
local function StyleCategoryButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    -- Hide default textures but keep SelectedTexture for state detection (hidden visually)
    SuppressCategoryTextures(button)

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
-- HIDE DECORATIONS
---------------------------------------------------------------------------

local function HideDecorations(frame)
    if not frame then return end
    SkinBase.HidePortraitFrameChrome(frame)

    -- CraftingOrders-specific money frame (not part of PortraitFrameTemplate)
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

local function SkinTabs(frame)
    if not frame then return end
    local tabs = { frame.BrowseTab, frame.OrdersTab }
    SkinBase.SkinTabGroup(tabs, frame, { font = true })
    -- Reposition tabs
    if tabs[1] then
        tabs[1]:ClearAllPoints()
        tabs[1]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -3, -30)
    end
    if tabs[2] and tabs[1] then
        tabs[2]:ClearAllPoints()
        tabs[2]:SetPoint("TOPLEFT", tabs[1], "TOPRIGHT", -5, 0)
    end
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
            SkinBase.SkinEditBox(searchBar.SearchBox, { font = true })
        end
        if searchBar.SearchButton then
            SkinBase.SkinButton(searchBar.SearchButton, { font = true })
        end
        if searchBar.FavoritesSearchButton then
            SkinBase.SkinButton(searchBar.FavoritesSearchButton)
        end
        -- Filter dropdown (WowStyle1 dropdown — standard button textures don't apply)
        if searchBar.FilterDropdown then
            SkinBase.SkinButton(searchBar.FilterDropdown, { strip = true, font = true })
            local dropdown = searchBar.FilterDropdown
            -- Keep the QUI backdrop BELOW the dropdown's children (belowChildren).
            local filterBd = SkinBase.GetBackdrop(dropdown)
            if filterBd then
                filterBd:SetFrameLevel(math.max(0, dropdown:GetFrameLevel() - 1))
            end
            -- The reset "X" (ResetButton) is purely a SHOW/hide issue, not
            -- z-order: it sits well above the backdrop, but Blizzard's
            -- WowDropdownFilterBehaviorMixin:ValidateResetState() only shows it
            -- when a filter is non-default. On a fresh open the dropdown's first
            -- OnShow can run ValidateResetState before InitFilterDropdown wires
            -- the isDefault callback, so an already-active filter's X stays
            -- hidden until the next validate (the menu click). Re-validate once
            -- after skinning so the X reflects the real filter state immediately.
            -- No-op when filters are default (the X correctly stays hidden — it
            -- only appears when there is something to reset).
            if dropdown.ValidateResetState then
                C_Timer.After(0, function() pcall(dropdown.ValidateResetState, dropdown) end)
            end
        end
    end

    -- Category list
    local categoryList = browseOrders.CategoryList
    if categoryList then
        SkinBase.StripTextures(categoryList)
        if categoryList.NineSlice then categoryList.NineSlice:Hide() end
        if categoryList.Background then categoryList.Background:SetAlpha(0) end

        -- Per-button styler (used both on acquisition and by the SetCategoryFilter
        -- refresh). Re-suppress on every call because Blizzard's element
        -- initializer restores NormalTexture alpha when it re-binds a button.
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

        SkinBase.HookScrollBoxAcquired(categoryList.ScrollBox, StyleCategoryRow)

        -- Selecting/deselecting a category invalidates the tree data provider,
        -- which re-runs the element initializer (restoring Blizzard textures) on
        -- buttons that stay on screen WITHOUT re-firing the acquired-frame
        -- callback. Re-suppress all visible buttons afterward, mirroring the
        -- Auction House OnFilterClicked hook.
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

        if categoryList.ScrollBar and categoryList.ScrollBar.Background then
            categoryList.ScrollBar.Background:Hide()
        end
    end

    -- Recipe list
    SkinBase.SkinListContainer(browseOrders.RecipeList, skinRow)
end

---------------------------------------------------------------------------
-- SKIN MY ORDERS PAGE
---------------------------------------------------------------------------

local function SkinMyOrders(frame)
    if not frame then return end

    local myOrders = frame.MyOrdersPage
    if not myOrders then return end

    -- Order list
    SkinBase.SkinListContainer(myOrders.OrderList, skinRow)

    -- Refresh button
    if myOrders.RefreshButton then
        SkinBase.SkinButton(myOrders.RefreshButton, { font = true })
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
        SkinBase.SkinButton(form.BackButton, { font = true })
    end

    -- Payment container
    if form.PaymentContainer then
        local pc = form.PaymentContainer
        if pc.ListOrderButton then
            SkinBase.SkinButton(pc.ListOrderButton, { font = true })
        end
        if pc.CancelOrderButton then
            SkinBase.SkinButton(pc.CancelOrderButton, { font = true })
        end
        -- Duration dropdown
        if pc.DurationDropdown then
            SkinBase.SkinDropdown(pc.DurationDropdown)
        end
        -- Note edit box border (non-standard alphas — NOT migrated to SkinEditBox)
        if pc.NoteEditBox and pc.NoteEditBox.Border then
            pc.NoteEditBox.Border:SetAlpha(0)
            SkinBase.CreateBackdrop(pc.NoteEditBox, sr, sg, sb, sa * 0.5, bgr, bgg, bgb, 0.8)
        end
    end

    -- Dropdowns on the form
    if form.MinimumQuality and form.MinimumQuality.Dropdown then
        SkinBase.SkinDropdown(form.MinimumQuality.Dropdown)
    end
    if form.OrderRecipientDropdown then
        SkinBase.SkinDropdown(form.OrderRecipientDropdown)
    end

    -- Recipient target edit box
    if form.OrderRecipientTarget then
        SkinBase.SkinEditBox(form.OrderRecipientTarget)
    end

    -- Current listings side panel
    if form.CurrentListings then
        local listings = form.CurrentListings
        if listings.NineSlice then listings.NineSlice:Hide() end
        SkinBase.StripTextures(listings)
        SkinBase.CreateBackdrop(listings, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        if listings.OrderList then
            SkinBase.SkinListContainer(listings.OrderList, skinRow)
        end
        if listings.CloseButton then
            SkinBase.SkinButton(listings.CloseButton)
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

    SkinBase.SkinCloseButton(frame.CloseButton or _G.ProfessionsCustomerOrdersFrameCloseButton)

    SkinTabs(frame)
    SkinBrowseOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinMyOrders(frame)
    SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.MarkSkinned(frame)
end

---------------------------------------------------------------------------
-- PANEL COLOR REFRESH (frame-specific, not part of shared widget API)
---------------------------------------------------------------------------

local function UpdatePanelColors(panel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = panel and SkinBase.GetBackdrop(panel)
    if not bd then return end
    bd:SetBackdropColor(math.min(bgr + 0.02, 1), math.min(bgg + 0.02, 1), math.min(bgb + 0.02, 1), 0.5)
    bd:SetBackdropBorderColor(sr, sg, sb, sa * 0.3)
end

---------------------------------------------------------------------------
-- REFRESH COLORS (for live theme changes)
---------------------------------------------------------------------------

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
    SkinBase.RefreshTabGroup({ frame.BrowseTab, frame.OrdersTab }, frame)

    -- Browse page
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

    -- My orders page
    local myOrders = frame.MyOrdersPage
    if myOrders then
        SkinBase.RefreshWidget(myOrders.RefreshButton)
    end

    -- Form
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
            SkinBase.RefreshWidget(form.CurrentListings.CloseButton)
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
