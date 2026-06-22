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
    -- Order/recipe/listing rows are TableBuilder rows whose cell fontstrings are
    -- built lazily. LockPooledRowText does the guarded recursive pass once, then
    -- locks the row subtree so the QUI face re-applies on every cell rebind.
    SkinBase.LockPooledRowText(row, 4)
end

-- Order-table column headers (ProfessionsCrafterTableHeaderStringTemplate, a
-- ColumnDisplay button) are pool-built lazily and swap their Highlight font
-- OBJECT on hover. Hook the shared mixin Init once so every header (this window
-- and the crafter ProfessionsFrame, which use the same template) gets the QUI
-- font driven onto its font objects right after Blizzard builds it.
local function HookProfessionTableHeaderFonts()
    local mixin = _G.ProfessionsCrafterTableHeaderStringMixin
    if not mixin or mixin.Init == nil or SkinBase.GetFrameData(mixin, "headerFontHooked") then return end
    hooksecurefunc(mixin, "Init", function(self)
        SkinBase.ApplyButtonFontObjects(self)
    end)
    SkinBase.SetFrameData(mixin, "headerFontHooked", true)
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
            SkinBase.SkinButton(searchBar.FavoritesSearchButton, { font = true })
        end
        -- Filter dropdown (WowStyle1 dropdown — standard button textures don't apply)
        if searchBar.FilterDropdown then
            local dropdown = searchBar.FilterDropdown
            -- WowStyle1FilterDropdownTemplate (a DropdownButton) — route through the
            -- canonical SkinDropdown (default strip), matching every other QUI
            -- dropdown. belowChildren keeps the QUI backdrop below the reset "X".
            SkinBase.SkinDropdown(dropdown, { belowChildren = true })
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
            SkinBase.SkinCategoryButton(button)
            SuppressCategoryTextures(button)
            SkinBase.RefreshCategorySelected(button)
            -- Reapply the QUI font: Blizzard's element initializer calls
            -- SetNormalFontObject on every rebind, reverting the label font.
            -- StyleCategoryRow only re-runs on acquisition/filter-refresh, so
            -- also lock the font object to re-assert on rebinds in between.
            SkinBase.SkinFontString(button.Text)
            SkinBase.LockFontObject(button, { fontOnly = true })
            -- Init's SetNormalFontObject REPLACES the font object SkinCategoryButton
            -- drove once (so the once-guard won't re-drive it). Re-drive here on every
            -- bind so the normal AND hover/disable font objects stay on the QUI face.
            SkinBase.ApplyButtonFontObjects(button)
        end
        local function RefreshCategoryButtons(self)
            SafeForEachFrame(self, StyleCategoryRow)
        end

        SkinBase.HookScrollBoxAcquired(categoryList.ScrollBox, StyleCategoryRow)

        -- The shared element initializer (ProfessionsCustomerOrdersCategoryButtonMixin
        -- :Init) re-asserts the Blizzard nav-button atlas + normalTexture:SetAlpha(1)
        -- + SetNormalFontObject on EVERY bind (initial data load, expand/collapse,
        -- scroll-recycle). Those rebinds DON'T re-fire the acquired-frame callback for
        -- on-screen buttons, so the stock texture/font flashes back. Hook the mixin
        -- once so the QUI suppression + skin re-runs right after Blizzard, same layout
        -- pass — mirrors the AuctionHouseFilterButton_SetUp hook.
        local catMixin = _G.ProfessionsCustomerOrdersCategoryButtonMixin
        if catMixin and catMixin.Init and not SkinBase.GetFrameData(categoryList, "categoryInitHooked") then
            hooksecurefunc(catMixin, "Init", function(self)
                if not IsEnabled() or self.isSpacer then return end
                StyleCategoryRow(self)
            end)
            SkinBase.SetFrameData(categoryList, "categoryInitHooked", true)
        end

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

        -- Canonical thin QUI scrollbar (was a bare Background:Hide() that left the
        -- stock thumb/track/arrows).
        if categoryList.ScrollBar then
            SkinBase.SkinTrimScrollBar(categoryList.ScrollBar)
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
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(form.LeftPanelBackground, sr, sg, sb, sa * 0.3, dr, dg, db, da)
    end

    -- Right panel background
    if form.RightPanelBackground then
        if form.RightPanelBackground.NineSlice then form.RightPanelBackground.NineSlice:Hide() end
        if form.RightPanelBackground.Background then form.RightPanelBackground.Background:SetAlpha(0) end
        local dr, dg, db, da = SkinBase.GetDepthColor("SUBPANEL")
        SkinBase.CreateBackdrop(form.RightPanelBackground, sr, sg, sb, sa * 0.3, dr, dg, db, da)
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
            -- SkinDropdown faces+locks the dropdown text internally (LockDropdownText:
            -- SkinFontString{fontOnly} + LockFontObject + LockFrameTextObjects(dropdown,2)).
            SkinBase.SkinDropdown(pc.DurationDropdown)
        end
        -- Note edit box
        if pc.NoteEditBox then
            SkinBase.SkinEditBox(pc.NoteEditBox, { borderAlpha = 0.5, bgAlpha = 0.8 })
        end
    end

    -- Dropdowns on the form
    -- SkinDropdown already calls LockDropdownText internally, so no post-lock needed.
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
            SkinBase.SkinButton(listings.CloseButton, { font = true })
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

    HookProfessionTableHeaderFonts()
    SkinTabs(frame)
    SkinBrowseOrders(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinMyOrders(frame)
    SkinForm(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

---------------------------------------------------------------------------
-- PANEL COLOR REFRESH (frame-specific, not part of shared widget API)
---------------------------------------------------------------------------

local function UpdatePanelColors(panel, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = panel and SkinBase.GetBackdrop(panel)
    if not bd then return end
    SkinBase.SetBackdropColors(bd, { sr, sg, sb, sa * 0.3 }, { SkinBase.GetDepthColor("SUBPANEL") })
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
        SkinBase.SetBackdropColors(mainBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
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
            SkinBase.RefreshWidget(pc.NoteEditBox)
        end
        -- Current listings
        if form.CurrentListings then
            local listingsBd = SkinBase.GetBackdrop(form.CurrentListings)
            if listingsBd then
                SkinBase.SetBackdropColors(listingsBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
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

SkinBase.OnAddOnLoaded("Blizzard_ProfessionsCustomerOrders", SkinCraftingOrders, 0)
